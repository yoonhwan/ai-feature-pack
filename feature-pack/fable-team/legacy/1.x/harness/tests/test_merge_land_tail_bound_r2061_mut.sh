#!/usr/bin/env bash
# test_merge_land_tail_bound_r2061_mut.sh — r2061 변이 짝: 원본 = PASS · 변이 = 바깥 상한에 잘림(FAIL) · 짝 3개를 병렬(동시 3 · 짝마다 fixture 따로)
#   M1 뒤처짐 알림을 명령 치환으로 → ① FAIL · M2 설치 대조를 명령 치환으로 → ② FAIL
#   ⑧(DA HOLD R1) 착지 알림 실 함수(fm_land_notify_land → fm_land_turn → ft-nano-record notify)의 손자가 stdout 을 물고 멈춤 → 마감 12 안 rc0 · 알림 줄 통과
#   M3 nano-record 알림을 옛 fm_try 직접 실행으로 → ⑧ FAIL(감싸기 tee 가 손자 pipe 를 기다림)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_tail_bound_r2061_fixture.sh"; T0=$SECONDS
TT="$(mktemp -d)"; trap 'for f in "$TT"/*/fifo-*; do rel "$f"; done; rm -rf "$TT"' EXIT
pair() {  # pair <이름> <사례 함수> <변이 파일> <원문> <새문> — 원본 PASS ∧ 변이 FAIL = PASS · rc = FAIL 수
  local nm="$1" cf="$2"; fx_init "$TT/$nm"; mkbin "$T/bin"; "$cf" "$T/bin" 81 12; ck "$nm 대조: 원본 PASS" $?
  mkbin "$T/mut" "$3" "$4" "$5" && { "$cf" "$T/mut" 82 12; [ $? != 0 ]; }; ck "변이 $nm → FAIL(rc=$rc el=${el}s)" $?
  return "$fail"
}
S1=$SECONDS
pair M1 c1 ft-merge-land.sh "$NEWH" "$OLDH" > "$TT/M1.log" 2>&1 & P1=$!
pair M2 c2 ft-merge-land.sh "$NEWI" "$OLDI" > "$TT/M2.log" 2>&1 & P2=$!
REAL_NOTIFY=1 pair "M3(⑧ 착지 알림 손자)" c8 ft-merge-lib.sh "$NEWN" "$OLDN" > "$TT/M3.log" 2>&1 & P3=$!
for p in $P1 $P2 $P3; do wait "$p" || fail=$((fail + $?)); done
grep -hE '^(PASS|FAIL)' "$TT/M1.log" "$TT/M2.log" "$TT/M3.log"
[ "$(cat "$TT"/M*.log | grep -cE '^(PASS|FAIL)')" = 6 ] || { echo "FAIL 짝 결과 줄 6 아님"; cat "$TT"/M*.log | tail -20; fail=$((fail + 1)); }
echo "단계별 초: 짝 3개 병렬 $((SECONDS - S1)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
