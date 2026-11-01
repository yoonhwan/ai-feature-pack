#!/usr/bin/env bash
# test_press_gate_step1_cache_r1260_e.sh — r1260 press 게이트 ① 판정 캐시(5/5): 변이 4~6 — 변이마다 해당 칸이 FAIL 해야 하고 변이 없는 판은 PASS(대조)
#   변이 4 키에서 카드 해시 빼기 → R5c FAIL · 변이 5 판 해시를 cd 뒤 상대 경로로 읽기 → R10 FAIL · 변이 6 카드 경로가 파일 아니거나 해시 못 얻어도 캐시 → R11 FAIL (변이 1~3 은 d)
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
mut(){ # 이름 칸 sed식
  local m; m="$(mkprobe "$GATE" "$3")" || { bad "$1 적용 안 됨"; return; }
  run_cases "$P" "$2"; [ -z "$BAD" ] && ok "$1 대조(변이 없음) $2 통과" || { bad "$1 대조 $2 실패"; return; }
  run_cases "$m" "$2"; [ "$BAD" = " $2" ] && ok "$1 → $2 FAIL" || bad "$1 못 잡음($2 결과:${BAD:- 통과})"
}
mut "변이 5(판 해시를 cd 뒤 상대 경로로)" r10 's/shasum -a 256 "\$SELF"/shasum -a 256 "${BASH_SOURCE[0]}"/'
mut "변이 4(키에서 카드 해시)" r5c 's/p="\$p|card=\$ch"/p="$p|card=x"/'
mut "변이 6(카드·해시 못 얻어도 캐시)" r11 's/\[ -f "\$c" \] || return 1/:/;s/\[ -n "\$h" \] && \[ "\${ch#\/}" != "\$ch" \] || return 1; //'
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
