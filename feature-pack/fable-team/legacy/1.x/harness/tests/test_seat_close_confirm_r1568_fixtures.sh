#!/usr/bin/env bash
# test_seat_close_confirm_r1568_fixtures.sh — r1682: r1568 계열 시험 3파일이 함께 쓰는 픽스처·도구(사례 아님 · source 전용).
#   픽스처는 «스스로 멈춘다»: ① 멈춤 표식 $TMP/stop (cleanup 첫 줄 · guard) ② 부모 감시(kill -0 본체 — KILL 로 끊겨도 끝난다)
#   cleanup = 표식 → keeper·keep2 까지 → pgrep MKX 0 이 될 때까지 kill -9 되풀이(최대 10회) → 남으면 stderr 1줄
#   guard = 본체가 죽으면(EXIT·TERM·KILL 모두) cleanup 을 다시 돌리는 감시자 1개 — 임시 폴더·내 회차 tmux 까지 지운다
#   쓰기는 mktemp 안 · press 0 · 다른 회차·좌석 프로세스는 읽지도 죽이지도 않는다(MKX·tmux 이름 = 이 회차 pid)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; REAP="$BIN/ft-seat-reap.sh"; CLOSE="$BIN/ft-seat-close.sh"; BASH_X="$(command -v bash)"
TEST_PID=$$; T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MKX="r1568fx-$$-"
S="r1568t-$$#0"; S1="r1568t-$$#1"; SD="r1568d-$$#0"; SD1="r1568d-$$#1"; S3="r1568c-$$#0"; S4="r1568w-$$#0"
mkdir -p "$TMP/else" "$TMP/wt" "$TMP/mb" "$TMP/psbin" "$TMP/resume" "$TMP/cf/comm" "$TMP/faux"
git -C "$TMP/wt" init -q
export ZC_RESUME_DIR="$TMP/resume" FT_REAP_DEFER_DIR="$TMP/defer" FT_PERMIT_DIR="$TMP/permits" FT_BG_FINITE_LEDGER="$TMP/ledger.tsv"
export FT_PRESS_RUNNER_RE="r1568-never-$$" FT_SUCCESSOR_DIR="$TMP/succ" FT_MBOX_PY="$TMP/mbox-ok.py"
export FT_REAP_TERM_WAIT=0.15 FIX_STOP="$TMP/stop" FIX_PARENT="$TEST_PID"   # TERM 대기 0.15초 = 시험 전용(제품 기본 3초)
printf 'print("CLOSE-OK stub")\n' > "$TMP/mbox-ok.py"
printf '#!/bin/sh\necho "$*" >> %s/mbox.log\nexit 0\n' "$TMP/cf" > "$TMP/cf/comm/mbox.sh"
cleanup() { local s p x i left; : > "$TMP/stop" 2>/dev/null; pkill -f "$TMP/keeper.sh" 2>/dev/null; pkill -f "$TMP/keep2.sh" 2>/dev/null
  for s in "$S" "$S1" "$SD" "$SD1" "$S3" "$S4"; do tmux kill-session -t "=$s" 2>/dev/null; done
  i=0; while [ "$i" -lt 10 ]; do p="$(pgrep -f "$MKX" 2>/dev/null)"; [ -z "$p" ] && break; for x in $p; do kill -9 "$x" 2>/dev/null; done; sleep 0.1; i=$((i+1)); done
  left="$(pgrep -f "$MKX" 2>/dev/null | wc -l | tr -d ' ')"; [ "$left" != 0 ] && echo "cleanup: 남은 픽스처 $left (MKX=$MKX)" >&2
  rm -rf "$T0"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 143' TERM INT
# guard — 본체가 죽으면(EXIT·TERM·KILL·프로세스 묶음 KILL 모두) 정리한다. 묶음 밖(setpgrp)에서 기다리므로 묶음째 KILL 에도 살아남는다
cat > "$TMP/guard.sh" <<EOS
#!/bin/bash
trap '' TERM HUP INT
while st="\$(ps -o stat= -p $TEST_PID 2>/dev/null)"; [ -n "\$st" ] && [ "\${st#Z}" = "\$st" ]; do sleep 0.1; done
: > "$TMP/stop" 2>/dev/null; pkill -f "$TMP/keeper.sh" 2>/dev/null; pkill -f "$TMP/keep2.sh" 2>/dev/null
for s in "$S" "$S1" "$SD" "$SD1" "$S3" "$S4"; do tmux kill-session -t "=\$s" 2>/dev/null; done
for i in 1 2 3 4 5 6 7 8 9 10; do p="\$(pgrep -f "$MKX" 2>/dev/null)"; [ -z "\$p" ] && break; for x in \$p; do kill -9 "\$x" 2>/dev/null; done; sleep 0.1; done
rm -rf "$T0"
EOS
python3 -c 'import os,sys; os.setpgrp(); os.execv(sys.argv[1], sys.argv[1:])' "$BASH_X" "$TMP/guard.sh" >/dev/null 2>&1 &
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
nu()  { case "$1" in *"$2"*) bad "$3 — 있으면 안 되는 글자: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
endline() { tail -1 <<< "$1" | grep -oE 'left=[0-9?]+ rc=[0-9]+'; }
nkills() { grep '^reap-kill' <<< "$1" | grep -vc 'via=자손'; }
finish() { echo; if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "FAILED $fail"; exit 1; fi; }
mksess() {  # mksess <이름> <cwd> — pane 감시자가 본체를 지켜본다: 본체가 KILL 로 죽어도 세션이 스스로 닫힌다(고아 탭 0)
  #   read -t 는 bash 내장이라 pane 에 자식 프로세스가 없다(reap 후보 ① 은 «pane pid 의 자손» 만 본다)
  tmux new-session -d -s "$1" -c "$2" -e "FT_SEAT=$1" "$BASH_X" -c "exec 3<>'$TMP/sess.$$.fifo'; while kill -0 $TEST_PID 2>/dev/null; do read -t 0.2 -u 3 _ || :; done"; }

# faux 래퍼 — reap 의 ②b(argv) 규칙만 흉내낸다. --next 가 있으면 TERM 때 다음 세대를 낳고 죽는다(사슬 · h8128 꼴)
cat > "$TMP/faux/ft-bg-loop.sh" <<'EOS'
#!/bin/bash
seat=""; nxt=""; gen=0; max=0; tag=""
while [ $# -gt 0 ]; do case "$1" in --seat) seat="$2"; shift 2;; --next) nxt="$2"; shift 2;; --gen) gen="$2"; shift 2;; --max) max="$2"; shift 2;; *) tag="$1"; shift;; esac; done
should_stop() { [ -n "${FIX_STOP:-}" ] && [ -f "$FIX_STOP" ] && return 0; [ -n "${FIX_PARENT:-}" ] && ! kill -0 "$FIX_PARENT" 2>/dev/null && return 0; return 1; }
if [ -n "$nxt" ] && [ "$gen" -lt "$max" ]; then
  trap "should_stop && exit 0; nohup /bin/bash '$0' --seat '$seat' --gen $((gen+1)) --max '$max' --next '$nxt' '$nxt-$((gen+1))' </dev/null >/dev/null 2>&1 & exit 0" TERM
elif [ -n "${STUBBORN_ARM:-}" ]; then
  trap 'touch "$STUBBORN_ARM"; :' TERM   # TERM 을 «무시» — 표식 파일만 남기고 계속 산다(KILL 분기 재현)
fi
# 둘 다 아니면 기본 TERM(죽는다) — 서비스·짧은 자식 픽스처
while :; do should_stop && exit 0; sleep 0.05; done # $tag
EOS
pick() {  # pick <표식> — faux «본체» pid(래퍼 셸은 argv 가 «bash -c …» 라 걸러진다)
  pgrep -f "$1" | while read -r p; do ps -o command= -p "$p" 2>/dev/null | grep -qE '^[^ ]*bash [^ ]*faux/ft-bg-loop\.sh --seat ' && echo "$p"; done | head -1
}
spawn_faux() {  # spawn_faux <좌석> <표식> <표식파일|-> [--gen N --max M --next TAG] — 고아 1개
  local st="$1" tag="$2" arm="$3"; shift 3
  ( cd "$TMP/else" && if [ "$arm" = - ]; then nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$st" "$@" "$tag" </dev/null >/dev/null 2>&1 & else STUBBORN_ARM="$arm" nohup "$BASH_X" "$TMP/faux/ft-bg-loop.sh" --seat "$st" "$@" "$tag" </dev/null >/dev/null 2>&1 & fi )
  sleep 0.5
}
kill_mk() { local p; for p in $(pgrep -f "$1"); do kill -9 "$p" 2>/dev/null; done; }
wait_dead() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do [ -z "$(pgrep -f "$1")" ] && return 0; sleep 0.1; done; }

# 변이 사본 — bin 사본 + 문자열 1개 치환(못 찾으면 그 변이는 판정 불가 = FAIL)
mut() {  # mut <이름> <파일> <옛글자> <새글자>
  local d="$TMP/mb/$1"; mkdir -p "$d"
  cp "$BIN/ft-seat-reap.sh" "$BIN/ft-seat-close.sh" "$BIN/ft-leak-reap.sh" "$BIN/ft-bg-finite.sh" "$BIN/ft-harness-root.sh" "$BIN/ft_roster_lib.py" "$BIN/ft-verdict-row.sh" "$BIN/ft-team-lib.sh" "$d"/ 2>/dev/null
  python3 - "$d/$2" "$3" "$4" <<'PY'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mut: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PY
}
mut2() {  # mut2 <이름> <파일> <옛1> <새1> <옛2> <새2> — 변이 2단(한 갈래를 통째로 되돌린다)
  mut "$1" "$2" "$3" "$4" || return 1
  python3 - "$TMP/mb/$1/$2" "$5" "$6" <<'PYX'
import sys
p, o, n = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(o) != 1: print(f"mut2: «{o}» 개수 {s.count(o)}"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(o, n))
PYX
}
