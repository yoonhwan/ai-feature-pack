#!/usr/bin/env bash
# test_merge_land_reserve_r2355_mut2.sh — r2355 press 증거 검사 변이: M10 바깥 상한 0 그대로 · M11 TB rc 124 갈래 지움(끊김도 지금 글) — 둘 다 ④c 가 FAIL 이어야
#   M11 = _mut3.sh · M1~M9 = _mut.sh · 기준판 Red = _red.sh · 반례 = _reserve r2355 본체 (70초 상한 · 하드 룰 22 로 쪼갬)
#   R2355_FAST=1 = 같은 규칙 · 짧은 초 · 실 원격·실 gh·실 mbox 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export R2355_FAST=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
mut() {   # mut <이름> <사례> <파일> <옛 글> <새 글> — 사본 1벌 재사용 · 사례 FAIL 이어야 · 원본 같은 사례 = PASS
  local m="$T/mut"; [ -d "$m" ] || mkbin "$m"
  cp "$FIX/$3" "$m/$3"
  python3 - "$m/$3" "$4" "$5" <<'PY' || { echo "FAIL M$1 :: 변이 글자 1곳 아님($3)"; fail=$((fail+1)); return; }
import io, sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  if "$2" "$m"; then echo "FAIL M$1 :: 변이가 $2 를 통과"; fail=$((fail+1)); else echo "PASS M$1 ($2 FAIL)"; fi
  "$2" "$FIX"; ck "M$1-원본" $?
}
S1=$SECONDS
mut 10 k4c ft-merge-land.sh 'PEV="$("$TB" "$PSB" ' 'PEV="$('   # M10 press 바깥 상한 0 그대로
echo "단계별 초: press 변이 M10 $((SECONDS - S1)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
