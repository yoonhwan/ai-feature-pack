#!/usr/bin/env bash
# test_live_bin_drift_check_r2386_reg2.sh — r2386 회귀②(가벼운 셋): r1337 PENDING 창 · r2017 local_bin 링크 · r1407 포인터.
#   판정 규칙은 reg.sh 와 같다: PASS 수가 기존 기준값과 같고, 남는 FAIL 은 «환경 사유» 뿐.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
T0=$SECONDS; fail=0
ENVCAUSE='origin main fetch 실패'
ENVCAUSE_D8='^FAIL D8$'   # D8 = spawn·close 로 WARN/PENDING 줄을 보는 시험 — 이 기계는 spawn 의 origin fetch 가 실패해 그 «앞» 에서 멈춘다(기준판 동일)
reg() { # reg <시험 파일> <기대 PASS 수> <기대 FAIL 줄 수>
  local t="$1" want="$2" wantfail="$3" out rc np nf bad_lines
  out="$(bash "$HERE/$t" 2>&1)"; rc=$?
  np="$(printf '%s\n' "$out" | grep -c '^PASS ' || true)"; nf="$(printf '%s\n' "$out" | grep -c '^FAIL ' || true)"
  bad_lines="$(printf '%s\n' "$out" | grep '^FAIL ' | grep -vF "$ENVCAUSE" | grep -Ev "$ENVCAUSE_D8" || true)"
  if [ "${np:-0}" -eq "$want" ] && [ "${nf:-0}" -eq "$wantfail" ] && [ -z "$bad_lines" ]; then
    echo "PASS $t — PASS $np · FAIL $nf(환경 사유만) · rc=$rc"
  else
    echo "FAIL $t — PASS ${np:-0}(기대 $want) · FAIL ${nf:-0}(기대 $wantfail) · 환경 밖 FAIL: ${bad_lines:0:300}"; fail=$((fail + 1))
  fi
}
reg test_drift_check_landing_window_r1337.sh 20 1
reg test_local_bin_link_drift_r2017.sh 21 0
reg test_live_bin_pointer_drift_r1407.sh 20 0

echo "[시간] 회귀(가벼운 3파일) 총 $((SECONDS - T0))초"
[ "$((SECONDS - T0))" -le 70 ] && echo "PASS 시험 시간 상한(70초 · 실측 $((SECONDS - T0))초)" || { echo "FAIL 시험 시간 상한(70초 초과)"; fail=$((fail + 1)); }
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "($fail failed)"; exit 1
