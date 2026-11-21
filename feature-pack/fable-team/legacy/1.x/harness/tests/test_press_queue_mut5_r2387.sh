#!/usr/bin/env bash
# test_press_queue_mut5_r2387.sh — r2387 변이 M5: 꼬리 «남은 초 ≥ 8» 확인을 지우면 ⑫ 가 FAIL 하는가 (DA#54 H1 뒤 = 하드 룰 22 로 mut2 에서 쪼갬)
#   준비 = ⑫ 원본 판 1회(남은 초 < 8 → queue 부름 0 · skip=pressq) → 그 사본에서 확인 1곳만 지운 판으로 같은 사례 → queue 를 부른다(FAIL) → 끝
#   틀 = _press_queue_tail_r2387_lib.sh(tail 시험과 같은 픽스처) · sleep 0(마감만 짧게) · 실 gh·실 원격·실 mbox 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_tail_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:1400}"; fail=$((fail+1)); fi; }
S0=$SECONDS

# ===== 준비: ⑫ 원본 판(한 번만) — 남은 초 < 8 → queue 부름 0 · skip=pressq =====
PRF=worker/pr213.py DL_OFF=10 FT_PUSH_FIXED_S=0.5 land "$FIX" 213 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=213 ' <<<"$out" && [ "$(qqueue)" = 0 ] && grep -q 'pressq' <<<"$(ltail)"
ck "ⓜM5 준비: 원본 판 ⑫ 통과(남은 초 < 8 → queue 부름 0 · skip=pressq)" $?

# ===== 변이: «남은 초 ≥ 8» 확인 지움 → 남은 0 에서도 queue 부름 = ⑫ FAIL =====
MS="$T/mfix"; rm -rf "$MS"; cp -R "$FIX" "$MS"
python3 - "$MS/ft-merge-land.sh" <<'PY' || { echo "FAIL M5 변이 대상 없음"; fail=$((fail+1)); }
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
a = 'if [ "$PQS" -lt 8 ] 2>/dev/null; then [ "$PQS" -lt 1 ] || ltk pressq; else'
assert s.count(a) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(a, 'if false; then [ "$PQS" -lt 1 ] || ltk pressq; else'))
PY
PRF=worker/pr214.py DL_OFF=10 FT_PUSH_FIXED_S=0.5 land "$MS" 214 40
N5="$(qqueue)"
[ "$rc" = 0 ] && [ "$N5" -ge 1 ] && ! grep -q pressq <<<"$(ltail)"
ck "ⓜM5 꼬리 «남은 초 ≥ 8» 확인 지움 → 남은 초 < 8 에서도 queue 부름(${N5}회) = ⑫ FAIL" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: M5 $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
