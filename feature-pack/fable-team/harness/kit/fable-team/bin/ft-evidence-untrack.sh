#!/usr/bin/env bash
# ft-evidence-untrack.sh [--dry-run] <리포 루트>   (r449 · 오빠 2026-10-19 «관리도 안되고 무식하게 아래로만 커지는 로그성파일»)
#   이미 tracked 인 design/ 아래 증거 로그를 index 에서만 뺀다 — git rm --cached(디스크 파일 보존 · 이력 재작성 0 · 커밋은 부른 쪽).
#   판정식 = ft-evidence-lib.sh 한 곳(pre-commit·ft-merge-land 와 같은 함수) · 크기 = index blob 크기 합.
#   출력: --dry-run 은 목록 줄 + 마지막 `UNTRACK n=<n> MB=<m> dry=1` · 적용은 `UNTRACK n=<n> MB=<m> dry=0` 한 줄.
#   종료: 0 · 1 REJECT(미커밋 tracked 변경 있음 — [wip] 먼저 · rm 실패) · 2 usage. 외부 호출 0(로컬 git 만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-evidence-lib.sh"
usage() { echo "usage: $0 [--dry-run] <리포 루트>" >&2; exit 2; }
DRY=0; ROOT=""
while [ $# -gt 0 ]; do case "$1" in
  --dry-run) DRY=1; shift;;
  -*) usage;; *) [ -z "$ROOT" ] || usage; ROOT="$1"; shift;; esac; done
[ -n "$ROOT" ] || usage
ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || { echo "REJECT git 리포가 아님: $ROOT" >&2; exit 2; }
G() { git -C "$ROOT" "$@"; }
[ -z "$(G status --porcelain --untracked-files=no)" ] || { echo "REJECT 미커밋 변경 있음 — [wip] 먼저 커밋한 뒤 다시(untrack 커밋에 남의 변경이 섞이지 않게)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G ls-files -z -- design | tr '\0' '\n' | ft_evidence_filter > "$T/list"
N="$(grep -c . "$T/list")"
BYTES="$(sed 's/^/:/' "$T/list" | G cat-file --batch-check='%(objectsize)' | awk '{s+=$1} END{printf "%d", s}')"
MB="$(awk -v b="$BYTES" 'BEGIN{printf "%.1f", b/1048576}')"
if [ "$DRY" = 1 ]; then cat "$T/list"
elif [ "$N" -gt 0 ]; then
  tr '\n' '\0' < "$T/list" > "$T/list0"
  # --sparse: sparse-checkout 워크트리(나노 spawn 기본)에서 cone 밖 항목도 index 에서 뺀다 — 없으면 일부만 빠지고 실패한다(r449 실측 59/614)
  G --literal-pathspecs rm --cached --sparse -q --pathspec-from-file="$T/list0" --pathspec-file-nul || { echo "REJECT git rm --cached 실패 — index 가 일부 바뀌었을 수 있음 · 되돌림: git -C $ROOT reset -q"; exit 1; }
fi
echo "UNTRACK n=$N MB=$MB dry=$DRY"
