#!/usr/bin/env bash
# h-mini-e2e-round1-run.sh — mini 에서 BYZ e2e 러너 «1회차»(마이크 1회 → STT 최종본 1건)를 돌린다.
#   초안 v2(2026-10-22 · pi 초안 → aifp-multihost-master-claude#1 검수·재작성) · 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   근거: docs/multihost/measured-runner-cli-20261022.md (sha 33335c7a 기준 줄번호)
#     · 최소 조합 = `--mr-scenario baseline-ko-en --mr-turn-limit 1 --engine say` (4895·4898·4897) — press 1회
#     · 성공 판정 문자열 = `✅ host 단일 버블 (delta=1, polished Nchars)` (2891)
#     · 러너는 Chrome 을 열지 않는다(CDP 9333 전제 · 탭은 러너가 cdp_new_tab) · 선행조건 자기검사 없음 → 이 h 가 preflight
# 호출: [NEW=1] [ACTION=run|stop] bash /tmp/h<N>
#   기본 동작 = 이미 도는 회차가 있으면 «상태만 확인», 끝난 회차가 있으면 «결과만 보여 줌». 새 회차(= 새 press)는 NEW=1 일 때만 시작한다
#   → 같은 h 를 실수로 두 번 쳐도 마이크가 두 번 눌리지 않는다(오디오 press 는 한 번에 하나).
# 원칙: ★기존 러너 그대로★(trusted `Input.dispatchMouseEvent`) — 클릭 대체·DOM/Redis 주입 코드를 새로 만들지 않는다(하드 룰 11)
#       비밀(BYZ_E2E_JWT_SECRET)은 ssh stdin 으로만 → 명령줄·mini 디스크 0 · 값 출력 0 · 외부 호출 단건 70초 천장(러너는 mini 백그라운드 + 짧은 폴링)
# 검수에서 pi 초안 대비 고친 것: ①JWT 시크릿을 모으기만 하고 러너에 전달하지 않던 것 ②러너(수 분)를 70초 ssh 한 번에 걸어 끊기던 것
#   ③`pgrep -c`(macOS 에 없음)로 «다른 오디오 회차» 검사가 항상 0 이던 것 + pgrep -f 가 자기 명령줄에 걸리는 문제 ④`set -e` 가 몰래 켜지던 것
#   ⑤중첩 따옴표 preflight → bash -s stdin ⑥같은 h 재실행 시 press 이중 발사 방지 ⑦러너 위치를 서버 h 가 반입한 전체 repo(BYZ-Agents)로
# rc: 0 성공(STT 최종본 1건) · 2 사전점검 실패 · 3 진행 중(같은 h 로 이어서 확인) · 5 러너 실패/시간초과
set -uo pipefail

MINI="${MINI:-mini}"
SRC="${SRC:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"
P_GW="${P_GW:-38312}"; P_WEB="${P_WEB:-38314}"; CDP="${CDP:-9333}"
SCEN="${SCEN:-baseline-ko-en}"; TURNS="${TURNS:-1}"
RUN_MAX="${RUN_MAX:-420}"                  # 러너 실행 상한(초) — 넘으면 러너만 종료
NEW="${NEW:-0}"; ACTION="${ACTION:-run}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[h-run1] %s\n' "$*"; }
die() { printf '[h-run1] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
# ★mini 원격은 항상 PATH 접두★ — 명령줄에는 비밀이 없다. zsh 함정: 세션 지정 `-t =이름` 금지(이 h 는 tmux 를 쓰지 않음)
ms() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }

# ── ACTION=stop — 이 h 가 연 러너만 ───────────────────────────────────────
if [ "$ACTION" = "stop" ]; then
  say "STOP — .h-run1.pid 의 러너(와 그 자식)만"
  ms 20 'cd $HOME/Project/BYZ-Agents 2>/dev/null || exit 0; [ -f .h-run1.pid ] || { echo none; exit 0; }; p=$(cat .h-run1.pid); for c in $(pgrep -P "$p" 2>/dev/null); do kill "$c" 2>/dev/null; done; kill "$p" 2>/dev/null; echo stopped_pid=$p' 2>&1 | sed 's/^/        /'
  exit 0
fi

# ── 0) 로컬 사전점검 ─────────────────────────────────────────────────────
say "0/6 로컬 사전점검"
[[ "$P_GW" =~ ^383[0-9][0-9]$ && "$P_WEB" =~ ^383[0-9][0-9]$ ]] || die 2 "포트는 38301~38399 만(받은 값: $P_GW/$P_WEB)"
[ -f "$SRC/.env" ] || die 2 "BYZ .env 가 없다(JWT 시크릿 «한 줄»만 쓴다 · 값은 출력하지 않는다): $SRC/.env"
say "        scenario=$SCEN turns=$TURNS · gw=$P_GW web=$P_WEB cdp=$CDP · NEW=$NEW"

# ── 1) 상태 확인 — 이미 돌거나 끝난 회차가 있나 ──────────────────────────
STATE="$(ms 15 'cd $HOME/Project/BYZ-Agents 2>/dev/null || { echo norepo; exit 0; }; if [ -f .h-run1.pid ] && kill -0 "$(cat .h-run1.pid)" 2>/dev/null; then echo running; elif [ -f .h-run1.rc ]; then echo finished; else echo none; fi' 2>&1)" || STATE=unknown
case "$STATE" in norepo) die 2 "mini ~/Project/BYZ-Agents 가 없다 — 서버 h(h-mini-byz-server.sh) 먼저";; esac
if [ "$STATE" = "running" ]; then say "이미 러너가 도는 중 — 새로 시작하지 않고 진행만 확인한다"; fi
if [ "$STATE" = "finished" ] && [ "$NEW" != "1" ]; then say "끝난 회차가 있다 — 결과만 다시 보여 준다(새 회차는 NEW=1)"; fi

START=0
if [ "$STATE" = "none" ] || { [ "$STATE" = "finished" ] && [ "$NEW" = "1" ]; }; then START=1; fi

if [ "$START" = "1" ]; then
  # ── 2) preflight (전부 읽기 · bash -s 로 stdin) ─────────────────────────
  say "1/6 preflight — 서버 / CDP / 오디오 / tts-say / 파이썬 / 다른 오디오 회차"
  PRE="$(ms 40 'bash -s' 2>&1 <<EOF
echo gw=\$(curl -s -L -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:$P_GW/health || true)
echo web=\$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:$P_WEB/ || true)
echo tun=\$(lsof -nP -iTCP:${LOOM_PG_TUNNEL_PORT:-38309} -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' ')
echo tun_llm=\$(lsof -nP -iTCP:8000 -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' ')
echo tun_stt=\$(lsof -nP -iTCP:8001 -sTCP:LISTEN 2>/dev/null | wc -l | tr -d ' ')
echo llm_http=\$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8000/health || true)
echo stt_http=\$(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:8001/health || true)
echo cdp=\$(curl -s -m 4 http://127.0.0.1:$CDP/json/version | grep -c Chrome || true)
echo blackhole=\$(system_profiler SPAudioDataType 2>/dev/null | grep -c 'BlackHole 2ch')
echo outdev=\$(system_profiler SPAudioDataType 2>/dev/null | grep -B8 'Default Output Device: Yes' | grep -E '^ {8}[A-Za-z].*:\$' | head -1 | tr -d ' :')
echo ttssay=\$(test -x \$HOME/.local/bin/tts-say && echo yes || echo NO)
echo timeout=\$(command -v timeout >/dev/null && echo yes || echo NO)
echo runner=\$(test -f \$HOME/Project/BYZ-Agents/tests/e2e/realtime_multi_e2e.py && echo yes || echo NO)
A=\$HOME/Project/BYZ-Agents/.venv/bin/python; B=\$HOME/Project/BYZ-e2e/.venv/bin/python
if [ -x \$A ] && \$A -c 'import websockets, jwt' 2>/dev/null; then echo py=A; elif [ -x \$B ] && \$B -c 'import websockets, jwt' 2>/dev/null; then echo py=B; else echo py=NONE; fi
echo busy=\$(( \$(pgrep -f '[r]ealtime_multi_e2e.py' | wc -l) + \$(pgrep -x afplay | wc -l) + \$(pgrep -x say | wc -l) ))
echo hostname=\$(hostname -s)
EOF
)" || die 2 "mini 접속 실패: $PRE"
  printf '%s\n' "$PRE" | sed 's/^/        /'
  get() { printf '%s\n' "$PRE" | sed -n "s/^$1=//p" | head -1; }
  WANT=()
  [ "$(get gw)"  = "200" ] || WANT+=("gateway health 200 아님('$(get gw)') → 서버 h(h-mini-byz-server.sh) 먼저")
  [ "$(get web)" = "200" ] || WANT+=("web / 200 아님('$(get web)') → 서버 h 먼저")
  [ "$(get tun)" -ge 1 ] 2>/dev/null || WANT+=("mini 127.0.0.1:${LOOM_PG_TUNNEL_PORT:-38309} 포워딩이 없다(이 맥 loom 터널로 가는 역방향 ssh 가 죽음) → 이 맥이 켜져 있는지 확인 후 서버 h(h-mini-byz-server-run)를 다시: 서버 DB 가 이 맥 터널에 의존")
  [ "$(get tun_llm)" -ge 1 ] 2>/dev/null || WANT+=("mini 127.0.0.1:8000(LLM) 포워딩이 없다(이 맥 launchd 18703 으로 가는 역방향 ssh) → 서버 h 다시")
  [ "$(get tun_stt)" -ge 1 ] 2>/dev/null || WANT+=("mini 127.0.0.1:8001(GPU STT/TTS) 포워딩이 없다 → 서버 h 다시")
  [ "$(get llm_http)" = "200" ] || WANT+=("LLM 포워딩 health 200 아님('$(get llm_http)') → 이 맥 18703 터널/GPU VM 상태 확인")
  [ "$(get stt_http)" = "200" ] || WANT+=("STT/TTS 포워딩 health 200 아님('$(get stt_http)') → 이 맥 8001 터널 확인")
  [ "$(get cdp)" -ge 1 ] 2>/dev/null || WANT+=("CDP $CDP 응답 없음 → mini 앞 체크리스트 4번(시험용 Chrome 띄우기)")
  [ "$(get blackhole)" -ge 1 ] 2>/dev/null || WANT+=("BlackHole 2ch 장치 안 보임")
  case "$(get outdev)" in *BlackHole*|*Multi-Output*) ;; *) WANT+=("출력 기본값이 BlackHole/Multi-Output 이 아님('$(get outdev)') → 체크리스트 2번");; esac
  [ "$(get ttssay)" = "yes" ]  || WANT+=("tts-say 없음 → h-mini-tts-say.sh 먼저")
  [ "$(get timeout)" = "yes" ] || WANT+=("timeout 명령 없음")
  [ "$(get runner)" = "yes" ]  || WANT+=("러너 코드 없음(~/Project/BYZ-Agents/tests/e2e) → 서버 h 가 끝났는지")
  [ "$(get py)" != "NONE" ]    || WANT+=("websockets·jwt 가 있는 파이썬이 없다 → h-mini-e2e-setup.sh(venv) 먼저")
  [ "$(get busy)" = "0" ]      || WANT+=("다른 오디오 회차/재생이 $(get busy)건 돌고 있음 → 끝난 뒤(오디오 press 는 한 번에 하나)")
  if [ "${#WANT[@]}" -gt 0 ]; then
    for w in "${WANT[@]}"; do say "        ✗ $w"; done
    die 2 "선행 조건 ${#WANT[@]}건 미충족 — 위 1줄씩 처리한 뒤 같은 h 를 다시"
  fi
  say "        preflight 전부 통과 (py=$(get py), 출력=$(get outdev))"
  HOST="$(get hostname)"
  if [ "${DRY:-0}" = "1" ]; then say "DRY — preflight 까지만(쓰기 0). 러너 시작 안 함"; exit 0; fi

  # ── 3) 시작 — JWT 시크릿은 stdin 으로만 ────────────────────────────────
  say "2/6 러너 시작 (mini 백그라운드 · 상한 ${RUN_MAX}s · 시크릿 stdin)"
  JWT="$(grep -m1 -E '^BYZ_E2E_JWT_SECRET=' "$SRC/.env" | sed "s/^BYZ_E2E_JWT_SECRET=//; s/^[\"']//; s/[\"']\$//" | tr -d '\r')"
  [ -n "$JWT" ] || say "        ⚠ BYZ_E2E_JWT_SECRET 이 .env 에 없다 — 크레딧 경로가 None 이 될 수 있다(러너는 계속 돈다)"
  # 시크릿은 600 임시 파일 → ssh stdin 으로만(h-mini-byz-server.sh 와 같은 꼴 · 화면 출력 0 · 끝나면 삭제)
  ENVF="$(mktemp "${TMPDIR:-/tmp}/h-run1-env.XXXXXX")"; chmod 600 "$ENVF"; trap 'rm -f "$ENVF"' EXIT
  printf 'export BYZ_E2E_JWT_SECRET=%q\n' "$JWT" > "$ENVF"
  {
    cat "$ENVF"
    cat <<EOS
cd "\$HOME/Project/BYZ-Agents" || exit 1
export BYZ_WEB_BASE=http://127.0.0.1:$P_WEB BYZ_GATEWAY_BASE=http://127.0.0.1:$P_GW CDP_PORT=$CDP BYZ_WORKER_LOG=/tmp/h-byz-worker.log
A="\$HOME/Project/BYZ-Agents/.venv/bin/python"; B="\$HOME/Project/BYZ-e2e/.venv/bin/python"
if [ -x "\$A" ] && "\$A" -c 'import websockets, jwt' 2>/dev/null; then PY="\$A"; else PY="\$B"; fi
rm -f .h-run1.rc; LOG=".h-run1-\$(date +%Y%m%d-%H%M%S).log"; echo "\$LOG" > .h-run1.logpath; : > "\$LOG"; chmod 600 "\$LOG"
nohup bash -c 'timeout $RUN_MAX "\$0" tests/e2e/realtime_multi_e2e.py --mr-scenario $SCEN --mr-turn-limit $TURNS --engine say > "\$1" 2>&1; echo \$? > .h-run1.rc' "\$PY" "\$LOG" </dev/null >/dev/null 2>&1 &
echo \$! > .h-run1.pid
echo started_pid=\$(cat .h-run1.pid) log=\$LOG
EOS
  } | timeout 30 ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; bash -s" 2>&1 | sed 's/^/        /' || die 5 "러너 시작 실패"
  rm -f "$ENVF"; unset JWT
else
  HOST="$(ms 10 'hostname -s' 2>/dev/null)"
fi

# ── 4) 진행 폴링(짧은 호출만) ────────────────────────────────────────────
say "3/6 진행 확인 (최대 55초 · 더 걸리면 같은 h 로 이어서)"
DONE=0
for i in 1 2 3 4 5 6 7 8 9 10 11; do
  R="$(ms 10 'cd $HOME/Project/BYZ-Agents; if [ -f .h-run1.rc ]; then echo done; else echo wait; fi' 2>/dev/null)" || R=wait
  [ "$R" = "done" ] && { DONE=1; break; }
  sleep 5
done
LOGP="$(ms 10 'cat $HOME/Project/BYZ-Agents/.h-run1.logpath 2>/dev/null' 2>/dev/null)"
if [ "$DONE" != "1" ]; then
  ms 10 "tail -n 3 \$HOME/Project/BYZ-Agents/$LOGP 2>/dev/null | cut -c1-160" 2>&1 | sed 's/^/        진행| /'
  say "        아직 도는 중 — 러너는 mini 에서 계속 돈다. 같은 h 를 다시 실행하면 이어서 확인(새 press 안 함)"
  exit 3
fi

# ── 5) 결과 ──────────────────────────────────────────────────────────────
say "4/6 결과 (로그 끝 40줄)"
ms 20 "tail -n 40 \$HOME/Project/BYZ-Agents/$LOGP 2>/dev/null | cut -c1-200" 2>&1 | sed 's/^/        /'
RC="$(ms 10 'cat $HOME/Project/BYZ-Agents/.h-run1.rc 2>/dev/null' 2>/dev/null)"
OK_LINE="$(ms 20 "grep -F '✅ host 단일 버블' \$HOME/Project/BYZ-Agents/$LOGP 2>/dev/null | head -1 | cut -c1-200" 2>/dev/null)"
# 2026-10-25: «✅ host 단일 버블» 은 ptt_multi_utterance(5문장 1PTT) 시나리오만 찍는다(realtime_multi_e2e.py:2893). 기본 시나리오 baseline-ko-en 의 합격 표지는 MR:corpus «turn_ok» + «scenario_done … ok=N/N errors=0».
MR_OK="$(ms 20 "grep 'scenario_done id=' \$HOME/Project/BYZ-Agents/$LOGP 2>/dev/null | sed -nE 's/.*scenario_done id=([^ ]+) ok=([0-9]+)\\/([0-9]+) errors=0.*/\\1 \\2 \\3/p' | awk '\$2==\$3 && \$2>0 {print \"MR scenario_done \"\$1\" ok=\"\$2\"/\"\$3\" errors=0\"; exit}'" 2>/dev/null)"
[ -z "$OK_LINE" ] && [ -n "$MR_OK" ] && OK_LINE="$MR_OK"
say "5/6 증거 3줄"
say "        · runner_rc=${RC:-?} · 성공줄: ${OK_LINE:-없음}"
say "        · hostname=${HOST:-?}  (BYZs-Mac-mini 여야 mini)"
ms 20 'cd $HOME/Project/BYZ-Agents; tot=0; while read -r pid; do r=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d " "); [ -n "$r" ] || continue; tot=$((tot+r/1024)); done < .h-pids 2>/dev/null; echo "total_rss=${tot}MB"' 2>&1 | sed 's/^/        · 서버 /'
if [ -n "$OK_LINE" ] && [ "${RC:-1}" = "0" ]; then say "6/6 성공 — STT 최종본 1건 확인"; exit 0; fi
say "6/6 실패 — 전체 로그: ssh $MINI 'tail -100 ~/Project/BYZ-Agents/$LOGP'"
exit 5
