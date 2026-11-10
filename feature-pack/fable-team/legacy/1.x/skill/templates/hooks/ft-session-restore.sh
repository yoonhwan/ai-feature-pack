#!/bin/bash
# fable-team ft-session-restore — SessionStart 훅 (§2-3③)
# CWD 기준 .fable-team/state/ACTIVE(+ .worktrees/* glob) 탐지 → 존재 시 복원 안내 additionalContext 주입
# + watchd 헬스 리페어 지시 + (ft-pm-* 세션 존재 시) BRIEF_REQUEST 권고.
# + MBOX 미수신분 기계 recv(comm-filebased D-6 경로3) — ft-* 세션 시작·재개·복원 시 자동 회수.
# ★ FAIL-OPEN: 어떤 오류에서도 exit 0.
set +e
INPUT=$(cat 2>/dev/null)   # SessionStart payload(사용 안 함)

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# ── MBOX 미수신분 기계 recv(D-6 경로3): ACTIVE 탐지·early-exit보다 앞. consume형. ──
ME="$(tmux display-message -p '#S' 2>/dev/null)"
MBOX_CTX=""
case "$ME" in
  ft-*) RECV="$(bash "$ROOT/.fable-team/bin/ft-mbox.sh" recv "$ME" 2>/dev/null)"
        [ -n "$RECV" ] && [ "$RECV" != "READ none" ] && MBOX_CTX="[MBOX 미수신분 자동회수] $RECV" ;;
esac

# ── ACTIVE 탐지: 루트 + 워크트리 glob ──
FOUND=""
for a in "$ROOT/.fable-team/state/ACTIVE" "$ROOT"/.worktrees/*/.fable-team/state/ACTIVE; do
  [ -f "$a" ] && { FOUND="$a"; break; }
done
# ACTIVE·MBOX_CTX 둘 다 없으면 무출력(부재 시 조용)
[ -n "$FOUND" ] || [ -n "$MBOX_CTX" ] || exit 0

MSG=""
if [ -n "$FOUND" ]; then
  SLUG="$(head -1 "$FOUND" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$SLUG" ]; then
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
  fi
fi

# MBOX_CTX 합류(있으면 앞에) — additionalContext에 미수신분 우선 노출
if [ -n "$MBOX_CTX" ]; then
  [ -n "$MSG" ] && MSG="$MBOX_CTX $MSG" || MSG="$MBOX_CTX"
fi
[ -n "$MSG" ] || exit 0

printf '%s\n' "$MSG" >&2
python3 - "$MSG" <<'PY' 2>/dev/null
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":sys.argv[1]}}))
PY
exit 0
