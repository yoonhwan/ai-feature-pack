#!/usr/bin/env bash
# test_disk_alarm.sh — ft-disk-alarm.sh (R246): 여유 문턱별 planner 쪽지 · 반복 억제 · 회복 · 측정 실패.
# 가짜 df(FT_DISK_FREE_GIB)·가짜 시계(FT_DISK_NOW)·가짜 mbox·임시 루트만 쓴다 — 실 쪽지·실 상태 파일 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="$REPO/scripts/fable-team-bin/ft-disk-alarm.sh"
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
  FT_SEATS_JSON="$T/seats.json" FT_RES_WATCH_SH="$T/watch.sh" FT_SCRATCH_REPO_SH="${SCR_STUB:-$T/noscratch.sh}" bash "$SUT" >"$T/out" 2>&1; RC=$?; }
printf '#!/bin/sh\nexit 0\n' > "$T/noscratch.sh"; chmod 755 "$T/noscratch.sh"   # 실 TMPDIR 을 건드리지 않게 항상 가짜 주입
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

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
