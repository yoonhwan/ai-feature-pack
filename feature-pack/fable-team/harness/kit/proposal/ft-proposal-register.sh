#!/usr/bin/env bash
# ft-proposal-register.sh <제안서.md> [--check | --apply]
#   제안서 흐름 4단계 · «제안서 Issue 등록 진입점». 확인과 생성을 한 실행으로 묶는다(DA HOLD-P1).
#   제안서를 «1회» 읽어 ①머리줄 정확히 `- 상태: 승인 — 판정 <숫자>` ②머리줄·본문에 `Issue #<번호>` 없음 ③`## 검증` 칸 1줄 이상
#   — 셋 다 맞을 때만 본문을 만들고 Tank 래퍼 create → label(proposal,approved) 를 부른다. 하나라도 틀리면 Tank 호출 0.
#   --check = 확인만(Tank 호출 0) · --apply = 실제 등록 · 둘 다 없으면 Tank 를 dry-run 으로(create 만, label 0).
#   exit 0 = 통과/등록 · 1 = 실패(사유 stdout) · 2 = usage   출력(--apply 성공) = REGISTERED #M 판정 N
# 시험용: FT_TANK_CMD(Tank 래퍼 대체 — 기본 ft-gh-as-tank.sh)
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
usage() { echo "usage: $0 <제안서.md> [--check | --apply]" >&2; exit 2; }

[ $# -ge 1 ] || usage
FILE="$1"; shift
MODE="dry"
while [ $# -gt 0 ]; do case "$1" in
  --check) [ "$MODE" = dry ] || usage; MODE="check"; shift;;
  --apply) [ "$MODE" = dry ] || usage; MODE="apply"; shift;;
  *) echo "unknown $1" >&2; usage;; esac; done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -n "${FT_TANK_CMD:-}" ]; then read -ra TANK <<<"$FT_TANK_CMD"; else TANK=(bash "$HERE/../fable-team/bin/ft-gh-as-tank.sh"); fi

[ -f "$FILE" ] || die "제안서 파일 없음: $FILE"
CONTENT="$(cat "$FILE")"   # ★1회 읽기★ — 이하 확인·본문은 전부 이 변수에서 나온다(확인과 생성 사이 파일이 바뀌어도 어긋나지 않는다)

STATUS_LINES="$(printf '%s\n' "$CONTENT" | sed -n '/^## /q;/^- 상태:/p')"
[ "$(printf '%s\n' "$STATUS_LINES" | grep -c '^- 상태:')" = 1 ] || die "머리의 「- 상태:」 줄이 정확히 1개가 아니다(판정 충돌 — 첫 줄만 믿지 않는다): $(printf '%s\n' "$STATUS_LINES" | grep -c '^- 상태:')개"
STATUS_LINE="$STATUS_LINES"
[[ "$STATUS_LINE" =~ ^-\ 상태:\ 승인\ —\ 판정\ ([0-9]+)$ ]] || die "머리줄이 「- 상태: 승인 — 판정 <숫자>」 가 아니다: ${STATUS_LINE:-상태 줄 없음}"
VERDICT="${BASH_REMATCH[1]}"
printf '%s\n' "$CONTENT" | grep -qE 'Issue #[0-9]+' && die "이미 Issue 번호가 있다(재등록 금지): $(printf '%s\n' "$CONTENT" | grep -oE 'Issue #[0-9]+' | head -1)"
VERIFY="$(printf '%s\n' "$CONTENT" | awk 'index($0,"## 검증")==1{f=1;next} /^## /{f=0} f' | grep -v '^[[:space:]]*$')"
[ -n "$VERIFY" ] || die "「## 검증」 칸이 비어 있다(구현 뒤 Issue close 증거로 쓰일 문장 1줄 이상 필요)"

if [ "$MODE" = check ]; then echo "CHECK OK 판정 $VERDICT — Tank 호출 0"; exit 0; fi

TITLE_RAW="$(printf '%s\n' "$CONTENT" | sed -n 's/^# 제안서 — //p' | head -1)"
TITLE="[제안서] ${TITLE_RAW:-$(basename "$FILE" .md)}"
BODY="$(mktemp "${TMPDIR:-/tmp}/ft-proposal-body.XXXXXX")" || die "본문 임시 파일 생성 실패"
trap 'rm -f "$BODY"' EXIT
{
  echo "제안서: $FILE"
  echo "오빠 컨펌: 판정 $VERDICT (승인)"
  echo
  echo "## 검증"
  printf '%s\n' "$VERIFY"
} > "$BODY"

if [ "$MODE" = dry ]; then
  "${TANK[@]}" create "$TITLE" "$BODY" || die "Tank dry-run create 실패(rc=$?)"
  echo "DRY 판정 $VERDICT — create dry-run 만 · label 0"; exit 0
fi

OUT="$("${TANK[@]}" create "$TITLE" "$BODY" --apply 2>&1)" || { printf '%s\n' "$OUT"; die "Tank create 실패 — label 0"; }
NUM="$(printf '%s\n' "$OUT" | sed -n 's/.*issue=#\([0-9][0-9]*\).*/\1/p' | tail -1)"
[ -n "$NUM" ] || { printf '%s\n' "$OUT"; die "create 출력에서 Issue 번호를 못 읽었다(issue=#N 없음) — label 0 · 채널·GitHub 에서 확인"; }
"${TANK[@]}" label "$NUM" --add proposal,approved --apply >/dev/null 2>&1 || die "#$NUM 등록됨 · 라벨 수동(proposal,approved) — label 실패"
echo "REGISTERED #$NUM 판정 $VERDICT"
