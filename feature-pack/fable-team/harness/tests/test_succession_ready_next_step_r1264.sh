#!/usr/bin/env bash
# test_succession_ready_next_step_r1264.sh — retire·close-check의 mbox 다음 동작 계약.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stub"
fail=0; env_n=0; O=byz-feature-master-claude#78; N=byz-feature-master-claude#79
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3"; return 1;; esac; }
new_env() {
  env_n=$((env_n+1)); ENVROOT="$T/env.$env_n"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
  mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats" "$T/stub"; git -C "$ENVROOT" init -q
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; : > "$Q"
  roster 0
}
roster() {
  if [ "$1" = 1 ]; then
    printf '{"_master":"%s","%s":{"role":"stop-ready","_replaced_by":"%s"},"%s":{"role":"master"}}\n' "$N" "$O" "$N" "$N" > "$ENVROOT/seats/seats-feature.json"
  else
    printf '{"_master":"%s","%s":{"role":"master"},"%s":{"role":"master"}}\n' "$O" "$O" "$N" > "$ENVROOT/seats/seats-feature.json"
  fi
}
row() { printf '{"seq":%s,"ts":"t","to":"%s","from":"slack-oppa","body":"%s"}\n' "$1" "$2" "$3" >> "$Q"; }
sh_() { OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-feature.json" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/stub/ft-hil.sh" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats-feature.json" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/stub/ft-hil.sh" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }
retire() {
  local old="$1"; shift
  OUT="$(cd "$ENVROOT" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY FT_SEATS_JSON="$ENVROOT/seats/seats-feature.json" FT_MBOX_DIR="$C" FT_MBOX_PY="$C/mbox.py" FT_SEAT_REAP_BIN="$T/reap-stub.sh" FT_SEAT_QUIESCE_BIN="$T/quiesce-stub.sh" bash "$BIN/ft-seat-retire.sh" "$old" "$@" 2>&1)"; RC=$?
}
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/reap-stub.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/quiesce-stub.sh"
printf '#!/bin/sh\necho "h62 0"\n' > "$T/stub/ft-hil.sh"

# R1: 성공한 승계 retire는 후계가 읽고 응답할 두 mbox 명령만 안내한다.
new_env; retire "$O" "$N" --seats "$ENVROOT/seats/seats-feature.json"
ROOT="$(cd "$ENVROOT" && pwd -P)"; MBOX="$ROOT/.fable-team/comm/mbox.sh"
NEXT="다음: bash $MBOX recv '$N' → bash $MBOX ready '$N' '$O' (pane 입력 [레디] 는 닫기 관문이 세지 않음)"
[ "$RC" = 0 ] && has "$OUT" "$NEXT" "R1 retire 성공 안내 대상·명령" || bad "R1 rc=$RC 안내 없음 · out=[$OUT] want=[$NEXT]"

# R2: 미표시 쪽지가 retire를 막으면 다음 단계 안내도 나오지 않는다.
new_env; row 1 "$O" "[HIL] 질문"; sh_ recv "$O"
retire "$O" "$N" --seats "$ENVROOT/seats/seats-feature.json"
[ "$RC" = 4 ] && has "$OUT" "REJECT 승계 전 쪽지 마무리" "R2 retire 거절 rc4" || bad "R2 rc=$RC"
case "$OUT" in *"다음:"*) bad "R2 거절 경로에 다음 단계가 나옴";; *) ok "R2 거절 경로 안내 0";; esac

# R3: record-only는 승계 재개 기록만 처리하고 안내를 내지 않는다.
new_env; retire "$O" "$N" --seats "$ENVROOT/seats/seats-feature.json"; roster 1
retire "$O" --record-only --seats "$ENVROOT/seats/seats-feature.json"
[ "$RC" = 0 ] || bad "R3 record-only rc=$RC"
case "$OUT" in *"다음:"*) bad "R3 record-only 안내가 나옴";; *) ok "R3 record-only 안내 0";; esac

# R4: close-check는 후계 ready 명령을 안내하고, 실제 ready 뒤에는 기존 CLOSE-OK를 유지한다.
new_env; row 1 "$O" "[HIL] 질문"; sh_ recv "$O"; sh_ handover "$O" "$N"; [ "$RC" = 0 ] || bad "R4 handover rc=$RC: $OUT"; roster 1
py close-check "$O"
[ "$RC" = 3 ] && has "$OUT" "bash mbox.sh ready $N $O (pane 입력은 세지 않음)" "R4 close-check 거절 안내" || bad "R4 미응답 rc=$RC"
sh_ recv "$N"; sh_ ready "$N" "$O"; sh_ recv "$O"; py close-check "$O"
[ "$RC" = 0 ] && has "$OUT" "CLOSE-OK" "R4 ready 뒤 CLOSE-OK 유지" || bad "R4 응답 rc=$RC"

[ "$fail" -eq 0 ] && { echo ALL-PASS; exit 0; }
echo "FAILED $fail"; exit 1
