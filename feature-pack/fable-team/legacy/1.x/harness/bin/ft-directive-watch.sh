#!/usr/bin/env bash
# ft-directive-watch.sh status|tick [--now <시각>] — 오빠 지시마다 담당 카드가 있고 움직이는가(담당 없는 오빠 지시 N · 멈춘 오빠 지시 M). 본체는 같은 디렉터리 ft_directive_watch.py (r1212).
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft_directive_watch.py" "$@"
