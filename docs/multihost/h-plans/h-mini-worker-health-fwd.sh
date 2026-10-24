#!/usr/bin/env bash
# h-mini-worker-health-fwd.sh — mini 의 gateway 가 보는 worker 상태 주소(localhost:8081)를 실제 worker(8080)로 이어 준다. 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1 (쓰기 0)
#   (2026-10-24 · aifp-multihost-master-claude#3 · 러너 1회차 h313 4번째 실패: host_empty — 녹음은 켜졌고 발화도 나갔지만 STT 결과 0)
#   원인 실측: gateway GET /graph/speech/pulse_transcribe/v1/health = 503 `worker_unreachable`(gateway 로그 «worker unreachable url=http://localhost:8081/health · Connection refused»).
#     gateway 는 worker_health_url 미설정이면 정본 server.sh 관례 localhost:8081 을 본다(gateway/routes/compat/speech.py:789). mini 의 서버 h 는 worker PORT 를 주지 않아(WORKER_ENV_SPEC 의 PORT 를 건너뜀)
#     worker 가 기본 8080 에서 뜬다 — 직접 보면 8080/health = 200 · consumer_ready=true. FE 는 이 응답이 ok 가 아니면 STT 를 막는다(clients/web/src/domains/realtime/ptt-health.ts `return res.ok`).
#   하는 일(mini 안 · 서버 재시작 0 · 환경변수 변경 0 · GCP 쓰기 0 · sudo 0):
#     ① 사전점검: worker 8080/health 200 + consumer_ready=true · 127.0.0.1:8081 비어 있음 · gateway pulse health 가 지금 503
#     ② 127.0.0.1:8081 → 127.0.0.1:8080 TCP 중계 작은 파이썬 프로세스를 nohup 으로 기동(/tmp/h-worker-health-fwd.py · 로그 /tmp/h-health-fwd.log) · pid 를 ~/Project/BYZ-Agents/.h-pids 에 추가(서버 h 의 ACTION=stop 이 같이 정지)
#     ③ 증거: 8081/health 200 · gateway pulse health 200
#   ★이건 «정본 server.sh 의 worker 포트 8081 관례를 mini 에서 흉내 내는» 보정이다. 근본(서버 h 가 worker 에 PORT=8081 을 주거나 gateway 에 WORKER_HEALTH_URL 을 주기)은 서버 재시작이 필요해 이번 회차 뒤로 미뤘다
#   ★되돌림(삭제·종료)은 사람 승인: 서버 h ACTION=stop 이 .h-pids 의 pid 를 정리하거나 mini 에서 해당 pid 종료. 이 스크립트는 지우지 않는다
# rc: 0 성공 · 2 사전점검 실패 · 4 기동/증거 실패
set -uo pipefail

MINI="${MINI:-mini}"; DRY="${DRY:-0}"
P_WK="${P_WK:-8080}"; P_FWD="${P_FWD:-8081}"; P_GW="${P_GW:-38312}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-whfwd] %s\n' "$*"; }
die() { printf '[h-whfwd] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

say "0/3 사전점검 (DRY=${DRY} · worker=${P_WK} → ${P_FWD} · gateway=${P_GW})"
case "${P_WK}${P_FWD}${P_GW}" in *[!0-9]*) die 2 "포트는 숫자만";; esac

PRE="$(timeout 40 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; P_WK=${P_WK} P_FWD=${P_FWD} P_GW=${P_GW} bash -s" <<'REMOTE' 2>&1
H="$(curl -s -m 5 "http://127.0.0.1:${P_WK}/health" 2>/dev/null)"
echo "worker_http=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${P_WK}/health" 2>/dev/null)"
echo "consumer_ready=$(printf '%s' "$H" | grep -o '"consumer_ready":[a-z]*' | head -1 | cut -d: -f2)"
echo "fwd_port_listener=$(lsof -nP -iTCP:"$P_FWD" -sTCP:LISTEN -t 2>/dev/null | head -1)"
echo "gw_pulse_http=$(curl -s -o /dev/null -m 7 -w '%{http_code}' "http://127.0.0.1:${P_GW}/graph/speech/pulse_transcribe/v1/health" 2>/dev/null)"
echo "py=$([ -x /opt/homebrew/bin/python3.13 ] && echo /opt/homebrew/bin/python3.13 || command -v python3)"
echo "runner_procs=$(pgrep -f realtime_multi_e2e 2>/dev/null | wc -l | tr -d ' ')"
REMOTE
)" || die 2 "mini 접속 실패: ${PRE}"
get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
printf '%s\n' "$PRE" | sed 's/^/        /'

[ "$(get worker_http)" = "200" ] || die 2 "worker ${P_WK}/health 가 200 이 아니다($(get worker_http)) — worker 가 안 떠 있다"
[ "$(get consumer_ready)" = "true" ] || die 2 "worker consumer_ready 가 true 가 아니다($(get consumer_ready))"
[ -z "$(get fwd_port_listener)" ] || die 2 "127.0.0.1:${P_FWD} 이 이미 사용 중이다(pid $(get fwd_port_listener)) — 남의 프로세스는 건드리지 않는다"
[ "$(get runner_procs)" = "0" ] || die 2 "러너가 돌고 있다 — 끝난 뒤 다시"
[ -n "$(get py)" ] || die 2 "mini 에 python3 가 없다"

if [ "$DRY" = "1" ]; then
  say "DRY — 하려던 일(쓰기 0): mini 에 /tmp/h-worker-health-fwd.py(TCP 중계 127.0.0.1:${P_FWD}→127.0.0.1:${P_WK}) 만들고 nohup 기동 → pid 를 .h-pids 에 추가 → ${P_FWD}/health·gateway pulse health 200 확인 (지금 gateway pulse=$(get gw_pulse_http))"
  exit 0
fi

say "1/3 중계 프로세스 파일 배치"
timeout 20 ssh "${SO[@]}" "$MINI" "cat > /tmp/h-worker-health-fwd.py" <<'PYEOF' || die 4 "중계 스크립트 배치 실패"
# 127.0.0.1:LISTEN → 127.0.0.1:TARGET 단순 TCP 중계(worker health 전용 · 외부 노출 0)
import asyncio, os, sys
LISTEN = int(os.environ["FWD_LISTEN"]); TARGET = int(os.environ["FWD_TARGET"])

async def pipe(r, w):
    try:
        while True:
            b = await r.read(65536)
            if not b:
                break
            w.write(b)
            await w.drain()
    except Exception:
        pass
    finally:
        try:
            w.close()
        except Exception:
            pass

async def handle(cr, cw):
    try:
        ur, uw = await asyncio.open_connection("127.0.0.1", TARGET)
    except Exception:
        cw.close()
        return
    await asyncio.gather(pipe(cr, uw), pipe(ur, cw))

async def main():
    srv = await asyncio.start_server(handle, "127.0.0.1", LISTEN)
    print(f"fwd 127.0.0.1:{LISTEN} -> 127.0.0.1:{TARGET}", flush=True)
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
PYEOF

say "2/3 중계 기동 (분리 실행)"
timeout 20 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; PY=$(get py) FWD_LISTEN=${P_FWD} FWD_TARGET=${P_WK} bash -s" <<'REMOTE' || die 4 "기동 명령 실패"
( FWD_LISTEN="$FWD_LISTEN" FWD_TARGET="$FWD_TARGET" nohup "$PY" /tmp/h-worker-health-fwd.py >/tmp/h-health-fwd.log 2>&1 </dev/null &
  echo $! >> "$HOME/Project/BYZ-Agents/.h-pids" )
sleep 2
echo started
REMOTE

say "3/3 증거"
EV="$(timeout 40 ssh "${SO[@]}" "$MINI" "P_FWD=${P_FWD} P_GW=${P_GW} bash -s" <<'REMOTE' 2>&1
i=0; GW=000
while [ $i -lt 6 ]; do
  GW="$(curl -s -o /dev/null -m 7 -w '%{http_code}' "http://127.0.0.1:${P_GW}/graph/speech/pulse_transcribe/v1/health" 2>/dev/null)"
  [ "$GW" = "200" ] && break
  sleep 2; i=$((i+1))
done
echo "fwd_health=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${P_FWD}/health" 2>/dev/null)"
echo "gw_pulse_http=$GW"
echo "gw_pulse_body=$(curl -s -m 7 "http://127.0.0.1:${P_GW}/graph/speech/pulse_transcribe/v1/health" 2>/dev/null | cut -c1-160)"
echo "fwd_log=$(tail -1 /tmp/h-health-fwd.log 2>/dev/null)"
REMOTE
)" || die 4 "증거 수집 실패: ${EV}"
printf '%s\n' "$EV" | sed 's/^/        /'
[ "$(printf '%s\n' "$EV" | sed -n 's/^fwd_health=//p' | head -1)" = "200" ] || die 4 "중계 ${P_FWD}/health 가 200 이 아니다 — /tmp/h-health-fwd.log 확인"
[ "$(printf '%s\n' "$EV" | sed -n 's/^gw_pulse_http=//p' | head -1)" = "200" ] || die 4 "gateway pulse health 가 200 이 아니다 — 위 본문 확인"
say "완료 rc=0 — gateway pulse health 200 (worker 8080 으로 중계). 다음: 러너 1회차 h"
exit 0
