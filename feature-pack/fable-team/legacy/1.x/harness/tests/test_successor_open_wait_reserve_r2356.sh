#!/usr/bin/env bash
# test_successor_open_wait_reserve_r2356.sh — 후계 개설의 SessionStart 대기가 «송신·도달 예약» 을 먹지 않는다 (r2356 · Issue #10239 · 골좌표 6).
# 실사건: pi 좌석은 부팅 문장이 제출돼 첫 user 가 들어와야 session_info 를 쓰고(tmuxc 부팅 문장 미제출 = 기록 0), claude 는 미관측이면 jsonl 이 없다.
#   그래서 510행 대기 루프가 BUDGET(60)을 다 써 515행이 늘 rc5 → 같은 인자 재실행이 같은 대기에 다시 들어가 «진척 0»(feature-arch#17 rc5 ×3 · #498 · #499).
# K1 = 대기는 «예약 앞» 에서 멈춘다: 남은 − POLL ≥ SEND_RESERVE → 신호가 안 와도 송신·도달로 간다.
#   ① pi 미관측(POLL 1) → rc0 · 송신 1 · 대기 20초  ② claude 미관측(POLL 3 · 간격 무관) → rc0 · 송신 1
#   ③ 미도달 rc5 뒤 같은 인자 재실행 = 확인만 → 송신 총 1 · rc0(되풀이 0) · M1·M2·M4 = K1 변이
# K2 = 다른 길 그대로: ④ codex 생략 길(대기 0)  ⑤ 관측되면 조기 종료(대기 0)  ⑥ 미제출·미도달 = rc5 · 예산 안
# 기준판(고침 전) Red = ① · ② — 대기가 예산을 다 써 rc5 · 송신 0.
# 준비 = lib/r1660_successor_env.sh(가짜 tmux·tmuxc·pgrep·ps·send·mbox·reach·retire + 격리 시계) · 실 tmux·실 좌석·실 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
SO="$SO0"
mkstub send5 'echo send >> "$LOG"; echo "SENT_UNCONFIRMED seq=777"; exit 5'   # 송신은 큐에 들어갔으나 도달 미확인(rc5)
# pi 폴더는 있는데 session_info 가 없다 = tmuxc 부팅 문장이 제출되지 않아 첫 user 가 안 들어온 상태(실사건 #357351 · 23:36:36 머리 / 23:40:24 파일)
pi_no_boot() { mkdir -p "$PI/--$(cd_pi)--"; printf '{"type":"session_meta","name":"other"}\n' > "$PI/--$(cd_pi)--/s.jsonl"; }
el() { echo $(( $(clk) - $1 )); }

# ── ① pi 부팅 문장 미관측 — 대기는 예약(40초) 앞에서 멈추고 송신·도달로 간다(기준판 = 60초 소진 rc5 · 송신 0)
world; pi_no_boot; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && reached_ok && [ "$(n 'send')" = 1 ] && grep -q "SessionStart 미관측 $NEW" "$TMP/out" \
  && [ "$(el "$C0")" -ge 20 ] && [ "$(el "$C0")" -le 60 ] && ! grep -q '다음: 같은 인자로 다시 실행' "$TMP/out"; } \
  && ok "① pi 미관측 → 대기 $(el "$C0")초(예약 40초 안 남김) · 송신 1 · 도달 파일 · rc0" || bad "① rc=$RC 경과=$(el "$C0") $(SOUTC)"
# ── ② claude 미관측 — 같은 꼴 · 대기 간격이 달라도(FT_SO_POLL=3) 예약이 지켜진다
world; C0="$(clk)"; run claude FT_SO_POLL=3 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && reached_ok && [ "$(n 'send')" = 1 ] && grep -q "SessionStart 미관측 $NEW" "$TMP/out" \
  && [ "$(el "$C0")" -ge 15 ] && [ "$(el "$C0")" -le 60 ]; } \
  && ok "② claude 미관측(POLL 3) → 대기 $(el "$C0")초 · 송신 1 · 도달 파일 · rc0" || bad "② rc=$RC 경과=$(el "$C0") $(SOUTC)"
# ── ③ 도달 미확인(rc5) 뒤 «같은 인자» 재실행 = 확인만 — 대기가 예산을 먹지 않아 되풀이 rc5 가 0(진척 있음)
world; pi_no_boot; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60 FT_SEND_VERIFIED="$FAKE/send5"
{ [ "$RC" = 5 ] && [ "$(n 'send')" = 1 ] && [ "$(sent_file)" = 777 ] && [ ! -f "$STATE/$OLD.json" ]; } \
  && ok "③ 첫 실행(도달 미확인) → rc5 · 송신 1 · .sent=777 · 도달 파일 0" || bad "③ rc=$RC send=$(n 'send') $(SOUTC)"
rm -f "$CLK"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60 REACH_RC=0
{ [ "$RC" = 0 ] && [ "$(n 'send')" = 1 ] && [ "$(n 'mbox ring')" -ge 1 ] && reached_ok && [ -z "$(sent_file)" ] && grep -q '재실행 확인만' "$TMP/out"; } \
  && ok "③ 재실행 → 송신 총 1(다시 안 보냄) · ring 1 · 도달 파일 · rc0(되풀이 0)" || bad "③ 재실행 rc=$RC send=$(n 'send') $(SOUTC)"
# ── ④ codex 생략 길 그대로 — 관측 못 하는 신호를 안 기다린다(대기 0 · «생략» 1줄)
world; C0="$(clk)"; run codex FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && reached_ok && [ "$(n 'send')" = 1 ] && grep -q 'SessionStart 관측 생략(codex — 기록 없음)' "$TMP/out" && [ "$(el "$C0")" -le 5 ]; } \
  && ok "④ codex → 대기 $(el "$C0")초(0에 붙음) · «생략» 1줄 · 송신 1 · 도달 파일" || bad "④ rc=$RC 경과=$(el "$C0") $(SOUTC)"
# ── ⑤ 관측되는 길 그대로 — 기록이 있으면 첫 바퀴에 관측하고 안 기다린다(대기 0)
world pi; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && [ "$(el "$C0")" -le 5 ]; } \
  && ok "⑤ pi 관측 → 대기 $(el "$C0")초(0에 붙음) · «관측» 1줄 · rc0" || bad "⑤ pi rc=$RC 경과=$(el "$C0") $(SOUTC)"
world claude; C0="$(clk)"; run claude FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && [ "$(el "$C0")" -le 5 ]; } \
  && ok "⑤ claude 관측 → 대기 $(el "$C0")초(0에 붙음) · «관측» 1줄 · rc0" || bad "⑤ claude rc=$RC 경과=$(el "$C0") $(SOUTC)"
# ── ⑥ 미제출·미도달 — 신호도 없고 도달도 안 되면 rc5 지만 «한 실행 예산» 안에서 끝나고 되풀이 송신 0
world; pi_no_boot; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60 FT_SEND_VERIFIED="$FAKE/send5" REACH_RC=4
{ [ "$RC" = 5 ] && [ ! -f "$STATE/$OLD.json" ] && [ "$(el "$C0")" -le 60 ] && ! grep -q 'rc124\|시간 초과' "$TMP/out"; } \
  && ok "⑥ 미제출·미도달 → rc5 · 경과 $(el "$C0")초 ≤ 60 · 도달 파일 0" || bad "⑥ rc=$RC 경과=$(el "$C0") $(SOUTC)"
# ── 변이 M1 510행 조건을 기준판(남은 > 0)으로 되돌림(사본) → ① 이 rc5 · 송신 0 으로 돌아가야 한다(기준판 Red 재현)
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^while \[ "\$i" -lt "\$WAIT_MAX" \] && so_wait_ready; do i=\$((i+1))$/while [ "$i" -lt "$WAIT_MAX" ] \&\& so_budget_ok; do i=$((i+1))/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c 'so_wait_ready; do' "$TMP/mut/ft-successor-open.sh")" = 0 ] && [ "$(grep -c 'so_budget_ok; do' "$TMP/mut/ft-successor-open.sh")" = 2 ] || bad "변이 M1 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; pi_no_boot; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 5 ] && [ "$(n 'send')" = 0 ] && [ "$(el "$C0")" = 60 ] && grep -q '검증 송신' "$TMP/out"; } \
  && ok "M1 조건 원복 → ① FAIL 재현(대기 60초 소진 · 송신 0 · rc5)" || bad "M1 이 ① 에 안 잡힘 rc=$RC 경과=$(el "$C0") $(SOUTC)"
SO="$SO0"; world; pi_no_boot; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && [ "$(n 'send')" = 1 ] && [ "$(el "$C0")" -le 60 ]; } && ok "M1 원본 대조 → 고친 판은 ① PASS(rc0 · 송신 1)" || bad "M1 원본 대조 실패 rc=$RC $(SOUTC)"
# ── 변이 M2 조건의 POLL 을 상수 1 로(간격 무시 · 사본) → ② 의 «POLL 3» 칸이 무너져야 한다(수면 몫을 안 빼면 예약이 1초 모자란다)
sed 's/^so_wait_ready() { \[ "\$(( BUDGET - \$(so_elapsed) - POLL ))" -ge "\$SEND_RESERVE" \]; }$/so_wait_ready() { [ "$(( BUDGET - $(so_elapsed) - 1 ))" -ge "$SEND_RESERVE" ]; }/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c 'so_wait_ready() { \[ "$(( BUDGET - $(so_elapsed) - 1 ))"' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M2 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; C0="$(clk)"; run claude FT_SO_POLL=3 FT_SO_WAIT_MAX=60
{ [ "$RC" = 5 ] && [ "$(n 'send')" = 0 ] && [ "$(el "$C0")" -ge 20 ] && [ "$(el "$C0")" -le 30 ]; } \
  && ok "M2 POLL 무시 → ② FAIL 재현($(el "$C0")초에서 멈춰 잔여 39초 < 예약 40 · 송신 0 · rc5)" || bad "M2 가 ② 에 안 잡힘 rc=$RC 경과=$(el "$C0") $(SOUTC)"
SO="$SO0"; world; C0="$(clk)"; run claude FT_SO_POLL=3 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && [ "$(n 'send')" = 1 ]; } && ok "M2 원본 대조 → 고친 판은 ② PASS(rc0 · 송신 1)" || bad "M2 원본 대조 실패 rc=$RC $(SOUTC)"
# ── 변이 M3 codex 생략 갈래 삭제(사본) → ④ 가 «미관측 대기» 로 돌아가야 한다(K2 다른 길 보존)
sed 's/^if \[ "\$AGENT" = codex \] || \[ "\$AGENT" = cmd \] || \[ "\$AGENT" = opencode \]; then$/if false; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^if false; then$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M3 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; C0="$(clk)"; run codex FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && ! grep -q '관측 생략' "$TMP/out" && grep -q 'SessionStart 미관측' "$TMP/out" && [ "$(el "$C0")" -ge 20 ]; } \
  && ok "M3 codex 생략 삭제 → ④ FAIL 재현(도로 «미관측» 대기)" || bad "M3 가 ④ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"; world; C0="$(clk)"; run codex FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 0 ] && grep -q '관측 생략' "$TMP/out" && [ "$(el "$C0")" -le 5 ]; } && ok "M3 원본 대조 → 고친 판은 ④ PASS(대기 $(el "$C0")초)" || bad "M3 원본 대조 실패 rc=$RC $(SOUTC)"
# ── 변이 M4 조건을 so_send_ready 1낱말 판으로(사전 DA#46 HOLD 2/2 지적 · 사본) → 수면 뒤 남은 39초로 515행 rc5 그대로
sed 's/^while \[ "\$i" -lt "\$WAIT_MAX" \] && so_wait_ready; do i=\$((i+1))$/while [ "$i" -lt "$WAIT_MAX" ] \&\& so_send_ready; do i=$((i+1))/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^while \[ "$i" -lt "$WAIT_MAX" \] && so_send_ready; do' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M4 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; pi_no_boot; C0="$(clk)"; run pi FT_SO_POLL=1 FT_SO_WAIT_MAX=60
{ [ "$RC" = 5 ] && [ "$(n 'send')" = 0 ] && [ "$(el "$C0")" -ge 20 ] && [ "$(el "$C0")" -le 30 ]; } \
  && ok "M4 1낱말 판(so_send_ready) → ① FAIL 재현($(el "$C0")초 · 잔여 39초 · 송신 0 · rc5)" || bad "M4 가 ① 에 안 잡힘 rc=$RC 경과=$(el "$C0") $(SOUTC)"
SO="$SO0"
# ── 런타임(bin)과 설치본(kit)은 «같은 바이트» — 고침이 두 벌에 다 들어갔는지
cmp -s "$SO0" "$BIN/../kit/fable-team/bin/ft-successor-open.sh" && ok "ⓕ bin·kit 짝 cmp0(고침 두 벌)" || bad "ⓕ kit 짝 다름"
grep -q '^so_wait_ready() {' "$BIN/../kit/fable-team/bin/ft-successor-open.sh" && ok "ⓕ kit 에 so_wait_ready 있음" || bad "ⓕ kit 에 so_wait_ready 없음"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
