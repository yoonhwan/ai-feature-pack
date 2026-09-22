#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# 좌석 busy/IDLE 판정 — 눈대중 금지, 이 스크립트가 정본.
#
# 2026-09-01 신설 (오빠: "또 안멈춰있게 체크루프 모니터링 확실히")
# 배경: master 가 pane 캡처에서 'esc to interrupt' 같은 문자열을 잡아
#   IDLE 좌석을 "작업중"으로 두 번 오판했고, 그때마다 좌석이 놀았다.
#
# 판정식(고정):
#   busy  = pane 에 진행 스피너 토큰이 있다 (Claude Code 는 작업 중에만 찍는다)
#   IDLE  = 그 토큰이 없다 — 상태줄만 남은 상태
# 스피너 토큰은 버전마다 늘어난다. 목록을 여기 한 곳에서만 고친다.

set -uo pipefail
SPIN='thinking|Sublimating|Cogitat|Gusting|Crunch|Sock-hopping|Brewed|Elucidat|Worked for|Percolat|Simmer|Mulling|Pondering|Noodling|Ruminat|Deliberat|Herding|Puzzl|Wrangl|Baking|Steeping|Whirring|Forging|Honing|Distilling|Musing'

seats() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep -E "${1:-^ft-}" | sort
}

pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

status_of() {
  local p; p="$(pane_of "$1")"
  [ -n "$p" ] || { echo "NOSEAT"; return; }
  local cap; cap="$(tmux capture-pane -p -J -S -12 -t "$p" 2>/dev/null)"
  if echo "$cap" | grep -qE "$SPIN"; then echo "BUSY"; else echo "IDLE"; fi
}

case "${1:-list}" in
  list)
    for s in $(seats "${2:-^ft-}"); do printf "%-26s %s\n" "$s" "$(status_of "$s")"; done ;;
  idle)   # IDLE 좌석만 — 깨울 대상
    for s in $(seats "${2:-^ft-}"); do [ "$(status_of "$s")" = "IDLE" ] && echo "$s"; done ;;
  one)    status_of "${2:?seat}" ;;
  *) echo "usage: $0 {list|idle|one <seat>} [regex]" >&2; exit 2 ;;
esac
