#!/usr/bin/env bash
# h-mini-server-restart-dev.sh — mini 서버를 «V5_BACKEND_ENABLED 포함» 으로 다시 올리고, 웹을 dev(mock host + E2E 토큰)로 맞춘다. 실행은 오빠가 `! bash /tmp/h<N>` 로만.
#   (2026-10-24 · aifp-multihost-master-claude#3 · 러너 1회차 h313 5번째 실패: 녹음·발화·마이크 입력(v65_input_start)까지 갔으나 chunk_post_failed "audio_event 404" → host_empty)
#   원인 실측: gateway 로그 POST /v5/audio_event·/v5/sessions/init = 404 · worker 시작 로그 backend_enabled=false event_enabled=false.
#     gateway 는 V5_BACKEND_ENABLED 가 true 계열일 때만 /v5 라우터를 붙인다(gateway/main.py:139 · shared/config/v5_config.py). 이 맥 .env 는 켜짐인데 서버 h 의 주입 키 목록(KEYS)에 이름이 없어 mini 로 안 넘어갔다 → 서버 h 에 추가함.
#   하는 일(순서대로 · 하나라도 실패하면 거기서 멈춘다):
#     ① 서버 정지  (h-mini-byz-server-run.sh stop — 이 h 가 띄운 pid 만)
#     ② 서버 기동  (h-mini-byz-server-run.sh up  — 같은 sha 4c876d7f · 설치·빌드 표식이 같으면 재설치 없음 · KEY_SRC=dotenv · 이번엔 V5_BACKEND_ENABLED 포함)
#     ③ 웹을 dev 로  (h-mini-web-dev.sh — next dev + mock host + 브라우저 E2E 토큰, 시크릿은 stdin)
#     ④ 증거: gateway 가 /v5/sessions/init 에 404 가 아닌 응답(405·422 등)을 주는지 — 라우터가 붙었다는 뜻
#   시험용 Chrome(9333)·마이크 권한(세션)·터널·BlackHole 은 건드리지 않는다.
# rc: 0 성공 · 2/3/4/5 = 해당 단계 실패(위 단계 번호는 메시지에)
set -uo pipefail

HP="/Users/yoonhwan/Project/ai-feature-pack/.worktrees/multihost-plan/docs/multihost/h-plans"
MINI="${MINI:-mini}"; DRY="${DRY:-0}"; P_GW="${P_GW:-38312}"
say() { printf '[h-restart] %s\n' "$*"; }
die() { printf '[h-restart] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }

grep -q "V5_BACKEND_ENABLED" "$HP/h-mini-byz-server.sh" || die 2 "서버 h 의 KEYS 에 V5_BACKEND_ENABLED 가 없다 — 이 h 의 전제가 깨졌다"
[ -f "$HP/h-mini-byz-server-run.sh" ] && [ -f "$HP/h-mini-web-dev.sh" ] || die 2 "하위 h 파일이 없다"

if [ "$DRY" = "1" ]; then
  say "DRY — 하려던 일(쓰기 0): ① 서버 정지 → ② 서버 기동(V5_BACKEND_ENABLED 포함) → ③ 웹 dev 교체 → ④ /v5/sessions/init 이 404 가 아닌지 확인. 서버 h 자체에는 DRY 가 없어 여기서는 전제 파일·키 이름만 점검"
  say "        전제 OK: 서버 h KEYS 에 V5_BACKEND_ENABLED 있음 · 하위 h 2개 있음"
  PRE="$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=6 "$MINI" "echo gw_v5_init=\$(curl -s -o /dev/null -m 5 -w '%{http_code}' -X POST http://127.0.0.1:${P_GW}/v5/sessions/init 2>/dev/null); echo runner=\$(pgrep -f realtime_multi_e2e | wc -l | tr -d ' ')" 2>&1)" || die 2 "mini 접속 실패: ${PRE}"
  printf '%s\n' "$PRE" | sed 's/^/        /'
  exit 0
fi

R="$(timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=6 "$MINI" "pgrep -f realtime_multi_e2e | wc -l | tr -d ' '" 2>&1)" || die 2 "mini 접속 실패: ${R}"
[ "$R" = "0" ] || die 2 "러너가 돌고 있다(${R}개) — 끝난 뒤 다시"

say "1/4 서버 정지"
bash "$HP/h-mini-byz-server-run.sh" stop || die 3 "서버 정지 실패 — 위 출력 확인(서버가 이미 꺼져 있었다면 위 메시지로 판단)"
say "2/4 서버 기동 (BYZ main c34fc47f · V5_BACKEND_ENABLED 포함 · 코드가 바뀌면 설치·빌드가 몇 분 걸려 50초마다 «이어서 확인» 으로 최대 10회 다시 부른다)"
UPLOG="$(mktemp "${TMPDIR:-/tmp}/h-restart-up.XXXXXX")"; trap 'rm -f "$UPLOG"' EXIT
UP_OK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  bash "$HP/h-mini-byz-server-run.sh" up 2>&1 | tee "$UPLOG"
  RC="${PIPESTATUS[0]}"
  if [ "$RC" = "0" ]; then UP_OK=1; break; fi
  if grep -q -E "몇 분 뒤 같은 인자로 재실행|진행 중 — 몇 분" "$UPLOG"; then say "        설치·빌드 진행 중 — 45초 뒤 이어서(${i}/10)"; sleep 45; continue; fi
  break
done
[ "$UP_OK" = "1" ] || die 4 "서버 기동 실패 — 위 출력 확인"
say "3/4 웹 dev 교체"
bash "$HP/h-mini-web-dev.sh" || die 5 "웹 dev 교체 실패 — 위 출력 확인"

say "4/4 증거 — /v5 라우터가 붙었는지"
CODE="$(timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=6 "$MINI" "curl -s -o /dev/null -m 7 -w '%{http_code}' -X POST http://127.0.0.1:${P_GW}/v5/sessions/init 2>/dev/null" 2>&1)" || die 5 "증거 조회 실패: ${CODE}"
say "        POST /v5/sessions/init -> ${CODE}  (404 이면 라우터 없음)"
[ "$CODE" != "404" ] || die 5 "/v5/sessions/init 이 아직 404 — V5_BACKEND_ENABLED 가 gateway 에 안 들어갔다"
GPUENV="$(timeout 30 ssh -o BatchMode=yes -o ConnectTimeout=6 "$MINI" 'export PATH=/opt/homebrew/bin:$PATH; for p in $(pgrep -f "worker.main|worker/main|uvicorn.*worker|python.*worker" | head -3); do ps eww -p $p 2>/dev/null | tr " " "\n" | grep -c "^DEV_GPU_STATUS_URL=" ; done | sort -rn | head -1' 2>&1)" || GPUENV="?"
say "        worker env 에 DEV_GPU_STATUS_URL 이름 있음(1=있음 · 값 출력 0): ${GPUENV:-?}  (0·? 이면 STT 게이트가 로컬 Redis 하트비트로 떨어진다)"
say "완료 rc=0 — /v5 라우터 장착. 다음: 러너 1회차 h"
exit 0
