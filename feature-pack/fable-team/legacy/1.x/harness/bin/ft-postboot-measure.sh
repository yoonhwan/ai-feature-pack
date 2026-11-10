#!/usr/bin/env bash
# ft-postboot-measure.sh [--summary]   (r868 · 오빠 10-25 «재부팅 직후 기준선 대비 같은 명령 2시간 주기 재측정 → 원인별 닫는 사건 설계»)
#   읽기 전용 측정 1회 → <FT_ROOT>/.fable-team/state/postboot-measure.tsv 1행(14일 지난 행은 그때 정리) · 날이 바뀐 첫 회 = 전날 요약 1장
#   (기본 자리 = 상태 파일과 같은 폴더 · 다른 자리는 FT_POSTBOOT_SUMMARY_DIR 로만 · 커밋 0). 명령마다 7초 상한 · 넘으면 «시간 초과» 칸(tmux = «오류(시간 초과)») · 판정·한계 = ft_postboot_measure.py 머리.
#   launchd com.byz.ft-postboot-measure 가 7200초마다 + 적재 때 1회(재부팅 직후 열) 실행 · 상시 프로세스 0 · 끝 = 측정 끝나면 bootout.
#   상태 기록이 실패해도(상태 폴더 읽기 전용 등) 로그 닫는 사건은 돈다 — 로그만 자라는 길 0.
#   로그 닫는 사건 = stdout/err 는 상태 파일 옆 postboot-measure.log 1개(plist) · 하루 요약 때 비우고 그 밖엔 1MiB 넘으면 회전.
set -uo pipefail
SRC="${BASH_SOURCE[0]:-$0}"; case "$SRC" in */*) HERE="$(cd -- "${SRC%/*}" && pwd)";; *) HERE="$PWD";; esac   # 내장만(외부 dirname 0)
[ -f "$HERE/ft_postboot_measure.py" ] && [ -f "$HERE/ft_postboot_report.py" ] || { echo "REJECT ft_postboot_*.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
exec python3 "$HERE/ft_postboot_measure.py" "$@"
