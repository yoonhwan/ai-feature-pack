#!/usr/bin/env bash
# test_successor_open.sh — ft-successor-open.sh (R107): 승계 후계 개설 = 기동 확인(pgrep) → 검증 송신 → 도달 파일.
# 가짜 tmux·tmuxc·pgrep·ft-send-verified·mbox·ft-reach-check(PATH 앞 스텁 + env) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="$HERE/../../scripts/harness-install/fable-team/bin/ft-successor-open.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; BODY="$TMP/body.txt"
mkdir -p "$REPO" "$FAKE"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"; OLD="byz-t-old-claude#1"; NEW="byz-t-new-claude#2"

mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux   'case "$1" in has-session) exit 0;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc  'echo "tmuxc $*" >> "$LOG"; exit "${TMUXC_RC:-0}"'
mkstub pgrep  'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$CNT"; [ "$n" -ge "${PGREP_UP_AT:-3}" ] && { echo 5555; exit 0; }; exit 1'
mkstub send   'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
# 자원 문지기 격리(R218) — 실 머신 압력·실 pressure.tsv 를 재지 않는다: 공통 가짜 센서 헬퍼(압력 1·에이전트 35 · 임시 FT_RES_ROOT).
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"

JDIR="$TMP/home/.claude/projects/$(printf '%s' "$TMP/pane" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
run() { # run <환경 KEY=VAL…> — 호출마다 로그·카운터·도달 파일 초기화. 출력은 $TMP/out, rc 는 $RC
  rm -f "$LOG" "$CNT"; rm -rf "$STATE"; : > "$LOG"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" FT_SO_POLL=0 FT_SO_WAIT_MAX=5 \
      FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$BODY_USE" > "$TMP/out" 2>&1
  RC=$?
}
count() { grep -c "^$1" "$LOG"; }
BODY_USE="$BODY"

# ⓐ 본문 첫 3줄이 비었다 → REJECT · tmuxc·송신 0
printf '\n\n\n본문\n' > "$TMP/blank.txt"; BODY_USE="$TMP/blank.txt"; run
{ [ "$RC" -ne 0 ] && grep -q 'REJECT' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓐ 첫 3줄 빈 값 → REJECT · open·송신 0" || bad "ⓐ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
BODY_USE="$BODY"

# ⓑ pgrep 이 3번째에 뜬다 → 송신은 그 뒤 1회 · 도달 파일
run PGREP_UP_AT=3 SEND_RC=0
order="$(grep -E '^(pgrep|send)$' "$LOG" | tr '\n' ' ')"
{ [ "$RC" -eq 0 ] && [ "$order" = "pgrep pgrep pgrep send " ] && [ -f "$STATE/$OLD.json" ] && grep -q "$NEW" "$STATE/$OLD.json"; } \
  && ok "ⓑ 기동 확인(pgrep 3) → 송신 1회 · 도달 파일" || bad "ⓑ rc=$RC order=$order file=$(ls "$STATE" 2>&1)"

# ⓒ pgrep 상한 초과 → 송신 0 · 도달 파일 0 · exit≠0 · [HIL] 줄
run PGREP_UP_AT=99
{ [ "$RC" -ne 0 ] && [ "$(count send)" = 0 ] && [ ! -e "$STATE/$OLD.json" ] && grep -q '\[HIL\]' "$TMP/out"; } \
  && ok "ⓒ 기동 미확인 → 송신 0 · 도달 파일 0 · [HIL]" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓓ send-verified 5 → ring 1회 → 다시 5 → 도달 파일 0 · exit 5 · 닫기 0 안내
run SEND_RC=5 REACH_RC=5
{ [ "$RC" -eq 5 ] && [ "$(count 'mbox ring')" = 1 ] && [ ! -e "$STATE/$OLD.json" ] && grep -q '\[HIL\]' "$TMP/out" && grep -q '구 좌석 닫기 0' "$TMP/out"; } \
  && ok "ⓓ 5 → ring 1 → 5 → exit 5 · 도달 파일 0 · 닫기 0" || bad "ⓓ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓔ(카드 설계 보정 1 의 시험 ⓕ) 첫 송신 미제출 — send-verified 2 → ring → 도달 확인 0 → 도달 파일
run SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox ring')" = 1 ] && [ -f "$STATE/$OLD.json" ]; } \
  && ok "ⓔ 2 → ring 1 → 도달 → 도달 파일 · exit 0" || bad "ⓔ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓕ tmuxc open 실패 → REJECT · pgrep·송신 0
run TMUXC_RC=1
{ [ "$RC" -ne 0 ] && grep -q 'REJECT' "$TMP/out" && [ "$(count pgrep)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓕ open 실패 → REJECT · 기동 확인·송신 0" || bad "ⓕ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓖ 새 좌석 jsonl 에 SessionStart 가 있으면 «관측», 없으면 상한까지 기다린 뒤 «미관측» 을 드러내고 송신(도달 판정은 send-verified 몫)
mkdir -p "$JDIR"
printf '{"type":"agent-name","agentName":"%s"}\n{"hookEvent":"SessionStart"}\n' "$NEW" > "$JDIR/s.jsonl"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q 'SessionStart 관측' "$TMP/out" && ! grep -q '미관측' "$TMP/out"; } \
  && ok "ⓖ SessionStart 레코드 있음 → 관측 후 송신" || bad "ⓖ rc=$RC out=$(cat "$TMP/out")"
rm -f "$JDIR/s.jsonl"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q 'SessionStart 미관측' "$TMP/out" && [ "$(count send)" = 1 ]; } \
  && ok "ⓖ SessionStart 없음 → 미관측 표시 · 송신 1회" || bad "ⓖ' rc=$RC out=$(cat "$TMP/out")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
