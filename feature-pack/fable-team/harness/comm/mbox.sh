#!/bin/bash
# 파일 기반 세션 메시지 큐 (mbox) — 파일 큐 + push 알림 하이브리드.
# send = 파일 append + 수신자 tmux에 recv 트리거 주입(push). 본문은 파일(유실0), tmux엔 트리거만.
# LIFO·per-to 10 ring·fcntl.flock·consume-on-read·to==me grep.
# Usage: mbox.sh {send <to> <from> <body...> [--no-notify] | recv <me> | peek <me>}
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBOXPY="$DIR/mbox.py"
SELF="$DIR/mbox.sh"

# 세션명 → pane_id 정확 매칭 (#-suffix 세션명 send-keys 파싱 함정 회피)
pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

# doorbell: 대상 pane 에 recv 트리거만 주입(본문 아님). send·relay 가 공유한다.
#
# ★억제는 «화면 텍스트»가 아니라 «시간»으로 한다★ — 원래는 tail -1 에 `recv $to` 가 보이면
# 스킵했는데, 그 조건은 «한 번도 참이 된 적이 없다»(2026-09-01 실측 6좌석 전수). Claude Code UI 는
# 프롬프트 «아래»에 상태줄이 있어 tail -1 이 늘 `⏵⏵ bypass permissions on …` 이나 힌트 조각 `/r`
# 을 잡는다. 그래서 매 send 마다 주입이 들어갔고, 그게 사용자 터미널 입력을 막은 두 번째 기제였다.
# 화면 텍스트 매칭은 UI 가 바뀌면 조용히 죽고, 죽어도 증상이 «더 많이 보내는 것»뿐이라 아무도 모른다.
DOORBELL_MIN="${FT_MBOX_DOORBELL_MIN:-3}"   # 같은 좌석에 이 초 안에 두 번 울리지 않는다
# $2=force(1) 이면 시간 억제를 뚫는다 — 발주는 «반드시» 창에 떠야 한다.
doorbell() {
  local to="$1" dbforce="${2:-0}" pane seat stamp recvstamp last recvlast now
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || return 0
  seat="$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  stamp="${TMPDIR:-/tmp}/mbox-doorbell-$seat"
  recvstamp="${TMPDIR:-/tmp}/mbox-recv-$seat"
  now="$(date +%s)"
  last="$(stat -f %m "$stamp" 2>/dev/null || echo 0)"
  recvlast="$(stat -f %m "$recvstamp" 2>/dev/null || echo 0)"
  # ★outstanding doorbell — pane 을 «읽지 않고» 판정★: 마지막 doorbell 이 마지막 recv 보다 나중이면
  # 아직 소비 안 된 doorbell 이 창에 떠 있다 → 재주입 불필요. 두 스탬프 다 없으면(첫 발신) 통과.
  # 조용한 폴백 금지: stat 실패 시 값 0 → 첫 발신처럼 «울리는 쪽»(안 울려 못 받는 게 더 나쁘다).
  # ★굶김 상한★ (2026-09-04 실측 회귀): outstanding 만으로 억제하면 좌석이 «영구 벙어리»가 된다.
  # doorbell 은 주입됐는데 좌석이 그 입력을 삼키면(턴 실행 중 입력 유실은 실측된 동작) recv 가
  # 영영 안 돌고 recv 스탬프도 안 생겨 ★이후 모든 send 가 skip★ 된다.
  # 실측: FB_CFO#4 는 09-03 17:00 doorbell 이후 recv 0회로 19시간 벙어리였다.
  # 그래서 «오래된» outstanding 은 소비될 가망이 없다고 보고 다시 울린다. 억제의 취지는
  # 홍수 방지지 침묵이 아니다 — 안 울려서 못 받는 것이 두 번 울리는 것보다 나쁘다.
  if [ "$dbforce" != 1 ] && [ "$last" -gt "$recvlast" ] \
     && [ "$((now - last))" -lt "${FT_MBOX_DOORBELL_STARVE:-120}" ]; then return 0; fi
  if [ "$dbforce" != 1 ] && [ "$((now - last))" -lt "$DOORBELL_MIN" ]; then return 0; fi
  : > "$stamp" 2>/dev/null || true
  tmux send-keys -t "$pane" -l "bash $SELF recv $to" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
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
    # 가드 거부(exit 3) 시 doorbell 을 울리지 않는다 — 큐에 들어간 게 없다.
    python3 "$MBOXPY" send "$to" "$from" "${args[*]}" ${force[@]+"${force[@]}"} || exit $?
    # ★`[ ] && doorbell` 로 쓰지 않는다★ — set -e 에서 notify=0 이면 리스트가 실패로 끝나 exit 1.
    if [ "$notify" = 1 ]; then doorbell "$to" "$dbf"; fi
    ;;
  relay)
    # 긴 본문의 정본 절차: 원문을 /tmp/mbox 로 복사하고 요약+경로만 큐잉.
    to="${1:?to}"; from="${2:?from}"; file="${3:?file}"; shift 3
    notify=1; args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) notify=0 ;;
        *)           args+=("$a") ;;
      esac
    done
    python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}" || exit $?
    if [ "$notify" = 1 ]; then doorbell "$to"; fi
    ;;
  recv)  me="${1:?me}"; shift
         # ★recv 스탬프 touch — doorbell outstanding 판정의 «소비» 신호★. exec 전에 해야 실행된다.
         : > "${TMPDIR:-/tmp}/mbox-recv-$(printf '%s' "$me" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null || true
         exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  *) echo "usage: mbox.sh {send <to> <from> <body> [--no-notify] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>}" >&2; exit 2;;
esac
