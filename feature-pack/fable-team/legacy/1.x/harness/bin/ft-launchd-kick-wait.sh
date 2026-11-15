#!/usr/bin/env bash
# ft-launchd-kick-wait.sh — r1755: launchd 잡을 다시 돌리고 «이번 실행이 쓴 결과 파일»(mtime ≥ T0)이 생길 때까지 기다린 뒤 그 실행의 exit code 를 1줄로 낸다.
#   usage: ft-launchd-kick-wait.sh <launchd 라벨> <결과 파일> [--wait <초>]      (기본 FT_KICK_WAIT_S 또는 25 · 상한 25 = 하드 룰 12 로컬 하네스)
#   T0 기록 → launchctl kickstart -k gui/<uid>/<라벨> → 1초 간격으로 «결과 파일 mtime ≥ T0 ∧ 잡 running 아님» 확인
#     (설치 h 의 «running 일 때만 기다림» 루프는 잡이 몇 초 만에 끝나면 첫 회에 빠져 옛 판을 읽었다 · r1744 실측)
#   출력·반환값:
#     KICKED <라벨> fresh=<mtime> exit=<n> waited=<초>          rc0 (exit≠0 이면 rc1)
#     STALE <라벨> 결과 파일 mtime <m> < T0 <t> · waited=<초>     rc3 (상한까지 이번 판 0)
#     판정 불가 <사유>                                           rc2 (잡 없음 = print rc113 · print·kickstart 실패 · 상한 안에 안 끝남 · usage — 하드 룰 20)
#   쓰기 0: kickstart 1회 외 결과 파일·plist·잡 목록 손 0.
set -uo pipefail
L="${1:-}"; R="${2:-}"; W="${FT_KICK_WAIT_S:-25}"
[ "${3:-}" = --wait ] && W="${4:-}"
case "$W" in ''|*[!0-9]*) L="" ;; esac
[ -n "$L" ] && [ -n "$R" ] || { echo "판정 불가 usage: ft-launchd-kick-wait.sh <라벨> <결과 파일> [--wait <초>]"; exit 2; }
[ "$W" -gt 25 ] && W=25   # r1755-mut:cap
U="gui/$(id -u)/$L"; P=""; prc=0
pr() { P=$(launchctl print "$U" 2>/dev/null); prc=$?; }
running() {
  pr; [ "$prc" = 0 ] || { echo "판정 불가 launchctl print rc=$prc $L"; exit 2; }
  printf '%s\n' "$P" | grep -q 'state = running'
}
mt() { stat -f %m "$R" 2>/dev/null || echo 0; }
pr
[ "$prc" = 113 ] && { echo "판정 불가 잡 없음 $L (launchctl print rc=113)"; exit 2; }
[ "$prc" = 0 ] || { echo "판정 불가 launchctl print rc=$prc $L"; exit 2; }
T0=$(date +%s)
launchctl kickstart -k "$U" >/dev/null 2>&1 || { echo "판정 불가 kickstart rc=$? $L"; exit 2; }
while :; do
  m=$(mt); now=$(date +%s)
  [ "$m" -ge "$T0" ] && ! running && break   # r1755-mut:fresh
  [ $((now - T0)) -ge "$W" ] && break
  sleep 1
done
w=$(( $(date +%s) - T0 ))
[ "$m" -ge "$T0" ] || { echo "STALE $L 결과 파일 mtime $m < T0 $T0 · waited=$w"; exit 3; }
running && { echo "판정 불가 상한 ${W}초 안에 잡이 안 끝남 $L · waited=$w"; exit 2; }
ec=$(printf '%s\n' "$P" | awk -F'= ' '/last exit code/{print $2; exit}')
echo "KICKED $L fresh=$m exit=${ec:-?} waited=$w"
[ "$ec" = 0 ] || exit 1
