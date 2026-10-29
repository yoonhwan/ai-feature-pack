#!/usr/bin/env bash
# test_nano_close_landed_pr_root_r1053.sh — r1053: ft-nano-close.sh --landed-pr 의 리포 = 카드 «대상:» 절대경로 0 이면 «카드 읽기 판이 사는 리포» 가 ROOT 일 때만 ROOT
# 임시 git 리포 + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 자기 재호출 0 · 고정 sleep 0 · GIT_* env 0.
# ⓐ R1 대상 줄 0 · 카드 = ROOT 작업 트리 파일 · MERGED → CLOSED + INFO «카드 위치 근거 → ROOT» + gh -R ROOT 1회
#    ⓐ2 같은 입력 · 카드 = ROOT 의 ref 판(임시 파일 · 실사건 꼴 = origin/main 판) → 같음
# ⓑ R2 같은 입력 + OPEN · CLOSED + main 에 산출 없음(r1058: 판정 = origin/main) → REJECT state=… · 닫기 0
# ⓔ R5 카드가 ROOT 밖 다른 리포에 삶 + 대상 줄 0 → REJECT «≠ ROOT» · gh 0
# ⓓ R7 마지막 증거 줄에 «시험:» 칸 없음 + MERGED → 통과(형식 검사 0) · + OPEN → REJECT · R8 --landed-pr 없음 → «형식 불일치» REJECT
# 변이: «ROOT 갈래 끔» → ⓐ FAIL · «카드 리포 대조 끔» → ⓔ FAIL · «착지 판정 끔(r1058: _lp_landed_gate)» → ⓓ OPEN 칸 FAIL
# ③ 기존 갈래(R3 팩·섞임 · R4 카드 없음 · R6 --wt 팩) = test_nano_close_landed_pr_r1011.sh 회귀
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
chmod +x "$T/bin/"* "$T/fake/"*

BYZ_URL='https://github.com/lptest/byz.git'
REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$REPO" remote add origin "$BYZ_URL"; git -C "$REPO" config "url.$REPO.insteadOf" "$BYZ_URL"   # 식별자 = 설정값 · 전송 = 로컬
mkdir -p "$REPO/.fable-team" "$REPO/design/ops/indices/완성" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-ops-nano-lp#0'; BR='nano/lp'; NW="$REPO/.worktrees/v65-lp"
CARD_REL='design/ops/indices/완성/lp.md'; CARD="$REPO/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/web" && echo 'x' > "$NW/web/a.txt"
git -C "$NW" add web/a.txt && git -C "$NW" commit -q -m "work (squash 로 착지한 세트)"
SHA0="$(git -C "$NW" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse main)"
# R5 = 카드가 ROOT 밖 다른 리포에 산다(FT_NANO_LEDGER_WT 후보로만 찾힘)
OTHER="$T/other"; mkdir -p "$OTHER"; git -C "$OTHER" init -q -b main
LEDGER="$T/ledger.md"

card_body() {  # card_body <증거 꼴: ok|no-test> → 대상 줄 0 · «- 착지:» 줄 있음(BYZ 팀 카드 꼴)
  local ev="시험: bash t.sh (3 passed) rc=0 · 이슈: 0"; [ "$1" = ok ] || ev="변이: 헤더 제거 → RED rc=1 · 이슈: 0"
  printf '# 인덱스: lp\n## 상태\n- 2026-10-28 진행\n  - 세트: %s · %s\n- 착지: 346ae185ad821bc64f550913ba18bf8676924a12\n' "$SHA0" "$ev"
}
setup() {  # setup <MERGED|OPEN|CLOSED> [<증거 꼴>]
  git -C "$NW" reset -q --hard "$SHA0"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean" "$OTHER/design"
  card_body "${2:-ok}" > "$CARD"
  local m='null'; [ "$1" != MERGED ] || m="{\"oid\":\"$SHA0\"}"
  printf '{"state":"%s","mergeCommit":%s,"headRefOid":"%s"}\n' "$1" "$m" "$SHA0" > "$T/gh.json"
}
close() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" \
  ${CARD_REF:+FT_CARD_REF="$CARD_REF"} ${LWT:+FT_NANO_LEDGER_WT="$LWT"} \
  FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
}
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh (매번 새 사본)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$1" "$2" <<'PY'
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding='utf-8').read()
assert s.count(a) == 1, f"변이 자리 {s.count(a)}곳: {a}"
open(p, 'w', encoding='utf-8').write(s.replace(a, b))
PY
}
GH1="pr view 363 -R lptest/byz --json state,mergeCommit,headRefOid"

echo "== ⓐ R1 대상 줄 0 · 카드 = ROOT 작업 트리 파일 · MERGED → CLOSED · INFO 카드 위치 근거 → ROOT"
setup MERGED; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "INFO ⑥--landed-pr 카드 위치 근거 → ROOT($REPO" "  └ INFO 카드 위치 근거 → ROOT"
has "$out" "LANDED-PR-OK #363 merged=${SHA0:0:9} state=MERGED head=${SHA0:0:9} repo=lptest/byz" "  └ LANDED-PR-OK repo=ROOT"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "  └ CLOSED-ABSENT"
[ "$(cat "$T/ghlog")" = "$GH1" ] && ok "  └ gh 1회 -R lptest/byz" || bad "ⓐ gh: $(cat "$T/ghlog")"

echo "== ⓐ2 같은 입력 · 카드 = ROOT ref 판(임시 파일) → CLOSED"
setup MERGED
_b="$(git -C "$REPO" hash-object -w "$CARD")"
_t="$(printf '100644 blob %s\tlp.md\n' "$_b" | git -C "$REPO" mktree)"
for _d in 완성 indices ops design; do _t="$(printf '040000 tree %s\t%s\n' "$_t" "$_d" | git -C "$REPO" mktree)"; done
git -C "$REPO" update-ref refs/cardref "$(git -C "$REPO" -c user.email=t@t -c user.name=t commit-tree "$_t" -m card)"
out="$(CARD_REF=refs/cardref close --landed-pr 363)"; rc=$?
has "$out" "INFO 카드 위치 ← refs/cardref:$CARD_REL" "  └ 읽기 판 = ref 판(임시 파일)"
[ "$rc" -eq 0 ] && has "$out" "카드 위치 근거 → ROOT" "ⓐ2 ref 판 → ROOT · rc=0" || bad "ⓐ2 rc=$rc ← ${out:0:900}"

echo "== ⓑ R2 같은 입력 + OPEN · CLOSED + main 에 산출 없음 → REJECT · 닫기 0"
for st in OPEN CLOSED; do
  setup "$st"; out="$(close --landed-pr 363)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "state=$st · main 에 산출 없음" "ⓑ $st → REJECT" || bad "ⓑ $st rc=$rc ← ${out:0:600}"
  untouched "ⓑ $st"
done

echo "== ⓔ R5 카드가 ROOT 밖 리포에 삶 + 대상 줄 0 → REJECT · gh 0"
setup MERGED; mkdir -p "$OTHER/$(dirname "$CARD_REL")"; mv "$CARD" "$OTHER/$CARD_REL"
out="$(LWT="$OTHER" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "카드가 사는 리포 $OTHER ≠ ROOT" "ⓔ ROOT 밖 카드 → REJECT(추측 0)" || bad "ⓔ rc=$rc ← ${out:0:900}"
[ ! -s "$T/ghlog" ] && ok "  └ gh 호출 0" || bad "ⓔ gh: $(cat "$T/ghlog")"
untouched "ⓔ"

echo "== ⓓ R7 증거 줄에 «시험:» 칸 없음 + MERGED → 통과 · + OPEN → REJECT"
setup MERGED no-test; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓓ MERGED → rc=0(형식 검사 면제)" || bad "ⓓ MERGED rc=$rc ← ${out:0:900}"
hasnt "$out" "형식 불일치" "  └ 형식 불일치 0"
setup OPEN no-test; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "state=OPEN" "ⓓ OPEN → REJECT" || bad "ⓓ OPEN rc=$rc ← ${out:0:600}"
untouched "ⓓ OPEN"
echo "== ⓓ R8 같은 카드 · --landed-pr 없음 → «증거 줄 형식 불일치» REJECT"
setup MERGED no-test; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "형식 불일치" "ⓓ R8 → 형식 불일치 REJECT" || bad "ⓓ R8 rc=$rc ← ${out:0:900}"
[ ! -s "$T/ghlog" ] && ok "  └ gh 호출 0" || bad "ⓓ R8 gh: $(cat "$T/ghlog")"

echo "== 변이 «ROOT 갈래 끔» → ⓐ 가 잡는다"
mutant 'if [ -n "$t" ] && [ "$t" = "$nw" ]; then repo="$ROOT"' 'if false; then repo="$ROOT"'
setup MERGED; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "변이(ROOT 갈래 끔) → REJECT = ⓐ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc"
echo "== 변이 «카드 리포 대조 끔» → ⓔ 가 잡는다"
mutant 'if [ -n "$t" ] && [ "$t" = "$nw" ]; then repo="$ROOT"' 'if true; then repo="$ROOT"'
setup MERGED; mkdir -p "$OTHER/$(dirname "$CARD_REL")"; mv "$CARD" "$OTHER/$CARD_REL"
out="$(LWT="$OTHER" CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이(대조 끔) → ROOT 밖 카드가 닫힘 = ⓔ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"
echo "== 변이 «착지 판정 끔(상태 칸과 무관하게 면제)» → ⓓ OPEN 칸이 잡는다"
mutant '  _lp_landed_gate || return 1' '  :'
setup OPEN no-test; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이(착지 판정 끔) → OPEN 카드가 닫힘 = ⓓ OPEN 칸이 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
