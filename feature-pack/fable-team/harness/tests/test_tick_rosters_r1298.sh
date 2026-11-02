#!/usr/bin/env bash
# R1298 R15 — ft-tick 소비자는 현역 TEAMS 좌석표만 ft_raised에 넘긴다.
set -uo pipefail
export LC_ALL=C
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"; mkdir -p "$ROOT/design/teams/active/indices" "$ROOT/design/teams/sleep/indices"
mkdir -p "$ROOT/.fable-team/comm" "$ROOT/.fable-team/state" "$ROOT/.fable-team/bin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| active | design/teams/active/ | x | 현역 |\n| sleep | design/teams/sleep/ | x | 휴면 |\n' > "$ROOT/design/TEAMS.md"
printf '{"_master":"m#1","_label":"active","_cards":"design/teams/active/indices","_cards_wt":"","m#1":{"role":"master"}}\n' > "$ROOT/.fable-team/seats-active.json"
printf '{"_master":"s#1","_label":"sleep","_cards":"design/teams/sleep/indices","_cards_wt":"","s#1":{"role":"master"}}\n' > "$ROOT/.fable-team/seats-sleep.json"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/.fable-team/comm/mbox.sh"
cat > "$TMP/raised.py" <<'PY'
#!/usr/bin/env python3
import os
import sys
open(os.environ["FT_RAISED_ARGS"], "w").write("\n".join(sys.argv[1:]))
PY
chmod +x "$TMP/raised.py"
export FT_ROOT="$ROOT" FT_TEAMS_MD="$ROOT/design/TEAMS.md" FT_TICK_SEATS="$ROOT/.fable-team/seats-active.json"
export FT_TICK_RAISED_BIN="$TMP/raised.py" FT_RAISED_ARGS="$TMP/raised.args" FT_TICK_MBOX="$ROOT/.fable-team/comm/mbox.sh"
export FT_MBOX_DIR="$ROOT/.fable-team/comm" FT_TICK_PIDFILE="$ROOT/tick.pid"
export FT_TICK_STAMP_PREFIX="$ROOT/stamp-" FT_TICK_STATE_DIR="$ROOT/.fable-team/state/tick"
export FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0
export FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_MODEL_SWAP=0
export FT_TICK_UNPUSHED=0 FT_TICK_RENAMED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_CARD_ASSIGN=0 FT_TICK_RAISED=1
bash "$BIN/ft-tick.sh" --once >/dev/null 2>&1
grep -q 'seats-active.json' "$FT_RAISED_ARGS"
! grep -q 'seats-sleep.json' "$FT_RAISED_ARGS"
echo "PASS R15 ft-tick roster lookup excludes dormant team"
