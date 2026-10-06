#!/usr/bin/env bash
# ft-env-fingerprint.sh — press 전 «테스트 환경 버전» 지문 1장 (읽기 전용)
#
# 오빠 지시(2026-09-21): 「테스트환경 버전 철저히 체크 서포트」
# 배경: 계기가 틀리면 판정도 틀린다 — runner sid 불일치·늦은 로그 혼입·구세대 프로세스로
#       회차가 통째로 버려진 적이 반복됐다. press 발사 «전»에 이 한 장을 찍고 보고 첫 줄에 붙인다.
#
# 사용: bash .fable-team/bin/ft-env-fingerprint.sh
# 종료코드: 0=전 구성요소 정합 / 1=구세대 프로세스 존재(press 금지)

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

HEAD_SHA=$(git log -1 --format='%h')
HEAD_EPOCH=$(git log -1 --format='%ct')
HEAD_HUMAN=$(git log -1 --format='%cd' --date=format:'%m-%d %H:%M:%S')
echo "HEAD           : $HEAD_SHA ($HEAD_HUMAN)"

stale=0

# ★lstart 문자열 파싱은 «로캘» 에 깨진다 — 한글 로캘에서 「월 9/21 15:21:27 2026」 이 나와
#   date -j -f '%a %b %d %T %Y' 가 실패한다(2026-09-21 실측). LC_ALL=C 로 강제해서 읽는다.★
pid_epoch() {
  local raw
  raw=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//;s/  */ /g')
  [ -z "$raw" ] && { echo 0; return; }
  LC_ALL=C date -j -f '%a %b %d %T %Y' "$raw" '+%s' 2>/dev/null || echo 0
}
pid_human() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//;s/ *$//'; }


# 경로별 «마지막으로 그 컴포넌트를 건드린 커밋» 시각과 프로세스 기동 시각을 비교한다.
check() { # name port paths...
  local name=$1 port=$2; shift 2
  local pid start_epoch last_epoch last_sha
  # ★uvicorn --reload 는 부모(reload master)와 자식(worker)이 «둘 다» 포트를 물고 있고,
  #   자식은 감시 경로가 바뀔 때마다 갈린다 — 그래서 lsof 첫 줄을 잡으면 «자식의 기동시각»을
  #   서비스 기동시각으로 오독한다(2026-09-21 실측: 부모 24123=15:21:27 인데 자식은 20:20→20:23 로 계속 교체).
  #   ★판정은 «부모(가장 오래된 PID)» 로 하고, 자식이 더 새로우면 reload 가 돌고 있다는 사실을 따로 적는다.★
  local pids child_note='' newest=''
  pids=$(lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null)
  if [ -z "$pids" ]; then
    printf '%-14s : (미기동) port=%s\n' "$name" "$port"
    stale=1; return
  fi
  # etimes = 살아 있은 초. 큰 쪽이 «먼저 뜬 것»(= reload 부모), 작은 쪽이 «방금 갈린 자식».
  pid=$(for p in $pids; do echo "$(pid_epoch "$p") $p"; done | sort -n | head -1 | awk '{print $2}')
  newest=$(for p in $pids; do echo "$(pid_epoch "$p") $p"; done | sort -n | tail -1 | awk '{print $2}')
  if [ "$newest" != "$pid" ]; then
    child_note=" ★reload 자식 PID=$newest($(pid_human "$newest"))— press 중 리로드 주의★"
  fi
  start_epoch=$(pid_epoch "$pid")
  last_sha=$(git log -1 --format='%h' -- "$@" 2>/dev/null)
  last_epoch=$(git log -1 --format='%ct' -- "$@" 2>/dev/null)
  local verdict='정합'
  if [ -n "$last_epoch" ] && [ -n "$start_epoch" ] && [ "$start_epoch" -lt "$last_epoch" ]; then
    verdict='★구세대 — 재기동 필요★'; stale=1
  fi
  printf '%-14s : PID=%-7s 기동=%s  마지막변경=%s(%s)  %s%s\n' \
    "$name" "$pid" "$(pid_human "$pid")" \
    "${last_sha:-none}" "$(date -r "${last_epoch:-0}" '+%H:%M:%S' 2>/dev/null)" "$verdict" "$child_note"
}

check FE        3001 clients/web
check gateway   8080 gateway live/gateway live/shared
check worker    8081 worker live/worker
# ★gpu-wrap 은 «원격» 실행본이다 — :8001 의 로컬 PID 는 터널/프록시라 기동시각 비교가 성립하지 않는다.
#   (2026-09-21 실측: 로컬 PID 29414 는 09-19 기동인데 원격 wrapper 는 18:38 반영본이었다.)
#   원격 반영 여부는 컨테이너 PID1 경로+SHA 로만 확인한다 — 여기서는 비교하지 않고 사실만 적는다.
gwpid=$(lsof -ti:8001 -sTCP:LISTEN 2>/dev/null | head -1)
printf '%-14s : local PID=%-7s (터널/프록시 — 기동시각 비교 무의미) · 마지막 변경=%s(%s) · ★원격 실행본 SHA 는 arch 가 컨테이너 PID1 로 확인★\n' \
  "gpu-wrap" "${gwpid:-none}" \
  "$(git log -1 --format='%h' -- infrastructure/gpu 2>/dev/null)" \
  "$(git log -1 --format='%cd' --date=format:'%H:%M:%S' -- infrastructure/gpu 2>/dev/null)"

echo "--- FE 런타임 env (ps eww 직독) ---"
fepid=$(lsof -ti:3001 -sTCP:LISTEN 2>/dev/null | head -1)
if [ -n "$fepid" ]; then
  ppid=$(ps -o ppid= -p "$fepid" | tr -d ' ')
  for x in "$fepid" "$ppid"; do
    ps eww -p "$x" 2>/dev/null | tr ' ' '\n' \
      | grep -E '^(NEXT_PUBLIC_BUILD_TAG|NEXT_PUBLIC_DEV_MOCK_HOST|NEXT_PUBLIC_V6_RT|NEXT_PUBLIC_V5_RT|BYZ_REALTIME_MODE)=' \
      | tr '\n' ' '
  done
  echo
fi

echo "--- health / GPU ---"
for u in http://localhost:8080/health http://localhost:8081/health http://localhost:8001/health; do
  printf '%-34s %s\n' "$u" "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$u")"
done
curl -s -m 5 http://localhost:8080/gpu/status; echo
echo "  (주의: local GET /gpu/status 는 DEV_GPU_STATUS_URL=prod-dev 프록시다 — 로컬 GPU 상태가 아니다.)"
echo "  (주의: ttl 은 alive 임대이지 WARM 창 길이가 아니다.)"

echo "--- 미커밋 ---"
git status --short | head -10

if [ "$stale" -ne 0 ]; then
  echo "판정: ★구세대 프로세스 존재 — press 금지, 재기동 먼저★"
  exit 1
fi
echo "판정: 전 구성요소 정합 — press 가능"
exit 0
