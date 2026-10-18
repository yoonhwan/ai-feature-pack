#!/usr/bin/env bash
# ft-proposal-inbox.sh [--apply] — 오빠가 답을 달았는데 아직 답 안 한 제안 Issue 를 찾는다 (R77 r1 · 판정 826)
#   열린 `proposal` Issue 중 마지막 코멘트 작성자가 Tank(byz-tank) 가 아닌 것을 `#M · 작성자 · 시각 · 첫 줄` 로 낸다.
#   --apply 면 아직 `needs-reply` 가 없는 그 Issue 에 Tank `label --add needs-reply` — 이 라벨이 있으면 승인(approve·게이트)이 막힌다.
# 시험용: FT_TANK_CMD · FT_GH_READ · GH_REPO · FT_TANK_LOGIN
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
APPLY=0; for a in "$@"; do case "$a" in --apply) APPLY=1;; *) echo "usage: $0 [--apply]" >&2; exit 2;; esac; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; LIB="$HERE/proposal_issue_lib.py"
if [ -n "${FT_TANK_CMD:-}" ]; then read -ra TANK <<<"$FT_TANK_CMD"; else TANK=(bash "$HERE/../fable-team/bin/ft-gh-as-tank.sh"); fi
ROWS="$(python3 "$LIB" inbox --repo "${GH_REPO:-SecondWindStudio/byz-agents}" --tank "${FT_TANK_LOGIN:-byz-tank}")" || die "조회 실패: $ROWS"
n=0
while IFS=$'\t' read -r num who at first has; do
  [ -n "$num" ] || continue; n=$((n+1))
  echo "#$num · $who · $at · $first$([ "$has" = yes ] && echo ' [needs-reply 있음]')"
  if [ "$APPLY" = 1 ] && [ "$has" = no ]; then "${TANK[@]}" label "$num" --add needs-reply --apply >/dev/null || die "#$num needs-reply 라벨 실패"; fi
done <<<"$ROWS"
echo "답 안 한 제안 Issue ${n}건"
