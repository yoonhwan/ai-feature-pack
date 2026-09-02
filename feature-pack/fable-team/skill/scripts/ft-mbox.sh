#!/bin/bash
# ft-mbox.sh — 파일 기반 세션 메시지 큐 래퍼 (fable-team). COMM-GUIDE §1 {mbox}의 실체.
# 본문 = 파일 큐(ft-mbox.py, 유실0), tmux엔 doorbell(recv 트리거)만 주입 — 손상·유실 안전.
# v6-realtime-live mbox.sh 계승 + ft-lib 통합(swap_guard·ROOT 해석)·ft_sess_alive 게이트·ring.
# Usage: ft-mbox.sh {send <to> <from> <body...> [--no-notify] | recv <me> [<from>] | peek <me> | ring <sess>}
set +e
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BINDIR/ft-lib.sh"                       # ft_swap_guard 발동 + ft_sess_alive 등 헬퍼
# ★2026-08-25 — 여기서 FT_MBOX_DIR 을 «덮어쓰지» 않는다★
# 이전: ROOT 를 cwd 기준(ft_resolve_root)으로 잡아 FT_MBOX_DIR 을 export 했다. 그래서
# (a) 같은 스크립트가 «부른 사람의 cwd» 에 따라 다른 우편함을 썼고 (b) 사용자가 env 로
# 명시한 FT_MBOX_DIR 마저 덮어써서 회피가 불가능했다 — 실제로 메시지 유실이 났다.
# 지금: 경로 결정은 ft-mbox.py 가 «스크립트 위치에서 유도한 정본» 으로 한다.
# ★ft_resolve_root 자체는 안 건드렸다★ — 다른 ft-* 8개가 그 함수를 쓴다(최소 절개).
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
# $2=force(1) 이면 시간 억제를 뚫는다 — 발주는 «반드시» 창에 떠야 한다.
doorbell() {
  local to="$1" dbforce="${2:-0}" cap pane _db_stamp _db_last
  ft_sess_alive "$to" || { echo absent; return 0; }
  # 상태 판독: 옵션모드(Enter to select)면 skip(Escape 금지 — HIL 프롬프트 파괴 방지, 본문은 큐에 안전).
  # 미제출 잔류(❯ 텍스트)면 C-u로 클리어. capture는 invalid UTF-8 섞임 → LC_ALL=C grep -a 바이트매치(V3).
  cap="$(tmux capture-pane -p -t "$to" 2>/dev/null)"
  if printf '%s\n' "$cap" | LC_ALL=C grep -aq 'Enter to select'; then
    echo skipped; return 0
  fi
  # ★억제는 «화면 텍스트»가 아니라 «시간»으로 한다★ — 원래 여기서 tail -1 에 `recv $to` 가
  # 보이면 스킵했는데, 그 조건은 «한 번도 참이 된 적이 없다»(2026-09-01 실측 6좌석 전수).
  # Claude Code UI 는 프롬프트 «아래»에 상태줄이 있어 tail -1 이 늘 `⏵⏵ bypass permissions on …`
  # 이나 힌트 조각 `/r` 을 잡는다 — 입력줄이 아니다. 그래서 매 send 마다 주입이 들어갔고,
  # 그게 사용자 터미널 입력을 막은 두 번째 기제였다. 게다가 이 스킵이 «아래 C-u 클리어보다 앞»에
  # 있어서, 정말로 트리거가 미제출로 걸렸을 때 그걸 치우는 유일한 코드에 영영 도달하지 못했다.
  # 화면 텍스트 매칭은 UI 가 바뀌면 조용히 죽고, 죽어도 증상이 «더 많이 보내는 것»뿐이라 아무도 모른다.
  _db_stamp="${TMPDIR:-/tmp}/mbox-doorbell-$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  _db_last="$(stat -f %m "$_db_stamp" 2>/dev/null || echo 0)"
  if [ "$dbforce" != 1 ] && [ "$(( $(date +%s) - _db_last ))" -lt "${FT_MBOX_DOORBELL_MIN:-3}" ]; then
    echo skipped; return 0
  fi
  : > "$_db_stamp" 2>/dev/null || true
  if printf '%s\n' "$cap" | LC_ALL=C grep -aqE '❯[[:space:]]+[^[:space:]]'; then
    tmux send-keys -t "$to" C-u 2>/dev/null || true; sleep 0.2
  fi
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || { echo absent; return 0; }
  # 고정 명령 문자열 — 가변부는 allowlist 통과 세션명뿐. 짧아서 유실·손상 안전.
  # ★절대경로로 주입한다★ — 상대경로면 수신자의 cwd 에서 해석돼 «보낸 우편함과 다른 곳»을
  # 열거나 아예 파일을 못 찾는다. 유실 기제의 «나머지 절반» 이 여기였다.
  tmux send-keys -t "$pane" -l "bash $BINDIR/ft-mbox.sh recv $to" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
  echo sent
}

cmd="${1:-}"; shift || true
case "$cmd" in
  send)
    to="${1:?to}"; from="${2:?from}"; shift 2
    notify=1; force=(); dbf=0
    args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) notify=0 ;;
        --force)     force=(--force); dbf=1 ;;
        *)           args+=("$a") ;;
      esac
    done
    # py가 allowlist 검증(BAD_SESSION_NAME exit 1) + 발신 가드(BLOCKED exit 3) + 큐잉.
    # 거부되면 doorbell 을 울리지 않는다 — 큐에 들어간 게 없다.
    py_out="$(python3 "$MBOXPY" send "$to" "$from" "${args[*]}" ${force[@]+"${force[@]}"})" || exit $?
    if [ "$notify" = 1 ]; then db="$(doorbell "$to" "$dbf")"; else db=off; fi
    echo "$py_out doorbell=$db"
    ;;
  relay)
    # 긴 본문의 정본 절차: 원문을 RELAY_DIR(기본 /tmp/mbox)로 복사하고 요약+경로만 큐잉.
    to="${1:?to}"; from="${2:?from}"; file="${3:?file}"; shift 3
    notify=1; args=(); force=()
    for a in "$@"; do
      case "$a" in
        --no-notify) notify=0 ;;
        --force)     force=(--force) ;;   # ★F3: relay 도 재발신 탈출구 — 요약 텍스트에 안 섞이게 파싱.
        *)           args+=("$a") ;;
      esac
    done
    py_out="$(python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}" ${force[@]+"${force[@]}"})" || exit $?
    if [ "$notify" = 1 ]; then db="$(doorbell "$to")"; else db=off; fi
    echo "$py_out doorbell=$db"
    ;;
  recv)  me="${1:?me}"; shift; exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  ring)  sess="${1:?sess}"; _check_name "$sess" || exit 1
         db="$(doorbell "$sess")"; echo "RING $sess doorbell=$db" ;;
  *) echo "usage: ft-mbox.sh {send <to> <from> <body> [--no-notify] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>|ring <sess>}" >&2; exit 2;;
esac
