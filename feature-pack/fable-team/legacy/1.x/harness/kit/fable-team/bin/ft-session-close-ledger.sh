#!/usr/bin/env bash
# ft-session-close-ledger.sh — r2101 세션 닫힘 원장: tmux session-closed hook 줄(언제 · 어느 세션) + 닫기 도구 줄(누가 · 왜)을 한 원장에 남기고 짝지어 읽는다
#   note <세션> <도구> <사유>      tool 줄 1개(좌석 = env FT_SEAT 또는 «-» · 세션 id = 이름이 글자 그대로 같은 tmux 세션의 #{session_id} 또는 «-» · 호출 pid = 부른 프로세스)
#                                  env FT_SESSION_CLOSE_ID 가 있으면 그 값을 세션 id 칸에 그대로(note 안 tmux 호출 0 · 닫기 도구가 kill 바로 앞에서 부를 때)
#   id <세션>                    그 이름의 세션 id 1줄(«$N» 또는 «-» · 언제나 rc 0) — note 의 세션 id 읽기를 먼저 해 둘 때(r2101 DA 구현 R1)
#   fail <세션> <도구>             fail 줄 1개(사유 «kill 실패» · id «-» · tmux 호출 0) — 닫기 도구의 kill-session 실패 갈래 맨 앞
#                                  note · fail: rc 0 · 원장 쓰기 실패 = stderr «판정 불가 원장 쓰기 실패 <경로>» rc 1
#   hook <세션 id> <세션 이름>     hook 줄 1개(도구 · 좌석 · 사유 · pid 칸 «-») · 인자가 2개가 아니면 줄 0 · 화면 출력 0 · 언제나 rc 0
#   hook-on | hook-off             hook-on = 그 자리에서 원장 경로를 풀어 내 줄에 박는다(r2119 C1) · 옛 꼴 · 다른 경로 내 줄은 빼고 1개만(같은 경로 줄 있으면 바꿈 0)
#                                  · 60초 넘은 <원장>.lock 1개 회수(«잠금 회수») · 경로 못 풂 = «판정 불가 원장 경로 못 풂» rc 1 · set-hook 0 | hook-off = 내 줄(옛 꼴 · 새 꼴) 모두 뺀다 — 남의 hook 줄은 그대로
#                                  내 줄 = run-shell -b "FT_SESSION_CLOSE_LEDGER_HEX=<원장 경로 16진> bash <이 파일> hook #{q:hook_session} #{q:hook_session_name}"
#                                  (16진 = tmux · sh 를 거쳐도 경로 1개 · q: = 값마다 sh 인자 1개 · 셸 글로 읽지 않음) · 옛 꼴(r2101) = 16진 칸 없는 같은 줄
#   hook-status                    «HOOK on <경로>»(60초 넘은 잠금 = 끝 «· 잠금 남음 <초>초») · «HOOK on 경로 없음(옛 줄)» · «HOOK off» 1줄 · tmux 조회 실패 = «판정 불가 …» 1줄 rc 1
#   read [--since <ISO>] [--session <이름>]   짝 읽기 = 같은 폴더 ft_session_close_read.py(차례 ⓐ fail · ⓑ hook 짝 «후보 ←»(확정 아님) · ⓒ 짝 없는 tool · 끝 줄)
#   원장 = env FT_SESSION_CLOSE_LEDGER_HEX(hook 줄이 박은 경로) · env FT_SESSION_CLOSE_LEDGER · <데이터 루트>/.fable-team/state/session-close/ledger.tsv 차례(일반 파일 · 추가 전용)
#   회전(r2119 C4) = 쓰기 전 크기 ≥ 상한(env FT_SESSION_CLOSE_LEDGER_MAX_KB · 기본 512 KiB)이면 잠금(<원장>.lock 폴더) 안에서 크기를 다시 본 뒤 <원장>.1 로 옮김(옛 .1 덮음)
#     잠금 못 잡음 = 회전 0 · 쓰기는 그대로 · 잠금은 잡은 프로세스만 지운다(남의 잠금은 나이와 무관하게 그대로 · 회수 = hook-on) · read = .1 다음 본 원장
#   한 줄 = 탭 8칸 «시각(ISO 초) · 종류(hook|tool|fail) · 세션 · 도구 · 좌석 · 사유 · 세션 id · 호출 pid» · 값 속 탭 · CR · LF = 글자마다 공백 1개 · 줄 하나 = 쓰기 1번
#   알려진 한계: kill-server · 마지막 세션 닫힘 · pid 죽이기 · 만든 스크립트 안의 kill-session 은 줄이 안 남거나 «도구 줄 없음» · hook 은 tmux 서버가 다시 뜨면 꺼진다(hook-status)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
HOOK_TAIL="bash $SELF hook #{q:hook_session} #{q:hook_session_name}\""
HOOK_OLD="run-shell -b \"$HOOK_TAIL"; HOOK_HEAD="run-shell -b \"FT_SESSION_CLOSE_LEDGER_HEX="
usage() { echo "usage: $0 note <세션> <도구> <사유> | id <세션> | fail <세션> <도구> | hook <세션 id> <세션 이름> | hook-on | hook-off | hook-status | read [--since <ISO>] [--session <이름>]" >&2; exit 2; }

hexof() { printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'; }
unhex() { local h="$1" i o=""; [[ "$h" =~ ^([0-9a-f][0-9a-f])+$ ]] || return 1; for ((i = 0; i < ${#h}; i += 2)); do o="$o\\x${h:i:2}"; done; printf '%b' "$o"; }
hook_cmd() { printf '%s' "$HOOK_HEAD$1 $HOOK_TAIL"; }   # $1 = 원장 경로 16진
ledger_path() {
  if [ -n "${FT_SESSION_CLOSE_LEDGER_HEX:-}" ]; then unhex "$FT_SESSION_CLOSE_LEDGER_HEX" && echo; return; fi
  if [ -n "${FT_SESSION_CLOSE_LEDGER:-}" ]; then printf '%s\n' "$FT_SESSION_CLOSE_LEDGER"; return 0; fi
  local d; d="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" && [ -n "$d" ] || return 1
  printf '%s\n' "$d/.fable-team/state/session-close/ledger.tsv"
}
cell() { local v="${1//$'\t'/ }"; v="${v//$'\n'/ }"; v="${v//$'\r'/ }"; printf '%s' "${v:--}"; }
put() {   # put <종류> <세션> <도구> <좌석> <사유> <세션 id> <pid> — 한 줄을 printf 1번으로 붙인다
  local f row a
  f="$(ledger_path)" || { echo "판정 불가 원장 쓰기 실패 (데이터 루트 못 풂)" >&2; return 1; }
  row="$(date '+%Y-%m-%dT%H:%M:%S')"; for a in "$@"; do row="$row"$'\t'"$(cell "$a")"; done
  { mkdir -p -- "$(dirname -- "$f")" && { rotate "$f"; printf '%s\n' "$row" >> "$f"; }; } 2>/dev/null || { echo "판정 불가 원장 쓰기 실패 $f" >&2; return 1; }
}
fsize() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
lock_age() { local m; m="$(stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null)" && [ -n "$m" ] || return 1; echo $(( $(date +%s) - m )); }
LOCK=""
rotate() {   # rotate <원장> — 상한 이상이면 잠금 안에서 크기를 다시 보고 .1 로 옮긴다 · 실패 = 회전 0(쓰기는 부르는 쪽이 그대로)
  local f="$1" kb="${FT_SESSION_CLOSE_LEDGER_MAX_KB:-512}"; case "$kb" in ''|*[!0-9]*) kb=512;; esac
  [ "$(fsize "$f")" -ge $((kb * 1024)) ] || return 0
  mkdir -- "$f.lock" 2>/dev/null || return 0
  LOCK="$f.lock"; trap 'rmdir -- "$LOCK" 2>/dev/null' EXIT
  [ "$(fsize "$f")" -ge $((kb * 1024)) ] && mv -f -- "$f" "$f.1"
  rmdir -- "$LOCK" 2>/dev/null; LOCK=""; trap - EXIT; return 0
}
session_id() {   # 이름이 글자 그대로 같은 세션의 #{session_id}(«$N») · 없음 · 조회 실패 = «-»
  local o; o="$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null)" || { echo -; return 0; }
  printf '%s\n' "$o" | S="$1" awk '{ i = $1; n = $0; sub(/^[^ ]+ /, "", n) } i ~ /^\$[0-9]+$/ && n == ENVIRON["S"] { print i; f = 1; exit } END { if (!f) print "-" }'
}

load_mine() {   # MINE = 전역 session-closed 의 내 줄 «번호 16진»(옛 꼴 = «-» · 큰 번호부터) · 조회 실패 = «판정 불가» 1줄 + exit 1
  local o; o="$(tmux show-hooks -g session-closed 2>&1)" || { echo "판정 불가 tmux 조회 실패: ${o%%$'\n'*}"; exit 1; }
  MINE="$(printf '%s\n' "$o" | HO="$HOOK_OLD" HH="$HOOK_HEAD" HT=" $HOOK_TAIL" awk '{ i = index($0, "] "); if (i == 0) next; c = substr($0, i + 2)
    n = substr($0, index($0, "[") + 1); n = substr(n, 1, index(n, "]") - 1); hh = ENVIRON["HH"]; ht = ENVIRON["HT"]
    if (c == ENVIRON["HO"]) { print n, "-"; next }
    if (length(c) > length(hh) + length(ht) && substr(c, 1, length(hh)) == hh && substr(c, length(c) - length(ht) + 1) == ht) {
      x = substr(c, length(hh) + 1, length(c) - length(hh) - length(ht)); if (x ~ /^[0-9a-f]+$/) print n, x } }' | sort -rn)"
}
unhook() { tmux set-hook -gu "session-closed[$1]" 2>/dev/null || { echo "판정 불가 tmux set-hook -u 실패"; exit 1; }; }
hook_on() {
  local f h i x keep="" a
  f="$(ledger_path)" && [ -n "$f" ] || { echo "판정 불가 원장 경로 못 풂"; exit 1; }
  case "$f" in /*) ;; *) f="$PWD/$f";; esac
  h="$(hexof "$f")"; load_mine
  while read -r i x; do [ -n "$i" ] || continue
    if [ -z "$keep" ] && [ "$x" = "$h" ]; then keep="$i"; else unhook "$i"; fi
  done <<< "$MINE"
  [ -n "$keep" ] || tmux set-hook -ag session-closed "$(hook_cmd "$h")" 2>/dev/null || { echo "판정 불가 tmux set-hook 실패"; exit 1; }
  a="$(lock_age "$f.lock")" && [ "$a" -gt 60 ] && rmdir -- "$f.lock" 2>/dev/null && echo "잠금 회수 $f.lock (${a}초)"
  echo "HOOK on $f"
}
hook_off() {
  local i x; load_mine
  while read -r i x; do [ -z "$i" ] || unhook "$i"; done <<< "$MINE"
  echo "HOOK off"
}
hook_status() {   # 새 꼴 줄(큰 번호) > 옛 꼴 > 없음
  local i x f a; load_mine
  while read -r i x; do [ -n "$x" ] && [ "$x" != - ] || continue
    f="$(unhex "$x")" || continue; a="$(lock_age "$f.lock")" && [ "$a" -gt 60 ] && f="$f · 잠금 남음 ${a}초"
    echo "HOOK on $f"; return 0
  done <<< "$MINE"
  if [ -n "$MINE" ]; then echo "HOOK on 경로 없음(옛 줄)"; else echo "HOOK off"; fi
}
read_ledger() {
  local since="" sess="" f
  while [ $# -gt 0 ]; do case "$1" in --since) since="${2:-}"; shift 2 || usage;; --session) sess="${2:-}"; shift 2 || usage;; *) usage;; esac; done
  f="$(ledger_path)" || { echo "판정 불가 원장 경로 못 풂(데이터 루트)"; exit 1; }
  python3 "$HERE/ft_session_close_read.py" "$f" "$since" "$sess"
}

case "${1:-}" in
  note) [ $# -eq 4 ] || usage; put tool "$2" "$3" "${FT_SEAT:-}" "$4" "${FT_SESSION_CLOSE_ID-$(session_id "$2")}" "$PPID" || exit 1;;
  id) [ $# -eq 2 ] || usage; session_id "$2";;
  fail) [ $# -eq 3 ] || usage; put fail "$2" "$3" "${FT_SEAT:-}" "kill 실패" - "$PPID" || exit 1;;
  hook) [ $# -eq 3 ] && put hook "$3" - - - "$2" - >/dev/null 2>&1; exit 0;;
  hook-on) hook_on;;
  hook-off) hook_off;;
  hook-status) hook_status;;
  read) shift; read_ledger "$@";;
  *) usage;;
esac
