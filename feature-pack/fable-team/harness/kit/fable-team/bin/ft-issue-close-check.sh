#!/usr/bin/env bash
# ft-issue-close-check.sh <Issue#> [--from-json <file>]
#   C4 · Issue close 완료 5항 검사 (읽기 전용 — gh issue view 만 부른다 · edit/close/label 0).
#   5항 = 닫는 사건 · PR · 재현 PASS · 정리 · 기록 (design/harness/ISSUE-TRANSITIONS.md §3).
#   통과 = ①코멘트 어딘가에 5항 줄이 «값과 함께» 전부 있다 ②Closes 로 연결된 PR 이 있다(closedByPullRequestsReferences).
#   exit 0 = 통과 · 1 = 미비(사유 stdout) · 2 = usage 또는 조회 실패
#   --from-json = gh 호출 대신 같은 모양의 JSON 파일(시험용 · tests/fixtures/issue_close/).
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; shift || true
FROM_JSON=""
while [ $# -gt 0 ]; do case "$1" in --from-json) FROM_JSON="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> [--from-json <file>]" >&2; exit 2;; esac
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }

if [ -n "$FROM_JSON" ]; then
  [ -f "$FROM_JSON" ] || { echo "json 없음: $FROM_JSON" >&2; exit 2; }
  JSON="$(cat "$FROM_JSON")"
else
  JSON="$(gh issue view "$N" --json number,state,title,comments,closedByPullRequestsReferences 2>&1)" \
    || { echo "gh issue view $N 실패: $JSON" >&2; exit 2; }
fi

STATE="$(jq -r '.state' <<<"$JSON")"
echo "Issue #$N state=$STATE title=$(jq -r '.title' <<<"$JSON")"

MISS=0
for ITEM in "닫는 사건" "PR" "재현 PASS" "정리" "기록"; do
  # 줄 모양: [- ][[x] ]<항목>: <값>  (값은 비어 있지 않고 <...> 자리표시가 아님)
  HIT="$(jq -r --arg item "$ITEM" '[.comments[].body | split("\n")[]
    | select(test("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $item + "\\s*[:：]\\s*[^<\\s]"))] | length' <<<"$JSON")"
  if [ "${HIT:-0}" -ge 1 ]; then echo "  OK   5항 $ITEM"; else echo "  MISS 5항 $ITEM — 코멘트에 「${ITEM}: <값>」 줄 없음"; MISS=1; fi
done

PRS="$(jq -r '[.closedByPullRequestsReferences[]?.number] | map("#"+tostring) | join(" ")' <<<"$JSON")"
if [ -n "$PRS" ]; then echo "  OK   Closes 연결 PR $PRS"; else echo "  MISS Closes 연결 PR 없음 — 랜딩 PR 본문에 「Closes #${N}」 필요"; MISS=1; fi

if [ "$MISS" -eq 0 ]; then echo "PASS #$N 완료 5항 + Closes 연결"; exit 0; fi
echo "FAIL #$N 미비 — 소유 오케에 1통(보완 또는 ft-issue-reopen.sh)"; exit 1
