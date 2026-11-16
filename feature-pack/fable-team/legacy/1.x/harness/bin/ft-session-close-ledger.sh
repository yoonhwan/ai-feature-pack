#!/usr/bin/env bash
# ft-session-close-ledger.sh — r2101 세션 닫힘 원장: tmux session-closed hook 줄(언제 · 어느 세션) + 닫기 도구 줄(누가 · 왜)을 한 원장에 남기고 짝지어 읽는다
#   note <세션> <도구> <사유>      tool 줄 1개(좌석 칸 = env FT_SEAT · 없으면 «-») · rc 0 · 원장 쓰기 실패 = stderr «판정 불가 원장 쓰기 실패 <경로>» rc 1
#   hook <세션>                    hook 줄 1개(도구 · 좌석 · 사유 칸 «-») · 화면 출력 0 · 언제나 rc 0
#   hook-on | hook-off             전역 session-closed 에 내 줄 1개를 보탠다(같은 줄 있으면 보탬 0) | 내 줄만 뺀다 — 남의 hook 줄은 그대로
#   hook-status                    «HOOK on» 또는 «HOOK off» 1줄 · tmux 조회 실패 = «판정 불가 …» 1줄 rc 1
#   read [--since <ISO>] [--session <이름>]   hook 줄마다 1줄(짝 = 같은 세션 tool 줄이 hook 앞 60초 ~ 뒤 5초 · tool 줄 하나는 가장 가까운 hook 하나와만)
#                                  + 짝 없는 tool 줄 «hook 줄 없음(<도구>)» + 끝 줄 «닫힘 N · 도구 줄 있음 a · 도구 줄 없음 b · hook 줄 없음 c · 깨진 줄 d» · 원장 없음 = 끝 줄만 rc 0
#   원장 = env FT_SESSION_CLOSE_LEDGER 또는 <데이터 루트>/.fable-team/state/session-close/ledger.tsv(일반 파일 · 추가 전용)
#   한 줄 = 탭 6칸 «시각(ISO 초) · 종류(hook|tool) · 세션 · 도구 · 좌석 · 사유» · 값 속 탭·줄바꿈 = 공백 · 줄 하나 = 쓰기 1번
#   알려진 한계: kill-server · pid 죽이기 · 만든 스크립트 안의 kill-session 으로 닫힌 세션은 «도구 줄 없음» 으로 보인다 · hook 은 tmux 서버가 다시 뜨면 꺼진다(hook-status)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SELF="$HERE/$(basename -- "${BASH_SOURCE[0]:-$0}")"
HOOK_CMD="run-shell -b \"$SELF hook #{hook_session_name}\""
usage() { echo "usage: $0 note <세션> <도구> <사유> | hook <세션> | hook-on | hook-off | hook-status | read [--since <ISO>] [--session <이름>]" >&2; exit 2; }

ledger_path() {
  if [ -n "${FT_SESSION_CLOSE_LEDGER:-}" ]; then printf '%s\n' "$FT_SESSION_CLOSE_LEDGER"; return 0; fi
  local d; d="$(. "$HERE/ft-harness-root.sh" && ft_data_root "$HERE" 2>/dev/null)" && [ -n "$d" ] || return 1
  printf '%s\n' "$d/.fable-team/state/session-close/ledger.tsv"
}
cell() { local v="${1//$'\t'/ }"; v="${v//$'\n'/ }"; v="${v//$'\r'/ }"; printf '%s' "${v:--}"; }
put() {   # put <종류> <세션> <도구> <좌석> <사유> — 한 줄을 printf 1번으로 붙인다
  local f row
  f="$(ledger_path)" || { echo "판정 불가 원장 쓰기 실패 (데이터 루트 못 풂)" >&2; return 1; }
  row="$(date '+%Y-%m-%dT%H:%M:%S')"$'\t'"$1"$'\t'"$(cell "$2")"$'\t'"$(cell "$3")"$'\t'"$(cell "$4")"$'\t'"$(cell "$5")"
  { mkdir -p -- "$(dirname -- "$f")" && printf '%s\n' "$row" >> "$f"; } 2>/dev/null || { echo "판정 불가 원장 쓰기 실패 $f" >&2; return 1; }
}

load_mine() {   # MINE = 전역 session-closed 의 내 줄 번호(큰 것부터) · 조회 실패 = «판정 불가» 1줄 + exit 1
  local o; o="$(tmux show-hooks -g session-closed 2>&1)" || { echo "판정 불가 tmux 조회 실패: ${o%%$'\n'*}"; exit 1; }
  MINE="$(printf '%s\n' "$o" | my_index)"
}
my_index() {    # stdin = show-hooks 줄 → 내 줄의 번호(큰 것부터)
  HC="$HOOK_CMD" awk '{ i = index($0, "] "); if (i == 0) next; if (substr($0, i + 2) != ENVIRON["HC"]) next
    n = substr($0, index($0, "[") + 1); print substr(n, 1, index(n, "]") - 1) }' | sort -rn
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
  python3 - "$f" "$since" "$sess" <<'PY'
import datetime as D, sys
path, since, sess = sys.argv[1:4]
def when(s):
    try: w = D.datetime.fromisoformat(s)
    except ValueError: return None
    return w.astimezone().replace(tzinfo=None) if w.tzinfo else w
lo = when(since) if since else None
if since and lo is None: print(f"판정 불가 --since 시각 꼴 아님: {since}"); sys.exit(2)
try: lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
except FileNotFoundError: lines = []
except OSError as e: print(f"판정 불가 원장 읽기 실패 {path}: {e.strerror}"); sys.exit(1)
hooks, tools, broken = [], [], 0
for ln in lines:
    if not ln.strip(): continue
    c = ln.split("\t"); w = when(c[0]) if len(c) == 6 else None
    if w is None or c[1] not in ("hook", "tool"): broken += 1; continue
    if (lo and w < lo) or (sess and c[2] != sess): continue
    (hooks if c[1] == "hook" else tools).append((w, c))
cand = sorted((abs((tw - hw).total_seconds()), h, t) for h, (hw, hc) in enumerate(hooks) for t, (tw, tc) in enumerate(tools)
              if hc[2] == tc[2] and -60 <= (tw - hw).total_seconds() <= 5)
pair, used = {}, set()
for _, h, t in cand:
    if h not in pair and t not in used: pair[h] = t; used.add(t)
out = []
for h, (w, c) in enumerate(hooks):
    tc = tools[pair[h]][1] if h in pair else None
    out.append((w, f"{c[0]} {c[2]} ← {tc[3]} · {tc[4]} · {tc[5]}" if tc else f"{c[0]} {c[2]} ← 도구 줄 없음"))
out += [(w, f"{c[0]} {c[2]} ← hook 줄 없음({c[3]})") for t, (w, c) in enumerate(tools) if t not in used]
for _, s in sorted(out, key=lambda x: x[0]): print(s)
print(f"닫힘 {len(hooks)} · 도구 줄 있음 {len(pair)} · 도구 줄 없음 {len(hooks) - len(pair)} · hook 줄 없음 {len(tools) - len(used)} · 깨진 줄 {broken}")
PY
}

case "${1:-}" in
  note) [ $# -eq 4 ] || usage; put tool "$2" "$3" "${FT_SEAT:-}" "$4" || exit 1;;
  hook) put hook "${2:-}" - - - >/dev/null 2>&1; exit 0;;
  hook-on) hook_on;;
  hook-off) hook_off;;
  hook-status) hook_status;;
  read) shift; read_ledger "$@";;
  *) usage;;
esac
