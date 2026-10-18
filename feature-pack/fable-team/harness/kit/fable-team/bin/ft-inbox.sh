#!/usr/bin/env bash
# ft-inbox.sh — 메인팀 인박스 진입점. 본체는 같은 디렉터리 ft-inbox.py (사용법·계약은 그 머리말).
exec python3 "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/ft-inbox.py" "$@"
