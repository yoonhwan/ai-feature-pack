#!/usr/bin/env bash
# ft-bg-loop.sh --seat <좌석> --max-sec <n> --stop-file <경로> -- <명령…> — 감시·증거 루프 래퍼 (r448 · 골 6)
#   좌석이 은퇴·증류된 뒤 ppid 1 로 남아 로그를 쌓던 `while … sleep … >>` 루프(10-19 tester67 guard.sh 5개 · 7시간)에 «닫는 사건» 3개를 붙인다:
#   ①--max-sec 초 경과 ②--stop-file 생김(1초 주기) ③명령 자체 종료 — 셋 중 먼저 오는 것. 둘 다 필수(상한 없는 루프 0).
#   명령은 자기 프로세스 그룹에서 돌고 FT_SEAT=<좌석> 을 물려받는다 — ft-seat-reap 이 argv `--seat <좌석>`·env 로 찾는다. 래퍼가 TERM·INT·HUP 을 받으면 그룹을 멈추고 끝난다.
#   끝 줄 1개 `bg-loop end reason=max-sec|stop-file|cmd-exit|signal sec=<n> rc=<명령 rc>` (stdout) · rc = 명령 rc(cmd-exit) · 그 밖 0 · usage 2.
#   쓰는 법: `nohup ft-bg-loop.sh --seat "$ME" --max-sec 3600 --stop-file ev/done.txt -- bash guard.sh >> ev/guard.log 2>&1 &` · 린트 = ft-bg-loop-lint.sh
set -uo pipefail
USAGE="usage: $0 --seat <좌석> --max-sec <n> --stop-file <경로> -- <명령…>"
SEAT=""; MAX=""; STOPF=""
while [ $# -gt 0 ]; do case "$1" in
  --seat) SEAT="${2:-}"; shift 2;; --max-sec) MAX="${2:-}"; shift 2;; --stop-file) STOPF="${2:-}"; shift 2;;
  --) shift; break;; *) echo "$USAGE" >&2; exit 2;; esac; done
[ -n "$SEAT" ] && [ -n "$STOPF" ] && [[ "$MAX" =~ ^[1-9][0-9]*$ ]] && [ $# -gt 0 ] || { echo "$USAGE — --seat·--max-sec(양의 정수)·--stop-file·명령 모두 필수" >&2; exit 2; }
export FT_SEAT="$SEAT"
T0=$SECONDS; REASON=""; CRC=0
set -m   # 명령을 자기 프로세스 그룹으로 — 그룹째 멈춘다
"$@" & CPID=$!
set +m
stop_group() {
  kill -TERM -- "-$CPID" 2>/dev/null; local i=0
  while kill -0 "$CPID" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i+1)); done
  kill -KILL -- "-$CPID" 2>/dev/null; wait "$CPID" 2>/dev/null
}
trap 'REASON=signal; stop_group; echo "bg-loop end reason=$REASON sec=$((SECONDS - T0)) rc=0"; exit 0' TERM INT HUP
while :; do
  if ! kill -0 "$CPID" 2>/dev/null; then wait "$CPID"; CRC=$?; REASON=cmd-exit; break; fi
  if [ -e "$STOPF" ]; then REASON=stop-file; stop_group; break; fi
  if [ $((SECONDS - T0)) -ge "$MAX" ]; then REASON=max-sec; stop_group; break; fi
  sleep 1 & wait $!   # wait 로 기다려야 trap 이 바로 돈다
done
echo "bg-loop end reason=$REASON sec=$((SECONDS - T0)) rc=$CRC"
[ "$REASON" = cmd-exit ] && exit "$CRC"; exit 0
