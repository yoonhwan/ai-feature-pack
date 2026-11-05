#!/usr/bin/env bash
# test_press_gate_step1_cache_r1260_d.sh — r1260 press 게이트 ① 판정 캐시(4/5): 변이 3 — 변이마다 해당 칸이 FAIL 해야 하고 변이 없는 판은 PASS(대조)
#   변이 1 키에서 나노 HEAD 빼기 → R2 FAIL · 변이 2 키에 기준 줄기 sha 다시 넣기 → R3 FAIL(r1411 · 판정 4127) · 변이 3 저장 판정을 늘 OK 로 → R7 FAIL (변이 4~6 은 e)
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
mut(){ # 이름 칸 sed식
  local m; m="$(mkprobe "$GATE" "$3")" || { bad "$1 적용 안 됨"; return; }
  run_cases "$P" "$2"; [ -z "$BAD" ] && ok "$1 대조(변이 없음) $2 통과" || { bad "$1 대조 $2 실패"; return; }
  run_cases "$m" "$2"; [ "$BAD" = " $2" ] && ok "$1 → $2 FAIL" || bad "$1 못 잡음($2 결과:${BAD:- 통과})"
}
mut "변이 1(키에서 나노 HEAD)" r2 's/p="\$p|\$w:\$h:\$ih:\$bres"/p="$p|$w:$ih:$bres"/'
mut "변이 2(키에 기준 줄기 sha)" r3 's/^  p="trunk=\$FEAT|/  p="trunk=$FEAT,$S1_FEAT_NOW|/'
mut "변이 3(저장 판정 늘 OK)" r7 's/"\$(\[ "\$UNLANDED" = "0" \] && echo OK || echo UNLANDED)"/OK/'
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
