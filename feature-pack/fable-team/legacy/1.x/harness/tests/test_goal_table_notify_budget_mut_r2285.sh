#!/usr/bin/env bash
# test_goal_table_notify_budget_mut_r2285.sh — r2285 변이(사본에서만) · 변이마다 원본으로 같은 사례 1회 더.
#   M1 공지를 표 출력 앞으로 되돌림 → ① FAIL
#   M2 받은 팀장 목록을 무시(전원 다시) → ② FAIL
#   M3 시간 상한을 끔 → ① FAIL
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
MAIN="$HERE/test_goal_table_notify_budget_r2285.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mutate() {  # <이름> <옛 글자> <새 글자> — bin 사본에 1곳 바꿈(정확히 1곳이 아니면 rc1)
  mkdir -p "$T/$1" && cp "$BIN"/*.py "$T/$1/" && python3 - "$T/$1/ft_goal_table.py" "$2" "$3" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    raise SystemExit(f"변이 자리 {s.count(old)}곳: {old}")
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
}
case_of() {  # <이름> <사례 기호> <CASES> <원본|변이 bin> — 그 사례 FAIL 줄 수
  GT_TOOL="$4/ft_goal_table.py" CASES="$3" bash "$MAIN" 2>&1 | grep -c "^FAIL $2"
}
run() {  # <이름> <사례 기호> <CASES> <옛 글자> <새 글자>
  if ! mutate "$1" "$4" "$5"; then bad "$1 변이 못 만듦"; return; fi
  local m o; m="$(case_of "$1" "$2" "$3" "$T/$1")"; o="$(case_of "$1" "$2" "$3" "$BIN")"
  [ "$m" -ge 1 ] && ok "$1 변이 → $2 FAIL ${m}줄" || bad "$1 변이인데 $2 통과"
  [ "$o" = 0 ] && ok "$1 원본 → $2 PASS" || bad "$1 원본인데 $2 FAIL ${o}줄"
}
run M1 ① 1 'lambda: render(defer=True)' 'render'
run M2 ② 12 'got = set() if bad else _sent_names(prev, fp)' 'got = set()'
run M3 ① 1 'if NOTIFY_BUDGET - (time.monotonic() - start) < NOTIFY_TIMEOUT:' 'if False:'
echo "== test_goal_table_notify_budget_mut_r2285: fail=$fail"
[ "$fail" = 0 ]
