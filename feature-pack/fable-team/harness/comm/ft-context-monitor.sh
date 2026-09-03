#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# ft-v65 좌석 컨텍스트 사용률·compaction 후 재개 실패 감시.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBOX="${FT_CTX_MBOX:-$SCRIPT_DIR/../comm/mbox.sh}"
CLAUDE_CONTEXT="${FT_CTX_CLAUDE_CONTEXT:-$SCRIPT_DIR/ft-claude-context.sh}"
REPORT_TO="${1:-ft-v65-master#10}"
FROM_SESSION="${2:-ft-v65-pm-codex#0}"
FABLE_ORCH="${FT_CTX_FABLE_ORCH:-ft-v65-fable-orch#9}"
SESSION_PREFIX="${FT_CTX_SESSION_PREFIX:-ft-v65-}"
EXCLUDE_SESSIONS="${FT_CTX_EXCLUDE_SESSIONS:-ft-v65-master#7,ft-v65-master#8,ft-v65-master#9,ft-v65-architect#4,ft-v65-architect#6,ft-v65-arch-fable#1,ft-v65-arch-fable#5,ft-v65-arch-fable#9,ft-v65-arch-judge#0,ft-v65-fable-orch#1,ft-v65-fable-orch#2,ft-v65-fable-orch#3,ft-v65-fable-orch#4,ft-v65-fable-orch#5,ft-v65-fable-orch#6,ft-v65-fable-orch#7,ft-v65-fable-orch#8}"
STATE_FILE="${FT_CTX_STATE_FILE:-/tmp/ft-v65-context-monitor.state}"
WARN_PCT="${FT_CTX_WARN_PCT:-70}"
FORCE_PCT="${FT_CTX_FORCE_PCT:-90}"
DRY_RUN="${FT_CTX_DRY_RUN:-0}"

parse_context_used() {
  local snapshot="$1" token pct left

  token=$(printf '%s\n' "$snapshot" \
    | LC_ALL=C grep -ioE '[0-9]{1,3}%[[:space:]]+context[[:space:]]+used' \
    | tail -1 || true)
  if [ -n "$token" ]; then
    pct=$(printf '%s' "$token" | LC_ALL=C grep -oE '[0-9]{1,3}' | head -1)
    printf '%s\n' "$pct"
    return 0
  fi

  token=$(printf '%s\n' "$snapshot" \
    | LC_ALL=C grep -oE 'ctx:[^%]*[0-9]{1,3}%' \
    | tail -1 || true)
  if [ -n "$token" ]; then
    pct=$(printf '%s' "$token" | LC_ALL=C grep -oE '[0-9]{1,3}%$' | tr -d '%')
    printf '%s\n' "$pct"
    return 0
  fi

  token=$(printf '%s\n' "$snapshot" \
    | LC_ALL=C grep -oE '[0-9]+(\.[0-9]+)?[KM][[:space:]]+\([0-9]{1,3}%\)' \
    | tail -1 || true)
  if [ -n "$token" ]; then
    pct=$(printf '%s' "$token" | LC_ALL=C grep -oE '\([0-9]{1,3}%\)' | tr -cd '0-9')
    printf '%s\n' "$pct"
    return 0
  fi

  token=$(printf '%s\n' "$snapshot" \
    | LC_ALL=C grep -oE 'Context[[:space:]]+[0-9]{1,3}%' \
    | tail -1 || true)
  if [ -n "$token" ]; then
    left=$(printf '%s' "$token" | LC_ALL=C grep -oE '[0-9]{1,3}' | head -1)
    printf '%s\n' "$((100 - left))"
    return 0
  fi

  return 1
}

if [ "${1:-}" = "--parse" ]; then
  INPUT=$(sed -n '1,$p')
  parse_context_used "$INPUT" || printf 'n/a\n'
  exit 0
fi

send_alert() {
  local target="$1" body="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf 'DRY-RUN to=%s %s\n' "$target" "$body" >&2
    return 0
  fi
  bash "$MBOX" send "$target" "$FROM_SESSION" "$body" >/dev/null 2>&1 || true
}

notify_master_and_seat() {
  local seat="$1" body="$2"
  send_alert "$REPORT_TO" "$body"
  [ "$FABLE_ORCH" = "$REPORT_TO" ] || send_alert "$FABLE_ORCH" "$body"
  if [ "$seat" != "$REPORT_TO" ] && [ "$seat" != "$FABLE_ORCH" ]; then
    send_alert "$seat" "$body"
  fi
}

mkdir -p "$(dirname "$STATE_FILE")"
ROWS_FILE=$(mktemp "${STATE_FILE}.rows.XXXXXX") || exit 1
TMP_STATE=$(mktemp "${STATE_FILE}.tmp.XXXXXX") || exit 1
cleanup() {
  [ -z "${ROWS_FILE:-}" ] || rm -f "$ROWS_FILE"
  [ -z "${TMP_STATE:-}" ] || rm -f "$TMP_STATE"
}
trap cleanup EXIT

tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
  | awk -F'|' -v prefix="$SESSION_PREFIX" -v excluded=",$EXCLUDE_SESSIONS," \
      'index($1, prefix) == 1 && index(excluded, "," $1 ",") == 0 {print $1 "|" $2}' \
  | sort -u > "$ROWS_FILE"

SUMMARY=""
while IFS='|' read -r SESSION PANE; do
  [ -n "$SESSION" ] || continue
  SNAPSHOT=$(tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -12)
  PCT=$(parse_context_used "$SNAPSHOT" || true)
  [ -n "$PCT" ] || PCT=$(bash "$CLAUDE_CONTEXT" "$SESSION" 2>/dev/null || true)
  case "$PCT" in
    ''|*[!0-9]*) PCT="" ;;
    *) [ "$PCT" -le 100 ] || PCT="" ;;
  esac

  OLD_LINE=$(awk -F'|' -v session="$SESSION" '$1 == session {print; exit}' "$STATE_FILE" 2>/dev/null || true)
  OLD_BAND=$(printf '%s' "$OLD_LINE" | awk -F'|' '{print $2}')
  OLD_COMPACT=$(printf '%s' "$OLD_LINE" | awk -F'|' '{print $3}')
  [ -n "$OLD_BAND" ] || OLD_BAND="normal"
  [ -n "$OLD_COMPACT" ] || OLD_COMPACT="0"

  BAND="$OLD_BAND"
  DISPLAY="n/a"
  if [ -n "$PCT" ]; then
    DISPLAY="${PCT}%"
    if [ "$PCT" -ge "$FORCE_PCT" ]; then
      BAND="force"
    elif [ "$PCT" -ge "$WARN_PCT" ]; then
      BAND="warn"
    else
      BAND="normal"
    fi

    if [ "$BAND" = "force" ] && [ "$OLD_BAND" != "force" ]; then
      BODY="[ctx-monitor] FORCE seat=${SESSION} ctx=${PCT}%. ${FORCE_PCT}% 도달: 지연 없이 강제 증류를 발동하고 연속성 스냅샷·후계 좌석 또는 compact 집행 결과를 즉시 보고하라."
      notify_master_and_seat "$SESSION" "$BODY"
    elif [ "$BAND" = "warn" ] && [ "$OLD_BAND" = "normal" ]; then
      BODY="[ctx-monitor] WARN seat=${SESSION} ctx=${PCT}%. ${WARN_PCT}% 도달: 현재 목표·완료 근거·미완·다음 1행동·dirty 파일의 연속성 스냅샷을 준비하고 증류 계획을 보고하라."
      notify_master_and_seat "$SESSION" "$BODY"
    fi
  fi

  COMPACT_NOW="0"
  if printf '%s\n' "$SNAPSHOT" \
    | LC_ALL=C grep -qiE '^[[:space:]]*([^[:alnum:][:space:]]+[[:space:]]*)?Compacting([^[:alpha:]]|$)'; then
    COMPACT_NOW="1"
  fi

  printf '%s|%s|%s|%s\n' "$SESSION" "$BAND" "$COMPACT_NOW" "${PCT:-n/a}" >> "$TMP_STATE"
  if [ "$COMPACT_NOW" = "1" ]; then
    DISPLAY="${DISPLAY}(compact 관측·pane 확인)"
  elif [ "$OLD_COMPACT" = "1" ]; then
    DISPLAY="${DISPLAY}(compact 후 재개 확인)"
  fi
  [ -z "$SUMMARY" ] || SUMMARY="${SUMMARY}, "
  SUMMARY="${SUMMARY}${SESSION}=${DISPLAY}"
done < "$ROWS_FILE"

mv "$TMP_STATE" "$STATE_FILE"
TMP_STATE=""
printf '%s\n' "${SUMMARY:-없음}"
