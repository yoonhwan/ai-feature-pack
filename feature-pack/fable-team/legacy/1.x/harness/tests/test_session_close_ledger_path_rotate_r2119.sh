#!/usr/bin/env bash
# test_session_close_ledger_path_rotate_r2119.sh — r2119 세션 닫힘 원장 경로 박기 · 옛 줄 바꿈 · hook-status · 회전 · .1 읽기 반례 ①~⑨
#   (카드 design/harness/indices/대기/r2119-session-close-ledger-path-rotate.md · 사전 DA APPROVE ad75512d9a)
#   hook 칸 = 별도 소켓 실 tmux(`tmux -L r2119-<pid>` · 서버 cwd · HOME = 데이터 루트 밖 임시 폴더 · 끝에 그 서버만 내림)
#   데이터 루트 = 임시 git 리포(.fable-team/LIVE_ROOT → 임시 폴더) · 상한 = env FT_SESSION_CLOSE_LEDGER_MAX_KB=1(시험만)
#   실 원장 · 실 tmux 서버 · 실 hook 0 · sleep 0(hook 기다림 = 뒤 hook 줄 «wait-for -S» + `wait-for` + 원장 줄 수 보기)
#   R2119_BIN = 시험할 bin(기본 팩 harness/bin · 변이 사본 · 기준판 사본을 줄 때)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_SEAT FT_SESSION_CLOSE_ID \
  FT_SESSION_CLOSE_LEDGER FT_SESSION_CLOSE_LEDGER_HEX FT_SESSION_CLOSE_LEDGER_MAX_KB
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$(cd -- "${R2119_BIN:-$HERE/../bin}" && pwd)"; KIT="$HERE/../kit/fable-team/bin"; LED="$BIN/ft-session-close-ledger.sh"
REAL_TMUX="$(command -v tmux)"; SOCK="r2119-$$"
T="$(cd "$(mktemp -d)" && pwd -P)"
trap '( unset TMUX; "$REAL_TMUX" -L "$SOCK" kill-server 2>/dev/null ); rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T"' EXIT   # 그 서버와 그 소켓 파일만
fail=0; T0=$SECONDS; STAGES=""
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1:0:600}» ≠ «${2:0:600}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
stage(){ STAGES="$STAGES $1=$((SECONDS-T0))s"; T0=$SECONDS; echo "== $2"; }
nl()   { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
row()  { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }
age()  { python3 -c 'import os,sys,time; t=time.time()-int(sys.argv[2]); os.utime(sys.argv[1],(t,t))' "$1" "$2"; }   # 폴더 시각을 N초 전으로
REAL_HOOKS0="$(unset TMUX_PANE; "$REAL_TMUX" show-hooks -g 2>&1)"
ROOTS=""; r="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$r" ] && [ ! -e "$r/.fable-team/state/session-close" ] && ROOTS="$r"

# 데이터 루트 = 임시 git 리포의 LIVE_ROOT · 서버 cwd = 그 밖
R="$T/root"; REPO="$T/repo"; SRV="$T/srv"; mkdir -p "$R" "$REPO/.fable-team" "$SRV" "$T/tb"
git -C "$REPO" init -q 2>/dev/null; echo "$R" > "$REPO/.fable-team/LIVE_ROOT"; LR="$R/.fable-team/state/session-close/ledger.tsv"
printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$REAL_TMUX" "$SOCK" > "$T/tb/tmux"; chmod +x "$T/tb/tmux"
TB() { ( unset TMUX TMUX_PANE; PATH="$T/tb:$PATH"; export PATH; "$@" ); }
srv_up() { ( cd "$SRV" && HOME="$SRV" TB tmux -f /dev/null new-session -d -s keep cat ); }
LEDR() { ( cd "$REPO" && TB bash "$LED" "$@" ); }   # 데이터 루트 cwd 에서
mine() { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF "bash $LED hook #{q:hook_session} #{q:hook_session_name}\""; }
old()  { TB tmux show-hooks -g session-closed 2>/dev/null | grep -cxE "session-closed\[[0-9]+\] run-shell -b \"bash $(printf '%s' "$LED" | sed 's/[][\.*^$/]/\\&/g') hook #\{q:hook_session\} #\{q:hook_session_name\}\""; }
other(){ TB tmux show-hooks -g session-closed 2>/dev/null | grep -cF '@r2119_other'; }
OLD="run-shell -b \"bash $LED hook #{q:hook_session} #{q:hook_session_name}\""
wait_lines() { local e=$((SECONDS+4)); while [ "$(nl "$1")" -lt "$2" ]; do [ "$SECONDS" -ge "$e" ] && return 1; done; return 0; }
close_one() {
  TB tmux new-session -d -s "$1" cat
  TB tmux kill-session -t "=$1"
  ( unset TMUX; timeout 10 "$REAL_TMUX" -L "$SOCK" wait-for r2119-closed ); }
sync_tail() { TB tmux set-hook -ag session-closed 'wait-for -S r2119-closed'; }   # 내 줄 뒤에 기다림 줄

stage prep "①②③④ 경로 박기(C1) — 별도 소켓 실 tmux"
srv_up; TB tmux set-hook -g session-closed 'set-option -g @r2119_other 1'
eq "$(TB tmux show-environment -g 2>/dev/null | grep -c '^FT_SESSION_CLOSE_LEDGER')" 0 "① 서버 전역 env 에 FT_SESSION_CLOSE_LEDGER 없음"
o="$(LEDR hook-on 2>&1)"; r=$?; sync_tail
eq "$r|$o" "0|HOOK on $LR" "① 데이터 루트 cwd hook-on → rc 0 · «HOOK on <원장>»"
close_one c1; wait_lines "$LR" 1
eq "$(nl "$LR")|$(cut -f2,3 "$LR" 2>/dev/null | tr '\t' '|')" "1|hook|c1" "① 서버 cwd = 데이터 루트 밖 · env 없음 → 세션 1개 닫음 → 원장 hook 줄 1"
TB tmux set-environment -g FT_SESSION_CLOSE_LEDGER "$T/other.tsv"
close_one c2; wait_lines "$LR" 2
eq "$(nl "$LR")|$(nl "$T/other.tsv")" "2|0" "② 서버 전역 env = 다른 경로 → hook 줄은 박은 경로에만(박은 2 · 다른 경로 0)"
TB tmux set-environment -gu FT_SESSION_CLOSE_LEDGER
QD="$T/sp ace'q\$x \"d"; QL="$QD/l.tsv"; mkdir -p "$QD"
o="$(cd "$REPO" && FT_SESSION_CLOSE_LEDGER="$QL" TB bash "$LED" hook-on 2>&1)"; r=$?
eq "$r|$o|$(mine)" "0|HOOK on $QL|1" "③ 경로에 공백 · 작은따옴표 · \$ · 큰따옴표 → hook-on «HOOK on <경로 그대로>» · 내 줄 1"
close_one c3; wait_lines "$QL" 1
eq "$(nl "$QL")|$(cut -f3 "$QL" 2>/dev/null)|$(ls "$T" | tr '\n' ,)" "1|c3|repo,root,sp ace'q\$x \"d,srv,tb," "③ hook 줄 1 · 그 경로 그대로(다른 파일 · 폴더 생김 0)"
eq "$(LEDR hook-status 2>&1)" "HOOK on $QL" "③ hook-status «HOOK on <경로 그대로>»"
H0="$(TB tmux show-hooks -g session-closed 2>&1)"
o="$(cd "$SRV" && TB bash "$LED" hook-on 2>&1)"; r=$?
eq "$r|$o|$(TB tmux show-hooks -g session-closed 2>&1)" "1|판정 불가 원장 경로 못 풂|$H0" "④ 데이터 루트 못 푸는 cwd · env 없음 → rc 1 · «판정 불가 원장 경로 못 풂» 1줄 · show-hooks 바뀜 0"

stage c1 "⑤⑥⑦ 옛 줄 바꿈(C2) · hook-status(C3)"
TB tmux set-hook -gu session-closed; TB tmux set-hook -ag session-closed "$OLD"; TB tmux set-hook -ag session-closed 'set-option -g @r2119_other 1'
eq "$(old)|$(mine)|$(other)" "1|1|1" "⑤ 준비 = 옛 꼴 내 줄 1 · 남의 줄 1"
eq "$(LEDR hook-status 2>&1)" "HOOK on 경로 없음(옛 줄)" "⑦ 옛 꼴만 → «HOOK on 경로 없음(옛 줄)»"
o="$(LEDR hook-on 2>&1)"; r=$?
eq "$r|$(old)|$(mine)|$(other)|$(LEDR hook-status 2>&1)" "0|0|1|1|HOOK on $LR" "⑤ hook-on → 옛 꼴 0 · 내 줄 = 새 꼴 1 · 남의 줄 그대로 · «HOOK on <원장>»"
H1="$(TB tmux show-hooks -g session-closed 2>&1)"; o="$(LEDR hook-on 2>&1)"
eq "$(TB tmux show-hooks -g session-closed 2>&1)" "$H1" "⑤ 같은 경로 두 번째 hook-on → show-hooks 바뀜 0"
o="$(cd "$REPO" && FT_SESSION_CLOSE_LEDGER="$T/l5b.tsv" TB bash "$LED" hook-on 2>&1)"
eq "$(mine)|$(old)|$(other)|$(LEDR hook-status 2>&1)" "1|0|1|HOOK on $T/l5b.tsv" "⑤ 다른 경로 hook-on → 내 줄 1개(새 경로) · 남의 줄 그대로"
TB tmux set-hook -ag session-closed "$OLD"
eq "$(mine)|$(old)" "2|1" "⑥ 준비 = 옛 꼴 · 새 꼴 내 줄 둘 다"
o="$(LEDR hook-off 2>&1)"; r=$?
eq "$r|$o|$(mine)|$(other)" "0|HOOK off|0|1" "⑥ hook-off → 내 줄 0(옛 꼴 · 새 꼴) · 남의 줄 그대로"
eq "$(LEDR hook-status 2>&1)" "HOOK off" "⑦ 내 줄 없음 → «HOOK off»"
LEDR hook-on >/dev/null 2>&1; TB tmux kill-server 2>/dev/null; srv_up
eq "$(LEDR hook-status 2>&1)" "HOOK off" "⑦ 서버 다시 띄움 → «HOOK off»"

stage c2 "⑧ 회전(C4) — 상한 1 KiB"
export FT_SESSION_CLOSE_LEDGER_MAX_KB=1 FT_SESSION_CLOSE_ID=-
fill() { local i; mkdir -p "$(dirname -- "$1")"; : > "$1"; for i in $(seq 1 "$2"); do row 2026-11-16T20:00:00 hook S - - - '$1' - >> "$1"; done; }   # 1줄 38B
L="$T/r8a/l.tsv"; fill "$L" 30; echo "old one" > "$L.1"; cp "$L" "$T/r8a.orig"
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s8 t r >/dev/null 2>&1; r=$?
eq "$r|$(wc -c < "$T/r8a.orig" | tr -d ' ')|$(cmp -s "$L.1" "$T/r8a.orig" && echo same)|$(nl "$L")|$(cut -f2,3 "$L" | tr '\t\n' '|,')" "0|1140|same|1|tool|s8," "⑧ 1140B ≥ 1 KiB · .1 있음 → note 1번 → .1 = 옮기기 전 원장 바이트 그대로 · 본 원장 = 새 줄 1"
L="$T/r8b/l.tsv"; fill "$L" 10; FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s8 t r >/dev/null 2>&1
eq "$(nl "$L")|$([ -e "$L.1" ] && echo has1)" "11|" "⑧ 상한 미만 → 회전 0"
L="$T/r8c/l.tsv"; fill "$L" 30; mkdir "$L.lock"; age "$L.lock" 10
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s8 t r >/dev/null 2>&1; r=$?
eq "$r|$(nl "$L")|$([ -e "$L.1" ] && echo has1)|$([ -d "$L.lock" ] && echo lock)" "0|31||lock" "⑧ 잠금 10초 전 → 회전 0 · 줄은 씀 · 잠금 그대로"
L="$T/r8d/l.tsv"; fill "$L" 30
o="$(cd "$REPO" && FT_SESSION_CLOSE_LEDGER="$L" TB bash "$LED" hook-on 2>&1)"; mkdir "$L.lock"; age "$L.lock" 61
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s8 t r >/dev/null 2>&1; r1=$?
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" fail s8 t >/dev/null 2>&1; r2=$?
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" hook '$8' s8 >/dev/null 2>&1; r3=$?
eq "$r1$r2$r3|$(nl "$L")|$([ -e "$L.1" ] && echo has1)|$([ -d "$L.lock" ] && echo lock)" "000|33||lock" "⑧ 잠금 61초 전 → note · fail · hook 회전 0 · 줄은 씀 · 잠금 그대로(남의 잠금 지움 0)"
o="$(LEDR hook-status 2>&1)"; has "$o" "HOOK on $L · 잠금 남음 " "⑧ hook-status 끝 «· 잠금 남음 <초>초»"
o="$(cd "$REPO" && FT_SESSION_CLOSE_LEDGER="$L" TB bash "$LED" hook-on 2>&1)"
eq "$(printf '%s\n' "$o" | grep -c '잠금 회수')|$([ -e "$L.lock" ] && echo lock)" "1|" "⑧ 사람이 부르는 hook-on → 61초 넘은 잠금 0 · «잠금 회수» 1줄"
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note s8 t r >/dev/null 2>&1
eq "$(nl "$L.1")|$(nl "$L")" "33|1" "⑧ 다음 note → 회전 1(.1 = 33줄 · 본 = 1줄)"
L="$T/r8e/l.tsv"; fill "$L" 30; cp "$L" "$T/r8e.orig"; mkdir "$L.lock"; age "$L.lock" 61
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note A test reason >/dev/null 2>&1 & pa=$!
FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note B test reason >/dev/null 2>&1 & pb=$!
wait "$pa" "$pb"
eq "$([ -d "$L.lock" ] && echo lock)|$([ -e "$L.1" ] && echo has1)|$(cat "$L.1" "$L" 2>/dev/null | wc -l | tr -d ' ')|$(head -n 30 "$L" | cmp -s - "$T/r8e.orig" && echo keep)|$(cut -f3 "$L" | tail -n 2 | sort | tr '\n' ,)" \
  "lock||32|keep|A,B," "⑧ DA 입력(1140B · 1 KiB · 61초 전 빈 잠금 · writer A · B 동시) → 잠금 지움 0 · 회전 0 · 원래 30줄 + A + B"
# 동시 칸 ⓐ 끼어들기 고정: B 가 잠금 잡기 직전에 A 가 회전 · 쓰기를 끝냄(가짜 mkdir) → B 는 잠금 안에서 크기를 다시 봐야 .1 을 안 덮는다
L="$T/r8f/l.tsv"; fill "$L" 30; cp "$L" "$T/r8f.orig"; mkdir -p "$T/fm"
cat > "$T/fm/mkdir" <<'EOF'
#!/bin/bash
for a in "$@"; do case "$a" in *.lock) [ -e "$FM_ONCE" ] || { : > "$FM_ONCE"; PATH="$FM_PATH" bash "$FM_LED" note A test inner >/dev/null 2>&1; };; esac; done
exec /bin/mkdir "$@"
EOF
chmod +x "$T/fm/mkdir"
FM_ONCE="$T/fm/once" FM_PATH="$PATH" FM_LED="$LED" PATH="$T/fm:$PATH" FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note B test outer >/dev/null 2>&1
eq "$([ -e "$T/fm/once" ] && echo hit)|$(cmp -s "$L.1" "$T/r8f.orig" && echo same)|$(cut -f3 "$L" 2>/dev/null | tr '\n' ,)" "hit|same|A,B," \
  "⑧ 동시 ⓐ A 회전 뒤 B 잠금 → B 는 잠금 안 크기 다시 보기로 회전 0 · .1 = 원래 1140B · 본 = A · B"
# 동시 칸 ⓑ note 8개(상한 근처 988B)
L="$T/r8g/l.tsv"; fill "$L" 26; cp "$L" "$T/r8g.orig"; N0=26; pids=""
for i in 1 2 3 4 5 6 7 8; do FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" note "w$i" t r >/dev/null 2>&1 & pids="$pids $!"; done
wait $pids
eq "$(cat "$L.1" "$L" 2>/dev/null | wc -l | tr -d ' ')|$(cat "$L.1" "$L" 2>/dev/null | cut -f3 | grep -c '^w')|$(head -n "$N0" "$L.1" 2>/dev/null | cmp -s - "$T/r8g.orig" && echo keep)" "$((N0+8))|8|keep" \
  "⑧ 동시 ⓑ note 8개 → 줄 잃음 0(본 + .1 = 앞 줄 + 8) · .1 이 짧은 판으로 덮임 0"
unset FT_SESSION_CLOSE_LEDGER_MAX_KB FT_SESSION_CLOSE_ID

stage c4 "⑨ .1 읽기(C5)"
L="$T/r9/l.tsv"; mkdir -p "$T/r9"
row 2026-11-16T21:00:00 tool s9 ft-seat-close.sh 'seat#1' why '$9' 77 > "$L.1"; row 2026-11-16T21:00:01 hook s9 - - - '$9' - > "$L"
o="$(FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" read 2>&1)"
eq "$o" "$(printf '%s\n' '2026-11-16T21:00:01 s9 후보 ← ft-seat-close.sh · seat#1 · why' '닫힘 1 · 후보 1 · 도구 줄 없음 0 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0')" "⑨ .1 의 tool 줄 · 본 원장의 짝 hook 줄 → 짝 1 · 도구 줄 없음 0"
rm -f "$L.1"; row 2026-11-16T21:00:00 tool s9 ft-seat-close.sh 'seat#1' why '$9' 77 > "$L"; row 2026-11-16T21:00:01 hook s9 - - - '$9' - >> "$L"
row 2026-11-16T21:00:05 hook s10 - - - '$10' - >> "$L"
o="$(FT_SESSION_CLOSE_LEDGER="$L" bash "$LED" read 2>&1)"
eq "$o" "$(printf '%s\n' '2026-11-16T21:00:01 s9 후보 ← ft-seat-close.sh · seat#1 · why' '2026-11-16T21:00:05 s10 ← 도구 줄 없음' '닫힘 2 · 후보 1 · 도구 줄 없음 1 · hook 줄 없음 0 · kill 실패 0 · 깨진 줄 0')" "⑨ .1 없음 → 지금(r2101) 결과와 같음"

stage c5 "불변 · bin = kit · 실 상태"
TB tmux kill-server 2>/dev/null
eq "$(unset TMUX_PANE; "$REAL_TMUX" show-hooks -g 2>&1)" "$REAL_HOOKS0" "⑩ 실 tmux show-hooks -g 앞뒤 같음"
for r in $ROOTS; do [ ! -e "$r/.fable-team/state/session-close" ] && ok "⑩ $r/.fable-team/state/session-close 안 생김" || bad "⑩ 시험이 $r/.fable-team/state/session-close 를 만듦"; done
if [ -z "${R2119_BIN:-}" ]; then for f in ft-session-close-ledger.sh ft_session_close_read.py; do cmp -s "$BIN/$f" "$KIT/$f" && ok "⑩ bin = kit $f" || bad "⑩ bin ≠ kit $f"; done; fi
eq "$([ "$(wc -l < "$LED")" -le 200 ] && echo yes)" yes "⑩ ft-session-close-ledger.sh ≤ 200줄"

stage invariant "끝"
echo "STAGES$STAGES"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
