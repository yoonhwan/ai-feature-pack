#!/usr/bin/env bash
# test_merge_land_card_only_pr_mut_r2248.sh — r2248 짝 시험: 기준판 Red ①② + 변이 M1~M3(bin 사본 · 그 자리만) + 원본 대조
#   사례 본체 = test_merge_land_card_only_pr_r2248.sh(FT_R2248_BIN · FT_R2248_ONLY 로 그 사례만) · 본 시험과 나눈 까닭 = 시험 1개 70초 상한(하드 룰 22)
#   실 좌석·실 리포·실 gh·네트워크 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; CASES="$HERE/test_merge_land_card_only_pr_r2248.sh"
BIN="$(cd "$HERE/../bin" && pwd -P)"; fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mut() {  # mut <이름> <파일> <옛 글> <새 글> → MB
  MB="$T/mut-$1"; rm -rf "$MB"; cp -R "$BIN" "$MB"; rm -rf "$MB/__pycache__"
  python3 - "$MB/$2" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
runc() {  # runc <bin> <사례…> → rc · out(PASS/FAIL 줄 요약)
  local o; o="$(FT_R2248_BIN="$1" FT_R2248_ONLY="$2" bash "$CASES" 2>&1)"; rc=$?
  out="$(printf '%s\n' "$o" | grep -E '^(PASS|FAIL)' | sed 's/ :: .*//' | tr '\n' ' ')"
}
red() { runc "$2" "$3"; [ "$rc" != 0 ]; ck "$1 → $3 FAIL(기대) :: $out" $?; }   # red <이름> <bin> <사례…>

echo "### 원본 대조: 추적본 bin 으로 c2 c4 c7 → PASS"
runc "$BIN" "c2 c4 c7"; [ "$rc" = 0 ]; ck "원본 c2 c4 c7 PASS :: $out" $?
S1=$SECONDS
echo "### 변이 M1~M3"
mut m1 ft-merge-lib.sh "grep -qvE '^design/(.+/)?indices/'" "grep -qvE '^design/'" && red "M1 indices 접두 뺌" "$MB" c4
mut m2 ft-merge-lib.sh "  case \"\${FM_CARD_ONLY:-}\" in 1|'?') tok=\"\";; esac   # r2248 O3" "  # r2248 O3" && red "M2 짝에는 판정 안 검" "$MB" c2
mut m3 ft-merge-land.sh 'fm_card_only "$REPO" "$M" "$Q"' 'fm_card_only "$REPO" "$Q^1" "$Q"' && red "M3 기준 Q^1" "$MB" c7
S2=$SECONDS
echo "### 기준판 Red ①② (팩 19fd4739 = 착지 전 origin/main)"
BASE="$T/base"; mkdir -p "$BASE"
if git -C "$HERE/.." archive 19fd4739a5dab3da21d5c1aebed1aeec09bda2ed -- bin 2>/dev/null | tar -x -C "$BASE" 2>/dev/null && [ -f "$BASE/bin/ft-merge-land.sh" ]; then
  runc "$BASE/bin" "c1 c2"; [ "$rc" != 0 ] && [[ "$out" == *"FAIL ① "* ]] && [[ "$out" == *"FAIL ② 장부 행 1 "* ]] && [[ "$out" == *"FAIL ② due 에 나노 닫기 차례 0"* ]]
  ck "기준판 ① ② FAIL(기대) :: $out" $?
else rc=1; out="git archive 실패"; ck "기준판 꺼내기" 1; fi
echo "단계별 초: 원본 대조 $((S1 - T0)) · 변이 $((S2 - S1)) · 기준판 $((SECONDS - S2)) · 전체 $((SECONDS - T0))"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
