#!/usr/bin/env bash
# test_gh_as_tank.sh — ft-gh-as-tank.sh(래퍼) + gh-issue-author-guard.sh(가드) 시험. 실제 GitHub 호출 0 — PATH 맨 앞 가짜 gh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
WRAP="$ROOT/scripts/fable-team-bin/ft-gh-as-tank.sh"
GUARD="$ROOT/scripts/harness-install/fable-team/templates/hooks/gh-issue-author-guard.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"; LOG="$T/gh.log"; : > "$LOG"
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# 가짜 gh: 호출을 로그에 남기고, api user 는 STUB_LOGIN, issue create 는 URL 을 돌려준다.
echo "GH_TOKEN=${GH_TOKEN:-} $*" >> "$STUB_LOG"
case "$1 $2" in
  "api user") echo "${STUB_LOGIN:-byz-tank}";;
  "issue create") echo "https://github.com/o/r/issues/99";;
  "issue view") echo "${STUB_VIEW_JSON-}"; exit "${STUB_VIEW_RC:-0}";;
  "issue edit") echo "https://github.com/SecondWindStudio/byz-agents/issues/${3:-0}";;
  "pr view") echo "${STUB_VIEW_JSON-}"; exit "${STUB_VIEW_RC:-0}";;
  "pr edit") echo "https://github.com/SecondWindStudio/byz-agents/pull/${3:-0}";;
  "pr create") echo "https://github.com/SecondWindStudio/byz-agents/pull/123";;
  "api repos/"*"/branches/"*) [ "${STUB_BRANCH_RC:-0}" = 0 ] || exit 1;;
  "api repos/"*"/pulls/"*) echo "${STUB_PR_AUTHOR:-byz-tank}";;
esac
exit 0
EOF
chmod +x "$T/bin/gh"
cat > "$T/mbox.sh" <<'EOF'
#!/usr/bin/env bash
echo "QUEUED seq=1 stub" ; exit 0
EOF
echo '{"_master":"mgr#1"}' > "$T/seats-issues.json"
echo "본문" > "$T/body.md"
export STUB_LOG="$LOG" PATH="$T/bin:$PATH" FT_ME="seat#0" FT_ISSUES_SEATS="$T/seats-issues.json" FT_MBOX_CMD="$T/mbox.sh"
TOKEN="tok_SECRET_VALUE_123"
# R102: close(completed) 는 게이트를 먼저 탄다 — 7·8항이 채워진 상태 파일을 주입해 기존 기대값을 그대로 둔다(게이트 자체는 test_issue_close_gate.sh)
echo '{"number":5,"state":"OPEN","title":"x","labels":[],"closedByPullRequestsReferences":[],"comments":[{"body":"원인 확정: Y — 시험 입력 근거 열 글자 이상\n같은 증상 보류: 0"}]}' > "$T/gate-pass.json"; export FT_CLOSE_CHECK_FROM_JSON="$T/gate-pass.json"

bash -n "$WRAP" && ok "bash -n 래퍼" || bad "bash -n 래퍼"
bash -n "$GUARD" && ok "bash -n 가드" || bad "bash -n 가드"

# ── 래퍼 dry-run: 5동작 + PR 2종 명령 출력 · gh 호출 0 ──
dry() { out="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" "$@" 2>&1)"; rc=$?; }
want() { [ $rc -eq 0 ] && grep -qF -- "$1" <<<"$out" && ok "dry-run $2" || bad "dry-run $2 → rc=$rc $out"; }
dry create "제목" "$T/body.md";                 want "DRY gh issue create --title '제목'" "create"
dry comment 5 "$T/body.md";                    want "gh issue comment 5 -R SecondWindStudio/byz-agents --body-file $T/body.md" "comment"
dry label 5 --add harness,bug --remove wip;    want "gh issue edit 5 -R SecondWindStudio/byz-agents --add-label harness,bug --remove-label wip" "label"
dry close 5 --comment "$T/body.md" --reason not-planned; want "gh issue close 5 -R SecondWindStudio/byz-agents --reason not planned --comment <$T/body.md>" "close"
dry reopen 5;                                  want "gh issue reopen 5 -R SecondWindStudio/byz-agents" "reopen"
dry edit 5 --title 새제목;                       want "gh issue edit 5 -R SecondWindStudio/byz-agents --title 새제목" "edit 제목만"
dry edit 5 --body-file "$T/body.md";           want "gh issue edit 5 -R SecondWindStudio/byz-agents --body-file $T/body.md" "edit 본문만"
dry edit 5 --title 새제목 --body-file "$T/body.md"; want "gh issue edit 5 -R SecondWindStudio/byz-agents --title 새제목 --body-file $T/body.md" "edit 둘 다"
dry pr-comment 7 "$T/body.md";                 want "gh pr comment 7 -R SecondWindStudio/byz-agents --body-file $T/body.md" "pr-comment"
dry pr-create "PR제목" "$T/body.md" --base main; want "gh pr create -R SecondWindStudio/byz-agents --title PR제목 --body-file $T/body.md --base main" "pr-create"
dry pr-edit 5 --title 새제목;                    want "gh pr edit 5 -R SecondWindStudio/byz-agents --title 새제목" "pr-edit 제목만"
dry pr-edit 5 --body-file "$T/body.md";        want "gh pr edit 5 -R SecondWindStudio/byz-agents --body-file $T/body.md" "pr-edit 본문만"
dry pr-edit 5 --title 새제목 --body-file "$T/body.md"; want "gh pr edit 5 -R SecondWindStudio/byz-agents --title 새제목 --body-file $T/body.md" "pr-edit 둘 다"
dry pr-close 5 --comment "$T/body.md";          want "gh pr close 5 -R SecondWindStudio/byz-agents --comment <$T/body.md>" "pr-close 코멘트 있음"
dry pr-close 5;                                want "gh pr close 5 -R SecondWindStudio/byz-agents" "pr-close 코멘트 없음"
dry pr-create "PR제목" "$T/body.md";           want "gh pr create -R SecondWindStudio/byz-agents --title PR제목 --body-file $T/body.md" "pr-create (--base/--head 생략)"
dry pr-create "PR제목" "$T/body.md" --base dev --head feat/x; want "--base dev --head feat/x" "pr-create (dry-run 은 base 검사 안 함)"
[ ! -s "$LOG" ] && ok "dry-run 은 gh 호출 0" || bad "dry-run 인데 gh 호출됨: $(cat "$LOG")"

# ── usage 오류 exit 2 ──
for args in "" "bogus" "comment x $T/body.md" "comment 5 /nonexistent" "label 5" "close 5 --reason weird" "reopen 5 --reason completed" \
  "edit 5" "edit x --title t" "edit 5 --body-file /nonexistent" "edit 5 --title t --bogus" "edit 5 --title t --body-file" \
  "pr-edit 5" "pr-edit x --title t" "pr-edit 5 --body-file /nonexistent" "pr-close x" "pr-close 5 --comment /nonexistent" "pr-close 5 --bogus"; do
  # shellcheck disable=SC2086
  bash "$WRAP" $args >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage exit 2: [$args]" || bad "usage exit 2 여야 함: [$args]"
done

# ── pr-create --apply: base main 고정 · head 필수 · 원격 head 실재 · 작성자 확인 ──
pcr() { out="$(FT_ISSUE_BOT_TOKEN=$TOKEN "$@" bash "$WRAP" pr-create "t" "$T/body.md" "${PC_ARGS[@]}" --apply 2>&1)"; rc=$?; }
nocreate() { grep -q "pr create" "$LOG" && bad "PR 생성이 호출됨: $1" || ok "PR 생성 호출 0: $1"; }
: > "$LOG"
PC_ARGS=(--base dev --head feat/x); pcr env;  [ $rc -eq 2 ] && ok "pr-create --apply --base dev → rc=2" || bad "--base dev → rc=$rc $out"; nocreate "base dev"
PC_ARGS=(--base main);              pcr env;  [ $rc -eq 2 ] && ok "pr-create --apply head 없음 → rc=2" || bad "head 없음 → rc=$rc $out"; nocreate "head 없음"
PC_ARGS=(--head feat/x);            pcr env;  [ $rc -eq 2 ] && ok "pr-create --apply base 없음 → rc=2" || bad "base 없음 → rc=$rc $out"; nocreate "base 없음"
PC_ARGS=(--base main --head feat/x)
pcr env STUB_BRANCH_RC=1; [ $rc -eq 1 ] && grep -q "head 브랜치가 없다" <<<"$out" && ok "원격 head 없음 → rc=1" || bad "원격 head 없음 → rc=$rc $out"; nocreate "원격 head 없음"
pcr env STUB_PR_AUTHOR=yoonhwan; [ $rc -eq 1 ] && grep -q "작성자=yoonhwan" <<<"$out" && grep -q "pull/123" <<<"$out" && ok "작성자 불일치 → rc=1 · URL 출력" || bad "작성자 불일치 → rc=$rc $out"
: > "$LOG"
pcr env; [ $rc -eq 0 ] && grep -q "OK as=byz-tank pr-create 123 — https://github.com/SecondWindStudio/byz-agents/pull/123" <<<"$out" && ! grep -qF "$TOKEN" <<<"$out" && ok "pr-create --apply 성공 rc=0 · 토큰 미출력" || bad "pr-create --apply 성공 → rc=$rc $out"
grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -qF "pr create -R SecondWindStudio/byz-agents --title t --body-file $T/body.md --base main --head feat/x" && ok "gh pr create + Tank 토큰" || bad "gh pr create 누락: $(cat "$LOG")"
grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -qF "api repos/SecondWindStudio/byz-agents/branches/feat/x" && ok "생성 전 원격 head 조회" || bad "원격 head 조회 누락"
: > "$LOG"

# ── 토큰 없음 rc=2 (오빠 로그인 폴백 0 — gh 호출 0) ──
for args in "comment 5 $T/body.md" "label 5 --add x" "close 5" "reopen 5" "pr-comment 7 $T/body.md" "create 제목 $T/body.md"; do
  # shellcheck disable=SC2086
  out="$(env -u FT_ISSUE_BOT_TOKEN FT_ISSUE_BOT_TOKEN_FILE=/nonexistent bash "$WRAP" $args --apply 2>&1)"; rc=$?
  [ $rc -eq 2 ] && grep -q "봇 토큰 없음" <<<"$out" && ok "토큰 없음 rc=2: ${args%% *}" || bad "토큰 없음 rc=2 여야 함: $args → rc=$rc $out"
done
[ ! -s "$LOG" ] && ok "토큰 없음 경로 gh 호출 0" || bad "토큰 없음인데 gh 호출됨"

# ── 작성자 불일치 REJECT (쓰기 gh 0건) ──
out="$(STUB_LOGIN=yoonhwan FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" comment 5 "$T/body.md" --apply 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "REJECT 토큰 주인이 byz-tank 가 아니다(주인=yoonhwan)" <<<"$out" && ok "작성자 불일치 REJECT rc=1" || bad "작성자 불일치 → rc=$rc $out"
grep -q "issue comment" "$LOG" && bad "작성자 불일치인데 쓰기 gh 실행됨" || ok "작성자 불일치 시 쓰기 gh 0건"

# ── --apply 성공(가짜 gh): Tank 토큰으로 실행 · 토큰 값 미출력 ──
: > "$LOG"
for args in "comment 5 $T/body.md" "label 5 --add x" "close 5 --comment $T/body.md" "reopen 5" "pr-comment 7 $T/body.md" "create 제목 $T/body.md"; do
  # shellcheck disable=SC2086
  out="$(FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" $args --apply 2>&1)"; rc=$?
  [ $rc -eq 0 ] && ! grep -qF "$TOKEN" <<<"$out" && ok "apply ${args%% *} rc=0 · 토큰 미출력" || bad "apply $args → rc=$rc $out"
done
for pat in "issue comment 5" "issue edit 5 -R SecondWindStudio/byz-agents --add-label x" "issue close 5" "issue reopen 5" "pr comment 7" "issue create --title 제목"; do
  grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -qF "$pat" && ok "gh 실행 + Tank 토큰: $pat" || bad "gh 실행 누락: $pat"
done
grep -F "issue create" "$LOG" | grep -q "ft-origin" && bad "로그에 본문 마커?" || ok "create = 쌍 스크립트 경유(PAIR)"

bash "$WRAP" edit 5 --title "" >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage exit 2: edit --title 빈 문자열" || bad "edit --title '' → exit 2 여야 함"

# ── edit --apply: 수정 전 원문 보관(제목·본문) → 그 뒤에만 gh issue edit ──
BAK="$T/bak"; export STUB_VIEW_JSON='{"title":"옛 제목","body":"옛 본문\n둘째줄"}'
eapply() { out="$(FT_ISSUE_BOT_TOKEN=$TOKEN FT_ISSUE_EDIT_BAK_DIR="$BAK" bash "$WRAP" edit 5 "$@" --apply 2>&1)"; rc=$?; }
: > "$LOG"
eapply --title 새제목 --body-file "$T/body.md"
[ $rc -eq 0 ] && ok "edit --apply 성공 rc=0" || bad "edit --apply → rc=$rc $out"
! grep -qF "$TOKEN" <<<"$out" && ok "edit 출력에 토큰 없음" || bad "edit 출력에 토큰 노출"
BB="$(ls "$BAK"/5-*.body.md 2>/dev/null | head -1)"; BT="${BB%.body.md}.title.txt"
[ -f "$BB" ] && [ -f "$BT" ] && ok "보관 두 파일 실재(.body.md · .title.txt)" || bad "보관 파일 없음: $(ls "$BAK" 2>&1)"
[ "$(cat "$BB")" = "$(printf '옛 본문\n둘째줄')" ] && ok "보관 본문 = 수정 전 본문" || bad "보관 본문 불일치: $(cat "$BB")"
[ "$(cat "$BT")" = "옛 제목" ] && ok "보관 제목 = 수정 전 제목" || bad "보관 제목 불일치: $(cat "$BT")"
grep -q "bak=$BB" <<<"$out" && ok "성공 출력 끝에 bak=<본문 경로>" || bad "bak= 누락: $out"
grep -qF "edit 5 --body-file $BB --title \"\$(cat $BT)\" --apply" <<<"$out" && ok "되돌림 명령 1줄 출력" || bad "되돌림 줄 누락: $out"
VN="$(grep -n "issue view 5" "$LOG" | head -1 | cut -d: -f1)"; EN="$(grep -n "issue edit 5 -R SecondWindStudio/byz-agents --title 새제목 --body-file" "$LOG" | head -1 | cut -d: -f1)"
[ -n "$VN" ] && [ -n "$EN" ] && [ "$VN" -lt "$EN" ] && ok "issue view 가 issue edit 보다 먼저" || bad "호출 순서 이상 view=$VN edit=$EN"
grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -qF "issue view 5" && ok "view 도 Tank 토큰" || bad "view 토큰 누락"
# 보관 실패 3종 → rc=1 · 수정 시도 0
: > "$LOG"; STUB_VIEW_RC=1 eapply --title t; [ $rc -eq 1 ] && ok "view 실패 → rc=1" || bad "view 실패 → rc=$rc $out"
grep -q "issue edit" "$LOG" && bad "view 실패인데 issue edit 호출됨" || ok "view 실패 시 issue edit 0건"
: > "$LOG"; STUB_VIEW_JSON="" eapply --title t; [ $rc -eq 1 ] && ok "view 빈 응답 → rc=1" || bad "빈 응답 → rc=$rc $out"
grep -q "issue edit" "$LOG" && bad "빈 응답인데 issue edit 호출됨" || ok "빈 응답 시 issue edit 0건"
: > "$LOG"; touch "$T/notadir"; out="$(FT_ISSUE_BOT_TOKEN=$TOKEN FT_ISSUE_EDIT_BAK_DIR="$T/notadir" bash "$WRAP" edit 5 --title t --apply 2>&1)"; rc=$?
[ $rc -eq 1 ] && ok "보관 쓰기 실패 → rc=1" || bad "보관 쓰기 실패 → rc=$rc $out"
grep -q "issue edit" "$LOG" && bad "보관 실패인데 issue edit 호출됨" || ok "보관 실패 시 issue edit 0건"
# 토큰 주인 불일치 → rc=1 · view·edit 0건
: > "$LOG"; out="$(STUB_LOGIN=yoonhwan FT_ISSUE_BOT_TOKEN=$TOKEN FT_ISSUE_EDIT_BAK_DIR="$BAK" bash "$WRAP" edit 5 --title t --apply 2>&1)"; rc=$?
[ $rc -eq 1 ] && grep -q "주인=yoonhwan" <<<"$out" && ok "edit 토큰 주인 불일치 → rc=1" || bad "주인 불일치 → rc=$rc $out"
grep -qE "issue (view|edit)" "$LOG" && bad "주인 불일치인데 view/edit 호출됨" || ok "주인 불일치 시 view·edit 0건"
# ── pr-edit --apply: 보관(pr<번호>-…) → 그 뒤에만 gh pr edit · 보관 실패면 pr edit 0건 ──
PRBAK="$T/prbak"
pe() { out="$(FT_ISSUE_BOT_TOKEN=$TOKEN FT_ISSUE_EDIT_BAK_DIR="$PRBAK" bash "$WRAP" pr-edit 5 "$@" --apply 2>&1)"; rc=$?; }
: > "$LOG"; pe --title 새제목 --body-file "$T/body.md"
[ $rc -eq 0 ] && ok "pr-edit --apply 성공 rc=0" || bad "pr-edit --apply → rc=$rc $out"
PB="$(ls "$PRBAK"/pr5-*.body.md 2>/dev/null | head -1)"; PT="${PB%.body.md}.title.txt"
[ -f "$PB" ] && [ -f "$PT" ] && [ "$(cat "$PT")" = "옛 제목" ] && ok "pr-edit 보관 pr5-*.body.md·.title.txt" || bad "pr-edit 보관 이상: $(ls "$PRBAK" 2>&1)"
grep -q "bak=$PB" <<<"$out" && grep -qF "ft-gh-as-tank.sh pr-edit 5 --body-file $PB" <<<"$out" && ok "pr-edit bak= + 되돌림 1줄" || bad "pr-edit bak/되돌림 누락: $out"
PV="$(grep -n "pr view 5" "$LOG" | head -1 | cut -d: -f1)"; PE="$(grep -n "pr edit 5 -R SecondWindStudio/byz-agents --title 새제목" "$LOG" | head -1 | cut -d: -f1)"
[ -n "$PV" ] && [ -n "$PE" ] && [ "$PV" -lt "$PE" ] && ok "pr view 가 pr edit 보다 먼저" || bad "pr 호출 순서 이상 view=$PV edit=$PE"
: > "$LOG"; STUB_VIEW_RC=1 pe --title t; [ $rc -eq 1 ] && ok "pr-edit view 실패 → rc=1" || bad "pr-edit view 실패 → rc=$rc $out"
grep -q "pr edit" "$LOG" && bad "pr-edit 보관 실패인데 pr edit 호출됨" || ok "pr-edit 보관 실패 시 pr edit 0건"
# pr-close --apply: 파일 내용이 --comment 문자열로 나간다
: > "$LOG"; out="$(FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" pr-close 5 --comment "$T/body.md" --apply 2>&1)"; rc=$?
[ $rc -eq 0 ] && grep -F "GH_TOKEN=$TOKEN" "$LOG" | grep -qF "pr close 5 -R SecondWindStudio/byz-agents --comment 본문" && ok "pr-close --apply: 파일 내용 --comment + Tank 토큰" || bad "pr-close apply → rc=$rc $out · $(cat "$LOG")"
unset STUB_VIEW_JSON

# ── 가드 ──
# 임시 git 리포(원격만 지정 · 네트워크 0): SWS = SecondWindStudio 원격 · OTHER = 다른 owner · NOGIT = git 아님
SWS="$T/sws"; OTHER="$T/other"; NOGIT="$T/nogit"; mkdir "$SWS" "$OTHER" "$NOGIT"
git -C "$SWS" init -q && git -C "$SWS" remote add origin https://github.com/SecondWindStudio/byz-agents.git
git -C "$OTHER" init -q && git -C "$OTHER" remote add origin git@github.com:yoonhwan/x.git
git -C "$SWS" remote add upstream git@github.com:yoonhwan/y.git
OWN=SecondWindStudio/byz-agents
# guard <명령> <tool> <cwd> — cwd 빈 값이면 훅 입력에 cwd 키 없음
guard() { python3 -c 'import json,sys
d={"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}
if sys.argv[3]: d["cwd"]=sys.argv[3]
print(json.dumps(d))' "${2:-Bash}" "$1" "${3-$SWS}" | bash "$GUARD" >/dev/null 2>"$T/g.err"; return $?; }
block() { guard "$1"; rc=$?; [ $rc -eq 2 ] && grep -q "ft-gh-as-tank.sh" "$T/g.err" && ok "차단: $1" || bad "차단이어야 함(rc=$rc): $1"; }
pass()  { guard "$1" "${2:-Bash}"; rc=$?; [ $rc -eq 0 ] && ok "통과: $1" || bad "통과여야 함(rc=$rc): $1"; }
# rc_is <기대 rc> <cwd> <명령> <라벨> — cwd 에 따른 리포 범위 시험
rc_is() { guard "$3" Bash "$2"; rc=$?; [ $rc -eq "$1" ] && ok "rc=$1 [$4]: $3" || bad "rc=$1 여야 함(실제 $rc) [$4]: $3"; }
mblock() { rc_is 2 "$SWS" "$1" main; grep -q "main 삭제·재작성(강제 push·리베이스 후 강제)은 금지 — 오빠 10-07" "$T/g.err" && ok "main 차단 메시지: $1" || bad "main 차단 메시지 누락: $1"; }
mpass()  { rc_is 0 "$SWS" "$1" main; }

# 직접 호출 차단
block 'gh issue create --title x --body y'
block 'gh issue comment 5 -b hi'
block 'gh issue edit 5 --add-label x'
block 'gh issue edit 5 --body x'
block 'gh issue close 5'
block 'gh issue reopen 5'
block "gh -R $OWN issue close 5"
block "gh issue -R $OWN comment 5 -b hi"
block 'gh pr comment 7 -b hi'
block 'gh pr review 5 --approve'
block 'gh pr review 5 --comment -b x'
block 'gh pr close 5 -c bye'
block 'gh pr edit 5 --body x'
block 'gh pr edit 5 --title t'
block "gh api -X PATCH repos/$OWN/pulls/5 -f body=x"
block "gh api repos/$OWN/pulls/5/comments -f body=x"
block "gh api graphql -f query='mutation { x }'"
block "gh api repos/$OWN/issues/5/comments -f body=x"
block "gh api -X PATCH repos/$OWN/issues/5 -f state=closed"
block "gh api --method POST repos/$OWN/issues/5/labels -f labels[]=x"
block 'GH_TOKEN=abc gh issue close 5'
block '/opt/homebrew/bin/gh issue close 5'
block 'bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 5 f --apply; gh issue close 5'
block 'echo ok && gh issue comment 5 -b hi'
block $'echo start\ngh issue close 5'
block 'bash -c "gh issue close 5"'
block 'eval "gh issue create --title x"'
# 래퍼 경유 통과
pass 'bash scripts/fable-team-bin/ft-gh-as-tank.sh comment 5 body.md --apply'
pass 'bash scripts/fable-team-bin/ft-gh-as-tank.sh create "gh 제목" body.md --apply'
pass 'bash scripts/fable-team-bin/ft-issue-create-pair.sh "제목" body.md --apply'
pass 'bash scripts/fable-team-bin/ft-gh-as-tank.sh pr-comment 7 body.md'
# 조회·PR 비코멘트 통과
pass 'gh issue view 5'
pass 'gh issue list --label x'
pass 'gh issue status'
pass "gh api repos/$OWN/issues/5"
pass "gh api repos/$OWN/issues -X GET -f state=open"
pass 'gh pr create --title x --body y'
pass 'gh pr merge 7 --squash'
pass 'gh pr checkout 7'
pass 'gh pr diff 7'
pass 'gh pr view 7'
pass "gh api repos/$OWN/pulls/7"
pass 'gh pr close 5'
pass 'gh pr edit 5 --add-label x'
pass 'gh pr review 5'
pass "gh api graphql -f query='query { x }'"
rc_is 0 "$SWS" 'gh pr edit 5 --body x -R yoonhwan/p' "개인 리포 PR edit"
# 명령이 아닌 문자열(따옴표·heredoc)·타 도구·비정상 입력
pass 'echo "gh issue close 5"'
pass 'git commit -m "docs: gh issue comment 래퍼 안내"'
pass $'cat > note.md <<\'EOF\'\ngh issue close 5\nEOF'
pass 'git status' Read
pass 'gh issue close 5' Edit
echo 'not json' | bash "$GUARD" >/dev/null 2>&1; [ $? -eq 0 ] && ok "JSON 아님 → fail-open 허용" || bad "JSON 아님 → 허용이어야 함"

# ── 리포 범위: 대상 owner 가 SecondWindStudio 일 때만 차단 · 판정 불가 = 통과 ──
rc_is 2 "$SWS"   'gh issue comment 5 -b hi'                                        "범위ⓐ cwd=SWS"
rc_is 0 "$OTHER" 'gh issue comment 5 -b hi'                                        "범위ⓑ cwd=다른 owner"
rc_is 0 "$NOGIT" 'gh issue comment 5 -b hi'                                        "범위ⓒ cwd=git 아님"
rc_is 0 ""       'gh issue comment 5 -b hi'                                        "범위ⓒ' cwd 키 없음"
rc_is 2 "$OTHER" "gh issue comment 5 -R SecondWindStudio/byz-agents -b hi"         "범위ⓓ cwd 다른 owner + -R SWS"
rc_is 2 "$OTHER" "gh issue comment 5 -R secondwindstudio/byz-agents -b hi"         "범위ⓓ' owner 대소문자 무시"
rc_is 0 "$SWS"   "gh issue comment 5 -R yoonhwan/x -b hi"                          "범위ⓔ cwd SWS + -R 다른 owner"
rc_is 2 "$OTHER" "GH_REPO=SecondWindStudio/byz-agents gh issue comment 5 -b hi"    "범위ⓕ GH_REPO=SWS (cwd 다른 owner)"
rc_is 0 "$SWS"   "gh api repos/yoonhwan/x/issues/1/comments -f body=y"             "범위ⓖ api 경로 다른 owner (cwd SWS)"
rc_is 2 "$OTHER" "gh api repos/SecondWindStudio/byz-agents/issues/1/comments -f body=y" "범위ⓖ' api 경로 SWS (cwd 다른 owner)"
rc_is 0 "$SWS"   "gh pr comment 7 --repo yoonhwan/x -b hi"                         "범위 --repo 다른 owner"

# ── main 보호 (cwd=SWS): 차단 2 ──
mblock 'git push origin :main'
mblock 'git push origin +main'
mblock 'git push origin +HEAD:main'
mblock 'git push origin --delete main'
mblock 'git push origin -d refs/heads/main'
mblock 'git push --mirror origin'
mblock 'git push --prune origin'
mblock 'git push origin main -f'
mblock "git -C $SWS push origin :refs/heads/main"
mblock 'git push https://github.com/SecondWindStudio/byz-agents.git +main'
mblock "gh api -X DELETE repos/$OWN/git/refs/heads/main"
mblock "gh api --method PATCH repos/$OWN/git/refs/heads/main -F force=true"
mblock "gh api -X DELETE repos/$OWN/branches/main/protection"
mblock "gh repo delete $OWN --yes"
# main 보호: 통과 0
mpass 'git push origin main'
mpass 'git push origin HEAD:main'
mpass 'git push'
mpass 'git push origin --delete feat/x'
mpass 'git push origin :feat/x'
mpass 'git push origin +feat/x'
mpass 'git push -u origin feat/main'
mpass "gh api -X DELETE repos/$OWN/git/refs/heads/feat/x"
mpass "gh api -X PATCH repos/$OWN/branches/feature"
mpass "gh api repos/$OWN/branches/main"
rc_is 0 "$OTHER" 'git push origin :main'                       "main 보호 cwd 다른 owner"
rc_is 0 "$OTHER" 'git push origin --delete main'               "main 보호 cwd 다른 owner(--delete)"
rc_is 0 "$NOGIT" 'git push origin :main'                       "main 보호 cwd git 아님 → 판정 불가 통과"
rc_is 2 "$OTHER" 'git push https://github.com/SecondWindStudio/byz-agents.git :main' "main 보호 원격 URL SWS (cwd 다른 owner)"
rc_is 0 "$SWS"   'git push upstream :main'                     "main 보호 원격 이름 → 다른 owner"
rc_is 0 "$SWS"   "gh repo delete yoonhwan/x --yes"             "repo delete 다른 owner"
rc_is 0 "$SWS"   'git status'                                  "git 비 push"

echo "fail=$fail"; [ $fail -eq 0 ]
