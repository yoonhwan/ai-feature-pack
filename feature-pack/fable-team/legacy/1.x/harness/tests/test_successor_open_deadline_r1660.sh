#!/usr/bin/env bash
# test_successor_open_deadline_r1660.sh — 송신 단계도 «전체 예산» 안에서 끝난다 (r1660-c · arch#298 · DA HOLD §3).
# 반례: 좌석이 작업 중(QUEUED=1)이면 ft-send-verified 가 reach 를 60초로 잡아 2회 = 120초 → 도구 상한(60)·70초 래퍼를 넘겼다.
#   T1 busy 반례 → 가상 경과 ≤ BUDGET · 송신 1회 · rc5   T2 T1 직후 재실행(확인만) → 송신 총 1 · ring 1 · rc0 · .sent 없음
#   T3 유휴 좌석 20초 경로 불변 rc0   T4 FT_SV_DEADLINE 없는 직접 호출 = 종전 동작   M4 clip 제거 → T1 FAIL   M5 .sent 기록 제거 → T2 송신 2
# 준비 = lib/r1660_successor_env.sh · 송신은 «진짜» ft-send-verified.sh 를 reach·mbox 대역과 함께 돌린다(가상 시계 · 실 좌석 0).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
SV="$TMP/sv"; mkdir -p "$SV"; cp "$SV0" "$SV/ft-send-verified.sh"; cp "$FAKE/reach" "$SV/ft-reach-check.sh"
FT_SEND_VERIFIED_OVERRIDE="$SV/ft-send-verified.sh"; export FT_SEND_VERIFIED_OVERRIDE
SO="$SO0"; elapsed_of() { echo $(( $(clk) - $1 )); }
# T1 busy 반례 — 기동은 정상(대기 0)이고 좌석이 «작업 중» 이라 send-verified 의 TIMEOUT=60 → clip 이 예산 안에서 끊어야 한다
world; C0="$(clk)"; run codex RUNNING=1 REACH_RC=1
{ [ "$RC" = 5 ] && [ "$(elapsed_of "$C0")" -le 60 ] && grep -q 'SENT_UNCONFIRMED' "$TMP/out" && [ "$(sent_file)" = 777 ] && [ "$(n 'mbox send')" = 1 ]; } \
  && ok "T1 busy(QUEUED=1) → 가상 경과 $(elapsed_of "$C0")초 ≤ 60 · 송신 1 · rc5 · .sent=777" || bad "T1 rc=$RC 경과=$(elapsed_of "$C0") $(SOUTC)"
# T2 T1 직후 같은 인자 재실행 = «확인만» — 다시 보내지 않고 ring + reach 로 도달을 확정한다
run codex REACH_RC=0
{ [ "$RC" = 0 ] && [ "$(n 'mbox send')" = 1 ] && [ "$(n 'mbox ring')" -ge 1 ] && reached_ok && [ -z "$(sent_file)" ] && grep -q '재실행 확인만' "$TMP/out"; } \
  && ok "T2 재실행 → 송신 총 1 · ring 1 · 도달 파일 · .sent 지움 · rc0" || bad "T2 rc=$RC send=$(n 'mbox send') $(SOUTC)"
# T3 유휴 좌석은 종전 그대로 — TIMEOUT=20 경로로 한 번에 도달(.sent 흔적 0)
world; run codex REACH_RC=0
{ [ "$RC" = 0 ] && reached_ok && [ -z "$(sent_file)" ] && grep -q 'to=20' "$LOG" && ! grep -q 'SENT_UNCONFIRMED' "$TMP/out"; } \
  && ok "T3 유휴 → reach 20초 경로 rc0 · .sent 0(불변)" || bad "T3 rc=$RC $(SOUTC)"
# T4 FT_SV_DEADLINE 없는 직접 호출 = 종전 동작(reach 두 번 60초 · rc2 NOT_SUBMITTED)
: > "$LOG"; rm -f "$CLK"
env PATH="$FAKE:$PATH" LOG="$LOG" CLK="$CLK" RUNNING=1 REACH_RC=1 FT_MBOX_SH="$FAKE/mbox" FT_SEND_FROM="$OLD" \
    bash "$SV/ft-send-verified.sh" "$NEW" "본문" > "$TMP/svout" 2>&1; SRC=$?
{ [ "$SRC" = 2 ] && [ "$(grep -c 'to=60' "$LOG")" = 2 ] && ! grep -q 'SENT_UNCONFIRMED' "$TMP/svout"; } \
  && ok "T4 env 없음 → 종전 그대로(reach 60×2 · rc2)" || bad "T4 rc=$SRC log=$(tr '\n' ' ' < "$LOG" | cut -c1-120)"
# 변이 M4 clip 제거(사본만) → T1 의 «경과 ≤ 예산» 칸이 무너져야 한다
mkdir -p "$TMP/mut-sv"
sed 's/^    \[ -z "${FT_SV_DEADLINE:-}" \] && { echo "$1"; return 0; }$/    echo "$1"; return 0/' "$SV0" > "$TMP/mut-sv/ft-send-verified.sh"
[ "$(grep -c '^    echo "$1"; return 0$' "$TMP/mut-sv/ft-send-verified.sh")" = 1 ] || bad "변이 M4 적용 실패"
cp "$FAKE/reach" "$TMP/mut-sv/ft-reach-check.sh"
FT_SEND_VERIFIED_OVERRIDE="$TMP/mut-sv/ft-send-verified.sh"; world; C0="$(clk)"; run codex RUNNING=1 REACH_RC=1
{ [ "$(elapsed_of "$C0")" -gt 60 ]; } && ok "M4 clip 제거 → T1 FAIL 재현(가상 경과 $(elapsed_of "$C0")초 > 60)" || bad "M4 가 T1 에 안 잡힘 경과=$(elapsed_of "$C0")"
FT_SEND_VERIFIED_OVERRIDE="$SV/ft-send-verified.sh"
# 변이 M5 .sent 기록 제거(사본만) → T2 가 «확인만» 을 못 하고 두 번 보낸다
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^if \[ -n "\$SEQ" \]; then$/if false; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^if false; then$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M5 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex RUNNING=1 REACH_RC=1; run codex REACH_RC=0
{ [ "$(n 'mbox send')" -ge 2 ]; } && ok "M5 .sent 기록 제거 → T2 FAIL 재현(송신 2회)" || bad "M5 가 T2 에 안 잡힘 send=$(n 'mbox send')"
SO="$SO0"
# 런타임(comm)과 설치본(kit)은 MBOX 해석이 달라 «같은 바이트» 가 아니다 — clip 이 두 벌에 다 들어갔는지만 본다
{ grep -q 'sv_timeout' "$SV0" && grep -q 'sv_timeout' "$BIN/../kit/fable-team/bin/ft-send-verified.sh"; }   && ok "ⓕ clip 이 런타임·설치본 두 벌에 다 있음" || bad "ⓕ clip 이 한 벌에 빠짐"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
