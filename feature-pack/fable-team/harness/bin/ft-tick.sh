#!/bin/bash
# ft-tick.sh — Seatbelt 0.4 통합 틱 (ft-master-tick.sh · ft-pm-tick.sh · ft-goal-tick.sh 를 한 프로세스로)
#   한 루프마다 <리포루트>/.fable-team/seats.json 을 «다시 읽어» tick != null 이고 _replaced_by 없는 좌석마다
#   그 tick 종류의 간격·프롬프트를 적용한다. 승계 = seats.json 한 줄 교체(env 재기동 0회).
#   생존은 launchd KeepAlive (ft-tick.plist · ft-tick-install.sh) — 이 스크립트는 워치독을 갖지 않는다.
#
#   tick 종류: ft-master-tick(900s) · ft-pm-tick(600s · REPORT_TO = seats.json 의 현역 master)
#              + master 좌석엔 goal-tick(240s · ft-goal-tick.sh 를 그대로 호출 — rc=0 GOAL-OK 면 조용)
#   4중 디바운스(원본 그대로): ① 단일 인스턴스 pidfile ② 최소 간격(좌석별 stamp /tmp/ft-tick-<좌석>.last)
#              ③ pane busy·미제출 입력 스킵 ④ 전송 후 제출 검증(미제출이면 Enter 1회)
#   ft-tick.sh [--once] [--dry-run]   --once=한 바퀴만 · --dry-run=대상·메시지 앞 80자만 출력(전송·stamp 없음)
#   seats.json 을 못 읽으면 stderr 에 찍고 다음 루프(조용히 건너뛰지 않는다). 세션명에 '#' 가 있어 pane_id 로 송신.
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
SEATS="${FT_TICK_SEATS:-${ROOT:-$WT}/.fable-team/seats.json}"
GOAL_TICK="${FT_TICK_GOAL_TICK:-$HERE/ft-goal-tick.sh}"
LOOP_SEC="${FT_TICK_LOOP_SEC:-60}"
PIDFILE="${FT_TICK_PIDFILE:-/tmp/ft-tick.pid}"
MASTER_INTERVAL="${FT_TICK_MASTER_INTERVAL:-900}"; MASTER_MIN_GAP="${FT_TICK_MASTER_MIN_GAP:-840}"
PM_INTERVAL="${FT_TICK_PM_INTERVAL:-600}";         PM_MIN_GAP="${FT_TICK_PM_MIN_GAP:-540}"
GOAL_INTERVAL="${FT_TICK_GOAL_INTERVAL:-240}"
ONCE=0; DRY=0
for a in "$@"; do case "$a" in --once) ONCE=1;; --dry-run) DRY=1;; *) echo "usage: $0 [--once] [--dry-run]" >&2; exit 2;; esac; done

log() { echo "$(date '+%F %T') $*"; }
now() { date +%s; }
stamp_of() { echo "/tmp/ft-tick-$1${2:+.$2}.last"; }
pane_of() { tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null | awk -v s="$1" '$1==s{print $2; exit}'; }

# seats.json → "seat<TAB>tick<TAB>role" (현역만: _ 키 제외 · tick != null · _replaced_by 없음). 실패면 rc≠0.
read_seats() {
  python3 - "$SEATS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if v.get("tick") is None or v.get("_replaced_by"): continue
    print(f"{k}\t{v['tick']}\t{v.get('role','')}")
PY
}
master_seat() { awk -F'\t' '$3=="master"{print $1; exit}' <<< "$1"; }

MASTER_MSG="[cron-tick] master 점검 틱 — ★i-have-adhd 스타일로 출력(행동 우선·표·상태 재고지)★. ①★세션별 상세 테이블 필수★: 좌석명 / 에이전트 / ★지금 무슨 작업을 하는가★ / 상태(작업중·대기·응답없음·소진) — mbox 로 확인하고 pane 캡처로 판정 금지 ②★arch 가 지정한 구현 윈도우 상태★: 지금 닫는 인덱스 번호와 제목 / 사이클 단계(①기획~⑥정리 중 어디) / ★무엇을 구현 중인가★ / 남은 것 ③사용자 확인이 필요한 항목 — 있으면 모아서 한 번에(워커가 직접 묻지 않는다) ④press 순번 충돌과 GPU 창 잔여 ⑤미커밋 산출물이 있으면 커밋 ⑥★새 지시가 있었으면 USER-ORDERS-REGISTER 에 등록됐는지 확인★ ⑦★★oc 좌석 정지 감지★★ — impl-oc·checker-oc·tester-oc 등 opencode 좌석은 ★가끔 조용히 멈춘다★. 판별: ★작업 중인 파일의 mtime 이 10분 이상 정지★ + ★git diff --stat 변화 없음★ + ctx·비용 거의 안 움직임. ★★멈춘 것으로 보이면 오빠께 즉시 개입 요청★★(오빠가 취소 후 continue 를 걸면 재개된다). 실측 근거(파일 mtime·경과분)를 함께 올릴 것. 변화 없으면 \"변화 없음\" 1줄."
pm_msg() { # $1 = report_to
  echo "[cron-tick] pm 점검 틱(v65 정본 기준, 2026-09-13 master-sonnet#0 개정 — PROGRESS.md/fable-orch/ammo 계열 폐기, 참조 금지) — RUNLOG-pm1-v65-timeline.md(최신 E번호)·NANO-LEDGER-pm1-temp-sessions.md·GOAL-LEDGER-v65.md·GOAL-20260912-clear-list.md 대조해 ①골 대조 한 줄(지금 진행 중인 것이 M?/G? 어느 축인가) ②원장 미등재 항목 유무 ③활성 나노(ft-v65-temp-*) 전수 @zc_v65_active 태그 확인 — 0 인 활성 좌석은 이 틱에서 즉시 tmux set-option 으로 표식 ④사람 확인 필요 항목은 모아서 $1 에. 변화 없으면 \"변화 없음\" 1줄."
}

# 한 좌석·한 종류 발사: ② 간격 → ③ busy → 전송 → ④ 제출 검증. $1 seat $2 kind $3 interval $4 min_gap $5 msg
fire() {
  local seat="$1" kind="$2" interval="$3" min_gap="$4" msg="$5" stamp gap pane tail
  stamp="$(stamp_of "$seat" "$kind")"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY seat=$seat kind=$kind interval=${interval}s gap=${gap}s msg=${msg:0:80}"; return 0; fi
  [ "$gap" -ge "$interval" ] || return 0                                   # 아직 차례 아님(조용)
  [ "$gap" -ge "$min_gap" ] || { log "skip $seat/$kind — debounce (${gap}s < ${min_gap}s)"; return 0; }
  pane="$(pane_of "$seat")"; [ -n "$pane" ] || { log "skip $seat/$kind — session absent"; return 0; }
  tail="$(tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -3)"
  if printf '%s' "$tail" | LC_ALL=C grep -qaE 'esc to interrupt|Working|Thinking'; then log "skip $seat/$kind — pane busy (working)"; return 0; fi
  if printf '%s' "$tail" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then log "skip $seat/$kind — pane has unsubmitted input"; return 0; fi
  tmux send-keys -t "$pane" -l "$msg"; sleep 0.3; tmux send-keys -t "$pane" Enter
  now > "$stamp"
  sleep 1.5
  if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -2 | LC_ALL=C grep -qaE '^[›❯] +\[cron-tick\]'; then
    log "$seat/$kind not submitted — sending Enter once more"; tmux send-keys -t "$pane" Enter
  fi
  log "$kind sent to $seat ($pane)"
}

# goal-tick: 기존 ft-goal-tick.sh 를 좌석 대상으로 «그대로» 실행(내부에서 ft-goal-check → rc=0 이면 조용, rc≠0 relay).
goal() {
  local seat="$1" stamp gap
  stamp="$(stamp_of "$seat" goal)"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  [ -x "$GOAL_TICK" ] || [ -f "$GOAL_TICK" ] || { echo "$(date '+%F %T') goal-tick script missing: $GOAL_TICK" >&2; return 0; }
  if [ "$DRY" = 1 ]; then
    echo "DRY seat=$seat kind=goal-tick interval=${GOAL_INTERVAL}s gap=${gap}s msg=(ft-goal-tick.sh 결과 → rc≠0 일 때만 relay)"; return 0
  fi
  [ "$gap" -ge "$GOAL_INTERVAL" ] || return 0
  FT_GOAL_TICK_TARGET="$seat" bash "$GOAL_TICK" | sed "s/^/goal-tick[$seat] /"
  now > "$stamp"
}

pass() {
  local rows seat tick role report_to
  rows="$(read_seats 2>&1)" || { echo "$(date '+%F %T') seats.json unreadable ($SEATS): ${rows//$'\n'/ | }" >&2; return 1; }
  [ -n "$rows" ] || { log "no active seat with tick in $SEATS"; return 0; }
  report_to="$(master_seat "$rows")"; report_to="${FT_TICK_PM_REPORT_TO:-${report_to:-ft-v65-master}}"
  while IFS=$'\t' read -r seat tick role; do
    case "$tick" in
      ft-master-tick) fire "$seat" master "$MASTER_INTERVAL" "$MASTER_MIN_GAP" "$MASTER_MSG"; goal "$seat";;
      ft-pm-tick)     fire "$seat" pm "$PM_INTERVAL" "$PM_MIN_GAP" "$(pm_msg "$report_to")";;
      ft-goal-tick)   goal "$seat";;
      *) echo "$(date '+%F %T') unknown tick kind '$tick' for $seat — skipped" >&2;;
    esac
  done <<< "$rows"
}

if [ "$DRY" = 1 ]; then pass; exit $?; fi

# ── ① 단일 인스턴스 — 살아 있는 선점자가 있으면 죽을 때까지 대기(launchd 재스폰 폭주 방지) ──
while :; do
  OLD="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill -0 "$OLD" 2>/dev/null; then
    [ "$ONCE" = 1 ] && { log "already running (pid=$OLD) — exit"; exit 0; }
    log "already running (pid=$OLD) — standby"; sleep 10; continue
  fi
  echo "$$" > "$PIDFILE"; break
done
trap 'rm -f "$PIDFILE"; log "ft-tick stopped"; exit 0' INT TERM
log "ft-tick started pid=$$ seats=$SEATS loop=${LOOP_SEC}s master=${MASTER_INTERVAL}s pm=${PM_INTERVAL}s goal=${GOAL_INTERVAL}s"
while :; do
  pass
  [ "$ONCE" = 1 ] && { rm -f "$PIDFILE"; exit 0; }
  sleep "$LOOP_SEC"
done
