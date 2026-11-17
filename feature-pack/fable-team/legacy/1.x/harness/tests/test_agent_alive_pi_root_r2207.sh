#!/usr/bin/env bash
# test_agent_alive_pi_root_r2207.sh — r2207: ft2 가 pi 를 pane 뿌리로 바로 띄운다. 쉬는 pi 는 자손 0 이라 «그 밖» 갈래에서 NOAGENT 였다.
#   고친 뒤: claude·codex 가 아닌 좌석에서 root 자신의 실행 주체가 pi(정지 T·좀비 Z 아님)면 root 를 본체로 본다. 그 밖 뿌리는 그대로.
#   ② root «pi»(+ 실 ps 꼴 뒤 공백) 자손 0 전경 node → ALIVE body=root ③ root «node /…/bin/pi» → ALIVE
#   ④ root «pi» T → NOAGENT ⑤ root «less» 전경 less → NOAGENT ⑥ root «pi» 전경 zsh → NOAGENT (① = test_agent_alive_fg_judge.sh 재실행)
# 가짜 tmux(export -f) + 가짜 ps(FT_PS_CMD) — 실 tmux·실 좌석 0 · sleep 0. 쓰기는 mktemp scratch 만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
AL="${AL_UNDER_TEST:-$HERE/../comm/ft-agent-alive.sh}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (got=[$2] want=[$3])"; fail=$((fail+1)); fi; }

mkdir -p "$T/comm"; cp "$AL" "$T/comm/ft-agent-alive.sh"
echo '{"_master":"other","other":{"role":"master","agent":"claude"}}' > "$T/seats.json"   # seatP 행 없음 → agent 빈 값(ft2 나노 꼴)
cat > "$T/fakeps" <<'S'
#!/bin/bash
case "$*" in *"pid=,ppid=,stat=,args="*) cat "$PS_ROWS";; *) exit 9;; esac
S
chmod +x "$T/fakeps"
tmux() {
  case "$1" in
    list-panes) printf 'seatP|%%7|100\n';;
    display-message) echo "$FAKE_FG";;
  esac; }
export -f tmux
export FT_PS_CMD="$T/fakeps" PS_ROWS="$T/ps.rows" FT_SEATS_JSON="$T/seats.json" TMPDIR="$T"

# 사례: 이름|root stat|root args|전경|기대 rc|기대 줄
run() {
  local name="$1" stat="$2" args="$3" fg="$4" want_rc="$5" want="$6" out rc
  printf '100 1 %s %s\n' "$stat" "$args" > "$T/ps.rows"
  out="$(FAKE_FG="$fg" bash "$T/comm/ft-agent-alive.sh" seatP 2>/dev/null)"; rc=$?
  chk "$name rc" "$rc" "$want_rc"
  case "$want" in *" body=*") out="${out% body=*} body=*";; esac   # body 칸을 보지 않는 사례(⑥ — 전경 셸이면 rc 만 계약)
  chk "$name 줄" "$out" "$want"
}
run "② pi 뿌리 · 자손 0 · 전경 node"        "Ss" "pi"                "node" 0 "ALIVE seat=seatP fg=node body=100"
run "② 실 ps 꼴 «pi» 뒤 공백 채움"          "Ss" "pi         "       "node" 0 "ALIVE seat=seatP fg=node body=100"
run "③ node /…/bin/pi 뿌리 · 자손 0"        "Ss" "node /opt/x/bin/pi" "node" 0 "ALIVE seat=seatP fg=node body=100"
run "④ pi 뿌리 정지 T"                       "T"  "pi"                "node" 1 "NOAGENT seat=seatP fg=node body=none"
run "⑤ less 뿌리 · 자손 0 · 전경 less"       "Ss" "less"              "less" 1 "NOAGENT seat=seatP fg=less body=none"
run "⑥ pi 뿌리 · 전경 zsh (O4)"              "Ss" "pi"                "zsh"  1 "NOAGENT seat=seatP fg=zsh body=*"

echo "FAIL $fail"
[ "$fail" -eq 0 ]
