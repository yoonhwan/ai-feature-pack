#!/usr/bin/env bash
# test_mbox_ring_unregistered_successor_r1116c.sh — 후계 명부 미등록(retire 전)이어도 깨우기가 후계로 간다 (r1116c ⓔ-1 · R7 · Issue #4798).
# 실사건: v65 #254 17:35~ 멈춤 — 후계가 명부 밖이라 역할 우편함·ring 현역 = 구 #253(planner 가 pane 주입으로 깨움).
# 고침 = ft-successor-open 이 도달 직후 같은 호출에서 ft-seat-retire(진짜) → 명부 _replaced_by → r1116 holder(ring·doorbell 대상)가 후계.
# 가짜 명부 1칸 + 정본 mbox 사본(임시 폴더) + 가짜 tmux — 실 명부·실 큐·실 tmux 입력 0 · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 재진입 표지 = RSG_ACTIVE(자식 1회)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; SRC="$HERE/../comm"; SO0="$BIN/ft-successor-open.sh"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
OLD="byz-zz-master-claude#78"; NEW="byz-zz-master-claude#79"; FAKE="$TMP/fakebin"; mkdir -p "$FAKE"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in has-session) exit 0;; list-panes) echo 4242;; display-message) case "$*" in *":"*) echo "$PANE_CWD";; esac;; esac; exit 0'
mkstub tmuxc 'echo bootenter >> "$LOG"; exit 4'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; exit 1'
mkstub reach 'exit 4'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문\n' > "$TMP/body.txt"

world() {   # 임시 리포 · 명부(구 #78 현역 · 후계 #79 미등록) · 정본 mbox 사본 · 후계 발신 쪽지 1(log.jsonl = 도달 근거 mail)
  REPO="$(mktemp -d "$TMP/w.XXXXXX")"; git -C "$REPO" init -q; C="$REPO/.fable-team/comm"; mkdir -p "$C" "$REPO/.fable-team/state"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$C/"; : > "$C/mailbox.jsonl"
  printf '{}\n' > "$REPO/.fable-team/seats.json"
  printf '{"_master": "%s", "%s": {"role": "master", "agent": "claude", "model": "claude-sonnet-5-5"}}\n' "$OLD" "$OLD" > "$REPO/.fable-team/seats-zz.json"
  printf '{"seq": 192730, "ts": "2026-10-29T17:40:00", "to": "byz-planner-master-claude#166", "from": "%s", "body": "[보고] 부팅"}\n' "$NEW" > "$C/mailbox.log.jsonl"
  LOG="$REPO/calls.log"; : > "$LOG"
}
holder() { (cd "$REPO" && env PATH="$FAKE:$PATH" FT_SEATS_JSON="$REPO/.fable-team/seats.json" FT_MBOX_DIR="$C" python3 "$C/mbox.py" holder "$1" 2>&1); }
run() {   # run <successor-open 경로>
  (env HOME="$TMP/home" PANE_CWD="$REPO" PATH="$FAKE:$PATH" LOG="$LOG" FT_SO_POLL=0 FT_SO_WAIT_MAX=2 \
    FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$C/mbox.sh" FT_REACH_CHECK="$FAKE/reach" \
    bash "$1" "$OLD" "$REPO" --name "$NEW" --agent claude --model claude-sonnet-5-5 --body-file "$TMP/body.txt") > "$TMP/out" 2>&1
  RC=$?
}
roster_new() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get(sys.argv[2],{}).get("_replaced_by",""),d.get("_master",""))' "$REPO/.fable-team/seats-zz.json" "$OLD"; }

# 기준값: 후계 미등록이면 ring·doorbell 대상(holder) = 구 좌석
world; h0="$(holder "$OLD")"
[ "$h0" = "$OLD" ] && ok "기준 holder($OLD) = 구 좌석(후계 미등록 = 깨우기가 구 좌석으로)" || bad "기준 holder :: $h0"

# 변이: retire 호출 끔(사본만) → 명부 그대로 · holder = 구 좌석 → ⓔ FAIL 재현
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^  \[ -f "\$RETIRE" \] || {.*$/  return 0/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^  return 0$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 적용 실패"
run "$TMP/mut/ft-successor-open.sh"; hm="$(holder "$OLD")"
{ [ "$RC" = 0 ] && [ "$hm" = "$OLD" ]; } && ok "변이 retire 끔 → holder 구 좌석 그대로(ⓔ FAIL 재현)" || bad "변이가 안 잡힘 rc=$RC holder=$hm"

# ⓔ R7: 이어가기 «이미 도달(mail)» → 같은 호출에서 진짜 retire → 명부 _replaced_by 후계 → holder(구·역할 이름) = 후계
world; run "$SO0"; h1="$(holder "$OLD")"; h2="$(holder byz-zz-master-claude)"; rn="$(roster_new)"
{ [ "$RC" = 0 ] && grep -q '이미 도달(근거=mail)' "$TMP/out" && grep -q 'retire rc=0' "$TMP/out" && [ "$rn" = "$NEW $NEW" ]; } \
  && ok "ⓓ R7 도달 직후 retire rc0 → 명부 _replaced_by·_master = $NEW" || bad "ⓓ R7 rc=$RC roster=$rn $(tr '\n' ' ' < "$TMP/out" | cut -c1-400)"
{ [ "$h1" = "$NEW" ] && [ "$h2" = "$NEW" ]; } && ok "ⓔ ring 대상 holder($OLD)·역할 이름 = 후계 $NEW" || bad "ⓔ holder :: $h1 $h2"
{ [ "$(grep -c '^bootenter' "$LOG")" = 0 ] && [ "$(grep -c '^send' "$LOG")" = 0 ]; } && ok "ⓔ' boot-enter·송신 0(입력줄 빔 · 재송신 0)" || bad "ⓔ' log=$(tr '\n' ' ' < "$LOG")"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
