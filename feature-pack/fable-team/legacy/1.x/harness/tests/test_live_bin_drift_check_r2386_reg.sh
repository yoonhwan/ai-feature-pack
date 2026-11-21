#!/usr/bin/env bash
# test_live_bin_drift_check_r2386_reg.sh — r2386 회귀①(무거운 것 하나): spawn·close·tick 입구까지 보는 기존 시험이 «같은 결과» 인가(card: 하드 룰 22 — 70초 상한이라 나머지 3개는 reg2).
#   판정: PASS 수가 기존 기준값과 같고, 남는 FAIL 은 «환경 사유»(spawn 이 만드는 임시 클론의 origin fetch 실패 · 이 기계 사정) 뿐이어야 한다.
#   같은 FAIL 이 기준판(tests/fixtures/drift_check_pre_r2386.sh)에서도 나는 것은 evidence/r2386/reg-{old,new}-*.log 에 남겼다 — 새 판이 만든 것이 아니다.
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
reg test_live_bin_drift_check.sh 64 5

echo "[시간] 회귀(무거운 1파일) 총 $((SECONDS - T0))초"
[ "$((SECONDS - T0))" -le 70 ] && echo "PASS 시험 시간 상한(70초 · 실측 $((SECONDS - T0))초)" || { echo "FAIL 시험 시간 상한(70초 초과)"; fail=$((fail + 1)); }
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "($fail failed)"; exit 1
