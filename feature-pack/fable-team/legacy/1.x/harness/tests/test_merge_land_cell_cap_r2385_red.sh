#!/usr/bin/env bash
# test_merge_land_cell_cap_r2385_red.sh — r2385 K6·K7 기준판 Red: origin/main 판은 gate·EQUIV 칸이 없어(고정 rsv) press 몫·상한 초과 글을 못 낸다
#   ⑲ Red = GATE-CAP 줄 0 · 고친 판(_cell_cap.sh)은 1줄 + press 몫 남김 · E① Red = equiv 칸 30 고정 → 가짜 equiv 31초가 끊김(고친 판은 칸 46 안에서 통과) · E⑦ Red = 시간 초과 글 ⓐ 0 · 옛 글
#   격리 = _reserve_r2355_fixture.sh · 기준판 = fx_base(origin/main 사본) · 판정 1판에 실 31초를 쓴다(하드 룰 22 · 70초 상한 = 파일을 쪼갬)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix; fx_base
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:300}"; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»(표본을 미리 심는다)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"; s=$SECONDS
  if [ -n "${DL_OFF:-}" ]; then out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  else out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; fi
  rc=$?; el=$((SECONDS - s))
}
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
row() { printf '%s pr=%s close=3 view=1 fetch=2 gate=%s overlap=0 equiv=0 press=%s lint=0 push=%s etc=0 total=0 left=%s\n' "$1" "$2" "$3" "$4" "$5" "$6"; }
seed() {   # seed <gate p90> <press p90> <PR> [<직전 press>]
  local i; : > "$PFILE"
  for i in $(seq 1 18); do row "$(tsa 300)" "$((800 + i))" "$1" 0 1 40 >> "$PFILE"; done
  for i in 19 20; do row "$(tsa 120)" "$((800 + i))" "$1" "$2" 1 40 >> "$PFILE"; done
  [ -z "${4:-}" ] || row "$(tsa 600)" "$3" 0 "$4" - 40 >> "$PFILE"
}
[ -n "${BASE:-}" ] || { echo "SKIP 기준판(origin/main 사본) 못 만듦 — 판정 불가"; exit 0; }

# ── ⑲ Red — 기준판은 gate 칸·GATE-CAP 줄이 없다(press 몫을 남길 자리 자체가 없음) ──────────────
r19() { ! grep -q '^GATE-CAP ' <<<"$out" || return 1; ! grep -q '^EQUIV-CAP ' <<<"$out" || return 1; return 0; }
seed 20 23 901 23; DL_OFF=60 mland "$BASE" 901 40 FT_PUSH_FIXED_S=$F
ok=0; r19 && ok=1
ck "⑲ Red 기준판 → GATE-CAP·EQUIV-CAP 줄 0 (고친 판은 GATE-CAP press 몫 23 을 남긴다)" $((1 - ok))

# ── E① Red — equiv 칸 30 고정 → 31초 가짜 equiv 가 끊긴다(고친 판은 칸 46 안에서 통과) ─────────
re1() { [ "$rc" = 1 ] || return 1; grep -q '승인 뒤 head 가 움직였고 동일승인 대조(병합·rebase 두 경로)도 실패' <<<"$out" || return 1; ! grep -q '^LANDED' <<<"$out" || return 1; return 0; }
seed 20 23 902 0; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_SLEEP=31 mland "$BASE" 902 40 FT_PUSH_FIXED_S=$F; APSH=""
ok=0; re1 && ok=1
ck "E① Red 기준판 equiv 칸 30 → 31초 대조가 끊김(rc 1 · 옛 글 · 착지 0)" $((1 - ok))

# ── E⑦ Red — 시간 초과 글 ⓐ 가 없다(옛 글 그대로) ───────────────────────────────────────────
re7() { [ "$rc" = 1 ] || return 1; ! grep -q '상한 초과(판정 불가 · 다음 틱)' <<<"$out" || return 1; grep -q '승인 뒤 head 가 움직였' <<<"$out" || return 1; return 0; }
seed 20 23 903 0; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_RC=124 mland "$BASE" 903 40 FT_PUSH_FIXED_S=$F; APSH=""
ok=0; re7 && ok=1
ck "E⑦ Red 기준판 → ⓐ «상한 초과» 글 0 · 옛 «head 가 움직였» 글(고친 판은 ⓐ)" $((1 - ok))
echo "판 1회 ${el}초 · 합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
