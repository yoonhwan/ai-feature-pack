#!/usr/bin/env bash
# test_mbox_handover_doorbell_force_r1160.sh — r1160: 승계 핸드셰이크 [인계](구→후계)·[레디](후계→구)는
#   doorbell 시간 억제(outstanding 120초 · 3초)를 뚫고 울린다(발주와 같은 force) · 보통 send 억제·absent 는 그대로.
#  R1 후계 doorbell 스탬프 60초 전 · recv 스탬프 그보다 앞 · handover → doorbell=sent · send-keys 1
#  R2 후계 doorbell 스탬프 1초 전(3초 억제) · handover → doorbell=sent
#  R3 구 좌석 doorbell 스탬프 60초 전 · ready → doorbell=sent
#  R4 보통 send([정리]) · 같은 outstanding 조건 → doorbell=skipped
#  R5 handover · 후계 pane 없음 → doorbell=absent
#  변이: dbf 조건 줄 삭제(= 고치기 전) → R1 skipped = FAIL 확인
# 격리: 정본 comm 사본 + 임시 우편함(FT_MBOX_DIR) + 가짜 tmux(send-keys 를 파일에 적음) + ps 스냅샷 + 임시 TMPDIR(스탬프)
#   실 우편함·실 tmux·실 명부 0 · 자기 재호출 0 · 고정 sleep 0(스탬프 시각은 touch -t)
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
O=byz-feature-master-claude#78; N=byz-feature-master-claude#79
mkdir -p "$T/stub" "$T/tmp"
# 가짜 tmux: 세션 목록 = $FAKE_SESSIONS(«이름|pane» 공백 구분) · pane_pid = 999990(실 프로세스 자식 0) · -l 주입만 기록
cat > "$T/stub/tmux" <<'EOS'
#!/bin/bash
case "$1" in
  list-panes) case "$*" in *'#{session_name}'*) for s in $FAKE_SESSIONS; do echo "$s"; done ;; *) echo 999990 ;; esac ;;
  display-message) echo claude ;;
  send-keys) [ "${4:-}" = -l ] && printf '%s|%s\n' "$3" "${5:-}" >> "$FAKE_TMUX_LOG" ;;
esac
exit 0
EOS
printf '#!/bin/sh\nexit 0\n' > "$T/stub/pgrep"
printf '#!/bin/sh\n[ "$1 $2" = "--pending --each" ] && exit 0\nexit 2\n' > "$T/stub/ft-hil.sh"
chmod +x "$T/stub/tmux" "$T/stub/pgrep" "$T/stub/ft-hil.sh"
printf '%s\n' '999990 0 999990 Mon Oct 28 12:00:00 2026 00:00.00 S login' \
  '999991 999990 999991 Mon Oct 28 12:00:00 2026 00:00.00 S claude' > "$T/ps.snapshot"

roster() {   # roster <retired 0|1>
  python3 - "$ENVROOT/seats/seats-feature.json" "$1" "$O" "$N" <<'PY'
import json, sys
p, r, o, n = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
d = {"_master": n if r else o, o: {"role": "master"}, n: {"role": "master"}}
if r: d[o] = {"role": "stop-ready", "_replaced_by": n}
json.dump(d, open(p, "w", encoding="utf-8"))
PY
}
new_env() {   # new_env [변이함수]
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$SRC"/ft-agent-alive.sh "$C/"
  printf '{}\n' > "$ENVROOT/seats/seats.json"; roster 0; : > "$Q"; rm -f "$T"/tmp/mbox-*
  if [ -n "${1:-}" ]; then "$1"; fi
}
xenv() { env -u FT_PLANNER_HEAD_MODE -u FT_DOORBELL_TAIL PATH="$T/stub:$PATH" TMPDIR="$T/tmp" FAKE_TMUX_LOG="$T/log" \
  FAKE_SESSIONS="${SESS:-$O|%1 $N|%2}" FT_PS_SNAPSHOT="$T/ps.snapshot" FT_AGENT_ALIVE_TIMEOUT=2 \
  FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/stub/ft-hil.sh" \
  FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$REPO/harness/bin/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" "$@"; }
sh_() { : > "$T/log"; OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
row() { printf '{"seq": %s, "ts": "2026-10-29T00:00:00", "to": "%s", "from": "slack-oppa", "body": "%s"}\n' "$1" "$2" "$3" >> "$Q"; }
ago() { date -r "$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S; }
stamps() {   # stamps <좌석> <doorbell 몇 초 전> — recv 스탬프는 그보다 앞(200초 전) = outstanding 꼴
  touch -t "$(ago 200)" "$T/tmp/mbox-recv-$1"; touch -t "$(ago "$2")" "$T/tmp/mbox-doorbell-$1"; }
db() { printf '%s\n' "$OUT" | sed -n 's/.* doorbell=\([a-z]*\)$/\1/p' | tail -1; }
keys() { grep -c "^$1|" "$T/log" 2>/dev/null || true; }
mut_nodbf() { sed -i '' '/"\[인계\]"\*|"\[레디\]"\*) dbf=1;;/d' "$C/mbox.sh"; ! grep -q 'dbf=1;; esac' "$C/mbox.sh"; }

# R1 (변이 겸용): 후계 outstanding 60초 · handover → sent · 후계 pane(%2) send-keys 1
chk_1() { new_env "${1:-}" || return 2; row 1 "$O" "[HIL] q"; sh_ recv "$O"; stamps "$N" 60; sh_ handover "$O" "$N"
  [ "$RC" = 0 ] && [ "$(db)" = sent ] && [ "$(keys %2)" = 1 ]; }
chk_1 mut_nodbf; r=$?; [ "$r" = 1 ] && ok "변이(dbf 조건 줄 삭제) → R1 doorbell=$(db) FAIL 확인" || bad "변이가 R1 에 안 잡힘 rc=$r :: $OUT"
chk_1 && ok "R1 [인계] outstanding 60초 → doorbell=sent · send-keys 1" || bad "R1 rc=$RC db=$(db) keys=$(keys %2) :: $OUT"

# R2: 후계 doorbell 1초 전(3초 억제) · handover → sent
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; stamps "$N" 1; sh_ handover "$O" "$N"
[ "$RC" = 0 ] && [ "$(db)" = sent ] && ok "R2 [인계] 3초 억제 → doorbell=sent" || bad "R2 rc=$RC db=$(db) :: $OUT"

# R3: retire 뒤 후계가 [인계] recv → 구 좌석 outstanding 60초 · ready → sent · 구 pane(%1)
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; sh_ handover "$O" "$N"; roster 1; sh_ recv "$N"; stamps "$O" 60; sh_ ready "$N" "$O"
[ "$RC" = 0 ] && [ "$(db)" = sent ] && [ "$(keys %1)" = 1 ] && ok "R3 [레디] outstanding 60초 → doorbell=sent · 구 pane 1" || bad "R3 rc=$RC db=$(db) keys=$(keys %1) :: $OUT"

# R4: 보통 send([정리]) · 같은 outstanding → skipped(지금과 같음) · send-keys 0
new_env; stamps "$N" 60; sh_ send "$N" "$O" "[정리] 보통 쪽지"
[ "$RC" = 0 ] && [ "$(db)" = skipped ] && [ "$(keys %2)" = 0 ] && ok "R4 보통 send outstanding → doorbell=skipped · send-keys 0" || bad "R4 rc=$RC db=$(db) :: $OUT"

# R5: 후계 pane 없음 · handover → absent(지금과 같음)
new_env; row 1 "$O" "[HIL] q"; sh_ recv "$O"; SESS="$O|%1" sh_ handover "$O" "$N"
[ "$RC" = 0 ] && [ "$(db)" = absent ] && ok "R5 후계 pane 없음 → doorbell=absent" || bad "R5 rc=$RC db=$(db) :: $OUT"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
