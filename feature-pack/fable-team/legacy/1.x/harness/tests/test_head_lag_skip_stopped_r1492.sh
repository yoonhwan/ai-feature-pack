#!/usr/bin/env bash
# test_head_lag_skip_stopped_r1492.sh — r1492: 정지 팀 좌석(penalty 재개 전 · 전팀 정지)에 [베이스 뒤처짐] 을 보내지 않는다(T1~T6).
#   T1 penalty 재개 전 팀 = 발신 0 + INFO 1줄 + head-lag.json held · T2 정지 아닌 팀 = 그대로 1통 · T3 재개 뒤 첫 실행 = 보류분 1회 + held 삭제
#   T4 ALL_STOP = 전 팀 0 + INFO all-stop · T5 판정 불가(파일 손상) = 발신 + WARN · T6 따라잡음 = 항목·held 삭제
#   임시 origin+clone+워크트리 2 · 시험용 tmux 서버(-L) · 가짜 mbox(기록만) · 격리 state — 실 저장소·실 tmux·실 mbox·실 state 0 · 발신은 가짜 mbox 1곳 · press 0 · sleep 0
set -uo pipefail
[ -z "${FT_R1492_TEST_ACTIVE:-}" ] || exit 0   # 자기 재호출 가드(ft-test-reentry-lint)
export FT_R1492_TEST_ACTIVE=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R1492_BIN:-$HERE/../bin}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; SOCK="r1492$$"
TM() { tmux -L "$SOCK" "$@"; }
cleanup() { for s in $(TM list-sessions -F '#{session_name}' 2>/dev/null); do TM kill-session -t "$s" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
SECS0=$SECONDS
mkrepo "$T"
ST="$T/.fable-team/state"; SF="$ST/head-lag.json"; mkdir -p "$ST"
export FT_ROOT="$T" FT_HEAD_LAG_MBOX="$T/mbox" FT_HEAD_LAG_TMUX_ARGS="-L $SOCK" MBOX_LOG="$T/mbox.log"
: > "$MBOX_LOG"
cat > "$T/mbox" <<'EOF'
#!/bin/bash
n=$(( $(wc -l < "$MBOX_LOG") + 1 ))
printf '%s\t%s\n' "$2" "$(printf '%s' "$3" | tr '\n' '~')" >> "$MBOX_LOG"
echo "QUEUED seq=$((9000+n)) to=$2"
EOF
chmod +x "$T/mbox"
echo '{"_master":"byz-teama-master-claude#1"}' > "$T/.fable-team/seats-teama.json"
echo '{"_master":"byz-teamb-master-claude#2"}' > "$T/.fable-team/seats-teamb.json"
MA="byz-teama-master-claude#1"; MB="byz-teamb-master-claude#2"
mkwt() { git -C "$W" worktree add -q -b "$2" "$T/$1" "$M0"; echo "$1" > "$T/$1/w_$1.txt"; git -C "$T/$1" add "w_$1.txt"; git -C "$T/$1" commit -q -m "work $1"; }
mkwt wtA wip/wtA; mkwt wtB wip/wtB
TM new-session -d -s 'byz-teama-nano-claude#0' -c "$T/wtA"
TM new-session -d -s 'byz-teamb-nano-claude#0' -c "$T/wtB"
git -C "$W" commit -q --allow-empty -m c1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
RA="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$T/wtA")"
RB="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$T/wtB")"
msgs() { wc -l < "$MBOX_LOG" | tr -d ' '; }
to() { grep -c "^$1	" "$MBOX_LOG"; }   # to <master> — 그 master 앞 쪽지 수
heldm() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print((d.get("seats",{}).get(sys.argv[2],{}) or {}).get("held",{}).get(sys.argv[3],"-"))' "$SF" "$1" "$2"; }   # heldm <워크트리 실제경로> <master>
has() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(sys.argv[2] in d.get("seats",{}))' "$SF" "$1"; }
pen() { printf '{"since":%s,"reason":"시험","order":["teama","teamb"],"resumed":[%s]}\n' "$(date +%s)" "$1" > "$ST/PENALTY_STOP"; }
allon() { printf '{"since":%s,"by":"test","reason":"시험","notify_failed":[]}\n' "$(date +%s)" > "$ST/ALL_STOP.json"; }
run() { out="$(cd / && python3 -I "$BIN/ft_head_lag.py" --event --repo "$W" --bin "$BIN" 2>"$T/err")"; rc=$?; }

# ── T1·T2: teama = penalty 재개 전(발신 0 + INFO + held) · teamb = 재개됨(그대로 1통)
: > "$MBOX_LOG"; rm -f "$SF"; pen '"teamb"'
run
[ "$rc" = 0 ] && [ "$(msgs)" = 1 ] && [ "$(to "$MB")" = 1 ] && [ "$(to "$MA")" = 0 ]; ck "T1 penalty 팀 master 쪽지 0 · 정지 아닌 팀 1통(T2)" $?
[ "$(grep -c '^INFO 정지 팀 teama 알림 0(penalty)$' <<<"$out")" = 1 ]; ck "T1 stdout INFO 정지 팀 teama 알림 0(penalty) 1줄" $?
[ "$(heldm "$RA" "$MA")" = penalty ]; ck "T1 head-lag.json 에 held=penalty(따라잡으면 삭제된다)" $?
! grep -q '^WARN' "$T/err"; ck "T1 판정이 됐으니 WARN 0(조용한 생략 0 · 시끄러운 오판 0)" $?

# ── T3: 재개(파일 없음) 뒤 첫 실행 = 보류분 1회 발신 + held 삭제
B0="$(msgs)"; rm -f "$ST/PENALTY_STOP"; run
[ "$rc" = 0 ] && [ "$(( $(msgs) - B0 ))" = 1 ] && [ "$(to "$MA")" = 1 ] && [ "$(to "$MB")" = 1 ]; ck "T3 재개 뒤 첫 실행 = 팀a 보류분 1통만(팀b 재알림 0)" $?
[ "$(heldm "$RA" "$MA")" = - ]; ck "T3 발신 뒤 held 삭제" $?

# ── T4: 전팀 정지(ALL_STOP) = 두 팀 다 0 + INFO all-stop 2줄
rm -f "$SF"; allon; run
[ "$rc" = 0 ] && [ "$(msgs)" = 2 ]; ck "T4 ALL_STOP = 발신 0" $?
[ "$(grep -c '알림 0(all-stop)$' <<<"$out")" = 2 ]; ck "T4 INFO 정지 팀 … 알림 0(all-stop) 두 팀" $?
[ "$(heldm "$RA" "$MA")" = all-stop ] && [ "$(heldm "$RB" "$MB")" = all-stop ]; ck "T4 둘 다 held=all-stop(받는이별)" $?

# ── T5: 판정 불가(깨진 상태 파일) = 지금처럼 발신 + WARN(안전 쪽)
rm -f "$ST/ALL_STOP.json" "$SF"; printf '{broken\n' > "$ST/PENALTY_STOP"; run
[ "$rc" = 0 ] && [ "$(msgs)" = 4 ] && [ "$(to "$MA")" = 2 ] && [ "$(to "$MB")" = 2 ]; ck "T5 판정 불가 = 두 팀 발신(조용한 생략 0)" $?
grep -q '^WARN 정지 판정 불가' "$T/err"; ck "T5 WARN 정지 판정 불가 1줄" $?

# ── T6: 따라잡은 워크트리 = 항목·held 삭제 · 발신 0
rm -f "$SF"; pen '"teamb"'; N0="$(to "$MA")"; run
[ "$(heldm "$RA" "$MA")" = penalty ] && [ "$(to "$MA")" = "$N0" ]; ck "T6 다시 정지 → 팀a 보류(쪽지 0)" $?
git -C "$T/wtA" merge -q --no-edit origin/main; rm -f "$ST/PENALTY_STOP"; run
[ "$rc" = 0 ] && [ "$(to "$MA")" = "$N0" ] && [ "$(has "$RA")" = False ]; ck "T6 따라잡음 = 발신 0 + head-lag.json 항목(held 포함) 삭제" $?

# ── T7 (DA #276249 R1): 정지 A·활성 B 가 «같은» 뒤처진 worktree → B 발신 성공이 A 의 held 를 덮지 않는다
#    (RED 근거: held 가 워크트리 한 칸이라 B 의 성공 기록이 지우고, 재개 직후에는 n≥1·6시간 규칙에 A 까지 건너뛴다)
echo '{"_master":"byz-teamc-master-claude#3"}' > "$T/.fable-team/seats-teamc.json"
echo '{"_master":"byz-teamd-master-claude#4"}' > "$T/.fable-team/seats-teamd.json"
MC="byz-teamc-master-claude#3"; MD="byz-teamd-master-claude#4"
mkwt wtS wip/wtS
TM new-session -d -s 'byz-teamc-nano-claude#0' -c "$T/wtS"
TM new-session -d -s 'byz-teamd-nano-claude#0' -c "$T/wtS"
RS="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$T/wtS")"
: > "$MBOX_LOG"; rm -f "$SF"; printf '{"since":%s,"reason":"시험","order":["teamc","teamd"],"resumed":["teamd"]}\n' "$(date +%s)" > "$ST/PENALTY_STOP"
run
[ "$rc" = 0 ] && [ "$(to "$MC")" = 0 ] && [ "$(to "$MD")" = 1 ]; ck "T7 같은 worktree 정지 C=발신 0 · 활성 D=1통" $?
[ "$(heldm "$RS" "$MC")" = penalty ]; ck "T7 활성 팀 발신 성공 뒤에도 C 의 held 보존" $?
[ "$(to "$MC")" = 0 ] && rm -f "$ST/PENALTY_STOP" && run
[ "$(to "$MC")" = 1 ] && [ "$(to "$MD")" = 1 ]; ck "T7 재개 직후 C 재개 발신 1 · D 추가 0" $?
[ "$(heldm "$RS" "$MC")" = - ]; ck "T7 재개 발신 뒤 C 의 held 삭제" $?
M7="$(msgs)"; run; [ "$(msgs)" = "$M7" ]; ck "T7 그 다음 실행 = 재알림 0(6시간 규칙 그대로)" $?

# ── 정적
bash -n "$BIN/ft-head-lag.sh" && bash -n "${BASH_SOURCE[0]}"; ck "bash -n 진입·시험" $?
python3 -I -m py_compile "$BIN/ft_head_lag.py" "$BIN/ft_head_lag_stop.py"; ck "py_compile rc0(ft_head_lag · ft_head_lag_stop)" $?
[ "$(wc -l < "$BIN/ft_head_lag.py" | tr -d ' ')" -le 150 ] && [ "$(wc -l < "$BIN/ft_head_lag_stop.py" | tr -d ' ')" -le 150 ]; ck "ft_head_lag.py · ft_head_lag_stop.py ≤ 150줄(기존 두 시험의 한도 그대로)" $?
echo "총 $((SECONDS - SECS0))초"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
