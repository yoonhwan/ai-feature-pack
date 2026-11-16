#!/usr/bin/env bash
# ft-session-close-ledger.sh — r2101 세션 닫힘 원장: tmux session-closed hook 줄(언제 · 어느 세션) + 닫기 도구 줄(누가 · 왜)을 한 원장에 남기고 짝지어 읽는다
#   note <세션> <도구> <사유>      tool 줄 1개(좌석 = env FT_SEAT 또는 «-» · 세션 id = 이름이 글자 그대로 같은 tmux 세션의 #{session_id} 또는 «-» · 호출 pid = 부른 프로세스)
#   fail <세션> <도구>             fail 줄 1개(사유 «kill 실패» · id «-» · tmux 호출 0) — 닫기 도구의 kill-session 실패 갈래 맨 앞
#                                  note · fail: rc 0 · 원장 쓰기 실패 = stderr «판정 불가 원장 쓰기 실패 <경로>» rc 1
#   hook <세션 id> <세션 이름>     hook 줄 1개(도구 · 좌석 · 사유 · pid 칸 «-») · 인자가 2개가 아니면 줄 0 · 화면 출력 0 · 언제나 rc 0
#   hook-on | hook-off             전역 session-closed 에 내 줄 1개를 보탠다(같은 줄 있으면 보탬 0) | 내 줄만 뺀다 — 남의 hook 줄은 그대로
#                                  내 줄 = run-shell -b "<이 파일> hook #{q:hook_session} #{q:hook_session_name}"(q: = 값마다 sh 인자 1개 · 셸 글로 읽지 않음)
#   hook-status                    «HOOK on» 또는 «HOOK off» 1줄 · tmux 조회 실패 = «판정 불가 …» 1줄 rc 1
#   read [--since <ISO>] [--session <이름>]   짝 읽기 = 같은 폴더 ft_session_close_read.py(차례 ⓐ fail · ⓑ hook 짝 · ⓒ 짝 없는 tool · 끝 줄)
#   원장 = env FT_SESSION_CLOSE_LEDGER 또는 <데이터 루트>/.fable-team/state/session-close/ledger.tsv(일반 파일 · 추가 전용)
#   한 줄 = 탭 8칸 «시각(ISO 초) · 종류(hook|tool|fail) · 세션 · 도구 · 좌석 · 사유 · 세션 id · 호출 pid» · 값 속 탭 · CR · LF = 글자마다 공백 1개 · 줄 하나 = 쓰기 1번
#   알려진 한계: kill-server · 마지막 세션 닫힘 · pid 죽이기 · 만든 스크립트 안의 kill-session 은 줄이 안 남거나 «도구 줄 없음» · hook 은 tmux 서버가 다시 뜨면 꺼진다(hook-status)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
HOOK_CMD="run-shell -b \"$SELF hook #{q:hook_session} #{q:hook_session_name}\""
usage() { echo "usage: $0 note <세션> <도구> <사유> | fail <세션> <도구> | hook <세션 id> <세션 이름> | hook-on | hook-off | hook-status | read [--since <ISO>] [--session <이름>]" >&2; exit 2; }

ledger_path() {
  if [ -n "${FT_SESSION_CLOSE_LEDGER:-}" ]; then printf '%s\n' "$FT_SESSION_CLOSE_LEDGER"; return 0; fi
  local d; d="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" && [ -n "$d" ] || return 1
  printf '%s\n' "$d/.fable-team/state/session-close/ledger.tsv"
}
cell() { local v="${1//$'\t'/ }"; v="${v//$'\n'/ }"; v="${v//$'\r'/ }"; printf '%s' "${v:--}"; }
put() {   # put <종류> <세션> <도구> <좌석> <사유> <세션 id> <pid> — 한 줄을 printf 1번으로 붙인다
  local f row a
  f="$(ledger_path)" || { echo "판정 불가 원장 쓰기 실패 (데이터 루트 못 풂)" >&2; return 1; }
  row="$(date '+%Y-%m-%dT%H:%M:%S')"; for a in "$@"; do row="$row"$'\t'"$(cell "$a")"; done
  { mkdir -p -- "$(dirname -- "$f")" && printf '%s\n' "$row" >> "$f"; } 2>/dev/null || { echo "판정 불가 원장 쓰기 실패 $f" >&2; return 1; }
}
session_id() {   # 이름이 글자 그대로 같은 세션의 #{session_id}(«$N») · 없음 · 조회 실패 = «-»
  local o; o="$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null)" || { echo -; return 0; }
  printf '%s\n' "$o" | S="$1" awk '{ i = $1; n = $0; sub(/^[^ ]+ /, "", n) } i ~ /^\$[0-9]+$/ && n == ENVIRON["S"] { print i; f = 1; exit } END { if (!f) print "-" }'
}

load_mine() {   # MINE = 전역 session-closed 의 내 줄 번호(큰 것부터) · 조회 실패 = «판정 불가» 1줄 + exit 1
  local o; o="$(tmux show-hooks -g session-closed 2>&1)" || { echo "판정 불가 tmux 조회 실패: ${o%%$'\n'*}"; exit 1; }
  MINE="$(printf '%s\n' "$o" | HC="$HOOK_CMD" awk '{ i = index($0, "] "); if (i == 0) next; if (substr($0, i + 2) != ENVIRON["HC"]) next
    n = substr($0, index($0, "[") + 1); print substr(n, 1, index(n, "]") - 1) }' | sort -rn)"
}
hook_on() {
  load_mine
  [ -n "$MINE" ] || tmux set-hook -ag session-closed "$HOOK_CMD" 2>/dev/null || { echo "판정 불가 tmux set-hook 실패"; exit 1; }
  echo "HOOK on"
}
hook_off() {
  local i; load_mine
  for i in $MINE; do tmux set-hook -gu "session-closed[$i]" 2>/dev/null || { echo "판정 불가 tmux set-hook -u 실패"; exit 1; }; done
  echo "HOOK off"
}
hook_status() {
  load_mine
  if [ -n "$MINE" ]; then echo "HOOK on"; else echo "HOOK off"; fi
}
read_ledger() {
  local since="" sess="" f
  while [ $# -gt 0 ]; do case "$1" in --since) since="${2:-}"; shift 2 || usage;; --session) sess="${2:-}"; shift 2 || usage;; *) usage;; esac; done
  f="$(ledger_path)" || { echo "판정 불가 원장 경로 못 풂(데이터 루트)"; exit 1; }
  python3 "$HERE/ft_session_close_read.py" "$f" "$since" "$sess"
}

case "${1:-}" in
  note) [ $# -eq 4 ] || usage; put tool "$2" "$3" "${FT_SEAT:-}" "$4" "$(session_id "$2")" "$PPID" || exit 1;;
  fail) [ $# -eq 3 ] || usage; put fail "$2" "$3" "${FT_SEAT:-}" "kill 실패" - "$PPID" || exit 1;;
  hook) [ $# -eq 3 ] && put hook "$3" - - - "$2" - >/dev/null 2>&1; exit 0;;
  hook-on) hook_on;;
  hook-off) hook_off;;
  hook-status) hook_status;;
  read) shift; read_ledger "$@";;
  *) usage;;
esac
