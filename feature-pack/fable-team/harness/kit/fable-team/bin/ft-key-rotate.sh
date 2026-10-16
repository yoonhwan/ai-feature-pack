#!/usr/bin/env bash
# ft-key-rotate.sh — 노출 키 교체 (R195). 새 값 = 클립보드 → stdin 으로만 파이썬에 전달.
# 사용: ft-key-rotate.sh [--paid-check] <KEY> | --check-old [--paid-check] <KEY> | --restore <KEY> | --status
# 출력은 키 이름·길이·HTTP 코드뿐 — 값은 화면·로그·argv·env 어디에도 안 나간다.
set -uo pipefail
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${FT_KEY_ROTATE_PYTHON:-python3}"
TOOL="$HERE/ft_key_rotate.py"

case "${1:-}" in
  --status)    exec "$PY" "$TOOL" status ;;
  --check-old) shift; exec "$PY" "$TOOL" check-old "$@" ;;
  --restore)   shift; exec "$PY" "$TOOL" restore "$@" ;;
  --abandon)   shift; exec "$PY" "$TOOL" abandon "$@" ;;
  --resume)    shift
    case " $* " in
      *" --from-clipboard "*) trap 'printf "" | pbcopy' EXIT; pbpaste | "$PY" "$TOOL" resume "$@"; exit "${PIPESTATUS[1]}" ;;
      *) exec "$PY" "$TOOL" resume "$@" < /dev/null ;;
    esac ;;
  ""|-h|--help) exec "$PY" "$TOOL" ;;
esac

# 교체: 성공·실패·중단 모두 클립보드 비움 (유니버설 클립보드·기록 앱 전파 차단)
trap 'printf "" | pbcopy' EXIT
pbpaste | "$PY" "$TOOL" rotate "$@"
exit "${PIPESTATUS[1]}"
