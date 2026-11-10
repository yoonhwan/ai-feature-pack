#!/usr/bin/env bash
# test_successor_open_carry.sh — ft-successor-open.sh r1037: «모델»과 «ultrathink 이월(--carry 0|1)» 두 축을 따로 받는다.
#   계약 R1~R8(카드 r1037 반례 집합) · 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 스텁) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
#   ★스텁 send/mbox 는 받은 FT_DOORBELL_TAIL 값을 로그에 남긴다★ — 「환경변수가 켜졌나」를 간접 추론이 아니라 «값»으로 본다(R2·R8).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="${FT_SO_PATH:-$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh}"
CARRY0='승계 이월 0: 앞 세션에서 쓴 사고 확대 키워드의 효과는 이 세션에 없다. 막히면 이 세션에서 판단해 다시 쓴다.'
CARRY1='승계 이월 1: 앞 세션의 확대 사고를 이어 받는다. 문제가 풀리면 다음 승계에서 이월 0.'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 변이 2종 — ⓐ(꼬리를 «항상» 켬) → carry 생략/0 계약이 빨강이어야 한다 · ⓑ(꼬리 설정 줄 삭제) → carry 1 계약이 빨강이어야 한다
if [ -n "${FT_SO_CARRY_MUTATE:-}" ]; then
  MUTBIN="$TMP/mutbin"; mkdir -p "$MUTBIN"; cp -R "$(dirname -- "$SO")/." "$MUTBIN/"; MUT="$MUTBIN/$(basename -- "$SO")"
  case "$FT_SO_CARRY_MUTATE" in
    always|never) python3 - "$MUT" "$FT_SO_CARRY_MUTATE" <<'PYMUT' || { echo "FAIL 변이 적용 실패"; exit 1; }
import sys
p, mode = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
old = 'TAILENV=""; [ "$CARRY" = 1 ] && TAILENV="FT_DOORBELL_TAIL=ultrathink"'
if old not in s:
    print("FAIL 변이 대상 줄 없음"); sys.exit(1)
new = 'TAILENV="FT_DOORBELL_TAIL=ultrathink"' if mode == "always" else 'TAILENV=""'
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PYMUT
    ;; *) echo "FAIL 모르는 변이: $FT_SO_CARRY_MUTATE"; exit 1 ;;
  esac
  SO="$MUT"
fi
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; BODY_OUT="$TMP/sent_body.txt"
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
mkstub send   'echo "send tail=${FT_DOORBELL_TAIL:-none}" >> "$LOG"; printf "%s" "${2:-}" > "$BODY_OUT"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1 tail=${FT_DOORBELL_TAIL:-none}" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"; cp "$BODY" "$TMP/body.before"
mkdir -p "$REPO/.fable-team" "$TMP/live-root"; printf '%s\n' "$TMP/live-root" > "$REPO/.fable-team/LIVE_ROOT"
M_OLD='byz-t-harness-master-claude#1'; M_NEW='byz-t-harness-master-claude#2'
A_OLD='byz-t-harness-arch-claude#1';   A_NEW='byz-t-harness-arch-claude#2'
# run <구 좌석> <후계> [환경…] — MODEL_ARG: 없음 = --model 생략 · CARRY_ARG: 없음 = --carry 생략(빈 값 "" = --carry "")
run() {
  local old="$1" new="$2"; shift 2
  rm -f "$LOG" "$OPENED" "$BODY_OUT"; rm -rf "$STATE"
  local marg=() carg=(); [ -n "${MODEL_ARG:-}" ] && marg=(--model "$MODEL_ARG")
  [ -n "${CARRY_ARG+set}" ] && carg=(--carry "$CARRY_ARG")
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" OPENED="$OPENED" BODY_OUT="$BODY_OUT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$SO" "$old" "$REPO" --name "$new" --agent claude "${marg[@]}" "${carg[@]}" --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
count() { grep -c "^$1" "$LOG" 2>/dev/null || echo 0; }
tailof() { sed -n "s/^$1 tail=//p" "$LOG" 2>/dev/null | head -1; }

# ⓐ R1·R3 carry 생략·0 = r1034 동작(환경변수 0 · «이월 0» 줄 · 송신 1회)
run "$M_OLD" "$M_NEW"
{ [ "$RC" -eq 0 ] && [ "$(tailof send)" = "none" ] && [ "$(count send)" = 1 ] && [ "$(tail -n1 "$BODY_OUT")" = "$CARRY0" ] \
  && ! grep -qi 'ultrathink' "$BODY_OUT" && cmp -s "$BODY" "$TMP/body.before"; } \
  && ok "ⓐ1 팀장 + --carry 생략 → 꼬리 0 · «이월 0» 1줄 · 낱말 0 · 원본 불변" \
  || bad "ⓐ1 rc=$RC tail=[$(tailof send)] last=[$(tail -n1 "$BODY_OUT" 2>/dev/null)] out=$(cat "$TMP/out")"
CARRY_ARG=0 run "$M_OLD" "$M_NEW"
{ [ "$RC" -eq 0 ] && [ "$(tailof send)" = "none" ] && [ "$(tail -n1 "$BODY_OUT")" = "$CARRY0" ]; } \
  && ok "ⓐ2 --carry 0 명시 = 생략과 같다(꼬리 0 · «이월 0»)" \
  || bad "ⓐ2 rc=$RC tail=[$(tailof send)] last=[$(tail -n1 "$BODY_OUT" 2>/dev/null)] out=$(cat "$TMP/out")"
unset CARRY_ARG

# ⓑ R2·R8 carry 1 → 송신·링 재시도 «둘 다» 꼬리 · «이월 1» 줄 · 본문 낱말 0 · 원본 불변
CARRY_ARG=1 run "$M_OLD" "$M_NEW"
{ [ "$RC" -eq 0 ] && [ "$(tailof send)" = "ultrathink" ] && [ "$(tail -n1 "$BODY_OUT")" = "$CARRY1" ] \
  && ! grep -qi 'ultrathink' "$BODY_OUT" && [ "$(head -n3 "$BODY_OUT" | grep -c .)" = 3 ] && cmp -s "$BODY" "$TMP/body.before"; } \
  && ok "ⓑ1 --carry 1 → send 꼬리 ultrathink · «이월 1» 1줄 · 낱말 0 · 골 3줄 보존 · 원본 불변" \
  || bad "ⓑ1 rc=$RC tail=[$(tailof send)] last=[$(tail -n1 "$BODY_OUT" 2>/dev/null)] out=$(cat "$TMP/out")"
# R8 송신 rc5 → ring 경로에서도 같은 꼬리(도달 실패로 exit 5 는 유지)
CARRY_ARG=1 run "$M_OLD" "$M_NEW" SEND_RC=5 REACH_RC=5
{ [ "$RC" -eq 5 ] && [ "$(count 'mbox ring')" = 1 ] && [ "$(tailof 'mbox ring')" = "ultrathink" ] && [ ! -e "$STATE/$M_OLD.json" ]; } \
  && ok "ⓑ2 R8 송신 5 → ring 1회에도 꼬리 ultrathink · exit 5 · 도달 파일 0" \
  || bad "ⓑ2 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
unset CARRY_ARG

# ⓒ R4·R5 잘못된 값·팀장 아닌 이름 → usage rc2 · 열기·송신 0
for v in 2 x ''; do
  CARRY_ARG="$v" run "$M_OLD" "$M_NEW"
  { [ "$RC" -eq 2 ] && grep -q 'usage:' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
    && ok "ⓒ1 --carry '$v' → usage rc2 · 열기·송신 0" || bad "ⓒ1 v='$v' rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
done
unset CARRY_ARG
CARRY_ARG=1 MODEL_ARG='claude-sonnet-5-5' run "$A_OLD" "$A_NEW"
{ [ "$RC" -eq 2 ] && grep -q 'usage:' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓒ2 R5 팀장 아닌 이름 + --carry 1 → usage rc2 · 열기·송신 0(조용히 무시 0)" \
  || bad "ⓒ2 rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
# 팀장 아닌 이름 + carry 생략은 종전대로 동작(«이월» 줄 0)
MODEL_ARG='claude-sonnet-5-5' run "$A_OLD" "$A_NEW"
{ [ "$RC" -eq 0 ] && [ "$(tailof send)" = "none" ] && [ "$(cat "$BODY_OUT")" = "$(cat "$BODY")" ]; } \
  && ok "ⓒ3 팀장 아닌 이름 + carry 생략 → 종전 그대로(꼬리 0 · 본문 파일 그대로)" \
  || bad "ⓒ3 rc=$RC tail=[$(tailof send)] body=$(tr '\n' '|' < "$BODY_OUT" 2>/dev/null) out=$(cat "$TMP/out")"
unset MODEL_ARG CARRY_ARG

# ⓓ R6·R7 모델 축(약어·풀네임·생략) × 이월 축(0·1) — 서로 독립
combo() { # <--model 값|''> <--carry 값|''> <기대 model> <기대 tail> <기대 마지막 줄>
  MODEL_ARG="$1"; [ -z "$2" ] && unset CARRY_ARG || CARRY_ARG="$2"
  run "$M_OLD" "$M_NEW"
  { [ "$RC" -eq 0 ] && grep -q -- "--model $3" "$LOG" && [ "$(tailof send)" = "$4" ] && [ "$(tail -n1 "$BODY_OUT")" = "$5" ]; } \
    && ok "ⓓ model='${1:-생략}' carry='${2:-생략}' → --model $3 · 꼬리 $4 · $( [ "$4" = none ] && echo «이월 0» || echo «이월 1» )" \
    || bad "ⓓ model='${1:-생략}' carry='${2:-생략}' rc=$RC log=$(tr '\n' ' ' < "$LOG") last=[$(tail -n1 "$BODY_OUT" 2>/dev/null)]"
  unset MODEL_ARG; unset CARRY_ARG
}
combo ''    '' 'claude-sonnet-5-5' 'none'       "$CARRY0"
combo ''    '1' 'claude-sonnet-5-5' 'ultrathink' "$CARRY1"
combo 'sn'  '' 'claude-sonnet-5-5' 'none'       "$CARRY0"
combo 'sn'  '1' 'claude-sonnet-5-5' 'ultrathink' "$CARRY1"
combo 'op'  '0' 'claude-opus-5-5'  'none'       "$CARRY0"
combo 'op'  '1' 'claude-opus-5-5'  'ultrathink' "$CARRY1"
combo 'claude-opus-5-5' '1' 'claude-opus-5-5' 'ultrathink' "$CARRY1"
combo 'claude-haiku-4-5' '' 'claude-haiku-4-5' 'none'      "$CARRY0"   # R7 약어가 아닌 값은 건드리지 않는다
grep -q 'claude-sonnet-5-5sn' "$LOG" 2>/dev/null && bad "ⓓ 약어가 값에 붙었다" || true

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
