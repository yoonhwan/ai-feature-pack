#!/usr/bin/env bash
# install-magazine.sh — 아침 매거진 모듈·plist 를 설치한다. 멱등. launchctl 은 --load 를 줄 때만 부른다.
# 사용: BYZ_ROOT=<리포 루트> bash install-magazine.sh [--load]
#   (--load 없음) ~/.hermes/scripts 복사(+.bak) · ~/Library/LaunchAgents plist 치환 + plutil -lint · ops/magazine 워크트리(없을 때만) — launchctl 0
#   --load        위에 더해 bootout → bootstrap 하고 state/next 를 출력한다 (금지선: 수동 1회 OK + planner 보고 뒤에만)
# 재적재 절차(plist 를 바꿨을 때):
#   launchctl bootout gui/$UID/com.byz.ft-magazine; launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.byz.ft-magazine.plist
#   launchctl print gui/$UID/com.byz.ft-magazine | grep -E 'state|next'
# 모듈만 바꿨다면 cp 만으로 다음 08:00 에 반영된다(장기 루프 아님 — 재적재 불필요).
# 예약 실행은 push 켬(ops/magazine 만 · 판정 348). 수동 시험은 CLI 에 --no-push.
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${BYZ_ROOT:?BYZ_ROOT 필요 — .fable-team 이 있는 리포 루트}"
CHANNEL="${MAGAZINE_CHANNEL:-C0C6MJGRR89}"
REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
PY="${MAGAZINE_PY:-/opt/homebrew/bin/python3}"
WT="${MAGAZINE_WORKTREE:-$ROOT/.worktrees/ops-magazine}"
LABEL="com.byz.ft-magazine"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOAD=0; [ "${1:-}" = "--load" ] && LOAD=1

REQUIRED="byz_morning_magazine.py magazine_emit.py magazine_render.py magazine_summary.py magazine_slack.py magazine_publish.py magazine_pdf.py magazine_git.py
  magazine_window.py magazine_collect.py magazine_collect_git.py magazine_collect_gh.py magazine_collect_mbox.py byz_proposal_publish.py
  magazine_render_full.py magazine_attach.py magazine_reattach.py magazine_cli_args.py"
# 풀 디테일 세트의 다른 나노 산출(수집 detail · eli5 HTML) — 통합 전 브랜치에는 없을 수 있어 «있으면 복사 · 없으면 WARN»(조용한 건너뛰기 아님).
# 통합(cherry-pick) 뒤 설치할 때는 WARN 이 0 이어야 한다. 없는 채로 돌면 실행 때 ImportError/「쉬운 판 못 만들었어요」 로 보인다.
COMPANION="magazine_collect_detail.py magazine_collect_decisions.py magazine_eli5.py magazine_eli5_batches.py magazine_eli5_template.html
  proposal_eli5.py proposal_eli5_template.html proposal_state.py proposal_files.py"

[ -x "$PY" ] || { echo "ERROR: python 없음: $PY" >&2; exit 1; }
for f in $REQUIRED; do [ -f "$KIT/$f" ] || { echo "ERROR: 키트 파일 없음: $f" >&2; exit 1; }; done

mkdir -p "$HOME/.hermes/scripts" "$HOME/.hermes/logs" "$HOME/.hermes/state" "$HOME/.hermes/magazine" "$HOME/Library/LaunchAgents"
for f in $REQUIRED; do
  [ -f "$KIT/$f" ] || continue
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
for f in $COMPANION; do
  if [ ! -f "$KIT/$f" ]; then echo "WARN: 키트에 없음(통합 전?): $f" >&2; continue; fi
  [ -f "$HOME/.hermes/scripts/$f" ] && cp -p "$HOME/.hermes/scripts/$f" "$HOME/.hermes/scripts/$f.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$KIT/$f" "$HOME/.hermes/scripts/$f"
done
chmod +x "$HOME/.hermes/scripts/byz_morning_magazine.py"

PY="$PY" HOME_DIR="$HOME" BYZ_ROOT_V="$ROOT" REPO="$REPO" CHANNEL="$CHANNEL" \
  python3 - "$KIT/$LABEL.plist.template" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__BYZ_ROOT__", "BYZ_ROOT_V"), ("__REPO__", "REPO"), ("__CHANNEL__", "CHANNEL")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
plutil -lint "$PLIST" >/dev/null

# ops/magazine 전용 워크트리 — 없을 때만 만든다(있으면 그대로 · rebase/merge 0). main 체크아웃 0.
if [ -e "$WT/.git" ]; then
  echo "worktree 있음: $WT (그대로)"
elif git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" worktree add -b ops/magazine "$WT" origin/main
else
  echo "WARN: $ROOT 가 git 리포가 아님 — ops/magazine 워크트리 생성 건너뜀" >&2
fi

if [ "$LOAD" = 1 ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|next' || true
fi
echo "installed $LABEL plist=$PLIST load=$LOAD worktree=$WT"
