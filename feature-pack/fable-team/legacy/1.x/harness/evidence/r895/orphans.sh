#!/usr/bin/env bash
# r895 orphans.sh <목록 파일> <출력 tsv> — `.worktrees/` 안에 있지만 `git worktree list` 에 없는 폴더(등록 밖) 조사 · 읽기 전용.
#   칸: 경로 · 크기KiB(du 상한 7초 · 넘으면 못잼) · .git 종류(file=옛 워크트리 꼬리표 · dir=통째 복제 · 없음) · 수정시각 · cwd 쥔 프로세스
set -uo pipefail
IN="${1:?usage}"; OUT="${2:?usage}"
printf 'path\tkib\tgit\tmtime\tcwd_held\n' > "$OUT"
while read -r p; do
  [ -n "$p" ] || continue
  k="$(timeout 7 nice -n 10 du -sk "$p" 2>/dev/null | cut -f1)"; [ -n "$k" ] || k=못잼
  if [ -f "$p/.git" ]; then t=file; elif [ -d "$p/.git" ]; then t=dir; else t=없음; fi
  h="$(lsof -t +d "$p" 2>/dev/null | head -3 | tr '\n' ',')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$k" "$t" "$(stat -f %Sm -t %FT%T "$p")" "${h:-없음}" >> "$OUT"
done < "$IN"
echo "OK orphans → $OUT"
