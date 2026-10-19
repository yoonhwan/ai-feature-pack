#!/usr/bin/env bash
# test_seat_reap_left0.sh — r448: 좌석 닫기가 «그 좌석이 띄운 백그라운드 루프»를 멈추고 reap left=0 을 남긴다 + 감시 루프 래퍼·린트 + tmuxc FT_SEAT 상속.
#   ⓐ ft-seat-reap: ①pane 자손 2 ②FT_SEAT 고아 2 ③env 없는 cwd 고아 1 정지 · 남의 FT_SEAT·보호 exe 생존 · stopped=5 left=0 rc=0
#   ⓑ 못 멈춤(FT_REAP_NOSIGNAL) → left=1 rc=1 · ft-seat-close CLOSE-FAIL + 세션 생존 → 신호 켜면 CLOSED-SESSION … reap left=0 rc=0 · FT_SEAT 잔존 0
#   ⓒ ft-seat-retire(--orphans-only) reap 줄 · CLOSE-FAIL (nano-close 배선 = test_nano_close_fail_closed.sh ⓖ)
#   ⓓ ft-bg-loop max-sec·stop-file·cmd-exit · ft-bg-loop-lint 파일·--range · ⓔ 600/300 0 · tmuxc -e 상속 · GIT_* 0
# 실프로세스 픽스처 = 이 시험이 만든 tmux 세션 r448t-<pid>#0·#1 + 표식 r448fx-<pid> 를 argv 에 단 고아 루프만 — trap 이 세션 kill + 표식 프로세스 정리.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; TMUXC="$HERE/../../../tmuxc/core/bin/tmuxc"
REAP="$BIN/ft-seat-reap.sh"; LOOP="$BIN/ft-bg-loop.sh"; LINT="$BIN/ft-bg-loop-lint.sh"; CLOSE="$BIN/ft-seat-close.sh"; RETIRE="$BIN/ft-seat-retire.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r448fx-$$"
A="r448t-$$#0"; A1="r448t-$$#1"; B="r448u-$$#0"; E="r448e-$$#0"
cleanup() {   # 이 시험이 만든 세션 3 + 표식 프로세스만
  local s p; for s in "$A" "$A1" "$E"; do tmux kill-session -t "=$s" 2>/dev/null; done
  for p in $(pgrep -f "$MK"); do kill -9 "$p" 2>/dev/null; done
}
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
orphan() {  # orphan <cwd> <FT_SEAT|-> <실행 파일> <루프 본문> — ppid 1 고아 1개 · pid 출력
  local d="$1" s="$2" x="$3" body="$4"
  ( cd "$d" && if [ "$s" = - ]; then env -u FT_SEAT nohup "$x" -c "$body # $MK" >/dev/null 2>&1 & else FT_SEAT="$s" nohup "$x" -c "$body # $MK" >/dev/null 2>&1 & fi )
  sleep 0.4; pgrep -f "$body # $MK" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | tail -1
}
seat_procs() { ps -axEww -o pid=,command= | grep -E "FT_SEAT=$1( |$)" | grep -vc grep; }
mkdir -p "$TMP/wtA" "$TMP/else" "$TMP/pbin" "$TMP/resume"; git -C "$TMP/wtA" init -q
export ZC_RESUME_DIR="$TMP/resume" FT_SUCCESSOR_DIR="$TMP/succ"
BASH_X="$(command -v bash)"; ln -s "$BASH_X" "$TMP/pbin/headroom"   # 보호 exe(ft-leak-reap PROTECT_EXE «headroom») 꼴

for f in "$REAP" "$LOOP" "$LINT" "$CLOSE" "$RETIRE" "$BIN/ft-nano-close.sh" "$BIN/ft-merge-land.sh" "$TMUXC"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done
for f in ft-seat-reap.sh ft-bg-loop.sh ft-bg-loop-lint.sh ft-seat-close.sh ft-nano-close.sh ft-seat-retire.sh ft-merge-land.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" && ok "짝 cmp0 $f" || bad "짝 다름 $f"; done
PROBE="$(orphan "$TMP/else" probe-$$ "$BASH_X" 'while true; do sleep 1; : probe; done')"
ENVOK=0; ps -E -ww -o command= -p "$PROBE" | grep -q "FT_SEAT=probe-$$" && ENVOK=1; kill "$PROBE" 2>/dev/null
[ "$ENVOK" = 1 ] && ok "env 노출 확인($BASH_X)" || echo "INFO 이 머신은 $BASH_X 의 env 를 ps 로 못 읽음 — ② 는 ②b·③ 로만 잡힌다(아래 ② 기대값 건너뜀)"

echo "== ⓐ ft-seat-reap — ① pane 자손 · ② FT_SEAT 고아 2 · ③ cwd 고아 1 정지 · 남의 좌석·보호 exe 생존"
tmux new-session -d -s "$A" -c "$TMP/wtA" -e "FT_SEAT=$A"
tmux send-keys -t "=$A:" "bash -c 'sleep 120; :' $MK &" Enter; sleep 0.8
L1="$(orphan "$TMP/else" "$A" "$BASH_X" 'while true; do echo x >> l1.log; sleep 1; done')"
L2="$(orphan "$TMP/else" "$A" "$BASH_X" 'while true; do echo y >> l2.log; sleep 1; done')"
L3="$(orphan "$TMP/wtA" - /bin/sh 'while true; do sleep 1; done')"
LB="$(orphan "$TMP/wtA" "$B" "$BASH_X" 'while true; do echo b >> b.log; sleep 1; done')"
LP="$(orphan "$TMP/else" "$A" "$TMP/pbin/headroom" 'while true; do sleep 1; : prot; done')"
chk "ⓐ픽스처 고아 5(ppid 1)" "$([ -n "$L1" ] && [ -n "$L2" ] && [ -n "$L3" ] && [ -n "$LB" ] && [ -n "$LP" ] && echo 5)" 5
dry="$(bash "$REAP" "$A" --dry-run)"; rc=$?
chk "ⓐdry-run rc 0 · 정지 0" "$rc $(alive "$L1")" "0 alive"
has "$dry" "pid=$L3 via=③" "ⓐdry ③ cwd 고아"
grep -q "via=①" <<< "$dry" && ok "ⓐdry ① pane 자손" || bad "ⓐdry ① 없음 ← $dry"
[ "$ENVOK" = 0 ] || { has "$dry" "pid=$L1 via=②" "ⓐdry ② L1"; has "$dry" "pid=$L2 via=②" "ⓐdry ② L2"; }
case "$dry" in *"pid=$LB "*|*"pid=$LP "*) bad "ⓐdry 남의 좌석·보호 exe 가 후보에 ← $dry";; *) ok "ⓐdry 남의 좌석·보호 exe 후보 0";; esac
out="$(bash "$REAP" "$A")"; rc=$?
ST="$(tail -1 <<< "$out" | sed -n 's/.* stopped=\([0-9]*\) .*/\1/p')"   # ① bash+sleep 2 · ② 2 · ③ 1 = 5 · kill 직전에 루프가 낳은 sleep 고아를 2회전이 더 잡으면 6+
[ "$ENVOK" = 1 ] && chk "ⓐ끝 줄 stopped≥5 left=0 rc=0" "$rc $([ "${ST:-0}" -ge 5 ] && echo ge5) $(tail -1 <<< "$out" | grep -oE 'left=.*')" "0 ge5 left=0 rc=0" || has "$out" "left=0 rc=0" "ⓐ left=0 rc=0"
chk "ⓐA 루프 2 · cwd 고아 정지" "$(alive "$L1") $(alive "$L2") $(alive "$L3")" "dead dead dead"
chk "ⓐ남의 좌석 B · 보호 exe 생존" "$(alive "$LB") $(alive "$LP")" "alive alive"
chk "ⓐpane 자손 0 · 세션 생존" "$(pgrep -f "sleep 120; :" | wc -l | tr -d ' ') $(tmux has-session -t "=$A" 2>/dev/null && echo up)" "0 up"
kill "$LB" "$LP" 2>/dev/null

echo "== ⓑ 못 멈춤 → left=1 rc=1 · ft-seat-close CLOSE-FAIL(세션 생존) → 신호 켜면 CLOSED-SESSION … reap left=0 rc=0"
tmux new-session -d -s "$A1" -c "$TMP/else" -e "FT_SEAT=$A1"; : > "$ZC_RESUME_DIR/$A.json"   # 계보 최신 #1 + 재개 기록 = 표준승인 kill 범위
printf '{"%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}, "%s": {"role": "tester", "tick": null}}\n' "$A" "$A1" > "$TMP/seats.json"
L4="$(orphan "$TMP/else" "$A" "$BASH_X" 'while true; do echo z >> l4.log; sleep 1; done')"
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" "$A")"; rc=$?
[ "$ENVOK" = 0 ] || chk "ⓑNOSIGNAL rc 1 · left=1" "$rc $(tail -1 <<< "$out" | grep -oE 'left=[0-9]+ rc=[0-9]+')" "1 left=1 rc=1"
out="$(FT_REAP_NOSIGNAL=1 bash "$CLOSE" "$A" --reason "r448 시험" --seats "$TMP/seats.json" 2>/dev/null)"; rc=$?
[ "$ENVOK" = 0 ] || { chk "ⓑclose rc 1" "$rc" 1; has "$out" "CLOSE-FAIL reap left=1 rc=1" "ⓑCLOSE-FAIL reap left=1 rc=1"; chk "ⓑ세션 생존 · 루프 생존" "$(tmux has-session -t "=$A" 2>/dev/null && echo up) $(alive "$L4")" "up alive"; }
out="$(bash "$CLOSE" "$A" --reason "r448 시험" --seats "$TMP/seats.json" 2>/dev/null)"; rc=$?
chk "ⓑ신호 켬 → rc 0 · CLOSED-SESSION … kill=ok reap left=0 rc=0" "$rc ${out%% *} ${out##*kill=}" "0 CLOSED-SESSION ok reap left=0 rc=0"
chk "ⓑ세션 없음 · 루프 정지 · FT_SEAT=$A 잔존 0" "$(tmux has-session -t "=$A" 2>/dev/null && echo up || echo gone) $(alive "$L4") $(seat_procs "$A")" "gone dead 0"

echo "== ⓒ ft-seat-retire --orphans-only — 고아만 정지 · 살아 있는 좌석 세션 그대로 · 못 멈춤 = CLOSE-FAIL rc 1"
printf '{"%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$A1" > "$TMP/seats2.json"
L5="$(orphan "$TMP/else" "$A1" "$BASH_X" 'while true; do echo r >> l5.log; sleep 1; done')"
out="$(bash "$RETIRE" "$A1" "r448t-$$#2" --seats "$TMP/seats2.json" 2>/dev/null)"; rc=$?
chk "ⓒRETIRED · reap left=0 rc=0 · rc 0" "$rc $(grep -c '^RETIRED' <<< "$out") $(tail -1 <<< "$out")" "0 1 reap left=0 rc=0"
[ "$ENVOK" = 0 ] || chk "ⓒ고아 정지 · 세션 생존" "$(alive "$L5") $(tmux has-session -t "=$A1" 2>/dev/null && echo up)" "dead up"
L6="$(orphan "$TMP/else" "$A1" "$BASH_X" 'while true; do echo s >> l6.log; sleep 1; done')"
out="$(FT_REAP_NOSIGNAL=1 bash "$RETIRE" "$A1" "r448t-$$#2" --seats "$TMP/seats2.json" 2>/dev/null)"; rc=$?
[ "$ENVOK" = 0 ] || { chk "ⓒ못 멈춤 rc 1" "$rc" 1; has "$out" "CLOSE-FAIL reap left=1 rc=1" "ⓒCLOSE-FAIL reap left=1 rc=1"; }
kill "$L6" 2>/dev/null

echo "== ⓓ ft-bg-loop 래퍼 — max-sec · stop-file · cmd-exit · usage"
s=$SECONDS; out="$(bash "$LOOP" --seat "$E" --max-sec 3 --stop-file "$TMP/stop1" -- sh -c "while true; do echo x >> $TMP/bl1.log; sleep 1; done # $MK")"
chk "ⓓmax-sec 3 → 5 s 안 · reason=max-sec" "$([ $((SECONDS - s)) -le 5 ] && echo in) ${out%% sec=*}" "in bg-loop end reason=max-sec"
chk "ⓓ래퍼 끝난 뒤 자식 0" "$(pgrep -f "bl1.log; sleep 1; done # $MK" | wc -l | tr -d ' ')" 0
bash "$LOOP" --seat "$E" --max-sec 60 --stop-file "$TMP/stop2" -- sh -c "while true; do echo y >> $TMP/bl2.log; sleep 1; done # $MK" > "$TMP/bl2.out" & BP=$!
sleep 1; s=$SECONDS; : > "$TMP/stop2"; wait "$BP"
chk "ⓓstop-file → 1주기 안 · reason=stop-file" "$([ $((SECONDS - s)) -le 2 ] && echo in) $(cut -d' ' -f1-3 < "$TMP/bl2.out")" "in bg-loop end reason=stop-file"
out="$(bash "$LOOP" --seat "$E" --max-sec 60 --stop-file "$TMP/stop3" -- sh -c 'exit 3')"; rc=$?
chk "ⓓcmd-exit → rc 3 · reason=cmd-exit rc=3" "$rc ${out%% sec=*} ${out##* }" "3 bg-loop end reason=cmd-exit rc=3"
bash "$LOOP" --seat "$E" --stop-file "$TMP/s" -- true 2>/dev/null; chk "ⓓ--max-sec 없음 → usage rc 2" "$?" 2
bash "$LOOP" --seat "$E" --max-sec 5 -- true 2>/dev/null; chk "ⓓ--stop-file 없음 → usage rc 2" "$?" 2
bash "$LOOP" --seat "$E" --max-sec 60 --stop-file "$TMP/stop4" -- bash -c "while true; do sleep 1; done # $MK" >/dev/null & BW=$!
sleep 1; out="$(bash "$REAP" "$E")"; chk "ⓓreap 이 래퍼(②b argv --seat) 찾아 정지 · 자식 0" "$(grep -c "pid=$BW via=②b" <<< "$out") $(alive "$BW") $(pgrep -f "while true; do sleep 1; done # $MK" | wc -l | tr -d ' ') $(tail -1 <<< "$out" | grep -oE 'left=[0-9]+')" "1 dead 0 left=0"
wait "$BW" 2>/dev/null

echo "== ⓓ ft-bg-loop-lint — 래퍼 밖 루프 ERR(줄 번호) · 래퍼 안 OK · --range = 가지가 추가·수정한 design/·tests/e2e/ 만"
mkdir -p "$TMP/lint"
printf '#!/bin/zsh\nR=/tmp/x\nwhile [ ! -f $R/done.txt ]; do\n  echo "$(date +%%T)" >> $R/guard.log\n  sleep 5\ndone\n' > "$TMP/lint/guard.sh"   # room evidence guard.sh 꼴(옛 증거)
printf '#!/bin/sh\nwhile true; do echo x >> log; sleep 1; done &\n' > "$TMP/lint/one.sh"
printf '#!/bin/sh\nnohup ft-bg-loop.sh --seat "$ME" --max-sec 60 --stop-file done.txt -- sh -c '"'"'while true; do echo x >> log; sleep 1; done'"'"' &\nft-bg-loop.sh --seat "$ME" --max-sec 9 --stop-file d \\\n  -- sh -c '"'"'while :; do date >> l; sleep 2; done'"'"'\n' > "$TMP/lint/wrapped.sh"
printf '#!/bin/sh\n# while true; do echo x >> log; sleep 1; done\nwhile read -r l; do echo "$l" >> out; done < in\nfor i in 1 2; do sleep 1; done\n' > "$TMP/lint/clean.sh"
out="$(bash "$LINT" "$TMP/lint/guard.sh")"; rc=$?; chk "ⓓguard.sh 꼴 → ERR :3 · rc 1" "$rc $(grep -c "guard.sh:3 " <<< "$out") $(tail -1 <<< "$out")" "1 1 ERR bg-loop 1"
out="$(bash "$LINT" "$TMP/lint/one.sh")"; chk "ⓓ한 줄 루프 → ERR :2" "$(grep -c 'one.sh:2 ' <<< "$out")" 1
out="$(bash "$LINT" "$TMP/lint/wrapped.sh" "$TMP/lint/clean.sh")"; rc=$?; chk "ⓓ래퍼 안(같은 줄·\\ 이음) · 주석·sleep/>> 한쪽만 → OK rc 0" "$rc $out" "0 OK bg-loop 0"
out="$(bash "$LINT" "$TMP/lint")"; chk "ⓓ폴더 재귀 → ERR 2" "$(tail -1 <<< "$out")" "ERR bg-loop 2"
bash "$LINT" 2>/dev/null; chk "ⓓ인자 없음 usage rc 2" "$?" 2
R="$TMP/lrepo"; mkdir -p "$R/design/old" "$R/tests/e2e" "$R/kit"; git -C "$R" init -q -b main
G() { git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
cp "$TMP/lint/guard.sh" "$R/design/old/guard.sh"; cp "$TMP/lint/clean.sh" "$R/tests/e2e/run.sh"; G add -A; G commit -q -m base; BASE="$(G rev-parse HEAD)"
G checkout -q -b feat; cp "$TMP/lint/one.sh" "$R/design/old/new.sh"; cp "$TMP/lint/wrapped.sh" "$R/tests/e2e/run.sh"; cp "$TMP/lint/one.sh" "$R/kit/tool.sh"; printf '\n' >> "$R/tests/e2e/run.sh"
G add -A; G commit -q -m feat; HEADS="$(G rev-parse HEAD)"
out="$(bash "$LINT" --range "$BASE..$HEADS" --repo "$R")"; rc=$?
chk "ⓓ--range → 새 design/ 파일만 ERR(옛 guard.sh·kit/·래퍼 쓴 tests/e2e 0)" "$rc $(grep -c '^ERR design/old/new.sh:2 ' <<< "$out") $(tail -1 <<< "$out")" "1 1 ERR bg-loop 1"
out="$(bash "$LINT" --range "$BASE..$BASE" --repo "$R")"; chk "ⓓ--range 변경 0 → OK" "$out" "OK bg-loop 0"
grep -q 'ft-bg-loop-lint.sh" --range "$M..$S"' "$BIN/ft-merge-land.sh" && ok "ⓓft-merge-land 착지 게이트 1줄" || bad "ⓓft-merge-land 게이트 줄 없음"

echo "== ⓔ 7초 룰 · tmuxc -e 상속 · GIT_* 0"
chk "ⓔ새 도구 600/300 0" "$(grep -nE '\b(600|300)\b' "$REAP" "$LOOP" "$LINT" | wc -l | tr -d ' ')" 0
chk "ⓔ시험 env GIT_DIR 류 0(R121)" "$(env | grep -cE '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY)=')" 0
eval "$(sed -n '/^prepare_color_environment() {/,/^}/p;/^create_tmux_session() {/,/^}/p' "$TMUXC")"
create_tmux_session "$E" "$TMP/else" && tmux send-keys -t "=$E:" "echo \"X=\${FT_SEAT:-none}\" > $TMP/inherit.out" Enter; sleep 1
chk "ⓔtmuxc create_tmux_session → 첫 셸 FT_SEAT=<세션명>" "$(cat "$TMP/inherit.out" 2>/dev/null)" "X=$E"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
