#!/usr/bin/env bash
# ft-issue-close-check.sh <Issue#> [--from-json <file>] [--repo <dir>]
#   C4 · Issue close 완료 6항 검사 (읽기 전용 — gh issue view 만 부른다 · edit/close/label 0).
#   6항 = 닫는 사건 · PR · 재현 PASS · 정리 · 기록 · 정본 (design/harness/ISSUE-TRANSITIONS.md §3).
#   통과 = ①코멘트 어딘가에 6항 줄이 «값과 함께» 전부 있다 ②Closes 로 연결된 PR 이 있다(closedByPullRequestsReferences).
#   6항 정본 = `정본: <파일>#<절>@<랜딩 sha>`(부분 PR 은 `@S1,S2` · ff 랜딩은 `@T..S`) 또는 `정본 영향 없음: <이유 ≥10자>`.
#     `정본:` 은 S 마다 (가)S 가 랜딩 ref(env FT_LAND_REF · 기본 origin/main)의 조상 (나)S^1..S(T..S 면 그 구간)의 바뀐 파일에 <파일> 포함.
#     fetch 하지 않는다 — S 가 로컬에 없으면 MISS.
#   exit 0 = 통과 · 1 = 미비(사유 stdout) · 2 = usage 또는 조회 실패
#   --from-json = gh 호출 대신 같은 모양의 JSON 파일(시험용 · tests/fixtures/issue_close/).
#   --repo = 정본 sha 를 조회할 git 리포(기본 = 이 스크립트가 있는 리포 루트).
set -uo pipefail
unset GH_TOKEN
N="${1:-}"; shift || true
FROM_JSON=""; REPO=""
while [ $# -gt 0 ]; do case "$1" in --from-json) FROM_JSON="${2:-}"; shift 2;; --repo) REPO="${2:-}"; shift 2;; *) echo "unknown $1" >&2; exit 2;; esac; done
case "$N" in ''|*[!0-9]*) echo "usage: $0 <Issue#> [--from-json <file>] [--repo <dir>]" >&2; exit 2;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$REPO" ] || REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || (cd "$HERE/../.." && pwd))"
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

# 6항 정본 — 줄 모양은 5항과 같다. `정본\s*:` 만 잡으므로 `정본 영향 없음:` 줄은 섞이지 않는다.
canon_lines() { # <키 정규식> → 값 줄들(값 비면·`<…>` 면 제외)
  jq -r --arg k "$1" '.comments[].body | split("\n")[]
    | select(test("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $k + "\\s*[:：]\\s*[^<\\s]"))
    | sub("^\\s*[-*]?\\s*(\\[[ xX]\\]\\s*)?" + $k + "\\s*[:：]\\s*"; "") | sub("\\s+$"; "")' <<<"$JSON"
}
canon_check_sha() { # <파일> <sha 또는 T..S> → 0 통과 · 1 MISS(사유 stdout)
  local X="$1" TOK="$2" S FROM FILES REF="${FT_LAND_REF:-origin/main}"
  case "$TOK" in -*|'') echo "  MISS 6항 정본 — sha 「${TOK}」 형식 오류"; return 1;; esac
  case "$TOK" in *..*) FROM="${TOK%%..*}"; S="${TOK##*..}";; *) S="$TOK"; FROM="$TOK^1";; esac
  if ! git -C "$REPO" cat-file -e "${S}^{commit}" 2>/dev/null; then echo "  MISS 6항 정본 $S — S 없음 — git fetch 후 다시"; return 1; fi
  if ! git -C "$REPO" rev-parse --verify -q "${REF}^{commit}" >/dev/null; then echo "  MISS 6항 정본 $S — 랜딩 ref ${REF} 없음 — git fetch 후 다시"; return 1; fi
  if ! git -C "$REPO" merge-base --is-ancestor "$S" "$REF"; then echo "  MISS 6항 정본 $S — 랜딩 안 됨 (${REF} 의 조상이 아님)"; return 1; fi
  if ! FILES="$(git -C "$REPO" diff --name-only "$FROM" "$S" 2>/dev/null)"; then echo "  MISS 6항 정본 $S — 범위 ${FROM}..${S} 를 못 읽음"; return 1; fi
  if ! grep -Fxq -- "$X" <<<"$FILES"; then echo "  MISS 6항 정본 $S — 랜딩 commit 에 정본 $X 없음 — 로컬에만 고친 것"; return 1; fi
  echo "  OK   6항 정본 $X @ $S"; return 0
}
CANON="$(canon_lines '정본')"
if [ -n "$CANON" ]; then
  while IFS= read -r V; do
    X="${V%%#*}"; REST="${V#*#}"
    if [ "$X" = "$V" ] || [ "${REST#*@}" = "$REST" ]; then echo "  MISS 6항 정본 — 「${V}」 은 <파일>#<절>@<sha> 모양이 아님"; MISS=1; continue; fi
    X="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$X")"; SHAS="${REST##*@}"
    IFS=',' read -ra TOKS <<<"$SHAS"
    for TOK in "${TOKS[@]}"; do
      TOK="$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$TOK")"
      canon_check_sha "$X" "$TOK" || MISS=1
    done
  done <<<"$CANON"
else
  REASON="$(canon_lines '정본 영향 없음' | head -1)"
  RLEN="$(jq -Rn --arg r "$REASON" '$r | length')"   # 글자 수(로케일 무관 — ${#…} 는 C 로케일에서 바이트)
  if [ -z "$REASON" ]; then
    echo "  MISS 6항 정본 — 코멘트에 「정본: <파일>#<절>@<랜딩 sha>」 또는 「정본 영향 없음: <이유>」 줄 없음"; MISS=1
  elif [ "$RLEN" -ge 10 ]; then echo "  OK   6항 정본 영향 없음 (이유 ${RLEN}자)"
  else echo "  MISS 6항 정본 영향 없음 — 이유 ${RLEN}자 (<10자)"; MISS=1; fi
fi

PRS="$(jq -r '[.closedByPullRequestsReferences[]?.number] | map("#"+tostring) | join(" ")' <<<"$JSON")"
if [ -n "$PRS" ]; then echo "  OK   Closes 연결 PR $PRS"; else echo "  MISS Closes 연결 PR 없음 — 랜딩 PR 본문에 「Closes #${N}」 필요"; MISS=1; fi

if [ "$MISS" -eq 0 ]; then echo "PASS #$N 완료 6항 + Closes 연결"; exit 0; fi
echo "FAIL #$N 미비 — 소유 오케에 1통(보완 또는 ft-issue-reopen.sh)"; exit 1
