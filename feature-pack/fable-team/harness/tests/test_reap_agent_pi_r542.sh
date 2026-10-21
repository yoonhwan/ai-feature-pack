#!/usr/bin/env bash
# test_reap_agent_pi_r542.sh — r542: 회수 판정기 한 곳에 «에이전트별 이름 집합»(--agent opencode|pi) · 나노 닫기가 pi 좌석도 회수 · 훅 이름 집합.
#   진짜 pi·opencode 실행 0 — 스텁 = 이름이 pi 인 bash 스크립트(sleep 루프) · tmux = 가짜(FT_TMUX_BIN) · 신호는 이 시험이 띄운 스텁에만 · 닫기 픽스처 = test_nano_close_fail_closed.sh 와 같은 꼴.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAP="${PI_REAP:-$HERE/../bin/ft-opencode-reap.sh}"
KITBIN="$HERE/../kit/fable-team/bin"
HOOK="$HERE/../kit/hooks/opencode-reap-check.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { for p in $(ps -axww -o pid=,command= | awk -v s="$T/" 'index($0, s) {print $1}'); do kill -9 "$p" 2>/dev/null; done; chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null; }
dead()  { local i; for i in 1 2 3 4 5 6 7 8 9 10; do alive "$1" || return 0; sleep 0.2; done; return 1; }

mkdir -p "$T/stub" "$T/oc" "$T/wt/.git" "$T/wt/sub" "$T/else" "$T/pids"
cat > "$T/stub/pi" <<'EOF'
#!/bin/bash
[ -n "${PI_PIDOUT:-}" ] && echo $$ > "$PI_PIDOUT"
[ "${STUB_NOTERM:-0}" = 1 ] && trap '' TERM
while :; do sleep 0.3; done
EOF
cat > "$T/tmux" <<'EOF'
#!/bin/bash
[ "$1" = list-panes ] || exit 0
[ -s "$FAKE_PANES" ] && { cat "$FAKE_PANES"; exit 0; }; echo "no server running on /tmp/fake"; exit 1
EOF
chmod +x "$T/stub/pi" "$T/tmux"
export FT_OC_STATE_DIR="$T/oc" FT_TMUX_BIN="$T/tmux" FAKE_PANES="$T/panes"
S=$'\t'; ST="$T/stub/pi"
pane() { local n="$1" d="$2"; shift 2
  ( cd "$d" && exec env "$@" bash -c 'PI_PIDOUT="$1-run" "$0" run & PI_PIDOUT="$1-serve" "$0" serve & wait' "$ST" "$T/pids/$n" ) & PANE=$!
  local i; for i in $(seq 1 30); do [ -s "$T/pids/$n-run" ] && [ -s "$T/pids/$n-serve" ] && break; sleep 0.1; done; }
orphan() { bash -c 'cd "$1" || exit 1; PI_PIDOUT="$2" nohup "$0" serve >/dev/null 2>&1 &' "$ST" "$2" "$T/pids/$1"
  local i; for i in $(seq 1 30); do [ -s "$T/pids/$1" ] && [ "$(ps -o ppid= -p "$(cat "$T/pids/$1")" | tr -d ' ')" = 1 ] && return 0; sleep 0.1; done; echo "FAIL 시험 준비: $1 이 부모를 잃지 않음"; fail=$((fail+1)); }
pid() { cat "$T/pids/$1"; }

bash -n "$REAP" && ok "bash -n ft-opencode-reap.sh" || bad "bash -n ft-opencode-reap.sh"
bash -n "$HOOK" && ok "bash -n opencode-reap-check.sh" || bad "bash -n opencode-reap-check.sh"
cmp -s "$REAP" "$KITBIN/ft-opencode-reap.sh" && ok "bin ↔ kit 짝 cmp0" || bad "bin ↔ kit 짝이 다르다"
out="$(bash "$REAP" 'seat#0' --agent bogus 2>&1)"; [ $? -eq 2 ] && ok "--agent bogus → rc 2(usage)" || bad "--agent bogus rc≠2 ← $out"

echo "== ⓐ 이름 집합이 opencode 고정이면 pi 는 조사 줄 0 (기본값 = opencode = 지금 동작 그대로)"
pane seat "$T/wt"; SEATP=$PANE; printf 'seat#0%s%s\n' "$S" "$SEATP" > "$T/panes"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt")"; rc=$?
[ $rc -eq 0 ] && has "$out" "REAPED seat#0 n=0 left=0 dry-run rc=0" "ⓐ 기본 opencode → 후보 0" || bad "ⓐ rc=$rc ← $out"
hasnt "$out" "pid=$(pid seat-run) " "ⓐ pi 는 기본값에서 후보 0(이름 고정)"

echo "== ⓑ --agent pi → 좌석 pane 나무의 pi 가 대상 · --apply → REAPED left=0 rc=0"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt" --agent pi)"; rc=$?
[ $rc -eq 0 ] && has "$out" "pid=$(pid seat-run) via=① agent=pi" "ⓑ 조사: 좌석 나무 run(① · 이름 표기 pi)" || bad "ⓑ rc=$rc ← $out"
has "$out" "pid=$(pid seat-serve) via=① agent=pi" "ⓑ 조사: 좌석 나무 serve(① · 이름 표기 pi)"
alive "$(pid seat-run)" && ok "ⓑ 조사는 kill 0" || bad "ⓑ 조사가 프로세스를 죽였다"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt" --agent pi --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "REAPED seat#0 n=2 left=0 rc=0" "ⓑ REAPED n=2 left=0 rc=0" || bad "ⓑ rc=$rc ← $out"
has "$out" "oc-kill pid=$(pid seat-run) via=①" "ⓑ oc-kill 줄(pi)"
for x in seat-run seat-serve; do dead "$(pid $x)" && ok "ⓑ $x 소멸" || bad "ⓑ $x 살아 있음"; done
hasnt "$out" "oc-kill pid=$SEATP " "ⓑ pane 셸(pi 아님) 은 kill-session 몫 — 신호 0"
kill "$SEATP" 2>/dev/null; wait "$SEATP" 2>/dev/null

echo "== ⓒ 다른 tmux 세션(aifp 좌석 흉내) 나무의 pi → 대상 0 · 생존 (남의 pi 0)"
pane other "$T/wt/sub"; OTHER=$PANE; printf 'seat#0%s%s\nother#0%s%s\n' "$S" "$OTHER" "$S" "$OTHER" > "$T/panes"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt" --agent pi --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "left=0 rc=0" "ⓒ 남의 것만 있으면 left=0" || bad "ⓒ rc=$rc ← $out"
for x in other-run other-serve; do alive "$(pid $x)" && ok "ⓒ 남의 pi $x 생존" || bad "ⓒ 남의 pi $x 가 죽었다"; done
kill "$OTHER" 2>/dev/null; wait "$OTHER" 2>/dev/null

echo "== ⓓ pid 파일 기록(시작 시각 일치) → 대상 · 기록 없이 cwd 로만 찾은 부모 잃은 pi → kill 0 + «주인 미확인» 줄"
: > "$T/panes"; pane seat4 "$T/else"; P4=$PANE; printf 'seat4#0%s%s\n' "$S" "$P4" > "$T/panes"
out="$(bash "$REAP" 'seat4#0' --agent pi --record)"; has "$out" "oc-record seat4#0 n=2" "ⓓ 기록 n=2(pi)"
kill "$P4"; wait "$P4" 2>/dev/null; : > "$T/panes"; sleep 0.3
[ "$(ps -o ppid= -p "$(pid seat4-serve)" | tr -d ' ')" = 1 ] && ok "ⓓ pane 셸 소멸 → pi 부모 잃음(ppid 1)" || bad "ⓓ ppid ≠ 1"
orphan o1 "$T/wt"                                       # 기록 없는 부모 잃은 pi · cwd ⊂ 좌석 워크트리
out="$(bash "$REAP" 'seat4#0' --wt "$T/wt" --agent pi)"; rc=$?
has "$out" "pid=$(pid seat4-serve) via=① agent=pi" "ⓓ 기록분 = 대상(pid 파일 · 기록 때의 via)"
has "$out" "pid=$(pid o1) via=미확인 owner=주인 미확인 agent=pi" "ⓓ 기록 없는 cwd 부모 잃은 pi = «주인 미확인» 조사 줄"
hasnt "$out" "pid=$(pid o1) via=③" "ⓓ 기록 없는 pi 는 ③ 대상 아님(cwd 로만 찾은 것)"
out="$(bash "$REAP" 'seat4#0' --wt "$T/wt" --agent pi --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "left=0 rc=0" "ⓓ 기록분 회수 left=0" || bad "ⓓ rc=$rc ← $out"
dead "$(pid seat4-serve)" && ok "ⓓ 기록된 pi 소멸" || bad "ⓓ 기록된 pi 살아 있음"
alive "$(pid o1)" && ok "ⓓ 주인 미확인 pi 생존(kill 0 · 승인 범위 밖)" || bad "ⓓ 주인 미확인 pi 가 죽었다"
hasnt "$out" "oc-kill pid=$(pid o1) " "ⓓ 주인 미확인 pi 에 신호 0"
kill -9 "$(pid o1)" 2>/dev/null

echo "== ⓔ 못 멈추면 REAPED left=<n> rc=1 · 나노 닫기는 CLOSE-FAIL(승인 조건 «못 끄면 닫기 실패»)"
pane seat3 "$T/wt"; P3=$PANE; printf 'seat3#0%s%s\n' "$S" "$P3" > "$T/panes"
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" 'seat3#0' --agent pi --apply)"; rc=$?
[ $rc -eq 1 ] && has "$out" "REAPED seat3#0 n=0 left=2 rc=1" "ⓔ left=2 rc 1" || bad "ⓔ rc=$rc ← $out"
has "$out" "oc-left pid=$(pid seat3-serve)" "ⓔ oc-left 줄"
kill "$P3" 2>/dev/null; wait "$P3" 2>/dev/null; : > "$T/panes"

echo "== ⓕ 나노 닫기: 명부 agent=pi → 회수 단계 --agent pi · agent=claude → 회수 호출 0 (픽스처 = fail_closed 꼴)"
SRC="$KITBIN"
mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*
REPO="$T/repo"; mkdir -p "$REPO/design"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
printf '| 팀 | 폴더 | 메모 |\n|---|---|---|\n| v65 | design/teams/v65/ | 이동 뒤 |\n| planner | design/planner/ | |\n' > "$REPO/design/TEAMS.md"
GIT add design/TEAMS.md && GIT commit -q -m "teams on main"
MAIN="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/.fable-team" "$REPO/design/teams/v65" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
LEDGER="$REPO/design/teams/v65/NANO-LEDGER-temp.md"
SEAT='byz-planner-nano-pi#0'; CARD="$REPO/design/planner/indices/진행/ovr.md"; SEATS="$REPO/.fable-team/seats-planner.json"
NW="$REPO/.worktrees/pi-ovr"; BR="fix/ovr-verdict"
GIT worktree add -q "$NW" -b "$BR"
git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" > "$SEATS"; chmod 644 "$SEATS"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; rm -rf "$T/wtclean"
  mkdir -p "$(dirname "$LEDGER")"; : > "$LEDGER"
  git -C "$REPO" update-ref refs/remotes/origin/main "$MAIN"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"; : > "$T/oc-args"
}
ocstub() { printf '#!/bin/sh\necho "$*" >> "%s/oc-args"\ncase "$*" in *--record*) echo "oc-record $1 n=1"; exit 0;; esac\necho "REAPED $1 n=1 left=%s rc=%s"; exit %s\n' "$T" "$1" "$1" "$1" > "$T/bin/ft-opencode-reap.sh"; chmod +x "$T/bin/ft-opencode-reap.sh"; }
ocseats() { printf '{"%s":{"role":"nano","agent":"%s","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" "$1" > "$SEATS"; }
closeoc() { run FT_OC_STATE_DIR="$T/oc" FT_NANO_LEDGER="$LEDGER" FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER_WT="$REPO" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR"; }
setup; ocseats pi; ocstub 0; out="$(closeoc)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "PI-REAPED $SEAT reap left=0 rc=0" "ⓕ pi 좌석 → PI-REAPED left=0 (rc 0)" || bad "ⓕ pi rc=$rc ← ${out:0:600}"
has "$(sed -n 1p "$T/oc-args")" "$SEAT --wt $NW --agent pi --record" "ⓕ 1번째 = --record(--agent pi · 같은 자리)"
has "$(sed -n 2p "$T/oc-args")" "$SEAT --wt $NW --agent pi --apply" "ⓕ 2번째 = --apply(--agent pi)"
has "$(cat "$T/tlog")" "kill-session" "ⓕ 회수는 세션 kill 뒤(kill-session 실행됨)"
setup; ocseats claude; ocstub 0; out="$(closeoc)"; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$T/oc-args" ] && ok "ⓕ claude 좌석(pid 파일 없음) → 회수 호출 0" || bad "ⓕ claude rc=$rc args=$(cat "$T/oc-args")"
hasnt "$out" "PI-REAPED" "ⓕ claude 좌석 → PI-REAPED 0"
setup; ocseats pi; ocstub 1; out="$(closeoc)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "CLOSE-FAIL reap left=1 rc=1" "ⓔⓕ pi left=1 → CLOSE-FAIL rc 1(못 끄면 닫기 실패)" || bad "ⓕ left=1 rc=$rc ← ${out:0:600}"
hasnt "$out" "PI-REAPED" "ⓕ CLOSE-FAIL 이면 PI-REAPED 0"
rm -f "$T/bin/ft-opencode-reap.sh"

echo "== ⓖ 기존 opencode 시험 base 대조 diff 0 (시험 파일 손대지 않음 + rc0)"
for t in test_opencode_reap.sh test_nano_close_fail_closed.sh; do
  bash "$HERE/$t" > "$T/$t.log" 2>&1 && ok "ⓖ $t rc=0" || bad "ⓖ $t rc≠0 ← $(tail -3 "$T/$t.log")"
done
change="$(git -C "$HERE" diff --name-only HEAD -- test_opencode_reap.sh test_nano_close_fail_closed.sh test_nano_close_rerun_early.sh test_seat_reap_left0.sh test_seat_reap_services.sh 2>/dev/null)"
[ -z "$change" ] && ok "ⓖ 기존 회수·닫기 시험 파일 변경 0(base 대조 = HEAD)" || bad "ⓖ 기존 시험 파일이 바뀌었다: $change"
hk() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" | bash "$HOOK"; }
orphan h1 "$T/else"
out="$(hk 'pi -p "hello"')"
has "$out" "[pi-reap-check] pi 고아" "ⓖ 훅: pi 실행 뒤 고아 → pi 분기 알림(kill 0)"
has "$out" "--agent pi --apply" "ⓖ 훅 회수 명령에 --agent pi"
alive "$(pid h1)" && ok "ⓖ 훅은 kill 0" || bad "ⓖ 훅이 죽였다"
for c in 'echo pi' 'pip install x' 'grep -n api notes.txt'; do out="$(hk "$c")"; [ -z "$out" ] && ok "ⓖ 훅 출력 0: $c" || bad "ⓖ «$c» → ${out:0:200}"; done
kill -9 "$(pid h1)" 2>/dev/null

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
