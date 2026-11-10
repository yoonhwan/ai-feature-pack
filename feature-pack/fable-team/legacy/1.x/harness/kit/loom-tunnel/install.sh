#!/usr/bin/env bash
# LOOM DB 터널(38309 → 10.2.0.10:5432)을 세션 밖 launchd 상시 소유로 (R87 · 오빠 판정 913 · 제안 #1213)
# 사용: bash install.sh [install|status]      (기본 install · 머신마다 1회)
# 원칙: «옛 터널을 끊는 것»은 «새 터널이 DB 까지 확인된 뒤»에만 — ①옛 터널이 살아 있는 동안 빈 포트에서 같은 명령(비대화)을
#   미리 열어 select 1 → ②옛 pid 종료(argv·시작시각 재대조) → launchd 기동 → 38309 LISTEN+select 1 → ③어느 단계든 실패면 복구.
# 시험 주입: LOOM_TUNNEL_{PORT,AGENTS_DIR,WAIT,KILL,PREKILL,CALL_TMO,SELECT1_CMD} — 실 터널·실 launchd 0 으로 돌릴 때만 쓴다.
# 종료코드: 0 완료 · 1 status 불일치 · 2 사용/환경 · 3 REJECT(포트를 쥔 게 정확히 같은 명령이 아님 · 변경 0)
#           4 옛 터널 종료 실패 · 5 전환 실패(복구 결과 줄 참조) · 6 사전검증 실패(전환 0 · 옛 터널 그대로)
set -uo pipefail
HERE="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.byz.loom-pg-tunnel"
RLABEL="$LABEL.recover"
PORT="${LOOM_TUNNEL_PORT:-38309}"
PRIVATE_HOST="10.2.0.10"
VM="byz-agents-gce-stt-tts-dev"
ZONE="asia-northeast3-a"
ACCOUNT="byz-local-dev@byz-agents-484214.iam.gserviceaccount.com"
AGENTS_DIR="${LOOM_TUNNEL_AGENTS_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$AGENTS_DIR/$LABEL.plist"
RPLIST="$AGENTS_DIR/$RLABEL.plist"
WAIT="${LOOM_TUNNEL_WAIT:-60}"
KILL="${LOOM_TUNNEL_KILL:-kill}"          # 옛 터널 pid 종료용
PREKILL="${LOOM_TUNNEL_PREKILL:-kill}"    # 내가 연 사전검증 프로세스 종료용
CALL_TMO="${LOOM_TUNNEL_CALL_TMO:-7}"     # 외부 호출 1회 상한(초) — 7초 룰 + 재시도 1회
DOMAIN="gui/$(id -u)"
LOG="/tmp/byz-loom-pg-tunnel.log"

die() { local rc="$1"; shift; echo "$*" >&2; exit "$rc"; }
holder_pid() { lsof -nP -iTCP:"${1:-$PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1; }
loaded() { launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; }
pfield() { ps -ww -o "$1=" -p "$2" 2>/dev/null | sed 's/^ *//;s/ *$//'; }

# ── 외부 호출 상한: 1회 CALL_TMO 초 + 실패 시 재시도 1회 (멈춤으로 복구에 못 닿는 경로 0)
tmo1() {   # 상한 뒤 TERM → 1초 유예 → 자식까지 KILL. 시간 초과는 rc≠0(143/137).
  "$@" & local p=$!
  # 자식 pid 를 «먼저» 읽고 부모와 한 번에 보낸다 — 부모 먼저 죽어도 자식이 고아로 남지 않고, 자식만 죽어 부모가 «성공»으로 이어지지도 않는다
  ( sleep "$CALL_TMO"; kids="$(pgrep -P "$p")"; kill -TERM "$p" $kids 2>/dev/null
    sleep 1; kids="$(pgrep -P "$p")"; kill -KILL "$p" $kids 2>/dev/null ) >/dev/null 2>&1 & local w=$!
  local rc=0; wait "$p" 2>/dev/null || rc=$?
  pkill -P "$w" 2>/dev/null; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}
tmo7() { tmo1 "$@" || tmo1 "$@"; }

# ── 정확 대조: argv 를 토큰으로 쪼개 VM·--zone·--account·-L 값을 «정확히» 비교 (부분 문자열·접미사 금지)
tok_has()  { local want="$1" t; shift; for t in "$@"; do [ "$t" = "$want" ] && return 0; done; return 1; }
tok_pair() { local a="$1" b="$2" prev="" t; shift 2; for t in "$@"; do [ "$prev" = "$a" ] && [ "$t" = "$b" ] && return 0; prev="$t"; done; return 1; }
gcloud_ssh_match() {  # $1=argv 문자열
  [ -n "$1" ] || return 1
  local -a t; read -ra t <<< "$1"
  tok_pair compute ssh "${t[@]}" && tok_pair ssh "$VM" "${t[@]}" \
    && tok_has "--zone=$ZONE" "${t[@]}" && tok_has "--account=$ACCOUNT" "${t[@]}" \
    && tok_has --tunnel-through-iap "${t[@]}" && tok_pair -L "$PORT:$PRIVATE_HOST:5432" "${t[@]}"
}
ssh_match() { [ -n "$1" ] || return 1; local -a t; read -ra t <<< "$1"; tok_pair -L "$PORT:$PRIVATE_HOST:5432" "${t[@]}"; }

# 홀더(ssh)와 그 부모(gcloud compute ssh)의 argv+시작시각 서명. 정확히 같은 명령이 아니면 rc=1.
tunnel_sig() {
  local pid="$1" ppid cmd pcmd
  cmd="$(pfield command "$pid")"; ppid="$(pfield ppid "$pid")"; pcmd="$(pfield command "$ppid")"
  if gcloud_ssh_match "$cmd"; then pcmd="$cmd"; ppid="$pid"             # 홀더 자신이 gcloud
  elif ! { ssh_match "$cmd" && [ -n "$pcmd" ] && gcloud_ssh_match "$pcmd"; }; then return 1; fi
  printf '%s|%s|%s|%s' "$cmd" "$(pfield lstart "$pid")" "$pcmd" "$(pfield lstart "$ppid")"
}

render_plist() {
  local gcloud; gcloud="$(command -v gcloud)" || die 2 "gcloud 없음 — PATH 확인"
  mkdir -p "$AGENTS_DIR"
  sed -e "s|__GCLOUD__|$gcloud|" -e "s|__VM__|$VM|" -e "s|__ZONE__|$ZONE|" -e "s|__ACCOUNT__|$ACCOUNT|" \
      -e "s|__PORT__|$PORT|" -e "s|__PRIVATE_HOST__|$PRIVATE_HOST|" -e "s|__HOME__|$HOME|" \
      -e "s|__PATH__|$(dirname "$gcloud"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin|" \
      "$HERE/com.byz.loom-pg-tunnel.plist.template" > "$PLIST"
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

# 접속 확인 [$1=port] — DSN 은 loom_dsn.sh 가 시크릿에서 받아 «출력 0» 으로 psql 에만 쓴다. 모든 외부 호출 7초+재시도 1회.
select1() {
  local port="${1:-$PORT}"
  if [ -n "${LOOM_TUNNEL_SELECT1_CMD:-}" ]; then
    LOOM_TUNNEL_SELECT1_PORT="$port" tmo7 bash -c "$LOOM_TUNNEL_SELECT1_CMD" >/dev/null 2>&1 && echo ok || echo fail; return
  fi
  ( set -e
    gcloud() { tmo7 command gcloud "$@"; }
    # shellcheck disable=SC1091
    source "$HERE/../../server/loom_dsn.sh"
    export APP_ENV=local LOOM_PG_TUNNEL_PORT="$port" PGCONNECT_TIMEOUT="$CALL_TMO"
    resolve_loom_interim_dsn status
    [ "$(tmo7 psql "$LOOM_INTERIM_DB_URL" -tAc 'select 1' 2>/dev/null)" = 1 ]
  ) >/dev/null 2>&1 && echo ok || echo fail
}

status() {
  local ld=missing lp sel
  loaded && ld=loaded
  lp="$(holder_pid)"; sel=skip
  [ -n "$lp" ] && sel="$(select1)"
  echo "launchd=$ld listen=${lp:-none} select1=$sel"
  [ "$ld" = loaded ] && [ -n "$lp" ] && [ "$sel" = ok ]
}

# ── ① 사전검증: 옛 터널이 살아 있는 동안 38301~38399 빈 포트에서 «같은 명령 + 비대화 옵션» 으로 열어 select 1.
preflight() {
  local fp="" p gp lp
  for p in $(seq 38301 38399); do [ "$p" = "$PORT" ] && continue; [ -z "$(holder_pid "$p")" ] && { fp="$p"; break; }; done
  [ -n "$fp" ] || { echo "사전검증 빈 포트 없음(38301~38399)"; return 1; }
  command gcloud compute ssh "$VM" --zone="$ZONE" --account="$ACCOUNT" --tunnel-through-iap --quiet \
    --strict-host-key-checking=yes -- -N -L "$fp:$PRIVATE_HOST:5432" -o BatchMode=yes \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes </dev/null >>"$LOG" 2>&1 &
  gp=$!
  local ok=0 foreign=""
  if wait_listen 1 "$fp"; then
    lp="$(holder_pid "$fp")"
    if is_descendant "$lp" "$gp"; then [ "$(select1 "$fp")" = ok ] && ok=1; else foreign="$lp"; fi
  fi
  # 정리는 내가 연 gp 와 그 자손만 — 남의 홀더는 TERM 0
  lp="$(holder_pid "$fp")"
  [ -n "$lp" ] && [ -z "$foreign" ] && is_descendant "$lp" "$gp" && $PREKILL -TERM "$lp" 2>/dev/null
  $PREKILL -TERM "$gp" 2>/dev/null; wait "$gp" 2>/dev/null
  [ -z "$foreign" ] || { echo "사전검증 빈 포트 $fp 에 남의 리스너(pid $foreign) — 건드리지 않음"; return 1; }
  [ "$ok" = 1 ] || { echo "사전검증 실패(빈 포트 $fp: 열림/ select 1)"; return 1; }
  echo "사전검증 ok(빈 포트 $fp)"
}

is_descendant() {  # $1=pid $2=조상 — 최대 6단계
  local p="$1" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$i" -lt 6 ]; do
    [ "$p" = "$2" ] && return 0
    p="$(pfield ppid "$p")"; i=$((i + 1))
  done
  return 1
}

# ── ③ 복구: 새 launchd 항목을 내리고(결과 검사·기록) 같은 명령을 «세션 밖» launchd 일회성 job 으로 되살린다.
recover() {
  local old="$1" brc=0 jpid lp jppid jpg cpg
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || brc=$?
  [ "$brc" = 0 ] || { echo "bootout rc=$brc ($LABEL)" | tee -a "$LOG" >&2; }
  [ -n "$old" ] || die 5 "ROLLBACK 불필요(옛 터널 없었음) — 새 터널 실패 · 로그 $LOG"
  wait_listen 0 || die 5 "ROLLBACK 실패 — $PORT 가 안 비워짐(소유 pid $(holder_pid)) · bootout rc=$brc · 수동 복구 필요(판정 799 명령)"
  sed -e "s|$LABEL|$RLABEL|" -e '/KeepAlive/s|<true/>|<false/>|' "$PLIST" > "$RPLIST"
  launchctl bootout "$DOMAIN/$RLABEL" >/dev/null 2>&1
  launchctl bootstrap "$DOMAIN" "$RPLIST" >/dev/null 2>&1 || die 5 "ROLLBACK 실패 — 복구 job bootstrap 실패($RPLIST)"
  wait_listen 1 || die 5 "ROLLBACK 실패 — 복구 뒤 $PORT LISTEN 없음 · 로그 $LOG"
  lp="$(holder_pid)"
  jpid="$(launchctl list "$RLABEL" 2>/dev/null | sed -n 's/.*"PID" = \([0-9][0-9]*\);.*/\1/p' | head -1)"
  { [ -n "$jpid" ] && is_descendant "$lp" "$jpid"; } \
    || die 5 "ROLLBACK 실패 — $PORT LISTEN 소유 pid ${lp:-?} 가 복구 job(pid ${jpid:-?}) 이 띄운 게 아님"
  [ "$(select1)" = ok ] || die 5 "ROLLBACK 실패 — 복구 터널(pid $lp) select 1 실패"
  jppid="$(pfield ppid "$jpid")"; jpg="$(pfield pgid "$jpid")"; cpg="$(/bin/ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  { [ "$jppid" = 1 ] && [ -n "$jpg" ] && [ "$jpg" != "$cpg" ]; } \
    || die 5 "ROLLBACK 실패 — 복구 job 이 세션 밖이 아님(ppid=$jppid pgid=$jpg 호출자 pgid=$cpg)"
  die 5 "ROLLBACK ok — 옛 명령으로 복구(listen pid $lp · job pid $jpid ppid=$jppid pgid=$jpg ≠ 호출자 pgid=$cpg) · 새 터널 실패 로그 $LOG"
}

install() {
  local old sig sig2 pre
  old="$(holder_pid)"
  if [ -n "$old" ] && loaded; then echo "ALREADY 설치됨"; status; return; fi
  if [ -n "$old" ]; then
    sig="$(tunnel_sig "$old")" \
      || die 3 "REJECT $PORT 를 쥔 pid $old 가 정확히 같은 명령이 아님(VM·--zone·--account·-L 토큰 대조) — 변경 0"
  fi
  render_plist                                              # 준비 — 옛 pid 는 아직 건드리지 않는다
  if [ -n "$old" ]; then
    pre="$(preflight)" || die 6 "REJECT $pre — 옛 터널 pid $old 그대로(전환 0)"
    echo "$pre"
    sig2="$(tunnel_sig "$old")" && [ "$sig2" = "$sig" ] \
      || die 3 "REJECT 사전검증 사이 pid $old 의 argv·시작시각이 바뀜 — 종료 0(변경 0)"
    $KILL -TERM "$old" 2>/dev/null
    wait_listen 0 || die 4 "옛 터널 pid $old 가 안 내려감 — 새 터널 기동 전 중단(변경: plist 만)"
  fi
  launchctl bootstrap "$DOMAIN" "$PLIST" >/dev/null 2>&1 || recover "$old"
  wait_listen 1 || recover "$old"
  [ "$(select1)" = ok ] || recover "$old"
  echo "INSTALLED launchd=$LABEL listen=$(holder_pid) plist=$PLIST${old:+ 넘겨받음=$old}"
}

case "${1:-install}" in
  install) install ;;
  status) status ;;
  *) die 2 "사용: install.sh [install|status]" ;;
esac
