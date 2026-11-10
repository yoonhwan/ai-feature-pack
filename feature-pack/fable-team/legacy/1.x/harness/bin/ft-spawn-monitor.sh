#!/usr/bin/env bash
# ft-spawn-monitor.sh — ft_spawn_measure.py 얇은 래퍼(r1563). 인자는 그대로 넘긴다: [--hours N]
# 심링크(~/.local/bin/ft-spawn-monitor → 이 파일)로 불려도 자기 «실제» 폴더에서 py 를 찾는다.
set -uo pipefail
SELF="${BASH_SOURCE[0]:-$0}"
while [ -L "$SELF" ]; do
  D="$(cd -P -- "$(dirname -- "$SELF")" && pwd)"
  SELF="$(readlink -- "$SELF")"
  case "$SELF" in /*) ;; *) SELF="$D/$SELF" ;; esac
done
HERE="$(cd -P -- "$(dirname -- "$SELF")" && pwd)"
M="$HERE/ft_spawn_measure.py"
[ -f "$M" ] || { echo "ft-spawn-monitor: ft_spawn_measure.py 없음: $HERE" >&2; exit 2; }
exec python3 "$M" "$@"
