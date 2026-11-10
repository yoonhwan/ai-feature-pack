#!/usr/bin/env bash
# install-github.sh — GitHub→Slack 미러(열림·닫힘·머지·hil:needed)를 ~/.hermes 에 설치하고 launchd 1개를 (재)기동한다. 멱등.
# 사용: BYZ_ROOT=<리포 루트(= .fable-team 이 있는 곳)> bash install-github.sh   (토큰: Slack = ~/.hermes/secrets/yoonhwan_bot.env · GitHub = gh auth 키체인)
#   결정 자리 줄의 근거인 planner 명부는 $BYZ_ROOT/.fable-team/seats-planner.json (MIRROR_PLANNER_SEATS 로 직접 지정 가능)
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
REPO="${MIRROR_REPO:-SecondWindStudio/byz-agents}"
CHANNEL="${MIRROR_CHANNEL:-C0C6MJGRR89}"
MENTION="${MIRROR_MENTION:-U0AC2JF0M7D}"
PY="${MIRROR_PY:-/opt/homebrew/bin/python3}"
LABEL="com.hermes.byz-github-slack-mirror"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TOKEN="$HOME/.hermes/secrets/yoonhwan_bot.env"
PLANNER_SEATS="${MIRROR_PLANNER_SEATS:-${BYZ_ROOT:+$BYZ_ROOT/.fable-team/seats-planner.json}}"
[ -n "$PLANNER_SEATS" ] || { echo "ERROR: planner 명부 경로 필요 — BYZ_ROOT=<리포 루트> 또는 MIRROR_PLANNER_SEATS=<seats-planner.json>" >&2; exit 1; }

[ -f "$TOKEN" ] || { echo "ERROR: 토큰 파일 없음: $TOKEN" >&2; exit 1; }
[ "$(stat -f %Lp "$TOKEN")" = "600" ] || { echo "ERROR: 토큰 파일 권한이 600 이 아니다" >&2; exit 1; }
[ -x "$PY" ] || { echo "ERROR: python 없음: $PY" >&2; exit 1; }
env -u GH_TOKEN gh auth token >/dev/null 2>&1 || { echo "ERROR: gh auth 토큰 없음 — gh auth login" >&2; exit 1; }

mkdir -p "$HOME/.hermes/scripts" "$HOME/.hermes/logs" "$HOME/.hermes/state" "$HOME/Library/LaunchAgents"
for f in byz_github_slack_mirror.py mirror_github.py mirror_lib.py mirror_share.py mirror_summary.py mirror_deliver.py resume_block.py mirror_team.py mirror_team_render.py mirror_team_roots.py magazine_indexless.py magazine_eli5_batches.py magazine_summary.py magazine_emit.py; do
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
chmod +x "$HOME/.hermes/scripts/byz_github_slack_mirror.py"

PY="$PY" HOME_DIR="$HOME" REPO="$REPO" CHANNEL="$CHANNEL" MENTION="$MENTION" PLANNER_SEATS="$PLANNER_SEATS" \
  python3 - "$KIT/$LABEL.plist.template" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__REPO__", "REPO"), ("__CHANNEL__", "CHANNEL"), ("__MENTION__", "MENTION"), ("__PLANNER_SEATS__", "PLANNER_SEATS")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "installed $LABEL repo=$REPO channel=$CHANNEL"
