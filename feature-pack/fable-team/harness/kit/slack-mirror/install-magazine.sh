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
# 예약 2종(R184): com.byz.ft-magazine = 08:00 오빠 확인판 발행(magazine_from_news.sh --publish → magazine_doc.py · 판정 1424) ·
#   com.byz.ft-magazine-model = 08:00 시트 이야기 모델만(--emit-model · 게시 0).
# ★--load 는 예약이 launchd 에서 disabled 면 «켜지 않고» ERROR + rc 1 — 몰래 enable 하지 않는다(켜는 건 사람/master).★
# ★내림 기록 규칙★ 하네스가 com.byz.* 예약을 내릴 때(launchctl disable)는 같은 턴에 `.fable-team/state/launchd-disabled/<Label>.md` 를 쓴다 —
#   사유 · 판정(오빠 값 번호) · 다시 올릴 조건 · 누가(좌석). 기록이 있으면 틱은 «내림 중(사유)» 1줄, 없으면 harness master 에 [급] 1통(하루 1회).
#   다시 올리면(enable) 기록 파일도 지운다. 기대 예약표 = `.fable-team/state/launchd-expected.txt`(한 줄 한 Label).
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)"
ROOT="${BYZ_ROOT:?BYZ_ROOT 필요 — .fable-team 이 있는 리포 루트}"
CHANNEL="${MAGAZINE_CHANNEL:-C0C6MJGRR89}"
REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
PY="${MAGAZINE_PY:-/opt/homebrew/bin/python3}"
WT="${MAGAZINE_WORKTREE:-$ROOT/.worktrees/ops-magazine}"
LABELS="com.byz.ft-magazine com.byz.ft-magazine-model"
LOAD=0; [ "${1:-}" = "--load" ] && LOAD=1

REQUIRED="byz_morning_magazine.py magazine_emit.py magazine_render.py magazine_summary.py magazine_slack.py magazine_publish.py magazine_pdf.py magazine_git.py
  magazine_window.py magazine_collect.py magazine_collect_open.py magazine_collect_git.py magazine_collect_gh.py magazine_collect_mbox.py byz_proposal_publish.py
  magazine_render_full.py magazine_render_cap.py magazine_card_shape.py magazine_attach.py magazine_reattach.py magazine_cli_args.py
  magazine_eli5_decisions.py magazine_indexless.py magazine_eli5_pdf.py magazine_run_emit.py
  resume_block.py thread_ledger.py thread_card.py thread_unit.py thread_post_args.py thread_post_update.py thread_reply_slack.py post_guard.py byz_thread_post.py magazine_block.py
  mirror_share.py mirror_lib.py file_guard.py mirror_summary.py proposal_text.py
  magazine_doc.py magazine_goal.py magazine_doc_md.py magazine_doc_three.py magazine_date_guard.py magazine_hermes.py magazine_swiss_template.html magazine_from_news.sh
  magazine_brief.py magazine_brief_rows.py magazine_brief_diff.py magazine_brief_html.py magazine_guide_check.py"
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
chmod +x "$HOME/.hermes/scripts/byz_morning_magazine.py" "$HOME/.hermes/scripts/magazine_from_news.sh"

for LABEL in $LABELS; do
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  PY="$PY" HOME_DIR="$HOME" BYZ_ROOT_V="$ROOT" REPO="$REPO" CHANNEL="$CHANNEL" \
    python3 - "$KIT/$LABEL.plist.template" "$PLIST" <<'PYEOF'
import os, sys
t = open(sys.argv[1], encoding="utf-8").read()
for k, env in (("__PY__", "PY"), ("__HOME__", "HOME_DIR"), ("__BYZ_ROOT__", "BYZ_ROOT_V"), ("__REPO__", "REPO"), ("__CHANNEL__", "CHANNEL")):
    t = t.replace(k, os.environ[env])
open(sys.argv[2], "w", encoding="utf-8").write(t)
PYEOF
  plutil -lint "$PLIST" >/dev/null
done

# ops/magazine 전용 워크트리 — 없을 때만 만든다(있으면 그대로 · rebase/merge 0). main 체크아웃 0.
if [ -e "$WT/.git" ]; then
  echo "worktree 있음: $WT (그대로)"
elif git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" worktree add -b ops/magazine "$WT" origin/main
else
  echo "WARN: $ROOT 가 git 리포가 아님 — ops/magazine 워크트리 생성 건너뜀" >&2
fi

if [ "$LOAD" = 1 ]; then
  DISABLED="$(launchctl print-disabled "gui/$(id -u)")" || { echo "ERROR launchctl print-disabled 실패 — 예약 상태를 못 읽어 적재 중단" >&2; exit 1; }
  for LABEL in $LABELS; do
    if printf '%s\n' "$DISABLED" | grep -Eq "\"$LABEL\"[[:space:]]*=>[[:space:]]*(disabled|true)"; then
      REC="$ROOT/.fable-team/state/launchd-disabled/$LABEL.md"; [ -f "$REC" ] || REC="없음"
      echo "ERROR 예약이 꺼져 있음(disabled): $LABEL — 내림 기록: $REC · 켜지 않았다(켜는 건 사람/master: launchctl enable gui/$(id -u)/$LABEL)" >&2
      exit 1
    fi
  done
  for LABEL in $LABELS; do
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist"
    launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|next' || true
  done
fi
echo "installed $LABELS load=$LOAD worktree=$WT"
