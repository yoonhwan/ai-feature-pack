#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: harness/comm/ · 드리프트 확인: harness/comm/check-drift.sh
# ft-v65-pm-codex#0 크론 틱 — 보드 리뷰·프로그레스 공유 트리거
#
# 2026-08-16 개정 (master#3): 틱 루프가 3개 동시에 돌면서 같은 pane 에
# 멀티바이트를 겹쳐 써 화면이 깨졌고, 보고 수신처가 죽은 master#0 이라
# pm 이 10분마다 일하고 아무도 안 받는 곳으로 보내고 있었다.
# 아래 4중 디바운스로 재발을 막는다.
#   ① 단일 인스턴스 lock (pidfile + 생존 확인)
#   ② 최소 간격 보장 (직전 전송 이후 MIN_GAP 미만이면 스킵)
#   ③ pane busy 스킵 (작업 중이거나 미제출 입력이 있으면 안 보낸다)
#   ④ 전송 후 제출 검증 (미제출이면 1회 Enter 보정)
#
# 세션명에 '#'가 있어 -t 직접 타겟 금지: pane_id 로 해석해 송신한다.

set -uo pipefail

TARGET_SESSION="${FT_PM_TICK_TARGET:-ft-v65-pm-codex#0}"
REPORT_TO="${FT_PM_TICK_REPORT_TO:-ft-v65-master#10}"
INTERVAL="${FT_PM_TICK_INTERVAL:-600}"
MIN_GAP="${FT_PM_TICK_MIN_GAP:-540}"
PIDFILE="${FT_PM_TICK_PIDFILE:-/tmp/ft-pm-tick.pid}"
STAMP="${FT_PM_TICK_STAMP:-/tmp/ft-pm-tick.last}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT_MONITOR="${FT_PM_CONTEXT_MONITOR:-$SCRIPT_DIR/ft-context-monitor.sh}"
FABLE_ORCH="${FT_PM_FABLE_ORCH:-ft-v65-fable-orch#9}"
# R383: 기본 규칙 문서 = v65 팀 폴더(cwd 리포의 design/TEAMS.md · 팀 이름 글자 0) — 못 풀면 ERROR 종료(옛 경로 후퇴 0)
if [ -n "${FT_PM_RULES_FILE:-}" ]; then RULES_FILE="$FT_PM_RULES_FILE"
else _v65rel="$( . "$SCRIPT_DIR/ft-team-lib.sh" && ft_team_rel v65 )" || { echo "ERROR v65 팀 폴더를 못 풀었다(design/TEAMS.md) — FT_PM_RULES_FILE 로 지정하거나 명단을 고친다" >&2; exit 1; }; RULES_FILE="${_v65rel}20260826/RULES-ammo-and-distill-20260826.md"; fi
CURRENT_INDEX="${FT_PM_CURRENT_INDEX:-v65-S4}"
CURRENT_AMMO="${FT_PM_CURRENT_AMMO:-6}"
CTX_SUMMARY="${FT_PM_CTX_SUMMARY:-n/a}"

log() { echo "$(date '+%F %T') $*"; }

# ── ① 단일 인스턴스 lock ────────────────────────────────────────────
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    log "already running (pid=$OLD) — exit"
    exit 0
  fi
  log "stale pidfile (pid=${OLD:-none}) — taking over"
fi
echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"; log "tick loop stopped"; exit 0' INT TERM EXIT

log "tick loop started pid=$$ target=$TARGET_SESSION report_to=$REPORT_TO fable_orch=$FABLE_ORCH interval=${INTERVAL}s min_gap=${MIN_GAP}s"

while :; do
  PANE=$(tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null \
         | awk -v s="$TARGET_SESSION" '$1==s{print $2; exit}')
  if [ -z "$PANE" ]; then
    log "target session gone — tick loop exit"
    exit 0
  fi

  MSG="[cron-tick] pm 점검 틱(v65 정본 기준, 2026-09-13 master-sonnet#0 개정 — PROGRESS.md/fable-orch/ammo 계열 폐기, 참조 금지) — RUNLOG-pm1-v65-timeline.md(최신 E번호)·NANO-LEDGER-pm1-temp-sessions.md·GOAL-LEDGER-v65.md·GOAL-20260912-clear-list.md 대조해 ①골 대조 한 줄(지금 진행 중인 것이 M?/G? 어느 축인가) ②원장 미등재 항목 유무 ③활성 나노(byz-v65-nano-* · 옛 이름 ft-v65-temp-*) 전수 @zc_v65_active 태그 확인 — 0 인 활성 좌석은 이 틱에서 즉시 tmux set-option 으로 표식 ④사람 확인 필요 항목은 모아서 ${REPORT_TO} 에. 변화 없으면 \"변화 없음\" 1줄."

  log "ctx — $CTX_SUMMARY"

  SKIP=""

  # ── ② 최소 간격 (디바운스) ────────────────────────────────────────
  if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    GAP=$(( NOW - LAST ))
    [ "$GAP" -lt "$MIN_GAP" ] && SKIP="debounce (last tick ${GAP}s ago < ${MIN_GAP}s)"
  fi

  # ── ③ pane busy 스킵 ─────────────────────────────────────────────
  if [ -z "$SKIP" ]; then
    TAIL=$(tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -vE '^\s*$' | tail -3)
    if printf '%s' "$TAIL" | LC_ALL=C grep -qaE 'esc to interrupt|Working|Thinking'; then
      SKIP="pane busy (working)"
    elif printf '%s' "$TAIL" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then
      SKIP="pane has unsubmitted input"
    fi
  fi

  if [ -n "$SKIP" ]; then
    log "skip — $SKIP"
    sleep "$INTERVAL"
    continue
  fi

  # ── 전송 ─────────────────────────────────────────────────────────
  tmux send-keys -t "$PANE" -l "$MSG"
  sleep 0.3
  tmux send-keys -t "$PANE" Enter
  date +%s > "$STAMP"

  # ── ④ 제출 검증 (미제출이면 1회 보정) ────────────────────────────
  sleep 1.5
  if tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -vE '^\s*$' | tail -2 \
     | LC_ALL=C grep -qaE '^[›❯] +\[cron-tick\]'; then
    log "not submitted — sending Enter once more"
    tmux send-keys -t "$PANE" Enter
  fi

  log "tick sent to $PANE (report_to=$REPORT_TO)"
  sleep "$INTERVAL"
done
