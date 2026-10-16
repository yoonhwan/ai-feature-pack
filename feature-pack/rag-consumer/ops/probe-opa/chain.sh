#!/bin/bash
# Three-stage chain, run once by a human (design arch-20261015-opa-popup-design-r8 §4):
# N1 launchd probe -> N2 E1 terminal table -> N3 the same E1 under `taskpolicy -b`.
#
#   bash chain.sh [--python <absolute consumer python>] [--plan full|e1|probe|n4]
#   bash chain.sh --selftest --python <absolute python> ...     test mode: PROBE_* overrides are honoured
#
# The reviewed tools run unchanged; a stage starts only when the previous tool's exit code AND its closed-schema
# result file pass the gate. Whole run <= 240 s (full), 162 s (e1: N2+N3), 84 s (probe: N1). Ctrl-C stops it: the
# running tool cleans up itself, the rest is skipped. No `op` process is ever signalled.
#
# Exit codes: tool codes unchanged, 0 all passed, 2 refused, 5 gate stop, 6 tool overran, 7 skipped_budget,
# 130/143/129 interrupted.

HERE="$(cd "$(dirname "$0")" && pwd -P)"
SELFTEST=0
PYTHON_BIN=""
PLAN=full
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    --python) PYTHON_BIN="${2:-}"; shift ;;
    --plan) PLAN="${2:-}"; shift ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자입니다 (--help)."; exit 2 ;;
  esac
  shift
done
case "$PLAN" in
  full|e1|probe|n4) ;;
  *) echo "계획은 full, e1, probe, n4 중 하나여야 합니다. 시작하지 않습니다."; exit 2 ;;
esac

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

# The worker handles SIGINT/SIGTERM/SIGHUP itself (it forwards the signal once to the running tool), so it takes
# this process's place and receives the signals directly.
exec "$PYTHON_BIN" -I "$HERE/chain.py" --mode "$MODE" --python "$PYTHON_BIN" --plan "$PLAN"
