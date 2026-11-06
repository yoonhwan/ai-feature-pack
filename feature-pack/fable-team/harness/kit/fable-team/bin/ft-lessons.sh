#!/usr/bin/env bash
# ft-lessons.sh — 좌석·팀·전역 3계층 LESSONS + 락 (r1433 · hermes MEMORY.md/USER.md + .lock 방식)
#   사용:
#     ft-lessons.sh check                              # 3계층 존재·.lock·크기 상한 판정 (rc0 통과 / rc1 위반)
#     ft-lessons.sh init                               # 좌석·팀 계층 폴더·파일·락 생성(멱등)
#     ft-lessons.sh path <seat|team|global> [이름]     # 경로 1줄
#     ft-lessons.sh add <seat|team> <이름> "1줄"        # 락 잡고 append. 상한 넘으면 자동 분리(SPLIT 1줄)
#     ft-lessons.sh read <seat|team> <이름> [--all]    # 앞 20줄 기본
#     ft-lessons.sh compact <seat|team> <이름>         # 상한 넘은 만큼 오래된 줄을 .archive-<날짜>.md 로
#   상한: seat 2048 · team 4096 · global 2048 (전역 = ~/.claude/rules/dumb-time-digest.md · 읽기 전용)
#   데이터 루트 = <FT_ROOT>/state/lessons/  (FT_ROOT 기본 = 현재 리포 .fable-team)
#   락 = <파일>.lock (fcntl.flock · 7초 대기 · 실패 = rc3 «판정 불가», 하드 룰 20)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft_lessons.py" ] || { echo "REJECT ft_lessons.py 없음: $HERE"; exit 1; }
command -v python3 >/dev/null || { echo "REJECT python3 없음"; exit 1; }
exec python3 "$HERE/ft_lessons.py" "$@"
