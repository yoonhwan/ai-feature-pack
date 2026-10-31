#!/usr/bin/env bash
# test_press_gate_step1_cache_r1260_a.sh — r1260 press 게이트 ① 판정 캐시(1/5): 적중 · 끄기·시간·잘못된 값 · BLOCK 저장 · 판정 불가 · 시험 변수
#   R1 같은 입력 2회 → 둘째는 «① 캐시 재사용» + ① 줄·판정 같음 + ① 의 git log·diff·merge-base·cat-file 호출 0(첫 실행은 >0)
#   R6 FT_PRESS_GATE_CACHE_SEC=0 → 늘 전체 · 300초 지남 → 전체 · 숫자 아님 → ✗ + FAIL
#   R7 미랜딩 2 로 BLOCK 이 저장돼 둘째도 BLOCK · FEAT 못 풂(판정 불가)은 저장 0 · 둘째도 전체
#   R10 상대 경로 호출·다른 cwd: 문구 다른 게이트 둘이 같은 캐시를 쓰지 않는다(판 해시는 cd 전 절대 경로)
#   R11 카드 경로가 디렉터리·없는 파일 = 해시 못 얻음 → 캐시 0 · 정상 카드는 캐시
#   R9 FT_PRESS_SEAT 실행은 캐시 파일 0 · FT_PRESS_GATE_SELFTEST 도 0
#   (② 이후는 b·c · 변이는 d — 한 시험 70초 상한(하드 룰 22)으로 5파일로 쪼갰다)
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
run_cases "$P" r1 r6 r7 r9 r10 r11
[ -z "$BAD" ] && ok "R1·R6·R7·R9·R10·R11 통과" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -12 | sed 's/^/    /'; }
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
