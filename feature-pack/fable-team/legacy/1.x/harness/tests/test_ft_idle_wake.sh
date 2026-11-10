#!/usr/bin/env bash
# test_ft_idle_wake.sh — 유휴 좌석 깨우기 시험 (R241c · DESIGN-r241-desk-never-stall §9 구현 범위 8)
# 격리: 대역 큐(mailbox.jsonl) · 대역 seat-status(상태 파일) · 대역 mbox(ring 호출 기록) · 테스트 tmux 서버(-L) · 가짜 시계(FT_IDLE_WAKE_NOW).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; SH="$ROOT/harness/bin/ft-idle-wake.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(mktemp -d)"; SOCK="r241w$$"; CTL="$T/ctl"; mkdir -p "$T/.fable-team/comm" "$T/.fable-team/state" "$CTL"
SEAT='seat-r241w#1'; PLAN='planner-r241w#1'; Q="$T/.fable-team/comm/mailbox.jsonl"; NOW="$(date +%s)"
tm() { tmux -L "$SOCK" "$@"; }
cleanup() { touch "$CTL/stop"; sleep 0.3; tm kill-session -t "$SEAT" 2>/dev/null; tm kill-session -t "$PLAN" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
tm -f /dev/null new-session -d -s "$SEAT" -x 80 -y 24 'sleep 120'
tm new-session -d -s "$PLAN" -x 80 -y 24 'sleep 120'
# 대역 mbox: ring 호출을 기록만 한다 / 대역 seat-status: 상태 파일의 첫 단어를 낸다(파일 없음 = 실패 rc 3)
cat > "$T/mbox.sh" <<'EOF'
#!/bin/bash
sleep "${MBOX_SLEEP:-0}"; echo "$*" >> "$RING_LOG"; [ -z "${MBOX_FAIL:-}" ] || { echo "RING refused" >&2; exit 1; }; echo "RING $2 doorbell=sent"
EOF
cat > "$T/seat-status.sh" <<'EOF'
#!/bin/bash
f="$STATUS_DIR/$2"; [ -f "$f" ] || { echo "turn: no jsonl" >&2; exit 3; }
echo "$(cat "$f") 2026-10-15T00:00:00 1000 yes jsonl"
EOF
export RING_LOG="$T/ring.log" STATUS_DIR="$T/status"; mkdir -p "$STATUS_DIR"; : > "$RING_LOG"
row() {  # seq to 대기초 → 큐 행 (ts = 가짜 now − 대기초, 로컬 시각)
  python3 -c 'import json,sys,time;s,to,age=sys.argv[1:4];print(json.dumps({"seq":int(s),"ts":time.strftime("%Y-%m-%dT%H:%M:%S",time.localtime(int(sys.argv[4])-int(age))),"to":to,"from":"x","body":"b"}))' "$1" "$2" "$3" "$NOW" >> "$Q"
}
set_state() { printf '%s' "$2" > "$STATUS_DIR/$1"; }
wake() {
  : > "$RING_LOG"
  out="$(env FT_ROOT="$T" FT_MBOX="$T/mbox.sh" FT_SEAT_STATUS="$T/seat-status.sh" FT_TMUX="tmux -L $SOCK" FT_IDLE_WAKE_NOW="${1:-$NOW}" "${@:2}" bash "$SH" 2>"$T/err")"; rc=$?
}
rings() { wc -l < "$RING_LOG" | tr -d ' '; }

bash -n "$SH" 2>/dev/null; ck "bash -n" $?

# ① 대기 200초 + 유휴 + 키 입력 없음 → ring 1 (seq 그대로)
: > "$Q"; row 11 "$SEAT" 200; set_state "$SEAT" IDLE; wake
[ "$(rings)" = 1 ] && grep -q "ring $SEAT 11" "$RING_LOG"; ck "① 유휴·200초·키 입력 없음 → ring 1(seq 11)" $?
# ② 같은 (좌석, 가장 오래된 seq) → 다시 안 깨운다
wake; [ "$(rings)" = 0 ]; ck "② 다음 실행 같은 seq → 0" $?
# ③ 그 쪽지가 읽혀 더 새 쪽지(180초 넘음)가 가장 오래된 것이 되면 다시 1
: > "$Q"; row 12 "$SEAT" 190; wake; [ "$(rings)" = 1 ] && grep -q "ring $SEAT 12" "$RING_LOG"; ck "③ 새 seq 가 가장 오래된 것 → ring 1(seq 12)" $?
# ④ 대기 179초 → 0
: > "$Q"; row 13 "$SEAT" 179; wake; [ "$(rings)" = 0 ]; ck "④ 대기 179초 → 0" $?
# ⑤ 바쁨 → 0
: > "$Q"; row 14 "$SEAT" 300; set_state "$SEAT" WORKING; wake; [ "$(rings)" = 0 ]; ck "⑤ 바쁨(WORKING) → 0" $?
# ⑥ 조회 실패(상태 파일 없음 rc≠0) → 0 + 로그
rm -f "$STATUS_DIR/$SEAT"; wake; [ "$(rings)" = 0 ] && grep -q "$SEAT" "$T/.fable-team/state/idle-wake.log"; ck "⑥ 상태 조회 실패 → 0 + 로그 1줄" $?
# ⑦ 세션 없음 → 0 + 로그
: > "$Q"; row 15 "ghost-r241w#9" 300; set_state "ghost-r241w#9" IDLE; wake
[ "$(rings)" = 0 ] && grep -q "ghost-r241w#9" "$T/.fable-team/state/idle-wake.log"; ck "⑦ tmux 세션 없음 → 0 + 로그" $?
# ⑧ 키 입력 60초 전 → 0 (진짜 pty 클라이언트가 방금 쳤다 = 오빠가 그 화면에 있다)
: > "$Q"; row 16 "$SEAT" 300; set_state "$SEAT" IDLE
python3 -I "$HERE/pty_client.py" "$SOCK" "$SEAT" "$CTL" >/dev/null 2>&1 &
PP=$!; for _ in $(seq 1 50); do [ -e "$CTL/READY" ] && break; sleep 0.1; done
touch "$CTL/press"; for _ in $(seq 1 50); do [ -e "$CTL/press" ] || break; sleep 0.1; done; sleep 0.3
wake "$(( $(date +%s) + 60 ))"; [ "$(rings)" = 0 ]; ck "⑧ 키 입력 60초 전(120초 창 안) → 0" $?
# ⑨ 키 입력이 창 밖(FT_IDLE_CLIENT_SEC=1 · 2초 경과) → ring 1
sleep 2.2; wake "$(( $(date +%s) + 60 ))" FT_IDLE_CLIENT_SEC=1; [ "$(rings)" = 1 ]; ck "⑨ 키 입력이 창 밖 → ring 1" $?
touch "$CTL/stop"; wait "$PP" 2>/dev/null
# ⑩ planner(_master) 도 같은 규칙 — 별도 예외 없음
: > "$Q"; row 17 "$PLAN" 400; set_state "$PLAN" IDLE; wake; [ "$(rings)" = 1 ] && grep -q "ring $PLAN 17" "$RING_LOG"; ck "⑩ planner 좌석도 같은 규칙 → ring 1" $?
# ⑪ 큐 파일 없음 → 0 + 로그(지어내기 0)
rm -f "$Q"; wake; [ "$rc" = 0 ] && [ "$(rings)" = 0 ]; ck "⑪ 큐 파일 없음 → ring 0" $?

STATE_F="$T/.fable-team/state/idle-wake.json"
# ⑬ H3: 첫 조회(옛 값) 뒤 ring 직전에 키 입력이 들어오면 ring 0 — 직전 재확인 (DA⑥ H3)
cat > "$T/tmux-wrap.sh" <<WRAP
#!/bin/bash
if [[ "\$*" == *list-clients* ]] && [ ! -e "$T/wrapped" ]; then
  out="\$(tmux -L $SOCK "\$@")"; touch "$T/wrapped"; touch "$CTL/press"
  for _ in \$(seq 1 50); do [ -e "$CTL/press" ] || break; sleep 0.1; done; sleep 0.3; echo "\$out"; exit 0
fi
exec tmux -L $SOCK "\$@"
WRAP
rm -f "$STATE_F" "$CTL/stop" "$CTL/READY"; : > "$Q"; row 20 "$SEAT" 400; set_state "$SEAT" IDLE
python3 -I "$HERE/pty_client.py" "$SOCK" "$SEAT" "$CTL" >/dev/null 2>&1 &
PP=$!; for _ in $(seq 1 50); do [ -e "$CTL/READY" ] && break; sleep 0.1; done; sleep 2.2
wake "$(date +%s)" FT_TMUX="bash $T/tmux-wrap.sh" FT_IDLE_CLIENT_SEC=1
[ -e "$T/wrapped" ] && [ "$(rings)" = 0 ]; ck "⑬ 첫 조회 뒤 키 입력 → ring 직전 재확인으로 ring 0(보류)" $?
touch "$CTL/stop"; wait "$PP" 2>/dev/null
# ⑭ H4: 같은 좌석·seq 를 두 실행이 동시에 관측해도 ring 1 (flock 선점)
rm -f "$STATE_F"; : > "$Q"; row 21 "$SEAT" 400; set_state "$SEAT" IDLE; : > "$RING_LOG"
for i in 1 2; do env FT_ROOT="$T" FT_MBOX="$T/mbox.sh" FT_SEAT_STATUS="$T/seat-status.sh" FT_TMUX="tmux -L $SOCK" FT_IDLE_WAKE_NOW="$NOW" MBOX_SLEEP=1 bash "$SH" >/dev/null 2>&1 & done; wait
out="rings=$(rings) $(cat "$RING_LOG" | tr "\n" ";")"; [ "$(rings)" = 1 ]; ck "⑭ 동시 2 실행 → ring 1 ($out)" $?
# ⑮ H4: 상태 JSON 손상 → ring 0 + stderr ERROR + rc 4 (빈 상태로 덮지 않는다)
printf '{깨진' > "$STATE_F"; : > "$Q"; row 22 "$SEAT" 400; wake
[ "$rc" = 4 ] && [ "$(rings)" = 0 ] && grep -q 'ERROR' "$T/err" && [ "$(cat "$STATE_F")" = '{깨진' ]; ck "⑮ 상태 손상 → ring 0 · rc 4 · ERROR · 파일 보존" $?
# ⑯ 명시 실패(mbox rc≠0) → 다음 실행에 재시도 / 성공하면 다시 안 함
rm -f "$STATE_F"; : > "$Q"; row 23 "$SEAT" 400; wake "$NOW" MBOX_FAIL=1; [ "$(rings)" = 1 ]; ck "⑯a ring 명시 실패 → 시도 기록(ring 호출 1)" $?
wake; [ "$(rings)" = 1 ]; ck "⑯b 다음 실행에 재시도 → ring 호출 1(성공)" $?
wake; [ "$(rings)" = 0 ]; ck "⑯c 성공 뒤엔 다시 안 함" $?

# ⑫ launchd plist 틀 — 60초 간격 · 자리표시자 2종만 · plutil lint
PT="$ROOT/harness/kit/launchd/com.byz.ft-idle-wake.plist.template"
sed -e 's#__FT_BIN__#/x/bin#g' -e 's#__BYZ_ROOT__#/x#g' "$PT" > "$T/p.plist" 2>/dev/null
plutil -lint "$T/p.plist" >/dev/null 2>&1 && grep -q '<key>StartInterval</key><integer>60</integer>' "$T/p.plist" && ! grep -q '__' "$T/p.plist"; ck "⑫ plist 틀: lint OK · StartInterval 60 · 자리표시자 완전 치환" $?

echo "fail=$fail"; [ "$fail" = 0 ]
