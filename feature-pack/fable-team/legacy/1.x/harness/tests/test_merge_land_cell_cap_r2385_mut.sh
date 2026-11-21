#!/usr/bin/env bash
# test_merge_land_cell_cap_r2385_mut.sh — r2385 K6·K7 변이: 사본에서만 고치고 «같은 사례가 FAIL» + «원본 같은 사례 PASS»(반대 결과 대조)
#   M10 gate 칸 press 예약 지움(⑲) · M11 gate 직전 소요 지움(⑳) · EM1 EQUIV 칸 30 고정(E②) · EM2 EQUIV press 예약 지움(E②) · EM3 천장 지움(E③) · EM4 시간 초과 글 갈래 지움(E⑦) · EM6 EQUIV-CAP 을 늘 찍음(E⑪)
#   EM5(자동 병합 글 갈래)는 S0(자동 병합 판)를 세우는 fixture 가 따로 필요해 이 파일 밖 — 원본 대조는 각 변이 뒤에 바로 돈다 · 격리 = _reserve_r2355_fixture.sh · 70초 상한
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:300}"; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"; s=$SECONDS
  if [ -n "${DL_OFF:-}" ]; then out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  else out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; fi
  rc=$?; el=$((SECONDS - s))
}
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
row() { printf '%s pr=%s close=3 view=1 fetch=2 gate=%s overlap=0 equiv=0 press=%s lint=0 push=%s etc=0 total=0 left=%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
seed() {   # seed <gate p90> <press p90> <PR> [<직전 gate> <직전 press> <직전 left>]
  local i; : > "$PFILE"
  for i in $(seq 1 18); do row "$(tsa 300)" "$((800 + i))" "$1" 0 1 40 >> "$PFILE"; done
  for i in 19 20; do row "$(tsa 120)" "$((800 + i))" "$1" "$2" 1 40 >> "$PFILE"; done
  [ -z "${3:-}" ] || row "$(tsa 600)" "$3" "${4:-0}" "${5:-0}" - "${6:-40}" >> "$PFILE"
}
gv() { tr ' ' '\n' <<<"$(grep -m1 "^$1 " <<<"$out")" | sed -n "s/^$2=//p"; }
gn() { grep -c "^$1 " <<<"$out"; }
cl() { local l="$1" p="$2" t; t=$(( l - 14 - p )); [ "$t" -lt 30 ] && t=30; [ "$t" -gt 60 ] && t=60; [ "$t" -gt $(( l - 14 )) ] && t=$(( l - 14 )); printf '%s' "$t"; }

c19() { seed 20 23 801 0 23 40; mland "$1" 801 40 FT_PUSH_FIXED_S=$F
  local gl; gl="$(gv GATE-CAP left)"; [ "$(gv GATE-CAP press)" = 23 ] && [ "$(gv GATE-CAP s)" = "$(( gl - 37 > ( gl - 14 < 27 ? gl - 14 : 27 ) ? gl - 37 : ( gl - 14 < 27 ? gl - 14 : 27 ) ))" ]; }
c20() { seed 20 23 802 39 23 40; mland "$1" 802 40 FT_PUSH_FIXED_S=$F; [ "$(gv GATE-CAP need)" = 46 ]; }
cE2() { seed 20 15 803 0 15 40; APSH="$(sha "$W" "$M0")" DL_OFF=90 mland "$1" 803 40 FT_PUSH_FIXED_S=$F; APSH=""
  [ "$(gv EQUIV-CAP press)" = 15 ] && [ "$(gv EQUIV-CAP s)" = "$(cl "$(gv EQUIV-CAP left)" 15)" ]; }
cE3() { seed 90 0 804 0 0 40; APSH="$(sha "$W" "$M0")" DL_OFF=110 mland "$1" 804 40 FT_PUSH_FIXED_S=$F; APSH=""
  [ "$(gv EQUIV-CAP press)" = 0 ] && [ "$(gv EQUIV-CAP s)" = 60 ]; }
cE7() { seed 20 23 805 0 23 40; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_RC=124 mland "$1" 805 40 FT_PUSH_FIXED_S=$F; APSH=""
  [ "$rc" = 1 ] && grep -qE '^REJECT 동일승인 대조 [0-9]+s 상한 초과\(판정 불가 · 다음 틱\) · 남은 [0-9]+s' <<<"$out"; }
cE11() { seed 20 23 806 0 23 40; mland "$1" 806 40 FT_PUSH_FIXED_S=$F; [ "$(gn EQUIV-CAP)" = 0 ]; }

mut() {   # mut <이름> <사례> <파일> <옛 글> <새 글>
  local m="$T/mut" c="$2"; [ -d "$m" ] || mkbin "$m"
  cp "$FIX/$3" "$m/$3"
  python3 - "$m/$3" "$4" "$5" <<'PY' || { echo "FAIL M$1 :: 변이 글자 1곳 아님($3)"; fail=$((fail+1)); return; }
import io, sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(a, b, 1))
PY
  if "$c" "$m"; then echo "FAIL M$1 :: 변이가 $c 를 통과"; fail=$((fail+1)); else echo "PASS M$1 ($c FAIL)"; fi
  cp "$FIX/$3" "$m/$3"; "$c" "$FIX"; ck "M$1-원본" $?
}
mut 10 c19 ft-merge-land.sh 'gg=$((gl - RU - PRESV))' 'gg=$((gl - RU))'
mut 11 c20 ft-merge-land.sh '(PGATV > GN90 ? PGATV : GN90)' 'GN90'
mut 1 cE2 ft-merge-land.sh 'EC=$((ER - RU - PRESV));' 'EC=30;'   # EM1
mut 2 cE2 ft-merge-land.sh 'EC=$((ER - RU - PRESV));' 'EC=$((ER - RU));'   # EM2
mut 3 cE3 ft-merge-land.sh '[ "$EC" -le 60 ] || EC=60;' ''   # EM3
mut 4 cE7 ft-merge-land.sh 'case "$ERS" in 124|143) rej "동일승인 대조 ${EC}s 상한 초과(판정 불가 · 다음 틱) · 남은 ${ER}s";; esac; ' ''   # EM4
mut 6 cE11 ft-merge-land.sh "trap 'lc_line; ph_line' EXIT" "echo \"EQUIV-CAP s=0 left=0 rpush=0 press=0\"; trap 'lc_line; ph_line' EXIT"   # EM6
echo "합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
