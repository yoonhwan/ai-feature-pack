#!/usr/bin/env bash
# ft-accum-sweep.sh — r1293 하루 1회 누적 정리(옮기기·목록만 · 지우기 0) 진입. 본체 = ft_accum_sweep.py (같은 폴더).
#   부르는 곳 = ft-disk-alarm.sh accum() (하루 1회) · 손으로 돌릴 때는 bash ft-accum-sweep.sh.
#   env: FT_ACCUM_ROOT(데이터 루트 · 없으면 ft_repo_root) FT_ACCUM_NOW FT_ACCUM_BUDGET_SEC(70) FT_ACCUM_ARCHIVE_WARN_GIB(5)
#        FT_ACCUM_SCAN_DELAY_MS FT_ACCUM_SEATS FT_MBOX_SH FT_ACCUM_GIT
#   stdout 마지막 1줄 = 끝 줄(«[누적 정리] 옮김 …») · rc 0 정상 · 3 판정 불가 있음 · 2 루트·python3 없음
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ACCUM_ROOT:-}"
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 2
command -v python3 >/dev/null 2>&1 || { echo "판정 불가 python3 없음"; exit 2; }
[ -f "$HERE/ft_accum_sweep.py" ] || { echo "ERROR ft_accum_sweep.py 없음: $HERE (런타임 .fable-team/bin 에서 실행하라)"; exit 2; }
FT_ACCUM_ROOT="$ROOT" exec python3 "$HERE/ft_accum_sweep.py" "$@"
