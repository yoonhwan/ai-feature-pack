#!/usr/bin/env bash
# test_successor_open_pi_boot_enter_r2328.sh — 이어가기 boot-enter 조건 = «RESUMED ∧ AGENT ∈ {claude, pi}» (r2328 X4 · 반례 ⑥ · 변이 M3).
# 실사건: DA #38→#39 개설 1·2회째 rc5 — pi 는 떴는데 부팅 글이 입력창에 남고, 재실행의 «남은 부팅 글 Enter 1회» 가 claude 만이라 손 Enter 가 필요했다.
#   ⑥a AGENT=pi 이어가기 → 가짜 tmuxc 에 boot-enter 1회 · rc0 → 송신으로 잇는다(송신 1 · 도달 파일)
#   ⑥b boot-enter rc≠0 → HIL exit 5 · 송신 0 / ⑥c claude 이어가기 그대로 boot-enter 1회 / ⑥d bin·kit 짝 cmp0
#   M3(사본만) 조건에서 pi 지움 → ⑥a FAIL 재현 · 원본 대조 = ⑥a
# 준비 = lib/r1660_successor_env.sh(가짜 tmux·pgrep·ps·send·mbox·reach·retire·격리 시계) + 이 파일의 가짜 tmuxc(boot-enter rc = BE_RC) · 실 tmux·실 좌석·sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"
SO="$SO0"
mkstub tmuxc 'case "$1" in boot-enter) echo "bootenter $2" >> "$LOG"; exit "${BE_RC:-0}";; *) echo "open $2" >> "$LOG";; esac; exit 0'
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
n() { grep -c "^$1" "$LOG"; }
reached_ok() { [ -f "$STATE/$OLD.json" ] && grep -q "\"successor\":\"$NEW\"" "$STATE/$OLD.json"; }
SOUTC() { tr '\n' ' ' < "$TMP/out" | cut -c1-300; }
case_6a() { world pi; run pi HAS_AT=1 REACH_RC=0; [ "$RC" = 0 ] && [ "$(n bootenter)" = 1 ] && [ "$(n send)" = 1 ] && reached_ok && grep -q '이어감' "$TMP/out"; }

# ⑥a pi 이어가기 → boot-enter 1회 · rc0 → 송신으로 잇는다
case_6a && ok "⑥a pi 이어가기 → boot-enter 1 · 송신 1 · 도달 파일" || bad "⑥a rc=$RC bootenter=$(n bootenter) send=$(n send) $(SOUTC)"
# ⑥b boot-enter rc≠0 → HIL exit 5 · 송신 0
world pi; run pi HAS_AT=1 BE_RC=4
{ [ "$RC" = 5 ] && [ "$(n bootenter)" = 1 ] && [ "$(n send)" = 0 ] && ! reached_ok && grep -q '이어가기 부팅 문장 판정 rc=4' "$TMP/out"; } \
  && ok "⑥b boot-enter rc4 → HIL exit 5 · 송신 0" || bad "⑥b rc=$RC bootenter=$(n bootenter) send=$(n send) $(SOUTC)"
# ⑥c claude 이어가기 그대로
world claude; run claude HAS_AT=1 REACH_RC=0
{ [ "$RC" = 0 ] && [ "$(n bootenter)" = 1 ] && [ "$(n send)" = 1 ]; } \
  && ok "⑥c claude 이어가기 → boot-enter 1 · 송신 1(불변)" || bad "⑥c rc=$RC bootenter=$(n bootenter) $(SOUTC)"
# M3(사본만) 조건에서 pi 지움 → ⑥a FAIL 재현
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^if \[ "\$RESUMED" = 1 \] && { \[ "\$AGENT" = claude \] || \[ "\$AGENT" = pi \]; }; then$/if [ "$RESUMED" = 1 ] \&\& [ "$AGENT" = claude ]; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
if cmp -s "$SO0" "$TMP/mut/ft-successor-open.sh"; then bad "M3 적용 실패(대상 줄 없음)"
else SO="$TMP/mut/ft-successor-open.sh"; case_6a && bad "M3 가 ⑥a 에 안 잡힘" || ok "M3 pi 지움 → ⑥a FAIL 재현(bootenter=$(n bootenter) rc=$RC)"; SO="$SO0"; fi
# ⑥d bin·kit 짝
cmp -s "$SO0" "$BIN/../kit/fable-team/bin/ft-successor-open.sh" && ok "⑥d bin·kit 짝 cmp0" || bad "⑥d kit 짝 다름"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
