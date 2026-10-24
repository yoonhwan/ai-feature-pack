#!/usr/bin/env bash
# h-mini-chrome-cdp.sh — mini 의 시험용 Chrome(CDP 9333 · 전용 프로필)을 터미널과 무관하게 띄운다. 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1 (쓰기 0)
#   (2026-10-24 · aifp-multihost-master-claude#3 · 러너 1회차 h313 rc=2: 오빠가 mini 터미널에서 `… &` 로 띄운 Chrome 이 22:4x 사이 꺼짐(추정: 터미널 종료와 함께))
#   하는 일(mini 안 · GCP 쓰기 0 · sudo 0):
#     ① 사전점검: 9333 이 비어 있는지 · Chrome 앱 · 이 사용자가 mini 콘솔(GUI) 사용자인지
#     ② `open -n -a "Google Chrome" --args --remote-debugging-port=9333 …` — LaunchServices 가 GUI 세션에서 띄우므로 ssh/터미널을 닫아도 남는다(부모 = launchd)
#     ③ 증거: 9333 /json/version 의 Browser 줄 · Chrome 프로세스 부모가 1(launchd) · 평소 Chrome(--no-startup-window)은 그대로
#   오빠 평소 Chrome·프로필은 건드리지 않는다. 시험용은 별도 프로필 /tmp/chrome-byz-debug 만 쓴다(헤드풀 필수 · --headless 금지).
# rc: 0 성공 · 2 사전점검 실패 · 4 기동/증거 실패
# ★GUI 세션이 없어 open 이 실패하면 이 스크립트는 아무것도 바꾸지 않고 rc=4 — 그때는 mini 터미널에서 `nohup … &` + `disown` 로 띄워야 한다(안내 출력)
set -uo pipefail

MINI="${MINI:-mini}"; DRY="${DRY:-0}"; CDP="${CDP:-9333}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-chrome] %s\n' "$*"; }
die() { printf '[h-chrome] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

say "0/3 사전점검 (DRY=${DRY} · CDP=${CDP})"
case "$CDP" in *[!0-9]*) die 2 "포트는 숫자만";; esac

PRE="$(timeout 30 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; CDP=${CDP} bash -s" <<'REMOTE' 2>&1
echo "cdp_http=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${CDP}/json/version" 2>/dev/null)"
echo "chrome_app=$([ -d '/Applications/Google Chrome.app' ] && echo yes || echo no)"
echo "me=$(id -un) console=$(stat -f %Su /dev/console 2>/dev/null)"
echo "gui_session=$(launchctl print "gui/$(id -u)" >/dev/null 2>&1 && echo yes || echo no)"
echo "debug_chrome_procs=$(ps -eo command | grep -- "remote-debugging-port=${CDP}" | grep -v grep | wc -l | tr -d ' ')"
echo "profile_dir=$([ -d /tmp/chrome-byz-debug ] && echo yes || echo no)"
REMOTE
)" || die 2 "mini 접속 실패: ${PRE}"
get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
printf '%s\n' "$PRE" | sed 's/^/        /'

[ "$(get chrome_app)" = "yes" ] || die 2 "mini 에 /Applications/Google Chrome.app 이 없다"
[ "$(get gui_session)" = "yes" ] || die 2 "mini 에 GUI 세션이 없다(콘솔 로그인 필요)"
if [ "$(get cdp_http)" = "200" ]; then say "        이미 ${CDP} 이 응답한다 — 할 일 없음"; exit 0; fi

if [ "$DRY" = "1" ]; then
  say "DRY — 하려던 일(쓰기 0): open -n -a \"Google Chrome\" --args --remote-debugging-port=${CDP} --no-first-run --no-default-browser-check --user-data-dir=/tmp/chrome-byz-debug about:blank → 최대 20초 ${CDP} 응답 대기 → 부모 launchd 확인"
  exit 0
fi

say "1/3 시험용 Chrome 기동 (open · GUI 세션)"
timeout 20 ssh "${SO[@]}" "$MINI" "open -n -a 'Google Chrome' --args --remote-debugging-port=${CDP} --no-first-run --no-default-browser-check --user-data-dir=/tmp/chrome-byz-debug about:blank" || die 4 "open 실패 — 아무것도 바꾸지 않았다. mini 터미널에서: nohup \"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome\" --remote-debugging-port=${CDP} --no-first-run --no-default-browser-check --user-data-dir=/tmp/chrome-byz-debug about:blank >/dev/null 2>&1 & disown"

say "2/3 ${CDP} 응답 대기 (최대 20초)"
EV="$(timeout 40 ssh "${SO[@]}" "$MINI" "CDP=${CDP} bash -s" <<'REMOTE' 2>&1
i=0; H=000
while [ $i -lt 10 ]; do
  H="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:${CDP}/json/version" 2>/dev/null || echo 000)"
  [ "$H" = "200" ] && break
  sleep 2; i=$((i+1))
done
echo "http=$H"
echo "browser=$(curl -s -m 3 "http://127.0.0.1:${CDP}/json/version" 2>/dev/null | grep '"Browser"' | tr -d ' ,')"
P="$(ps -eo pid,ppid,command | grep -- "remote-debugging-port=${CDP}" | grep -v grep | grep -v Helper | head -1)"
echo "proc=$(printf '%s' "$P" | cut -c1-110)"
echo "ppid=$(printf '%s' "$P" | awk '{print $2}')"
REMOTE
)" || die 4 "증거 수집 실패: ${EV}"
printf '%s\n' "$EV" | sed 's/^/        /'
[ "$(printf '%s\n' "$EV" | sed -n 's/^http=//p' | head -1)" = "200" ] || die 4 "${CDP} 이 20초 안에 응답하지 않았다 — mini 화면에 Chrome 창이 떴는지 확인"

say "3/3 증거"
PP="$(printf '%s\n' "$EV" | sed -n 's/^ppid=//p' | head -1)"
if [ "$PP" = "1" ]; then say "        부모 launchd(1) ✅ — 터미널을 닫아도 남는다"; else say "        ⚠ 부모 pid=${PP} — launchd 가 아니다(터미널 종속일 수 있음)"; fi
say "완료 rc=0 — 시험용 Chrome(${CDP}) 가동. 다음: 러너 1회차 h"
exit 0
