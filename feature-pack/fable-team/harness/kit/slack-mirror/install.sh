#!/usr/bin/env bash
# install.sh — Slack 읽기 미러를 ~/.hermes 에 설치하고 launchd 1개를 (재)기동한다. 멱등.
# 사용: BYZ_ROOT=<리포 루트(= .fable-team 이 있는 곳)> bash install.sh
# 토큰은 ~/.hermes/secrets/yoonhwan_bot.env (chmod 600) — 없으면 중단한다(채우는 건 사람/harness-ops).
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${BYZ_ROOT:?BYZ_ROOT 필요 — .fable-team 이 있는 리포 루트}"
PROJECT="${MIRROR_PROJECT:-byz}"
SEAT="${MIRROR_SEAT:-^byz-planner-arch#[0-9]+\$}"
CHANNEL="${MIRROR_CHANNEL:-C0C6MJGRR89}"
MENTION="${MIRROR_MENTION:-U0AC2JF0M7D}"
PY="${MIRROR_PY:-/opt/homebrew/bin/python3}"
MAILBOX="$ROOT/.fable-team/comm/mailbox.log.jsonl"
LABEL="com.hermes.byz-mbox-slack-mirror"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TOKEN="$HOME/.hermes/secrets/yoonhwan_bot.env"

[ -f "$TOKEN" ] || { echo "ERROR: 토큰 파일 없음: $TOKEN" >&2; exit 1; }
[ "$(stat -f %Lp "$TOKEN")" = "600" ] || { echo "ERROR: 토큰 파일 권한이 600 이 아니다" >&2; exit 1; }
[ -x "$PY" ] || { echo "ERROR: python 없음: $PY" >&2; exit 1; }
[ -f "$MAILBOX" ] || { echo "ERROR: 사본 로그 없음(D1 미적용?): $MAILBOX" >&2; exit 1; }

mkdir -p "$HOME/.hermes/scripts" "$HOME/.hermes/logs" "$HOME/.hermes/state" "$HOME/Library/LaunchAgents"
for f in byz_mbox_slack_mirror.py mirror_lib.py mirror_summary.py; do
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
chmod +x "$HOME/.hermes/scripts/byz_mbox_slack_mirror.py"

PY="$PY" HOME_DIR="$HOME" PROJECT="$PROJECT" MAILBOX="$MAILBOX" SEAT="$SEAT" CHANNEL="$CHANNEL" MENTION="$MENTION" \
  python3 - "$KIT/$LABEL.plist.template" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__PROJECT__", "PROJECT"),
               ("__MAILBOX__", "MAILBOX"), ("__SEAT__", "SEAT"), ("__CHANNEL__", "CHANNEL"), ("__MENTION__", "MENTION")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
plutil -lint "$PLIST" >/dev/null

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "installed $LABEL channel=$CHANNEL seat=$SEAT mailbox=$MAILBOX"
