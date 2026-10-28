#!/usr/bin/env bash
# test_successor_open_ctx_r1060.sh — ft-successor-open.sh r1060: `--ctx` 는 창 크기 꼴(^[0-9]+m$)만 받는다.
#   실사건(planner#152<｜begin▁of▁sentence｜>// 2026-10-28 17:00): 호출자가 창 크기 자리에 «지금 쓴 토큰 수» 554k 를 넣어 tmuxc 가 모델을
#   claude-sonnet-5-5[554k] 로 만들었고 API 가 400 으로 거절했다. 도구는 값을 보지 않고 넘겼다.
#   계약 R1~R5(카드 r1060 반례 집합) · 가짜 tmux·tmuxc·pgrep·send·mbox·reach(PATH 스텁) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="${FT_SO_PATH:-$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# 변이 2종 — check = «값 검사 줄 삭제»(→ R1 빨강이어야 한다) · shape = «꼴 검사를 숫자만(^[0-9]+$)으로»(→ R2 빨강이어야 한다)
if [ -n "${FT_SO_CTX_MUTATE:-}" ]; then
  MUTBIN="$TMP/mutbin"; mkdir -p "$MUTBIN"; cp -R "$(dirname -- "$SO")/." "$MUTBIN/"; MUT="$MUTBIN/$(basename -- "$SO")"
  python3 - "$SO" "$MUT" "$FT_SO_CTX_MUTATE" <<'PYMUT' || { echo "FAIL 변이 적용 실패: $FT_SO_CTX_MUTATE"; exit 1; }
import sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read()
if mode == "check":                       # 값 검사(거절) 줄만 지운다 → 틀린 값이 그대로 통과한다
    out = "\n".join(l for l in text.splitlines() if '[ "$_ctx_bad" = 0 ] ||' not in l) + "\n"
    if out == text: print("변이 check 대상 줄 없음"); sys.exit(1)
elif mode == "shape":                     # 꼴 검사에서 «m» 요구를 없앤다(= ^[0-9]+$ 와 같은 효과) → 1m 이 거절된다
    old = '    *m) _ctx_pre="${CTX%m}";'
    if old not in text: print("변이 shape 대상 줄 없음"); sys.exit(1)
    out = text.replace(old, '    *) _ctx_pre="$CTX";')
else:
    print("모르는 변이: %s" % mode); sys.exit(1)
open(dst, "w", encoding="utf-8").write(out)
PYMUT
  SO="$MUT"
fi
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; BODY="$TMP/body.txt"
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
mkstub send   'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"
mkdir -p "$REPO/.fable-team" "$TMP/live-root"; printf '%s\n' "$TMP/live-root" > "$REPO/.fable-team/LIVE_ROOT"
OLD='byz-t-harness-nano-claude#1'; NEW='byz-t-harness-nano-claude#2'
# run <에이전트> [추가 인자…] — --ctx 는 호출자가 준 그대로 넘긴다(생략·빈 값 포함)
run() {
  local agent="$1"; shift
  rm -f "$LOG" "$CNT" "$OPENED"; rm -rf "$STATE"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" \
      bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent "$agent" --model claude-sonnet-5-5 "$@" --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
count() { cat "$LOG" 2>/dev/null | grep -c "^$1" || true; }
# rej <설명> <--ctx 인자…> — rc2 · «REJECT --ctx» 1줄 · tmuxc 0 · 송신 0 · 도달 파일 0 (옛 좌석·명부·쪽지 손 0)
rej() {
  local label="$1"; shift
  run claude "$@"
  { [ "$RC" -eq 2 ] && grep -q 'REJECT --ctx 는 창 크기' "$TMP/out" && [ "$(count tmuxc)" = 0 ] \
    && [ "$(count send)" = 0 ] && [ "$(count 'mbox')" = 0 ] && [ ! -e "$STATE/$OLD.json" ]; } \
    && ok "$label rc2 · REJECT 1줄 · tmuxc·송신·쪽지 0 · 도달 파일 0" \
    || bad "$label rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"
}

# R1 토큰 사용량(554k) → 거절
rej "R1 --ctx 554k →" --ctx 554k
# R4 꼴 밖(대소문자·단위 없음·꼬리 붙음·앞 공백) → 거절
rej "R4-1 --ctx 1M →" --ctx 1M
rej "R4-2 --ctx 1 →" --ctx 1
rej "R4-3 --ctx m →" --ctx m
rej "R4-4 --ctx 1m5 →" --ctx 1m5
rej "R4-5 --ctx ' 1m' →" --ctx ' 1m'
# R5 agent≠claude 라도 틀린 값은 거절(맞는 값의 무시 규칙은 아래 R2 그대로)
run codex --ctx 554k
{ [ "$RC" -eq 2 ] && grep -q 'REJECT --ctx 는 창 크기' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "R5 --agent codex --ctx 554k → rc2 · tmuxc·송신 0" \
  || bad "R5 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"

# R2 맞는 값(1m) → 지금처럼 tmuxc 에 --ctx 1m
run claude --ctx 1m
{ [ "$RC" -eq 0 ] && grep -q -- '--ctx 1m' "$LOG" && [ "$(count tmuxc)" = 1 ] && [ -e "$STATE/$OLD.json" ]; } \
  && ok "R2 --ctx 1m → rc0 · tmuxc --ctx 1m · 도달 파일 기록" \
  || bad "R2 rc=$RC log=$(tr '\n' ' ' < "$LOG" 2>/dev/null) out=$(cat "$TMP/out")"

# R3 생략·빈 값 → --ctx 안 넘김(지금과 같음)
run claude
A_RC=$RC; A_CTX="$(cat "$LOG" 2>/dev/null | grep -c -- '--ctx' || true)"; A_OPEN="$(count tmuxc)"
run claude --ctx ''
B_CTX="$(cat "$LOG" 2>/dev/null | grep -c -- '--ctx' || true)"
{ [ "$A_RC" -eq 0 ] && [ "$A_CTX" = 0 ] && [ "$A_OPEN" = 1 ] && [ "$RC" -eq 0 ] && [ "$B_CTX" = 0 ] && [ "$(count tmuxc)" = 1 ]; } \
  && ok "R3 생략·빈 값 → rc0 · tmuxc 호출에 --ctx 0" \
  || bad "R3 생략 rc=$A_RC ctx=$A_CTX open=$A_OPEN · 빈 값 rc=$RC ctx=$B_CTX log=$(tr '\n' ' ' < "$LOG" 2>/dev/null)"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
