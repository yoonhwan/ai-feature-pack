#!/usr/bin/env bash
# ft-close-reason-check.sh <Issue#> [--from-json <file>]
#   C23 · close 사유 3종 검사 (SPEC-github-issue-driven §12-4 · 읽기 전용 — gh issue view 만 부른다 · 쓰기 0).
#   코멘트 줄 모양(줄 머리 `-`·`*` 허용):
#     close-사유: 완성
#     close-사유: 교체됨 → #<N>        + 승계: <무엇이 승계되나>        + 확인 seq: <mbox seq>
#     close-사유: 불필요 — <근거>      (또는 별도 줄 근거: <값>)        + 확인 seq: <mbox seq>
#   완성 = 기존 ft-issue-close-check.sh(5항 + Closes PR) 결과를 그대로 인용한다(같은 --from-json 전달).
#   교체됨·불필요 = 매니저 단독 금지 — 소유 오케 확인 seq 코멘트가 없으면 exit 1(매니저 반려 1통).
#   exit 0 = 통과 · 1 = 미비(사유 stdout) · 2 = usage 또는 조회 실패
#   --from-json = gh 호출 대신 같은 모양의 JSON 파일(시험용 · tests/fixtures/issue_close/).
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; shift || true
FROM_JSON=""
while [ $# -gt 0 ]; do case "$1" in --from-json) FROM_JSON="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> [--from-json <file>]" >&2; exit 2;; esac
command -v jq >/dev/null || { echo "jq 필요" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$FROM_JSON" ]; then
  [ -f "$FROM_JSON" ] || { echo "json 없음: $FROM_JSON" >&2; exit 2; }
  JSON="$(cat "$FROM_JSON")"
else
  JSON="$(gh issue view "$N" --json number,state,title,comments,closedByPullRequestsReferences 2>&1)" \
    || { echo "gh issue view $N 실패: $JSON" >&2; exit 2; }
fi
echo "Issue #$N state=$(jq -r '.state' <<<"$JSON") title=$(jq -r '.title' <<<"$JSON")"

# 코멘트 전 줄에서 «값이 있는» 줄만 뽑는다(<...> 자리표시 제외). 첫 일치 줄의 값 반환.
field() { # <키 정규식> → 값(없으면 빈 문자열)
  jq -r --arg k "$1" '[.comments[].body | split("\n")[]
    | select(test("^\\s*[-*]?\\s*" + $k + "\\s*[:：]\\s*[^<\\s]"))
    | sub("^\\s*[-*]?\\s*" + $k + "\\s*[:：]\\s*"; "")] | first // ""' <<<"$JSON"
}

REASON_LINE="$(field 'close-사유')"
if [ -z "$REASON_LINE" ]; then
  echo "MISS 사유 — 코멘트에 「close-사유: 완성|교체됨 → #N|불필요 — <근거>」 줄 없음(3종만)"
  echo "FAIL #$N 사유 미기재 — 소유 오케에 1통"; exit 1
fi

MISS=0
case "$REASON_LINE" in
  완성*)
    echo "사유=완성 → ft-issue-close-check.sh 인용"
    if [ -n "$FROM_JSON" ]; then bash "$HERE/ft-issue-close-check.sh" "$N" --from-json "$FROM_JSON"; exit $?; fi
    bash "$HERE/ft-issue-close-check.sh" "$N"; exit $?;;
  교체됨*)
    echo "사유=교체됨"
    TARGET="$(grep -oE '#[0-9]+' <<<"$REASON_LINE" | head -1)"
    if [ -z "$TARGET" ]; then echo "  MISS 대체 Issue 번호 — 「교체됨 → #N」 필수"; MISS=1
    elif [ "$TARGET" = "#$N" ]; then echo "  MISS 대체 번호가 자기 자신($TARGET)"; MISS=1
    else echo "  OK   대체 $TARGET"; fi
    if [ -n "$(field '승계')" ]; then echo "  OK   승계 줄"; else echo "  MISS 「승계: <무엇이 승계되나>」 줄(회귀 팩 행 승계 포함)"; MISS=1; fi;;
  불필요*)
    echo "사유=불필요"
    GROUND="$(sed -E 's/^불필요[[:space:]]*[—:：-]*[[:space:]]*//' <<<"$REASON_LINE")"
    [ -n "$GROUND" ] || GROUND="$(field '근거')"
    if [ -n "$GROUND" ] && [ "$GROUND" != "$REASON_LINE" ]; then echo "  OK   근거: $GROUND"
    elif [ -n "$(field '근거')" ]; then echo "  OK   근거 줄"
    else echo "  MISS 근거 — 「불필요 — <근거>」 또는 「근거: <값>」 필수"; MISS=1; fi;;
  *)
    echo "MISS 사유 값 「${REASON_LINE}」 은 3종(완성·교체됨·불필요)이 아님"; echo "FAIL #$N 사유 미분류"; exit 1;;
esac

SEQ="$(field '확인 seq')"
case "$SEQ" in
  [0-9]*) echo "  OK   소유 오케 확인 seq $SEQ";;
  *) echo "  MISS 「확인 seq: <mbox seq>」 — 교체·불필요는 매니저 단독 close 금지(소유 오케 확인 1통)"; MISS=1;;
esac

if [ "$MISS" -eq 0 ]; then echo "PASS #$N close 사유 검사"; exit 0; fi
echo "FAIL #$N 미비 — 매니저 반려: reopen 요청 1통(소유 오케 집행)"; exit 1
