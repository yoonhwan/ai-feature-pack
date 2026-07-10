#!/usr/bin/env bash
# TeammateIdle auto-GC hook
# 조건: idle 개수 > N(3) AND 최초 idle 발생 후 1분 경과 → 자동 종료
# keep-* 이름 패턴은 보호 (절대 종료 안 함)

set -euo pipefail

IDLE_DIR="/tmp/claude-teammate-idle"
MAX_IDLE=10
GRACE_SEC=1800
mkdir -p "$IDLE_DIR"

INPUT=$(cat)
TEAMMATE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('teammate_name',''))" 2>/dev/null || true)
SESSION=$(printf '%s' "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || true)

[[ -z "$TEAMMATE" || -z "$SESSION" ]] && exit 0

# 보호 패턴 → 무조건 유지 (재사용 pane)
# <PREFIX>-*: fable-team 로스터 (ft-implementer, ft-tester, ft-planner 등 — PREFIX는 install.json에서 런타임 로드)
# keep-*: 명시적 보호 지정
PREFIX=$(python3 -c "import json; print(json.load(open('${CLAUDE_PROJECT_DIR:-.}/.fable-team/install.json')).get('prefix','ft'))" 2>/dev/null || echo ft)
[[ "$TEAMMATE" == ${PREFIX}-* || "$TEAMMATE" == keep-* ]] && exit 0

# 1시간 넘은 stale 기록 정리 (이전 세션 잔류물)
find "$IDLE_DIR" -maxdepth 1 -name "*.idle" -mmin +60 -delete 2>/dev/null || true

IDLE_FILE="${IDLE_DIR}/${SESSION}__${TEAMMATE}.idle"
NOW=$(date +%s)

# 이 teammate의 idle 시작 기록 (최초 1회만)
if [[ ! -f "$IDLE_FILE" ]]; then
  printf '%s' "$NOW" > "$IDLE_FILE"
fi

# 이 세션의 idle teammate 수
IDLE_COUNT=0
OLDEST_TIME="$NOW"
for f in "${IDLE_DIR}/${SESSION}__"*.idle; do
  [[ -f "$f" ]] || continue
  IDLE_COUNT=$((IDLE_COUNT + 1))
  T=$(cat "$f" 2>/dev/null || echo "$NOW")
  [[ "$T" -lt "$OLDEST_TIME" ]] && OLDEST_TIME="$T"
done

ELAPSED=$((NOW - OLDEST_TIME))

# 로그 (디버그용)
printf '[idle-gc] teammate=%s count=%d/%d elapsed=%ds/%ds\n' \
  "$TEAMMATE" "$IDLE_COUNT" "$MAX_IDLE" "$ELAPSED" "$GRACE_SEC" \
  >> /tmp/teammate-idle-gc.log 2>/dev/null || true

# 조건: idle 개수 > MAX_IDLE AND 최초 idle 후 GRACE_SEC 경과
if [[ "$IDLE_COUNT" -gt "$MAX_IDLE" ]] && [[ "$ELAPSED" -gt "$GRACE_SEC" ]]; then
  rm -f "$IDLE_FILE"
  printf '{"continue": false, "stopReason": "auto-gc: %d idle (>%d), grace %ds (>%ds)"}\n' \
    "$IDLE_COUNT" "$MAX_IDLE" "$ELAPSED" "$GRACE_SEC"
  printf '[idle-gc] STOPPED %s (count=%d elapsed=%ds)\n' "$TEAMMATE" "$IDLE_COUNT" "$ELAPSED" \
    >> /tmp/teammate-idle-gc.log 2>/dev/null || true
fi
