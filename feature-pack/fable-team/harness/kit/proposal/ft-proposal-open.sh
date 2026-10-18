#!/usr/bin/env bash
# ft-proposal-open.sh <제안서.md> [--apply] [--revision rN] — 제안서를 «처음부터» Tank 제안 Issue 로 연다 (R77 r1 · 판정 826 · 정본 = 이 Issue)
#   제안서를 1회 읽어 필수 칸 6개(결론·오빠가 결정할 것·배경·제안·되돌림·근거)가 비어 있지 않은지 본다 — 하나라도 비면 Tank 호출 0 + rc 1.
#   본문 = 숨은 표식 `<!-- byz-proposal-id: <팀>/<slug> -->` + 제안서 «전문»(링크만 0 · 60,000자 넘으면 `(이어서 k/N)` 코멘트로 분할).
#   같은 ID 의 Issue 가 원격에 이미 있으면 채택(create 0 · 라벨만 보장). Tank create → label --add proposal. 출력 `OPENED #M`(채택이면 ` (채택)`).
#   --revision rN = 이미 연 Issue 의 본문을 Tank `edit --body-file`(래퍼가 옛 본문 보관) 로 고치고 `rN 변경` 코멘트 — 승인 라벨(approved)이 있으면 «edit 전에» Tank `label --remove approved`(무효화 먼저 · 과거 승인 재사용 금지 · 재승인 = approve 도구). 출력 `REVISED #M rN` (분할이 필요한 길이는 거부).
#   --apply 없으면 Tank 를 dry-run 으로(실행할 명령만 출력) · 라벨 승인(approved)은 이 도구가 하지 않는다 — ft-proposal-approve.sh.
# 시험용: FT_TANK_CMD(Tank 래퍼 대체) · FT_GH_READ(원격 읽기 대체) · GH_REPO · FT_GATE_GH_TIMEOUT
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
usage() { echo "usage: $0 <제안서.md> [--apply] [--revision rN]" >&2; exit 2; }
[ $# -ge 1 ] || usage
FILE="$1"; shift; APPLY=(); REV=""
while [ $# -gt 0 ]; do case "$1" in
  --apply) APPLY=(--apply); shift;;
  --revision) [[ "${2:-}" =~ ^r[1-9][0-9]*$ ]] || usage; REV="$2"; shift 2;;
  *) echo "unknown $1" >&2; usage;; esac; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; LIB="$HERE/proposal_issue_lib.py"
if [ -n "${FT_TANK_CMD:-}" ]; then read -ra TANK <<<"$FT_TANK_CMD"; else TANK=(bash "$HERE/../fable-team/bin/ft-gh-as-tank.sh"); fi
REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
[ -f "$FILE" ] || die "제안서 파일 없음: $FILE"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ft-proposal-open.XXXXXX")" || die "임시 폴더 생성 실패"; trap 'rm -rf "$WORK"' EXIT
TEAM="$(basename "$(cd "$(dirname "$FILE")" && pwd -P)")"; mkdir -p "$WORK/snap/$TEAM"; SNAP="$WORK/snap/$TEAM/$(basename "$FILE")"
cp "$FILE" "$SNAP" || die "제안서 복사 실패"   # ★1회 읽기★ — 이하 확인·ID·본문은 전부 이 스냅샷에서 나온다
MISS="$(python3 "$LIB" sections --file "$SNAP")" || die "필수 칸이 없거나 비어 있다: $MISS — Tank 호출 0"
META="$(python3 "$LIB" meta --file "$SNAP")" || die "$META"
ID="$(sed -n 1p <<<"$META")"; TITLE="[제안서] $(sed -n 2p <<<"$META")"
FIND="$(python3 "$LIB" find --repo "$REPO" --id "$ID")" || die "원격 조회 실패 — Tank 0: $FIND"
NCH="$(python3 "$LIB" open-body --id "$ID" --file "$SNAP" --out "$WORK")" || die "본문 생성 실패: $NCH"

if [ -n "$REV" ]; then
  [[ "$FIND" == ADOPT* ]] || die "수정할 제안 Issue 가 없다(표식 $ID) — 먼저 --revision 없이 연다 · Tank 0"
  [ "$NCH" = 1 ] || die "분할이 필요한 길이(${NCH}조각)는 --revision 미지원 — Tank 0"
  NUM="${FIND#ADOPT }"; echo "$REV 변경 — 본문을 이 판으로 고쳤다" > "$WORK/rev-comment"
  LB="$(python3 "$LIB" labels --repo "$REPO" --issue "$NUM")" || die "라벨 조회 실패 — Tank 0(승인 잔존 여부를 모른 채 본문을 고치지 않는다): $LB"
  case " $LB " in *" approved "*)   # ★무효화 먼저★ — 고친 본문에 과거 승인 재사용 금지(중간 실패여도 승인 없는 상태 유지) · 재승인 = ft-proposal-approve.sh
    "${TANK[@]}" label "$NUM" --remove approved ${APPLY[@]+"${APPLY[@]}"} >/dev/null || die "#$NUM approved 라벨 제거 실패 — 본문 edit 0";; esac
  "${TANK[@]}" edit "$NUM" --body-file "$WORK/chunk-1" ${APPLY[@]+"${APPLY[@]}"} || die "Tank edit 실패(#$NUM) — 코멘트 0 · 승인은 이미 제거됨"
  "${TANK[@]}" comment "$NUM" "$WORK/rev-comment" ${APPLY[@]+"${APPLY[@]}"} || die "#$NUM 본문은 고침 · 코멘트 실패 — 수동(승인은 이미 제거됨)"
  echo "REVISED #$NUM $REV"; exit 0
fi

if [[ "$FIND" == ADOPT* ]]; then NUM="${FIND#ADOPT }"; NOTE=" (채택)"
else
  OUT="$("${TANK[@]}" create "$TITLE" "$WORK/chunk-1" ${APPLY[@]+"${APPLY[@]}"} 2>&1)"; RC=$?
  [ $RC -eq 0 ] || { printf '%s\n' "$OUT"; die "Tank create 실패(rc=$RC) — 같은 명령을 다시 돌리면 표식으로 채택한다 · label 0"; }
  [ ${#APPLY[@]} -gt 0 ] || { printf '%s\n' "$OUT"; echo "DRY 본문 조각 ${NCH}개 · create dry-run 만 · label 0"; exit 0; }
  NUM="$(printf '%s\n' "$OUT" | sed -n 's/.*issue=#\([0-9][0-9]*\).*/\1/p' | tail -1)"; NOTE=""
  [ -n "$NUM" ] || { printf '%s\n' "$OUT"; die "create 결과에 issue=#N 이 없다 — GitHub 에서 표식 확인 뒤 다시(채택된다)"; }
  k=2; while [ "$k" -le "$NCH" ]; do
    "${TANK[@]}" comment "$NUM" "$WORK/chunk-$k" --apply >/dev/null 2>&1 || die "#$NUM 등록됨 · 분할 $k/$NCH 부터 수동(코멘트 확인 후)"; k=$((k+1)); done
fi
[ ${#APPLY[@]} -gt 0 ] || { echo "DRY #$NUM 채택 — label dry-run 생략"; exit 0; }
"${TANK[@]}" label "$NUM" --add proposal --apply >/dev/null 2>&1 || die "#$NUM 열림 · 라벨 proposal 수동(label-create 먼저인지 확인)"
echo "OPENED #$NUM$NOTE"
