#!/bin/bash
# ft-mbox.sh — 파일 기반 세션 메시지 큐 래퍼 (fable-team). COMM-GUIDE §1 {mbox}의 실체.
# 본문 = 파일 큐(ft-mbox.py, 유실0), tmux엔 doorbell(recv 트리거)만 주입 — 손상·유실 안전.
# v6-realtime-live mbox.sh 계승 + ft-lib 통합(swap_guard·ROOT 해석)·ft_sess_alive 게이트·ring.
# Usage: ft-mbox.sh {send <to> <from> <body...> [--no-notify] | recv <me> [<from>] | peek <me> | ring <sess>}
set +e
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BINDIR/ft-lib.sh"                       # ft_swap_guard 발동 + ft_sess_alive 등 헬퍼
ROOT="$(ft_resolve_root "")"
export FT_MBOX_DIR="$ROOT/.fable-team/comm" # py 데이터 경로 주입(bin과 데이터 분리)
MBOXPY="$BINDIR/ft-mbox.py"

# 세션명 allowlist(py NAME_RE와 동일) — 세션명이 doorbell send-keys 명령에 삽입되므로 하드 거부.
_check_name() {
  case "$1" in
    ''|*[!A-Za-z0-9._#-]*) echo "BAD_SESSION_NAME $1" >&2; return 1;;
  esac
}

# 세션명 → pane_id 정확 매칭(#-suffix 세션명 send-keys 파싱 함정 회피, v6 계승)
pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

# doorbell: 대상 세션에 recv 트리거만 주입(본문 아님). 전부 non-fatal(본문은 이미 큐에).
# echoes: sent | skipped | absent
doorbell() {
  local to="$1" cap pane
  ft_sess_alive "$to" || { echo absent; return 0; }
  # 상태 판독: 옵션모드(Enter to select)면 skip(Escape 금지 — HIL 프롬프트 파괴 방지, 본문은 큐에 안전).
  # 미제출 잔류(❯ 텍스트)면 C-u로 클리어. capture는 invalid UTF-8 섞임 → LC_ALL=C grep -a 바이트매치(V3).
  cap="$(tmux capture-pane -p -t "$to" 2>/dev/null)"
  if printf '%s\n' "$cap" | LC_ALL=C grep -aq 'Enter to select'; then
    echo skipped; return 0
  fi
  # 이미 동일 recv 트리거가 미제출 대기 중이면 중복 억제(연속 send 시 입력창 큐 폭주 방지).
  # capture는 커서 아래 빈 줄까지 포함하므로 빈 줄 제거 후 마지막 실제 내용 줄만 본다
  # (tail -1만 쓰면 빈 줄을 잡아 dedup이 무력화됨 — 핵심 버그포인트).
  if printf '%s\n' "$cap" | LC_ALL=C grep -av '^[[:space:]]*$' | tail -1 | LC_ALL=C grep -aqF "recv $to"; then
    echo skipped; return 0
  fi
  if printf '%s\n' "$cap" | LC_ALL=C grep -aqE '❯[[:space:]]+[^[:space:]]'; then
    tmux send-keys -t "$to" C-u 2>/dev/null || true; sleep 0.2
  fi
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || { echo absent; return 0; }
  # 고정 명령 문자열 — 가변부는 allowlist 통과 세션명뿐. 짧아서 유실·손상 안전.
  tmux send-keys -t "$pane" -l "bash .fable-team/bin/ft-mbox.sh recv $to" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
  echo sent
}

cmd="${1:-}"; shift || true
case "$cmd" in
  send)
    to="${1:?to}"; from="${2:?from}"; shift 2
    notify=1
    args=(); for a in "$@"; do [ "$a" = "--no-notify" ] && notify=0 || args+=("$a"); done
    # py가 allowlist 검증(BAD_SESSION_NAME + exit 1) + 큐잉. 실패 시 그대로 전파.
    py_out="$(python3 "$MBOXPY" send "$to" "$from" "${args[*]}")" || exit 1
    if [ "$notify" = 1 ]; then db="$(doorbell "$to")"; else db=off; fi
    echo "$py_out doorbell=$db"
    ;;
  recv)  exec python3 "$MBOXPY" recv "${1:?me}" ${2:+"$2"} ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1
         db="$(doorbell "$sess")"; echo "RING $sess doorbell=$db" ;;
  *) echo "usage: ft-mbox.sh {send <to> <from> <body> [--no-notify]|recv <me> [<from>]|peek <me>|ring <sess>}" >&2; exit 2;;
esac
