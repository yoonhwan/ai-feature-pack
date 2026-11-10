#!/bin/bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.0).★
# ft-tick-install.sh — Seatbelt 0.4 통합 틱을 launchd 에 설치/제거 (KeepAlive 가 생존을 맡는다)
#   설치:  ft-tick-install.sh [--worktree DIR] [--script PATH] [--dry-run]
#          → ft-tick.plist 템플릿의 __WORKTREE__/__SCRIPT__ 치환 → ~/Library/LaunchAgents/com.byz.ft-tick.plist
#          → plutil -lint → launchctl bootstrap gui/$UID → launchctl print 로 state 출력
#   제거:  ft-tick-install.sh --uninstall   → launchctl bootout gui/$UID/com.byz.ft-tick + plist 삭제
#   ★기존 ft-pm-tick.sh / ft-master-tick.sh 프로세스는 건드리지 않는다★ — 전환(구 데몬 정지)은 사람이
#   SEATBELT-README §4-2 절차대로 한다. 설치 직후엔 틱이 2중으로 갈 수 있다(그래서 실전은 master 소관).
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LABEL="com.byz.ft-tick"
PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
TEMPLATE="$HERE/ft-tick.plist"
DOMAIN="gui/$(id -u)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; SCRIPT=""; DRY=0; UNINSTALL=0
while [ $# -gt 0 ]; do case "$1" in
  --worktree) WT="$2"; shift 2;; --script) SCRIPT="$2"; shift 2;; --dry-run) DRY=1; shift;; --uninstall) UNINSTALL=1; shift;;
  *) echo "usage: $0 [--worktree DIR] [--script PATH] [--dry-run] | --uninstall" >&2; exit 2;; esac; done

if [ "$UNINSTALL" = 1 ]; then
  if [ "$DRY" = 1 ]; then echo "PLAN launchctl bootout $DOMAIN/$LABEL && rm -f $PLIST_DST"; exit 0; fi
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null && echo "bootout $LABEL OK" || echo "bootout $LABEL — not loaded (무시)"
  rm -f "$PLIST_DST"; echo "removed $PLIST_DST"; exit 0
fi

# 런타임 자리(.fable-team/bin, gitignore)가 있으면 그것, 없으면 추적 사본(scripts/fable-team-bin).
if [ -z "$SCRIPT" ]; then
  if [ -f "$WT/.fable-team/bin/ft-tick.sh" ]; then SCRIPT="$WT/.fable-team/bin/ft-tick.sh"; else SCRIPT="$WT/scripts/fable-team-bin/ft-tick.sh"; fi
fi
[ -f "$TEMPLATE" ] || { echo "REJECT 템플릿 없음: $TEMPLATE"; exit 1; }
[ -f "$SCRIPT" ]   || { echo "REJECT ft-tick.sh 없음: $SCRIPT"; exit 1; }
[ -d "$WT" ]       || { echo "REJECT 워크트리 없음: $WT"; exit 1; }
[ -x /opt/homebrew/bin/bash ] || { echo "REJECT /opt/homebrew/bin/bash 없음 (plist ProgramArguments)"; exit 1; }

render() { sed -e "s|__WORKTREE__|$WT|g" -e "s|__SCRIPT__|$SCRIPT|g" "$TEMPLATE"; }
if [ "$DRY" = 1 ]; then
  TMP="$(mktemp /tmp/ft-tick-plist.XXXXXX)"; render > "$TMP"
  plutil -lint "$TMP" >/dev/null && echo "PLAN plist lint OK · script=$SCRIPT · cwd=$WT · dst=$PLIST_DST · bootstrap $DOMAIN" || { echo "REJECT 렌더된 plist lint 실패: $TMP"; exit 1; }
  rm -f "$TMP"; exit 0
fi

mkdir -p "$(dirname "$PLIST_DST")"
render > "$PLIST_DST"
plutil -lint "$PLIST_DST" || { echo "REJECT plist lint 실패: $PLIST_DST"; exit 1; }
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true          # 재설치 허용(이미 떠 있으면 내렸다 올린다)
launchctl bootstrap "$DOMAIN" "$PLIST_DST" || { echo "REJECT bootstrap 실패 — launchctl print $DOMAIN/$LABEL 로 확인"; exit 1; }
sleep 1
launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E '^\s*(state|pid) ' || echo "WARN launchctl print 에 state/pid 없음"
echo "installed $LABEL → $PLIST_DST (log /tmp/ft-tick.log). ★구 데몬(ft-pm-tick/ft-master-tick)은 그대로다 — README §4-2 전환 절차★"
