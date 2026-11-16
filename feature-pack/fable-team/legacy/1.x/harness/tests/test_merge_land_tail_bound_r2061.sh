#!/usr/bin/env bash
# test_merge_land_tail_bound_r2061.sh — r2061: 착지 뒤 꼬리 단계(설치 대조 · 뒤처짐 알림 · 착지 알림)는 손자가 출력을 잡고 남아도 상한 안에 돌아온다
#   꼬리 실행 = ft-merge-lib.sh fm_tail_run 한 함수(출력은 임시 파일 · 직접 자식 pid 만 wait) · 꼬리 상한 = min(지정, 마감 남은 초 − 3)
#   ① 뒤처짐 알림 손자 멈춤 ② 설치 대조 손자 멈춤 ③ 둘 다 ④ 바로 끝남 = 옛 꼴(명령 치환·여유 0)과 출력 같음 ⑤ 남은 ≤ 3초 = 꼬리 호출 0 ⑥ 닫기 실패 + 뒤처짐 멈춤 = rc3
#   변이 M1·M2·M3 + ⑧(착지 알림) = test_merge_land_tail_bound_r2061_mut.sh(시험 1개 70초 상한 · 하드 룰 22 — 쪼갬) · fixture = _tail_bound_r2061_fixture.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_tail_bound_r2061_fixture.sh"; T0=$SECONDS
TT="$(mktemp -d)"; trap 'for f in "$TT"/fifo-*; do rel "$f"; done; rm -rf "$TT"' EXIT; fx_init "$TT"
S1=$SECONDS; FIX="$T/bin"; mkbin "$FIX"
c1 "$FIX" 61 12; ck "① 뒤처짐 알림 손자 멈춤 · 마감 12 → rc0 · 마감 안 · WARN 1줄 · LANDED" $?
c2 "$FIX" 62 12; ck "② 설치 대조 손자 멈춤 · 마감 12 → rc0 · INSTALL-PENDING 1줄 · 대기 파일 1" $?
land "$FIX" 63 14 FT_LAND_TOTAL_S=12 HOLD_LAG=1 HOLD_INSTALL=1 FT_INSTALL_CHECK_TIMEOUT=2 FT_HEAD_LAG_EVENT_S=2
[ "$rc" = 0 ] && [ "$el" -le 12 ] && grep -q '^INSTALL-PENDING 설치 검사' <<<"$out" && grep -qE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out"; ck "③ 둘 다 멈춤 → rc0 · 마감 안 · 두 줄" $?
S2=$SECONDS
mkbin "$T/b0" ft-merge-land.sh "$NEWI" "$OLDI" ft-merge-land.sh "$NEWH" "$OLDH" ft-merge-lib.sh 'r=$((r - 3)); ' ''; B0=$?
land "$FIX" 64 30; o4="$out"; r4=$rc; land "$T/b0" 65 30
[ "$B0" = 0 ] && [ "$r4" = 0 ] && [ "$rc" = 0 ] && [ "$(norm <<<"$o4")" = "$(norm <<<"$out")" ] && grep -q '^판정 불가 2곳' <<<"$o4" && ! grep -q '^WARN' <<<"$o4" && grep -q '^INSTALL OK n=1' <<<"$o4"
ck "④ 바로 끝남 → 옛 꼴(명령 치환 · 여유 0)과 줄·순서 같음 · 판정 불가 줄 통과" $?
land "$FIX" 66 14 FT_LAND_TOTAL_S=12 "FT_LAND_DEADLINE=$(( $(date +%s) + 3 ))"
[ "$rc" = 0 ] && grep -q '^LANDED' <<<"$out" && ! ran install && ! ran head-lag && grep -q '^INSTALL-PENDING 설치 검사 0초 초과' <<<"$out" && grep -q '^WARN 뒤처짐 알림 0초 초과' <<<"$out"
ck "⑤ 마감 남은 ≤ 3초 → 꼬리 호출 0 · 문구 1줄씩" $?
CPL="$T/state/merge-close-pending.jsonl"; : > "$CPL"
land "$FIX" 67 14 FT_LAND_TOTAL_S=12 HOLD_LAG=1 FAIL_CLOSE=1 FT_HEAD_LAG_EVENT_S=2
[ "$rc" = 3 ] && [ "$el" -le 12 ] && [ "$(grep -c . "$CPL")" = 1 ] && grep -qE '^WARN 뒤처짐 알림 [0-9]+초 초과' <<<"$out"; ck "⑥ 닫기 실패 + 뒤처짐 멈춤 → rc3 · 닫기 대기 1줄" $?
: > "$CPL"; S3=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-lib.sh" "$BIN/../kit/fable-team/bin/ft-merge-lib.sh"; ck "키트 사본 cmp0(land·lib)" $?
[ "$(wc -l < "$BIN/ft-merge-land.sh" | tr -d ' ')" -le 120 ] && bash -n "$BIN/ft-merge-land.sh" && bash -n "$BIN/ft-merge-lib.sh"; ck "ft-merge-land.sh ≤ 120줄 · bash -n" $?
echo "단계별 초: ①~③ $((S2 - S1)) · ④~⑥ $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
