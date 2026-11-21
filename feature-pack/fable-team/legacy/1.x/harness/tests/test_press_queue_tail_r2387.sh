#!/usr/bin/env bash
# test_press_queue_tail_r2387.sh — r2387 ⑪⑫⑬: 착지 꼬리 단계가 «음성 경로를 바꾼 착지» 뒤에만 queue 1회를 돌리고 STALE 줄·NEXT 줄만 1~2줄 남긴다 (K3)
#   ⑪ 착지 뒤 꼬리 · 남은 초 넉넉(≥ 11) · 음성 경로 PR 착지 → STALE 줄 + NEXT 줄 · 착지 rc 0 · LAND-TAIL 에 pressq 없음
#   ⑫ 착지 뒤 꼬리 · 남은 초 < 8 → queue 0회 · LAND-TAIL skip=pressq (시계 먹이기 0 — 마감만 짧게)
#   ⑬ 음성 경로 0 PR 착지 → queue 0회(gh pr list 0) · PR·NEXT 줄 0
#   틀 = _press_queue_tail_r2387_lib.sh(r2355 격리 + gh «pr list» 대역 + PR·묶음 도우미 · 변이 M5 와 같이 쓴다) · 실 gh·실 원격·실 mbox 0 · sleep 0
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_tail_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el:-0}s out=${out:0:1400}"; fail=$((fail+1)); fi; }
S0=$SECONDS

# ===== ⑪: 음성 경로 PR 착지 · 꼬리에 queue → STALE 줄 + NEXT 줄 · 착지 rc 0 =====
mkpr 212; H212="$PRSHA"; bundle "$H212" 20261117-131500          # #212 = 옛 main 세트 묶음(착지 뒤 무효가 된다)
plist 212 "$H212"
PRF=worker/pr211.py DL_OFF=30 land "$FIX" 211 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=211 ' <<<"$out" && grep -q '^PR #212 STALE · 다르게 만든 착지 ' <<<"$out" && [ "$(qtail | grep -c .)" = 2 ] && [ "$(listn)" = 1 ] \
  && ! grep -q 'skip=.*pressq' <<<"$(ltail)"
ck "⑪ 음성 경로 착지(rc 0) → 꼬리 = STALE 줄 + NEXT 줄 2줄 · gh pr list 1회 · pressq skip 0" $?
echo "단계 초: ⑪ $((SECONDS - S0))s"

# ===== ⑫: 꼬리 남은 초 < 8 → queue 0회 · LAND-TAIL skip=pressq =====
PRF=worker/pr213.py DL_OFF=10 FT_PUSH_FIXED_S=0.5 land "$FIX" 213 40   # 마감 10초 = 착지(1초대) 뒤 남은 < 11 → pressq 상한 = min(8, 남은−3) < 8
[ "$rc" = 0 ] && grep -q '^LANDED pr=213 ' <<<"$out" && [ "$(listn)" = 0 ] && [ "$(qtail | grep -c .)" = 0 ] && grep -q 'pressq' <<<"$(ltail)"
ck "⑫ 남은 초 < 8 → queue 0회(gh 0) · LAND-TAIL skip 에 pressq" $?
echo "단계 초: ⑫ $((SECONDS - S0))s"

# ===== ⑬: 음성 경로 0 PR 착지 → queue 0회(gh 0) · 줄 0 =====
PRF=docs/pr214.md DL_OFF=30 land "$FIX" 214 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=214 ' <<<"$out" && [ "$(listn)" = 0 ] && [ "$(qtail | grep -c .)" = 0 ] && ! grep -q 'skip=.*pressq' <<<"$(ltail)"
ck "⑬ 음성 경로 0 착지 → queue 0회(gh 0) · PR·NEXT 줄 0" $?

# ===== ⑪ 기준판 Red: 고치기 전 ft-merge-land.sh(꼬리 pressq 칸 0) 로 같은 사례 → STALE·NEXT 줄 0 =====
PACKDIR="$(git -C "$HERE" rev-parse --show-toplevel)"; QB0="$(git -C "$PACKDIR" merge-base HEAD origin/main)"   # 기준판 = 이 가지의 갈래 커밋(land·lib 짝이 맞는 판)
BFIX="$T/bfix"; cp -R "$FIX" "$BFIX"
for f in ft-merge-land.sh ft-merge-lib.sh; do   # 꼬리 pressq 칸이 없던 판(짝 = 같은 커밋의 lib)
  git -C "$PACKDIR" show "$QB0:feature-pack/fable-team/legacy/1.x/harness/bin/$f" > "$BFIX/$f" 2>/dev/null || { echo "FAIL 기준판 $f 못 읽음"; fail=$((fail+1)); }
done
PRF=worker/pr216.py DL_OFF=30 land "$BFIX" 216 40
[ "$rc" = 0 ] && grep -q '^LANDED pr=216 ' <<<"$out" && [ "$(qtail | grep -c .)" = 0 ] && [ "$(qqueue)" = 0 ]
ck "⑪ 기준판 Red — 꼬리 pressq 칸 0 이면 STALE·NEXT 줄 0 · queue 부름 0(착지 rc 는 0 그대로)" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 mbox 0)" $?
echo "단계 초: ⑬·Red $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
