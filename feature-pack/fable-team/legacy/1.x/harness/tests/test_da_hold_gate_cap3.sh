#!/usr/bin/env bash
# test_da_hold_gate_cap3.sh — r1042: 판정기 상한 CAP = 3(문서 r1038 «DA 기본 3회» 와 같은 숫자).
#   새 칸만 둔다 — 옛 상한 2 기대 칸은 test_da_hold_gate.sh·test_da_hold_gate_landed.sh 가 3 으로 고쳐 들고 있다.
#   전부 mktemp — 임시 카드·가짜 명부·가짜 우편함. 실 카드·실 큐·홈 쓰기 0 · 자기 자신을 다시 부르지 않는다.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; GATE="$KIT/ft_da_hold_gate.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/design/alpha/indices/진행" "$T/s" "$T/c" "$T/mut"; git -C "$T" init -q
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { { [ "$5" = "$2" ] && [[ "$4" == *"$3"* ]]; } && ok "$1" || bad "$1 → rc=$5 $4"; }
M='byz-alpha-master-claude#1'; A='byz-alpha-arch-claude#3'
printf '{"_master":"%s","_arch":"%s"}\n' "$M" "$A" > "$T/s/seats-alpha.json"
rec() { python3 -c 'import json,sys;print(json.dumps({"seq":int(sys.argv[1]),"from":sys.argv[2],"to":sys.argv[3],"body":sys.argv[4]},ensure_ascii=False))' "$@" >> "$T/c/mailbox.log.jsonl"; }
H2() { printf '%s\n' '- DA② r1 HOLD 1' '- DA② r2 HOLD 1'; }
H3() { H2; echo '- DA⑥ r1 HOLD 2'; }
# card <이름> <상태 줄…> — CARD 를 그 이름으로 옮긴다(해제 쪽지 머리는 카드 «파일 이름» 으로 본다)
card() { local n="$1"; shift; CARD="$T/design/alpha/indices/진행/$n.md"
  { echo "# 인덱스: $n"; echo "## 배경"; echo "x"; echo "## 상태"; printf '%s\n' "$@"; } > "$CARD"; }
g() { python3 "$GATE" "$CARD" --seats-dir "$T/s" --comm "$T/c" "$@" 2>&1; }

# ── 0. 상수 하나 · 두 사본 동일 · 문법 ──
cmp -s "$BIN/ft_da_hold_gate.py" "$GATE" && ok "두 사본 cmp0" || bad "두 사본 불일치"
[ "$(grep -c '^CAP = 3' "$GATE")" = 1 ] && ok "상한 상수 CAP = 3 한 곳" || bad "CAP = 3 상수 $(grep -c '^CAP = 3' "$GATE")곳"
grep -qE 'budget = 2 -|>= 2 and not valid|< 2 else' "$GATE" && bad "옛 하드코딩 2 가 남았다" || ok "옛 하드코딩 2 잔재 0"
ruff check "$GATE" >/dev/null 2>&1 && ok "ruff ft_da_hold_gate.py" || bad "ruff"

# ── 1. R1 사건 0·1·2 → 입장 통과(rc0) · 예산 = CAP − 사건 ──
card c0 '- base_sha: x' '- DA② r1 발주'; o="$(g --entry ② r1)"; chk "R1 사건 0 → budget_left=3" 0 "events=0 reviews=1 releases=0/0 budget_left=3" "$o" $?
card c1 '- DA② r1 HOLD 4' '- DA② r1 발주'; o="$(g --entry ② r1)"; chk "R1 사건 1 → budget_left=2" 0 "events=1 reviews=2 releases=0/0 budget_left=2" "$o" $?
card c2 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA② r3 발주'
o="$(g --entry ② r3)"; chk "R1 사건 2 → 입장 rc0 (상한 2 였다면 rc3)" 0 "events=2 reviews=3 releases=0/0 budget_left=1" "$o" $?

# ── 2. R2 사건 3 + 유효 해제 0 → 입장 막음(rc3) ──
card c3 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "R2 사건 3 · 해제 0 → rc3 budget_left=0" 3 "events=3 reviews=4 releases=0/0 budget_left=0" "$o" $?

# ── 3. R3 사건 3 + 미소진 유효 해제 1 → 입장 1회(rc0) ──
rec 8801 "$M" "$A" '[재설계 해제 c4.md] 해제=1 · 새 범위 설계 §7 · DESIGN r3'
card c4 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2' '- 재설계 해제: #8801' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "R3 사건 3 + 해제 1 → rc0 budget_left=1" 0 "releases=1/0 budget_left=1" "$o" $?

# ── 4. R4 --closing: 사건 2 + APPROVE → 통과 · 사건 3 + 해제 0 → 막음 ──
card c5 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA② r3 CLOSE APPROVE'
o="$(g --closing)"; chk "R4 closing 사건 2 + APPROVE → rc0" 0 "events=2 reviews=3" "$o" $?
card c6 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2' '- DA⑥ r2 CLOSE APPROVE'
o="$(g --closing)"; chk "R4 closing 사건 3 + 해제 0 → rc3" 3 "events=3 reviews=4" "$o" $?

# ── 5. R5 UNPARSED · NO-ORDER-LINE · DUP-ENTRY 그대로 ──
card c7 '- DA r1 HOLD 2'; o="$(g)"; chk "R5 UNPARSED rc3" 3 "UNPARSED" "$o" $?
card c8 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2'; o="$(g --entry ⑥ r2)"; chk "R5 NO-ORDER-LINE rc3" 3 "NO-ORDER-LINE DA⑥ r2" "$o" $?
card c9 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2' '- DA⑥ r2 발주' '- DA 입장: ⑥r2 · 발주서 본문 · 해제 #없음 · 2026-10-18T18:00:00'
o="$(g --entry ⑥ r2)"; chk "R5 DUP-ENTRY rc3" 3 "DUP-ENTRY ⑥r2" "$o" $?

# ── 6. R6 첫 줄 형식 불변 · budget_left = CAP − 사건 ──
card c10 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1'
o="$(g)"; [[ "${o%%$'\n'*}" =~ ^HOLD\ events=[0-9]+\ reviews=[0-9]+\ releases=[0-9]+/[0-9]+\ budget_left=-?[0-9]+$ ]] && ok "R6 첫 줄 형식 정규식 통과" || bad "R6 첫 줄 «${o%%$'\n'*}»"

# ── 7. 변이 — 상수를 2 로 되돌리면 R1(사건 2 입장) 칸이 잡고, 막는 비교를 지우면 R2(사건 3 막음) 칸이 잡는다 ──
cp "$GATE" "$KIT/ft_git_capped.py" "$KIT/ft-team-lib.sh" "$T/mut/"
{ echo '# 인덱스: m'; echo '## 상태'; H2; echo '- DA② r3 발주'; } > "$T/mut/cap2card.md"
sed 's/^CAP = 3/CAP = 2/' "$GATE" > "$T/mut/cap2.py"
OUT="$(python3 "$T/mut/cap2.py" "$T/mut/cap2card.md" --seats-dir "$T/s" --comm "$T/c" --entry ② r3 2>&1)"; RC=$?
{ [ "$RC" = 3 ] && [[ "$OUT" == *"budget_left=0"* ]]; } && ok "변이 ⓐ CAP=2 로 되돌림 → R1 칸(사건 2 rc0 기대)이 rc=3 으로 FAIL" || bad "변이 ⓐ rc=$RC $OUT"
{ echo '# 인덱스: m'; echo '## 상태'; H3; echo '- DA⑥ r2 발주'; } > "$T/mut/noblockcard.md"
sed 's/else budget <= 0/else budget <= -99/' "$GATE" > "$T/mut/noblock.py"
OUT="$(python3 "$T/mut/noblock.py" "$T/mut/noblockcard.md" --seats-dir "$T/s" --comm "$T/c" --entry ⑥ r2 2>&1)"; RC=$?
{ [ "$RC" = 0 ]; } && ok "변이 ⓑ 막는 비교 제거 → R2 칸(사건 3 rc3 기대)이 rc=0 으로 FAIL" || bad "변이 ⓑ rc=$RC $OUT"
card c3 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r1 HOLD 2' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "대조: 변이 전 원본은 같은 카드(c3)에서 rc3" 3 "budget_left=0" "$o" $?

echo "fail=$fail"; [ "$fail" = 0 ]
