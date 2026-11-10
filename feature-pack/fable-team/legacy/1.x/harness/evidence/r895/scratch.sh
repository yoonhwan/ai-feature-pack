#!/usr/bin/env bash
# r895 scratch.sh <등록부 tsv> <출력 폴더> — 임시 사본 조사(읽기 전용 · 삭제 0).
#   ⓐ 등록 사본(ft-scratch-repo.sh 등록부 «경로\t주인\t만든 epoch»): 실재·크기KiB·주인 tmux 실재·나이(시간)·cwd 쥔 프로세스
#   ⓑ $TMPDIR 의 repo-*(등록 안 된 것) · tmp.* 수·합계 ⓒ /private/tmp/claude-$UID 세션 스크래치 합계 · 그 안 .git 가진 사본
#   크기 = 항목마다 `du -sk` 상한 FT_R895_DU_S(기본 7초) — 넘으면 «못잼»
set -uo pipefail
REG="${1:?usage: scratch.sh <registry.tsv> <outdir>}"; OUT="${2:?}"; DU_S="${FT_R895_DU_S:-7}"; mkdir -p "$OUT"
NOW="$(date +%s)"; T="${TMPDIR:-/tmp}"; T="${T%/}"
SESS="$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"; TMUX_OK=$?
sz() { local k; k="$(timeout "$DU_S" nice -n 10 du -sk "$1" 2>/dev/null | cut -f1)"; echo "${k:-못잼}"; }
held() { local h; h="$(lsof -t +d "$1" 2>/dev/null | head -3 | tr '\n' ',')"; echo "${h:-없음}"; }
printf 'path\towner\tage_h\texists\tkib\towner_live\tcwd_held\n' > "$OUT/scratch-registered.tsv"
while IFS=$'\t' read -r p o t; do
  [ -n "$p" ] || continue
  age=$(( (NOW - ${t:-$NOW}) / 3600 ))
  if [ "$TMUX_OK" -ne 0 ]; then live="tmux목록실패"; elif printf '%s\n' "$SESS" | grep -qxF -- "$o"; then live=있음; else live=없음; fi
  if [ -d "$p" ]; then printf '%s\t%s\t%s\t있음\t%s\t%s\t%s\n' "$p" "$o" "$age" "$(sz "$p")" "$live" "$(held "$p")"
  else printf '%s\t%s\t%s\t없음\t0\t%s\t-\n' "$p" "$o" "$age" "$live"; fi
done < "$REG" >> "$OUT/scratch-registered.tsv"
printf 'path\tkib\tmtime\tcwd_held\n' > "$OUT/scratch-unregistered.tsv"
for p in "$T"/repo-*; do
  [ -d "$p" ] || continue; grep -qF -- "$p" "$REG" && continue
  printf '%s\t%s\t%s\t%s\n' "$p" "$(sz "$p")" "$(stat -f %Sm -t %FT%T "$p")" "$(held "$p")"
done >> "$OUT/scratch-unregistered.tsv"
{ echo "tmp_dot_count=$(ls -d "$T"/tmp.* 2>/dev/null | wc -l | tr -d ' ')"
  echo "tmp_dot_kib=$(timeout 70 nice -n 10 du -sck "$T"/tmp.* 2>/dev/null | tail -1 | cut -f1)"
  C="/private/tmp/claude-$(id -u)"
  echo "claude_scratch_kib=$(timeout 70 nice -n 10 du -sk "$C" 2>/dev/null | cut -f1)"
  echo "claude_scratch_git_copies=$(find "$C" -maxdepth 5 -name .git 2>/dev/null | wc -l | tr -d ' ')"
  echo "tmux_ok=$TMUX_OK"; } > "$OUT/scratch-summary.txt"
echo "OK scratch → $OUT"
