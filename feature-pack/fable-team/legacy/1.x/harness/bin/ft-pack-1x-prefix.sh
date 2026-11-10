#!/usr/bin/env bash
# ft-pack-1x-prefix — 팩 리포 <ref> 에서 1.x 하네스 경로 «접두 하나»를 낸다 (r1556 · 설치 h 의 PACK_1X).
# CLI: ft-pack-1x-prefix.sh <리포> <ref>
#   legacy/1.x/harness 만 있음 → feature-pack/fable-team/legacy/1.x  (rc0 · stdout 1줄)
#   harness 만 있음            → feature-pack/fable-team               (rc0 · stdout 1줄)
#   둘 다 · 둘 다 없음 · git 실패 → stderr «판정 불가 …» 1줄 · stdout 0 · rc1 (대체 실행 0 · 하드 룰 20)
# 설치 h 사용 꼴: PACK_1X=$(bash ft-pack-1x-prefix.sh <팩> <ref>) || exit 1 → git show <ref>:${PACK_1X}/harness/…
set -uo pipefail
BASE=feature-pack/fable-team
undecidable() { echo "판정 불가 $*" >&2; exit 1; }
repo="${1:-}" ref="${2:-}"
[ -n "$repo" ] && [ -n "$ref" ] || undecidable "usage: ft-pack-1x-prefix.sh <리포> <ref>"
git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null || undecidable "git 실패 <리포>=$repo <ref>=$ref"
has() { git -C "$repo" cat-file -e "$ref:$1" 2>/dev/null; }
legacy=0; main=0
has "$BASE/legacy/1.x/harness" && legacy=1
has "$BASE/harness" && main=1
case "$legacy$main" in
  10) echo "$BASE/legacy/1.x" ;;
  01) echo "$BASE" ;;
  11) undecidable "둘 다 있음 $ref" ;;
  *)  undecidable "둘 다 없음 $ref" ;;
esac
