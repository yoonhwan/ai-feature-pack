#!/usr/bin/env bash
# ft-sat-nano.sh — 입구. 본체 = 같은 폴더 ft_sat_nano.py · 엔진 ft_sat_rt.py (r902 r7 + DECISION 고침 3)
exec python3 "$(dirname "${BASH_SOURCE[0]}")/ft_sat_nano.py" "$@"
