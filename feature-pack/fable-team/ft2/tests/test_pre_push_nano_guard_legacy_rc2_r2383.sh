#!/bin/sh
# r2383 pre-push 나노 가드 rc2 칸 시험 — 반례 ⑲ · 변이 M5 (guard rc 2 = 판정 불가 · 임시 폴더 0).
# 판정 불가를 통과로 바꾸는 변이(M5)가 ⑱ 칸(시간)을 다시 7초 두 번 돌려야 해서 이 칸을 따로 뒀다(70초 상한).
# 공통 대역 = tests/pre_push_nano_guard_r2383_lib.sh · 실 원격 0 · 여기 sleep 0.
# 실행: sh tests/test_pre_push_nano_guard_legacy_rc2_r2383.sh
. "$(dirname "$0")/pre_push_nano_guard_r2383_lib.sh"

c19() {   # ⑲ guard rc 2 → 판정 불가 + PUSH_DENIED · 임시 폴더 남음 0
  MK_HOOK=$1; d=$(mk "c19$2") || return 1
  setguard "$d" bad; mkc "$d" "ft2 rc2" || return 1
  pushof "$d" "$NANO" HEAD:refs/heads/nano/x; rc=$?
  [ "$rc" != 0 ] || { echo "  rc=0"; return 1; }
  grep -qF "판정 불가 나노 가드 legacy_guard 실행 rc=2" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  grep -qF "PUSH_DENIED" "$d/push.out" || { echo "  $(why "$d")"; return 1; }
  [ -z "$(ls -A "$d/tmp")" ] || { echo "  임시 폴더 남음: $(ls -A "$d/tmp")"; return 1; }
}

run_case 19 c19

mtest M5 18 '  case "$rc" in 124|137|143) echo 124 ;; *) echo "$rc" ;; esac▸  case "$rc" in 124|137|143) echo 0 ;; *) echo "$rc" ;; esac'

lib_done "반례 ⑲ · 변이 M5"
