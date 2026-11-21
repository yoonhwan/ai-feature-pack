#!/usr/bin/env bash
# test_merge_land_cap_adaptive_r2385_land.sh — r2385 K4·K5: 판이 «LAND-CAP lim= push= 출처= n= pre90= push90=» 1줄을 찍고, LAND-PHASE 끝에 repo=·rpush= 칸 2개가 붙고, 다른 길(PB·DRY)이 그대로인가
#   ⑮ LAND-CAP 1줄 · LAND-PHASE = 앞 칸 그대로 + 끝 2칸 + tsv 1줄 · ⑰ push 크기 비례 PB 그대로(R_push 는 1차 NEED 만) · ⑱ DRY = LAND-CAP 1줄 · push 0
#   함수 반례 ①~⑭ + 변이 M1~M9 = test_merge_land_cap_adaptive_r2385.sh · ⑯ 실 54초 판(green/red) = _slow.sh · _red.sh(하드 룰 22 = 70초 상한으로 쪼갬)
#   격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press · 실 원격·실 gh·실 mbox 0) · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_reserve_r2355_fixture.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fx_init "$T"; fx_fix
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc el=${el}s out=${out:0:400}"; fail=$((fail+1)); fi; }
mland() {   # mland <bin> <PR> <바깥 상한초> [KEY=VAL…] — land() 와 같되 land-phase.tsv 를 «안 지운다»(표본을 미리 심는다)
  local b="$1" n="$2" o="$3" s; shift 3
  mkpr "$n"; apv --approve-sha "${APSH:-$PRSHA}"; : > "$STUB_LOG"
  s=$SECONDS
  if [ -n "${DL_OFF:-}" ]; then out="$(env "FT_LAND_DEADLINE=$(( $(date +%s) + DL_OFF ))" "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"
  else out="$(env "$@" "$TBIN" "$o" bash "$b/ft-merge-land.sh" "$n" --approve-sha "${APSH:-$PRSHA}" --repo "$W" 2>&1)"; fi
  rc=$?; el=$((SECONDS - s))
}
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
lc() { grep -m1 '^LAND-CAP ' <<<"$out"; }
lcv() { tr ' ' '\n' <<<"$(lc)" | sed -n "s/^$1=//p"; }   # lcv <칸이름> → LAND-CAP 줄의 그 칸

# ── ⑮ 착지 1판(LAND-CAP 1줄 · LAND-PHASE 끝 2칸 · tsv 1줄) ─────────────────────────────────────
rm -f "$PFILE"; mland "$FIX" 501 40 FT_PUSH_FIXED_S=$F
L="$(ph)"; N14="pr= close= view= fetch= gate= overlap= equiv= press= lint= push= etc= total= left= "
FIELDS="$(sed 's/ repo=[^ ]* rpush=[^ ]*$//' <<<"$L" | grep -oE '(pr|close|view|fetch|gate|overlap|equiv|press|lint|push|etc|total|left)=' | tr '\n' ' ')"
lt="$(lcv lim)"; lp="$(lcv push)"; ls_="$(lcv 출처)"; ok=0
{ [ "$rc" = 0 ] && grep -q '^LANDED pr=501 ' <<<"$out" && [ "$(grep -c '^LAND-CAP ' <<<"$out")" = 1 ] && [ "$lt" = 67 ] && [ "$lp" = 14 ] && \
  [ "$ls_" = "floor:없음" ] && [ "$(lcv n)" = 0 ] && [ "$FIELDS" = "$N14" ] && \
  grep -qE " repo=[^ ]+ rpush=14$" <<<"$L" && [ "$(grep -c . "$PFILE")" = 1 ] && grep -qE ' repo=[^ ]+ rpush=14$' "$PFILE"; } && ok=1
ck "⑮ LAND-CAP 1줄(lim=67 push=14 출처=floor:없음 n=0) · LAND-PHASE 앞 13칸 그대로 + 끝 repo=·rpush= · tsv 같은 줄" $((1 - ok))
RP="$(sed -n 's/.* repo=\([^ ]*\) rpush=.*/\1/p' "$PFILE" | tail -n 1)"

# ── ⑰ push 크기 비례 PB(객체 40 · 단위 1 → PB 70) → PB 는 그대로 · R_push 는 1차 NEED 만(14) ──────
rm -f "$PFILE" "$TSV"; mkpr 502 40; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
out="$(env FT_PUSH_FIXED_S=$F "FT_PUSH_UNIT_OBJECTS=1" "$TBIN" 40 bash "$FIX/ft-merge-land.sh" 502 --approve-sha "$PRSHA" --repo "$W" 2>&1)"; rc=$?
ok=0; { [ "$rc" = 0 ] && [ "$(pbv 5)" = 70 ] && [ "$(pbv 4)" -ge 40 ] && [ "$(lcv push)" = 14 ] && grep -q '^push ok objects=' <<<"$out"; } && ok=1
ck "⑰ 객체 40+ · 단위 1 → PB 70 그대로 · LAND-CAP push=14(1차 NEED 만) · push ok 줄" $((1 - ok))

# ── ⑱ --dry → LAND-CAP 1줄 · push 0(지금과 같음) ──────────────────────────────────────────────
rm -f "$PFILE" "$TSV"; mkpr 503; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"
out="$(env FT_PUSH_FIXED_S=$F "$TBIN" 40 bash "$FIX/ft-merge-land.sh" 503 --approve-sha "$PRSHA" --repo "$W" --dry 2>&1)"; rc=$?
ok=0; { [ "$rc" = 0 ] && grep -q '^DRY ALLOW' <<<"$out" && [ "$(grep -c '^LAND-CAP ' <<<"$out")" = 1 ] && [ ! -s "$TSV" ] && [ "$(phv push)" = "-" ]; } && ok=1
ck "⑱ --dry → DRY ALLOW · LAND-CAP 1줄 · push 시도 0 · LAND-PHASE push=-" $((1 - ok))
echo "표본 repo=$RP · 합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
