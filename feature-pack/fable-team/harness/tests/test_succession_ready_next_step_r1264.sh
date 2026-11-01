#!/usr/bin/env bash
# test_succession_ready_next_step_r1264.sh — 승계의 다음 동작은 mbox [레디] 수신이다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; REPO="$HERE/../.."
SRC="$REPO/harness/comm"; BIN="$REPO/harness/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3";; esac; }
O=byz-feature-master-claude#78; N=byz-feature-master-claude#79
mkdir -p "$T/stub"
printf '#!/bin/sh\necho "h62 0"\n' > "$T/stub/ft-hil.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/stub/tmux"

ENVROOT="$T/env"; C="$ENVROOT/.fable-team/comm"; Q="$C/mailbox.jsonl"
mkdir -p "$C" "$ENVROOT/.fable-team/state" "$ENVROOT/seats"
git -C "$ENVROOT" init -q
cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"
printf '{"_master":"%s","%s":{"role":"master"},"%s":{"role":"master"}}\n' "$O" "$O" "$N" > "$ENVROOT/seats/seats.json"
printf '{"seq":1,"ts":"t","to":"%s","from":"slack-oppa","body":"[HIL] 질문"}\n' "$O" > "$Q"
xenv() { env -u FT_PLANNER_HEAD_MODE PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_HIL_BIN="$T/stub/ft-hil.sh" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 FT_NAME_LINT="$BIN/ft-name-lint.sh" FT_MBOX_PY="$C/mbox.py" "$@"; }
sh_() { OUT="$(cd "$ENVROOT" && xenv bash "$C/mbox.sh" "$@" 2>&1)"; RC=$?; }
py() { OUT="$(cd "$ENVROOT" && xenv python3 "$C/mbox.py" "$@" 2>&1)"; RC=$?; }

# R1–R2: 인계 쪽지는 후계의 mbox 응답과 구세션 수신 순서를 안내한다.
sh_ recv "$O"
sh_ handover "$O" "$N"
BODY="$(python3 -c 'import json,sys;print([json.loads(x) for x in open(sys.argv[1]) if x.strip()][-1]["body"])' "$Q")"
has "$BODY" "bash mbox.sh ready $N $O" "R1 handover가 후계 mbox ready를 안내"
has "$BODY" "bash mbox.sh recv $O" "R2 handover가 구세션 mbox recv를 안내"
case "$BODY" in *send-keys*) bad "R3 handover는 pane 입력을 안내하지 않음";; *) ok "R3 handover는 pane 입력을 안내하지 않음";; esac

# R4: 실제 ready 회신을 옛 세션이 recv 한 뒤 닫기 관문을 통과한다.
printf '{"%s":{"role":"stop-ready","_replaced_by":"%s"},"%s":{"role":"master"}}\n' "$O" "$N" "$N" > "$ENVROOT/seats/seats.json"
sh_ recv "$N"; sh_ ready "$N" "$O"; sh_ recv "$O"; py close-check "$O"
[ "$RC" = 0 ] && has "$OUT" "CLOSE-OK" "R4 mbox ready recv 뒤 close-check 통과" || bad "R4 ready 왕복 rc=$RC"

# 은퇴 명령도 실제 stdout 에 구세션의 다음 수신 단계를 남긴다.
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/reap-stub.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/quiesce-stub.sh"
RETIRE_OUT="$(cd "$ENVROOT" && env FT_SEATS_JSON="$ENVROOT/seats/seats.json" FT_MBOX_DIR="$C" FT_MBOX_PY="$C/mbox.py" FT_SEAT_REAP_BIN="$T/reap-stub.sh" FT_SEAT_QUIESCE_BIN="$T/quiesce-stub.sh" bash "$BIN/ft-seat-retire.sh" "$O" "$N" --seats "$ENVROOT/seats/seats.json" 2>&1)"
has "$RETIRE_OUT" "NEXT: bash mbox.sh recv $O — 후계 [레디] 수신 뒤 닫기" "R4 retire stdout 에서 mbox ready 수신을 안내"

# 두 변이는 계약 문구가 빠지거나 tmux 입력으로 되돌면 테스트가 잡는다.
RETIRE="$BIN/ft-seat-retire.sh"; KIT="$REPO/harness/kit/fable-team/bin/ft-seat-retire.sh"
grep -Fq 'NEXT: bash mbox.sh recv %s' "$RETIRE" && ok "R1 retire 출력에 mbox recv 다음 단계" || bad "R1 retire 다음 단계 없음"
cmp -s "$RETIRE" "$KIT" && ok "R2 bin·kit retire 사본 일치" || bad "R2 bin·kit 사본 불일치"
cp "$RETIRE" "$T/retire.mut"; sed -i '' 's/NEXT: bash mbox.sh recv/REMOVED/' "$T/retire.mut"
grep -Fq 'NEXT: bash mbox.sh recv %s' "$T/retire.mut" && bad "M1 retire 안내 누락 변이를 못 잡음" || ok "M1 retire 안내 누락 변이 검출"
cp "$C/mbox_handover.py" "$T/handover.mut.py"; sed -i '' "s/bash mbox.sh ready/ tmux send-keys/" "$T/handover.mut.py"
grep -Fq 'bash mbox.sh ready' "$T/handover.mut.py" && bad "M2 ready 문구 변이를 못 잡음" || ok "M2 ready 문구 변이 검출"

[ "$fail" -eq 0 ] && { echo ALL-PASS; exit 0; }
echo "FAILED $fail"; exit 1
