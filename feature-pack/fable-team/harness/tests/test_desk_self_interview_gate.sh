#!/usr/bin/env bash
# test_desk_self_interview_gate.sh — desk 화면 인터뷰 차단 훅 시험 (R241 · DESIGN-r241-desk-never-stall §1)
# 격리: 임시 루트(FT_ROOT) + 테스트 tmux 서버(-L 소켓) + 진짜 pty 클라이언트. 실 ~/.claude·실 tmux 서버 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/hooks/desk-self-interview-gate.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; SOCK="r241desk$$"; CTL="$T/ctl"; mkdir -p "$T/.fable-team" "$CTL"
tm() { tmux -L "$SOCK" "$@"; }
cleanup() { touch "$CTL/stop"; sleep 0.3; tm kill-session -t 'desk-r241t#1' 2>/dev/null; tm kill-session -t 'other-r241t#1' 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

printf '{"_desk":"desk-r241t#1"}\n' > "$T/.fable-team/seats-planner.json"
tm -f /dev/null new-session -d -s 'desk-r241t#1' -x 80 -y 24 'sleep 120'
tm new-session -d -s 'other-r241t#1' -x 80 -y 24 'sleep 120'
env_for() {  # $1 = 세션 → 그 pane 안에서 도는 것처럼 TMUX·TMUX_PANE 을 만든다
  echo "TMUX=$(tm display-message -p -t "$1" '#{socket_path}'),0,0 TMUX_PANE=$(tm display-message -p -t "$1" '#{pane_id}')"
}
ASK='{"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"q","header":"h","multiSelect":false,"options":[{"label":"a","description":"x"},{"label":"b","description":"y"}]}]}}'
run() {  # $1 = 세션(빈 값 = tmux 정보 없음) · 나머지 = 추가 env
  local s="$1"; shift
  local e=""; [ -n "$s" ] && e="$(env_for "$s")"
  out="$(printf '%s' "$ASK" | env -u TMUX -u TMUX_PANE $e FT_ROOT="$T" FT_DESK_LOG="$T/desk.log" "$@" bash "$HK" 2>"$T/err")"; rc=$?
}
denied() { [ "$rc" = 0 ] && grep -q '"permissionDecision": "deny"' <<<"$out"; }
allowed() { [ "$rc" = 0 ] && [ -z "$out" ]; }

bash -n "$HK" 2>/dev/null; ck "bash -n" $?

# ① desk + 클라이언트 없음 → deny, 사유에 «방 글(post)» 안내 · «reply --ts» 단독 지시 0 (r617)
run 'desk-r241t#1'; denied && grep -q 'post --to desk' <<<"$out" && grep -q 'R241' <<<"$out" && ! grep -q -- 'reply --ts' <<<"$out"; ck "① desk·클라이언트 없음 → deny(사유에 post --to desk · reply --ts 단독 지시 0)" $?

# ②a 클라이언트가 방금 붙었고 키 입력은 0(자동 attach) → deny — attach 시각이 «직접 키» 로 읽히면 안 된다(DA⑥ H1)
python3 -I "$HERE/pty_client.py" "$SOCK" 'desk-r241t#1' "$CTL" >/dev/null 2>&1 &
PP=$!; for _ in $(seq 1 50); do [ -e "$CTL/READY" ] && break; sleep 0.1; done
run 'desk-r241t#1'; denied; ck "②a attach 직후·키 0 → deny(client_activity == client_created)" $?
tm send-keys -t 'desk-r241t#1' x; run 'desk-r241t#1'; denied; ck "②b attach 뒤 send-keys 만 → deny(기계 입력은 직접 키가 아니다)" $?
# ②c attach 뒤 실제 pty 키 1 → 허용 (오빠가 desk 화면에서 방금 친 때)
sleep 1.2; touch "$CTL/press"; for _ in $(seq 1 50); do [ -e "$CTL/press" ] || break; sleep 0.1; done; sleep 0.3
run 'desk-r241t#1'; allowed; ck "②c attach 뒤 pty 키 입력 직후(600초 안) → 허용" $?
# ②d client_created 를 못 읽으면 예외 불성립(언제나 deny)
mkdir -p "$T/shim"; REAL_TMUX="$(command -v tmux)"
printf '#!/bin/bash\nif [ "$1" = list-clients ]; then echo "%s"; exit 0; fi\nexec %s "$@"\n' "$(date +%s)" "$REAL_TMUX" > "$T/shim/tmux"; chmod +x "$T/shim/tmux"  # activity 만 주고 created 는 안 주는 tmux
run 'desk-r241t#1' PATH="$T/shim:$PATH"; denied; ck "②d client_created 를 못 읽음 → deny(예외 불성립)" $?

# ③ send-keys 는 client_activity 를 바꾸지 않는다 — 바뀌면 예외(②)를 지워야 한다
A1="$(tm list-clients -t 'desk-r241t#1' -F '#{client_activity}' | head -1)"; sleep 1.2
tm send-keys -t 'desk-r241t#1' x; A2="$(tm list-clients -t 'desk-r241t#1' -F '#{client_activity}' | head -1)"
[ -n "$A1" ] && [ "$A1" = "$A2" ]; out="A1=$A1 A2=$A2"; ck "③ send-keys 전후 client_activity 불변($A1)" $?

# ④ 클라이언트는 붙어 있으나 마지막 입력이 창(FT_DESK_DIRECT_SEC) 밖 → deny
sleep 2.2; run 'desk-r241t#1' FT_DESK_DIRECT_SEC=1; denied; ck "④ 입력이 예외 창 밖(1초 창·2초 경과) → deny" $?
touch "$CTL/stop"; wait "$PP" 2>/dev/null

# ⑤ 다른 좌석 → 허용
run 'other-r241t#1'; allowed; ck "⑤ desk 아닌 좌석 → 허용(변경 0)" $?

# ⑥ 명부 없음 → 허용 + 로그
mv "$T/.fable-team/seats-planner.json" "$T/sp.bak"; run 'desk-r241t#1'
allowed && grep -q 'seats-planner' "$T/desk.log"; ck "⑥ 명부 없음 → 허용 + 로그 1줄" $?
mv "$T/sp.bak" "$T/.fable-team/seats-planner.json"

# ⑦ tmux 정보 없음(TMUX_PANE 없음) → 허용 + 로그
: > "$T/desk.log"; run ''
allowed && grep -q 'tmux' "$T/desk.log"; ck "⑦ 좌석 이름을 못 구함 → 허용 + 로그 1줄" $?

# ⑧ 빈 stdin·깨진 JSON → 허용
out="$(printf '' | env FT_ROOT="$T" bash "$HK" 2>/dev/null)"; rc=$?; allowed; ck "⑧ 빈 stdin → 허용" $?

echo "fail=$fail"; [ "$fail" = 0 ]
