#!/bin/bash
# R372 — mbox 가드가 판정기를 FT_BIN → ../LIVE_BIN(1행 절대경로) → ../bin 순으로 찾는다.
# 임시 comm 폴더 + 가짜 판정기(호출 로그만 남기고 rc0) + 격리 큐 — 실 큐·루트 .fable-team/ 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
SRC="$(cd "$(dirname "$0")/../../harness/comm" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL $1"; echo "     rc=$RC out=${OUT:0:300}"; }
HM="byz-harness-master-claude#64"

fake_judge() {  # <폴더> — ft-goal-table.sh · ft-spawn-hold.sh 가짜(호출 로그 = $CALLLOG)
  mkdir -p "$1"
  for n in ft-goal-table.sh ft-spawn-hold.sh; do
    printf '#!/bin/bash\necho "%s $*" >> "$CALLLOG"\ncat >/dev/null\nexit 0\n' "$1/$n" > "$1/$n"
  done
}

new_env() {  # ENVROOT · CALLLOG 를 새로 만든다
  ENVROOT="$(mktemp -d "$T/env.XXXXXX")"; CALLLOG="$ENVROOT/calls.log"; : > "$CALLLOG"
  mkdir -p "$ENVROOT/.fable-team/comm" "$ENVROOT/.fable-team/state" "$ENVROOT/.fable-team/bin" "$ENVROOT/seats"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENVROOT/.fable-team/comm/"
  echo "{\"_master\":\"$HM\"}" > "$ENVROOT/seats/seats-harness.json"; echo '{}' > "$ENVROOT/seats/seats.json"
  : > "$ENVROOT/.fable-team/state/goal-gate.armed"
}

send_from() {  # <본문> [FT_BIN 값 — 비우면 unset]
  local fb=(env -u FT_BIN -u FT_PLANNER_HEAD_MODE)
  [ -z "${2:-}" ] || fb=(env -u FT_PLANNER_HEAD_MODE "FT_BIN=$2")
  OUT="$(cd "$ENVROOT" && CALLLOG="$CALLLOG" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$ENVROOT/.fable-team/comm" \
    FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 "${fb[@]}" bash "$ENVROOT/.fable-team/comm/mbox.sh" send 'byz-zz-nano-q#0' "$HM" "$1" 2>&1)"; RC=$?
}
called() { grep -qF "$1" "$CALLLOG"; }
GOAL=$'[발주 #1] 본문\n골'; HOLD=$'[spawn 정지] hold=5\n본문'

# ⓐ FT_BIN 없음 + LIVE_BIN(절대경로 1행) → 그 폴더 판정기 호출 · ../bin 에는 판정기 없음
new_env; fake_judge "$T/live/bin"; echo "$T/live/bin" > "$ENVROOT/.fable-team/LIVE_BIN"
send_from "$GOAL"; { [ "$RC" = 0 ] && called "$T/live/bin/ft-goal-table.sh"; } && ok "ⓐ LIVE_BIN 판정기 호출" || bad "ⓐ LIVE_BIN 판정기 호출"

# ⓑ FT_BIN·LIVE_BIN 없음 + ../bin 에 판정기 → 폴백 호출
new_env; fake_judge "$ENVROOT/.fable-team/bin"
send_from "$GOAL"; { [ "$RC" = 0 ] && called "$ENVROOT/.fable-team/bin/ft-goal-table.sh"; } && ok "ⓑ ../bin 폴백 호출" || bad "ⓑ ../bin 폴백 호출"

# ⓒ 셋 다 없음 → REJECT rc3 · 사유에 3경로(「판정기 없음」 안내가 실재 경로를 가리킨다)
new_env
send_from "$GOAL"; { [ "$RC" = 3 ] && echo "$OUT" | grep -qF 'FT_BIN=' && echo "$OUT" | grep -qF 'LIVE_BIN=' && echo "$OUT" | grep -qF "폴백=$ENVROOT/.fable-team/comm/../bin"; } && ok "ⓒ 셋 다 없음 REJECT + 3경로 사유" || bad "ⓒ 셋 다 없음 REJECT + 3경로 사유"

# ⓓ FT_BIN 있음 → 우선(LIVE_BIN 무시)
new_env; fake_judge "$T/live/bin"; fake_judge "$T/ftbin"; echo "$T/live/bin" > "$ENVROOT/.fable-team/LIVE_BIN"
send_from "$GOAL" "$T/ftbin"; { [ "$RC" = 0 ] && called "$T/ftbin/ft-goal-table.sh" && ! called "$T/live/bin/"; } && ok "ⓓ FT_BIN 우선" || bad "ⓓ FT_BIN 우선"

# ⓔ LIVE_BIN 이 상대경로·빈 줄 → 무시하고 ../bin
for v in "relative/bin" ""; do
  new_env; fake_judge "$ENVROOT/.fable-team/bin"; printf '%s\n' "$v" > "$ENVROOT/.fable-team/LIVE_BIN"
  send_from "$GOAL"; { [ "$RC" = 0 ] && called "$ENVROOT/.fable-team/bin/ft-goal-table.sh"; } && ok "ⓔ LIVE_BIN='${v:-<빈 줄>}' 무시" || bad "ⓔ LIVE_BIN='${v:-<빈 줄>}' 무시"
done

# ⓕ spawn-hold 판정기도 같은 해석 — LIVE_BIN 호출 · 셋 다 없으면 3경로 사유
new_env; fake_judge "$T/live/bin"; echo "$T/live/bin" > "$ENVROOT/.fable-team/LIVE_BIN"
send_from "$HOLD"; { [ "$RC" = 0 ] && called "$T/live/bin/ft-spawn-hold.sh"; } && ok "ⓕ spawn-hold LIVE_BIN 호출" || bad "ⓕ spawn-hold LIVE_BIN 호출"
new_env
send_from "$HOLD"; { [ "$RC" = 3 ] && echo "$OUT" | grep -qF 'LIVE_BIN=' && echo "$OUT" | grep -qF '폴백='; } && ok "ⓕ spawn-hold 셋 다 없음 3경로 사유" || bad "ⓕ spawn-hold 셋 다 없음 3경로 사유"

echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" = 0 ]
