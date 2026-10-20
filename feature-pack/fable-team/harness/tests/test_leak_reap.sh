#!/usr/bin/env bash
# test_leak_reap.sh — R347: 유출 부하 리퍼(ft-leak-reap.sh) + 틱 경보(ft-leak-watch.sh · ft-tick · ft-tick-team).
# 입력은 FT_PS_SNAPSHOT(가짜 ps 표) · 조사 실패는 FT_PS_CMD 대역 — 실 프로세스 종료 0(--kill 시험은 «내가 띄운 합성 고아 1건» 만 담은 스냅샷).
# mktemp 만 쓴다 · 시험에 GIT_DIR 류를 걸지 않는다(R121). 변이 시험은 R347_BIN=<변이 복사본 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R347_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
T0="$(mktemp -d)"; T="$(cd "$T0" && pwd -P)"; MARK="leakmark_$$_$RANDOM"; PGIDS=""; DP=""
# ★정리 주체★ 정상·INT·TERM·HUP·QUIT 종료 = 이 trap 이 «이 시험이 만든» 프로세스 그룹(PGID)만 TERM→1s→KILL. 외부 SIGKILL 시에는 trap 이 없다 — 그때 정리 주체 = 머신 가드(launchd ft-leak-reap).
cleanup() {
  local g
  [ -z "$DP" ] || kill "$DP" 2>/dev/null
  for g in $PGIDS; do kill -TERM -- "-$g" 2>/dev/null; done
  [ -z "$PGIDS" ] || sleep 1
  for g in $PGIDS; do kill -KILL -- "-$g" 2>/dev/null; done
  rm -rf "$T"
}
trap 'cleanup; rm -rf "$T0"' EXIT
trap 'exit 130' INT TERM HUP QUIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }

REAP="$BIN/ft-leak-reap.sh"; WATCH="$BIN/ft-leak-watch.sh"
for f in ft-leak-reap.sh ft-leak-watch.sh ft-tick.sh ft-tick-team.sh; do
  [ -f "$BIN/$f" ] && bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f (없거나 문법 오류)"
done
if [ -z "${R347_BIN:-}" ]; then for f in ft-leak-reap.sh ft-leak-watch.sh ft-tick.sh ft-tick-team.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done; fi
[ -f "$REAP" ] || { echo "FAILED $fail — ft-leak-reap.sh 없음(RED)"; exit 1; }

# ── ① 가짜 ps 표본 4(+경계·데이터 셸) ──
L="Sat Oct 18 00:12:34 2026"
row() { printf '%6s %6s %6s %s %10s %-4s %s\n' "$1" "$2" "$1" "$L" "$3" "${4:-R}" "$5"; }
{
  row 1 0 5:49.47 Ss /sbin/launchd
  row 5001 1 1:30.00 R "bash -c (while :; do :; done) & : x"                  # 고아 + 시그니처 + CPU 90s → 검출
  row 5002 1 0:45.10 R "/bin/sh -c (while true; do :; done)"                  # 고아 + 시그니처 + CPU 45s → 검출
  row 5003 777 2:00.00 R "bash -c (while :; do :; done) & : y"                # 부모 생존 → 제외
  row 5004 1 5:00.00 Ss '/opt/homebrew/bin/headroom proxy --note "while :; do :; done"'   # 보호 목록 exe → 제외
} > "$T/ps4.txt"
RUN() { local rc o; o="$(FT_PS_SNAPSHOT="$1" bash "$REAP" "${@:2}" 2>&1)"; rc=$?; printf '%s\n' "$o" | grep -v 'setlocale'; return $rc; }   # 로캘 경고(mac 에 C.UTF-8 없음)는 출력 비교에서 제외
o="$(RUN "$T/ps4.txt" --dry-run)"; rc=$?
rc_is "$rc" 10 "표본4 dry-run 발견"; has "$o" "pid=5001" "검출 5001"; has "$o" "pid=5002" "검출 5002"
hasnt "$o" "pid=5003" "부모 생존 제외"; hasnt "$o" "pid=5004" "보호 목록 제외"; hasnt "$o" "TERM" "사살 0(dry-run)"; has "$o" "유출 2건" "검출 2건"
fp1="$(printf '%s\n' "$o" | sed -n 's/.*fp=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)"; [ -n "$fp1" ] && ok "사건 지문 fp 8자리($fp1)" || bad "fp 없음"
o2="$(RUN "$T/ps4.txt" --dry-run --quiet)"; eq "$(printf '%s\n' "$o2" | sed -n 's/.*fp=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)" "$fp1" "같은 표 → 같은 지문"
o="$(RUN "$T/ps4.txt" --json)"; has "$o" '"leaked": 2' "--json leaked 2"; has "$o" '"killed": 0' "--json killed 0"
# CPU 29s / 30s 경계 · 시그니처를 데이터로만 가진 정상 셸
{ row 6001 1 0:29.00 R "bash -c (while :; do :; done)"; row 6002 1 0:30.00 R "bash -c (while :; do :; done)"
  row 6003 800 9:00.00 R 'bash -c echo "while :; do :; done"'; row 6004 1 0:02.00 R 'cat /tmp/while :; do :; done.txt'; } > "$T/psb.txt"
o="$(RUN "$T/psb.txt" --dry-run)"; rc=$?; rc_is "$rc" 10 "경계 표 발견"; hasnt "$o" "pid=6001" "CPU 29s 비검출"; has "$o" "pid=6002" "CPU 30s 검출"
hasnt "$o" "pid=6003" "데이터 셸(부모 생존) 비검출"; hasnt "$o" "pid=6004" "데이터 셸(CPU<30) 비검출"
o="$(RUN "$T/psb.txt" --dry-run --min-cpu=29)"; has "$o" "pid=6001" "--min-cpu=29 → 29s 검출"
{ row 7001 1 9:00.00 R "/usr/libexec/logd"; row 7003 2 0:00.00 '?' "(bash)"; } > "$T/ps0.txt";   # '?' stat 의 «(bash)» 행 = 실제 ps 의 종료 중 프로세스(2026-10-18 실측 — 조사 실패로 오판하면 안 됨)
 o="$(RUN "$T/ps0.txt" --dry-run)"; rc=$?; rc_is "$rc" 0 "유출 0 → rc 0"; has "$o" "유출 0" "유출 0 문구"
o="$(RUN "$T/ps0.txt" --dry-run --quiet)"; eq "$o" "" "유출 0 + --quiet → 출력 0"

# ── ② 조사 실패 = rc 20 + stderr 1줄(조용한 0 금지) ──
o="$(RUN "$T/없는파일" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "스냅샷 파일 없음"; has "$o" "ft-leak-reap: ERROR" "stderr ERROR 줄"
: > "$T/empty.txt"; o="$(RUN "$T/empty.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "빈 스냅샷"
printf '5001 1 0:30.00 broken row\n' > "$T/garbage.txt"; o="$(RUN "$T/garbage.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "파싱 불가 행(필드 부족)"
printf '%6s %6s %6s %s %s %s %s\n' 5001 1 5001 "토 10/17 14:33:28 2026" 1:30.00 R "bash -c (while :; do :; done)" > "$T/ko.txt"
o="$(RUN "$T/ko.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "로캘 달라 lstart 4토큰 → 조용한 오검출 0 · rc 20"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD=false bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?; rc_is "$rc" 20 "ps rc≠0"; has "$o" "ft-leak-reap: ERROR" "ps rc≠0 stderr"
s0=$SECONDS; o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD='sleep 30' FT_PS_TIMEOUT=1 bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?
rc_is "$rc" 20 "ps timeout"; [ $((SECONDS-s0)) -lt 10 ] && ok "timeout 10초 안" || bad "timeout 10초 초과"; has "$o" "timeout" "timeout 사유 줄"
mkdir -p "$T/nopy"; ln -s "$(command -v bash)" "$T/nopy/bash"
o="$(env -i PATH="$T/nopy" FT_PS_SNAPSHOT="$T/ps4.txt" "$T/nopy/bash" "$REAP" --dry-run --quiet 2>&1)"; rc=$?; rc_is "$rc" 20 "python3 없음"; has "$o" "python3" "python3 없음 stderr"
bash "$REAP" --bogus >/dev/null 2>&1; rc_is $? 2 "usage → rc 2"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="cat $T/ps4.txt" bash "$REAP" --snapshot="$T/snap.out" 2>&1)"; rc=$?; rc_is "$rc" 0 "--snapshot 생성"; eq "$(cat "$T/snap.out")" "$(cat "$T/ps4.txt")" "스냅샷 내용 = ps 출력 그대로"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD=false bash "$REAP" --snapshot="$T/snap2.out" 2>&1)"; rc=$?; rc_is "$rc" 20 "--snapshot ps 실패 → rc 20"; [ ! -e "$T/snap2.out" ] && ok "실패 시 파일 안 남김" || bad "실패인데 스냅샷 파일 있음"

# ── H1 고정 표본(DA⑥ r1) ──
printf 'old\n' > "$T/exist.out"; env -u FT_PS_SNAPSHOT FT_PS_CMD=false bash "$REAP" --snapshot="$T/exist.out" >/dev/null 2>&1; rc=$?
rc_is "$rc" 20 "H1-1 기존 출력 파일 + ps 실패 → rc 20"; [ ! -e "$T/exist.out" ] && ok "H1-1 기존 파일 삭제(유효 결과로 안 남김)" || bad "H1-1 기존 파일 남음"
printf '%6s %6s %6s %s %s %s %s\n' 7001 1 7001 'A B C D E' 0:30.00 R /usr/libexec/logd > "$T/badlst.txt"
o="$(RUN "$T/badlst.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "H1-2 잘못된 lstart(날짜 아님) → rc 20(조용한 유출 0 아님)"
printf '%6s %6s %6s %s %s %s %s\n' 7002 1 7002 "$L" 0:30.00 '!!' /usr/libexec/logd > "$T/badstat.txt"
o="$(RUN "$T/badstat.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "H1-2b 잘못된 stat → rc 20"
printf 'old\n' > "$T/exist2.out"; env -u FT_PS_SNAPSHOT FT_PS_CMD="cat $T/badlst.txt" bash "$REAP" --snapshot="$T/exist2.out" >/dev/null 2>&1; rc=$?
rc_is "$rc" 20 "H1-2c 생산도 같은 검증(잘못된 lstart 는 스냅샷으로 발행 안 함)"; [ ! -e "$T/exist2.out" ] && ok "H1-2c 파일 없음" || bad "H1-2c 파일 남음"
cp "$T/ps4.txt" "$T/oldloop.txt"; touch -t 202001010000 "$T/oldloop.txt"
o="$(RUN "$T/oldloop.txt" --dry-run --quiet)"; rc=$?; rc_is "$rc" 20 "H1-3 오래된 루프 스냅샷 → rc 20"; has "$o" "오래됨" "H1-3 사유 줄"
o="$(FT_PS_SNAPSHOT_MAX_AGE=999999999 FT_PS_SNAPSHOT="$T/oldloop.txt" bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?; rc_is "$rc" 10 "H1-3b 신선도 상한을 늘리면 같은 파일이 통과(검사가 신선도임을 대조)"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="cat $T/ps4.txt" bash "$REAP" --snapshot="$T/nodir/x.out" 2>&1)"; rc=$?
rc_is "$rc" 20 "H1-4 쓰기 실패(없는 폴더) → rc 20"; has "$o" "스냅샷 쓰기 실패" "H1-4 사유 줄"; [ ! -e "$T/nodir/x.out" ] && ok "H1-4 파일 없음" || bad "H1-4 파일 있음"
s0=$SECONDS; o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD='sleep 30' FT_PS_TIMEOUT=60 bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?
rc_is "$rc" 20 "H1-6 FT_PS_TIMEOUT=60 주입 → 7 로 제한돼 timeout rc 20"; [ $((SECONDS-s0)) -lt 12 ] && ok "H1-6 12초 안(60초 아님)" || bad "H1-6 12초 초과"; has "$o" "WARN FT_PS_TIMEOUT=60" "H1-6 WARN 1줄"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD='cat /nonexistent-ps' bash "$REAP" --min-cpu=abc --dry-run --quiet 2>&1)"; rc=$?; rc_is "$rc" 20 "H1 잘못된 수치 인자 → rc 20"; hasnt "$o" "Traceback" "H1 traceback 0"

# ── ③ 실제 ps: 합성 고아 1건 검출 + --kill(내 표식 스냅샷만) · 데이터 셸 비검출 ──
spawn_orphan() { python3 -c 'import subprocess,sys; print(subprocess.Popen(["sh","-c",sys.argv[1]], start_new_session=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid)' "(while :; do :; done) & : $MARK"; }   # 새 세션 = 고유 PGID(= sh pid) · sh 는 곧 끝나 busy-loop 가 고아
PGIDS="$(spawn_orphan)"; sleep 0.5
bash -c "echo 'while :; do :; done'; : $MARK-data; sleep 20" & DP=$!
sleep 0.3
LC_ALL=C ps -axo pid=,ppid=,pgid=,lstart=,time=,stat=,command= | grep "$MARK" | grep -v grep > "$T/real.txt" || true
o="$(RUN "$T/real.txt" --dry-run --min-cpu=0)"; rc=$?; rc_is "$rc" 10 "실 ps 합성 고아 dry-run 발견"; has "$o" "$MARK" "합성 고아 명령줄"; hasnt "$o" "$MARK-data" "데이터 셸 비검출(실 프로세스)"
n="$(printf '%s\n' "$o" | grep -c 'pid=')"; eq "$n" 1 "합성 고아 정확히 1건"
o="$(RUN "$T/real.txt" --kill --min-cpu=0)"; rc=$?; rc_is "$rc" 0 "--kill rc 0"; has "$o" "정리 1건 · 잔여 0건" "합성 고아만 정리"
sleep 0.3; [ -z "$(pgrep -f "while :; do :; done) & : $MARK" 2>/dev/null)" ] && ok "합성 고아 실제 소멸" || bad "합성 고아 생존"
kill -0 "$DP" 2>/dev/null && ok "데이터 셸은 살아 있음(건드리지 않음)" || bad "데이터 셸이 죽음"
kill "$DP" 2>/dev/null; DP=""
# 이 시험이 만든 그룹만 정리 → 잔여 0 확인(고유 태그)
for g in $PGIDS; do kill -TERM -- "-$g" 2>/dev/null; done; sleep 1; for g in $PGIDS; do kill -KILL -- "-$g" 2>/dev/null; done; PGIDS=""; sleep 0.3
eq "$(pgrep -f "$MARK" 2>/dev/null | wc -l | tr -d ' ')" 0 "합성 프로세스 잔여 0 (pgrep -f 고유 태그)"
echo "--- 정보: 머신 전체 pgrep -f 'while :; do :; done' = $(pgrep -f 'while :; do :; d[o]ne' 2>/dev/null | wc -l | tr -d ' ')건(다른 좌석 것 포함 · 이 시험 몫 0)"

# ── ④ 틱 경보: ft-leak-watch · ft-tick · ft-tick-team ──
B="$T/bin"; mkdir -p "$B"; for f in ft-leak-reap.sh ft-leak-watch.sh ft-tick.sh ft-tick-team.sh; do cp -p "$BIN/$f" "$B/" 2>/dev/null; done
TK="$T/tk"; mkdir -p "$TK"; printf '{"_master":"m#1","_hil_route":"p#1","m#1":{"role":"master","agent":"claude","tick":null}}\n' > "$TK/seats.json"
printf '#!/bin/bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/fakembox.sh"; printf '#!/bin/bash\nexit 1\n' > "$T/failmbox.sh"; chmod +x "$T/fakembox.sh" "$T/failmbox.sh"
printf '#!/bin/bash\necho "$*" >> "%s/reap-args.log"\nexit 0\n' "$T" > "$T/stub-reap.sh"
CK="$T/ck"; mkdir -p "$CK"; (cd "$CK" && git init -q 2>/dev/null)
ST="$T/alert.state"
reset_st() { rm -rf "$ST" "$ST.err" "$ST.lock"; }
TICK() { local tick="$1"; shift; (cd "$CK" && env "$@" FT_TICK_SEATS="$TK/seats.json" FT_TICK_STATE_DIR="$T/state" FT_TICK_MBOX="${MBOXBIN:-$T/fakembox.sh}" FT_TICK_PIDFILE="$T/tick.pid" FT_TICK_STAMP_PREFIX="$T/stamp-" \
  FT_LEAK_ALERT_STATE="$ST" FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_API_OUTAGE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 \
  FT_TICK_AUTONOMY=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_LONG=0 FT_TICK_RAISED=0 FT_TICK_DRIFT=0 FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_GOAL_INTERVAL=99999999999 bash "$B/$tick" --once 2>&1); }
sends() { local c; c="$(grep -c "$1" "$T/mbox.log" 2>/dev/null)"; echo "${c:-0}"; }
PS_OK="FT_PS_CMD=cat $T/ps4.txt"
t="$(TICK ft-tick.sh "$PS_OK")"; eq "$(sends '\[부하 유출 2건\]')" 1 "1틱: 유출 경보 1통"; has "$t" "leak-reap:" "틱 로그에 leak-reap 줄"
has "$(cat "$T/mbox.log")" "p#1" "수신자 = _hil_route(planner)"; hasnt "$(cat "$T/mbox.log")" '`' "본문 백틱 0"; has "$(cat "$T/mbox.log")" "$fp1" "본문에 사건 지문"
[ -f "$ST" ] && ok "경보 상태 파일 저장" || bad "경보 상태 파일 없음"
t="$(TICK ft-tick.sh "$PS_OK")"; eq "$(sends '\[부하 유출')" 1 "같은 지문 2틱: 추가 0"
t="$(TICK ft-tick-team.sh "$PS_OK")"; eq "$(sends '\[부하 유출')" 1 "팀 틱(같은 머신 같은 지문): 추가 0(단일 소유)"
t="$(TICK ft-tick.sh "$PS_OK" FT_LEAK_REALERT_SEC=0)"; eq "$(sends '\[부하 유출 2건\]')" 2 "재알림 간격 0 → 같은 지문 재송 1"
t="$(TICK ft-tick.sh "FT_PS_CMD=cat $T/psb.txt")"; has "$(tail -1 "$T/mbox.log")" "[부하 유출 1건]" "지문 바뀜(다른 표) → 새 통"
sleep 1.1; t="$(TICK ft-tick.sh "FT_PS_CMD=cat $T/ps0.txt")"; eq "$(sends '\[부하 유출 해소\]')" 1 "유출 사라짐 → 해소 1통"; [ ! -e "$ST" ] && ok "해소 뒤 상태 삭제" || bad "상태 남음"
t="$(TICK ft-tick.sh "FT_PS_CMD=cat $T/ps0.txt")"; eq "$(sends '\[부하 유출 해소\]')" 1 "해소 뒤 틱: 추가 0"
b="$(sends '\[부하 유출')"; t="$(TICK ft-tick.sh FT_PS_CMD=false)"
has "$t" "ERROR" "조사 실패 → 틱 로그 ERROR"; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "조사 실패 경보 1통(유출 경보와 다른 머리)"
t="$(TICK ft-tick.sh FT_PS_CMD=false)"; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "같은 오류 2틱: 추가 0"
t="$(TICK ft-tick.sh "$PS_OK")"; has "$(tail -1 "$T/mbox.log")" "[부하 유출 2건]" "오류 → 정상 복귀 시 유출 경보 정상 발신"
reset_st; : > "$T/mbox.log"; MBOXBIN="$T/failmbox.sh" t="$(MBOXBIN="$T/failmbox.sh" TICK ft-tick.sh "$PS_OK")"
has "$t" "mbox failed" "송신 실패 → stderr 1줄"; [ ! -e "$ST" ] && ok "송신 실패 → 상태 미저장(다음 틱 재시도)" || bad "송신 실패인데 상태 저장"
reset_st; : > "$T/mbox.log"; t="$(TICK ft-tick.sh "$PS_OK" FT_TICK_LEAK_REAP=0)"; eq "$(sends '\[부하')" 0 "FT_TICK_LEAK_REAP=0 → 검사·송신 0"
d="$(cd "$CK" && env "$PS_OK" FT_TICK_SEATS="$TK/seats.json" FT_TICK_STATE_DIR="$T/state-dry" FT_TICK_MBOX="$T/fakembox.sh" FT_LEAK_ALERT_STATE="$ST" bash "$B/ft-tick.sh" --dry-run 2>&1)"
has "$d" "DRY kind=leak-reap" "--dry-run → DRY kind=leak-reap"; eq "$(sends '\[부하')" 0 "--dry-run 송신 0"
d="$(cd "$CK" && env "$PS_OK" FT_TICK_SEATS="$TK/seats.json" FT_TICK_MBOX="$T/fakembox.sh" FT_LEAK_ALERT_STATE="$ST" bash "$B/ft-tick-team.sh" --dry-run 2>&1)"; has "$d" "DRY kind=leak-reap" "팀 틱 --dry-run → DRY kind=leak-reap"
# 틱은 영구히 dry-run: 대역 리퍼로 실제 인자를 기록 — --kill 0
reset_st; : > "$T/reap-args.log"; t="$(TICK ft-tick.sh FT_LEAK_REAP_BIN="$T/stub-reap.sh")"
hasnt "$(cat "$T/reap-args.log")" "--kill" "틱이 리퍼에 넘기는 인자에 --kill 0"; has "$(cat "$T/reap-args.log")" "--dry-run --quiet" "분석 호출 = --dry-run --quiet"
# 소스 근거: 주석 속 «--kill» 언급은 허용하되 호출 줄(bash … --kill)은 0
n2="$(grep -h -- '--kill' "$B/ft-leak-watch.sh" "$B/ft-tick.sh" "$B/ft-tick-team.sh" | grep -v '^\s*#' | grep -c 'bash ')"; eq "$n2" 0 "소스에 --kill 호출 줄 0"

# ── H1-5 python3 없는 watch + H2 경보 상태(DA⑥ r1) ──
W() { local mb="$1"; shift; env "$@" FT_TICK_SEATS="$TK/seats.json" FT_TICK_MBOX="$mb" FT_LEAK_ALERT_STATE="$ST" bash "$WATCH" 2>&1; }
printf '#!/bin/bash\nsleep 1\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/slowmbox.sh"; chmod +x "$T/slowmbox.sh"
mkdir -p "$T/nopy2"; for x in bash sed grep cut tr cksum date mktemp rm mkdir rmdir stat head tail cat mv sleep wc dirname basename; do [ -x "$(command -v $x)" ] && ln -sf "$(command -v $x)" "$T/nopy2/$x"; done
reset_st; : > "$T/mbox.log"; o="$(env -i PATH="$T/nopy2" FT_PS_CMD="cat $T/ps4.txt" FT_TICK_SEATS="$TK/seats.json" FT_TICK_MBOX="$T/fakembox.sh" FT_LEAK_ALERT_STATE="$ST" "$T/nopy2/bash" "$WATCH" 2>&1)"
has "$o" "leak-reap: ERROR" "H1-5 python3 없음 → 틱 로그용 ERROR 줄"; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "H1-5 python3 없어도 수신자 조회(grep)로 조사 실패 경보 1통"; has "$(cat "$T/mbox.log")" "p#1" "H1-5 수신자 = _hil_route"
reset_st; : > "$T/mbox.log"; o="$(W "$T/fakembox.sh" FT_LEAK_REAP_BIN="$T/없는리퍼.sh")"; has "$o" "ERROR" "H1 리퍼 없음 → ERROR 줄"; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "H1 리퍼 없음도 조사 실패 경보로 합류"
reset_st; : > "$T/mbox.log"; mkdir -p "$T/failmk"; printf '#!/bin/bash\necho "mktemp: fake failure" >&2; exit 1\n' > "$T/failmk/mktemp"; chmod +x "$T/failmk/mktemp"
o="$(W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps4.txt" PATH="$T/failmk:$PATH")"; has "$o" "ERROR" "H1 mktemp 실패 → ERROR 줄"; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "H1 mktemp 실패도 경보로 합류"

# H2-1 동시 발견 2틱(같은 이전 상태) → 경보 1통
reset_st; : > "$T/mbox.log"; W "$T/slowmbox.sh" FT_PS_CMD="cat $T/ps4.txt" > /dev/null & P1=$!; W "$T/slowmbox.sh" FT_PS_CMD="cat $T/ps4.txt" > /dev/null & P2=$!; wait $P1 $P2
eq "$(sends '\[부하 유출 2건\]')" 1 "H2-1 동시 발견 2틱 → 경보 1통(잠금)"; [ -f "$ST" ] && ok "H2-1 상태 1건 저장" || bad "H2-1 상태 없음"; [ ! -e "$ST.lock" ] && ok "H2-1 잠금 해제됨" || bad "H2-1 잠금 남음"
# H2-2 해소 vs 새 발견 경쟁 — 살아 있는 지문(F2)을 «해소» 로 보내면 안 된다
F2="$(env FT_PS_CMD="cat $T/psb.txt" bash "$REAP" --dry-run --quiet 2>&1 | sed -n 's/.*fp=\([0-9a-f]\{8\}\).*/\1/p' | tail -1)"
reset_st; : > "$T/mbox.log"; printf '%s %s\n' "$fp1" "$(( $(date +%s) - 1000 ))" > "$ST"
W "$T/slowmbox.sh" FT_PS_CMD="cat $T/ps0.txt" > /dev/null & P1=$!; W "$T/slowmbox.sh" FT_PS_CMD="cat $T/psb.txt" > /dev/null & P2=$!; wait $P1 $P2
hasnt "$(grep '해소' "$T/mbox.log" 2>/dev/null)" "$F2" "H2-2 새로 발견된 지문($F2)을 해소로 보내지 않음"
if [ -f "$ST" ]; then eq "$(cut -d' ' -f1 "$ST")" "$F2" "H2-2 상태가 남았다면 새 지문"; else ok "H2-2 상태 없음 = 해소가 먼저 끝난 직렬화(새 발견은 다음 틱)"; fi
[ "$(grep -c . "$T/mbox.log")" -le 2 ] && ok "H2-2 쪽지 2통 이하" || bad "H2-2 쪽지 과다"
# H2-3 유출 → 조사 실패 → 정상: 해소 1통(유출 칸 보존)
reset_st; : > "$T/mbox.log"; W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps4.txt" >/dev/null; sleep 1.1
W "$T/fakembox.sh" FT_PS_CMD=false >/dev/null; [ -f "$ST" ] && ok "H2-3 조사 실패 중에도 미해소 유출 칸 보존" || bad "H2-3 유출 칸이 오류에 덮임"; [ -f "$ST.err" ] && ok "H2-3 조사 실패 칸 따로 저장" || bad "H2-3 오류 칸 없음"
sleep 1.1; W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps0.txt" >/dev/null
eq "$(sends '\[부하 유출 해소\]')" 1 "H2-3 유출→오류→0 에서 해소 1통"; has "$(grep '해소' "$T/mbox.log")" "$fp1" "H2-3 해소 지문 = 처음 유출 지문"; [ ! -e "$ST" ] && [ ! -e "$ST.err" ] && ok "H2-3 두 칸 모두 정리" || bad "H2-3 상태 남음"
# H2-3b 오류 지문은 임시 경로·긴 숫자에 흔들리지 않는다(같은 원인 = 같은 지문)
reset_st; : > "$T/mbox.log"; printf '#!/bin/bash\necho "ps broke at /tmp/tmp.$RANDOM$RANDOM pid $RANDOM$RANDOM" >&2; exit 3\n' > "$T/flaky-ps.sh"; chmod +x "$T/flaky-ps.sh"
W "$T/fakembox.sh" FT_PS_CMD="$T/flaky-ps.sh" >/dev/null; W "$T/fakembox.sh" FT_PS_CMD="$T/flaky-ps.sh" >/dev/null; eq "$(sends '\[부하 유출 조사 실패\]')" 1 "H2-3b 경로·숫자만 다른 같은 오류 → 600초 억제"
# H2-4 송신 실패 → 상태 미저장 → 다음 틱 재시도
reset_st; : > "$T/mbox.log"; o="$(W "$T/failmbox.sh" FT_PS_CMD="cat $T/ps4.txt")"; has "$o" "mbox failed" "H2-4 송신 실패 stderr"; [ ! -e "$ST" ] && ok "H2-4 상태 미저장" || bad "H2-4 상태 저장됨"
W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps4.txt" >/dev/null; eq "$(sends '\[부하 유출 2건\]')" 1 "H2-4 다음 틱 재시도 1통"
# 오래된 잠금 잔재는 회수한다 · 새 잠금은 존중한다
reset_st; : > "$T/mbox.log"; mkdir "$ST.lock"; touch -t 202001010000 "$ST.lock"; W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps4.txt" >/dev/null; eq "$(sends '\[부하 유출 2건\]')" 1 "오래된 잠금 잔재 회수 → 경보 발신"
reset_st; : > "$T/mbox.log"; mkdir "$ST.lock"; W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps4.txt" >/dev/null; eq "$(sends '\[부하')" 0 "새 잠금이 잡혀 있으면 이 틱 알림은 건너뜀"
reset_st

echo "--- 증거: 시험 로케일 ${LC_ALL:-기본}"
if [ -z "${R347_SECOND:-}" ] && [ "$fail" -eq 0 ]; then LC_ALL=C.UTF-8 R347_SECOND=1 bash "${BASH_SOURCE[0]:-$0}" | tail -2; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=$((fail+1)); fi
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
