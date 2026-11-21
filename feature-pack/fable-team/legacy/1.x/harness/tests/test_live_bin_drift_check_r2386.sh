#!/usr/bin/env bash
# test_live_bin_drift_check_r2386.sh — r2386: 드리프트 검사 «대조 방식» 을 묶는다(hash-object --stdin-paths 1회 · here-string 0 · EXTRA awk 1회).
#   반례 ①~⑫ = 이 파일 · 회귀 = test_live_bin_drift_check_r2386_reg.sh · 변이 M1~M6 = test_live_bin_drift_check_r2386_mut.sh
#   세계·계측 = tests/lib/r2386_fixture.sh (mktemp 만 · 실 라이브·네트워크 0) · 기준판 = tests/fixtures/drift_check_pre_r2386.sh
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r2386_fixture.sh"   # R2386_BIN = 변이 사본 갈아끼우기
. "$RF_HERE/r2386_cells.sh"
T0=$SECONDS
[ -f "$SUT" ] || { echo "ERROR 검사 스크립트 없음: $SUT"; exit 1; }
[ -f "$OLD" ] || { echo "ERROR 기준판 사본 없음: $OLD"; exit 1; }
bash -n "$SUT" && ok "bash -n 검사 스크립트" || { echo "ERROR bash -n 실패"; exit 1; }

t=$SECONDS; c1;  echo "[시간] ① $((SECONDS - t))초"
t=$SECONDS; c2;  echo "[시간] ② $((SECONDS - t))초"
t=$SECONDS; c3;  echo "[시간] ③ $((SECONDS - t))초"
t=$SECONDS; c4;  echo "[시간] ④ $((SECONDS - t))초"
t=$SECONDS; c5;  echo "[시간] ⑤ $((SECONDS - t))초"
t=$SECONDS; c6;  echo "[시간] ⑥ $((SECONDS - t))초"
t=$SECONDS; c7;  echo "[시간] ⑦ $((SECONDS - t))초"
t=$SECONDS; c8;  echo "[시간] ⑧ $((SECONDS - t))초"
t=$SECONDS; c9;  echo "[시간] ⑨ $((SECONDS - t))초"
t=$SECONDS; c10; echo "[시간] ⑩ $((SECONDS - t))초"
t=$SECONDS; c11; echo "[시간] ⑪ $((SECONDS - t))초"
t=$SECONDS; c12; echo "[시간] ⑫ $((SECONDS - t))초"

echo "[시간] 반례 ①~⑫ 총 $((SECONDS - T0))초"
[ "$((SECONDS - T0))" -le 70 ] && ok "시험 시간 상한(70초 · 실측 $((SECONDS - T0))초)" || bad "시험 시간 상한(70초 초과)"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "($fail failed)"; exit 1
