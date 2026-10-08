#!/usr/bin/env bash
# ft-proposal-card.sh <팀> <slug> --origin "<오빠 원문>" [--source <링크>]… --signer <팀 arch 좌석>
#   제안서 흐름 2단계 · 팀 master 가 제안서 나노에게 줄 카드를 만든다 → design/<팀>/indices/대기/proposal-<slug>.md
#   exit 0 = 카드 생성+lint OK · 1 = 실패(사유 stdout) · 2 = usage
# 팀 env 는 ft-nano-spawn.sh:19 와 같은 규칙 — $ROOT/.fable-team/bin-<팀>/<팀>-env.sh 를 source(없으면 REJECT, 추측 0).
#   FT_GOAL_LEDGER·FT_GOAL_LINES_FILE 을 거기서 읽는다. 카드 폴더는 팀 이름에서 정해진다(별도 env 없음).
# 시험용 스위치: FT_PROPOSAL_ROOT(리포 루트 대체) · FT_INDEX_LINT(lint 스크립트 대체) · FT_PROPOSAL_DESIGN_REF(조사 근거로 인용할 설계 문서 경로)
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
usage() { echo "usage: $0 <팀> <slug> --origin \"<오빠 원문>\" [--source <링크>]… --signer <팀 arch 좌석>" >&2; exit 2; }

[ $# -ge 2 ] || usage
TEAM="$1"; SLUG="$2"; shift 2
ORIGIN=""; SIGNER=""; SOURCES=()
while [ $# -gt 0 ]; do case "$1" in
  --origin) [ $# -ge 2 ] || usage; ORIGIN="$2"; shift 2;;
  --source) [ $# -ge 2 ] || usage; SOURCES+=("$2"); shift 2;;
  --signer) [ $# -ge 2 ] || usage; SIGNER="$2"; shift 2;;
  *) echo "unknown $1" >&2; usage;; esac; done
[ -n "$ORIGIN" ] || usage
[ -n "$SIGNER" ] || usage

[[ "$TEAM" =~ ^[a-z0-9]+$ ]] || die "팀 이름 형식 오류(^[a-z0-9]+\$): $TEAM"
[[ "$SLUG" =~ ^[a-z0-9-]{3,40}$ ]] || die "slug 형식 오류(^[a-z0-9-]{3,40}\$): $SLUG"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git 리포 안에서 실행해야 한다"
ROOT="${FT_PROPOSAL_ROOT:-$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')}"
LINT="${FT_INDEX_LINT:-$HERE/../fable-team/bin/ft-index-lint.sh}"
[ -f "$LINT" ] || die "ft-index-lint.sh 없음: $LINT"

TENV="$ROOT/.fable-team/bin-$TEAM/$TEAM-env.sh"
[ -f "$TENV" ] || die "팀 env 없음: $TENV"
# shellcheck disable=SC1090
. "$TENV"
LEDGER_REL="${FT_GOAL_LEDGER:-}"
GOALS="${FT_GOAL_LINES_FILE:-}"
[ -n "$LEDGER_REL" ] || die "팀 env 에 FT_GOAL_LEDGER 없음: $TENV"
[ -f "$GOALS" ] || die "팀 env 의 FT_GOAL_LINES_FILE 없음: ${GOALS:-비어 있음}"
[ -f "$WT/$LEDGER_REL" ] || die "골 원장 없음: $WT/$LEDGER_REL"

IDXDIR="design/$TEAM/indices"
for st in 대기 진행 완성; do
  [ -e "$WT/$IDXDIR/$st/proposal-$SLUG.md" ] && die "같은 카드가 이미 있다: $IDXDIR/$st/proposal-$SLUG.md"
done
CARD="$WT/$IDXDIR/대기/proposal-$SLUG.md"

# 골좌표의 닫는 증거 — 원장에서 20자+ 한 줄의 앞부분을 «복붙»한다(lint ③: 원장에 실재해야 통과). 「」 가 든 줄은 건너뛴다.
EVIDENCE="$(python3 - "$WT/$LEDGER_REL" <<'PYEOF'
import re, sys
for ln in open(sys.argv[1], encoding="utf-8").read().splitlines():
    t = re.sub(r"\s+", " ", ln.replace("**", "")).strip()
    if len(t) >= 20 and not t.startswith("#") and "「" not in t and "」" not in t:
        print(t[:50].strip()); break
PYEOF
)"
[ -n "$EVIDENCE" ] || die "골 원장에서 닫는 증거로 쓸 20자+ 줄을 못 찾았다: $LEDGER_REL"

DESIGN_REF="${FT_PROPOSAL_DESIGN_REF:-design/harness/DESIGN-proposal-flow-20261008.md}"
TODAY="$(date +%F)"
mkdir -p "$(dirname "$CARD")"
{
  echo "# 인덱스: 제안서 — $SLUG ($TEAM)"
  echo "<!-- ledger: $LEDGER_REL -->"
  echo "- 상태: 대기"
  echo
  echo "## 골 원문 (항상 이 3줄)"
  sed -n '1,3p' "$GOALS"
  echo
  echo "## 골좌표"
  echo "제안서 흐름 2단계(기획) / 닫는 증거(정본 복붙): 「${EVIDENCE}」"
  echo
  echo "## 배경"
  echo "오빠 요청으로 제안서를 쓴다. 오빠 원문: 「${ORIGIN}」"
  if [ ${#SOURCES[@]} -gt 0 ]; then
    echo "자료:"; for s in "${SOURCES[@]}"; do echo "- $s"; done
  else
    echo "자료: (없음)"
  fi
  echo
  echo "## 사전검증"
  echo "- 소환: 아니오"
  echo "- 면제: 문서 전용 제안서(코드·설정 변경 0) — arch 서명 $SIGNER"
  echo
  echo "## 조사 근거"
  echo "- $DESIGN_REF:1 — 제안서 흐름 설계(상태 머리줄·템플릿 칸)"
  echo
  echo "## 구현 범위 (이 목록만 — 닫힌 목록)"
  echo "1. \`design/$TEAM/PROPOSAL-$SLUG-${TODAY//-/}.md\` 제안서 1개만 쓴다(템플릿 \`docs/rules/proposal_template.md\` 칸 순서 그대로 · 머리줄 \`- 상태: 초안\`)."
  echo "2. 자료 수집·현황 확인은 읽기 전용. 설계 참고: \`$DESIGN_REF\`"
  echo "금지: 코드·설정 수정 0 · Issue 쓰기 0 · 외부 게시(슬랙 포함) 0 · push 0 · AskUserQuestion 0. 커밋은 자기 브랜치."
  echo
  echo "## 완료 조건"
  echo "- 제안서의 템플릿 칸이 전부 채워졌고 120줄 이하. 머리줄 상태는 「초안」 그대로(상태를 올리는 손은 팀 master)."
  echo "- 닫힘 판단은 팀 master. 슬랙 발행도 팀 master 가 \`byz_proposal_publish.py\` 로 집행한다."
  echo
  echo "## 상태"
  echo "- $TODAY — 대기/ 생성 (ft-proposal-card.sh · 서명 $SIGNER)"
} > "$CARD"

echo "CARD $IDXDIR/대기/proposal-$SLUG.md"
cd "$WT" && bash "$LINT" "$IDXDIR/대기/proposal-$SLUG.md" || { echo "REJECT lint 실패 — 카드는 남겨 둔다: $CARD"; exit 1; }
exit 0
