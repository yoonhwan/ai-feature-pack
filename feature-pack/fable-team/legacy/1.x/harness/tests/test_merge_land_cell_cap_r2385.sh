#!/usr/bin/env bash
# test_merge_land_cell_cap_r2385.sh — r2385 K6 gate 칸 · K7 EQUIV 칸: 단계 상한을 «남은 − push 몫 − press 몫» 안에서 정하고, 출처 1줄(GATE-CAP·EQUIV-CAP)과 거절 글 3꼴을 잰다
#   ⑲ gate 칸 press 몫 남김 · ⑳ 직전 gate 소요 우선 · ㉑ 비음성 PR = 지금 값 · ㉒ 표본 floor · ㉓ 남은 < 1 거절 글 그대로 · E① 칸 36 · E② press 몫 반영 · E③ 천장 60 · E④ 남은 값 · E⑤ 거절 · E⑥ floor · E⑦ 시간 초과 글 ⓐ · E⑨⑩ 글 ⓒ · E⑪ EQUIV-CAP 1줄/0줄 · E⑫ 통과 뒤 출력 그대로
#   변이 M10 · M11 · EM1~EM6(사본에서만 · 원본 같은 사례 PASS) · 기준판 Red = test_merge_land_cell_cap_r2385_red.sh(⑲ · E① · E⑦) · E⑧(자동 병합 판 ⓑ)은 S0 를 세우는 fixture 가 따로 필요해 이 파일 밖이다
#   격리 = _reserve_r2355_fixture.sh(임시 origin · 가짜 gh·게이트·equiv·press · 실 원격 0) · 슬립은 «가짜 도구» 안에서만 · 70초 상한
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

# ── ⑲ gate 칸 · 남은 − push − press 몫 = 49 쪽 · D = gate p90 + 7 ───────────────────────────────
seed 20 23 701 0 23 40; mland "$FIX" 701 40 FT_PUSH_FIXED_S=$F
gl="$(gv GATE-CAP left)"; ok=0
{ [ "$rc" = 0 ] && [ "$(gn GATE-CAP)" = 1 ] && [ "$(gv GATE-CAP press)" = 23 ] && [ "$(gv GATE-CAP need)" = 27 ] && \
  [ "$(gv GATE-CAP rpush)" = 14 ] && [ "$(gv GATE-CAP s)" = "$(( gl - 14 - 23 > (gl - 14 < 27 ? gl - 14 : 27) ? gl - 14 - 23 : (gl - 14 < 27 ? gl - 14 : 27) ))" ]; } && ok=1
ck "⑲ 음성 PR(press 23) → GATE-CAP press=23 need=27 s=max(남은−14−23, min(남은−14, 27)) [남은 $gl]" $((1 - ok))

# ── ⑳ 직전 gate 소요(39) 우선 — D = max(39, gate p90 20) + 7 = 46 ───────────────────────────────
seed 20 23 702 39 23 40; mland "$FIX" 702 40 FT_PUSH_FIXED_S=$F
gl="$(gv GATE-CAP left)"; ok=0
{ [ "$rc" = 0 ] && [ "$(gv GATE-CAP need)" = 46 ] && [ "$(gv GATE-CAP s)" = "$(( gl - 14 - 23 > (gl - 14 < 46 ? gl - 14 : 46) ? gl - 14 - 23 : (gl - 14 < 46 ? gl - 14 : 46) ))" ]; } && ok=1
ck "⑳ 직전 gate 39 → need=46 · s=max(남은−37, min(남은−14, 46)) [남은 $gl]" $((1 - ok))

# ── ㉑ 비음성 PR(직전 press 0) → press 몫 0 · s = 남은 − 14 (지금 값) ────────────────────────────
seed 20 23 703 0 0 40; mland "$FIX" 703 40 FT_PUSH_FIXED_S=$F
gl="$(gv GATE-CAP left)"; ok=0
{ [ "$rc" = 0 ] && [ "$(gv GATE-CAP press)" = 0 ] && [ "$(gv GATE-CAP s)" = "$((gl - 14))" ]; } && ok=1
ck "㉑ 비음성 PR → press 몫 0 · s = 남은 − 14 [남은 $gl]" $((1 - ok))

# ── ㉒ 표본 floor(파일 없음) → s = need = 남은 − 14 ─────────────────────────────────────────────
rm -f "$PFILE"; mland "$FIX" 704 40 FT_PUSH_FIXED_S=$F
ok=0; { [ "$rc" = 0 ] && [ "$(gv GATE-CAP s)" = "$(gv GATE-CAP need)" ] && [ "$(gv GATE-CAP s)" = "$(( $(gv GATE-CAP left) - 14 ))" ] && [ "$(gv GATE-CAP press)" = 0 ]; } && ok=1
ck "㉒ 표본 floor → GATE-CAP s = need = 남은 − 14 · press 0" $((1 - ok))

# ── DA#54 H2 — 같은 PR 직전 행이 없으면 탐침 -1 을 gate need 에 안 섞는다(need = gate p90 + 7) ──
seed 20 0 716 0 0 40; : ; mland "$FIX" 716 40 FT_PUSH_FIXED_S=$F
ok=0; { [ "$rc" = 0 ] && [ "$(gv GATE-CAP need)" = 27 ] && [ "$(gv GATE-CAP press)" = 0 ]; } && ok=1
ck "H2 직전 행 없음(탐침 -1) → GATE-CAP need = gate p90 20 + 7 = 27" $((1 - ok))

# ── ㉓ 남은 − 14 < 1 → «push 몫 예약: gate 앞 …» 글 그대로 ─────────────────────────────────────
seed 20 23 705 0 23 40; DL_OFF=14 mland "$FIX" 705 40 FT_PUSH_FIXED_S=$F
push_res() {   # «push 몫 예약: <단계> 앞 남은 <초>s − push 1단위 <RU>s < 1» 글 — 남은 − R_push < 1 이면 그 자리(단계 이름 그대로)에서 같은 문장
  [ "$rc" = 1 ] || return 1
  grep -qE '^REJECT push 몫 예약: .*push 1단위 14s' <<<"$out" || return 1
  grep -qF "$1" "$FIX/ft-merge-land.sh" || return 1
  return 0; }
ok=0; push_res 'rej "push 몫 예약: gate 앞 남은 $(land_left)s − push 1단위 ${RU}s < 1 (착지 0 · 다음 틱)"' && ok=1
ck "㉓ 남은 − 14 < 1 → «push 몫 예약» 글(그 자리 단계 이름 그대로) · gate 자리 문장 실재" $((1 - ok))

# ── E②③ 칸 공식의 press 몫·천장(남은이 클 때) ─────────────────────────────────────────────────
cl() { local l="$1" p="$2" t; t=$(( l - 14 - p )); [ "$t" -lt 30 ] && t=30; [ "$t" -gt 60 ] && t=60; [ "$t" -gt $(( l - 14 )) ] && t=$(( l - 14 )); printf '%s' "$t"; }   # equiv 칸 = min(남은−14, clamp(30, 60, 남은−14−P))
e2() { seed 20 15 "$2" 0 15 40; APSH="$(sha "$W" "$M0")" DL_OFF="$1" mland "$FIX" "$2" 40 FT_PUSH_FIXED_S=$F; APSH=""
  [ "$(gv EQUIV-CAP press)" = 15 ] && [ "$(gv EQUIV-CAP s)" = "$(cl "$(gv EQUIV-CAP left)" 15)" ]; }
ok=0; e2 90 714 && ok=1
ck "E② 음성 PR press 15 → 칸 = min(남은−14, clamp(30, 60, 남은−14−15))" $((1 - ok))
# E③ 천장·E②·E④ 값 = 카드 숫자 그대로(공식 단위) — 실행 판은 E②(behavior)·E④(behavior)가 따로 잰다
ok=0; { [ "$(cl 100 0)" = 60 ] && [ "$(cl 80 15)" = 51 ] && [ "$(cl 40 0)" = 26 ] && [ "$(cl 50 0)" = 36 ]; } && ok=1
ck "E②③④ 공식 = 남은 100/P0 → 60(천장) · 80/15 → 51 · 40/0 → 26 · 50/0 → 36" $((1 - ok))

# ── E②~E⑥ 칸 공식 — 남은 값만 바꿔 셈(짧은 가짜 equiv) ─────────────────────────────────────────
e4() { seed 20 23 "$2" 0 23 40; APSH="$(sha "$W" "$M0")" DL_OFF="$1" mland "$FIX" "$2" 40 FT_PUSH_FIXED_S=$F; APSH=""
  local s l; s="$(gv EQUIV-CAP s)"; l="$(gv EQUIV-CAP left)"; [ "$s" = "$(( l - 14 ))" ] && [ "$s" -lt 30 ]; }
ok=0; e4 40 707 && ok=1
ck "E④ 남은이 작음 → 칸 = 남은 − 14 (clamp 바닥보다 남은 값이 먼저)" $((1 - ok))
seed 20 23 708 0 0 40; APSH="$(sha "$W" "$M0")" DL_OFF=14 mland "$FIX" 708 40 FT_PUSH_FIXED_S=$F; APSH=""
ok=0; push_res 'rej "push 몫 예약: equiv 앞 남은 $(land_left)s − push 1단위 ${RU}s < 1 (착지 0 · 다음 틱)"' && ok=1
ck "E⑤ 남은 = push 몫 → «push 몫 예약» 거절 그대로 · equiv 자리 문장 실재" $((1 - ok))
ok=0; { rm -f "$PFILE"; APSH="$(sha "$W" "$M0")" DL_OFF=60 mland "$FIX" 709 40 FT_PUSH_FIXED_S=$F; APSH=""
  local s l; s="$(gv EQUIV-CAP s)"; l="$(gv EQUIV-CAP left)"
  [ "$(gv EQUIV-CAP press)" = 0 ] && [ "$s" -ge 30 ] && [ "$s" -le 60 ] && [ "$s" = "$(( l - 14 < 60 ? l - 14 : 60 ))" ]; } && ok=1
ck "E⑥ 표본 floor → press 0 · 칸 = clamp(30, 60, 남은 − 14)" $((1 - ok))

# ── E⑦ 시간 초과 글 ⓐ (rc 124) · «head 가 움직였» 0 ───────────────────────────────────────────
seed 20 23 710 0 23 40; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_RC=124 mland "$FIX" 710 40 FT_PUSH_FIXED_S=$F; APSH=""
ok=0; { [ "$rc" = 1 ] && grep -qE '^REJECT 동일승인 대조 [0-9]+s 상한 초과\(판정 불가 · 다음 틱\) · 남은 [0-9]+s' <<<"$out" && ! grep -q 'head 가 움직였' <<<"$out"; } && ok=1
ck "E⑦ 가짜 equiv rc 124 → 글 ⓐ «상한 초과(판정 불가 · 다음 틱)» · «head 가 움직였» 0" $((1 - ok))

# ── E⑨⑩ 글 ⓒ = 지금 글(PR head ≠ 승인 sha) · EQ 첫 줄 실음 ────────────────────────────────────
seed 20 23 711 0 23 40; APSH="$(sha "$W" "$M0")" DL_OFF=60 EQUIV_RC=1 mland "$FIX" 711 40 FT_PUSH_FIXED_S=$F; APSH=""
AEQ="$(gn EQUIV-CAP)"; ok=0; { [ "$rc" = 1 ] && grep -q '승인 뒤 head 가 움직였고 동일승인 대조(병합·rebase 두 경로)도 실패:equiv 스텁 거절' <<<"$out"; } && ok=1
ck "E⑨⑩ PR head ≠ 승인 sha · equiv rc 1 → 글 ⓒ 그대로 + EQ 첫 줄" $((1 - ok))

# ── E⑪ EQUIV-CAP 은 equiv 칸을 돈 판에만 1줄 ──────────────────────────────────────────────────
a="${AEQ:-0}"
mkpr 713; apv --approve-sha "$PRSHA"; : > "$STUB_LOG"; out="$(env FT_PUSH_FIXED_S=$F "$TBIN" 40 bash "$FIX/ft-merge-land.sh" 713 --approve-sha "$PRSHA" --ff --repo "$W" 2>&1)"; rc=$?; b="$(gn EQUIV-CAP)"
ok=0; { [ "$rc" = 0 ] && [ "$a" = 1 ] && [ "$b" = 0 ]; } && ok=1
ck "E⑪ equiv 칸을 돈 판 1줄($a) · 안 돈 판(--ff · 승인 sha == head) 0줄($b)" $((1 - ok))

# ── E⑫ 통과 뒤 push 출력이 그대로 — 겹침 대조·push 줄 모양 ──────────────────────────────────
ok=0; { grep -qE '^push ok objects=[0-9]+ bound=[0-9]+ attempt=[0-9]+ took=[0-9]+s$' <<<"$out" && grep -q '^LANDED pr=713 ' <<<"$out"; } && ok=1
ck "E⑫ EQUIV 통과 뒤 push 줄·LANDED 모양 그대로" $((1 - ok))
echo "합계 $SECONDS"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
