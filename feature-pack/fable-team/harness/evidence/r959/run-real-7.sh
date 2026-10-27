#!/usr/bin/env bash
# r959 실사건 대조 — 막힌 카드 7장에 정본 게이트를 직접 돌린다(쓰기 0 · 읽기만).
#   BIN=고칠 판 또는 옛 판(origin/main) · 결과만 stdout. 인자: <bin 폴더>
set -uo pipefail
BIN="${1:?bin 폴더}"
HO=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/harness-ops
DAF="$HO/design/harness/VERDICT-bulk-close-landed-20261026.md"
WT="$(git -C "$HO" rev-parse --show-toplevel)"
export FT_HARNESS_ROOT=/Users/yoonhwan/Project/ai-feature-pack/.worktrees/r959-index-move-mv-fail-reason-and-lande/feature-pack/fable-team/harness
for pair in '§32 r462-approve-merge-equiv-head-with-main-merge-only' \
            '§56 r560-approval-equiv-main-moves-and-hook-candidates' \
            '§116 r737-news-map-canon-sha-change-trigger' \
            '§120 r756-desk-planner-seat-on-main-based-worktree' \
            '§128 r847-news-ledger-fetch-lsremote-30s' \
            '§135 r888-nano-close-research-seat-evidence-exempt-card-origin-main' \
            '§142 r911-finished-branch-archive-file-content-equal-main'; do
  SEC="${pair%% *}"; STEM="${pair##* }"
  CARD="$HO/design/harness/indices/진행/$STEM.md"
  [ -f "$CARD" ] || { echo "$SEC $STEM :: 카드 없음"; continue; }
  body="$(awk -v s="$SEC" 'index($0,"## ")==1{f=0; r=$0; while((i=index(r,s))>0){n=substr(r,i+length(s),1); if(index(s,"§")==0||n!~/[0-9]/){f=1;break}; r=substr(r,i+length(s))} if(f){print;next}} f' "$DAF")"
  SHA="$(printf '%s\n' "$body" | grep -oE '닫힘 — '"$STEM"' — main(\(팩\))? `[0-9a-f]{40}`' | head -1 | grep -oE '[0-9a-f]{40}')"
  MARK="$(printf '%s\n' "$body" | grep -oE '닫힘 — '"$STEM"' — main(\(팩\))?')"
  OUT="$(printf '%s\n' "$body" | bash "$BIN/ft-index-move-canon.sh" "$CARD" "$WT" "$SHA" 2>&1)"
  printf '%s %s :: %s :: %s\n' "$SEC" "$STEM" "$MARK" "$(printf '%s' "$OUT" | head -1)"
done
