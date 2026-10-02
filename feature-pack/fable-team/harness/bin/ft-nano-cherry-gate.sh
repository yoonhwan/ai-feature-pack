#!/usr/bin/env bash
# ft-nano-cherry-gate.sh <feat 브랜치> <nano 브랜치> [--repo <dir>]
#   ft-nano-close.sh 의 «산출물이 들어왔는가» 게이트 (G4 · 골좌표 M7 — 나노 브랜치에만 남은 커밋은 feat push 가 따라오지 않는다).
#   `git cherry <feat> <nano>` 의 «+»(feat 에 같은 patch 가 없는 커밋) 가 있으면 목록 출력 + exit 1. 없으면 `OK` 한 줄 + exit 0.
#   exit 0 = 통과 · 1 = REJECT(+ 있음 / ref 없음 / git 실패 — 전부 사유 stdout) · 2 = usage. ★침묵 통과 0★ — 어느 경로든 한 줄 이상 출력한다.
set -uo pipefail
FEAT="${1:-}"; NANO="${2:-}"; shift 2 2>/dev/null || { echo "usage: $0 <feat-branch> <nano-branch> [--repo <dir>]" >&2; exit 2; }
REPO="."; [ "${1:-}" = "--repo" ] && REPO="${2:-.}"
for r in "$FEAT" "$NANO"; do
  git -C "$REPO" rev-parse --verify -q "refs/heads/$r" >/dev/null || { echo "REJECT cherry 게이트 — 브랜치 없음: $r (refs/heads/)"; exit 1; }
done
out="$(git -C "$REPO" cherry "$FEAT" "$NANO" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] || { echo "REJECT cherry 게이트 — git cherry 실패(rc=$rc): ${out:0:120}"; exit 1; }
plus="$(printf '%s\n' "$out" | grep '^+' || true)"
n="$(printf '%s' "$plus" | grep -c . || true)"
if [ "$n" -gt 0 ]; then
  echo "REJECT cherry 게이트 — $NANO 에 $FEAT 로 안 들어온 커밋 ${n}개 (git cherry '+'):"
  printf '%s\n' "$plus" | head -20 | while read -r _ sha; do git -C "$REPO" log -1 --format='  + %h %s' "$sha" | cut -c1-120; done
  [ "$n" -le 20 ] || echo "  … 외 $((n - 20))개"
  echo "  → cherry-pick -x 로 $FEAT 에 반영하거나 폐기 사유를 값으로 적은 뒤 닫는다"
  exit 1
fi
echo "OK cherry 게이트 — $NANO 의 모든 커밋이 $FEAT 에 patch 단위로 존재(+ 0)"
exit 0
