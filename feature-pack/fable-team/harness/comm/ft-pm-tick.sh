#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
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
RULES_FILE="${FT_PM_RULES_FILE:-design/v65/20260826/RULES-ammo-and-distill-20260826.md}"
CURRENT_INDEX="${FT_PM_CURRENT_INDEX:-v65-S4}"
CURRENT_AMMO="${FT_PM_CURRENT_AMMO:-6}"

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

  CTX_SUMMARY=$(bash "$CONTEXT_MONITOR" "$REPORT_TO" "$TARGET_SESSION" 2>/dev/null || echo "측정 실패")
  MSG="[cron-tick] 틱: .fable-team/v65/ 폴더(PROGRESS.md·TODO.md·DOING.md·DONE.md)를 Read하고 ①전체 단계 흐름 요약·상태·프로그레스 ②현재 단계 요약·상태·프로그레스 를 정리해 화면 출력 + mbox로 ${REPORT_TO}·${FABLE_ORCH} 에 공유하라. ③시간보고 운영 신호: (g) 좌석별 ctx%=${CTX_SUMMARY} (h) 열린 이슈별 회차 카운터 — 3회 도달 즉시 ${FABLE_ORCH}·${REPORT_TO}에 별도 보고, 4회차 전에 중단 (i) 돌기 신호 — 미완 이슈 위 크리티컬 점프 감지 즉시 ${FABLE_ORCH}·${REPORT_TO}에 별도 보고 (j) 정체 신호 — 전 좌석 idle+크리티컬 패스 정체 감지 즉시 해당 소유자에게 같은 턴 재가동 트리거를 보내고 ${FABLE_ORCH}·${REPORT_TO}에 별도 보고. COMPACTING 자체는 정상 동작이라 보고하지 말고, 표시가 잡히면 해당 pane을 직접 확인해 compact 후 재개 실패일 때만 (j)·(k) 별도 보고하라. (k) Claude 503 빈도 — \`~/.headroom/logs/proxy.log\`에서 직전 보고 이후 \`503 auth_unavailable\` 건수·영향 좌석·타임스탬프 fresh 300tok 스모크 결과를 보고하라. \`/health\`나 동일 msg id 캐시 응답은 회복 증거가 아니다. 재시도 소진+queued 고착이면 \`Escape→Enter\` 순차 해제 후 소유자를 재가동하되 \`:8790\` kickstart는 오빠 HIL 전 실행하지 마라. 동일 결함 press 2회 연속이면 3회차 press 대신 checker 정적 대조를 먼저 하고, evidence에는 raw 콘솔·로그 캡처를 남겨라. 보드 갱신분 없으면 \"변화 없음\" 1줄."

# ── 5. 오빠 확정 룰(4-1총알·4-2증류) 틱 반영 ──────────────────
AMMO_INDEX="${CURRENT_INDEX:-v65-S4}"
AMMO_LEFT="${CURRENT_AMMO:-6}"
# 4-1: 잔여 0 이면 즉시 "정지·정렬 → 오빠 상신" 메시지로 강조
if [ "${AMMO_LEFT}" -eq 0 ] 2>/dev/null; then
  MSG="${MSG} ★정지·정렬 신호★: 총알 잔여 0 — 자동 충전 금지, 즉시 오빠 상신 항목으로 올려라(정본 4-1)."
else
  MSG="${MSG} ★4-1 총알 감시★: 현재 인덱스 ${AMMO_INDEX}·잔여 발수 ${AMMO_LEFT} — 인덱스 단계 넘어가면 clamp(n,5) 충전 delta 발행. ★4-2 ctx 80% 감시★: 9세션 ctx 점검 → 80% 도달 좌석 명시·「증류 큐 등록」 통지·증류 지원(pm), 좌석 개설=master 레인."
fi

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
