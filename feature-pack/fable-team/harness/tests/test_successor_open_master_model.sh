#!/usr/bin/env bash
# test_successor_open_master_model.sh — ft-successor-open.sh r1034: 팀장(master) 승계의 «기본 브레인 = Sonnet 5.5» 와 «이월 0» 줄.
#   계약 R1~R5(카드 r1034 반례 집합) · 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 스텁) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="${FT_SO_PATH:-$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh}"
CARRY='승계 이월 0: 앞 세션에서 쓴 사고 확대 키워드의 효과는 이 세션에 없다. 막히면 이 세션에서 판단해 다시 쓴다.'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 변이(model = 기본값 줄 삭제 · carry = «이월 0» 줄 삭제) → R1·R4 가 빨강이어야 한다
if [ -n "${FT_SO_MM_MUTATE:-}" ]; then
  MUTBIN="$TMP/mutbin"; mkdir -p "$MUTBIN"; cp -R "$(dirname -- "$SO")/." "$MUTBIN/"; MUT="$MUTBIN/$(basename -- "$SO")"
  case "$FT_SO_MM_MUTATE" in
    model) grep -v 'MODEL="claude-sonnet-5-5"' "$SO" > "$MUT.tmp" && mv "$MUT.tmp" "$MUT"
           grep -q 'MODEL="claude-sonnet-5-5"' "$MUT" && { echo "FAIL 변이 model 적용 실패"; exit 1; } ;;
    carry) grep -v '승계 이월 0:' "$SO" > "$MUT.tmp" && mv "$MUT.tmp" "$MUT"
           grep -q '승계 이월 0:' "$MUT" && { echo "FAIL 변이 carry 적용 실패"; exit 1; } ;;
    *) echo "FAIL 모르는 변이: $FT_SO_MM_MUTATE"; exit 1 ;;
  esac
  SO="$MUT"
fi
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; BODY="$TMP/body.txt"; BODY_OUT="$TMP/sent_body.txt"
mkdir -p "$REPO" "$FAKE"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"; OPENED="$TMP/opened"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux   'case "$1" in
  has-session) [ -f "$OPENED" ] && exit 0; exit 1;;
  list-panes) echo 4242;;
  send-keys) echo enter >> "$LOG";;
  display-message) echo "$PANE_CWD";;
esac; exit 0'
mkstub tmuxc  'echo "tmuxc $*" >> "$LOG"; [ "${TMUXC_RC:-0}" = 0 ] && : > "$OPENED"; exit "${TMUXC_RC:-0}"'
mkstub pgrep  'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; echo 5555; exit 0'
mkstub send   'echo send >> "$LOG"; printf "%s" "${2:-}" > "$BODY_OUT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"; cp "$BODY" "$TMP/body.before"
mkdir -p "$REPO/.fable-team" "$TMP/live-root"; printf '%s\n' "$TMP/live-root" > "$REPO/.fable-team/LIVE_ROOT"
M_OLD='byz-t-harness-master-claude#1'; M_NEW='byz-t-harness-master-claude#2'
A_OLD='byz-t-harness-arch-claude#1';   A_NEW='byz-t-harness-arch-claude#2'
# run <구 좌석> <후계> [환경…] — MODEL_ARG: 없음 = --model 생략 · 그 밖 = 그 값을 --model 로 넘긴다
run() {
  local old="$1" new="$2"; shift 2
  rm -f "$LOG" "$CNT" "$OPENED" "$BODY_OUT"; rm -rf "$STATE"
  local marg=(); [ -n "${MODEL_ARG:-}" ] && marg=(--model "$MODEL_ARG")
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" BODY_OUT="$BODY_OUT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$SO" "$old" "$REPO" --name "$new" --agent claude "${marg[@]}" --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
count() { grep -c "^$1" "$LOG" 2>/dev/null || echo 0; }

# R1 이름에 -master- + --model 생략 → tmuxc open 에 --model claude-sonnet-5-5
run "$M_OLD" "$M_NEW"
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-sonnet-5-5' "$LOG" && [ "$(count tmuxc)" = 1 ]; } \
  && ok "R1 팀장 + --model 생략 → open --model claude-sonnet-5-5 · rc0" || bad "R1 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
# R1-2 도달 파일 model 칸도 그 값
{ [ "$(jq -r '.model' "$STATE/$M_OLD.json" 2>/dev/null)" = "claude-sonnet-5-5" ]; } \
  && ok "R1-2 도달 파일 model = claude-sonnet-5-5" || bad "R1-2 $(cat "$STATE/$M_OLD.json" 2>&1)"

# R2 팀장 + --model claude-opus-5-5 명시 → 그 값 그대로(기본값이 덮지 않음)
MODEL_ARG='claude-opus-5-5' run "$M_OLD" "$M_NEW"
{ [ "$RC" -eq 0 ] && grep -q -- '--model claude-opus-5-5' "$LOG" && ! grep -q 'claude-sonnet-5-5' "$LOG"; } \
  && ok "R2 팀장 + --model 명시 → 그 값 그대로 · 기본값 덮음 0" || bad "R2 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
MODEL_ARG=''

# R3 팀장 아닌 이름 + --model 생략 → usage rc2 · 열기 0(지금과 같음)
run "$A_OLD" "$A_NEW"
{ [ "$RC" -eq 2 ] && grep -q 'usage:' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "R3 팀장 아닌 이름 + 생략 → usage rc2 · open·송신 0" || bad "R3 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# R4 팀장 → 보낸 본문 끝에 «이월 0» 줄 · 그 낱말 0 · 원본 파일 바이트 그대로
run "$M_OLD" "$M_NEW"
LAST="$(tail -n1 "$BODY_OUT" 2>/dev/null)"
{ [ "$RC" -eq 0 ] && [ "$LAST" = "$CARRY" ] && ! grep -qi 'ultrathink' "$BODY_OUT" \
  && [ "$(head -n3 "$BODY_OUT" | grep -c .)" = 3 ] && cmp -s "$BODY" "$TMP/body.before" && [ "$(count send)" = 1 ]; } \
  && ok "R4 팀장 본문 끝 «이월 0» 1줄 · 낱말 0 · 골 원문 3줄 보존 · 원본 불변" \
  || bad "R4 rc=$RC last=[$LAST] body=$(tr '\n' '|' < "$BODY_OUT" 2>/dev/null) file=$(cmp "$BODY" "$TMP/body.before" 2>&1)"

# R5 팀장 아닌 이름(모델 명시) → «이월 0» 줄 0 · 본문은 파일 그대로
MODEL_ARG='claude-sonnet-5-5' run "$A_OLD" "$A_NEW"
{ [ "$RC" -eq 0 ] && ! grep -q '이월 0' "$BODY_OUT" && [ "$(cat "$BODY_OUT")" = "$(cat "$BODY")" ]; } \
  && ok "R5 팀장 아닌 이름 → «이월 0» 줄 0 · 본문 파일 그대로" || bad "R5 rc=$RC body=$(tr '\n' '|' < "$BODY_OUT" 2>/dev/null) out=$(cat "$TMP/out")"
MODEL_ARG=''

# R6 기존 승계 흐름 회귀 — 송신 실패 5 → «이월 0» 붙은 본문으로도 ring 1회 · exit 5 · 도달 파일 0
run "$M_OLD" "$M_NEW" SEND_RC=5 REACH_RC=5
{ [ "$RC" -eq 5 ] && [ "$(count 'mbox ring')" = 1 ] && [ ! -e "$STATE/$M_OLD.json" ] && [ "$(tail -n1 "$BODY_OUT")" = "$CARRY" ]; } \
  && ok "R6 송신 5 → ring 1 · exit 5 · 도달 파일 0(본문에 «이월 0» 유지)" || bad "R6 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
