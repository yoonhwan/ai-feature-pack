#!/usr/bin/env bash
# ft-teamset-check.sh [<팀>|--all] — 라이브 tmux + 명부를 design/TEAMSET.md 표와 대조한다 (r-teamset-standard · 판정 2170 · 읽기 전용).
#   출력 팀당 1줄 `<팀> OK|WARN|ERR …` · rc: ERR 있으면 1 · 표·명부·tmux 를 못 읽으면 `ERROR …` rc1(조용한 통과 0).
#   ERR = 필수 master 없음 · 명부 _master 가 라이브 아님 · arch 없음(줄 끝 «→ 열기: …» = 여는 명령 1줄 · R437 · 문구 = ft_teamset.py arch_open_hint) · planner _master 의 세션 안 감시(ft-inbox-watch.sh) 없음(r408) / WARN = 나노 상한 초과 · 재개 기록 없는 직전 세대 · 표에 없는 _키 / 정보 = 모델≠표(상태 불변).
#   env(시험): FT_TEAMSET_ROOT FT_TEAMSET_MD ZC_RESUME_DIR FT_TEAMSET_WATCH
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
case "${1:-}" in ''|-h|--help) echo "usage: $0 <팀>|--all" >&2; exit 2;; esac
ROOT="${FT_TEAMSET_ROOT:-$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
MD="${FT_TEAMSET_MD:-gitref:origin/main:design/TEAMSET.md}"   # R351: 표 정본 = $ROOT 의 origin/main (호출 워크트리 파일 아님) · 출력 머리 `md=…@sha10`
[ -n "$ROOT" ] || { echo "ERROR 리포 루트를 못 찾는다(FT_TEAMSET_ROOT)"; exit 1; }
[ -f "$HERE/ft_teamset.py" ] || { echo "ERROR ft_teamset.py 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
if [ "$1" = "--all" ]; then exec python3 "$HERE/ft_teamset.py" check --root "$ROOT" --md "$MD" --all; fi
exec python3 "$HERE/ft_teamset.py" check --root "$ROOT" --md "$MD" --team "$1"
