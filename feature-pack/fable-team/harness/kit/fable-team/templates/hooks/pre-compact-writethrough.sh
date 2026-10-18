#!/bin/bash
# fable-team pre-compact-writethrough — PreCompact 훅 (§2-3②)
# ACTIVE 존재 시 state.md 이벤트 로그에 `- <ts> PRE-COMPACT 감지` 결정론 append +
# state.md mtime > 15분이면 "STALE — compact 전 write-through 의무" 컨텍스트 주입.
# ★ FAIL-OPEN: 어떤 오류에서도 exit 0 (훅이 compact를 막지 않는다).
set +e
INPUT=$(cat 2>/dev/null)   # PreCompact payload(사용 안 함) — stdin 소비만

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FT="$ROOT/.fable-team"
ACTIVE="$FT/state/ACTIVE"
[ -f "$ACTIVE" ] || exit 0
SLUG="$(head -1 "$ACTIVE" 2>/dev/null | tr -d '[:space:]')"
[ -n "$SLUG" ] || exit 0

# state 파일: per-feature 우선, 없으면 단일 state.md
STATE_MD="$FT/state/$SLUG.state.md"
[ -f "$STATE_MD" ] || STATE_MD="$FT/state/state.md"
[ -f "$STATE_MD" ] || exit 0

# ── stale 판정은 append 이전 mtime 기준(append가 mtime을 갱신하므로 선판독) ──
now=$(date +%s)
mt=$(stat -f %m "$STATE_MD" 2>/dev/null || stat -c %Y "$STATE_MD" 2>/dev/null)
stale=0
if [ -n "$mt" ] && [ $((now - mt)) -gt 900 ]; then stale=1; fi

# ── 결정론 이벤트 append ──
printf -- '- %s PRE-COMPACT 감지\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$STATE_MD" 2>/dev/null

# ── stale이면 write-through 의무 컨텍스트 주입 ──
if [ "$stale" = "1" ]; then
  MSG="⚠️ [pre-compact] fable-team ACTIVE=$SLUG state.md가 15분+ STALE입니다 — compact 전 write-through 의무: 워커 산출물·라운드·결정을 state.md에 반영한 뒤 compact 하세요(미반영분은 compact로 증발)."
  printf '%s\n' "$MSG" >&2
  python3 - "$MSG" <<'PY' 2>/dev/null
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":sys.argv[1]}}))
PY
fi
exit 0
