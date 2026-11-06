#!/usr/bin/env bash
# ft-weekend-watch.sh — 주말 무인 감시 러너 (r1447 · 오빠 «너가 주말내내 서포트»)
#   ★세션과 무관하게 돈다★: tmux/에이전트 세션이 죽어도 이 프로세스는 남아 15분마다 점검한다.
#   점검 5종(읽기 전용): ①오늘 진화 게이트 last-run ②오늘 10:00 평가 파일 ③lessons check rc ④state/*.log «판정 불가·ERROR» 급증 ⑤핵심 launchd 라벨 로드
#   이상이면 state/watch/weekend.log 1줄 + desk mbox 1통(같은 항목 1시간 디바운스). 정상이면 로그만.
#   ctx 축(오빠 11-06 «컨텍스트 기준 운영하고 모니터링»): waste-check 데몬 로드 여부를 ⑤에 포함 — 턴 기준 증류는 쓰지 않는다.
#   사용: ft-weekend-watch.sh [--start|--stop|--status|--once] [--interval 900]
set -uo pipefail
ARG1="${1:---start}"; ARG2="${2:-}"   # ★sourcing 전에 잡는다(ft-harness-root.sh 가 인자를 소비할 수 있다)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0}}")" && pwd)"
ROOT="${FT_ROOT:-}"
if [ -z "$ROOT" ]; then . "$HERE/ft-harness-root.sh" 2>/dev/null && ROOT="$(ft_repo_root "$HERE")/.fable-team"; fi
[ -n "$ROOT" ] || { echo "REJECT FT_ROOT 판정 실패"; exit 2; }
W="$ROOT/state/watch"; PID="$W/weekend.pid"; LOG="$W/weekend.log"; DED="$W/weekend.dedup"
mkdir -p "$W"
INTERVAL="${FT_WATCH_INTERVAL:-900}"
DESK="${FT_WATCH_DESK:-byz-planner-desk-claude#112}"
MBOX="$ROOT/bin/ft-mbox.sh"

check_once() {
  local problems=() today; today="$(date +%Y%m%d)"
  local lr; lr="$(cat "$ROOT/state/evolution/last-run" 2>/dev/null | tr -d '[:space:]')"
  [ "$lr" = "$today" ] || problems+=("게이트 미실행(last-run=${lr:-없음} · 오늘=$today)")
  ls "$ROOT"/state/eval/daily-*.md >/dev/null 2>&1 || problems+=("평가 파일 없음")
  # DA 3R 반례 6: 예정 시각(기본 10:00) 전에는 «없음» 이 정상 — 시각 조건 없이 오탐했다.
  local due="${FT_EVAL_DUE_HOUR:-10}"
  if [ "$(date +%H)" -ge "$due" ] || [ "${FT_WATCH_IGNORE_SCHEDULE:-0}" = 1 ]; then
    grep -q "daily-$today.md" <(ls "$ROOT"/state/eval/daily-*.md 2>/dev/null) || problems+=("오늘 평가($today) 없음 — ${due}:00 잡 확인")
  fi
  if [ -f "$ROOT/bin/ft-lessons.sh" ]; then
    FT_ROOT="$ROOT" bash "$ROOT/bin/ft-lessons.sh" check >/dev/null 2>&1 || problems+=("lessons check 위반")
  fi
  local bad=0 f n
  for f in "$ROOT"/state/*.log; do
    [ -f "$f" ] || continue
    n="$(tail -2000 "$f" 2>/dev/null | grep -c '판정 불가\|ERROR' | head -1)"; n="${n:-0}"
    bad=$((bad + n))
  done
  # 누적값은 계속 크다 → «직전 점검 대비 증가분» 으로 본다(오탐 0 · r1447)
  local pc="$W/last-count"; local prev=""; [ -f "$pc" ] && prev="$(cat "$pc" 2>/dev/null)"
  echo "$bad" > "$pc"
  [ -n "$prev" ] || prev="$bad"   # 첫 실행 = 기준선만 잡는다(오탐 0)
  [ "$bad" -gt "$prev" ] && [ $((bad - prev)) -ge 20 ] && problems+=("state 로그 실패 증가 +$((bad - prev))건(누적 $bad)")
  # 과적합 방지(r1450): 라벨을 스크립트에 박지 않는다. «이 프로젝트가 실제로 등록한» 라벨만 본다.
  #   목록 = <root>/state/watch/labels.txt (install 이 렌더·등록한 라벨만 적는다) 또는 FT_WATCH_LABELS.
  #   목록이 없으면 판정하지 않고 후보만 알려준다(설치된 plist ≠ 로드돼야 하는 plist — 정지 팀·pause 가 있다).
  local l labels=""
  labels="${FT_WATCH_LABELS:-}"
  [ -n "$labels" ] || { [ -f "$W/labels.txt" ] && labels="$(tr ', ' '\n\n' < "$W/labels.txt" | grep -v '^#' | tr '\n' ' ')"; }
  if [ -z "${labels// }" ]; then
    local cand; cand="$(ls "$HOME/Library/LaunchAgents" 2>/dev/null | grep -E '^com\..*ft-.*\.plist$' | sed 's/\.plist$//' | tr '\n' ' ')"
    { echo "# ft-weekend-watch 라벨 목록 — «이 프로젝트가 등록한» 라벨만 남긴다(나머지는 주석 처리: 정지·pause 팀이 있다)"; for c in $cand; do echo "# $c"; done; } > "$W/labels.txt"
    problems_skip=1
  fi
  if [ -z "${labels// }" ]; then
    [ "${problems_skip:-0}" = 1 ] && echo "$(date '+%F %T') INFO 라벨 목록 없음 — $W/labels.txt 에 검사할 라벨만 남겨라(이번 점검은 launchd 판정 생략)" >> "$LOG"
  else
    for l in $labels; do
      launchctl print "gui/$(id -u)/$l" >/dev/null 2>&1 || problems+=("launchd $l 미적재")
    done
  fi
  echo "$(date '+%F %T') interval=${INTERVAL}s problems=${#problems[@]} ${problems[*]:-}" >> "$LOG"
  if [ "${#problems[@]}" -gt 0 ]; then
    local key; key="$(printf '%s' "${problems[*]}" | md5 2>/dev/null || printf '%s' "${problems[*]}" | cksum)"
    local last=0; [ -f "$DED" ] && last="$(cut -f1 "$DED" 2>/dev/null || echo 0)"
    local now; now="$(date +%s)"
    if [ $((now - last)) -ge 3600 ] && [ -f "$MBOX" ]; then
      printf '%s\t%s\n' "$now" "$key" > "$DED"
      FT_ROOT="$ROOT" bash "$MBOX" send "$DESK" "ft-weekend-watch" "[주말감시] 이상 ${#problems[@]}건 — ${problems[*]:0:200}
확인: bash .fable-team/bin/ft-weekend-watch.sh --status" >/dev/null 2>&1 || true
    fi
    return 1
  fi
  return 0
}

case "$ARG1" in
  --once) check_once; echo "once rc=$?"; exit 0;;
  --status)
    if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "WATCH running pid=$(cat "$PID") interval=${INTERVAL}s"; else echo "WATCH stopped"; fi
    tail -3 "$LOG" 2>/dev/null; exit 0;;
  --stop)
    if [ -f "$PID" ]; then kill "$(cat "$PID")" 2>/dev/null && echo "WATCH stopped pid=$(cat "$PID")"; rm -f "$PID"; else echo "WATCH not running"; fi; exit 0;;
  --start) ;;
  --interval) INTERVAL="${ARG2:-900}";;
  *) echo "usage: $0 [--start|--stop|--status|--once] [--interval N]"; exit 2;;
esac
if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then echo "WATCH already running pid=$(cat "$PID")"; exit 0; fi
nohup bash -c 'while :; do "'"$HERE"'/ft-weekend-watch.sh" --once >/dev/null 2>&1; sleep "$0"; done' "$INTERVAL" >/dev/null 2>&1 &
echo $! > "$PID"
echo "WATCH started pid=$! interval=${INTERVAL}s root=$ROOT log=$LOG"
