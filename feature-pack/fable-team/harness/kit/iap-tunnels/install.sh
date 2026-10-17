#!/usr/bin/env bash
# 로컬 IAP 터널 2개를 재부팅 뒤 launchd 로 자동 기동 (R327b · stt-tunnel/install.sh 모형 복제 — 포트·VM·원격 포트만 치환)
#   embed = 18712 → byz-agents-gce-stt-tts-dev:8100 (byz-embed · ★확정★ KakaoBot 실측)
#   llm   = 18703 → byz-agents-gce-llm-dev:8000     (byz-llm   · ★추정★ 명령 기록 없음 — 오빠 확인 전 설치 금지)
# 사용: bash install.sh <embed|llm> [render|install|status|uninstall] [--apply] [--oppa-confirmed]
#   render    : 치환한 plist 를 stdout 에 출력(변경 0)
#   install   : 기본 dry-run(할 일만 출력 · 변경 0) · --apply 일 때만 plist 쓰기 + launchctl bootstrap + LISTEN·health 확인
#   uninstall : 기본 dry-run · --apply 일 때만 launchd 항목 내림 + plist 삭제
#   llm 은 --oppa-confirmed 없으면 REJECT(rc=3) — 값이 추정이라 오빠가 확인한 뒤에만 설치한다. 확인값: /v1/models 200.
#   health: llm = http://127.0.0.1:18703/v1/models 200 (실패면 launchd 항목을 내리고 plist 삭제 · rc=5 · [HIL]) · embed = LISTEN 만(health 경로 기록 없음)
# 원칙: 포트를 이미 다른 프로세스가 쥐고 있으면 건드리지 않고 REJECT(rc=3) — 남의 터널을 죽이지 않는다. 외부 호출은 1회 7초 + 재시도 1회(7초 룰).
# 시험 주입: IAP_TUNNEL_{HOME,LAUNCHCTL,GCLOUD,WAIT,CALL_TMO} — 실 터널·실 launchd·실 홈 0 으로 돌릴 때만 쓴다.
# 종료코드: 0 완료(또는 dry-run·render) · 1 status 불일치 · 2 사용/환경 · 3 REJECT(변경 0) · 5 전환 실패(launchd 항목 내림·plist 삭제)
set -uo pipefail
HERE="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ZONE="asia-northeast3-a"
ACCOUNT="byz-local-dev@byz-agents-484214.iam.gserviceaccount.com"
HOME_DIR="${IAP_TUNNEL_HOME:-$HOME}"
LAUNCHCTL="${IAP_TUNNEL_LAUNCHCTL:-launchctl}"
WAIT="${IAP_TUNNEL_WAIT:-60}"
CALL_TMO="${IAP_TUNNEL_CALL_TMO:-7}"
DOMAIN="gui/$(id -u)"

die() { local rc="$1"; shift; echo "$*" >&2; exit "$rc"; }

NAME="${1:-}"; [ $# -gt 0 ] && shift
case "$NAME" in
  embed) PORT=18712; VM="byz-agents-gce-stt-tts-dev"; REMOTE=8100; HEALTH_PATH=""; CONFIRM_NEEDED=0 ;;
  llm)   PORT=18703; VM="byz-agents-gce-llm-dev";     REMOTE=8000; HEALTH_PATH="/v1/models"; CONFIRM_NEEDED=1 ;;
  *) die 2 "사용: install.sh <embed|llm> [render|install|status|uninstall] [--apply] [--oppa-confirmed]" ;;
esac
ACTION="install"; APPLY=0; CONFIRMED=0
while [ $# -gt 0 ]; do
  case "$1" in
    render|install|status|uninstall) ACTION="$1" ;;
    --apply) APPLY=1 ;;
    --oppa-confirmed) CONFIRMED=1 ;;
    *) die 2 "사용: install.sh <embed|llm> [render|install|status|uninstall] [--apply] [--oppa-confirmed]" ;;
  esac
  shift
done

LABEL="com.byz.iap-tunnel-$PORT"
PLIST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"
LOG="/tmp/byz-iap-tunnel-$PORT.log"

holder_pid() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null | head -1; }
loaded() { "$LAUNCHCTL" print "$DOMAIN/$LABEL" >/dev/null 2>&1; }
say() { if [ "$APPLY" = 1 ]; then echo "APPLY $*"; else echo "DRY $*"; fi; }

gcloud_bin() { local g="${IAP_TUNNEL_GCLOUD:-$(command -v gcloud)}"; [ -n "$g" ] || die 2 "gcloud 없음 — PATH 확인"; echo "$g"; }

render_plist() {  # stdout
  local gcloud; gcloud="$(gcloud_bin)" || exit $?
  sed -e "s|__GCLOUD__|$gcloud|g" -e "s|__VM__|$VM|g" -e "s|__REMOTE_PORT__|$REMOTE|g" -e "s|__PORT__|$PORT|g" \
      -e "s|__ZONE__|$ZONE|g" -e "s|__ACCOUNT__|$ACCOUNT|g" -e "s|__HOME__|$HOME_DIR|g" \
      -e "s|__PATH__|$(dirname "$gcloud"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin|g" \
      "$HERE/com.byz.iap-tunnel.plist.template"
}

wait_listen() {  # $1=want(1|0) — 최대 WAIT 초
  local i=0
  while [ "$i" -lt "$WAIT" ]; do
    if [ "$1" = 1 ]; then [ -n "$(holder_pid)" ] && return 0; else [ -z "$(holder_pid)" ] && return 0; fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

health() {  # llm 만 — 1회 CALL_TMO 초 + 재시도 1회 · 200 이면 ok
  [ -n "$HEALTH_PATH" ] || { echo skip; return; }
  local i code
  for i in 1 2; do
    code="$(curl -s --max-time "$CALL_TMO" -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT$HEALTH_PATH" 2>/dev/null)"
    [ "$code" = 200 ] && { echo ok; return; }
  done
  echo fail
}

rollback() {  # 실패 복구: launchd 항목 내리고 plist 삭제 — 설치하지 않은 상태로 되돌린다
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  rm -f "$PLIST"
  die 5 "ROLLBACK ok(launchd 내림 · plist 삭제) — $1 · 로그 $LOG · [HIL] 상위에 올릴 것"
}

status() {
  local ld=missing lp h=skip
  loaded && ld=loaded
  lp="$(holder_pid)"
  [ -n "$lp" ] && h="$(health)"
  echo "launchd=$ld listen=${lp:-none} health=$h"
  [ "$ld" = loaded ] && [ -n "$lp" ] && [ "$h" != fail ]
}

install() {
  if [ "$CONFIRM_NEEDED" = 1 ] && [ "$CONFIRMED" = 0 ]; then
    die 3 "REJECT $NAME 은 값이 추정(VM=$VM · 원격 $REMOTE)이라 오빠 확인 전 설치 금지 — 확인 뒤 --oppa-confirmed (변경 0)"
  fi
  if loaded && [ -n "$(holder_pid)" ]; then
    echo "ALREADY 설치됨"
    if [ "$(health)" = fail ]; then   # 신규·재적재 공통 — health 실패는 같은 처리
      [ "$APPLY" = 1 ] || { say "health $HEALTH_PATH 200 아님 — --apply 면 rollback"; return 0; }
      rollback "재적재 상태에서 health $HEALTH_PATH 200 아님 — 값 추정 오류 가능"
    fi
    status; return
  fi
  local lp; lp="$(holder_pid)"
  [ -z "$lp" ] || die 3 "REJECT 포트 $PORT 를 이미 pid $lp 가 쥐고 있음 — 남의 터널은 건드리지 않음 (변경 0)"
  local tmp; tmp="$(mktemp)"; trap 'rm -rf "$tmp"' EXIT
  render_plist > "$tmp" || exit $?
  if command -v plutil >/dev/null 2>&1; then plutil -lint "$tmp" >/dev/null || die 2 "plist lint 실패"; fi
  say "plist $PLIST ($NAME · $PORT → $VM:$REMOTE)"
  [ "$APPLY" = 1 ] || { say "launchctl bootstrap $DOMAIN $PLIST"; return 0; }
  mkdir -p "$(dirname "$PLIST")" && cp "$tmp" "$PLIST" || die 2 "plist 쓰기 실패"
  "$LAUNCHCTL" bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || rollback "launchctl bootstrap 실패"
  wait_listen 1 || rollback "포트 $PORT LISTEN 안 뜸(${WAIT}s)"
  [ "$(health)" != fail ] || rollback "health $HEALTH_PATH 200 아님 — 값 추정 오류 가능"
  echo "INSTALLED launchd=$LABEL listen=$(holder_pid) plist=$PLIST"
}

uninstall() {  # 되돌림: launchd 항목 + plist 제거 — 변경이므로 --apply 일 때만 (기본 dry-run)
  say "launchctl bootout $DOMAIN/$LABEL + plist 삭제 $PLIST"
  [ "$APPLY" = 1 ] || return 0
  "$LAUNCHCTL" bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  rm -f "$PLIST"
  wait_listen 0 || die 5 "UNINSTALL 후에도 $PORT 가 안 비워짐(소유 pid $(holder_pid))"
  echo "UNINSTALLED $LABEL"
}

case "$ACTION" in
  render) render_plist ;;
  install) install ;;
  status) status ;;
  uninstall) uninstall ;;
esac
