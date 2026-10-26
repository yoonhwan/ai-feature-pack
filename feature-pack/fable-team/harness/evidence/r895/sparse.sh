#!/usr/bin/env bash
# r895 sparse.sh <worktrees.tsv> <출력 tsv> — 워크트리마다 «sparse 인가» 를 읽는다(읽기 전용 · 삭제 0).
#   판정: `git -C <경로> config --get core.sparseCheckout` = true → sparse · 그 밖 → false · 못 읽음 → 못잼
#   info_file = 그 워크트리 gitdir 의 info/sparse-checkout 실재(있음/없음) · kib 는 worktrees.tsv 값을 그대로 옮긴다
set -uo pipefail
export GIT_OPTIONAL_LOCKS=0
IN="${1:?usage: sparse.sh <worktrees.tsv> <out.tsv>}"; OUT="${2:?usage}"
printf 'path\tsparse\tinfo_file\tkib\n' > "$OUT"
while IFS=$'\t' read -r p b h kib _; do
  [ "$p" = path ] && continue
  [ -d "$p" ] || { printf '%s\t-\t-\t%s\n' "$p" "$kib" >> "$OUT"; continue; }
  s="$(timeout 7 git -C "$p" config --get core.sparseCheckout 2>/dev/null)"
  case "$s" in true) sp=true ;; false|"") sp=false ;; *) sp=못잼 ;; esac
  gd="$(timeout 7 git -C "$p" rev-parse --git-dir 2>/dev/null)"
  [ -n "$gd" ] || gd="$p/.git"
  case "$gd" in /*) ;; *) gd="$p/$gd" ;; esac
  [ -f "$gd/info/sparse-checkout" ] && inf=있음 || inf=없음
  printf '%s\t%s\t%s\t%s\n' "$p" "$sp" "$inf" "$kib" >> "$OUT"
done < "$IN"
echo "OK sparse → $OUT"
