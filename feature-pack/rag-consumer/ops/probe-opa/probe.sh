#!/bin/bash
# One-shot 1Password popup/timeout evidence probe (design arch-20261015-opa-popup-design-r4 §4.6).
#
#   bash probe.sh [--python <absolute python>]          one run, at most 75 seconds in total
#   bash probe.sh --selftest ...                        test mode: PROBE_*/FAKE_* overrides are honoured
#
# What it does: registers one temporary launchd job (label com.airag.probe-opa-<id>, RunAtLoad once, no
# KeepAlive/StartInterval, streams to /dev/null) that runs probe.py, waits for its result file, removes the
# job and reports. The operating consumer is not touched and stays disabled. Nothing is ever deleted here
# except by `launchctl bootout` of the probe's own label and TERM/KILL of the processes the probe recorded
# itself (pid + start time must still match). Shared 1Password daemons are never signalled.
#
# Exit codes: 0 done, 1 result incomplete, 2 refused to start, 3 bootstrap failed, 4 leftover to check,
# 129/130/143 interrupted (clean-up runs first).

HERE="$(cd "$(dirname "$0")" && pwd -P)"
SELFTEST=0
PYTHON_BIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    --python) PYTHON_BIN="${2:-}"; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자입니다 (--help)."; exit 2 ;;
  esac
  shift
done

LABEL=""
PROBE_DIR=""
CLEANED=0
RESIDUAL=0
LAUNCHCTL="launchctl"
UID_N="$(id -u)"

label_state() {  # loaded | absent | unknown   (a failed lookup is never "absent")
  local out rc
  command -v "$LAUNCHCTL" >/dev/null 2>&1 || { echo unknown; return; }
  out="$("$LAUNCHCTL" print "gui/$UID_N/$LABEL" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then echo loaded
  elif printf '%s' "$out" | grep -q 'Could not find service'; then echo absent
  else echo unknown
  fi
}

pid_matches() {  # $1 pid, $2 recorded "lstart comm"
  local current
  current="$(ps -o lstart=,comm= -p "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//')"
  [ -n "$current" ] && [ "$current" = "$2" ]
}

stop_recorded_pids() {  # only processes this probe recorded, only while pid AND start time still match
  [ -n "$PROBE_DIR" ] && [ -f "$PROBE_DIR/pids.json" ] || return 0
  local pid want i
  while IFS='|' read -r pid want; do
    [ -n "$pid" ] || continue
    pid_matches "$pid" "$want" || continue
    kill -TERM "$pid" 2>/dev/null
    i=0
    while [ $i -lt 20 ] && [ "$SECONDS" -lt "$CLEAN_DEADLINE" ] && pid_matches "$pid" "$want"; do
      sleep 0.1; i=$((i + 1))
    done
    if pid_matches "$pid" "$want"; then
      kill -KILL "$pid" 2>/dev/null
      i=0
      while [ $i -lt 10 ] && pid_matches "$pid" "$want"; do sleep 0.1; i=$((i + 1)); done
    fi
    if pid_matches "$pid" "$want"; then
      echo "잔존 확인 필요: pid $pid (공유 데몬은 종료하지 않음)"
      RESIDUAL=1
    fi
  done < <("$PYTHON_BIN" "$HERE/probe.py" --list-pids "$PROBE_DIR" 2>/dev/null)
}

cleanup() {  # idempotent; the caller must exit explicitly afterwards
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  RESIDUAL=0
  CLEAN_DEADLINE=$((SECONDS + ${T_CLEAN:-15}))
  if [ -n "$LABEL" ]; then
    local state
    state="$(label_state)"
    if [ "$state" != absent ] && command -v "$LAUNCHCTL" >/dev/null 2>&1; then
      "$LAUNCHCTL" bootout "gui/$UID_N/$LABEL" >/dev/null 2>&1   # once; never retried
      state="$(label_state)"
    fi
    if [ "$state" = unknown ]; then
      echo "unknown_check_required: $LABEL"
      echo "잔존 확인 필요: $LABEL"
      RESIDUAL=1
    elif [ "$state" = loaded ]; then
      echo "잔존 확인 필요: $LABEL"
      RESIDUAL=1
    fi
  fi
  stop_recorded_pids
  return $RESIDUAL
}

# Traps first, before any label or directory exists.
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP
trap 'cleanup' EXIT

if [ "$SELFTEST" = 1 ]; then
  export PROBE_SELFTEST=1
  [ -n "${PROBE_LAUNCHCTL:-}" ] && LAUNCHCTL="$PROBE_LAUNCHCTL"
  BASE="${PROBE_BASE:-$HOME/.local/share/airag-probe}"
  [ -z "$PYTHON_BIN" ] && PYTHON_BIN="${PROBE_PYTHON:-}"
  JOB_PATH="$PATH"
else
  if env | grep -Eq '^(PROBE_|FAKE_)'; then
    echo "PROBE_*/FAKE_* 재정의는 --selftest 에서만 허용됩니다. 실행하지 않습니다."
    exit 2
  fi
  BASE="$HOME/.local/share/airag-probe"
  JOB_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
fi
T_START="${PROBE_T_START:-10}"
T_RESULT="${PROBE_T_RESULT:-60}"
T_CLEAN="${PROBE_T_CLEAN:-15}"
[ -z "$PYTHON_BIN" ] && PYTHON_BIN="$(command -v python3)"

if ! command -v "$LAUNCHCTL" >/dev/null 2>&1; then
  echo "unknown_check_required: launchctl 을 찾을 수 없습니다. 시작하지 않습니다."
  exit 2
fi
if [ -z "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
  echo "python 을 찾을 수 없습니다 (--python <절대경로>). 시작하지 않습니다."
  exit 2
fi
if [ -L "$BASE" ] || [ -L "$(dirname "$BASE")" ]; then
  echo "점검 폴더의 위치가 심링크입니다. 시작하지 않습니다."
  exit 2
fi
mkdir -p -m 700 "$BASE" || exit 2
ID="$(date +%Y%m%d-%H%M%S)-$$-$RANDOM"
PROBE_DIR="$BASE/$ID"
mkdir -m 700 "$PROBE_DIR" || { PROBE_DIR=""; echo "점검 폴더가 이미 있습니다. 시작하지 않습니다."; exit 2; }
LABEL="com.airag.probe-opa-$ID"

state="$(label_state)"
if [ "$state" != absent ]; then
  [ "$state" = unknown ] && echo "unknown_check_required: $LABEL"
  echo "라벨 상태를 '없음'으로 확인하지 못했습니다 ($state). 시작하지 않습니다."
  exit 2
fi

xml_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

write_plist() {
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0">' '<dict>'
    printf '  <key>Label</key>\n  <string>%s</string>\n  <key>ProgramArguments</key>\n  <array>\n' "$(xml_esc "$LABEL")"
    for arg in "$PYTHON_BIN" "$HERE/probe.py" --run "$PROBE_DIR"; do
      printf '    <string>%s</string>\n' "$(xml_esc "$arg")"
    done
    printf '  </array>\n  <key>RunAtLoad</key>\n  <true/>\n  <key>ProcessType</key>\n  <string>Background</string>\n'
    printf '  <key>StandardOutPath</key>\n  <string>/dev/null</string>\n'
    printf '  <key>StandardErrorPath</key>\n  <string>/dev/null</string>\n'
    printf '  <key>EnvironmentVariables</key>\n  <dict>\n    <key>PATH</key>\n    <string>%s</string>\n' "$(xml_esc "$JOB_PATH")"
    if [ "$SELFTEST" = 1 ]; then
      env | grep -E '^(PROBE_|FAKE_|HOME=)' | while IFS= read -r line; do
        printf '    <key>%s</key>\n    <string>%s</string>\n' "$(xml_esc "${line%%=*}")" "$(xml_esc "${line#*=}")"
      done
    fi
    printf '  </dict>\n</dict>\n</plist>\n'
  } > "$PROBE_DIR/job.plist"
}
write_plist

if ! "$LAUNCHCTL" bootstrap "gui/$UID_N" "$PROBE_DIR/job.plist" >/dev/null 2>&1; then
  echo "bootstrap 에 실패했습니다."
  exit 3
fi

# Wait: <= T_START for the job to start (pids.json), <= T_RESULT in total for a complete result.
T0=$SECONDS
TIMED_OUT=0
while :; do
  if [ -f "$PROBE_DIR/result.json" ] && grep -q '"complete":true' "$PROBE_DIR/result.json"; then break; fi
  if [ ! -s "$PROBE_DIR/pids.json" ] && [ $((SECONDS - T0)) -ge "$T_START" ]; then TIMED_OUT=1; break; fi
  if [ $((SECONDS - T0)) -ge "$T_RESULT" ]; then TIMED_OUT=1; break; fi
  sleep 0.2
done
[ "$TIMED_OUT" = 1 ] && "$PYTHON_BIN" "$HERE/probe.py" --close-timeout "$PROBE_DIR"

cleanup
CLEAN_RC=$?
"$PYTHON_BIN" "$HERE/probe.py" --report "$PROBE_DIR"
REPORT_RC=$?
echo "결과 파일: $PROBE_DIR/result.json"
[ $CLEAN_RC -ne 0 ] && exit 4
[ $REPORT_RC -ne 0 ] && exit 1
exit 0
