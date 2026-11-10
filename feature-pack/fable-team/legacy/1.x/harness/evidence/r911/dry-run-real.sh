#!/usr/bin/env bash
# dry-run-real.sh — 실 리포 표본 dry-run: 같은 가지에 «옛 판정기(origin/main)» 와 «새 판정기(r911 E1f)» 를 돌려 판정을 나란히 낸다.
#   읽기 전용(삭제·이동 0) · FT_R911_N 기본 12 · 동시 6 · 대상 = refs/heads/nano/* 최신순(wt-sweep 이 보는 순서와 같다)
set -uo pipefail
R="${R:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents}"; OLD="${OLD:?옛 판정기 경로}"; NEW="${NEW:?새 판정기 경로}"; N="${FT_R911_N:-12}"
mapfile -t BRS < <(git -C "$R" for-each-ref --sort=-committerdate --count="$N" --format='%(refname:short)' 'refs/heads/nano/' 2>/dev/null || git -C "$R" for-each-ref --sort=-committerdate --count="$N" --format='%(refname:short)' 'refs/heads/nano/')
one() { bash "$2" "$1" --repo "$R" 2>&1; }
for b in "${BRS[@]}"; do
  ( one "$b" "$OLD" > "/tmp/r911o.$$.${b//\//_}" ) & ( one "$b" "$NEW" > "/tmp/r911n.$$.${b//\//_}" ) &
  while [ "$(jobs -rp | wc -l)" -ge 6 ]; do sleep 0.2; done
done
wait
printf '| # | 가지 | 옛 판 | 새 판 | E1f 근거 |\n|---|---|---|---|---|\n'
i=0; for b in "${BRS[@]}"; do i=$((i+1)); f="${b//\//_}"
  o="$(head -1 "/tmp/r911o.$$.$f" 2>/dev/null)"; n="$(head -1 "/tmp/r911n.$$.$f" 2>/dev/null)"
  e="$(sed -n 's/^E1f //p' "/tmp/r911n.$$.$f" 2>/dev/null | head -1)"; a="$(sed -n 's/.*ahead=\([0-9]*\).*/\1/p' "/tmp/r911n.$$.$f" | head -1)"
  printf '| %d | `%s` | %s | %s | %s (ahead=%s) |\n' "$i" "$b" "${o:-?}" "${n:-?}" "${e:-?}" "${a:-?}"; rm -f "/tmp/r911o.$$.$f" "/tmp/r911n.$$.$f"; done
