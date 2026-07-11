#!/bin/bash
# ft-pm-watchd.sh — PM 멈춤 감시 전용 데몬 (§3-3④)
# watchd는 판단하지 않는다(사실 감지만) — ALERT 판단·발신은 PM.
# 싱글턴(프로젝트당 1개): flock -n 비블로킹 + watchd.pid identity 검증.
# stale pidfile은 잔존 PID를 kill하지 않는다(무관 프로세스 파괴 금지) — pidfile 교체·재기동만.
#
# Modes:
#   --ensure           스폰 ⑦/헬스 리페어: 유효 인스턴스 없으면 --run 기동
#   --run              데몬 루프 본체(flock -n 획득 실패 시 즉시 종료 — 싱글턴 guard)
#   --stop-if-owned    PM kill 동반 정리: identity 양성 일치 시에만 kill, 아니면 pidfile 제거
set +e
LIB="$(cd "$(dirname "$0")" && pwd)/ft-lib.sh"; . "$LIB"
SEND="$(dirname "$0")/ft-tmux-send.sh"

ROOT="" MODE="ensure"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2;;
    --ensure) MODE="ensure"; shift;;
    --run) MODE="run"; shift;;
    --stop-if-owned) MODE="stop"; shift;;
    *) shift;;
  esac
done
ROOT="$(ft_resolve_root "$ROOT")"
PMSIG="$(ft_pm_signals "$ROOT")"; mkdir -p "$PMSIG/archive" 2>/dev/null
PIDFILE="$PMSIG/watchd.pid"
LOCK="$PMSIG/watchd.lock"
INTERVAL="${FT_WATCHD_INTERVAL:-40}"
BACKLOG_CAP=50

# identity 양성 일치? (command·project·lstart·watchd 전부) — pidfile: "<pid> <lstart> <proj>"
watchd_owned() {
  [ -f "$PIDFILE" ] || return 1
  local pid rest lstart proj
  read -r pid rest < "$PIDFILE"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  # 기록된 lstart(공백 포함)·proj 재구성: 마지막 필드=proj, 그 앞=lstart
  proj="${rest##* }"; lstart="${rest% *}"
  local cur; cur="$(ps -o lstart=,command= -p "$pid" 2>/dev/null)"
  # command 에 ft-pm-watchd 포함 + lstart 일치 + proj 일치
  case "$cur" in *ft-pm-watchd*) ;; *) return 1;; esac
  case "$cur" in *"$lstart"*) ;; *) return 1;; esac
  [ "$proj" = "$ROOT" ] || return 1
  return 0
}

case "$MODE" in
  stop)
    if watchd_owned; then
      read -r pid _ < "$PIDFILE"; kill "$pid" 2>/dev/null
      rm -f "$PIDFILE" 2>/dev/null
      echo "WATCHD stopped (owned pid killed)"
    else
      rm -f "$PIDFILE" 2>/dev/null    # 무관 프로세스일 수 있음 — kill 금지, pidfile만 제거
      echo "WATCHD stop: not owned — pidfile 제거만"
    fi
    exit 0;;
  ensure)
    if watchd_owned; then echo "WATCHD reuse (owned instance alive)"; exit 0; fi
    # stale/부재 → 재기동(잔존 PID kill 안 함). 실제 싱글턴 guard는 --run의 flock -n.
    [ -f "$PIDFILE" ] && rm -f "$PIDFILE" 2>/dev/null
    # V12: setsid는 macOS 미탑재(exit127) — 있으면 setsid, 없으면 nohup+&로 detach(둘 다 데몬화 충분).
    if command -v setsid >/dev/null 2>&1; then
      setsid nohup bash "$0" --root "$ROOT" --run >/dev/null 2>&1 &
    else
      nohup bash "$0" --root "$ROOT" --run >/dev/null 2>&1 &
    fi
    echo "WATCHD launched"
    exit 0;;
  run) : ;; # 아래로
esac

# ── --run: 싱글턴 guard — flock -n(Linux) 또는 mkdir 원자 락(macOS 등 flock 부재, V12) ──
# 기존엔 flock 부재 시 guard가 통째로 스킵돼 중복 데몬 + pidfile 상호파괴가 났다(EXIT trap).
LOCKDIR="$LOCK.d"; USED_MKDIR_LOCK=0
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK"
  flock -n 9 || { echo "ft-pm-watchd: 다른 인스턴스가 lock 보유 — 종료" >&2; exit 0; }
else
  # flock 부재: mkdir 원자성으로 싱글턴. 획득 실패 시 소유자 생존 확인 → stale이면 회수·재획득.
  # (mkdir 성공~pidfile 기록 사이 극소 경쟁창은 flock -n 근사치로 수용 — --ensure는 저빈도 기동.)
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    if watchd_owned; then echo "ft-pm-watchd: 다른 인스턴스가 lock 보유(mkdir) — 종료" >&2; exit 0; fi
    rmdir "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null || { echo "ft-pm-watchd: lock 경합 — 종료" >&2; exit 0; }
  fi
  USED_MKDIR_LOCK=1
fi
# pidfile 기록: "<pid> <lstart> <proj>"
LSTART="$(ps -o lstart= -p $$ 2>/dev/null | sed 's/^ *//')"
printf '%s %s %s\n' "$$" "$LSTART" "$ROOT" > "$PIDFILE"
trap 'rm -f "$PIDFILE" 2>/dev/null; [ "$USED_MKDIR_LOCK" = 1 ] && rmdir "$LOCKDIR" 2>/dev/null' EXIT

# 이벤트 발행: dedup(동일 key .evt 존재 시 억제=touch) + 백로그 상한 FIFO
emit_evt() {  # <key> <detail>
  # ★ f는 반드시 별도 local 문으로 — 같은 local 선언 내 $key 자기참조는 bash에서 빈 값으로
  #   전개돼 파일명이 watch..evt(빈 키)로 뭉개진다(#과 무관, 전 세션 emit 붕괴). 한 줄로 합치지 말 것.
  local key="$1" detail="$2"
  local f="$PMSIG/watch.$key.evt"
  if [ -f "$f" ]; then touch "$f" 2>/dev/null; return 0; fi   # dedup
  # 백로그 상한
  local cnt; cnt="$(ls -1 "$PMSIG"/watch.*.evt 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${cnt:-0}" -ge "$BACKLOG_CAP" ]; then
    local oldest; oldest="$(ls -1t "$PMSIG"/watch.*.evt 2>/dev/null | tail -1)"
    [ -n "$oldest" ] && mv "$oldest" "$PMSIG/archive/$(basename "$oldest").$(date +%s)" 2>/dev/null
    ft_atomic_write "$PMSIG/watch.overflow.evt" "$(date +%s) backlog cap $BACKLOG_CAP reached"
  fi
  ft_atomic_write "$f" "$(date +%s) $detail"
  # PM wake
  local pm; pm="$(cat "$PMSIG/pm-session" 2>/dev/null)"
  [ -n "$pm" ] && bash "$SEND" "$pm" --from watchd --id "$key" "WATCH_EVT watch.$key.evt" >/dev/null 2>&1
}

lowcpu_bump() {  # <sess> → 0=hang(2연속) 1=아직
  local sess="$1" c
  local f="$PMSIG/.lowcpu.$sess"   # ★ 별도 local — 같은 문 내 $sess 자기참조는 빈 값 전개(위 emit_evt 주석 참조)
  c="$(cat "$f" 2>/dev/null || echo 0)"; c=$((c+1)); printf '%s' "$c" > "$f"
  [ "$c" -ge 2 ]
}
lowcpu_reset() { rm -f "$PMSIG/.lowcpu.$1" 2>/dev/null; }

# ── 감시 루프 ──────────────────────────────────────────────
NOSYNC_LIMIT=1800   # 30분
HIL_LIMIT=300       # 5분
while :; do
  now="$(date +%s)"
  # 1) ft-* 워커+오케 CPU hang
  while read -r s; do
    case "$s" in ft-*) ;; *) continue;; esac
    cpu="$(ft_sess_cpu "$s")"
    if [ -z "$cpu" ]; then continue; fi
    if awk -v c="$cpu" 'BEGIN{exit !(c+0 < 0.3)}'; then
      if lowcpu_bump "$s"; then emit_evt "hang-$s" "cpu=$cpu"; fi
    else
      lowcpu_reset "$s"
    fi
  done < <(tmux ls -F '#{session_name}' 2>/dev/null)

  # 2) pending hil-* > 5분 방치 (전 active feature 스캔)
  for h in "$ROOT"/.fable-team/state/*/.signals/hil-*; do
    [ -f "$h" ] || continue
    hts="$(sed -n 's/.*ts=\([0-9]*\).*/\1/p' "$h" | head -1)"
    hsess="$(sed -n 's/.*sess=\([^ ]*\).*/\1/p' "$h" | head -1)"
    hid="$(basename "$h" | sed 's/^hil-//')"
    [ -n "$hts" ] || continue
    if [ $((now - hts)) -ge "$HIL_LIMIT" ]; then emit_evt "hil5m-$hsess-$hid" "hil aged $((now-hts))s"; fi
  done

  # 3) 30분 무SYNC (프록시: BRIEF.md mtime)
  BRIEF="$ROOT/.fable-team/pm/BRIEF.md"
  if [ -f "$BRIEF" ]; then
    bmt="$(stat -f %m "$BRIEF" 2>/dev/null || stat -c %Y "$BRIEF" 2>/dev/null)"
    [ -n "$bmt" ] && [ $((now - bmt)) -ge "$NOSYNC_LIMIT" ] && emit_evt "nosync-brief" "brief stale $((now-bmt))s"
  fi

  sleep "$INTERVAL"
done
