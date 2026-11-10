#!/usr/bin/env bash
# r895 measure.sh <리포> <출력 폴더> — 디스크 조사(읽기 전용 · 삭제·repack·gc·prune·mv 0).
#   산출: <출력>/<이름>-git.txt(count-objects·pack·잔재) · <이름>-worktrees.tsv(경로·가지·HEAD·크기KiB·tmux 주인·착지·미커밋)
#         <이름>-branches.txt(가지 수·nano/* 수·refs/archive 수) · <이름>-dup.tsv(같은 HEAD 사본 묶음)
#   부하: nice 10 · 크기 = 워크트리마다 `du -sk` 상한 FT_R895_DU_S(기본 7초 · 하드 룰 12) — 넘으면 크기 칸 «못잼»
#   착지 = `git merge-base --is-ancestor <HEAD> <기준>`(기준 = origin/main · 없으면 main) · 상한 7초 · 넘으면 «못잼»
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0   # git status 가 index 를 다시 쓰지 않게(읽기 전용)
REPO="${1:?usage: measure.sh <repo> <outdir>}"; OUT="${2:?usage: measure.sh <repo> <outdir>}"
DU_S="${FT_R895_DU_S:-7}"; GIT_S=7
NAME="$(basename "$REPO")"; mkdir -p "$OUT"
g() { timeout "$GIT_S" nice -n 10 git -C "$REPO" "$@"; }
BASE=origin/main; g rev-parse -q --verify "$BASE" >/dev/null || BASE=main

{ echo "# $REPO  (base=$BASE)"; echo "## du .git"; timeout 70 nice -n 10 du -sk "$REPO/.git" 2>/dev/null || echo "못잼(70초)"
  echo "## count-objects -vH"; g count-objects -vH 2>&1
  echo "## pack 파일 수"; ls "$REPO/.git/objects/pack/"*.pack 2>/dev/null | wc -l | tr -d ' '
  echo "## 잔재(tmp_pack·tmp_obj) — 크기KiB·수정시각·쥔 프로세스"
  find "$REPO/.git/objects" -maxdepth 2 -name 'tmp_*' 2>/dev/null | while read -r f; do
    held="$(lsof -t "$f" 2>/dev/null | tr '\n' ',')"
    printf '%s\t%s\t%s\t%s\n' "$f" "$(du -sk "$f" | cut -f1)" "$(stat -f %Sm -t %FT%T "$f")" "${held:-없음}"
  done; } > "$OUT/$NAME-git.txt"

{ echo "heads=$(g for-each-ref --format=x refs/heads | wc -l | tr -d ' ')"
  echo "nano=$(g for-each-ref --format=x refs/heads/nano | wc -l | tr -d ' ')"
  echo "archive=$(g for-each-ref --format=x refs/archive | wc -l | tr -d ' ')"
  echo "worktree_list=$(g worktree list --porcelain | grep -c '^worktree ')"
  echo "worktrees_dirs=$(ls -d "$REPO/.worktrees/"*/ 2>/dev/null | wc -l | tr -d ' ')"; } > "$OUT/$NAME-branches.txt"

SESS="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"; TMUX_OK=$?
printf 'path\tbranch\thead\tkib\tseat_live\tlanded\tdirty\n' > "$OUT/$NAME-worktrees.tsv"
g worktree list --porcelain | awk '/^worktree /{p=substr($0,10)} /^HEAD /{h=$2} /^branch /{b=$2} /^detached/{b="(detached)"} /^$/{print p"\t"b"\t"h; b=""}' |
while IFS=$'\t' read -r p b h; do
  [ "$p" = "$REPO" ] && continue
  [ -d "$p" ] || { printf '%s\t%s\t%s\t없음(prunable)\t-\t-\t-\n' "$p" "${b#refs/heads/}" "${h:0:10}" >> "$OUT/$NAME-worktrees.tsv"; continue; }
  kib="$(timeout "$DU_S" nice -n 10 du -sk "$p" 2>/dev/null | cut -f1)"; [ -n "$kib" ] || kib="못잼"
  key="$(basename "$p")"; key="${key#v65-}"; key="${key#*-}"
  if [ "$TMUX_OK" -ne 0 ]; then live="tmux목록실패"; elif printf '%s\n' "$SESS" | grep -qF -- "$key"; then live="$(printf '%s\n' "$SESS" | grep -F -- "$key" | head -1)"; else live="없음"; fi
  if timeout "$GIT_S" git -C "$REPO" merge-base --is-ancestor "$h" "$BASE" 2>/dev/null; then land=조상; else rc=$?; [ "$rc" = 124 ] && land=못잼 || land=아님; fi
  d="$(timeout "$GIT_S" git -C "$p" status --porcelain -uno 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$p" "${b#refs/heads/}" "${h:0:10}" "$kib" "$live" "$land" "$d" >> "$OUT/$NAME-worktrees.tsv"
done

# 중복 생성: 같은 HEAD 를 가진 워크트리 2개 이상 묶음
awk -F'\t' 'NR>1 && $3!="" {n[$3]++; l[$3]=l[$3]" "$1} END{for(k in n) if(n[k]>1) print k"\t"n[k]"\t"l[k]}' "$OUT/$NAME-worktrees.tsv" | sort -t$'\t' -k2,2nr > "$OUT/$NAME-dup.tsv"
echo "OK $NAME → $OUT"
