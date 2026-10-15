#!/usr/bin/env bash
# install-inbound.sh — Slack→mbox 역방향(오빠 글 → 좌석)를 ~/.hermes 에 설치하고 launchd 1개를 (재)기동한다. 멱등.
# 사용: bash install-inbound.sh   (BYZ_ROOT=<.fable-team 이 있는 리포 루트> 필요)
#   1번째 인스턴스(#byz-planner · --human 1명): 인자 없음 — 설치 + 기동(기존 동작 그대로).
#   2번째 인스턴스(#byz-talk · 명부 `_slack_users` N명 · 수신 좌석 = 전달마다 명부 키에서 읽음): --label <L> --channel <ID> --to-key <명부 키 예 _desk> --humans-from-seats
#     → plist «파일만» 쓴다. launchctl 호출 0 — 출력 `INSTALLED-NOT-LOADED <label>` (가동 = 후속 카드 r205b-desk-seat-open).
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${BYZ_ROOT:?BYZ_ROOT 필요 — .fable-team 이 있는 리포 루트}"
MBOX="$ROOT/.fable-team/comm/mbox.sh"
INBOX_BIN="${FT_INBOX_BIN:?FT_INBOX_BIN 필요 — ft-inbox.sh 절대 경로(조용한 기본값 없음)}"
MENTION="${MIRROR_MENTION:-U0AC2JF0M7D}"
PY="${MIRROR_PY:-/opt/homebrew/bin/python3}"
DEFAULT_LABEL="com.hermes.byz-slack-mbox-inbound"
LABEL="$DEFAULT_LABEL"; CHANNEL="${MIRROR_CHANNEL:-C0C6MJGRR89}"; TO_KEY=""; FROM_SEATS=0; TALK=0
SEATS="${MIRROR_SEATS:-$ROOT/.fable-team/seats-harness.json}"
TOKEN="$HOME/.hermes/secrets/yoonhwan_bot.env"

while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:?--label 값 필요}"; TALK=1; shift 2;;
    --channel) CHANNEL="${2:?--channel 값 필요}"; shift 2;;
    --to-key) TO_KEY="${2:?--to-key 값 필요}"; shift 2;;
    --humans-from-seats) FROM_SEATS=1; shift;;
    *) echo "ERROR: 알 수 없는 인자: $1" >&2; exit 2;;
  esac
done
if [ "$TALK" = 1 ]; then
  [ "$LABEL" != "$DEFAULT_LABEL" ] || { echo "ERROR: --label 은 1번째 인스턴스 라벨($DEFAULT_LABEL)과 달라야 한다" >&2; exit 2; }
  case "$LABEL" in com.hermes.[a-z0-9.-]*) ;; *) echo "ERROR: --label 은 com.hermes.<소문자·숫자·.·-> 꼴: $LABEL" >&2; exit 2;; esac
  case "$CHANNEL" in C[A-Z0-9]*) ;; *) echo "ERROR: --channel 은 슬랙 채널 ID(C…): $CHANNEL" >&2; exit 2;; esac
  case "$TO_KEY" in ''|_|[!_]*|*[!a-z_]*) echo "ERROR: --to-key 는 명부 키(_ 로 시작 · 소문자·밑줄 · 예 _desk): '$TO_KEY'" >&2; exit 2;; esac
  [ "$FROM_SEATS" = 1 ] || { echo "ERROR: 2번째 인스턴스는 --humans-from-seats 필수(허용 사용자 = 명부 _slack_users)" >&2; exit 2; }
  SEATS="${MIRROR_SEATS:-$ROOT/.fable-team/seats-planner.json}"
elif [ -n "$TO_KEY" ] || [ "$FROM_SEATS" = 1 ]; then
  echo "ERROR: --to-key / --humans-from-seats 는 --label 과 함께만 쓴다" >&2; exit 2
fi
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[ -f "$TOKEN" ] || { echo "ERROR: 토큰 파일 없음: $TOKEN" >&2; exit 1; }
[ "$(stat -f %Lp "$TOKEN")" = "600" ] || { echo "ERROR: 토큰 파일 권한이 600 이 아니다" >&2; exit 1; }
[ -x "$PY" ] || { echo "ERROR: python 없음: $PY" >&2; exit 1; }
[ -f "$INBOX_BIN" ] || { echo "ERROR: ft-inbox.sh 없음: $INBOX_BIN" >&2; exit 1; }
[ -f "$MBOX" ] || { echo "ERROR: mbox.sh 없음: $MBOX" >&2; exit 1; }
[ "$TALK" = 1 ] || [ -f "$SEATS" ] || { echo "ERROR: seats 파일 없음: $SEATS" >&2; exit 1; }  # 2번째 인스턴스의 명부는 가동 때 읽는다(설치는 파일만)

mkdir -p "$HOME/.hermes/scripts" "$HOME/.hermes/logs" "$HOME/.hermes/state" "$HOME/Library/LaunchAgents"
for f in byz_slack_mbox_inbound.py mirror_inbound.py mirror_humans.py mirror_plan.py mirror_questions.py mirror_board.py mirror_deliver.py mirror_lib.py mirror_share.py; do
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
chmod +x "$HOME/.hermes/scripts/byz_slack_mbox_inbound.py"

TEMPLATE="$KIT/$DEFAULT_LABEL.plist.template"; [ "$TALK" = 1 ] && TEMPLATE="$KIT/com.hermes.byz-slack-talk-inbound.plist.template"
PY="$PY" HOME_DIR="$HOME" CHANNEL="$CHANNEL" MENTION="$MENTION" MBOX="$MBOX" INBOX_BIN="$INBOX_BIN" SEATS="$SEATS" LABEL="$LABEL" TO_KEY="$TO_KEY" \
  python3 - "$TEMPLATE" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__CHANNEL__", "CHANNEL"), ("__MENTION__", "MENTION"), ("__MBOX__", "MBOX"), ("__INBOX_BIN__", "INBOX_BIN"), ("__SEATS__", "SEATS"), ("__LABEL__", "LABEL"), ("__TO_KEY__", "TO_KEY")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
plutil -lint "$PLIST" >/dev/null

if [ "$TALK" = 1 ]; then
  echo "INSTALLED-NOT-LOADED $LABEL channel=$CHANNEL to_key=$TO_KEY seats=$SEATS plist=$PLIST"
  exit 0
fi
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
echo "installed $LABEL channel=$CHANNEL human=$MENTION mbox=$MBOX seats=$SEATS"
