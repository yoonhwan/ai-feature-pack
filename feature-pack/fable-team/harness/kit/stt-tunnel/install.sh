#!/usr/bin/env bash
# 로컬 STT 터널(:8001 → byz-agents-gce-stt-tts-dev:8000)을 손 기동 nohup 에서 launchd 상주로 (ops R179 · 이슈 #1584)
# 사용: bash install.sh [install|status|uninstall]      (기본 install · 머신마다 1회 · ★집행은 master 순번 + press 창 밖★)
# 원칙(loom-tunnel/install.sh 와 같은 순서): «옛 터널을 끊는 것» 은 «새 경로가 health 200 까지 확인된 뒤» 에만 —
#   ①옛 터널이 살아 있는 동안 빈 포트에서 같은 ssh 명령을 미리 열어 /health 200 → ②옛 pid 종료(argv·시작시각 재대조) →
#   launchd 기동 → :8001 LISTEN + /health 200 → ③실패면 launchd 항목을 내리고 옛 nohup 줄을 출력(rc=5).
# 시험 주입: STT_TUNNEL_{PORT,AGENTS_DIR,WAIT,KILL,PREKILL,CALL_TMO,HEALTH_CMD} — 실 터널·실 launchd 0 으로 돌릴 때만 쓴다.
# 종료코드: 0 완료 · 1 status 불일치 · 2 사용/환경 · 3 REJECT(포트를 쥔 게 옛 nohup 터널이 아님 · 변경 0)
#           4 옛 터널 종료 실패 · 5 전환 실패(launchd 항목 내림 · 옛 줄 수동 복구) · 6 사전검증 실패(전환 0 · 옛 터널 그대로)
set -uo pipefail
HERE="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.byz.stt-tunnel-8001"
PORT="${STT_TUNNEL_PORT:-8001}"
VM="byz-agents-gce-stt-tts-dev"
ZONE="asia-northeast3-a"
ACCOUNT="byz-local-dev@byz-agents-484214.iam.gserviceaccount.com"
AGENTS_DIR="${STT_TUNNEL_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS_DIR/$LABEL.plist"
WAIT="${STT_TUNNEL_WAIT:-60}"
KILL="${STT_TUNNEL_KILL:-kill}"          # 옛 터널 pid 종료용
PREKILL="${STT_TUNNEL_PREKILL:-kill}"    # 내가 연 사전검증 프로세스 종료용
CALL_TMO="${STT_TUNNEL_CALL_TMO:-7}"     # 외부 호출 1회 상한(초) — 7초 룰 + 재시도 1회
DOMAIN="gui/$(id -u)"
LOG="/tmp/byz-stt-tunnel-8001.log"
OLD_LINE="nohup gcloud compute start-iap-tunnel $VM 8000 --local-host-port=localhost:$PORT --zone=$ZONE --account=$ACCOUNT >> /tmp/byz-iap-tunnel.log 2>&1 & disown"

die() { local rc="$1"; shift; echo "$*" >&2; exit "$rc"; }
holder_pid() { lsof -nP -iTCP:"${1:-$PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1; }
loaded() { launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }
pfield() { ps -ww -o "$1=" -p "$2" 2>/dev/null | sed 's/^ *//;s/ *$//'; }

# 외부 호출은 1회 CALL_TMO 초 + 실패 시 재시도 1회 (7초 룰) — curl 자체 --max-time 으로 끝난다.
health() {  # $1=port → 200 이면 ok
  local port="${1:-$PORT}" i code
  for i in 1 2; do
    if [ -n "${STT_TUNNEL_HEALTH_CMD:-}" ]; then
      STT_TUNNEL_HEALTH_PORT="$port" bash -c "$STT_TUNNEL_HEALTH_CMD" >/dev/null 2>&1 && { echo ok; return; }
    else
      code="$(curl -s --max-time "$CALL_TMO" -o /dev/null -w '%{http_code}' "http://localhost:$port/health" 2>/dev/null)"
      [ "$code" = 200 ] && { echo ok; return; }
    fi
  done
  echo fail
}

# 옛 터널 정확 대조: argv 토큰에서 start-iap-tunnel·VM·8000·--local-host-port·--zone 을 «정확히» 비교 (부분 문자열 금지)
tok_has() { local want="$1" t; shift; for t in "$@"; do [ "$t" = "$want" ] && return 0; done; return 1; }
old_match() {  # $1=argv 문자열
  [ -n "$1" ] || return 1
  local -a t; read -ra t <<< "$1"
  tok_has start-iap-tunnel "${t[@]}" && tok_has "$VM" "${t[@]}" && tok_has 8000 "${t[@]}" \
    && tok_has "--local-host-port=localhost:$PORT" "${t[@]}" && tok_has "--zone=$ZONE" "${t[@]}"
}
old_sig() { local cmd; cmd="$(pfield command "$1")"; old_match "$cmd" || return 1; printf '%s|%s' "$cmd" "$(pfield lstart "$1")"; }

render_plist() {
  local gcloud; gcloud="$(command -v gcloud)" || die 2 "gcloud 없음 — PATH 확인"
  mkdir -p "$AGENTS_DIR"
  sed -e "s|__GCLOUD__|$gcloud|" -e "s|__VM__|$VM|" -e "s|__ZONE__|$ZONE|" -e "s|__ACCOUNT__|$ACCOUNT|" \
      -e "s|__PORT__|$PORT|" -e "s|__HOME__|$HOME|" \
      -e "s|__PATH__|$(dirname "$gcloud"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin|" \
      "$HERE/com.byz.stt-tunnel-8001.plist.template" > "$PLIST"
  if command -v plutil >/dev/null 2>&1; then plutil -lint "$PLIST" >/dev/null || die 2 "plist lint 실패: $PLIST"; fi
}

wait_listen() {  # $1=want(1|0) [$2=port] — 최대 WAIT 초
  local i=0
  while [ "$i" -lt "$WAIT" ]; do
    if [ "$1" = 1 ]; then [ -n "$(holder_pid "${2:-}")" ] && return 0; else [ -z "$(holder_pid "${2:-}")" ] && return 0; fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

is_descendant() {  # $1=pid $2=조상 — 최대 6단계
  local p="$1" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 6 ]; do
    [ "$p" = "$2" ] && return 0
    p="$(pfield ppid "$p")"; i=$((i + 1))
  done
  return 1
}

# ① 사전검증: 옛 터널이 살아 있는 동안 38301~38399 빈 포트에서 «같은 ssh 명령» 으로 열어 /health 200. 정리는 내가 연 것만.
preflight() {
  local fp="" p gp lp ok=0 foreign=""
  for p in $(seq 38301 38399); do [ -z "$(holder_pid "$p")" ] && { fp="$p"; break; }; done
  [ -n "$fp" ] || { echo "사전검증 빈 포트 없음(38301~38399)"; return 1; }
  command gcloud compute ssh "$VM" --zone="$ZONE" --account="$ACCOUNT" --tunnel-through-iap --quiet \
    --strict-host-key-checking=yes -- -N -L "$fp:localhost:8000" -o BatchMode=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes </dev/null >>"$LOG" 2>&1 &
  gp=$!
  if wait_listen 1 "$fp"; then
    lp="$(holder_pid "$fp")"
    if is_descendant "$lp" "$gp"; then [ "$(health "$fp")" = ok ] && ok=1; else foreign="$lp"; fi
  fi
  lp="$(holder_pid "$fp")"
  [ -n "$lp" ] && [ -z "$foreign" ] && is_descendant "$lp" "$gp" && $PREKILL -TERM "$lp" 2>/dev/null
  $PREKILL -TERM "$gp" 2>/dev/null; wait "$gp" 2>/dev/null
  [ -z "$foreign" ] || { echo "사전검증 빈 포트 $fp 에 남의 리스너(pid $foreign) — 건드리지 않음"; return 1; }
  [ "$ok" = 1 ] || { echo "사전검증 실패(빈 포트 $fp: 열림/ health)"; return 1; }
  echo "사전검증 ok(빈 포트 $fp)"
}

# ③ 실패 복구: launchd 항목만 내리고, 옛 줄은 사람이 다시 친다(세션 밖 보장이 필요한 자동 복구는 만들지 않는다).
rollback() {
  local old="$1" brc=0
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || brc=$?
  [ "$brc" = 0 ] || echo "bootout rc=$brc ($LABEL)" | tee -a "$LOG" >&2
  wait_listen 0 || die 5 "ROLLBACK 불완전 — $PORT 가 안 비워짐(소유 pid $(holder_pid)) · bootout rc=$brc · 로그 $LOG"
  [ -n "$old" ] && die 5 "ROLLBACK ok(launchd 내림) — 옛 터널은 이미 종료됨 · 수동 복구: $OLD_LINE · 로그 $LOG"
  die 5 "ROLLBACK ok(launchd 내림 · 옛 터널 없었음) · 로그 $LOG"
}

status() {
  local ld=missing lp h=skip
  loaded && ld=loaded
  lp="$(holder_pid)"
  [ -n "$lp" ] && h="$(health)"
  echo "launchd=$ld listen=${lp:-none} health=$h"
  [ "$ld" = loaded ] && [ -n "$lp" ] && [ "$h" = ok ]
}

install() {
  local old sig sig2 pre
  old="$(holder_pid)"
  if [ -n "$old" ] && loaded; then echo "ALREADY 설치됨"; status; return; fi
  if [ -n "$old" ]; then
    sig="$(old_sig "$old")" \
      || die 3 "REJECT $PORT 를 쥔 pid $old 가 옛 nohup 터널이 아님(start-iap-tunnel·VM·8000·--local-host-port·--zone 토큰 대조) — 변경 0"
  fi
  render_plist                                              # 준비 — 옛 pid 는 아직 건드리지 않는다
  if [ -n "$old" ]; then
    pre="$(preflight)" || die 6 "REJECT $pre — 옛 터널 pid $old 그대로(전환 0)"
    echo "$pre"
    sig2="$(old_sig "$old")" && [ "$sig2" = "$sig" ] \
      || die 3 "REJECT 사전검증 사이 pid $old 의 argv·시작시각이 바뀜 — 종료 0(변경: plist 만)"
    $KILL -TERM "$old" 2>/dev/null
    wait_listen 0 || die 4 "옛 터널 pid $old 가 안 내려감 — 새 터널 기동 전 중단(변경: plist 만)"
  fi
  launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || rollback "$old"
  wait_listen 1 || rollback "$old"
  [ "$(health)" = ok ] || rollback "$old"
  echo "INSTALLED launchd=$LABEL listen=$(holder_pid) plist=$PLIST${old:+ 넘겨받음=$old}"
}

uninstall() {  # 되돌림: launchd 항목 + plist 제거. 옛 nohup 줄은 출력만(실행 0).
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1
  rm -f "$PLIST"
  wait_listen 0 || die 4 "UNINSTALL 후에도 $PORT 가 안 비워짐(소유 pid $(holder_pid))"
  echo "UNINSTALLED $LABEL — 옛 방식 복구: $OLD_LINE"
}

case "${1:-install}" in
  install) install ;;
  status) status ;;
  uninstall) uninstall ;;
  *) die 2 "사용: install.sh [install|status|uninstall]" ;;
esac
