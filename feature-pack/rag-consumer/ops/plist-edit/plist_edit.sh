#!/bin/bash
# Remove the top-level ProcessType entry from the operating consumer plist (design arch-20261016-opa-popup-design-r15
# §2.4 S0/S2 + errata §2). One run, no questions asked, nothing printed but key names and PASS/FAIL.
#
#   bash plist_edit.sh --python <absolute python>      the operating run (HIL: the human types the one line)
#   bash plist_edit.sh --python <absolute python> --selftest --plist F --backup-dir D --launchctl CMD [--plutil CMD]
#                                                      test mode: fixture paths only; the operating paths are refused
#
# What it does and what it never does: see plist_edit.py. In short: it checks (by reading only) that the job is not
# loaded and is disabled in launchd, backs the plist up (sha256 compared), edits a candidate, checks it, publishes it
# with one atomic rename, re-checks, and restores the backup if anything is off. It never changes launchd, never runs
# `op`, never touches the token file, the template or the runtime.
# The only process this wrapper ever signals is the python child it started itself.
#
# Exit codes: 0 done / already without the key, 2 usage or test-mode violation, 3 input refused, 4 launchd state not as
# required (nothing edited), 5 backup failed, 6 candidate check failed, 7 publish failed or the plist changed meanwhile,
# 8 post-check failed and the backup was restored, 9 restore failed (human decision, backup location printed),
# 130/143 interrupted (cleaned up; a published edit is restored first).

HERE="$(cd "$(dirname "$0")" && pwd -P)"
PYTHON_BIN=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --python) PYTHON_BIN="${2:-}"; shift ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
case "$PYTHON_BIN" in
  /*) [ -x "$PYTHON_BIN" ] || { echo "--python 이 실행할 수 없는 경로입니다. 시작하지 않습니다."; exit 2; } ;;
  *) echo "--python <절대 경로> 가 필요합니다. 시작하지 않습니다."; exit 2 ;;
esac

"$PYTHON_BIN" -I "$HERE/plist_edit.py" ${ARGS[@]+"${ARGS[@]}"} < /dev/null &
CHILD=$!
forward() { kill -s "$1" "$CHILD" 2>/dev/null; }
trap 'forward INT' INT
trap 'forward TERM' TERM
wait "$CHILD"
RC=$?
while kill -0 "$CHILD" 2>/dev/null; do  # a trapped signal ends the first wait early; the child is still cleaning up
  wait "$CHILD"
  RC=$?
done
exit "$RC"
