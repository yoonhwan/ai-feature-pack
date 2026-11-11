#!/usr/bin/env bash
# test_successor_open_codex_wait_r1660.sh — 후계 개설이 «관측할 수 없는 신호» 를 상한까지 기다리지 않는다 (r1660 · Issue #8313).
# 실사건: issues-master-sol#60 codex 개설 rc124 2회 — SessionStart 대기 60초 + 송신·도달 확인이 70초 상한을 넘어 기계 [인계] 0(손 전송 #283274).
#   ⓐ codex = 대기 0 + «생략» 1줄 ⓑ claude·pi 대기 불변 ⓒ 한 실행 FT_SO_BUDGET 안 · 넘으면 rc5+재실행 1줄 ⓓ 재실행 이어가기 ⓔ 회귀 0
# 준비(가짜 tmux·tmuxc·pgrep·ps·격리 시계·send·mbox·reach·retire) = lib/r1660_successor_env.sh · 실 tmux·실 좌석·sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
SO="$SO0"
# ⓐ codex = 관측 못 하는 신호를 안 기다린다 — 대기 0 · «생략» 1줄 · 곧바로 송신·도달
world; run codex
{ [ "$RC" = 0 ] && reached_ok && grep -q 'SessionStart 관측 생략(codex — 기록 없음)' "$TMP/out" && ! grep -q 'SessionStart 미관측' "$TMP/out" && [ "$(n open)" = 1 ] && [ "$(n send)" = 1 ]; } \
  && ok "ⓐ codex → SessionStart 대기 0 · «생략» 1줄 · 송신 1 · 도달 파일" || bad "ⓐ rc=$RC $(SOUTC)"
# 변이 M1 codex 생략 조건 삭제(사본만) → ⓐ 가 도로 «미관측» 대기로 돌아가야 한다
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^if \[ "\$AGENT" = codex \] || \[ "\$AGENT" = cmd \] || \[ "\$AGENT" = opencode \]; then$/if false; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^if false; then$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M1 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex
{ [ "$RC" = 0 ] && ! grep -q '관측 생략' "$TMP/out" && grep -q 'SessionStart 미관측' "$TMP/out"; } \
  && ok "M1 codex 생략 삭제 → ⓐ FAIL 재현(도로 «미관측» 대기)" || bad "M1 이 ⓐ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# ⓑ claude·pi 는 대기 그대로 — 기록이 있으면 곧바로 관측(«생략» 0)
world claude; run claude
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && ! grep -q '관측 생략' "$TMP/out"; } \
  && ok "ⓑ claude → SessionStart 관측(대기 그대로 · «생략» 0)" || bad "ⓑ claude rc=$RC $(SOUTC)"
world pi; run pi
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && ! grep -q '관측 생략' "$TMP/out"; } \
  && ok "ⓑ pi → SessionStart 관측(대기 그대로 · «생략» 0)" || bad "ⓑ pi rc=$RC $(SOUTC)"
# ⓒ 한 실행 시간 상한 — FT_SO_BUDGET 을 넘기 전에 단계 사이에서 멈추고 rc5 + «다시 실행» 1줄(70초 래퍼 rc124 0)
world; run codex UP_AT=999 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" = 5 ] && grep -q '다음: 같은 인자로 다시 실행(이어가기 r609)' "$TMP/out" && ! reached_ok && [ "$(n send)" = 0 ] && [ "$(n open)" = 1 ]; } \
  && ok "ⓒ 상한 초과 → rc5 + «다시 실행» 1줄 · 송신 0 · 도달 파일 0(세션은 열림)" || bad "ⓒ rc=$RC $(SOUTC)"
# ⓓ ⓒ 뒤 같은 인자 재실행 = 열기 건너뛰고 송신·도달 파일·retire 까지(r609 경로) · 송신 1회(두 번 송신 0)
OPEN1="$(n open)"; rm -f "$CLK"; run codex
{ [ "$RC" = 0 ] && [ "$(n open)" = "$OPEN1" ] && [ "$(n send)" = 1 ] && reached_ok && [ "$(n retire)" = 1 ] && grep -q '이어감' "$TMP/out"; } \
  && ok "ⓓ 재실행 → 열기 건너뜀 · 송신 1 · 도달 파일 1 · retire 1" || bad "ⓓ rc=$RC open=$(n open)/$OPEN1 $(SOUTC)"
# ⓖ (DA HOLD §3) 송신 단계 예산: 격리 시계로 «기동 58초» 만 소비 → 잔여 2초 < 송신·도달 예약 40초 → 송신 0 · rc5 · 이어가기 1줄
world; run codex UP_AT=58 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" = 5 ] && [ "$(n send)" = 0 ] && ! reached_ok && grep -q '다음: 같은 인자로 다시 실행(이어가기 r609)' "$TMP/out"; } \
  && ok "ⓖ 잔여 2초 → 송신 전 rc5 · 송신 0 · 도달 파일 0(중복 송신 0)" || bad "ⓖ rc=$RC send=$(n send) $(SOUTC)"
# 변이 M3 송신 예약 삭제(사본만) → ⓖ 에서 송신에 들어가 중복 위험이 돌아온다
sed 's/^so_send_ready || so_budget_stop/so_budget_ok || so_budget_stop/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^so_budget_ok || so_budget_stop' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M3 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex UP_AT=58 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$(n send)" -ge 1 ]; } && ok "M3 송신 예약 삭제 → ⓖ FAIL 재현(잔여 2초에 송신 진입)" || bad "M3 가 ⓖ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# 변이 M2 시간 상한 삭제(사본만) → ⓒ 의 rc5 칸이 안 잡혀야 한다(재현 검증)
sed 's/^so_elapsed() { echo \$(( \$(date +%s) - SO_T0 )); }$/so_elapsed() { echo 0; }/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^so_elapsed() { echo 0; }$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M2 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex UP_AT=999 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" != 5 ] && ! reached_ok && [ "$(n send)" = 0 ]; } \
  && ok "M2 상한 삭제(시계 무시) → ⓒ rc5 칸 FAIL 재현(rc=$RC · 안 멈춤)" || bad "M2 가 ⓒ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# ⓔ 기존 successor_open 시험 회귀 0 — 기준선 = 이 환경에서 origin/main 도 같은 4칸 FAIL(ⓝ·ⓗ·ⓘ·ⓚ = comm 폴더·카드 폴더 없음 · r1660 무관). 새 FAIL 0 이면 회귀 0.
bash "$HERE/test_successor_open.sh" > "$TMP/reg" 2>&1; RRC=$?
NEWF="$(grep '^FAIL ' "$TMP/reg" | grep -vE '^FAIL (ⓝ|ⓗ|ⓘ|ⓚ) ')"
[ -z "$NEWF" ] && ok "ⓔ test_successor_open.sh 새 FAIL 0(기준선 4칸 밖 · rc=$RRC)" || bad "ⓔ 새 FAIL: $(printf '%s' "$NEWF" | cut -c1-200)"
cmp -s "$SO0" "$BIN/../kit/fable-team/bin/ft-successor-open.sh" && ok "ⓕ bin·kit 짝 cmp0" || bad "ⓕ kit 짝 다름"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
