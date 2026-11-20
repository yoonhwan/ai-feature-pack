#!/usr/bin/env bash
# test_merge_land_reserve_r2355_mut.sh — r2355 변이 M1~M11(사본에서만 고치고 «같은 사례가 FAIL» + «원본은 PASS» = 반대 결과 대조) + 기준판 Red 대조
#   M1 예약 빼기(k1) · M2 시작 0 판정 지움(k2b) · M3 닫기 재시도 예약 무시(k3) · M4 REJECT 길 LAND-PHASE 0(k6) · M5 받는 이 _desk 만(k9)
#   M6 같은 값 거름 지움(k10) · M7 equiv 예약 빼기(k4b) · M10 press 예약 빼기(k4c) · M11 TB rc 124 갈래 지움(k4c) · M8 drain 이 이미 받은 이에게 다시(k11b) · M9 받는 이 2 를 모든 도구에(k11c)
#   기준판 Red = ① · ④b · ④c · ⑤ · ⑨ · ⑪b (origin/main 사본에서 그 사례가 FAIL) · 반례 본체 = test_merge_land_reserve_r2355.sh(두 파일로 쪼갬 · 하드 룰 22)
#   R2355_FAST=1 = 같은 규칙 · 짧은 초 · 실 원격·실 gh·실 mbox 0 · sleep 은 «가짜 도구» 안에서만(관계를 재는 시간)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export R2355_FAST=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
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
mut 1 k1 ft-merge-land.sh 'b=$(( $(land_left) - RU ))' 'b=$(( $2 ))'   # M1 예약 = 자기 상한 그대로
mut 2 k2b ft-merge-land.sh 'rsv view 7 || rej "push 몫 예약: gh pr view 앞 남은 $(land_left)s − push 1단위 ${RU}s < 1 (착지 0 · 다음 틱)"' ':'   # M2 시작 0 판정 지움
mut 3 k3 ft-merge-land.sh 'if [ "$CRS" -ge 7 ]; then' 'if [ 1 = 1 ]; then'   # M3 닫기 재시도 예약 무시
mut 4 k6 ft-merge-land.sh "trap 'ph_line' EXIT" ':'   # M4 REJECT 길에서 LAND-PHASE 안 찍음
mut 7 k4b ft-merge-land.sh 'ES="$RSV"; phs equiv' 'ES=30; phs equiv'   # M7 equiv 예약 빼기
S2=$SECONDS
mut 5 k9 ft-critical-notify.sh '    m = desk("_master") if t == "ft-merge-land" else ""' '    m = ""'   # M5 받는 이 _desk 만
mut 6 k10 ft-critical-notify.sh '    elif m and m not in out: out.append(m)' '    elif m: out.append(m)'   # M6 같은 값 거름 지움
mut 8 k11b ft-critical-notify.sh '            if to in miss: continue' '            if to in []: continue'   # M8 drain 이 이미 받은 이에게 다시
mut 9 k11c ft-critical-notify.sh '    m = desk("_master") if t == "ft-merge-land" else ""' '    m = desk("_master")'   # M9 받는 이 2 를 모든 도구에
S3=$SECONDS
mut 10 k4c ft-merge-land.sh 'PEV="$("$TB" "$PSB" ' 'PEV="$('   # M10 press 바깥 상한 0 그대로
mut 11 k4c ft-merge-land.sh '[ "$PEC" != 124 ] || rej "push 몫 예약: press 증거 검사 ${PSB}s 에 끊김 · 남은 $(land_left)s − push 1단위 ${RU}s (착지 0 · 다음 틱)"; ' ''   # M11 rc 124 갈래 지움(끊김도 지금 글)
S4=$SECONDS
red() {   # red <사례> — 기준판(origin/main 사본)에서 그 사례가 FAIL(rc≠0) 이어야 한다
  [ -n "${BASE:-}" ] || { echo "SKIP $1 기준판 대조(origin/main 사본 없음)"; return 0; }
  if "$1" "$BASE" >/dev/null 2>&1; then echo "FAIL $1 기준판 — 고치기 전에도 통과(시험 검출력 0)"; fail=$((fail+1)); else echo "PASS $1 기준판 Red(정상)"; fi
}
for c in k1 k4b k4c k5 k9 k11b; do red "$c"; done
S5=$SECONDS
cmp -s "$BIN/ft-merge-land.sh" "$BIN/../kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$BIN/ft-critical-notify.sh" "$BIN/../kit/fable-team/bin/ft-critical-notify.sh"
ck "키트 사본 2파일 같은 글자" $?
echo "단계별 초: 예약 변이 $((S2 - S1)) · 받는 이 변이 $((S3 - S2)) · press 변이 $((S4 - S3)) · 기준판 Red $((S5 - S4)) · 사본·줄 $((SECONDS - S5)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
