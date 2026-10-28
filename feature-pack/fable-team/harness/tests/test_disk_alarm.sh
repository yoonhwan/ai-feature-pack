#!/usr/bin/env bash
# test_disk_alarm.sh — ft-disk-alarm.sh (R246): 여유 문턱별 planner 쪽지 · 반복 억제 · 회복 · 측정 실패.
# 가짜 df(FT_DISK_FREE_GIB)·가짜 시계(FT_DISK_NOW)·가짜 mbox·임시 루트만 쓴다 — 실 쪽지·실 상태 파일 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="$REPO/harness/bin/ft-disk-alarm.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/R"; mkdir -p "$R/.fable-team/state"
MLOG="$T/mbox.log"; : > "$MLOG"
printf '#!/bin/sh\nprintf "%%s|%%s|%%s\\n" "$2" "$3" "$4" >> "%s"\n' "$MLOG" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '{"_hil_route":"byz-planner-master-claude#99"}\n' > "$T/seats.json"
printf '#!/bin/sh\nprintf "== 디스크 증가 상위 (직전 스냅샷 대비) ==\\n  /private/tmp/aaa  +3.00G  10.0MB/min\\n  worktrees.total  +2.00G  5.0MB/min\\n  pytest  +1.00G  1.0MB/min\\n  extra  +0.50G  1.0MB/min\\n== 디스크 증가 상위 (1시간 전 대비) ==\\n  zzz  +9.00G  1.0MB/min\\n"\n' > "$T/watch.sh"; chmod 755 "$T/watch.sh"

NOW=1000000
# run <여유GiB|fail> <시계 오프셋 초> — 쪽지 로그를 비우고 1회 실행
run() { : > "$MLOG"; env FT_RES_ROOT="$R" FT_DISK_FREE_GIB="$1" FT_DISK_NOW=$((NOW+$2)) FT_MBOX_SH="$T/mbox.sh" \
  FT_SEATS_JSON="$T/seats.json" FT_RES_WATCH_SH="$T/watch.sh" FT_SCRATCH_REPO_SH="${SCR_STUB:-$T/noscratch.sh}" FT_MBOX_SH="${MBOX_STUB:-$T/mbox.sh}" bash "$SUT" >"$T/out" 2>&1; RC=$?; }
printf '#!/bin/sh\nexit 0\n' > "$T/noscratch.sh"; chmod 755 "$T/noscratch.sh"   # 실 TMPDIR 을 건드리지 않게 항상 가짜 주입
export FT_DOCKER_REAP_SH="$T/noscratch.sh"   # 실 docker 를 건드리지 않게 시험 컨테이너 리퍼도 항상 가짜(기본 = 출력 0 → 쪽지 0)
export FT_WT_MODE_STAMP_SH="$T/noscratch.sh"   # r843 r2: 표식 탐지도 기본 가짜(출력 0 → 쪽지 0)
printf '#!/bin/sh\necho "[scratchpad 사본] DEAD-SAFE 0개 0.00GiB · DEAD-KEEP 0 · LIVE 0 · UNKNOWN 0 · 삭제 0"\n' > "$T/spc0.sh"; chmod 755 "$T/spc0.sh"
export FT_SCRATCHPAD_CENSUS_SH="$T/spc0.sh"   # r1080: scratchpad 사본 표도 기본 가짜(사본 0 = 쪽지 0 · 실 scratchpad 스캔 0)
sent() { grep -c . "$MLOG"; }
has()  { grep -q -- "$1" "$MLOG"; }

[ -f "$SUT" ] || { bad "ft-disk-alarm.sh 없음"; echo "(1 failed)"; exit 1; }

run 60 0;    [ "$(sent)" = 0 ] && [ $RC = 0 ] && ok "ⓐ 60Gi 쪽지 0" || bad "ⓐ sent=$(sent) rc=$RC"
run 45 1000
{ [ "$(sent)" = 1 ] && has 'byz-planner-master-claude#99|' && has '\[디스크 경고\] 여유 45Gi · 상위 3: /private/tmp/aaa +3.00G, worktrees.total +2.00G, pytest +1.00G'; } \
  && ok "ⓑ 45Gi 경고 1통 · 상위 3" || bad "ⓑ $(cat "$MLOG")"
has 'extra' && bad "ⓑ 상위 4번째 포함" || ok "ⓑ 상위 3 에서 끊김"
run 45 1100; [ "$(sent)" = 0 ] && ok "ⓒ 15분 안 재호출은 측정 자체 생략" || bad "ⓒ 주기 안 sent=$(sent)"
run 45 2000; [ "$(sent)" = 0 ] && ok "ⓒ 같은 단계 60분 안 재측정 0통" || bad "ⓒ 1000초 뒤 sent=$(sent)"
run 45 5000; [ "$(sent)" = 1 ] && has '\[디스크 경고\]' && ok "ⓒ 60분 뒤 같은 단계 재알림" || bad "ⓒ 60분 뒤 sent=$(sent)"
run 25 6000; [ "$(sent)" = 1 ] && has '\[디스크 긴급\]' && ok "ⓓ 25Gi 긴급 즉시(경고 뒤라도)" || bad "ⓓ $(cat "$MLOG")"
run 25 6950; [ "$(sent)" = 1 ] && has '\[디스크 긴급\]' && ok "ⓔ 긴급 유지 15분마다 1통" || bad "ⓔ sent=$(sent)"
run 25 7100; [ "$(sent)" = 0 ] && ok "ⓔ 15분 안 반복 0" || bad "ⓔ 15분 안 sent=$(sent)"
run 40 8000; [ "$(sent)" = 1 ] && has '\[디스크 경고\]' && ok "긴급→여유 40Gi(≥35) 경고 단계로 내림 1통" || bad "긴급→경고 $(cat "$MLOG")"
run 54 9000; [ "$(sent)" = 0 ] && ok "경고 단계 54Gi(<55) 회복 아님 · 쪽지 0" || bad "히스테리시스 sent=$(sent)"
run 57 10000; [ "$(sent)" = 1 ] && has '\[디스크 회복\]' && ok "ⓕ 57Gi 회복 1통" || bad "ⓕ $(cat "$MLOG")"
run 57 11000; [ "$(sent)" = 0 ] && ok "ⓕ 회복 뒤 상태 초기화 · 쪽지 0" || bad "ⓕ 초기화 sent=$(sent)"
run 45 12000; [ "$(sent)" = 1 ] && has '\[디스크 경고\]' && ok "ⓕ 초기화 뒤 경고 새로 1통" || bad "ⓕ 재경고 sent=$(sent)"
run fail 13000
{ [ "$(sent)" = 1 ] && has '\[디스크 측정 실패\]' && grep -q 'ERROR' "$R/.fable-team/state/disk-alarm.log"; } \
  && ok "ⓖ df 실패 → ERROR 로그 + 측정 실패 쪽지" || bad "ⓖ $(cat "$MLOG")"
printf '#!/bin/sh\necho "주인 없는 임시 사본 3개 1.5 GiB"\n' > "$T/scratch.sh"; chmod 755 "$T/scratch.sh"
: > "$MLOG"; env FT_RES_ROOT="$R" FT_DISK_FREE_GIB=45 FT_DISK_NOW=$((NOW+15000)) FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/seats.json" \
  FT_RES_WATCH_SH="$T/watch.sh" FT_SCRATCH_REPO_SH="$T/scratch.sh" bash "$SUT" >"$T/out" 2>&1
grep -q '주인 없는 임시 사본 3개 1.5 GiB' "$MLOG" && ok "경고 쪽지에 주인 없는 임시 사본 1줄 첨부" || bad "사본 줄 $(cat "$MLOG")"
echo '{}' > "$T/empty.json"
: > "$MLOG"; env FT_RES_ROOT="$R" FT_DISK_FREE_GIB=40 FT_DISK_NOW=$((NOW+20000)) FT_MBOX_SH="$T/mbox.sh" FT_SEATS_JSON="$T/empty.json" \
  FT_RES_WATCH_SH="$T/watch.sh" bash "$SUT" >"$T/out" 2>&1; RC=$?
{ [ $RC != 0 ] && [ "$(sent)" = 0 ] && grep -q 'ERROR' "$T/out"; } && ok "ⓗ _hil_route 없음 → ERROR rc≠0 · 옛 이름 발신 0" || bad "ⓗ rc=$RC sent=$(sent)"

# 하루 1회 사본 정리(판정 1920): 가짜 scratch 가 호출 횟수를 센다
printf '#!/bin/sh\n[ "$1" = --sweep ] || exit 0\necho x >> "%s/sweep.calls"\necho "[임시 사본 목록 보고 · 실삭제 0 · 다음 정리부터 자동] 주인 없는 사본 2개 0.10 GiB"\n' "$T" > "$T/sweep.sh"; chmod 755 "$T/sweep.sh"
SCR_STUB="$T/sweep.sh" run 60 100000
{ [ "$(grep -c . "$T/sweep.calls" 2>/dev/null)" = 1 ] && has '임시 사본 목록 보고 · 실삭제 0' && has 'byz-planner-master-claude#99|'; } && ok "사본 정리 24h 경과 → --sweep 1회 · 결과 1줄 planner 로" || bad "sweep $(cat "$MLOG")"
SCR_STUB="$T/sweep.sh" run 60 101000
[ "$(grep -c . "$T/sweep.calls")" = 1 ] && ok "사본 정리 하루 안 재호출 0" || bad "sweep 재호출 $(grep -c . "$T/sweep.calls")"

# 하루 1회 시험 컨테이너 정리(R352): 가짜 리퍼가 호출 횟수·인자를 센다 — 지운 결과·실패는 planner 로, «후보 0» 은 로그만
printf '#!/bin/sh\necho "$*" >> "%s/reap.calls"\n[ -e "%s/reap.fail" ] && { echo "ERROR docker-test-reap: docker ps 실패" >&2; exit 20; }\necho "주인 죽은 시험 컨테이너 2 제거 · 익명 볼륨 2 제거"\n' "$T" "$T" > "$T/reap.sh"; chmod 755 "$T/reap.sh"
FT_DOCKER_REAP_SH="$T/reap.sh" run 60 200000
{ [ "$(grep -c . "$T/reap.calls" 2>/dev/null)" = 1 ] && grep -qx -- '--kill' "$T/reap.calls" && has '\[시험 컨테이너 정리\] rc=0 주인 죽은 시험 컨테이너 2 제거' && has 'byz-planner-master-claude#99|'; } \
  && ok "시험 컨테이너 정리 24h 경과 → --kill 1회 · 지운 결과 1줄 planner 로" || bad "reap $(cat "$MLOG")"
FT_DOCKER_REAP_SH="$T/reap.sh" run 60 201000
[ "$(grep -c . "$T/reap.calls")" = 1 ] && [ "$(sent)" = 0 ] && ok "시험 컨테이너 정리 하루 안 재호출 0" || bad "reap 재호출 $(grep -c . "$T/reap.calls")"
touch "$T/reap.fail"; FT_DOCKER_REAP_SH="$T/reap.sh" run 60 300000
{ [ "$(grep -c . "$T/reap.calls")" = 2 ] && has '\[시험 컨테이너 정리 실패\] rc=20' && grep -q 'docker-test-reap rc=20' "$R/.fable-team/state/disk-alarm.log"; } \
  && ok "시험 컨테이너 정리 실패(rc20) → 로그 + planner 쪽지(조용한 0 없음)" || bad "reap 실패 $(cat "$MLOG")"
# ⓟ1: rc20 + 송신 실패 → pending 보관, 다음 틱엔 «경보만» 재시도(리퍼 재호출 0)
printf '#!/bin/sh\nexit 1\n' > "$T/mboxfail.sh"; chmod 755 "$T/mboxfail.sh"
MBOX_STUB="$T/mboxfail.sh" FT_DOCKER_REAP_SH="$T/reap.sh" run 60 400000
{ [ "$(grep -c . "$T/reap.calls")" = 3 ] && [ -s "$R/.fable-team/state/docker-reap.pending" ]; } && ok "ⓟ1 rc20 + 송신 실패 → pending 보관" || bad "ⓟ1 pending $(ls "$R/.fable-team/state")"
FT_DOCKER_REAP_SH="$T/reap.sh" run 60 401000
{ [ "$(grep -c . "$T/reap.calls")" = 3 ] && has '\[시험 컨테이너 정리 실패\] rc=20' && [ "$(sent)" = 1 ] && [ ! -e "$R/.fable-team/state/docker-reap.pending" ]; } \
  && ok "ⓟ1 다음 틱 경보만 재시도 1 · 리퍼 재호출 0 · pending 해소" || bad "ⓟ1 재시도 calls=$(grep -c . "$T/reap.calls") $(cat "$MLOG")"
FT_DOCKER_REAP_SH="$T/reap.sh" run 60 402000
[ "$(sent)" = 0 ] && ok "ⓟ1 해소 뒤 재전송 0" || bad "ⓟ1 재전송 $(sent)"
# ⓟ2: rc20 인데 본문이 OK 로 시작 → 본문 모양과 무관하게 경보 1
printf '#!/bin/sh\necho x >> "%s/reap.calls"\necho "OK 후보 0 — 겉보기 정상"\nexit 20\n' "$T" > "$T/reap_ok20.sh"; chmod 755 "$T/reap_ok20.sh"
FT_DOCKER_REAP_SH="$T/reap_ok20.sh" run 60 600000
{ [ "$(sent)" = 1 ] && has '\[시험 컨테이너 정리 실패\] rc=20 OK 후보 0'; } && ok "ⓟ2 rc20 + 본문 OK → 경보 1" || bad "ⓟ2 $(cat "$MLOG")"
rm -f "$T/reap.fail"

# r843 r2: 하루 1회 표식 없는 풀 팀 워크트리 탐지(ft-wt-mode-stamp --unmarked) — 목록은 planner 1통 · 지우기 0 · 탐지 실패도 쪽지
printf '#!/bin/sh\necho "$*" >> "%s/unm.calls"\n[ -e "%s/unm.fail" ] && { echo "REJECT 루트 폴더 없음"; exit 1; }\necho "UNMARKED /w/a teams=3 kib=1048576"\necho "UNMARKED /w/b teams=4 kib=524288"\necho "TOTAL worktrees=5 has=3 unmarked=2 mode=unmarked"\n' "$T" "$T" > "$T/unm.sh"; chmod 755 "$T/unm.sh"
FT_WT_MODE_STAMP_SH="$T/unm.sh" run 60 700000
{ [ "$(grep -c . "$T/unm.calls")" = 1 ] && grep -qx -- "--root $R --unmarked" "$T/unm.calls" && [ "$(sent)" = 1 ] && has 'byz-planner-master-claude#99|' \
  && has '\[표식 없는 풀 팀 워크트리\] 2곳 · 합 1.5GiB · 지우기 0' && has '앞 5: /w/a, /w/b' && [ "$(grep -c '^UNMARKED ' "$R/.fable-team/state/wt-unmarked.txt")" = 2 ]; } \
  && ok "ⓦ1 표식 탐지 24h 경과 → --unmarked 1회 · planner 1통(2곳 · 1.5GiB) · 전체 목록 파일" || bad "ⓦ1 calls=$(cat "$T/unm.calls") $(cat "$MLOG")"
FT_WT_MODE_STAMP_SH="$T/unm.sh" run 60 701000
{ [ "$(grep -c . "$T/unm.calls")" = 1 ] && [ "$(sent)" = 0 ]; } && ok "ⓦ2 하루 안 재호출 0" || bad "ⓦ2 calls=$(grep -c . "$T/unm.calls") sent=$(sent)"
touch "$T/unm.fail"; FT_WT_MODE_STAMP_SH="$T/unm.sh" run 60 800000
{ [ "$(sent)" = 1 ] && has '\[표식 탐지 실패\] rc=1 REJECT 루트 폴더 없음' && grep -q 'wt-unmarked rc=1' "$R/.fable-team/state/disk-alarm.log"; } \
  && ok "ⓦ3 탐지 실패 rc1 → 로그 + planner 쪽지(조용한 0 없음)" || bad "ⓦ3 $(cat "$MLOG")"
rm -f "$T/unm.fail"
printf '#!/bin/sh\necho "TOTAL worktrees=5 has=5 unmarked=0 mode=unmarked"\n' > "$T/unm0.sh"; chmod 755 "$T/unm0.sh"
FT_WT_MODE_STAMP_SH="$T/unm0.sh" run 60 900000; [ "$(sent)" = 0 ] && ok "ⓦ4 목록 0 → 쪽지 0(로그만)" || bad "ⓦ4 $(cat "$MLOG")"

# R262: 명부 env 를 «안 넣은» 기본 경로 — 임시 루트의 .fable-team/ 에 명부를 직접 둔다(env 주입이 기본값 결함을 가렸다)
# newroot <이름> <seats.json 내용> <seats-planner.json 내용> [seats-harness.json 내용] — 임시 루트 R_<이름> 만들기
newroot() { RR="$T/R_$1"; mkdir -p "$RR/.fable-team/state"; printf '%s\n' "$2" > "$RR/.fable-team/seats.json"; printf '%s\n' "$3" > "$RR/.fable-team/seats-planner.json"
  [ -z "${4:-}" ] || printf '%s\n' "$4" > "$RR/.fable-team/seats-harness.json"; }
# rund <루트> <여유GiB> <시계 오프셋> — FT_SEATS_JSON·FT_HARNESS_SEATS_JSON 을 unset 하고 1회 실행
rund() { : > "$MLOG"; env -u FT_SEATS_JSON -u FT_HARNESS_SEATS_JSON FT_RES_ROOT="$1" FT_DISK_FREE_GIB="$2" FT_DISK_NOW=$((NOW+$3)) FT_MBOX_SH="$T/mbox.sh" \
  FT_RES_WATCH_SH="$T/watch.sh" FT_SCRATCH_REPO_SH="$T/noscratch.sh" bash "$SUT" >"$T/out" 2>&1; RC=$?; }

newroot i '{}' '{"_hil_route":"byz-planner-master-claude#77"}'; rund "$RR" 25 0
{ [ $RC = 0 ] && [ "$(sent)" = 1 ] && has 'byz-planner-master-claude#77|' && has '\[디스크 긴급\]' && [ -f "$RR/.fable-team/state/disk-alarm.state" ]; } \
  && ok "ⓘ 기본 명부 = seats-planner.json — 긴급 1통 · state 생김" || bad "ⓘ rc=$RC $(cat "$MLOG")"
newroot j '{}' '{}' '{"_master":"byz-harness-master-claude#88"}'; RJ="$RR"; rund "$RJ" 25 0
{ [ $RC = 3 ] && grep -q 'ERROR' "$T/out" && [ "$(sent)" = 1 ] && has 'byz-harness-master-claude#88|' && has '\[디스크 경보 수신자 없음\]' && has '여유 25Gi'; } \
  && ok "ⓙ 수신자 없음 → rc3 · 하네스 master 에 고장 쪽지 1통(여유 25Gi) · planner 발신 0" || bad "ⓙ rc=$RC $(cat "$MLOG")"
has 'byz-planner' && bad "ⓙ 경보 본문을 planner 로 대신 보냄" || ok "ⓙ planner 발신 0"
rund "$RJ" 25 600;  { [ $RC = 3 ] && [ "$(sent)" = 0 ]; } && ok "ⓚ +600초 고장 쪽지 0(1시간 1통)" || bad "ⓚ +600 rc=$RC sent=$(sent)"
rund "$RJ" 25 3700; { [ $RC = 3 ] && [ "$(sent)" = 1 ] && has '\[디스크 경보 수신자 없음\]'; } && ok "ⓚ +3700초 고장 쪽지 다시 1통" || bad "ⓚ +3700 rc=$RC sent=$(sent)"
printf '{"_hil_route":"byz-planner-master-claude#77"}\n' > "$RJ/.fable-team/seats-planner.json"; rund "$RJ" 25 3760
{ [ $RC = 0 ] && [ "$(sent)" = 1 ] && has 'byz-planner-master-claude#77|' && has '\[디스크 긴급\]'; } \
  && ok "ⓛ 명부 고친 뒤 +60초 → 정상 경로 즉시(15분 주기가 고장 기간에 안 먹힘)" || bad "ⓛ rc=$RC $(cat "$MLOG")"
newroot m '{}' '{}'; rund "$RR" 25 0
{ [ $RC = 3 ] && [ "$(sent)" = 0 ] && [ "$(grep -c 'ERROR' "$RR/.fable-team/state/disk-alarm.log")" = 2 ]; } \
  && ok "ⓜ 두 명부 모두 키 없음 → rc3 · 쪽지 0 · ERROR 2줄" || bad "ⓜ rc=$RC sent=$(sent) $(cat "$RR/.fable-team/state/disk-alarm.log")"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
