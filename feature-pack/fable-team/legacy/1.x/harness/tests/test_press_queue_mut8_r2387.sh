#!/usr/bin/env bash
# test_press_queue_mut8_r2387.sh — r2387 변이 M8: VALID 를 «앞» 에서만 보면(정정 전 규칙) ⑩(줄 어디든 VALID 면 NEXT = 대기)이 FAIL 하는가 (하드 룰 22 로 mut2 에서 쪼갬)
#   ⑩ 사례 = 승인 순 A(NONE, 앞) · B(VALID, 뒤) · 묶음은 B 것 1개
#   틀 = _press_queue_r2387_lib.sh · 실 gh·실 원격 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
qmut() { : > "$STUB_LOG"; out="$(bash "$1/ft-press-evidence.sh" queue --repo "$REPO" --main "${QMAIN:-origin/main}" 2>&1)"; rc=$?; }
S0=$SECONDS
qreset
qm 101 pr101 30 worker/p101.py=p101
qm 102 pr102 10 worker/p102.py=p102
vbs "$(setof "$(sha "$REPO" pr102)")" 20261117-152000
mut M8 verify '    valid = [r for r in rows if r[2] == "VALID"]' '    valid = [r for r in rows[:1] if r[2] == "VALID"]'

# ===== 변이: 앞만 봄 → 앞줄(NONE)이 NEXT 가 되어 «대기(VALID …)» 가 안 나온다 = ⑩ FAIL =====
qmut "$MBIN"
if [ "$rc" = 0 ] && [[ "$out" == *"NEXT 대기(VALID PR 102 착지 뒤"* ]]; then ck "ⓜM8 VALID 를 «앞» 에서만 봄 → ⑩ 의 «대기(VALID PR 102 …)» 0 = FAIL" 1; else ck "ⓜM8 VALID 를 «앞» 에서만 봄 → ⑩ 의 «대기(VALID PR 102 …)» 0 = FAIL" 0; fi

# ===== 원본 재확인: 같은 사례에서 대기(VALID PR 102 …) =====
qmut "$BIN"
[ "$rc" = 0 ] && [[ "$out" == *"PR #101 NONE"* ]] && [[ "$out" == *"PR #102 VALID"* ]] && [[ "$out" == *"NEXT 대기(VALID PR 102 착지 뒤"* ]]
ck "ⓜM8 원본 재확인 → ⑩ 통과(같은 사례 1회 더)" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: M8 $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
