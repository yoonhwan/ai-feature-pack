#!/bin/bash
# fable-team ft-session-restore — SessionStart 훅 (§2-3③)
# CWD 기준 .fable-team/state/ACTIVE(+ .worktrees/* glob) 탐지 → 존재 시 복원 안내 additionalContext 주입
# + watchd 헬스 리페어 지시 + (ft-pm-* 세션 존재 시) BRIEF_REQUEST 권고. 부재 시 무출력.
# ★ FAIL-OPEN: 어떤 오류에서도 exit 0.
set +e
INPUT=$(cat 2>/dev/null)   # SessionStart payload(사용 안 함)

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ── ACTIVE 탐지: 루트 + 워크트리 glob ──
FOUND=""
for a in "$ROOT/.fable-team/state/ACTIVE" "$ROOT"/.worktrees/*/.fable-team/state/ACTIVE; do
  [ -f "$a" ] && { FOUND="$a"; break; }
done
[ -n "$FOUND" ] || exit 0

SLUG="$(head -1 "$FOUND" 2>/dev/null | tr -d '[:space:]')"
[ -n "$SLUG" ] || exit 0

FTDIR="$(dirname "$(dirname "$FOUND")")"   # .../.fable-team/state → .../.fable-team
STATE_MD="$FTDIR/state/$SLUG.state.md"
[ -f "$STATE_MD" ] || STATE_MD="$FTDIR/state/state.md"

# stage/status 파싱(느슨 — 없으면 ?)
STAGE="?"; STATUS="?"
if [ -f "$STATE_MD" ]; then
  s="$(grep -iE 'stage:' "$STATE_MD" 2>/dev/null | head -1 | sed -E 's/.*stage:[[:space:]]*([0-9]+).*/\1/')"
  [ -n "$s" ] && STAGE="$s"
  st="$(grep -iE 'status:' "$STATE_MD" 2>/dev/null | head -1 | sed -E 's/.*status:[[:space:]]*([A-Za-z_-]+).*/\1/')"
  [ -n "$st" ] && STATUS="$st"
fi

# ft-pm 세션 존재 확인
PM="$(tmux ls -F '#{session_name}' 2>/dev/null | grep -m1 '^ft-pm-')"

MSG="fable-team ACTIVE=$SLUG stage=$STAGE status=$STATUS — context-management §4 복원 선행."
if [ -n "$PM" ]; then
  MSG="$MSG ft-pm 세션($PM) 존재 → BRIEF_REQUEST 송신(맥락 재주입) 권고."
fi
MSG="$MSG watchd 헬스 리페어: '.fable-team/bin/ft-pm-watchd.sh --ensure'로 pid·start-time 검증(stale이면 재기동)."

printf '%s\n' "$MSG" >&2
python3 - "$MSG" <<'PY' 2>/dev/null
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))
PY
exit 0
