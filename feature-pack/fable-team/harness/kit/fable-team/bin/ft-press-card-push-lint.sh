#!/usr/bin/env bash
# ft-press-card-push-lint.sh --repo <리포> --base <ref> [--base <ref>…]
#   tester press 카드 push 검사(r1129 · 카드 design/harness/indices/진행/r1129-tester-press-card-header-push-lint-same-judge.md).
#   왜: 카드 머리줄은 발사 순간(ft-press-gate ⑥)에만 판정돼, 산문 붙은 «기준선:» 카드가 tester 손에서 처음 막히고 사본으로 우회됐다.
#   대상 = <base>...HEAD 에서 추가·변경(AM)된 design/**/indices/inbox/tester/<이름>.md(README.md·하위 폴더 제외) 중 줄 맨 앞 «기준선:» 이 있는 카드.
#     --base 가 여럿이면 모든 기준에서 바뀐 파일만(병합 유입 제외 · deferral-lint-gate 와 같은 범위).
#   판정 = 카드마다 ft-press-baseline-check.sh --card <카드> --repo <리포>(게이트 ⑥ 과 같은 판정기 · 두 벌 0) · 출력은 판정기 그대로.
#   면제 = 카드 줄 «- press-card-lint: ok <이유>» → 건너뛰고 «면제 <카드> <이유>» 1줄(숨김 0).
#   exit 0 = 통과(대상 0 포함) · 1 = BLOCK 1장 이상 · 2 = 검사 불가(usage·git 실패·판정기 없음·판정기 rc 0/1 밖·시간 넘김). ★침묵 통과 0★
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
JUDGE="${FT_PRESS_BASELINE_CHECK_BIN:-$HERE/ft-press-baseline-check.sh}"
STEP_S="${FT_PRESS_CARD_LINT_STEP_S:-7}"
REPO=""; BASES=()
usage() { echo "usage: $0 --repo <리포> --base <ref> [--base <ref>…]" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 2>/dev/null || usage ;;
    --base) BASES+=("${2:-}"); shift 2 2>/dev/null || usage ;;
    *) usage ;;
  esac
done
[ -n "$REPO" ] && [ "${#BASES[@]}" -gt 0 ] || usage
undecidable() { echo "PRESS-CARD-LINT 검사 불가 — $1"; exit 2; }
[ -f "$JUDGE" ] || undecidable "판정기 없음($JUDGE)"

# 바뀐 tester 카드(모든 기준에서 AM) — 기준마다 git 1회 · 실패 = 검사 불가
CANDS=""; first=1
for b in "${BASES[@]}"; do
  names="$(git -C "$REPO" diff --name-only --diff-filter=AM "$b...HEAD" 2>&1)" || undecidable "git diff $b...HEAD 실패: ${names%%$'\n'*}"
  names="$(printf '%s\n' "$names" | grep -E '^design/(.+/)?indices/inbox/tester/[^/]+\.md$' | grep -v '/README\.md$')"
  if [ "$first" = 1 ]; then CANDS="$names"; first=0
  else CANDS="$(comm -12 <(printf '%s\n' "$CANDS" | sort -u) <(printf '%s\n' "$names" | sort -u))"; fi
done

checked=0; blocked=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  card="$REPO/$rel"
  grep -q '^기준선:' "$card" 2>/dev/null || continue
  ex="$(grep -m1 -E '^- press-card-lint: ok [^[:space:]]' "$card")" && { echo "면제 $rel ${ex#- press-card-lint: ok }"; continue; }
  checked=$((checked + 1))
  out="$(timeout "$STEP_S" bash "$JUDGE" --card "$card" --repo "$REPO" 2>&1)"; rc=$?
  printf '%s\n' "$out"
  case $rc in
    0) ;;
    1) blocked=$((blocked + 1)) ;;
    124) undecidable "판정기가 ${STEP_S}초 안에 끝나지 않음($rel)" ;;
    *) undecidable "판정기 rc=$rc($rel)" ;;
  esac
done <<< "$CANDS"

[ "$checked" -gt 0 ] || { echo "PRESS-CARD-LINT OK 검사 대상 0"; exit 0; }
[ "$blocked" -eq 0 ] && { echo "PRESS-CARD-LINT OK 카드 ${checked}장 통과"; exit 0; }
echo "PRESS-CARD-LINT BLOCK 카드 ${blocked}/${checked}장 —머리줄을 판정기 꼴로 고쳐 다시 push(형식 = ft-press-baseline-check.sh 머리 주석)"
exit 1
