#!/usr/bin/env bash
# test_seat_close_dead_pi_r1679.sh — r1679: retire 가 «PI_DEAD(pi 좌석 tmux 없음)» 로 판정한 죽은 pi 좌석은 pane 이 없으므로 pane 결속 확인(ft_seat_bind)을 건너뛰고 NORECORD 로 닫는다. 살아 있는 pi 좌석의 결속 실패는 지금처럼 HELD rc3.
#   ⓐ 죽은 pi 좌석(retire NORECORD PI_DEAD rc0) → ft_seat_bind 호출 0 · rc0 · CLOSED · NORECORD 1줄 · _master 칸 비움(역할 칸 처리 불변) — DEAD=0 갈래(CLOSED-ROLE) 와 DEAD=1 갈래(CLOSED-DEAD) 둘 다
#   ⓐr 실 retire 사본 + 가짜 tmux «세션 없음» → 같은 닫힘(계약 문구가 실 retire 출력과 맞는다)
#   ⓑ 살아 있는 pi 좌석 ∧ 결속 실패 → HELD rc3 · 쓰기 0 ·  ⓒ retire 판정 불가(rc≠0) → HELD rc3 · bind 0
#   ⓓ claude 좌석 경로 불변(PI ADAPTER 밖 · bind 0) · ⓔ 짝 cmp0 · bash -n
#   ⓜ 변이 2/2 — M1 조건 삭제 → ⓐ 가 HELD 로 돌아감 · M2 조건을 «seat-close 자신의 DEAD=1 이면 건너뜀» 으로 → ⓒb(연결 실패) 가 닫힘으로 샘
# 모든 쓰기는 mktemp 리포·가짜 HOME·가짜 tmux(PATH 앞)·가짜 retire·가짜 ft_seat_bind 안 — 실 명부·실 tmux·실 좌석 0. sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; trap 'rm -rf "$T0"; exit 143' TERM INT HUP; T="$(cd "$T0" && pwd -P)"   # r1679 QA#6 — 70초 TERM 으로 끝나도 임시 폴더·가짜 세션이 남지 않는다
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← $(printf '%s' "$1" | head -2 | tr '\n' ' ')";; esac; }
J() { jq -r "$2" "$1"; }

echo "== ⓔ 짝 cmp0 · bash -n"
for f in ft-seat-close.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"; bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done

mkdir -p "$T/bin" "$T/rbin" "$T/fake" "$T/home" "$T/root" "$T/resume"
cp "$BIN/ft-seat-close.sh" "$BIN/ft_roster_lib.py" "$BIN/ft-harness-root.sh" "$BIN/ft-verdict-row.sh" "$BIN/ft-team-lib.sh" "$T/bin/"
cp "$BIN/ft-seat-retire.sh" "$BIN/ft_seat_bind.py" "$BIN/ft_seat_pi.py" "$BIN/ft_seat_pi_turn.py" "$BIN/ft_seat_codex.py" "$BIN/ft_roster_lib.py" "$BIN/ft-harness-root.sh" "$T/rbin/"   # ⓐr = 실 retire 사본(결속 판정기까지 자기 폴더에서 본다) · close 쪽은 가짜 결속기로 갈라 쓴다
printf '#!/usr/bin/env python3\nimport os,sys\nopen(os.environ["BIND_LOG"],"a").write(" ".join(sys.argv[1:])+"\\n")\nsys.exit(int(os.environ.get("FAKE_BIND_RC","1")))\n' > "$T/bin/ft_seat_bind.py"   # 가짜 결속 확인(호출 수 기록 · rc 는 FAKE_BIND_RC)
printf '#!/bin/sh\nprintf "%%s\\n" "${STUB_RETIRE_OUT:-}"\nexit "${STUB_RETIRE_RC:-0}"\n' > "$T/bin/stub-retire.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) n=""; for a in "$@"; do case "$a" in =*) n="${a#=}";; esac; done
               grep -qxF "kill-session -t =$n" "$TMUX_LOG" 2>/dev/null && exit 1
               case "${FAKE_TMUX:-alive}" in
                 alive) exit 0;;
                 dead) echo "can't find session: $n" >&2; exit 1;;
                 connfail) echo "error connecting to /tmp/tmux (Permission denied)" >&2; exit 1;;   # rc1 이지만 «그 세션이 없다» 는 말이 아니다
                 *) exit 2;;
               esac;;
  display) printf '%s %s\n' "$$" "$TWD" ;;
  list-sessions) printf '%s\n' ${FAKE_SESSIONS:-} ;;
  display-message) case "$*" in *session_attached*) echo 0;; *) echo caller#0;; esac;;   # r1839 사람 화면 0 = 지금 동작 그대로
  *) exit 0;;
esac
EOF
chmod +x "$T/bin/"*.sh "$T/fake/tmux"
REPO="$T/repo"; mkdir -p "$REPO/.fable-team" "$REPO/design/teams/planner"; git -C "$REPO" init -q -b main
printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/teams/planner/ | x | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '| 2400 | t | r1679 시험 |\n' > "$REPO/design/teams/planner/VERDICTS-planner-1.md"
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm ledger
export TMUX_LOG="$T/tmux.log" BIND_LOG="$T/bind.log" FT_ROOT="$T/root" ZC_RESUME_DIR="$T/resume" HOME="$T/home" FT_PI_SESSIONS="$T/home/.pi/agent/sessions" TWD="$T"
S="$REPO/.fable-team/seats.json"; : > "$TMUX_LOG"; : > "$BIND_LOG"
roster() { printf '{"_master":"%s","%s":{"role":"nano","agent":"%s","model":"m","tick":null,"index":"x.md"}}\n' "$1" "$1" "${2:-pi}" > "$S"; }   # <좌석> [agent] — _master 도 그 좌석(역할 칸 비움 확인)
binds() { grep -c . "$BIND_LOG" 2>/dev/null || true; }
run() { ( cd "$REPO" && env PATH="$T/fake:$PATH" FT_TEAMS_REF=main FT_SEAT_RETIRE_BIN="${RT_BIN:-$T/bin/stub-retire.sh}" FT_SEAT_REAP_BIN="$T/bin/ft-seat-reap.sh" FAKE_TMUX="${FAKE_TMUX:-alive}" "$@" 2>&1 ); }
close() { run bash "$T/bin/${CLOSE_BIN:-ft-seat-close.sh}" "$@"; }
win() { printf '%s\n' "$1" | grep -qE '^CLOSED-' && echo closed || echo notclosed; }

echo "== ⓐ 죽은 pi 좌석(retire PI_DEAD NORECORD rc0) → bind 0 · rc0 · NORECORD 1줄 · _master 비움"
roster pi#a1 pi
out="$(STUB_RETIRE_OUT="NORECORD pi#a1 pi 좌석 tmux 없음 — 산출 커밋 보존" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#a1 --reason "r1679 죽은 pi" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓐ rc 0 · CLOSED" "$rc $(win "$out")" "0 closed"
chk "ⓐ ft_seat_bind 호출 0(죽은 좌석 건너뜀)" "$(binds)" 0
chk "ⓐ NORECORD 줄 1개" "$(printf '%s\n' "$out" | grep -c '^NORECORD ')" 1
chk "ⓐ 명부 닫힘 · _master 칸 비움" "$(J "$S" '.["pi#a1"]|[.role,._closed.verdict]|join(",")') [$(J "$S" '._master')]" "stop-ready,2400 []"
roster pi#a2 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"
out="$(FAKE_TMUX=dead STUB_RETIRE_OUT="NORECORD pi#a2 pi 좌석 tmux 없음 — 산출 커밋 보존" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#a2 --reason "r1679 죽은 pi(DEAD=1)" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓐ(DEAD=1) rc 0 · CLOSED-DEAD · bind 0" "$rc $(printf '%s\n' "$out" | grep -oE '^CLOSED-DEAD pi#a2' | head -1) $(binds)" "0 CLOSED-DEAD pi#a2 0"
roster pi#a3 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"
out="$(FAKE_TMUX=dead RT_BIN="$T/rbin/ft-seat-retire.sh" FAKE_BIND_RC=1 close pi#a3 --reason "r1679 실 retire" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓐr 실 retire(세션 없음) rc 0 · CLOSED-DEAD · bind 0" "$rc $(win "$out") $(binds)" "0 closed 0"
has "$out" "pi 좌석 tmux 없음" "  └ 계약 문구가 실 retire 출력과 같다"

echo "== ⓑ 살아 있는 pi 좌석 ∧ 결속 실패 → HELD rc3 · 쓰기 0 / ⓒ retire 판정 불가 → HELD rc3 · bind 0"
roster pi#b1 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"
out="$(STUB_RETIRE_OUT="RESUME ok $T/resume/pi#b1.json" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#b1 --reason "r1679 산 좌석" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓑ rc 3 · HELD · bind 1회" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1) $(binds)" "3 HELD 1"
chk "ⓑ 명부 쓰기 0(role nano) · kill 0" "$(J "$S" '.["pi#b1"].role') $(grep -c '^kill-session' "$TMUX_LOG")" "nano 0"
roster pi#c1 pi; : > "$BIND_LOG"
out="$(STUB_RETIRE_OUT="REJECT Pi tmux 확인 실패 · minishell" STUB_RETIRE_RC=1 FAKE_BIND_RC=0 close pi#c1 --reason "r1679 판정 불가" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓒ rc 3 · HELD · bind 0(판정 불가를 닫지 않는다)" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1) $(binds)" "3 HELD 0"
chk "ⓒ 명부 role nano" "$(J "$S" '.["pi#c1"].role')" nano
roster pi#d1 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"
out="$(FAKE_TMUX=connfail STUB_RETIRE_OUT="RESUME ok $T/resume/pi#d1.json" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#d1 --reason "r1679 연결 실패" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓒb 연결 실패(DEAD=1)여도 HELD rc3 · bind 1" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1) $(binds)" "3 HELD 1"

echo "== ⓓ claude 좌석 경로 불변 — PI ADAPTER 밖(bind 0) · rc0"
roster cl#e1 claude; : > "$TMUX_LOG"; : > "$BIND_LOG"
out="$(STUB_RETIRE_OUT="RESUME ok $T/resume/cl#e1.json" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close cl#e1 --reason "r1679 claude" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓓ rc 0 · CLOSED · bind 0" "$rc $(win "$out") $(binds)" "0 closed 0"

echo "== ⓜ 변이 2/2 — 조건을 지우면 ⓐ 가 · 자신의 DEAD 로 가르면 ⓒb 가 무너진다"
mut() { python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
t = open(src, encoding="utf-8").read(); print(t.count(mark)); open(dst, "w", encoding="utf-8").write(t.replace(mark, repl))
PY
}
n="$(mut "$T/bin/ft-seat-close.sh" "$T/bin/m1.sh" 'if [ "$AGENT" = pi ] && [ "$rrc" = 0 ] && [ "$PI_DEADLY" = 0 ]; then' 'if [ "$AGENT" = pi ] && [ "$rrc" = 0 ]; then')"
chk "ⓜ1 표지 1줄(조건 삭제)" "$n" 1
roster pi#m1 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"; CLOSE_BIN=m1.sh
out="$(FAKE_TMUX=dead STUB_RETIRE_OUT="NORECORD pi#m1 pi 좌석 tmux 없음 — 산출 커밋 보존" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#m1 --reason "변이1" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓜ1 죽은 좌석이 HELD 로 돌아감(ⓐ FAIL)" "$rc $(win "$out")" "3 notclosed"
n="$(mut "$T/bin/ft-seat-close.sh" "$T/bin/m2.sh" '[ "$PI_DEADLY" = 0 ]' '[ "$DEAD" = 0 ]')"
chk "ⓜ2 표지 1줄(자신의 DEAD 로 가름)" "$n" 1
roster pi#m2 pi; : > "$TMUX_LOG"; : > "$BIND_LOG"; CLOSE_BIN=m2.sh
out="$(FAKE_TMUX=connfail STUB_RETIRE_OUT="RESUME ok $T/resume/pi#m2.json" STUB_RETIRE_RC=0 FAKE_BIND_RC=1 close pi#m2 --reason "변이2" --seats "$S" --verdict 2400)"; rc=$?
chk "ⓜ2 연결 실패가 닫힘으로 샘(ⓒb FAIL)" "$rc $(win "$out") $(binds)" "0 closed 0"
CLOSE_BIN=""; chk "변이는 사본에서만(본 파일 불변)" "$(grep -c 'PI_DEADLY' "$BIN/ft-seat-close.sh")" 2

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
