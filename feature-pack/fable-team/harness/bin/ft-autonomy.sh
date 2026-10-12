#!/usr/bin/env bash
# ft-autonomy.sh — 자율 대리 결정 모드 on/off/status (판정 1314·1322 · DESIGN-autonomy-proxy-decision r3 §1·§2)
#   on | off     오빠 `!` 한 줄(ft-hil.sh --add 가 돌려주는 `! bash /tmp/h<N>`)로만 부른다 — 좌석 경로 0
#   status       `[자율 ON A7 · 23:41~ · 대리 3 · 큐 1]` / `[자율 OFF]` / `[자율 ?? 위변조 → OFF]`
#   mode | event 기계용: on|off|tamper · 현재(또는 마지막) 사건 번호 A<N>
# 상태 = $STATE/autonomy.json {mode,since,event} + 추가 전용 autonomy.log (한 줄 = epoch<TAB>on|off<TAB>A<N>)
# 이 스크립트만 log 를 쓴다 → json 이 log 마지막 줄과 어긋나면 위변조 = OFF 취급. 시간 창·자동 해제 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(cd "$HERE/../.." && pwd)}"
STATE="${FT_AUTONOMY_STATE_DIR:-$ROOT/.fable-team/state}"
PLANNER="${FT_PLANNER_DIR:-$ROOT/design/planner}"
JSON="$STATE/autonomy.json"; LOG="$STATE/autonomy.log"; QUEUE="$PLANNER/AUTONOMY-QUEUE.md"

jfield() {  # <키> — autonomy.json 한 줄 값(문자열·숫자)
  sed -n "s/.*\"$1\": *\"\{0,1\}\([A-Za-z0-9]*\)\"\{0,1\}[,}].*/\1/p" "$JSON" 2>/dev/null | head -1
}

hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo "--:--"; }

# 유효 상태 → "on|off|tamper" (파일 없음 = off)
mode() {
  local m s e last
  [ -f "$JSON" ] || { echo off; return; }
  m="$(jfield mode)"; s="$(jfield since)"; e="$(jfield event)"
  last="$(tail -n 1 "$LOG" 2>/dev/null)"
  if [ -n "$m" ] && [ "$last" = "$(printf '%s\t%s\t%s' "$s" "$m" "$e")" ] && { [ "$m" = on ] || [ "$m" = off ]; }; then
    echo "$m"
  else
    echo tamper
  fi
}

# 마지막 사건 번호(마지막 log 줄) — 없으면 빈 값
event() { tail -n 1 "$LOG" 2>/dev/null | cut -f3; }

count_proxy() {  # <A<N>> — 판정 원장의 대리 줄 수
  local n; n="$(cat "$PLANNER"/VERDICTS-*.md 2>/dev/null | grep -cF "[대리 · 자율 ON $1]")"; echo "${n:-0}"
}
count_queue() { local n; n="$(grep -cF "| $1 |" "$QUEUE" 2>/dev/null)"; echo "${n:-0}"; }

status() {
  local m e s
  m="$(mode)"
  case "$m" in
    tamper) echo "[자율 ?? 위변조 → OFF]" ;;
    off) echo "[자율 OFF]" ;;
    on) e="$(jfield event)"; s="$(jfield since)"
        echo "[자율 ON $e · $(hhmm "$s")~ · 대리 $(count_proxy "$e") · 큐 $(count_queue "$e")]" ;;
  esac
}

write_state() {  # <모드> <사건> — log 먼저, json 은 임시 파일 → mv (json 이 log 를 앞서지 않는다)
  local now; now="$(date +%s)"
  mkdir -p "$STATE" || { echo "REJECT 상태 폴더를 못 만들었다: $STATE" >&2; exit 1; }
  printf '%s\t%s\t%s\n' "$now" "$1" "$2" >> "$LOG" || { echo "REJECT log 쓰기 실패" >&2; exit 1; }
  printf '{"mode":"%s","since":%s,"event":"%s"}\n' "$1" "$now" "$2" > "$JSON.tmp" && mv "$JSON.tmp" "$JSON"
}

cmd_on() {
  local n
  if [ "$(mode)" = on ]; then status; return 0; fi
  n="$(grep -c "$(printf '\ton\t')" "$LOG" 2>/dev/null)"
  write_state on "A$(( ${n:-0} + 1 ))"
  status
}

cmd_off() {
  local ev; ev="$(event)"
  if [ "$(mode)" = off ] && [ -f "$JSON" ]; then echo "[자율 OFF] (이미 OFF)"; return 0; fi
  if [ ! -f "$JSON" ] && [ -z "$ev" ]; then echo "[자율 OFF] (이미 OFF)"; return 0; fi
  [ -n "$ev" ] || ev="A0"
  write_state off "$ev"
  echo "[자율 OFF] $ev 구간 요약: 대리 $(count_proxy "$ev") · 큐 $(count_queue "$ev") · 큐 파일 $QUEUE"
}

case "${1:-}" in
  on) cmd_on ;;
  off) cmd_off ;;
  status) status ;;
  mode) mode ;;
  event) event ;;
  *) echo "usage: ft-autonomy.sh on|off|status|mode|event" >&2; exit 2 ;;
esac
