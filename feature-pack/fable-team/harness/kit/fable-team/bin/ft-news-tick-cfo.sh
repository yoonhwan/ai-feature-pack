#!/usr/bin/env bash
# ft-news-tick-cfo.sh — CFO 오케 뉴스 틱 = «큐 비우기 + CFO 좌석 상태 + 미push + ⑥ 골 트리 상시 출력» 한 명령.
# 왜: 오빠 2026-09-27 「루프, 체크뉴스에 트리 상시출력으로 개선」. v65 ft-news-tick.sh 와 같은 이유 —
#     기억으로 지키는 순서는 지켜지지 않는다. 뉴스를 쓰려면 이 명령을 «먼저» 돌려야 값이 나온다.
# 트리 원본 = design/cfo/NEWS-TREE.md (c-level-planning) · 상태는 카드 폴더(design/cfo/indices/{대기,진행,완성})·seats.json 에서
#     ft-news-tree.py 가 읽는다(오케가 손으로 트리를 다시 쓰지 않는다 · [idx:] 없는 줄만 적힌 값).
# 사용: bash ft-news-tick-cfo.sh [ME]   (기본 ME = seats.json 의 FB_CFO#N 최신 · 없으면 FT_ME)
set -u
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
CFO=$ROOT/.worktrees/c-level-planning
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/ft-team-lib.sh"   # R382b: cfo 팀 폴더는 CFO 워크트리의 design/TEAMS.md 폴더 칸으로(리터럴 0)
CFO_DIR="$(ft_team_in "$CFO" cfo)" || { echo "ERROR: cfo 팀 폴더를 못 풀었다($CFO/design/TEAMS.md)" >&2; exit 2; }
ME=${1:-${FT_ME:-$(tmux ls -F '#{session_name}' 2>/dev/null | grep -E '^FB_CFO#[0-9]+$' | sort -t'#' -k2 -n | tail -1)}}
[ -n "$ME" ] || { echo "ERROR: FB_CFO#N tmux 세션이 없다 — 인자나 FT_ME 로 좌석명을 줘라" >&2; exit 2; }
echo "ME=$ME  $(date '+%F %T')"
echo "════ ① 내 큐 ════"
bash "$ROOT/.fable-team/comm/mbox.sh" recv "$ME" --all 2>&1 | grep -vE '^SCANNED' | head -40
echo; echo "════ ② CFO 좌석 (tmux 실재 · 턴 · 큐) ════"
for S in $(tmux ls -F '#{session_name}' 2>/dev/null | grep -E '^(FB_CFO|CFO_HARNESS|CFO_SINBO|ft-v65-temp-sb-harness-0-5-row[0-9]+)' | sort); do
  T=$(bash "$HERE/ft-seat-status.sh" turn "$S" 2>/dev/null | awk '{print $1}')
  Q=$(bash "$ROOT/.fable-team/comm/mbox.sh" peek "$S" 2>/dev/null | grep -oE 'pending=[0-9]+' | head -1)
  printf "%-56s %-8s %s\n" "$S" "${T:-?}" "${Q:-}"
done
echo; echo "════ ③ 미push · 미커밋 ════"
for W in c-level-planning v6-realtime-live; do
  B=$(git -C "$ROOT/.worktrees/$W" rev-parse --abbrev-ref HEAD 2>/dev/null)
  A=$(git -C "$ROOT/.worktrees/$W" rev-list --count "origin/$B..HEAD" 2>/dev/null || echo '?')
  D=$(git -C "$ROOT/.worktrees/$W" status --short 2>/dev/null | wc -l | tr -d ' ')
  printf "%-20s %-28s ahead=%-4s dirty=%s\n" "$W" "$B" "$A" "$D"
done
echo "v65 워크트리=$(ls -d "$ROOT"/.worktrees/v65-* 2>/dev/null | wc -l | tr -d ' ')"
echo; echo "════ ④ 정본 크기 (35KB 한도) ════"
wc -c "$CFO_DIR/VERDICT-DATA-SOVEREIGNTY-20260923.md" | awk '{printf "VERDICT=%sB%s\n",$1,($1>35000?" ★초과 — archive 분리 먼저★":"")}'
echo; echo "════ ⑥ 골 트리 (뉴스에 그대로 · 상태 = 카드 폴더·seats.json) ════"
TREE="${FT_NEWS_TREE:-$CFO_DIR/NEWS-TREE.md}"
if [ -f "$TREE" ]; then python3 "$HERE/ft-news-tree.py" "$TREE" --root "$ROOT" --team-dir "$CFO_DIR"; else echo "ERROR: 트리 원본 없음 — $TREE" >&2; fi
