#!/usr/bin/env bash
# test_seat_retire_defer_press_r690.sh — r690: 승계(ft-seat-retire)의 고아 정리가 press 중이면 «미룸» · press 끝난 뒤 다음 정리가 소화.
#   ⓐ(실패 시험) press 러너 살아 있음 + 옛 좌석 고아(FT_SEAT=OLD · layout_watch 꼴) → retire 뒤 고아 생존 · reap-defer 줄 · 미룸 파일 1 · rc 0
#   ⓑ 장치 허가 device.json held=true(러너 없음) → 미룸 · ⓒ press 없음 → 지금처럼 kill(left=0)
#   ⓓ 미룸 소화: press 끝난 뒤 다른 좌석 reap 이 lstart 같은 pid 만 정지 · 파일 삭제 · pid 재사용(lstart 다름) → kill 0 + 파일 삭제 · 못 멈춤 → 파일 유지
#   ⓔ 남의 uid 러너 → 미룸 0 · ⓖ 변이(press 판정 삭제) 사본 → ⓐ FAIL
# 실프로세스 픽스처 = 표식 r690fx-<pid> 를 argv 에 단 고아 루프·러너만 — trap 이 정리. 상태 폴더(미룸·허가)는 전부 임시.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R690_BIN:-$HERE/../../harness/bin}"; REAP="$BIN/ft-seat-reap.sh"; RETIRE="$BIN/ft-seat-retire.sh"
T0="$(mktemp -d)"; TMP="$(cd "$T0" && pwd -P)"; MK="r690fx-$$"
OLD="r690t-$$#0"; NEW="r690t-$$#1"
cleanup() { local p; for p in $(pgrep -f "$MK"); do kill -9 "$p" 2>/dev/null; done; }
trap 'cleanup; rm -rf "$T0"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo dead; }
orphan() {  # orphan <FT_SEAT> <루프 본문> — ppid 1 고아 1개 · pid 출력
  ( cd "$TMP" || exit; FT_SEAT="$1" nohup "$BASH_X" -c "$2 # $MK" >/dev/null 2>&1 & )   # 백그라운드 = 단일 명령(중간 서브셸이 부모·$( ) 파이프를 쥐지 않게)
  sleep 0.4; pgrep -f "$2 # $MK" | while read -r p; do [ "$(ps -o ppid= -p "$p" | tr -d ' ')" = 1 ] && echo "$p"; done | tail -1
}
runner() { ( nohup python3 "$TMP/tests/e2e/r690_press_fx.py" "$MK" >/dev/null 2>&1 & ); sleep 0.4; pgrep -f "r690_press_fx.py $MK" | tail -1; }
seats() { printf '{"%s": {"role": "tester", "agent": "claude", "model": "m", "tick": null}}\n' "$OLD" > "$TMP/seats.json"; }
BASH_X="$(command -v bash)"
mkdir -p "$TMP/tests/e2e" "$TMP/permits" "$TMP/defer" "$TMP/resume"
printf 'import time, sys\nwhile True: time.sleep(1)\n' > "$TMP/tests/e2e/r690_press_fx.py"
export ZC_RESUME_DIR="$TMP/resume" FT_SUCCESSOR_DIR="$TMP/succ" FT_PERMIT_DIR="$TMP/permits" FT_REAP_DEFER_DIR="$TMP/defer"
DF="$TMP/defer/$OLD.jsonl"
PROBE="$(orphan probe-$$ 'while true; do sleep 1; : probe; done')"
ENVOK=0; ps -E -ww -o command= -p "$PROBE" | grep -q "FT_SEAT=probe-$$" && ENVOK=1; kill "$PROBE" 2>/dev/null
[ "$ENVOK" = 1 ] || { echo "SKIP 이 머신은 $BASH_X 의 env 를 ps 로 못 읽음 — ② 고아 픽스처 불가"; exit 0; }
for f in "$REAP" "$RETIRE"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

echo "== ⓐ press 러너 살아 있음(기본 패턴 tests/e2e/…press….py) → retire 뒤 고아 생존 · 미룸 1 · rc 0"
seats; PR="$(runner)"; L1="$(orphan "$OLD" 'while true; do echo w >> lw.log; sleep 1; done')"
chk "ⓐ픽스처 러너·고아" "$([ -n "$PR" ] && [ -n "$L1" ] && echo 2)" 2
out="$(bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" 2>&1)"; rc=$?
chk "ⓐretire rc 0 · 고아 생존" "$rc $(alive "$L1")" "0 alive"
has "$out" "reap-defer pid=$L1 why=press-active" "ⓐreap-defer 줄"
has "$out" "reap deferred=1 (press 중 · 끝난 뒤 다음 정리에서)" "ⓐretire 미룸 안내 줄"
chk "ⓐ끝 줄 reap left=0 rc=0 · CLOSE-FAIL 0" "$(tail -1 <<< "$out") $(grep -c CLOSE-FAIL <<< "$out")" "reap left=0 rc=0 0"
chk "ⓐ미룸 파일 1 · pid 기록" "$([ -f "$DF" ] && grep -c "\"pid\": $L1," "$DF")" 1
out="$(bash "$REAP" "$OLD" --orphans-only --defer-press)"
has "$(tail -1 <<< "$out")" "stopped=0 left=0 deferred=1 rc=0" "ⓐreap 끝 줄 deferred=1"

echo "== ⓓ 미룸 소화 — press 끝 → 다른 좌석 reap 이 미룸 pid 정지 · 파일 삭제"
export FT_PRESS_RUNNER_RE='tests/e2e/r690_press_fx\.py'   # 여기부터 «press 끝» 판정에 이 머신의 실 press 가 섞이지 않게(ⓐ 만 기본 패턴)
kill "$PR"; sleep 0.3
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" "r690other-$$#0")"
has "$out" "reap-deferred-done file=$DF stopped=0 kept=1" "ⓓ못 멈춤 → kept=1"
chk "ⓓ못 멈춤 → 파일 유지 · 고아 생존" "$([ -f "$DF" ] && echo kept) $(alive "$L1")" "kept alive"
out="$(bash "$REAP" "r690other-$$#0")"
has "$out" "reap-kill pid=$L1 via=⑤미룸" "ⓓreap-kill via=⑤미룸"
has "$out" "reap-deferred-done file=$DF stopped=1 kept=0" "ⓓreap-deferred-done stopped=1"
chk "ⓓ고아 정지 · 미룸 파일 삭제" "$(alive "$L1") $([ -f "$DF" ] && echo left || echo gone)" "dead gone"
sleep 30 & SP=$!   # pid 재사용 꼴: 살아 있는 내 프로세스 + 다른 시작 시각
printf '{"pid": %s, "lstart": "Mon Jan  1 00:00:00 2001", "cmd": "fake", "via": "②"}\n' "$SP" > "$DF"
out="$(bash "$REAP" "r690other-$$#0")"
chk "ⓓpid 재사용(lstart 다름) → kill 0 · 파일 삭제" "$(alive "$SP") $([ -f "$DF" ] && echo left || echo gone) $(grep -c "reap-kill pid=$SP" <<< "$out")" "alive gone 0"
kill "$SP" 2>/dev/null

echo "== ⓑ 장치 허가 held=true(러너 없음) → 미룸 · ⓒ press 없음 → kill"
export FT_PRESS_RUNNER_RE="r690-never-$$"   # 이 머신의 실 press 러너가 ⓑ·ⓒ 판정에 섞이지 않게
printf '{"held":true,"member":"r690"}\n' > "$TMP/permits/device.json"
seats; L2="$(orphan "$OLD" 'while true; do echo d >> ld.log; sleep 1; done')"
out="$(bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" 2>&1)"; rc=$?
chk "ⓑdevice held → rc 0 · 고아 생존 · 미룸 줄" "$rc $(alive "$L2") $(grep -c "reap-defer pid=$L2 why=press-active" <<< "$out")" "0 alive 1"
rm -f "$TMP/permits/device.json"
seats; out="$(bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" 2>&1)"; rc=$?
chk "ⓒpress 없음 → 미룸 소화 + 고아 정지 · 끝 줄 left=0" "$rc $(alive "$L2") $(tail -1 <<< "$out")" "0 dead reap left=0 rc=0"
L3="$(orphan "$OLD" 'while true; do echo c >> lc.log; sleep 1; done')"
seats; out="$(bash "$RETIRE" "$OLD" "$NEW" --seats "$TMP/seats.json" 2>&1)"; rc=$?
chk "ⓒ새 고아 → reap-kill · 미룸 0 · 파일 0" "$rc $(alive "$L3") $(grep -c 'reap-defer' <<< "$out") $([ -f "$DF" ] && echo f || echo nofile)" "0 dead 0 nofile"

echo "== ⓔ 남의 uid 러너(launchd · root) → 미룸 0"
L4="$(orphan "$OLD" 'while true; do echo e >> le.log; sleep 1; done')"
out="$(FT_PRESS_RUNNER_RE='/sbin/launchd|/sbin/init|systemd' bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "ⓔ남의 uid → kill · deferred=0" "$(alive "$L4") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "dead deferred=0"
SH="$(orphan "r690shell-$$" 'while true; do sleep 1; : tests/e2e/r690_press_fx.py; done')"   # 셸 명령줄에 러너 경로 «글자»만(실측 오탐 꼴)
L5="$(orphan "$OLD" 'while true; do echo f >> lf.log; sleep 1; done')"
out="$(FT_PRESS_RUNNER_RE='tests/e2e/r690_press_fx\.py' bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "ⓔ셸 명령줄 글자 오탐 0 → kill · deferred=0" "$(alive "$L5") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "dead deferred=0"
kill "$SH" 2>/dev/null
out="$(FT_PRESS_RUNNER_RE='(' bash "$REAP" "$OLD" --defer-press 2>&1)"; chk "ⓔ정규식 오류 → rc 20" "$?" 20
PR="$(runner)"; L6="$(orphan "$OLD" 'while true; do echo g >> lg.log; sleep 1; done')"
out="$(FT_ROOT= FT_REAP_DEFER_DIR= FT_PRESS_RUNNER_RE= bash "$REAP" "$OLD" --orphans-only --defer-press 2>&1)"; rc=$?   # git 밖 cwd(guard) + FT_ROOT 빈 값 = 데이터 루트 못 풂
chk "ⓔ미룸 경로 못 풂(데이터 루트 없음) → rc 20 · 고아 생존(조용히 지우지 않음)" "$rc $(alive "$L6")" "20 alive"
kill "$PR" "$L6" 2>/dev/null
rm -f "$TMP/defer/"*

lst() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | xargs; }   # reap 과 같은 꼴(LC_ALL=C TZ=UTC · 공백 1칸)
row() { printf '{"pid": %s, "lstart": "%s", "cmd": "fx", "via": "②"}\n' "$1" "$(lst "$1")"; }
echo "== H1 깨진 미룸 줄 → 원문 .broken 보존 + 줄 출력 · 유효 행은 소화"
L7="$(orphan "$OLD" 'while true; do echo h1 >> lh1.log; sleep 1; done')"
{ printf '\n{"pid":\n'; row "$L7"; } > "$DF"
out="$(bash "$REAP" "r690other-$$#0" 2>"$TMP/h1.err")"; rc=$?
BF="$(ls "$DF".broken-* 2>/dev/null | head -1)"
chk "H1 rc 0 · 유효 행 소화 · 원 파일 삭제" "$rc $(alive "$L7") $([ -f "$DF" ] && echo left || echo gone)" "0 dead gone"
has "$out" "reap-deferred-broken file=$BF lines=1" "H1 reap-deferred-broken 줄(stdout)"
chk "H1 .broken 원문 = 깨진 줄 1" "$([ -n "$BF" ] && cat "$BF")" '{"pid":'
has "$(cat "$TMP/h1.err")" "ERROR 미룸 파일 깨진 줄 1" "H1 stderr ERROR"
rm -f "$TMP/defer/"*

echo "== H2 press 판정 = python «실행 스크립트» 만 · 인자로만 든 시험 경로 → press 아님"
printf 'import time, sys\nwhile True: time.sleep(1)\n' > "$TMP/watch.py"
( nohup python3 -c 'import time; time.sleep(60)' "$TMP/tests/e2e/r690_press_fx.py" "$MK" >/dev/null 2>&1 & )
( nohup python3 "$TMP/watch.py" "$TMP/tests/e2e/r690_press_fx.py" "$MK" >/dev/null 2>&1 & ); sleep 0.4
export FT_PRESS_RUNNER_RE='tests/e2e/r690_press_fx\.py'
L8="$(orphan "$OLD" 'while true; do echo h2 >> lh2.log; sleep 1; done')"
out="$(bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "H2 -c 인자 · 감시기 인자 → 미룸 0 · kill" "$(alive "$L8") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "dead deferred=0"
( nohup python3 -u "$TMP/tests/e2e/r690_press_fx.py" "$MK" >/dev/null 2>&1 & ); sleep 0.4
L9="$(orphan "$OLD" 'while true; do echo h2b >> lh2b.log; sleep 1; done')"
out="$(bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "H2 옵션(-u) 뒤 실행 스크립트 = 러너 → 미룸" "$(alive "$L9") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "alive deferred=1"
for p in $(pgrep -f "r690_press_fx.py $MK"); do kill "$p" 2>/dev/null; done; sleep 0.3
export FT_PRESS_RUNNER_RE="r690-never-$$"
bash "$REAP" "r690other-$$#0" >/dev/null 2>&1; chk "H2 러너 끝 → 소화" "$(alive "$L9") $([ -f "$DF" ] && echo left || echo gone)" "dead gone"

echo "== H3 미룸 소화도 보호 exe · 서비스(LISTEN) 제외 — 신호 0"
mkdir -p "$TMP/pbin"; ln -sf "$BASH_X" "$TMP/pbin/headroom"
( nohup python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); time.sleep(60)' "lsfx-$MK" >/dev/null 2>&1 & ); sleep 0.6
LS="$(pgrep -f "lsfx-$MK" | tail -1)"
( cd "$TMP" || exit; FT_SEAT="$OLD" nohup "$TMP/pbin/headroom" -c "while true; do sleep 1; : prot; done # $MK" >/dev/null 2>&1 & ); sleep 0.4
LP="$(pgrep -f "sleep 1; : prot; done # $MK" | tail -1)"
{ row "$LS"; row "$LP"; } > "$DF"
out="$(bash "$REAP" "r690other-$$#0")"
has "$out" "reap-skip pid=$LS why=service-listen" "H3 LISTEN → reap-skip service-listen"
has "$out" "reap-skip pid=$LP why=protect-exe" "H3 보호 exe → reap-skip protect-exe"
chk "H3 둘 다 생존 · reap-kill 0 · 파일 정리" "$(alive "$LS") $(alive "$LP") $(grep -c 'via=⑤미룸' <<< "$out") $([ -f "$DF" ] && echo left || echo gone)" "alive alive 0 gone"
kill "$LS" "$LP" 2>/dev/null

echo "== H4 남의 uid 러너(python 조건은 통과 · uid 로만 탈락) → 미룸 0 · 같은 줄 내 uid → 미룸(대조)"
export FT_PRESS_RUNNER_RE='tests/e2e/r690_press_fx\.py'
L10="$(orphan "$OLD" 'while true; do echo h4 >> lh4.log; sleep 1; done')"
printf '999999 0 /usr/bin/python3 %s\n' "$TMP/tests/e2e/r690_press_fx.py" > "$TMP/snap0"
out="$(FT_PRESS_PS_SNAPSHOT="$TMP/snap0" bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "H4 uid 0 python 러너 → kill · deferred=0" "$(alive "$L10") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "dead deferred=0"
L11="$(orphan "$OLD" 'while true; do echo h4b >> lh4b.log; sleep 1; done')"
printf '999999 %s /usr/bin/python3 %s\n' "$(id -u)" "$TMP/tests/e2e/r690_press_fx.py" > "$TMP/snapme"
out="$(FT_PRESS_PS_SNAPSHOT="$TMP/snapme" bash "$REAP" "$OLD" --orphans-only --defer-press)"
chk "H4 대조: 내 uid 같은 줄 → 생존 · deferred=1" "$(alive "$L11") $(tail -1 <<< "$out" | grep -oE 'deferred=[0-9]+')" "alive deferred=1"
export FT_PRESS_RUNNER_RE="r690-never-$$"; bash "$REAP" "r690other-$$#0" >/dev/null 2>&1
chk "H4 소화 → 정지" "$(alive "$L11")" dead

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
