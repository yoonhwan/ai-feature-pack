#!/bin/bash
# E1: `op --version` terminal condition table, run once by a human (design arch-20261015-opa-popup-design-r6 §6).
#
#   bash compare.sh [--python <absolute consumer python>]
#   bash compare.sh --selftest --python <absolute python>      test mode: PROBE_* overrides are honoured
#
# It measures `op --version` only — three conditions (terminal environment without OP_*/credential-looking names,
# the minimal allow-listed environment, the minimal environment with a fresh private HOME) x two rounds, every
# attempt 7.0 s, the whole run <= 75 s. No token is passed or read, no account command runs, no launchd job is
# registered, and no `op` process is ever signalled (only this run's own measurement child is ended). Nothing but
# status classes, milliseconds and enums is written. Ctrl-C stops it after clean-up.
#
# Exit codes: 0 all six rounds ran, 1 incomplete, 2 refused to start, 130/143/129 interrupted (clean-up runs first).

HERE="$(cd "$(dirname "$0")" && pwd -P)"
SELFTEST=0
PYTHON_BIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    --python) PYTHON_BIN="${2:-}"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자입니다 (--help)."; exit 2 ;;
  esac
  shift
done

if [ "$SELFTEST" = 1 ]; then
  MODE=selftest
  [ -z "$PYTHON_BIN" ] && PYTHON_BIN="${PROBE_PYTHON:-}"
else
  if env | grep -Eq '^(PROBE_|FAKE_)'; then
    echo "PROBE_*/FAKE_* 재정의는 --selftest 에서만 허용됩니다. 실행하지 않습니다."
    exit 2
  fi
  MODE=production
  [ -z "$PYTHON_BIN" ] && PYTHON_BIN="$HOME/.local/share/airag/runtime/bin/python"
fi
case "$PYTHON_BIN" in
  /*) ;;
  *) echo "python 의 절대경로가 필요합니다 (--python <절대경로>). 시작하지 않습니다."; exit 2 ;;
esac
if [ ! -f "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
  echo "python 을 실행할 수 없습니다: 경로를 확인하세요 (--python <절대경로>). 시작하지 않습니다."
  exit 2
fi

# The worker handles SIGINT/SIGTERM/SIGHUP itself (it ends its own measurement child first), so it takes this
# process's place and receives the signals directly.
exec "$PYTHON_BIN" -I "$HERE/compare.py" --mode "$MODE"
