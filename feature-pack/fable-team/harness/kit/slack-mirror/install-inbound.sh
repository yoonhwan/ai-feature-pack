#!/usr/bin/env bash
# install-inbound.sh — Slack→mbox 역방향(오빠 글 → 좌석)를 ~/.hermes 에 설치하고 launchd 1개를 (재)기동한다. 멱등.
# 사용: bash install-inbound.sh   (BYZ_ROOT=<.fable-team 이 있는 리포 루트> 필요)
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${BYZ_ROOT:?BYZ_ROOT 필요 — .fable-team 이 있는 리포 루트}"
SEATS="${MIRROR_SEATS:-$ROOT/.fable-team/seats-harness.json}"
MBOX="$ROOT/.fable-team/comm/mbox.sh"
CHANNEL="${MIRROR_CHANNEL:-C0C6MJGRR89}"
MENTION="${MIRROR_MENTION:-U0AC2JF0M7D}"
PY="${MIRROR_PY:-/opt/homebrew/bin/python3}"
LABEL="com.hermes.byz-slack-mbox-inbound"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TOKEN="$HOME/.hermes/secrets/yoonhwan_bot.env"

[ -f "$TOKEN" ] || { echo "ERROR: 토큰 파일 없음: $TOKEN" >&2; exit 1; }
[ "$(stat -f %Lp "$TOKEN")" = "600" ] || { echo "ERROR: 토큰 파일 권한이 600 이 아니다" >&2; exit 1; }
[ -x "$PY" ] || { echo "ERROR: python 없음: $PY" >&2; exit 1; }
[ -f "$MBOX" ] || { echo "ERROR: mbox.sh 없음: $MBOX" >&2; exit 1; }
[ -f "$SEATS" ] || { echo "ERROR: seats 파일 없음: $SEATS" >&2; exit 1; }

mkdir -p "$HOME/.hermes/scripts" "$HOME/.hermes/logs" "$HOME/.hermes/state" "$HOME/Library/LaunchAgents"
for f in byz_slack_mbox_inbound.py mirror_inbound.py mirror_plan.py mirror_questions.py mirror_deliver.py mirror_lib.py; do
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
chmod +x "$HOME/.hermes/scripts/byz_slack_mbox_inbound.py"

PY="$PY" HOME_DIR="$HOME" CHANNEL="$CHANNEL" MENTION="$MENTION" MBOX="$MBOX" SEATS="$SEATS" \
  python3 - "$KIT/$LABEL.plist.template" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__CHANNEL__", "CHANNEL"), ("__MENTION__", "MENTION"), ("__MBOX__", "MBOX"), ("__SEATS__", "SEATS")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "installed $LABEL channel=$CHANNEL human=$MENTION mbox=$MBOX seats=$SEATS"
