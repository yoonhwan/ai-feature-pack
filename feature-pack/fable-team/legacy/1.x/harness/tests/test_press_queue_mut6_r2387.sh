#!/usr/bin/env bash
# test_press_queue_mut6_r2387.sh — r2387 변이 M6: gh 재시도를 지우면 ⑭(호출 2회 · 15초 안)가 FAIL 하는가 (하드 룰 22 로 mut2 에서 쪼갬)
#   변이 판 = gh 8초 멈춤 1회만(호출 1) → 원본 판 = 재시도 1 → 호출 2 · 14초대
#   틀 = _press_queue_r2387_lib.sh(임시 origin · gh «pr list» 대역 · 승인 표식 파일) · 실 gh·실 원격 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:700}"; fail=$((fail+1)); fi; }
qmut() { : > "$STUB_LOG"; out="$(bash "$1/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
S0=$SECONDS
qreset; qm 141 pr141 10 worker/p141.py=p141

# ===== 변이: gh 재시도 지움 → 호출 1회 = ⑭ FAIL(호출 수) =====
mut M6 verify '    for _ in (1, 2):
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=secs, encoding="utf-8", errors="replace")' '    for _ in (1,):
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=secs, encoding="utf-8", errors="replace")'
el=$SECONDS; GH_SLEEP=8 qmut "$MBIN"; N6="$(qgl)"; el=$((SECONDS - el))
[ "$el" -le 15 ] && [ "$N6" = 1 ] && [ "$rc" = 3 ]; ck "ⓜM6 gh 재시도 지움 → 호출 ${N6}회(2회여야) = ⑭ FAIL(계약 깨짐 재현)" $?

# ===== 원본 재확인: 재시도 1 → 호출 2회 · 15초 안 =====
el=$SECONDS; GH_SLEEP=8 qmut "$BIN"; N6B="$(qgl)"; el=$((SECONDS - el))
[ "$N6B" = 2 ] && [ "$rc" = 3 ] && [ "$el" -le 15 ]; ck "ⓜM6 원본 재확인 → 호출 ${N6B}회 · ${el}초(≤15) = ⑭ 통과(같은 사례 1회 더)" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: M6 $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
