#!/usr/bin/env bash
# test_seat_close_pi_resume_r960.sh — r960 ⓒⓓⓕ: pi 좌석(agent=pi)은 재개 기록을 pi 세션 파일에서 만들고, 없으면 «산출 커밋 보존» 사유로 살아 있어도 닫는다.
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 HOME(~/.pi/agent/sessions) + 실제 ft-seat-retire/close 만 쓴다 — 실제 리포·명부·tmux·pi 세션은 건드리지 않는다.
# 축 ⓒ agent=pi · 살아 있는 좌석 · pane cwd 의 pi 세션 파일 1개 → RETIRED 경로 RESUME ok(engine=pi · jsonl=세션 파일) · CLOSED-ROLE rc 0 · 명부 닫힘
#    ⓒ2 세션 파일이 좌석 프로세스 시작 «전» → 그 파일은 이 좌석 것이 아니다(NORECORD)
#    ⓓ agent=pi 세션 파일 0 → NORECORD «pi 세션 없음 — 산출 커밋 보존» 인데도 닫기 진행(rc 0) · claude 좌석 같은 상황은 HELD rc 3(동작 불변)
#    ⓕ 변이: pi 갈래 끔 → ⓒ FAIL · claude NORECORD 수용으로 넓히면 ⓓ 의 claude 칸 FAIL ⓖ 키트 짝 cmp0 · bash -n · 줄 수 상한 · 600/300·외부 호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
J() { jq -r "$2" "$1"; }

echo "== ⓖ 키트 짝 cmp0 · bash -n · 줄 수 상한"
for f in ft-seat-retire.sh ft-seat-close.sh ft_roster_lib.py; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  case "$f" in *.sh) bash -n "$KIT/$f" && ok "bash -n $f" || bad "bash -n $f";; esac
done
chk "ft-seat-retire.sh ≤ 200줄" "$([ "$(wc -l < "$BIN/ft-seat-retire.sh")" -le 200 ] && echo yes || echo no)" yes
chk "ft-seat-close.sh ≤ 120줄" "$([ "$(wc -l < "$BIN/ft-seat-close.sh")" -le 120 ] && echo yes || echo no)" yes

mkdir -p "$T/bin" "$T/home"
cp "$BIN/ft-seat-close.sh" "$BIN/ft-seat-retire.sh" "$BIN/ft_seat_bind.py" "$BIN/ft_roster_lib.py" "$BIN/ft-harness-root.sh" "$T/bin/"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cat > "$T/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TMUX_LOG"
case "$1" in
  has-session) [ "${FAKE_SESSION:-1}" = 1 ];;                                  # 살아 있는 좌석인가
  display) printf '%s %s\n' "${FAKE_PANE_PID:-1}" "${FAKE_PANE_CWD:-/tmp}" ;;  # ft_roster_lib.pi_seat_resume 의 결속 조회
  show-options) exit 0;;                                                       # @zc_v65_active 없음
  set-option|kill-session) exit 0;;
  display-message) echo caller#0;;
esac
EOF
chmod +x "$T/bin/"*
REPO="$T/repo"; mkdir -p "$REPO/.fable-team"
git -C "$REPO" init -q -b main
export TMUX_LOG="$T/tmux.log" FT_ROOT="$T/root" ZC_RESUME_DIR="$T/resume" FT_PI_SESSIONS="$T/home/.pi/agent/sessions"
mkdir -p "$FT_ROOT" "$ZC_RESUME_DIR" "$FT_PI_SESSIONS/enc"
export HOME="$T/home"
SESS="$FT_PI_SESSIONS/enc/2026-10-26T10-00-00-000Z_aaaa.jsonl"
PDIR="$T/worktree"; mkdir -p "$PDIR"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S)"
pifile() {  # pifile <시각 문자열> [cwd] — pi 세션 파일 1개(첫 줄 type=session) · 나머지 줄은 안 읽힌다
  printf '{"type":"session","version":3,"id":"aaaa-1111","timestamp":"%s","cwd":"%s"}\n{"type":"session_info","name":"pi#0"}\n' "${1:-$NOW}" "${2:-$PDIR}" > "$SESS"; }
seats_pi() { printf '{"_master":"M#1","M#1":{"role":"master","tick":"t"},"%s":{"role":"nano","agent":"%s","model":"m","tick":null,"index":"x.md"}}\n' "${1:-pi#0}" "${2:-pi}" > "$REPO/.fable-team/seats.json"; }
run() { ( cd "$REPO" && env PATH="$T/bin:$PATH" TMUX_LOG="$TMUX_LOG" FT_ROOT="$FT_ROOT" ZC_RESUME_DIR="$ZC_RESUME_DIR" FT_PI_SESSIONS="$FT_PI_SESSIONS" HOME="$HOME" FT_SEAT_RETIRE_BIN="${RT_BIN:-$T/bin/ft-seat-retire.sh}" \
  FAKE_SESSION="${FAKE_SESSION:-1}" FAKE_PANE_PID="$$" FAKE_PANE_CWD="${FAKE_PANE_CWD:-$PDIR}" "$@" 2>&1 ); }
close() { run bash "$T/bin/${CLOSE_BIN:-ft-seat-close.sh}" "$@"; }
retire_rec() { run bash "$T/bin/${RETIRE_BIN:-ft-seat-retire.sh}" "$1" --record-only --verdict 2400 --seats "$REPO/.fable-team/seats.json"; }

echo "== ⓒ pi 좌석 · 살아 있음 · pane cwd 의 pi 세션 파일 1개 → RESUME ok + 닫힘 rc 0"
seats_pi pi#0 pi; pifile "$NOW"; : > "$TMUX_LOG"
out="$(retire_rec 'pi#0')"; rc=$?
chk "ⓒretire rc 0 · RESUME ok" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1-2)" "0 RESUME ok"
chk "ⓒ기록 engine=pi · jsonl=세션 파일" "$(J "$ZC_RESUME_DIR/pi#0.json" '[.engine,.jsonl]|join(" ")')" "pi $SESS"
chk "ⓒ기록 cwd= pane cwd · uuid" "$(J "$ZC_RESUME_DIR/pi#0.json" '[.cwd,.uuid]|join(" ")')" "$PDIR aaaa-1111"
out="$(close 'pi#0' --reason "r960 pi 닫기 시험" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓒclose rc 0 · CLOSED-ROLE record 경로" "$rc $(printf '%s' "$out" | grep -o "record=[^ ]*")" "0 record=$ZC_RESUME_DIR/pi#0.json"
chk "ⓒ명부 닫힘(stop-ready · _closed.verdict)" "$(J "$REPO/.fable-team/seats.json" '.["pi#0"]|[.role,._closed.verdict]|join(",")')" "stop-ready,2400"

echo "== ⓒ2 세션 파일이 좌석 프로세스 시작 «전» → 이 좌석 세션 아님(NORECORD)"
seats_pi pi#2 pi; pifile "2020-01-01T00:00:00"
out="$(retire_rec 'pi#2')"; rc=$?
chk "ⓒ2 rc 0 · NORECORD" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "0 NORECORD"
has "$out" "pi 세션 없음 — 산출 커밋 보존" "  └ 사유에 «pi 세션 없음 — 산출 커밋 보존»"
chk "ⓒ2 기록 파일 0" "$([ -f "$ZC_RESUME_DIR/pi#2.json" ] && echo yes || echo no)" no

echo "== ⓓ agent=pi · 세션 파일 0 → NORECORD 인데도 닫기 진행 / claude 는 HELD rc 3(불변)"
seats_pi pi#3 pi; rm -f "$SESS"; : > "$TMUX_LOG"
out="$(close 'pi#3' --reason "r960 pi 세션 없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓓpi rc 0 · CLOSED-ROLE record=NORECORD" "$rc $(printf '%s' "$out" | grep -o 'record=[^ ]*')" "0 record=NORECORD"
chk "ⓓpi 명부 닫힘" "$(J "$REPO/.fable-team/seats.json" '.["pi#3"].role')" stop-ready
seats_pi cl#4 claude; : > "$TMUX_LOG"
out="$(close 'cl#4' --reason "r960 claude 세션 없음" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓓclaude rc 3 · HELD(동작 불변)" "$rc $(printf '%s' "$out" | head -1 | cut -d' ' -f1)" "3 HELD"
chk "ⓓclaude 명부 안 닫힘 · kill 0" "$(J "$REPO/.fable-team/seats.json" '.["cl#4"].role') $(grep -c '^kill-session' "$TMUX_LOG" || true)" "nano 0"

echo "== ⓕ 변이 — pi 갈래를 끄면 ⓒ 가 무너지는가 · claude NORECORD 수용으로 넓히면 ⓓ 의 claude 칸이 무너지는가"
mutate() {  # mutate <원본> <사본> <표지> <바꿀 글> [sub] — 표지 줄을 바꾸거나(sub 없이) 표지 글자만 바꾼 사본
  python3 - "$1" "$2" "$3" "$4" "${5:-line}" <<'PY'
import sys
src, dst, mark, repl, mode = sys.argv[1:6]
txt = open(src, encoding="utf-8").read()
out, hit = [], 0
if mode == "sub":
    hit = txt.count(mark); txt = txt.replace(mark, repl)
else:
    for ln in txt.splitlines():
        if mark in ln: out.append(repl); hit += 1
        else: out.append(ln)
    txt = "\n".join(out) + "\n"
open(dst, "w", encoding="utf-8").write(txt)
print(hit)
PY
}
n="$(mutate "$T/bin/ft-seat-retire.sh" "$T/bin/ft-seat-retire.mut.sh" "# r960-mut:pi" "    pass")"
chk "변이 표지 r960-mut:pi 1줄" "$n" 1
seats_pi pi#5 pi; pifile "$NOW"; RT_BIN="$T/bin/ft-seat-retire.mut.sh"
out="$(close 'pi#5' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓕ pi 갈래 끔 → rc 3 HELD(ⓒ FAIL)" "$rc" 3
RT_BIN=""
n="$(mutate "$T/bin/ft-seat-close.sh" "$T/bin/ft-seat-close.mut.sh" '"0:0 NORECORD "*"pi 세션 없음"*)' '"0:0 NORECORD "*)' sub)"
chk "변이 표지 pi 세션 없음 case 1줄" "$n" 1
seats_pi cl#6 claude; CLOSE_BIN=ft-seat-close.mut.sh
out="$(close 'cl#6' --reason "변이" --seats "$REPO/.fable-team/seats.json" --verdict 2400)"; rc=$?
chk "ⓕ claude NORECORD 도 통과로 → rc 0 (ⓓ claude 칸 FAIL)" "$rc" 0
CLOSE_BIN=""

echo "== ⓖ 600/300 s · 외부 호출 0 (r960 새 줄)"
NEWL="$(grep 'r960\|pi_seat_resume\|PI_NOREC' "$BIN/ft-seat-retire.sh" "$BIN/ft-seat-close.sh" "$BIN/ft_roster_lib.py")"
hasnt_() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
hasnt_ "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt_ "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
