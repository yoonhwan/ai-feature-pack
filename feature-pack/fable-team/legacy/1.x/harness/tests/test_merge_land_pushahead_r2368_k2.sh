#!/usr/bin/env bash
# test_merge_land_pushahead_r2368_k2.sh — r2368 뒷갈래: K2 판정(앞 대조가 ok 가 아닐 때 뒤 길 그대로) · K4 호출 0 안내 글자 · 팩 리포 뒤 검사 글자 그대로
#   이 파일 = 반례 ⑥(앞 대조 rc3) · ⑥-b(⑥ + 뒤 끊김 = 대기 파일 + range 줄) · ⑦(앞 대조 끊김 124) · ⑧(첫 줄 «OK n=2») · ⑨(다른 체크아웃 = 조용한 통과 0) · ⑪(팩 리포 · 뒤 단계 남은 ≤ 3 = 호출 0 «판정 불가») · ⑫(팩 리포 · 뒤 검사 끊김 = 지금 글자)
#   ①~⑤⑩⑬ = test_merge_land_pushahead_r2368.sh · 변이 M1~M4 = _mut.sh · M5~M7 = _mut2.sh · M8 = _mut3.sh · M9 = _mut4.sh · 기준판 Red = _red.sh(70초 상한으로 쪼갬)
#   격리 = _pushahead_r2368_fixture.sh · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:1200}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix; pa_bin
S1=$SECONDS

p6 "$FIX" >/dev/null; ck "⑥ 앞 대조 rc3 → HPRE 0 · 뒤 검사 부름 1 · 조용한 통과 0" $?
p6b "$FIX" >/dev/null; ck "⑥-b ⑥ + 뒤 끊김 → 대기 파일 = «검사 시간 초과» + range 줄(지금 꼴)" $?
S2=$SECONDS
p7 "$FIX" >/dev/null; ck "⑦ 앞 대조 끊김(124) → HPRE 0 · push 시도 1 · 착지 1 · 뒤 길 그대로" $?
p8 "$FIX" >/dev/null; ck "⑧ 앞 대조 rc0 첫 줄 «OK n=2» → HPRE 0 · 뒤 검사 부름 1" $?
p9 "$FIX" >/dev/null; ck "⑨ 다른 체크아웃(코드 루트 밖) · 앞 대조 rc3 → HPRE 0 · 뒤 길 그대로(조용한 통과 0)" $?
S3=$SECONDS
p11 "$FIX" >/dev/null; ck "⑪ 팩 리포 · 뒤 단계 남은 0 → 검사 부름 0 · «판정 불가 — 설치 검사 호출 0(남은 0초)» · 대기 파일 그대로" $?
p12 "$FIX" >/dev/null; ck "⑫ 팩 리포 · 뒤 검사 끊김 → «설치 검사 1초 초과 — 손으로: …» 지금 글자 · 대기 파일 지금 꼴" $?
echo "단계별 초: ⑥⑨ $((S2 - S1)) · ⑦⑧⑨ $((S3 - S2)) · ⑪⑫ $((SECONDS - S3)) · 합계 $((SECONDS - T0))   # ①~⑤⑩⑬ = 본체 · 변이 = _mut.sh·_mut2.sh · 기준판 Red = _red.sh"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
