#!/bin/bash
# One-shot 1Password popup/timeout evidence probe (design arch-20261015-opa-popup-design-r4 §4.6).
#
#   bash probe.sh --python <absolute consumer python>   one run, at most 75 seconds in total
#   bash probe.sh --selftest ...                        test mode: PROBE_*/FAKE_* overrides are honoured
#
# What it does: registers one temporary launchd job (label com.airag.probe-opa-<id>, RunAtLoad once, no
# KeepAlive/StartInterval, streams to /dev/null) that runs `python -I probe.py --run <dir> --mode <mode>`,
# waits for its result file, removes the job and reports. The operating consumer is not touched and stays
# disabled. The only things ever stopped here: the probe's own launchd job (and only while the loaded job shows
# this run's own directory) and the processes the probe recorded itself (pid AND start time must still match).
# Shared 1Password daemons are never signalled. Every launchctl call is time-capped; nothing is retried.
#
# Time: run phase (start of script .. result) <= 60 s, clean-up + close + report <= 15 s => 75 s hard.
# Exit codes: 0 done, 1 result incomplete, 2 refused to start, 3 bootstrap failed, 4 leftover to check,
# 129/130/143 interrupted (clean-up runs first).

HERE="$(cd "$(dirname "$0")" && pwd -P)"
START=$SECONDS
SELFTEST=0
PYTHON_BIN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    --python) PYTHON_BIN="${2:-}"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "알 수 없는 인자입니다 (--help)."; exit 2 ;;
  esac
  shift
done

LABEL=""
PROBE_DIR=""
CLEANED=0
RESIDUAL=0
BOOTSTRAP_ATTEMPTED=0
LABEL_STATE=unknown
LABEL_OUT=""
PHASE_DEADLINE=0
LAUNCHCTL="launchctl"
UID_N="$(id -u)"

bounded() {  # $1 = cap in seconds, rest = command: prints its output; 124 = cut off (or no time left in the phase)
  local cap="$1" left
  shift
  left=$((PHASE_DEADLINE - SECONDS))
  [ "$left" -lt "$cap" ] && cap="$left"
  [ "$cap" -lt 1 ] && return 124
  "$PYTHON_BIN" -I "$HERE/probe.py" --bounded "$cap" -- "$@"
}

label_probe() {  # sets LABEL_STATE (loaded | absent | unknown) and LABEL_OUT; a failed lookup is never "absent"
  local rc
  LABEL_OUT="$(bounded "$T_CALL" "$LAUNCHCTL" print "gui/$UID_N/$LABEL")"; rc=$?
  if [ $rc -eq 0 ]; then LABEL_STATE=loaded
  elif [ $rc -ne 124 ] && [ $rc -ne 127 ] && printf '%s' "$LABEL_OUT" | grep -q 'Could not find service'; then LABEL_STATE=absent
  else LABEL_STATE=unknown
  fi
}

pid_matches() {  # $1 pid, $2 recorded "lstart comm"
  local current
  current="$(LC_ALL=C ps -o lstart=,comm= -p "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//')"  # C locale, as probe.py records it
  [ -n "$current" ] && [ "$current" = "$2" ]
}

stop_recorded_pids() {  # only processes this probe recorded, only while pid AND start time still match
  [ -n "$PROBE_DIR" ] && [ -f "$PROBE_DIR/pids.json" ] || return 0
  local lines pid want i
  lines="$(bounded 3 "$PYTHON_BIN" -I "$HERE/probe.py" --list-pids "$PROBE_DIR")"
  if [ "$SELFTEST" = 1 ] && [ -n "${PROBE_EXTRA_PIDS:-}" ]; then lines="$lines"$'\n'"$PROBE_EXTRA_PIDS"; fi
  while IFS='|' read -r pid want; do
    [ -n "$pid" ] || continue
    if [ "$SECONDS" -ge "$PHASE_DEADLINE" ]; then   # clean-up time is spent: report, do not act
      if pid_matches "$pid" "$want"; then echo "잔존 확인 필요: pid $pid (정리 시간 소진)"; RESIDUAL=1; fi
      continue
    fi
    pid_matches "$pid" "$want" || continue
    kill -TERM "$pid" 2>/dev/null
    i=0
    while [ $i -lt 20 ] && [ "$SECONDS" -lt "$PHASE_DEADLINE" ] && pid_matches "$pid" "$want"; do
      sleep 0.1; i=$((i + 1))
    done
    if pid_matches "$pid" "$want" && [ "$SECONDS" -lt "$PHASE_DEADLINE" ]; then
      kill -KILL "$pid" 2>/dev/null
      i=0
      while [ $i -lt 10 ] && [ "$SECONDS" -lt "$PHASE_DEADLINE" ] && pid_matches "$pid" "$want"; do
        sleep 0.1; i=$((i + 1))
      done
    fi
    if pid_matches "$pid" "$want"; then
      echo "잔존 확인 필요: pid $pid (공유 데몬은 종료하지 않음)"
      RESIDUAL=1
    fi
  done <<< "$lines"
}

cleanup() {  # idempotent; the caller must exit explicitly afterwards
  [ "$CLEANED" = 1 ] && return 0
  CLEANED=1
  RESIDUAL=0
  PHASE_DEADLINE=$((SECONDS + CLEAN_BUDGET))
  if [ "$BOOTSTRAP_ATTEMPTED" = 1 ]; then   # a label this run never tried to start is never touched
    label_probe
    if [ "$LABEL_STATE" = loaded ]; then
      if printf '%s' "$LABEL_OUT" | grep -qF -- "$PROBE_DIR"; then   # the loaded job shows this run's own directory
        bounded "$T_CALL" "$LAUNCHCTL" bootout "gui/$UID_N/$LABEL" >/dev/null   # once; never retried
        label_probe
        if [ "$LABEL_STATE" = unknown ]; then echo "unknown_check_required: $LABEL"; fi
        if [ "$LABEL_STATE" != absent ]; then echo "잔존 확인 필요: $LABEL"; RESIDUAL=1; fi
      else
        echo "잔존 확인 필요: $LABEL (이 실행이 등록한 job 인지 확인되지 않아 내리지 않음)"
        RESIDUAL=1
      fi
    elif [ "$LABEL_STATE" = unknown ]; then
      echo "unknown_check_required: $LABEL"
      echo "잔존 확인 필요: $LABEL"
      RESIDUAL=1
    fi
  fi
  stop_recorded_pids
  return $RESIDUAL
}

# Traps first, before any label or directory exists.
T_START="${PROBE_T_START:-10}"
T_RESULT="${PROBE_T_RESULT:-60}"
T_CLEAN="${PROBE_T_CLEAN:-15}"
T_CALL="${PROBE_T_CALL:-10}"
if [ "$T_CLEAN" -gt 5 ]; then CLEAN_BUDGET=$((T_CLEAN - 4)); else CLEAN_BUDGET=1; fi   # 4 s kept for close + report
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP
trap 'cleanup' EXIT

if [ "$SELFTEST" = 1 ]; then
  [ -n "${PROBE_LAUNCHCTL:-}" ] && LAUNCHCTL="$PROBE_LAUNCHCTL"
  BASE="${PROBE_BASE:-$HOME/.local/share/airag-probe}"
  [ -z "$PYTHON_BIN" ] && PYTHON_BIN="${PROBE_PYTHON:-}"
  JOB_PATH="$PATH"
  MODE=selftest
else
  if env | grep -Eq '^(PROBE_|FAKE_)'; then
    echo "PROBE_*/FAKE_* 재정의는 --selftest 에서만 허용됩니다. 실행하지 않습니다."
    exit 2
  fi
  BASE="$HOME/.local/share/airag-probe"
  JOB_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
  MODE=production
  [ -z "$PYTHON_BIN" ] && PYTHON_BIN="$HOME/.local/share/airag/runtime/bin/python"
fi
case "$PYTHON_BIN" in
  /*) ;;
  *) echo "consumer 런타임 python 의 절대경로가 필요합니다 (--python <절대경로>). 시작하지 않습니다."; exit 2 ;;
esac
if [ ! -f "$PYTHON_BIN" ] || [ ! -x "$PYTHON_BIN" ]; then
  echo "python 을 실행할 수 없습니다: 경로를 확인하세요 (--python <절대경로>). 시작하지 않습니다."
  exit 2
fi
if ! command -v "$LAUNCHCTL" >/dev/null 2>&1; then
  echo "unknown_check_required: launchctl 을 찾을 수 없습니다. 시작하지 않습니다."
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

PHASE_DEADLINE=$((START + T_RESULT))
label_probe
if [ "$LABEL_STATE" != absent ]; then
  [ "$LABEL_STATE" = unknown ] && echo "unknown_check_required: $LABEL"
  echo "라벨 상태를 '없음'으로 확인하지 못했습니다 ($LABEL_STATE). 어떤 job 도 건드리지 않고 시작하지 않습니다."
  exit 2
fi

xml_esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

write_plist() {
  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0">' '<dict>'
    printf '  <key>Label</key>\n  <string>%s</string>\n  <key>ProgramArguments</key>\n  <array>\n' "$(xml_esc "$LABEL")"
    for arg in "$PYTHON_BIN" -I "$HERE/probe.py" --run "$PROBE_DIR" --mode "$MODE"; do
      printf '    <string>%s</string>\n' "$(xml_esc "$arg")"
    done
    printf '  </array>\n  <key>RunAtLoad</key>\n  <true/>\n  <key>ProcessType</key>\n  <string>Background</string>\n'
    printf '  <key>StandardOutPath</key>\n  <string>/dev/null</string>\n'
    printf '  <key>StandardErrorPath</key>\n  <string>/dev/null</string>\n'
    printf '  <key>EnvironmentVariables</key>\n  <dict>\n    <key>PATH</key>\n    <string>%s</string>\n' "$(xml_esc "$JOB_PATH")"
    if [ "$SELFTEST" = 1 ]; then
      env | grep -E '^(PROBE_|FAKE_|HOME=)' | grep -v '^PROBE_EXTRA_PIDS=' | while IFS= read -r line; do
        printf '    <key>%s</key>\n    <string>%s</string>\n' "$(xml_esc "${line%%=*}")" "$(xml_esc "${line#*=}")"
      done
    fi
    printf '  </dict>\n</dict>\n</plist>\n'
  } > "$PROBE_DIR/job.plist"
}
write_plist

BOOTSTRAP_ATTEMPTED=1
bounded "$T_CALL" "$LAUNCHCTL" bootstrap "gui/$UID_N" "$PROBE_DIR/job.plist" >/dev/null
rc=$?
if [ $rc -eq 124 ]; then
  echo "bootstrap 이 시간 초과로 중단되었습니다 (자동 재시도 없음)."
  exit 3
elif [ $rc -ne 0 ]; then
  echo "bootstrap 에 실패했습니다."
  exit 3
fi

# Wait: <= T_START for the job to start (pids.json), and the whole run phase ends at START + T_RESULT.
T0=$SECONDS
RUN_DEADLINE=$((START + T_RESULT))
TIMED_OUT=0
while :; do
  if [ -f "$PROBE_DIR/result.json" ] && grep -q '"complete":true' "$PROBE_DIR/result.json"; then break; fi
  if [ ! -s "$PROBE_DIR/pids.json" ] && [ $((SECONDS - T0)) -ge "$T_START" ]; then TIMED_OUT=1; break; fi
  if [ "$SECONDS" -ge "$RUN_DEADLINE" ]; then TIMED_OUT=1; break; fi
  sleep 0.2
done
if [ "$TIMED_OUT" = 1 ]; then
  PHASE_DEADLINE=$((SECONDS + 2))
  bounded 2 "$PYTHON_BIN" -I "$HERE/probe.py" --close-timeout "$PROBE_DIR"
fi

cleanup
CLEAN_RC=$?
PHASE_DEADLINE=$((SECONDS + 2))
bounded 2 "$PYTHON_BIN" -I "$HERE/probe.py" --report "$PROBE_DIR"
REPORT_RC=$?
echo "결과 파일: $PROBE_DIR/result.json"
[ $CLEAN_RC -ne 0 ] && exit 4
[ $REPORT_RC -ne 0 ] && exit 1
exit 0
