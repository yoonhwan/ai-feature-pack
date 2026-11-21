#!/usr/bin/env bash
# test_merge_land_cell_cap_r2385_slow.sh — r2385 E①(고친 판): EQUIV 칸이 46 까지 늘어 가짜 equiv 31초가 칸 안에서 끝난다(기준판 = _red.sh 에서 30 에서 끊김)
#   ⑲ gate 칸 press 몫 남김 · ⑳ 직전 gate 소요 우선 · ㉑ 비음성 PR = 지금 값 · ㉒ 표본 floor · ㉓ 남은 < 1 거절 글 그대로 · E① 칸 36 · E② press 몫 반영 · E③ 천장 60 · E④ 남은 값 · E⑤ 거절 · E⑥ floor · E⑦ 시간 초과 글 ⓐ · E⑨⑩ 글 ⓒ · E⑪ EQUIV-CAP 1줄/0줄 · E⑫ 통과 뒤 출력 그대로
#   판정 1판에 실 31초를 쓴다(하드 룰 22 · 70초 상한 = 파일을 쪼갬) · 나머지 반례 = _cell_cap.sh · 기준판 Red = _red.sh
#   격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press · 실 원격 0) · 슬립은 «가짜 도구» 안에서만
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:300}"; printf '%s\n' "$out" | grep -E '^(REJECT|EQUIV-CAP)' | sed 's/^/    > /'; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»(표본을 미리 심는다)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"; s=$SECONDS
  if [ -n "${DL_OFF:-}" ]; then out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  else out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; fi
  rc=$?; el=$((SECONDS - s))
}
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
row() {   # row <ts> <pr> <gate> <press> <push> <left> [<repo>] — 앞 합 = 3+1+2+gate+0+0+press+0
  printf '%s pr=%s close=3 view=1 fetch=2 gate=%s overlap=0 equiv=0 press=%s lint=0 push=%s etc=0 total=0 left=%s%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "${7:+ repo=$7}"
}
seed() {   # seed <gate p90> <press p90> [<PR>] [<직전 gate> <직전 press> <직전 left>] — 20행 표본 + (있으면) 같은 PR 직전 행
  local i; : > "$PFILE"
  for i in $(seq 1 18); do row "$(tsa 300)" "$((800 + i))" "$1" 0 1 40 >> "$PFILE"; done
  for i in 19 20; do row "$(tsa 120)" "$((800 + i))" "$1" "$2" 1 40 >> "$PFILE"; done
  [ -z "${3:-}" ] || row "$(tsa 600)" "$3" "${4:-0}" "${5:-0}" - "${6:-40}" >> "$PFILE"
}
gv() { tr ' ' '\n' <<<"$(grep -m1 "^$1 " <<<"$out")" | sed -n "s/^$2=//p"; }   # gv GATE-CAP press → 칸 값
gn() { grep -c "^$1 " <<<"$out"; }

# ── E① EQUIV 칸 = min(남은 − 14, clamp(30, 60, 남은 − 14 − P)) · 가짜 equiv 31초가 칸 안에서 끝난다 ──
seed 20 23 706 0 0 40; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_SLEEP=31 mland "$FIX" 706 70 FT_PUSH_FIXED_S=$F; APSH=""
ec="$(gv EQUIV-CAP s)"; el2="$(gv EQUIV-CAP left)"; AEQ="$(gn EQUIV-CAP)"; ok=0
{ [ "$(gn EQUIV-CAP)" = 1 ] && [ -n "$ec" ] && [ "$ec" -ge 31 ] && [ "$ec" = "$(( el2 - 14 < 60 ? el2 - 14 : 60 ))" ] && \
  ! grep -q '동일승인 대조' <<<"$out"; } && ok=1
ck "E① 비음성 PR(press 몫 0) · equiv 31초 → EQUIV-CAP s=$ec ≥ 31 · 칸 안에서 통과(상한 초과 글 0)" $((1 - ok))

echo "합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
