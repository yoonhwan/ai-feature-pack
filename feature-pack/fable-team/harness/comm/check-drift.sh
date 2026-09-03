#!/bin/bash
# comm 정본/도구 드리프트 체커 (읽기 전용).
# 런타임(추적 밖) vs 백업(tools/comm-canonical/) 을 diff -q 로 비교만 한다.
# 조용히 덮지 않는다 — 복사·수정 기능 없음. 판단은 사람이 한다.
#
# 출력: 파일당 한 줄 — SAME / DRIFT / MISSING_RUNTIME / MISSING_BACKUP
# 종료: 전부 SAME 이면 0, DRIFT/MISSING 하나라도 있으면 1.

set -u

# 스크립트 위치에서 리포 루트 유도 (하드코딩 금지: tools/comm-canonical/ 의 두 단계 위).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKUP_DIR="${SCRIPT_DIR}"

# 11개 매핑: "<백업파일명>|<런타임 상대경로>"
MAP=(
  "mbox.py|.claude/fable-team/bin/mbox.py"
  "ft-broadcast.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-broadcast.sh"
  "ft-claude-context.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-claude-context.sh"
  "ft-context-monitor.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-context-monitor.sh"
  "ft-master-tick.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-master-tick.sh"
  "ft-pm-tick.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-pm-tick.sh"
  "ft-reach-check.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-reach-check.sh"
  "ft-seat-status.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-seat-status.sh"
  "ft-send-verified.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-send-verified.sh"
  "ft-wall-check.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-check.sh"
  "ft-wall-read.sh|.worktrees/v6-realtime-live/.fable-team/bin/ft-wall-read.sh"
)

rc=0
for entry in "${MAP[@]}"; do
  name="${entry%%|*}"
  rel="${entry#*|}"
  runtime="${ROOT}/${rel}"
  backup="${BACKUP_DIR}/${name}"

  if [ ! -f "$runtime" ]; then
    echo "MISSING_RUNTIME  ${name}  (${rel})"
    rc=1
    continue
  fi
  if [ ! -f "$backup" ]; then
    echo "MISSING_BACKUP   ${name}"
    rc=1
    continue
  fi
  if diff -q "$runtime" "$backup" >/dev/null 2>&1; then
    echo "SAME             ${name}"
  else
    echo "DRIFT            ${name}  (${rel})"
    rc=1
  fi
done

exit $rc
