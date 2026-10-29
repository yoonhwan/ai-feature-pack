#!/usr/bin/env bash
# test_nano_close_landed_equiv_r1074.sh — r1074(r2): --landed-pr 의 squash 끝줄 head X 가 «지금 PR head» S 와 달라도,
#   «X 이후 가지에 새 내용이 없다» + «가지 내용이 전부 main 에 있다» 면 착지로 인정한다(ccu 4166 실측: 착지 뒤 PR 가지가 main 을 2회 병합 → PR head 교체 → «main 에 산출 없음» 거절).
#   ★r2(arch#173 재판단 · #182378 ②)★ 승인 판정기(ft-approval-equiv) 대신 git 3칸 — ⓐ X 가 S 의 조상 · ⓑ rev-list --first-parent --no-merges X..S = 0 ·
#   ⓒ diff --quiet merge-base(S,origin/main) S = 0. 판정기는 «승인 때 자기 변경 = 지금 자기 변경» 을 봐서 squash 착지 뒤엔 반드시 NOT-EQUIV 가 난다(도구가 다름).
#   ⓐ 후보 찾기 = «PR #<N> (head » 접두 · 끝줄이 «PR #<N> (head <40hex>)» 정확 꼴일 때만 X 추출(_lp_lastline_head)
# 임시 git 리포(ROOT + bare REMOTE) + 가짜 tmux·gh·git(PATH 앞)만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 고정 sleep 0 · GIT_* env 0 · 자기 재호출 0.
# ⓐ R1 ★실제 꼴★ main 에 squash C(끝줄 head X = 트리 A) · 그 뒤 PR 가지가 main 을 2회 병합(main 이 C 를 이미 포함) → CLOSED · INFO «→ PR head … = main 병합 2개뿐 · main 대비 자기 변경 0»
# ⓑ R2 X 뒤 빈 일반 커밋 1개(ⓒ 는 참) → REJECT(ⓑ) · ⓒ R3 손댄 병합(ⓑ 는 참) → REJECT(ⓒ)
# ⓓ R4 끝줄 head = S → 지금처럼 squash 통과 · git 3칸 판정 0회 · ⓔ R5 접두 겹침(PR #44 vs N=4)·본문 가운데 줄 → 후보 0 → REJECT · ⓕ R6 X 가 S 의 조상 아님(가지 갈아엎음) → REJECT(ⓐ)
# 변이: «ⓑ 끔» → R2 를 착지로 오판 · «ⓒ 끔» → R3 를 착지로 오판 = 이 시험이 잡는다
# 짝: bin == kit cmp0 · /bin/bash 3.2 -n · r1058/r1011/r1053 회귀는 이 파일 밖(카드 완료 조건에서 함께 rc0 확인)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

mkdir -p "$T/bin" "$T/fake"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-card-target-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
   "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" \
   "$SRC/ft-approval-equiv.sh" "$SRC/ft_approval_equiv.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
cat "$FAKE_GH_JSON"
EOF
cat > "$T/fake/git" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_GIT_LOG:-}" ] && echo "$*" >> "$FAKE_GIT_LOG"
exec /usr/bin/git "$@"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

BYZ_URL='https://github.com/lptest/byz.git'
ROOT="$T/repo"; mkdir -p "$ROOT"
git -C "$ROOT" init -q -b main && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" remote add origin "$BYZ_URL"
git -C "$ROOT" config "url.$T/remote.git.insteadOf" "$BYZ_URL"   # 식별자 = 설정값(github 꼴) · 전송 = 로컬 bare 리포(네트워크 0)
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git -C "$ROOT" push -q origin main

SEAT='byz-ops-nano-eq#0'; BR='nano/eq'; NW="$ROOT/.worktrees/v65-eq"
CARD_REL='design/ops/indices/진행/eq.md'; CARD="$ROOT/$CARD_REL"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
LEDGER="$T/ledger.md"
INIT="$(git -C "$ROOT" rev-parse main)"

# main 쪽 진행 = plumbing(commit-tree) — ROOT 의 checkout 을 건드리지 않는다 · push 로 가짜 origin/main 을 만든다
main_commit() {  # main_commit <부모 sha> <메시지> [<경로> <내용>] [<트리 sha>] → 새 sha(stdout)
  local base="$1" msg="$2" path="${3:-}" body="${4:-}" fix="${5:-}" tree blob
  tree="${fix:-$(git -C "$ROOT" rev-parse "$base^{tree}")}"
  if [ -n "$path" ]; then
    blob="$(printf '%s\n' "$body" | git -C "$ROOT" hash-object -w --stdin)"
    GIT_INDEX_FILE="$T/idx" git -C "$ROOT" read-tree "$tree"
    GIT_INDEX_FILE="$T/idx" git -C "$ROOT" update-index --add --cacheinfo "100644,$blob,$path"
    tree="$(GIT_INDEX_FILE="$T/idx" git -C "$ROOT" write-tree)"; rm -f "$T/idx"
  fi
  git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$base" -m "$msg"
}
pub() { git -C "$ROOT" push -q --force "$REMOTE" "$1:refs/heads/main" && git -C "$ROOT" fetch -q origin main; }
pr_reset() {  # NW 를 INIT 으로 되돌리고 A(자기 커밋 1 · pr/f.txt) 를 만든다 · 결과 = $A
  git -C "$NW" reset -q --hard "$INIT"; git -C "$NW" clean -qfd
  mkdir -p "$NW/pr" && printf 'f1\n' > "$NW/pr/f.txt"
  git -C "$NW" add pr/f.txt && git -C "$NW" commit -q -m "work f"
  A="$(git -C "$NW" rev-parse HEAD)"
}
sq_head() {  # sq_head <끝줄> [<커밋 sha — 그 트리를 쓴다>] → main 에 squash 커밋 C 를 얹는다(트리 기본 = main 그대로 · R1 은 A 트리 = «main 이 PR 내용을 이미 갖는다»)
  local msg="$1" tree="" c
  if [ -n "${2:-}" ]; then tree="$(git -C "$ROOT" rev-parse "$2^{tree}")"; fi
  c="$(main_commit "$(git -C "$ROOT" rev-parse refs/remotes/origin/main)" "squash 착지

$msg" "" "" "$tree")"; pub "$c"; echo "$c"
}
main_add() { pub "$(main_commit "$(git -C "$ROOT" rev-parse refs/remotes/origin/main)" "$1" "$2" "$3")"; }
merge_main() { git -C "$NW" fetch -q origin main; git -C "$NW" merge -q --no-ff -m "merge main $1" origin/main; }
card_body() {  # card_body [<세트 sha>] — 기본 = A(승인 전 head) · R1 은 S(지금 PR head)로 둬 «카드 세트 대조(r1019)» 를 건너뛰고 이 카드의 3칸만 본다
  printf '# 인덱스: eq\n## 상태\n- 2026-10-28 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n' "${1:-${A:-$INIT}}"
}
setup() {  # setup <MERGED|CLOSED> — main·명부·카드·gh·원장·로그를 «정상(세션 없음 · 미커밋 0)» 으로 리셋(origin/main = INIT)
  git -C "$ROOT" push -q --force "$REMOTE" "$INIT:refs/heads/main" && git -C "$ROOT" fetch -q origin main
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; : > "$T/gitlog"; rm -rf "$T/wtclean"
  card_body > "$CARD"
  printf '{"state":"%s","mergeCommit":null,"headRefOid":"%s"}\n' "$1" "$(git -C "$NW" rev-parse HEAD)" > "$T/gh.json"
}
gh_head() { printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$1" > "$T/gh.json"; }
# R1·R2·R3 공통 골격: main = C(끝줄 head A · 트리 A) → m1 → (필요하면) m2
land_graph() {  # land_graph <2|1> — PR 가지가 main 을 N회 병합한다(병합한 main 이 C 를 포함 = 실제 꼴)
  SQ="$(sq_head "PR #363 (head $A)" "$A")"
  main_add other1 g1.txt 1; merge_main 1
  [ "${1:-1}" = 1 ] && { S="$(git -C "$NW" rev-parse HEAD)"; return 0; }
  main_add other2 g2.txt 2; merge_main 2; S="$(git -C "$NW" rev-parse HEAD)"
}
close() { ( cd "$ROOT" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FAKE_GIT_LOG="${FAKE_GIT_LOG:-}" \
  FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "$1: 브랜치 삭제"
}
closed_ok() {
  jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "$1: 명부에 남음"
  has "$(cat "$LEDGER")" "landed-pr=363" "  └ 원장 닫힘 행 landed-pr=363"
}
mutant() {  # mutant <old> <new> [<old2> <new2> …] → $T/mutbin/ft-nano-close.sh
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; pairs = sys.argv[2:]
s = open(p, encoding='utf-8').read()
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
    s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
}
verdict() {  # verdict <이름> — 변이 실행이 «착지» 로 오판했는가(= 변이 FAIL · 시험이 잡는다)
  case "$1" in *"INFO ⑥--landed-pr 착지 확인"*) ok "$2";; *) bad "$2 — 변이 안 먹음 rc=$3 ← $(printf '%s' "$1" | tail -3)";; esac
}

echo "== ⓐ R1 ★실제 꼴★ C(끝줄 head A · 트리 A) + PR 가지가 main 2회 병합 → CLOSED · INFO «= main 병합 2개뿐 · main 대비 자기 변경 0»"
pr_reset; setup CLOSED; land_graph 2; gh_head "$S"
card_body "$S" > "$CARD"   # 세트 = S → r1019 «세트↔head» 대조는 건너뛴다(head == 세트)
SSH="$(git -C "$ROOT" rev-parse --short "$SQ")"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:800}"
has "$out" "INFO ⑥--landed-pr 착지 확인: squash $SSH · 끝줄 head ${A:0:9} → PR head ${S:0:9} = main 병합 2개뿐 · main 대비 자기 변경 0" "  └ INFO 문구(X → S · 병합 2개뿐 · 자기 변경 0)"
has "$out" "· PR state=CLOSED" "  └ 사유에 PR state=CLOSED"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 자리 = LANDED-PR-OK"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "  └ CLOSED-ABSENT <좌석> landed-pr=<N>"
closed_ok "ⓐ"

echo "== ⓑ R2 X 뒤 빈 일반 커밋 1개(ⓒ 는 참) → REJECT(ⓑ)"
pr_reset; setup CLOSED
SQ="$(sq_head "PR #363 (head $A)" "$A")"; main_add other1 g1.txt 1
git -C "$NW" commit -q --allow-empty -m "빈 커밋(내용 0)"
merge_main 1; S="$(git -C "$NW" rev-parse HEAD)"; gh_head "$S"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓑ rc=1" || bad "ⓑ rc=$rc ← ${out:0:600}"
has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0" "  └ 지금 REJECT 문구 유지"
has "$out" "ⓑ 거짓" "  └ 어느 칸이 거짓인지 = ⓑ"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
untouched "ⓑ"

echo "== ⓒ R3 손댄 병합(ⓑ 는 참 · 병합 커밋이 main 에 없는 줄 추가) → REJECT(ⓒ)"
pr_reset; setup CLOSED
SQ="$(sq_head "PR #363 (head $A)" "$A")"; main_add other1 g1.txt 1
git -C "$NW" fetch -q origin main; git -C "$NW" merge -q --no-ff --no-commit origin/main >/dev/null 2>&1
printf 'f1\n손댐\n' > "$NW/pr/f.txt"; git -C "$NW" add pr/f.txt; git -C "$NW" commit -q -m "merge main 1 (손댐)"
gh_head "$(git -C "$NW" rev-parse HEAD)"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓒ rc=1" || bad "ⓒ rc=$rc ← ${out:0:600}"
has "$out" "main 에 산출 없음" "  └ 손댄 병합 → REJECT"
has "$out" "ⓒ 거짓" "  └ 어느 칸이 거짓인지 = ⓒ"
untouched "ⓒ"

echo "== ⓓ R4 끝줄 head = S → 지금처럼 squash 통과 · git 3칸 판정 0회"
pr_reset; setup CLOSED; sq_head "PR #363 (head $A)" >/dev/null
gh_head "$A"; : > "$T/gitlog"
out="$(FAKE_GIT_LOG="$T/gitlog" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓓ rc=0" || bad "ⓓ rc=$rc ← ${out:0:600}"
has "$out" "INFO ⑥--landed-pr 착지 확인: squash" "  └ 지금 INFO 문구 그대로"
hasnt "$out" "main 대비 자기 변경 0" "  └ 3칸 INFO 줄 0(같은 head 경로)"
grep -q -- "--first-parent" "$T/gitlog" && bad "  └ ⓑ 판정 호출됨" || ok "  └ ⓑ 판정 0회(--first-parent 호출 없음)"
grep -q -- "diff --quiet" "$T/gitlog" && bad "  └ ⓒ 판정 호출됨" || ok "  └ ⓒ 판정 0회(diff --quiet 호출 없음)"

echo "== ⓔ R5 접두 겹침(«PR #44 (head …)» 인데 N=4)·본문 가운데 줄 → 후보 0 → REJECT"
pr_reset; setup CLOSED; sq_head "PR #44 (head $A)" >/dev/null
gh_head "$A"
out="$(close --landed-pr 4)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0)" "ⓔ(접두) 후보 0 → REJECT" || bad "ⓔ(접두) rc=$rc ← ${out:0:600}"
untouched "ⓔ 접두"
setup CLOSED; sq_head "PR #363 (head $A)

본문 마지막 줄" >/dev/null
gh_head "$A"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "ⓔ(가운데) 끝줄 아님 → REJECT" || bad "ⓔ(가운데) rc=$rc ← ${out:0:600}"
untouched "ⓔ 가운데"

echo "== ⓕ R6 X 가 S 의 조상 아님(가지를 INIT 으로 갈아엎음) → REJECT(ⓐ)"
pr_reset; setup CLOSED; sq_head "PR #363 (head $A)" "$A" >/dev/null
git -C "$NW" reset -q --hard "$INIT"; mkdir -p "$NW/pr"; printf 'other\n' > "$NW/pr/x.txt"; git -C "$NW" add pr/x.txt; git -C "$NW" commit -q -m "갈아엎음"
gh_head "$(git -C "$NW" rev-parse HEAD)"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓕ rc=1" || bad "ⓕ rc=$rc ← ${out:0:600}"
has "$out" "ⓐ 거짓" "  └ 어느 칸이 거짓인지 = ⓐ"
untouched "ⓕ"

echo "== 변이 «ⓑ 끔» → R2(빈 일반 커밋)를 착지로 오판한다(변이 FAIL = 이 시험이 잡는다)"
mutant '    if [ -n "$eout" ]; then' '    if false; then'
pr_reset; setup CLOSED
SQ="$(sq_head "PR #363 (head $A)" "$A")"; main_add other1 g1.txt 1
git -C "$NW" commit -q --allow-empty -m "빈 커밋(내용 0)"; merge_main 1; gh_head "$(git -C "$NW" rev-parse HEAD)"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
verdict "$out" "변이(ⓑ 끔) → R2 를 착지로 오판 = 변이 FAIL(테스트가 잡는다)" "$rc"

echo "== 변이 «ⓒ 끔» → R3(손댄 병합)을 착지로 오판한다"
mutant '    if [ "$rc3" -ne 0 ]; then' '    if false; then'
pr_reset; setup CLOSED
SQ="$(sq_head "PR #363 (head $A)" "$A")"; main_add other1 g1.txt 1
git -C "$NW" fetch -q origin main; git -C "$NW" merge -q --no-ff --no-commit origin/main >/dev/null 2>&1
printf 'f1\n손댐\n' > "$NW/pr/f.txt"; git -C "$NW" add pr/f.txt; git -C "$NW" commit -q -m "merge main 1 (손댐)"
gh_head "$(git -C "$NW" rev-parse HEAD)"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
verdict "$out" "변이(ⓒ 끔) → R3 를 착지로 오판 = 변이 FAIL(테스트가 잡는다)" "$rc"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
