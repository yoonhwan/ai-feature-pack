#!/usr/bin/env bash
# ft-proposal-register.sh <제안서.md> [--check | --apply] [--force-create]
#   제안서 흐름 4단계 · «제안서 Issue 등록 진입점». 확인과 생성을 한 실행으로 묶는다(DA HOLD-P1).
#   제안서를 «1회» 읽어 ①머리줄 정확히 `- 상태: 승인 — 판정 <숫자>` ②머리줄·본문에 `Issue #<번호>` 없음 ③`## 검증` 칸 1줄 이상
#   — 셋 다 맞을 때만 본문(= 제안서 전문 · 판정 357 r2)을 만들고 Tank 래퍼 create → (60,000자 초과분 comment) → label(proposal,approved) 를 부른다.
#   하나라도 틀리면 Tank 호출 0. 본문 첫 줄 = 숨은 표식 `<!-- byz-proposal-id: <ID> -->` · 시도 기록 ~/.hermes/state/proposal_register.json.
#   create 전 원격(읽기 전용)에서 같은 ID 를 찾는다 — 같은 ID = 채택(create 0) · 제목만 같음 = 충돌 rc1 · 기록 creating + 원격 없음 = 불명 rc1(--force-create 로만 진행).
#   --check = 확인만(Tank 호출 0) · --apply = 실제 등록 · 둘 다 없으면 Tank 를 dry-run 으로(create 만, label 0).
#   exit 0 = 통과/등록 · 1 = 실패(사유 stdout) · 2 = usage   출력(--apply 성공) = REGISTERED #M 판정 N · 이미 등록 = ALREADY #M 판정 N
# 시험용: FT_TANK_CMD(Tank 래퍼 대체 — 기본 ft-gh-as-tank.sh) · FT_GH_READ(원격 읽기 대체 — 기본 gh) · FT_PROPOSAL_STATE(시도 기록 경로) · GH_REPO
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
usage() { echo "usage: $0 <제안서.md> [--check | --apply] [--force-create]" >&2; exit 2; }

[ $# -ge 1 ] || usage
FILE="$1"; shift
MODE="dry"; FORCE=""
while [ $# -gt 0 ]; do case "$1" in
  --check) [ "$MODE" = dry ] || usage; MODE="check"; shift;;
  --apply) [ "$MODE" = dry ] || usage; MODE="apply"; shift;;
  --force-create) FORCE="--force-create"; shift;;
  *) echo "unknown $1" >&2; usage;; esac; done

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="$HERE/proposal_register_lib.py"
if [ -n "${FT_TANK_CMD:-}" ]; then read -ra TANK <<<"$FT_TANK_CMD"; else TANK=(bash "$HERE/../fable-team/bin/ft-gh-as-tank.sh"); fi
REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
STATE="${FT_PROPOSAL_STATE:-$HOME/.hermes/state/proposal_register.json}"

[ -f "$FILE" ] || die "제안서 파일 없음: $FILE"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft-proposal.XXXXXX")" || die "임시 폴더 생성 실패"
trap 'rm -rf "$WORK"' EXIT
cp "$FILE" "$WORK/snap.md" || die "제안서 복사 실패"   # ★1회 읽기★ — 이하 확인·ID·본문은 전부 이 스냅샷에서 나온다(확인과 생성 사이 파일이 바뀌어도 어긋나지 않는다)
CONTENT="$(cat "$WORK/snap.md")"

STATUS_LINES="$(printf '%s\n' "$CONTENT" | sed -n '/^## /q;/^- 상태:/p')"
[ "$(printf '%s\n' "$STATUS_LINES" | grep -c '^- 상태:')" = 1 ] || die "머리의 「- 상태:」 줄이 정확히 1개가 아니다(판정 충돌 — 첫 줄만 믿지 않는다): $(printf '%s\n' "$STATUS_LINES" | grep -c '^- 상태:')개"
STATUS_LINE="$STATUS_LINES"
[[ "$STATUS_LINE" =~ ^-\ 상태:\ 승인\ —\ 판정\ ([0-9]+)$ ]] || die "머리줄이 「- 상태: 승인 — 판정 <숫자>」 가 아니다: ${STATUS_LINE:-상태 줄 없음}"
VERDICT="${BASH_REMATCH[1]}"
printf '%s\n' "$CONTENT" | grep -qE 'Issue #[0-9]+' && die "이미 Issue 번호가 있다(재등록 금지): $(printf '%s\n' "$CONTENT" | grep -oE 'Issue #[0-9]+' | head -1)"
VERIFY="$(printf '%s\n' "$CONTENT" | awk 'index($0,"## 검증")==1{f=1;next} /^## /{f=0} f' | grep -v '^[[:space:]]*$')"
[ -n "$VERIFY" ] || die "「## 검증」 칸이 비어 있다(구현 뒤 Issue close 증거로 쓰일 문장 1줄 이상 필요)"

if [ "$MODE" = check ]; then echo "CHECK OK 판정 $VERDICT — Tank 호출 0"; exit 0; fi

# 경로@sha — 제안서는 git 리포 안에서 «커밋된 그대로» 여야 한다(본문이 «경로 @ 커밋» 이라 적으므로 작업본이 다르면 거짓 표기)
TOP="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null)" || die "제안서가 git 리포 안에 있어야 한다(경로@sha 를 못 정한다): $FILE"
TOP="$(cd "$TOP" && pwd -P)"; ABS="$(cd "$(dirname "$FILE")" && pwd -P)/$(basename "$FILE")"; REL="${ABS#"$TOP"/}"
SHA10="$(git -C "$TOP" log -1 --format=%H -- "$REL" | cut -c1-10)"
[ -n "$SHA10" ] || die "제안서가 커밋되지 않았다: $REL — 머리줄 갱신을 커밋한 뒤 다시"
[ -z "$(git -C "$TOP" status --porcelain --untracked-files=all -- "$REL")" ] || die "제안서가 커밋 뒤 수정됐다: $REL — 커밋한 뒤 다시"

TITLE_RAW="$(printf '%s\n' "$CONTENT" | sed -n 's/^# 제안서 — //p' | head -1)"
TITLE="[제안서] ${TITLE_RAW:-$(basename "$FILE" .md)}"
ID="$(python3 "$LIB" id --repo "$REPO" --rel "$REL" --verdict "$VERDICT" --file "$WORK/snap.md")" || die "제안서 식별자 계산 실패: $ID"
NCH="$(python3 "$LIB" body --id "$ID" --rel "$REL" --verdict "$VERDICT" --sha "$SHA10" --file "$WORK/snap.md" --top "$TOP" --out "$WORK")" || die "본문 생성 실패: $NCH"

if [ "$MODE" = dry ]; then
  "${TANK[@]}" create "$TITLE" "$WORK/chunk-1" || die "Tank dry-run create 실패(rc=$?)"
  echo "DRY 판정 $VERDICT — create dry-run 만 · label 0 · 본문 조각 ${NCH}개"; exit 0
fi

PLAN="$(python3 "$LIB" plan --id "$ID" --title "$TITLE" --repo "$REPO" --state "$STATE" $FORCE)" || die "원격 조회 실패·불완전 — Tank 0: $PLAN"
case "$PLAN" in
  ADOPT*) NUM="$(echo "$PLAN" | awk '{print $2}')"
          echo "ALREADY #$NUM 판정 $VERDICT — 이미 등록됨 #$NUM(채택) · 머리줄에 Issue #$NUM 기입 · 남은 조각·라벨은 기록 phase 기준 수동 ($PLAN)"; exit 0;;
  CONFLICT*) die "제목 충돌 #$(echo "$PLAN" | awk '{print $2}') — 다른 제안서(채택 0 · 제목을 바꿔 다시) — create 0";;
  UNKNOWN) die "불명: $ID 생성 결과 확인 필요 — GitHub 에서 표식 확인 뒤 --force-create (create 0)";;
  CREATE) ;;
  *) die "원격 조회 응답 해석 실패: $PLAN";;
esac

python3 "$LIB" rec "$STATE" set "$ID" creating >/dev/null || die "시도 기록 저장 실패 — Tank 0"
OUT="$("${TANK[@]}" create "$TITLE" "$WORK/chunk-1" --apply 2>&1)"; RC=$?
# 확정 거절 = Tank 래퍼가 원격 호출 «전» 에 거절한 rc=2(usage·토큰 없음)뿐. 그 밖의 실패·번호 없는 출력은 «불명» — creating 유지.
if [ $RC -eq 2 ]; then python3 "$LIB" rec "$STATE" del "$ID" >/dev/null; printf '%s\n' "$OUT"; die "Tank create 확정 거절(rc=2 · 원격 호출 전) — 기록 삭제 · label 0 · comment 0"; fi
NUM="$(printf '%s\n' "$OUT" | sed -n 's/.*issue=#\([0-9][0-9]*\).*/\1/p' | tail -1)"
if [ $RC -ne 0 ] || [ -z "$NUM" ]; then printf '%s\n' "$OUT"; die "Tank create 결과 불명(rc=$RC · issue=#N ${NUM:+있음}${NUM:-없음}) — 기록 creating 유지 · label 0 · GitHub 에서 표식 확인 뒤 --force-create"; fi
python3 "$LIB" rec "$STATE" set "$ID" created --issue "$NUM" >/dev/null || die "#$NUM 등록됨 · 시도 기록 저장 실패 — 남은 조각·라벨 수동"
k=2
while [ "$k" -le "$NCH" ]; do
  "${TANK[@]}" comment "$NUM" "$WORK/chunk-$k" --apply >/dev/null 2>&1 || die "#$NUM 등록됨 · 분할 $k/$NCH 부터 수동 — 분할 $k 는 원격에 생겼을 수도 있음: Issue #$NUM 댓글을 확인한 뒤 $k(또는 $((k+1)))부터 · label 0"
  python3 "$LIB" rec "$STATE" set "$ID" "comment-$k" --issue "$NUM" >/dev/null || die "#$NUM 등록됨 · 분할 $k/$NCH 까지 올라감 · 시도 기록 저장 실패 — 이어서 수동"
  k=$((k+1))
done
"${TANK[@]}" label "$NUM" --add proposal,approved --apply >/dev/null 2>&1 || die "#$NUM 등록됨 · 라벨 수동(proposal,approved) — label 실패"
python3 "$LIB" rec "$STATE" set "$ID" "done" --issue "$NUM" >/dev/null || echo "WARN 시도 기록 done 저장 실패(#$NUM 은 등록·라벨 완료)" >&2
echo "REGISTERED #$NUM 판정 $VERDICT"
