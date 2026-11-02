#!/usr/bin/env bash
# ft-team-main.sh render <팀>|--all — 팀 메인 파일(STATE) 렌더 (r1315 · 본체 ft_team_main.py).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
for f in ft_team_main.py ft_team_main_assign.py ft_team_main_inputs.py ft_team_lib.py ft_headline_seats.py; do
  [ -f "$HERE/$f" ] || { echo "REJECT 팀 메인 파일 구성 없음: $HERE/$f"; exit 1; }
done
exec python3 -I "$HERE/ft_team_main.py" "$@"
