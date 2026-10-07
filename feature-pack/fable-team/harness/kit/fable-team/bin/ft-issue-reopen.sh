#!/usr/bin/env bash
# ft-issue-reopen.sh <Issue#> <랜딩sha> [--apply]
#   C4 · 회귀 시 reopen — 원 Issue 를 다시 열고 «깬 랜딩 sha» 를 역링크 코멘트로 남긴다.
#   기본 = dry-run: 실행할 gh 명령만 출력한다(외부 상태 변경 0). --apply 가 있어야 실제로 실행한다.
#   exit 0 = 출력/실행 완료 · 1 = 실행 실패 · 2 = usage 또는 sha 검증 실패
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; SHA="${2:-}"; shift 2 || true
APPLY=0
while [ $# -gt 0 ]; do case "$1" in --apply) APPLY=1; shift;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> <랜딩sha> [--apply]" >&2; exit 2;; esac
[ -n "$SHA" ] || { echo "usage: $0 <Issue#> <랜딩sha> [--apply]" >&2; exit 2; }
FULL="$(git rev-parse --verify --quiet "$SHA^{commit}")" || { echo "sha 검증 실패(이 리포에 없는 커밋): $SHA" >&2; exit 2; }
URL="$(gh repo view --json url -q .url 2>/dev/null)"; [ -n "$URL" ] || { echo "리포 URL 조회 실패" >&2; exit 2; }
SUBJ="$(git log -1 --format=%s "$FULL")"
BODY="[reopen] 회귀 — 깬 랜딩: ${URL}/commit/${FULL} (${SUBJ}). 5항 재작성 후 다시 닫는다(design/harness/ISSUE-TRANSITIONS.md §4)."

CMDS=(
  "gh issue reopen $N"
  "gh issue edit $N --add-label status:needs-review --remove-label status:done"
  "gh issue comment $N --body \"$BODY\""
)
if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN (--apply 없음 · 아무것도 실행하지 않음)"
  printf '  %s\n' "${CMDS[@]}"
  exit 0
fi
gh issue reopen "$N" || exit 1
gh issue edit "$N" --add-label status:needs-review --remove-label status:done || exit 1
gh issue comment "$N" --body "$BODY" || exit 1
echo "REOPENED #$N <- ${FULL:0:10}"
