#!/usr/bin/env bash
# ft-regress-reopen.sh <Issue#> <깬 sha> [--found gate|live|baseline] [--live] [--apply] [--ledger <파일>]
#   C22 · 회귀 재오픈 절차 (SPEC-github-issue-driven §12-3). 새 Issue 0 — 원 Issue 를 다시 열고 «깬 랜딩» 을 역링크한다.
#   기본 = dry-run: 실행할 gh 명령·코멘트·안내만 출력(외부 상태 변경 0). --apply 가 있어야 gh 쓰기를 실행한다.
#   역링크 = LANDING-LEDGER 에서 «결과 sha» 열이 깬 sha 와 맞는 행(카드·Issue·행 번호). 행이 없으면 exit 2(은폐 0).
#   --live = 라이브 깨짐: 큐 `즉시` 행 요청 문구도 출력(큐에 쓰는 것은 planner — 이 스크립트는 문구만).
#   revert 는 «안내만» — 실행 0. 소유 오케가 손으로 `git revert` 새 커밋을 만들고 그 후보도 랜딩 ④~⑥ 전부를 거친다(면제 0).
#   exit 0 = 출력/실행 완료 · 1 = gh 실행 실패 · 2 = usage · sha 검증 실패 · LEDGER 행 없음
set -uo pipefail
unset GH_TOKEN
USAGE="usage: $0 <Issue#> <깬 sha> [--found gate|live|baseline] [--live] [--apply] [--ledger <파일>]"
N="${1:-}"; SHA="${2:-}"; shift 2 || true
APPLY=0; LIVE=0; FOUND=""; LEDGER="design/harness/LANDING-LEDGER.md"
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=1; shift;;
  --live) LIVE=1; shift;;
  --found) FOUND="${2:-}"; shift 2;;
  --ledger) LEDGER="${2:-}"; shift 2;;
  *) echo "unknown $1" >&2; exit 2;;
esac; done
case "$N" in ''|*[!0-9]*) echo "$USAGE" >&2; exit 2;; esac
[ -n "$SHA" ] || { echo "$USAGE" >&2; exit 2; }
[ -z "$FOUND" ] && { [ "$LIVE" -eq 1 ] && FOUND=live || FOUND=gate; }
case "$FOUND" in gate|live|baseline) ;; *) echo "--found 는 gate|live|baseline: $FOUND" >&2; exit 2;; esac
[ -f "$LEDGER" ] || { echo "LANDING-LEDGER 없음: $LEDGER" >&2; exit 2; }

FULL="$(git rev-parse --verify --quiet "$SHA^{commit}")" || { echo "sha 검증 실패(이 리포에 없는 커밋): $SHA" >&2; exit 2; }
SHORT="${FULL:0:10}"
ORIGIN="$(git remote get-url origin 2>/dev/null | sed -E 's#^git@github\.com:#https://github.com/#; s#\.git$##')"
[ -n "$ORIGIN" ] || { echo "origin URL 조회 실패" >&2; exit 2; }
SUBJ="$(git log -1 --format=%s "$FULL")"

# LANDING-LEDGER 표 행(「| 카드 | 결과 sha | Issue | …」) 중 결과 sha 가 깬 sha 의 접두(7자+)인 행
ROW=""; ROWNO=0; I=0
while IFS= read -r LINE; do
  case "$LINE" in '|'*) ;; *) continue;; esac
  CELL="$(awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}' <<<"$LINE")"
  case "$CELL" in ''|'결과 sha'|-*|'(랜딩 전)') continue;; esac
  I=$((I+1))
  if [ "${#CELL}" -ge 7 ] && case "$FULL" in "$CELL"*) true;; *) false;; esac; then ROW="$LINE"; ROWNO=$I; break; fi
done < "$LEDGER"
[ -n "$ROW" ] || { echo "LANDING-LEDGER 에 결과 sha ${SHORT} 행 없음 — 역링크 불가(깬 랜딩이 원장 밖). 원장 행부터 확인: $LEDGER" >&2; exit 2; }
CARD="$(awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}' <<<"$ROW")"
LEDGER_ISSUE="$(awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}' <<<"$ROW")"
case "$LEDGER_ISSUE" in "#$N") ;; *) echo "경고: 원장 행 Issue=${LEDGER_ISSUE} ≠ 요청 #${N} — 의도한 Issue 인지 확인" >&2;; esac

BODY="regression: 깬 sha ${FULL} · 발견 ${FOUND} · LEDGER 행 ${ROWNO}(${CARD}) — 깬 랜딩: ${ORIGIN}/commit/${FULL} (${SUBJ}). 5항 재작성 후 다시 닫는다(design/harness/ISSUE-TRANSITIONS.md §4)."
CMDS=(
  "gh issue reopen $N"
  "gh issue edit $N --add-label status:needs-review --remove-label status:done"
  "gh issue comment $N --body \"$BODY\""
)

if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN (--apply 없음 · 아무것도 실행하지 않음)"
  echo "역링크: LANDING-LEDGER 행 ${ROWNO} · 카드=${CARD} · 결과 sha=${SHORT}"
  printf '  %s\n' "${CMDS[@]}"
else
  gh issue reopen "$N" || exit 1
  gh issue edit "$N" --add-label status:needs-review --remove-label status:done || exit 1
  gh issue comment "$N" --body "$BODY" || exit 1
  echo "REOPENED #$N <- ${SHORT} (LEDGER 행 ${ROWNO})"
fi

if [ "$LIVE" -eq 1 ]; then
  echo "큐 요청(planner 에 mbox 1통 — 이 스크립트는 큐에 쓰지 않음): 종류=즉시 · Issue #${N} · 사유=라이브 깨짐 회귀 · 깬 sha ${SHORT}"
fi
echo "REVERT 안내(실행 0 · 소유 오케 손): git revert ${SHORT}  # 새 커밋 · force push 0 · 브랜치 삭제 0"
echo "  그 revert 후보도 랜딩 ④~⑥ 전부(대상 동기화 → 후보 sha 시험 → DA⑥ 증분 → push → 라이브) 통과 후 push — 면제 0"
exit 0
