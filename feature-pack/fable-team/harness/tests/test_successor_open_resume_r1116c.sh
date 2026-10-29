#!/usr/bin/env bash
# test_successor_open_resume_r1116c.sh — 이어가기 «이미 도달» 분기 + 도달 직후 retire (r1116c · Issue #4798 · 반례 R1~R6 동결).
# 실사건: v65 #253→#254 재실행 — 후계가 부팅 문장을 이미 제출해 입력줄이 비었고 boot-enter rc=4 → HIL exit 5 · 도달 파일 0.
# 가짜 tmux·tmuxc·pgrep·send·mbox·reach·retire(PATH 앞 스텁 + env) + 임시 git 리포만 — 실 tmux 입력 0 · 실 mbox 쓰기 0 · 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # 재진입 표지 = RSG_ACTIVE(자식 1회)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; SO0="$BIN/ft-successor-open.sh"; SO="$SO0"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"
mkdir -p "$REPO/.fable-team" "$FAKE"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"; OLD="byz-t-old-claude#253"; NEW="byz-t-old-claude#254"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in
  has-session) exit 0;; list-panes) echo 4242;;
  show-environment) [ -n "${BOOT_TEXT:-}" ] && echo "TMUXC_BOOT_TEXT=$BOOT_TEXT"; exit 0;;
  display-message) case "$*" in *":"*) echo "$PANE_CWD";; esac;;
esac; exit 0'
mkstub tmuxc 'echo "bootenter $2" >> "$LOG"; exit "${BE_RC:-0}"'
mkstub pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo 5555; exit 0'
mkstub send 'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1"; exit 0'
mkstub mbox 'echo "mbox $1" >> "$LOG"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach 'echo "reach $2" >> "$LOG"; exit "${REACH_RC:-4}"'
mkstub retire 'echo "retire $1 $2 $(pwd -P)" >> "$LOG"; [ "${RETIRE_RC:-0}" = 0 ] && echo "RETIRED $1 -> $2" || echo "REJECT 승계 전 쪽지 마무리(r1116 ③ · 쓰기 0 · rc 4) — 미표시 3건"; exit "${RETIRE_RC:-0}"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문\n' > "$BODY"
JDIR="$TMP/home/.claude/projects/$(printf '%s' "$REPO" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
world() {   # world jsonl|mail|none|badjdir — 후계 기록·발신 쪽지 상태
  rm -rf "$TMP/home" "$STATE"; rm -f "$FAKE"/mailbox.log.jsonl*; : > "$LOG"; mkdir -p "$TMP/home/.claude/projects"
  case "$1" in
    jsonl) mkdir -p "$JDIR"; printf '%s\n' "{\"type\":\"agent-name\",\"agentName\":\"$NEW\"}" '{"type":"attachment","attachment":{"type":"hook_success","hookEvent":"SessionStart"}}' '{"type":"user","message":{"content":"부팅 문장"}}' > "$JDIR/a.jsonl";;
    mail) mkdir -p "$JDIR"; printf '%s\n' "{\"type\":\"agent-name\",\"agentName\":\"$NEW\"}" '{"type":"attachment","attachment":{"hookEvent":"SessionStart"}}' > "$JDIR/a.jsonl"
          printf '{"seq": 192720, "to": "byz-planner-master-claude#166", "from": "%s", "body": "[보고] 부팅"}\n' "$NEW" > "$FAKE/mailbox.log.jsonl";;
    none) mkdir -p "$JDIR"; printf '%s\n' "{\"type\":\"agent-name\",\"agentName\":\"$NEW\"}" '{"type":"attachment","attachment":{"hookEvent":"SessionStart"}}' '{"type":"user","isMeta":true}' > "$JDIR/a.jsonl";;
    badjdir) printf 'x\n' > "$JDIR";;   # 폴더 자리에 일반 파일 = 못 읽음(권한 변경 0 · 하드 룰 19)
  esac
}
run() {
  env HOME="$TMP/home" PANE_CWD="$REPO" PATH="$FAKE:$PATH" LOG="$LOG" FT_SO_POLL=0 FT_SO_WAIT_MAX=2 \
      FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" \
      FT_REACH_CHECK="$FAKE/reach" FT_SEAT_RETIRE="$FAKE/retire" "$@" \
      bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent claude --model claude-opus-5-5 --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
n() { grep -c "^$1" "$LOG"; }
reached_ok() { [ -f "$STATE/$OLD.json" ] && grep -q "\"successor\":\"$NEW\"" "$STATE/$OLD.json"; }
r1() { world jsonl; run BE_RC=4; }

# 변이 ① 분기 끔(사본만) → R1 이 지금 결함(rc 5 · 도달 파일 0)으로 돌아가야 한다
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^if \[ "\$RESUMED" = 1 \]; then$/if false; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^if false; then$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이① 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; r1
{ [ "$RC" = 5 ] && ! reached_ok && [ "$(n bootenter)" = 1 ]; } && ok "변이① 분기 끔 → R1 FAIL 재현(rc 5 · 도달 파일 0 · 기준값)" || bad "변이① 이 R1 에 안 잡힘 rc=$RC"
# 변이 ② retire 호출 끔 → R1 의 retire 칸이 FAIL 이어야 한다
sed 's/^  \[ -f "\$RETIRE" \] || {.*$/  return 0/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^  return 0$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이② 적용 실패"
r1; [ "$RC" = 0 ] && [ "$(n retire)" = 0 ] && ok "변이② retire 끔 → ⓓ retire 호출 0(R1 retire 칸 FAIL 재현)" || bad "변이② rc=$RC retire=$(n retire)"
SO="$SO0"

# ⓐ R1 v65 #253→#254 꼴: 입력줄 빔(boot-enter 라면 rc4) · 후계 jsonl SessionStart 뒤 제출 1
r1; { [ "$RC" = 0 ] && reached_ok && grep -q '이미 도달(근거=jsonl)' "$TMP/out" && [ "$(n bootenter)" = 0 ] && [ "$(n send)" = 0 ]; } \
  && ok "ⓐ R1 이미 도달(jsonl) rc0 · 도달 파일 successor=#254 · boot-enter·송신 0" || bad "ⓐ R1 rc=$RC $(tr '\n' ' ' < "$TMP/out" | cut -c1-300)"
# ⓓ R7 쪽(retire 성공) — 같은 호출에서 retire <구> <후계> 1회 · 워크트리에서
{ [ "$(n retire)" = 1 ] && grep -q "^retire $OLD $NEW $(cd "$REPO" && pwd -P)\$" "$LOG" && grep -q 'retire rc=0' "$TMP/out"; } \
  && ok "ⓓ 도달 직후 retire $OLD $NEW 1회(cwd=워크트리)" || bad "ⓓ retire 호출 :: $(tr '\n' ' ' < "$LOG")"
# ⓐ R2 jsonl 제출 0 · 후계 발신 쪽지 1
world mail; run BE_RC=4
{ [ "$RC" = 0 ] && reached_ok && grep -q '이미 도달(근거=mail)' "$TMP/out" && [ "$(n bootenter)" = 0 ]; } && ok "ⓐ R2 이미 도달(mail) rc0" || bad "ⓐ R2 rc=$RC"
# ⓐ ③ ft-reach-check(부팅 문장 앞 40자) rc0
world none; run BE_RC=4 BOOT_TEXT="통신 표준: COMM-GUIDE-BOOT 를 지금 읽고 그대로 따를 것 — 너의 세션명은 $NEW" REACH_RC=0
{ [ "$RC" = 0 ] && reached_ok && grep -q '이미 도달(근거=reach)' "$TMP/out" && grep -qx 'reach 통신 표준: COMM-GUIDE-BOOT 를 지금 읽고 그대로 따를 것 ' "$LOG"; } \
  && ok "ⓐ ③ reach-check 앞 40자 rc0 → 이미 도달(reach)" || bad "ⓐ ③ rc=$RC log=$(tr '\n' ' ' < "$LOG")"
# ⓑ R3 근거 0 · 입력줄 = 부팅 문장(boot-enter rc0) → 지금처럼 boot-enter 1회 → 송신 → 도달
world none; run BE_RC=0
{ [ "$RC" = 0 ] && [ "$(n bootenter)" = 1 ] && [ "$(n send)" = 1 ] && reached_ok && ! grep -q '이미 도달' "$TMP/out"; } \
  && ok "ⓑ R3 근거 0 → boot-enter 1회 → 송신 1 · 도달(변경 0)" || bad "ⓑ R3 rc=$RC log=$(tr '\n' ' ' < "$LOG")"
# ⓑ R4 근거 0 · 입력줄 빔(boot-enter rc4) → 지금처럼 HIL exit 5 · 도달 파일 0 · retire 0
world none; run BE_RC=4 BOOT_TEXT="부팅 문장" REACH_RC=4
{ [ "$RC" = 5 ] && ! reached_ok && [ "$(n bootenter)" = 1 ] && [ "$(n send)" = 0 ] && [ "$(n retire)" = 0 ]; } \
  && ok "ⓑ R4 근거 0 → boot-enter rc4 → HIL exit 5(가짜 긍정 0 · retire 0)" || bad "ⓑ R4 rc=$RC"
# ⓒ R5 jsonl 폴더 못 읽음 → «판정 불가» exit 5 · boot-enter 0
world badjdir; run BE_RC=0
{ [ "$RC" = 5 ] && grep -q '판정 불가 — jsonl 폴더 못 읽음' "$TMP/out" && [ "$(n bootenter)" = 0 ] && ! reached_ok; } \
  && ok "ⓒ R5 jsonl 폴더 못 읽음 → 판정 불가 exit 5 · 추측 0" || bad "ⓒ R5 rc=$RC $(tail -1 "$TMP/out")"
# ⓒ' reach-check rc5(판정 불가) → exit 5
world none; run BE_RC=0 BOOT_TEXT="부팅 문장" REACH_RC=5
{ [ "$RC" = 5 ] && grep -q 'ft-reach-check rc=5' "$TMP/out" && [ "$(n bootenter)" = 0 ]; } && ok "ⓒ' reach-check rc5 → 판정 불가 exit 5" || bad "ⓒ' rc=$RC"
# ⓓ R6 retire REJECT(구 좌석 미표시 쪽지) → 사유 그대로 출력 · successor-open rc0 · 도달 파일 있음
world jsonl; run BE_RC=4 RETIRE_RC=4
{ [ "$RC" = 0 ] && reached_ok && grep -q '^retire: REJECT 승계 전 쪽지 마무리' "$TMP/out" && grep -q 'WARN retire rc=4 — 도달은 됨' "$TMP/out"; } \
  && ok "ⓓ R6 retire REJECT 사유 출력 · rc0(도달은 됨)" || bad "ⓓ R6 rc=$RC $(tr '\n' ' ' < "$TMP/out" | cut -c1-300)"
cmp -s "$SO0" "$HERE/../kit/fable-team/bin/ft-successor-open.sh" && ok "ⓕ bin·kit 짝 cmp0" || bad "ⓕ kit 짝 다름"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
