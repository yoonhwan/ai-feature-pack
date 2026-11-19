#!/usr/bin/env bash
# test_merge_land_tail_deadline_r2320.sh — r2320: 착지 1회가 바깥 70초 상한 안에서 끝난다 · 착지 알림은 루트 shim·뒤처짐 확인보다 먼저 · 꼬리를 건너뛰거나 잘리면 «LAND-TAIL» 1줄
#   계약 T1 마감 기본·한 시계 · T2 알림 앞으로 · T3 꼬리 단계 초 · T4 불변·바뀜 · T5 앞 길 마감(try-auto)
#   반례 ①~⑦ ⑨~⑪(여기) + 변이 M1~M7 = test_merge_land_tail_deadline_r2320_mut.sh(시험 1개 70초 상한 · 하드 룰 22 — 쪼갬)
#   ⑧ 회귀 = test_merge_land_close_before_lag_r1389.sh · test_merge_land_tail_bound_r2061.sh(_mut) · test_merge_land_root_shim_r1845.sh · test_try_auto_land_r2293.sh · test_try_auto_land_ok_line_r2295.sh · test_autonomy_try_auto_r1745.sh 따로 실행
#   격리: fixture = 임시 origin+clone · 가짜 gh·설치 대조·head-lag·루트 shim·착지 알림·git(push/ls-remote) · 실 원격·실 gh·실 mbox 0 · sleep 0 · R2320_BIN=<bin> 이면 그 사본이 대상(기준판 대조)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_tail_deadline_r2320_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
S1=$SECONDS
for c in k1 k2 k3 k4 k5 k6 k11 k10b k10 k12; do "$c" "$FIX"; ck "$c" $?; done
S2=$SECONDS
fx_base; k7; ck "k7(문서 꼴 = 기준판과 같은 줄 · LAND-TAIL 0)" $?
S3=$SECONDS
KITB="${R2320_KIT:-$BIN/../kit/fable-team/bin}"
if [ -d "$KITB" ]; then cmp -s "$BIN/ft-merge-land.sh" "$KITB/ft-merge-land.sh" && cmp -s "$BIN/ft-autonomy-try.sh" "$KITB/ft-autonomy-try.sh"; ck "키트 사본 cmp0(merge-land·autonomy-try)" $?; else echo "SKIP 키트 사본 cmp — 대상 폴더에 kit 없음($KITB)"; fi
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ] && [ "$(wc -l < "$BIN/ft-autonomy-try.sh" | tr -d ' ')" -le 100 ] && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-autonomy-try.sh"
ck "줄 상한(merge-land 120 · autonomy-try 100) · bash -n" $?
echo "단계별 초: 반례 $((S2 - S1)) · ⑦ $((S3 - S2)) · 사본·줄 $((SECONDS - S3)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
