#!/usr/bin/env bash
# ft-team-attach.sh — 팀 파생 명부 확인·생성·분리·복원 (r1298).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
for f in ft_team_attach.py ft_team_attach_lib.py ft_team_attach_ops.py ft_team_attach_state.py ft_team_lib.py; do
  [ -f "$HERE/$f" ] || { echo "REJECT 팀 attach 구성 파일 없음: $HERE/$f"; exit 1; }
done
exec python3 -I "$HERE/ft_team_attach.py" "$@"
