#!/usr/bin/env bash
# test_desk_bash_fg_gate.sh — desk 전경 명령 30초 상한 훅 시험 (R241 · DESIGN-r241-desk-never-stall §4)
# 격리: 임시 루트(FT_ROOT) + 테스트 tmux 서버(-L 소켓). 판단 근거 = 도구 입력의 run_in_background·timeout 두 값뿐.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="${FT_HK_PATH:-$ROOT/harness/kit/hooks/desk-bash-fg-gate.sh}"   # r609: FT_HK_PATH = 실패 시험 먼저(base 판)
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; SOCK="r241fg$$"; mkdir -p "$T/.fable-team"
tm() { tmux -L "$SOCK" "$@"; }
cleanup() { tm kill-session -t 'desk-r241t#1' 2>/dev/null; tm kill-session -t 'other-r241t#1' 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
printf '{"_desk":"desk-r241t#1"}\n' > "$T/.fable-team/seats-planner.json"
tm -f /dev/null new-session -d -s 'desk-r241t#1' -x 80 -y 24 'sleep 120'
tm new-session -d -s 'other-r241t#1' -x 80 -y 24 'sleep 120'
env_for() { echo "TMUX=$(tm display-message -p -t "$1" '#{socket_path}'),0,0 TMUX_PANE=$(tm display-message -p -t "$1" '#{pane_id}')"; }
mk() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":json.loads(sys.argv[1])}))' "$1"; }
run() {  # $1 = 세션(빈 값 = tmux 정보 없음) · $2 = tool_input JSON
  local e=""; [ -n "$1" ] && e="$(env_for "$1")"
  out="$(mk "$2" | env -u TMUX -u TMUX_PANE $e FT_ROOT="$T" FT_DESK_LOG="$T/desk.log" bash "$HK" 2>"$T/err")"; rc=$?
}
denied() { [ "$rc" = 0 ] && grep -q '"permissionDecision": "deny"' <<<"$out"; }
allowed() { [ "$rc" = 0 ] && [ -z "$out" ]; }
D='desk-r241t#1'

bash -n "$HK" 2>/dev/null; ck "bash -n" $?
run "$D" '{"command":"sleep 100","run_in_background":true}'; allowed; ck "① desk·백그라운드 → 허용" $?
run "$D" '{"command":"ls","timeout":30000}'; allowed; ck "② desk·timeout 30000 → 허용" $?
run "$D" '{"command":"ls","timeout":30001}'; denied && grep -q 'R241' <<<"$out" && grep -q 'run_in_background' <<<"$out"; ck "③ desk·timeout 30001 → deny(사유에 run_in_background 안내)" $?
run "$D" '{"command":"ls"}'; denied; ck "④ desk·timeout 없음(기본 120초) → deny" $?
run "$D" '{"command":"ls","timeout":600000}'; denied; ck "⑤ desk·timeout 600000 → deny" $?
# r609 ⓓ — 거절 문구가 승계를 직접 말한다(판정 식 불변 · 문구만)
run "$D" '{"command":"ft-successor-open.sh old wt --name new","timeout":60000}'; denied && grep -qF '승계(ft-successor-open)·시험처럼 30초 넘는 일 = run_in_background: true' <<<"$out"; ck "⑤-2 r609 승계 30초 초과 → deny 문구에 «승계(ft-successor-open)…= run_in_background: true»" $?
run "$D" '{"command":"ls","timeout":0}'; denied; ck "⑥ desk·timeout 0 → deny(값이 아니라 기본으로 돈다)" $?
run "$D" '{"command":"ls","run_in_background":false,"timeout":30000}'; allowed; ck "⑦ desk·background=false + timeout 30000 → 허용" $?
run 'other-r241t#1' '{"command":"ls"}'; allowed; ck "⑧ desk 아닌 좌석 → 허용(변경 0)" $?
mv "$T/.fable-team/seats-planner.json" "$T/sp.bak"; run "$D" '{"command":"ls"}'
allowed && grep -q 'seats-planner' "$T/desk.log"; ck "⑨ 명부 없음 → 허용 + 로그 1줄" $?
mv "$T/sp.bak" "$T/.fable-team/seats-planner.json"
: > "$T/desk.log"; run '' '{"command":"ls"}'; allowed && grep -q 'tmux' "$T/desk.log"; ck "⑩ 좌석 이름을 못 구함 → 허용 + 로그 1줄" $?
out="$(printf '' | env FT_ROOT="$T" bash "$HK" 2>/dev/null)"; rc=$?; allowed; ck "⑪ 빈 stdin → 허용" $?
out="$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"x"}}' | env $(env_for "$D") FT_ROOT="$T" bash "$HK" 2>/dev/null)"; rc=$?; allowed; ck "⑫ Bash 아닌 도구 → 허용" $?

echo "fail=$fail"; [ "$fail" = 0 ]
