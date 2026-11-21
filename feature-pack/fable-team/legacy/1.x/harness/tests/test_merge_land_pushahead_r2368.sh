#!/usr/bin/env bash
# test_merge_land_pushahead_r2368.sh — r2368: 하네스 밖 리포 착지는 설치 대조를 push 앞에서 1회 끝낸다(K1·K2·K3) — 뒤 단계 남은 시간이 0 이어도 «검사 시간 초과» 대기 파일을 남기지 않는다
#   이 파일 = 반례 ① · ⑩(① 의 착지 꼴) · ② · ③ · ⑬(③ 의 기준판 대조) · ④ · ⑤   # ⑥⑦⑧⑨⑪⑫ = _k2.sh · 변이 M1~M4 = _mut.sh · M5~M7 = _mut2.sh · M8 = _mut3.sh · M9 = _mut4.sh · 기준판 Red = _red.sh(70초 상한으로 쪼갬)
#   격리 = _pushahead_r2368_fixture.sh(r2355 격리 + 하네스 코드 루트 임시 리포 + PRE/POST 설치 검사 스텁 + 느린 push) · 실 원격·실 gh·실 mbox 0
#   ② 의 «남은 − PV < 1» 주입 = 가짜 press 가 마감을 «7.98초»(초 경계 0.3 뒤 정렬)까지 깎는다 → 남은 = 8 = PV · 앞 대조 상한 0(호출 0) · push 는 REM 8 ≥ PV 8 로 그대로 시도
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_pushahead_r2368_fixture.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:1600}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
pa_init "$T"; pa_fix; fx_base; BASE="${BASE:-}"
S1=$SECONDS

p1 "$FIX" >/dev/null; ck "① 하네스 밖 리포 · 앞 대조 ok → 대기 파일 0 · «INSTALL … · push 앞 대조(r2368)» 1줄 · 앞 대조 부름 1 · 착지 1  ｜ ⑩ LANDED · rc0 · PR 닫기 1 · 알림 설치 칸 install=0 · LAND-TAIL install=0" $?
S2=$SECONDS
p2 "$FIX" >/dev/null; ck "② push 앞 남은 − PV < 1 → 앞 대조 호출 0 · push 시도 1 · REJECT «push 몫 예약» 0" $?
p3 "$FIX" >/dev/null; ck "③ 팩 리포 → 앞 대조 0 · 뒤 검사 1  ｜ ⑬ ③ 의 설치 줄·LAND-PHASE 칸 이름·LAND-TAIL 수·닫기가 기준판과 같은 글자" $?
p4 "$FIX" >/dev/null; ck "④ --dry → 앞 대조 부름 0 · DRY 줄이 기준판과 같은 글자" $?
p5 "$FIX" >/dev/null; ck "⑤ --ff 착지 · 뒤 단계 남은 0 → 앞 대조 부름 1 · 대기 파일 0 · 착지 1(mode=ff)" $?
S3=$SECONDS
cmp -s "$FIX/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh"
ck "키트 사본 = 추적본(bin) 과 같은 글자 · 시험한 사본 = 추적본" $?
echo "단계별 초: ①⑩ $((S2 - S1)) · ②~⑤ $((S3 - S2)) · 키트 대조 $((SECONDS - S3)) · 합계 $((SECONDS - T0))   # ⑥⑦⑧⑨⑪⑫ = _k2.sh · 변이 = _mut.sh·_mut2.sh · 기준판 Red = _red.sh"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
