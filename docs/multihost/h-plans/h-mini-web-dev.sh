#!/usr/bin/env bash
# h-mini-web-dev.sh — mini 시험 웹을 production(next start) → dev(next dev + mock host)로 교체한다. 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1 (쓰기 0)
#   (2026-10-24 · aifp-multihost-master-claude#3 · 오빠 결정 «dev 모드로 교체» · 근거 = 러너 1회차 실패 HostRoomCreateError: host 탭 sessionStorage dev-mock-host-id 없음)
#   왜: 웹 미들웨어의 mock host 우회는 `NODE_ENV !== 'production'` AND `NEXT_PUBLIC_DEV_MOCK_HOST === '1'` 일 때만 열린다(clients/web/middleware.ts). production 빌드는 환경변수를 더해도 절대 안 열린다.
#   하는 일(mini 안 · GCP 쓰기 0 · sudo 0):
#     ① 사전점검: web 포트(기본 38314) 리스너가 ~/Project/BYZ-Agents 아래 프로세스인지 · 러너가 안 돌고 있는지
#     ② 그 web 프로세스(부모 next start 포함)만 정지 — gateway·worker·redis·터널·Chrome 은 건드리지 않는다
#     ③ clients/web 에서 next dev 기동(NEXT_PUBLIC_DEV_MOCK_HOST=1 · API/SSE/WS/BASE_URL 은 서버 h 와 같은 값 · NODE_ENV 미설정) → pid 를 .h-pids 에 추가(서버 h 의 ACTION=stop 이 같이 정지)
#     ④ 증거: 포트 응답 · 프로세스 명령이 next dev · 환경에 mock 플래그 있음 · NODE_ENV=production 아님
# rc: 0 성공 · 2 사전점검 실패 · 3 정지 실패 · 4 기동/증거 실패
# ★되돌림(production 빌드로 복귀)은 사람 승인: 서버 h(h-mini-byz-server.sh) ACTION=stop 후 같은 sha 로 up — .next 가 dev 로 덮였을 수 있어 빌드 표식이 맞아도 재빌드가 필요하면 mini 에서 ~/Project/BYZ-Agents/.h-installed 파일을 지우고 다시 up (이 스크립트는 지우지 않는다)
set -uo pipefail

MINI="${MINI:-mini}"; DRY="${DRY:-0}"
P_GW="${P_GW:-38312}"; P_WEB="${P_WEB:-38314}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-webdev] %s\n' "$*"; }
die() { printf '[h-webdev] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rmt() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }

say "0/4 사전점검 (DRY=${DRY} · web=${P_WEB} gateway=${P_GW})"
case "${P_GW}${P_WEB}" in *[!0-9]*) die 2 "포트는 숫자만";; esac
[[ "$P_GW" =~ ^383[0-9][0-9]$ && "$P_WEB" =~ ^383[0-9][0-9]$ ]] || die 2 "포트는 38301~38399 만(받은 값: ${P_GW}/${P_WEB})"

PRE="$(timeout 40 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; P_WEB=${P_WEB} P_GW=${P_GW} bash -s" <<'REMOTE' 2>&1
cd "$HOME/Project/BYZ-Agents/clients/web" 2>/dev/null || { echo "norepo=1"; exit 0; }
echo "norepo=0"
L="$(lsof -nP -iTCP:"$P_WEB" -sTCP:LISTEN -t 2>/dev/null | head -1)"
echo "listener=${L:-none}"
if [ -n "$L" ]; then
  CWD="$(lsof -a -p "$L" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  echo "cwd=$CWD"
  echo "cmd=$(ps -o command= -p "$L" | cut -c1-80)"
  PP="$(ps -o ppid= -p "$L" | tr -d ' ')"
  echo "ppid=$PP"
  echo "pcmd=$(ps -o command= -p "$PP" 2>/dev/null | cut -c1-80)"
  ENVL="$(ps eww -p "$L" 2>/dev/null | tr ' ' '\n' | grep -E '^(NODE_ENV|NEXT_PUBLIC_DEV_MOCK_HOST)=' | tr '\n' ' ')"
  echo "env=${ENVL}"
fi
GWL="$(lsof -nP -iTCP:"$P_GW" -sTCP:LISTEN -t 2>/dev/null | head -1)"
echo "gateway_listener=${GWL:-none}"
echo "runner_procs=$(pgrep -f realtime_multi_e2e 2>/dev/null | wc -l | tr -d ' ')"
echo "next_dev_ok=$([ -x ./node_modules/.bin/next ] && echo yes || echo no)"
REMOTE
)" || die 2 "mini 접속 실패: ${PRE}"
get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
printf '%s\n' "$PRE" | sed 's/^/        /'

[ "$(get norepo)" = "0" ] || die 2 "mini ~/Project/BYZ-Agents/clients/web 가 없다 — 서버 h(h-mini-byz-server.sh) 먼저"
[ "$(get runner_procs)" = "0" ] || die 2 "러너가 돌고 있다($(get runner_procs)개) — 끝난 뒤 다시"
[ "$(get gateway_listener)" != "none" ] || die 2 "gateway ${P_GW} 이 안 떠 있다 — 서버 h 먼저"
[ "$(get next_dev_ok)" = "yes" ] || die 2 "clients/web/node_modules/.bin/next 가 없다"
LISTENER="$(get listener)"
if [ "$LISTENER" != "none" ]; then
  case "$(get cwd)" in */Project/BYZ-Agents/*) ;; *) die 2 "web 포트 ${P_WEB} 리스너의 작업 폴더가 ~/Project/BYZ-Agents 아래가 아니다($(get cwd)) — 남의 프로세스는 건드리지 않는다";; esac
  if printf '%s' "$(get cmd) $(get pcmd)" | grep -q 'next dev' && printf '%s' "$(get env)" | grep -q 'NEXT_PUBLIC_DEV_MOCK_HOST=1' && ! printf '%s' "$(get env)" | grep -q 'NODE_ENV=production'; then
    say "        이미 dev + mock host 로 떠 있다 — 할 일 없음"; exit 0
  fi
fi

if [ "$DRY" = "1" ]; then
  say "DRY — 하려던 일(쓰기 0): ② ${P_WEB} 의 web 프로세스(pid ${LISTENER} · 부모 $(get ppid))만 정지 → ③ clients/web 에서 next dev -p ${P_WEB} (NEXT_PUBLIC_DEV_MOCK_HOST=1 · API/SSE/WS=127.0.0.1:${P_GW} · BASE_URL=127.0.0.1:${P_WEB}) 기동 → ④ 증거"
  exit 0
fi

say "1/4 사전점검 통과 — 2/4 web 정지(이 포트의 web 프로세스만)"
if [ "$LISTENER" != "none" ]; then
  rmt 20 "P_WEB=${P_WEB} L=${LISTENER} PP=$(get ppid) bash -s" <<'REMOTE' || die 3 "정지 명령 실패"
PC="$(ps -o command= -p "$PP" 2>/dev/null)"
case "$PC" in *next*) kill "$PP" 2>/dev/null;; esac
kill "$L" 2>/dev/null
i=0; while [ $i -lt 15 ]; do
  [ -z "$(lsof -nP -iTCP:"$P_WEB" -sTCP:LISTEN -t 2>/dev/null | head -1)" ] && { echo "freed"; exit 0; }
  sleep 1; i=$((i+1))
done
echo "still-listening"; exit 1
REMOTE
fi
[ -z "$(rmt 10 "lsof -nP -iTCP:${P_WEB} -sTCP:LISTEN -t 2>/dev/null | head -1")" ] || die 3 "web 포트 ${P_WEB} 이 15초 안에 비지 않았다 — mini 에서 확인(강제 종료는 이 h 가 하지 않는다)"
say "        web 포트 ${P_WEB} 비어짐"

say "3/4 next dev 기동 (mock host · 분리 실행)"
rmt 20 "P_WEB=${P_WEB} P_GW=${P_GW} bash -s" <<'REMOTE' || die 4 "기동 명령 실패"
cd "$HOME/Project/BYZ-Agents/clients/web" || exit 1
( env -u NODE_ENV \
    NEXT_PUBLIC_DEV_MOCK_HOST=1 \
    NEXT_PUBLIC_API_URL="http://127.0.0.1:${P_GW}/api/v1" \
    NEXT_PUBLIC_SSE_URL="http://127.0.0.1:${P_GW}/sse/v1" \
    NEXT_PUBLIC_WS_URL="ws://127.0.0.1:${P_GW}/ws/v1" \
    NEXT_PUBLIC_BASE_URL="http://127.0.0.1:${P_WEB}" \
    PORT="$P_WEB" \
    nohup ./node_modules/.bin/next dev -p "$P_WEB" >/tmp/h-byz-web.log 2>&1 </dev/null &
  echo $! >> ../../.h-pids )
sleep 2
echo started
REMOTE

say "4/4 증거 (첫 컴파일 때문에 최대 60초 기다린다)"
EV="$(timeout 80 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; P_WEB=${P_WEB} bash -s" <<'REMOTE' 2>&1
i=0; HTTP=000
while [ $i -lt 12 ]; do
  HTTP="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "http://127.0.0.1:${P_WEB}/" 2>/dev/null || echo 000)"
  case "$HTTP" in 2*|3*) break;; esac
  sleep 5; i=$((i+1))
done
echo "http=$HTTP"
L="$(lsof -nP -iTCP:"$P_WEB" -sTCP:LISTEN -t 2>/dev/null | head -1)"
echo "listener=${L:-none}"
if [ -n "$L" ]; then
  PP="$(ps -o ppid= -p "$L" | tr -d ' ')"
  echo "cmd=$(ps -o command= -p "$L" | cut -c1-60) | $(ps -o command= -p "$PP" 2>/dev/null | cut -c1-60)"
  ENVL="$( { ps eww -p "$L"; ps eww -p "$PP"; } 2>/dev/null | tr ' ' '\n' | grep -E '^(NODE_ENV|NEXT_PUBLIC_DEV_MOCK_HOST)=' | sort -u | tr '\n' ' ')"
  echo "env=${ENVL}"
fi
REMOTE
)" || die 4 "증거 수집 실패: ${EV}"
printf '%s\n' "$EV" | sed 's/^/        /'
EVH="$(printf '%s\n' "$EV" | sed -n 's/^http=//p' | head -1)"
case "$EVH" in 2*|3*) ;; *) die 4 "web 응답 ${EVH} — 로그: ssh ${MINI} 'tail -30 /tmp/h-byz-web.log'";; esac
printf '%s' "$EV" | grep -q 'NODE_ENV=production' && die 4 "NODE_ENV=production 이 설정돼 있다 — mock host 가 안 열린다"
printf '%s' "$EV" | grep -q 'next' || die 4 "web 프로세스 명령에 next 가 안 보인다"
# ps 는 프로세스 이름을 바꾼 next 의 환경을 못 보여 줄 수 있다(기존 production 프로세스도 env 가 비어 보였다) → 보이면 확인, 안 보이면 경고만. 실제 증거는 러너의 host 탭 dev-mock-host-id
if printf '%s' "$EV" | grep -q 'NEXT_PUBLIC_DEV_MOCK_HOST=1'; then say "        mock 플래그 ✅ 프로세스 환경에서 확인"; else say "        ⚠ 프로세스 환경에서는 mock 플래그가 안 보인다(ps 한계일 수 있음) — 러너 1회차의 host 탭 dev-mock-host-id 가 실제 증거"; fi
say "완료 rc=0 — mini web = next dev (포트 ${P_WEB} · mock 플래그 주입). 다음: 러너 1회차 h"
exit 0
