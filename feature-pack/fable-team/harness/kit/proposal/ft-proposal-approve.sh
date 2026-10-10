#!/usr/bin/env bash
# ft-proposal-approve.sh <M> --verdict N --interview <파일> [--approve] [--clear-needs-reply] [--apply] — 제안 Issue 에 오빠 인터뷰 판정을 남기고 승인한다 (R77 r1 · 판정 826)
#   ①planner 원장 `^N 오빠 인터뷰` 줄에 `github.com/<저장소>/issues/M` 이 없으면 Tank 호출 0 + rc 1.  ②Tank 코멘트 `[인터뷰 판정 N]` + 인터뷰 파일 원문(질문·오빠 답·추가 의견).
#   ③`--approve` 면 이어서 label --add approved(이미 approved 면 --remove 뒤 재부착 = 새 승인 시각) — `needs-reply` 가 있으면 거부(Tank 0 · --clear-needs-reply 와 같이 주면 라벨을 먼저 뗀다) · rejected 면 거부.
#   ④`--clear-needs-reply` 면 label --remove needs-reply.  --apply 없으면 Tank 를 dry-run 으로. 출력 `APPROVED #M 판정 N` | `COMMENTED #M 판정 N`.
# 시험용: FT_TANK_CMD · FT_GH_READ · GH_REPO · FT_PLANNER_VERDICTS_DIR(기본 $BYZ_ROOT/.worktrees/v6-realtime-live/design/planner) · BYZ_ROOT
set -uo pipefail
die() { echo "REJECT $1"; exit "${2:-1}"; }
usage() { echo "usage: $0 <Issue번호> --verdict N --interview <파일> [--approve] [--clear-needs-reply] [--apply]" >&2; exit 2; }
[ $# -ge 1 ] && [[ "$1" =~ ^[0-9]+$ ]] || usage
M="$1"; shift; N=""; IV=""; APPROVE=0; CLEAR=0; APPLY=()
while [ $# -gt 0 ]; do case "$1" in
  --verdict) N="${2:-}"; shift 2;; --interview) IV="${2:-}"; shift 2;;
  --approve) APPROVE=1; shift;; --clear-needs-reply) CLEAR=1; shift;; --apply) APPLY=(--apply); shift;;
  *) echo "unknown $1" >&2; usage;; esac; done
[[ "$N" =~ ^[1-9][0-9]*$ ]] && [ -f "$IV" ] && [ -s "$IV" ] || usage
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; LIB="$HERE/proposal_issue_lib.py"
if [ -n "${FT_TANK_CMD:-}" ]; then read -ra TANK <<<"$FT_TANK_CMD"; else TANK=(bash "$HERE/../fable-team/bin/ft-gh-as-tank.sh"); fi
REPO="${GH_REPO:-SecondWindStudio/byz-agents}"
ROOT="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; ROOT="${ROOT:-$(pwd)}"
VDIR="${FT_PLANNER_VERDICTS_DIR:-${BYZ_ROOT:-$ROOT}/.worktrees/v6-realtime-live/design/planner}"
R="$(python3 "$LIB" ledger --dir "$VDIR" --verdict "$N" --issue "$M" --repo "$REPO")" || die "$R — Tank 호출 0"
LB="$(python3 "$LIB" labels --repo "$REPO" --issue "$M")" || die "라벨 조회 실패 — Tank 0: $LB"
has() { case " $LB " in *" $1 "*) return 0;; esac; return 1; }
has proposal || die "#$M 는 proposal 라벨 Issue 가 아니다 — Tank 0"
if [ "$APPROVE" = 1 ]; then
  has rejected && die "#$M 에 rejected 라벨 — 승인 거부 · Tank 0"
  has needs-reply && [ "$CLEAR" = 0 ] && die "#$M 에 needs-reply 라벨이 있다(제안 Issue 에 답 안 한 코멘트) — 답을 확인하고 --clear-needs-reply 와 함께 · Tank 0"
fi
W="$(mktemp -d "${TMPDIR:-/tmp}/ft-proposal-approve.XXXXXX")" || die "임시 폴더 생성 실패"; trap 'rm -rf "$W"' EXIT
{ echo "[인터뷰 판정 $N]"; echo; cat "$IV"; } > "$W/comment"
"${TANK[@]}" comment "$M" "$W/comment" ${APPLY[@]+"${APPLY[@]}"} >/dev/null || die "Tank 코멘트 실패 — label 0"
if [ "$CLEAR" = 1 ]; then "${TANK[@]}" label "$M" --remove needs-reply ${APPLY[@]+"${APPLY[@]}"} >/dev/null || die "#$M 코멘트는 남김 · needs-reply 제거 실패 — approved 0"; fi
if [ "$APPROVE" = 1 ]; then
  has approved && { "${TANK[@]}" label "$M" --remove approved ${APPLY[@]+"${APPLY[@]}"} >/dev/null || die "#$M 코멘트는 남김 · 기존 approved 제거 실패(재부착 불가) — 수동"; }   # 중복 라벨은 승인 시각을 못 갱신 — 제거 후 재부착
  "${TANK[@]}" label "$M" --add approved ${APPLY[@]+"${APPLY[@]}"} >/dev/null || die "#$M 코멘트는 남김 · approved 라벨 실패 — 수동"
  echo "$([ ${#APPLY[@]} -gt 0 ] && echo APPROVED || echo "DRY(approve)") #$M 판정 $N"
else echo "$([ ${#APPLY[@]} -gt 0 ] && echo COMMENTED || echo "DRY(comment)") #$M 판정 $N"; fi
