#!/usr/bin/env bash
# h-mini-mic-grant.sh — mini 시험용 Chrome(CDP 9333)에 «마이크 권한만» 미리 준다(체크리스트 6번 «허용 팝업 1회» 의 CDP 판). 실행은 오빠가 `! bash /tmp/h<N>` 로만. 먼저 계획: DRY=1 (쓰기 0)
#   (2026-10-24 · aifp-multihost-master-claude#3 · 러너 1회차 h313 3번째 실패: host_record_not_started — 녹음 버튼 trusted 클릭은 갔으나 aria-pressed 가 안 켜짐 · 시험용 프로필 Preferences 의 media_stream_mic 허용 목록 {} = 마이크 허용 한 번도 안 줌)
#   하는 일(mini 안 · 시험용 Chrome 만 · GCP 쓰기 0 · sudo 0 · 파일 쓰기 0):
#     ① 사전점검: CDP 9333 응답 · mini 러너 venv 에 websockets 있음 · 러너가 안 돌고 있음
#     ② CDP `Browser.grantPermissions {origin: http://127.0.0.1:<web>, permissions:[audioCapture]}` — 권한 «부여» 만. 버튼 클릭·DOM·Redis 주입 0(하드 룰 5·11 — 이건 오빠가 허용 팝업을 누르는 것과 같은 사전 권한이고 시험 증거가 아니다. 증거는 러너의 trusted 클릭)
#     ③ 증거: 명령 응답 성공(빈 result)
#   ★Chrome 을 다시 띄우면 이 권한은 사라진다(세션 권한) → 그때는 이 h 를 다시. 영구 허용이 필요하면 mini 시험용 Chrome 창에서 오빠가 팝업 «허용» 한 번(체크리스트 6번)
# rc: 0 성공 · 2 사전점검 실패 · 4 부여 실패
set -uo pipefail

MINI="${MINI:-mini}"; DRY="${DRY:-0}"; CDP="${CDP:-9333}"; P_WEB="${P_WEB:-38314}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-mic] %s\n' "$*"; }
die() { printf '[h-mic] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

say "0/2 사전점검 (DRY=${DRY} · CDP=${CDP} · origin=http://127.0.0.1:${P_WEB})"
case "${CDP}${P_WEB}" in *[!0-9]*) die 2 "포트는 숫자만";; esac
[[ "$P_WEB" =~ ^383[0-9][0-9]$ ]] || die 2 "web 포트는 38301~38399 만(받은 값: ${P_WEB})"

PRE="$(timeout 30 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; CDP=${CDP} bash -s" <<'REMOTE' 2>&1
echo "cdp_http=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${CDP}/json/version" 2>/dev/null)"
PY="$HOME/Project/BYZ-Agents/.venv/bin/python"
[ -x "$PY" ] || PY="$HOME/Project/BYZ-e2e/.venv/bin/python"
echo "py=$PY"
echo "websockets=$("$PY" -c 'import websockets;print(websockets.__version__)' 2>/dev/null || echo no)"
echo "runner_procs=$(pgrep -f realtime_multi_e2e 2>/dev/null | wc -l | tr -d ' ')"
REMOTE
)" || die 2 "mini 접속 실패: ${PRE}"
get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
printf '%s\n' "$PRE" | sed 's/^/        /'
[ "$(get cdp_http)" = "200" ] || die 2 "CDP ${CDP} 응답 없음 — h-mini-chrome-cdp.sh 먼저"
[ "$(get websockets)" != "no" ] || die 2 "mini 러너 venv 에 websockets 가 없다"
[ "$(get runner_procs)" = "0" ] || die 2 "러너가 돌고 있다 — 끝난 뒤 다시"

if [ "$DRY" = "1" ]; then
  say "DRY — 하려던 일(쓰기 0): CDP ${CDP} 브라우저 대상에 Browser.grantPermissions(origin=http://127.0.0.1:${P_WEB}, permissions=[audioCapture]) 1회 → 응답 확인"
  exit 0
fi

say "1/2 마이크 권한 부여 (CDP Browser.grantPermissions)"
EV="$(timeout 30 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; CDP=${CDP} ORIGIN=http://127.0.0.1:${P_WEB} PY=$(get py) bash -s" <<'REMOTE' 2>&1
"$PY" - <<'PYEOF'
import asyncio, json, os, urllib.request
import websockets

cdp = os.environ["CDP"]; origin = os.environ["ORIGIN"]
ver = json.load(urllib.request.urlopen(f"http://127.0.0.1:{cdp}/json/version", timeout=5))
ws_url = ver["webSocketDebuggerUrl"]

async def main():
    async with websockets.connect(ws_url, max_size=2**22, open_timeout=5) as ws:
        await ws.send(json.dumps({"id": 1, "method": "Browser.grantPermissions",
                                  "params": {"origin": origin, "permissions": ["audioCapture"]}}))
        for _ in range(20):
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            if msg.get("id") == 1:
                print("grant_response=" + json.dumps({k: msg[k] for k in ("result", "error") if k in msg}))
                return
        print("grant_response=no-reply")

asyncio.run(main())
PYEOF
REMOTE
)" || die 4 "부여 명령 실패: ${EV}"
printf '%s\n' "$EV" | sed 's/^/        /'
printf '%s\n' "$EV" | grep -q '^grant_response={"result": {}}' || die 4 "응답이 빈 result 가 아니다 — 위 출력 확인"

say "2/2 증거 — 부여 응답 성공(빈 result)"
say "완료 rc=0 — 시험용 Chrome 에 ${P_WEB} 마이크 권한 부여. 다음: 러너 1회차 h (Chrome 을 다시 띄우면 이 h 를 다시)"
exit 0
