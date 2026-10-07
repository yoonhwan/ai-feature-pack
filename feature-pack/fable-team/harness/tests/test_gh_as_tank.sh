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
dry pr-comment 7 "$T/body.md";                 want "gh pr comment 7 -R SecondWindStudio/byz-agents --body-file $T/body.md" "pr-comment"
dry pr-create "PR제목" "$T/body.md" --base main; want "gh pr create -R SecondWindStudio/byz-agents --title PR제목 --body-file $T/body.md --base main" "pr-create"
[ ! -s "$LOG" ] && ok "dry-run 은 gh 호출 0" || bad "dry-run 인데 gh 호출됨: $(cat "$LOG")"

# ── usage 오류 exit 2 ──
for args in "" "bogus" "comment x $T/body.md" "comment 5 /nonexistent" "label 5" "close 5 --reason weird" "reopen 5 --reason completed"; do
  # shellcheck disable=SC2086
  bash "$WRAP" $args >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage exit 2: [$args]" || bad "usage exit 2 여야 함: [$args]"
done

# ── pr-create --apply 는 거부(권한 미확인) ──
out="$(FT_ISSUE_BOT_TOKEN=$TOKEN bash "$WRAP" pr-create "t" "$T/body.md" --apply 2>&1)"; rc=$?
[ $rc -eq 2 ] && grep -q "권한 미확인" <<<"$out" && [ ! -s "$LOG" ] && ok "pr-create --apply 거부 rc=2" || bad "pr-create --apply → rc=$rc $out"

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

# ── 가드 ──
guard() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "${2:-Bash}" "$1" | bash "$GUARD" >/dev/null 2>"$T/g.err"; return $?; }
block() { guard "$1"; rc=$?; [ $rc -eq 2 ] && grep -q "ft-gh-as-tank.sh" "$T/g.err" && ok "차단: $1" || bad "차단이어야 함(rc=$rc): $1"; }
pass()  { guard "$1" "${2:-Bash}"; rc=$?; [ $rc -eq 0 ] && ok "통과: $1" || bad "통과여야 함(rc=$rc): $1"; }

# 직접 호출 차단
block 'gh issue create --title x --body y'
block 'gh issue comment 5 -b hi'
block 'gh issue edit 5 --add-label x'
block 'gh issue close 5'
block 'gh issue reopen 5'
block 'gh -R o/r issue close 5'
block 'gh issue -R o/r comment 5 -b hi'
block 'gh pr comment 7 -b hi'
block 'gh api repos/o/r/issues/5/comments -f body=x'
block 'gh api -X PATCH repos/o/r/issues/5 -f state=closed'
block 'gh api --method POST repos/o/r/issues/5/labels -f labels[]=x'
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
pass 'gh api repos/o/r/issues/5'
pass 'gh api repos/o/r/issues -X GET -f state=open'
pass 'gh pr create --title x --body y'
pass 'gh pr merge 7 --squash'
pass 'gh pr checkout 7'
pass 'gh pr diff 7'
pass 'gh pr view 7'
pass 'gh api repos/o/r/pulls/7'
# 명령이 아닌 문자열(따옴표·heredoc)·타 도구·비정상 입력
pass 'echo "gh issue close 5"'
pass 'git commit -m "docs: gh issue comment 래퍼 안내"'
pass $'cat > note.md <<\'EOF\'\ngh issue close 5\nEOF'
pass 'git status' Read
pass 'gh issue close 5' Edit
echo 'not json' | bash "$GUARD" >/dev/null 2>&1; [ $? -eq 0 ] && ok "JSON 아님 → fail-open 허용" || bad "JSON 아님 → 허용이어야 함"

echo "fail=$fail"; [ $fail -eq 0 ]
