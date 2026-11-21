#!/usr/bin/env bash
# test_merge_land_cap_adaptive_r2385.sh — r2385: 착지 «총 상한»(LIM)·«push 1단위»(R_push)를 고정 67·14 대신 land-phase.tsv 실측으로 판마다 정한다(fm_land_cap)
#   이 파일 = K1 표본(① · ② · ⑫ · ⑬ · ⑭) · K2 공식(③ · ④ · ⑤ · ⑥ · ⑦ · ⑦b · ⑧) · K3 env 우선·판정 불가(⑨ · ⑨b · ⑩ · ⑪) · 변이 M1~M9(사본에서만 · 원본 같은 사례 = PASS)
#   K4 출처 1줄 · K5 다른 길 그대로(⑮~⑱) = test_merge_land_cap_adaptive_r2385_land.sh(실 54초짜리 판 · 하드 룰 22 = 70초 상한으로 쪼갬) · 기준판 Red = _red.sh
#   여기서는 함수만 부른다(임시 폴더 하나 · git·네트워크·실 상태 0 · sleep 0) · 시험 1개 70초 상한
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="${R2385_LIB:-$HERE/../bin/ft-merge-lib.sh}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc ${out:+$out}"; fail=$((fail+1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/state"; mkdir -p "$S"; F="$S/land-phase.tsv"
LIBV=""
cap() { ( . "${LIBV:-$LIB}"; fm_land_cap "$@" ); }   # cap <state> <repo> <pr> → stdout 6칸
nowf() { python3 -c 'import time; print("%.6f" % time.time())'; }
tsa() { python3 -c 'import sys,time;print(time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(time.time() - int(sys.argv[1]))))' "${1:-0}"; }
row() {   # row <ts> <pr> <앞 합(close+view+fetch+gate+lint)> <push> <left> [<repo>] [<rpush>] — 앞 합 = 3+1+2+(pre-6)+0
  printf '%s pr=%s close=3 view=1 fetch=2 gate=%s overlap=0 equiv=0 press=0 lint=0 push=%s etc=0 total=0 left=%s%s%s\n' \
    "$1" "$2" "$(( $3 - 6 ))" "$4" "$5" "${6:+ repo=$6}" "${7:+ rpush=$7}"
}
seed20() {   # seed20 <p90앞합> <p90push> [<repo>] [<채움행 push>] — 18행 낮은 값 + 2행 p90 값
  local i; : > "$F"
  for i in $(seq 1 18); do row "$(tsa 300)" "$((800 + i))" 8 "${4:-1}" 40 "${3:-}" >> "$F"; done
  for i in 19 20; do row "$(tsa 120)" "$((800 + i))" "$1" "$2" 40 "${3:-}" >> "$F"; done
}
chk() { local g; g="$(cap "$S" "$1" "$2" 2>/dev/null)"; out="got=[$g] want=[$3]"; [ "$g" = "$3" ]; }   # chk <repo> <pr> <기대 6칸>

# ── K1 표본 · K2 공식 ────────────────────────────────────────────────────────────────────────────
k1() { seed20 54 7 o/r; chk o/r 999 "75 14 p90 20 54 7"; }
k2() { seed20 54 18 o/r; chk o/r 999 "86 25 p90 20 54 18"; }
k3() { seed20 54 7 o/r; row "$(tsa 600)" 999 57 - 14 o/r 14 >> "$F"; chk o/r 999 "92 14 prev 20 54 7"; }
k4a() { seed20 54 7 o/r; row "$(tsa 600)" 999 57 - 14 o/r >> "$F"; chk o/r 999 "92 14 prev 20 54 7"; }   # ⓐ 옛 행 = rpush 칸 없음 = 14 · left 14 ≤ 14 = prev
k4b() { seed20 54 7 o/r; row "$(tsa 600)" 999 57 - 20 o/r 21 >> "$F"; chk o/r 999 "92 14 prev 20 54 7"; }   # ⓑ left 20 ≤ 21 = prev
k4c() { seed20 54 7 o/r; row "$(tsa 600)" 999 57 - 20 o/r 14 >> "$F"; chk o/r 999 "75 14 p90 20 54 7"; }   # ⓒ left 20 > 14 = prev 아님
k5() { seed20 54 7 o/r; row "$(tsa 1860)" 999 57 - 14 o/r 14 >> "$F"; chk o/r 999 "75 14 p90 20 54 7"; }   # 31분 전 = prev 아님
k6() { seed20 54 7 o/r; row "$(tsa 600)" 999 61 - 41 o/r 14 >> "$F"; chk o/r 999 "75 14 p90 20 54 7"; }   # press 거절(left 41 ≥ 14) = prev 아님
k7() { seed20 30 1 o/r; chk o/r 999 "67 14 floor 20 30 1"; }   # 바닥 67
k7b() { seed20 30 0 o/r 0; chk o/r 999 "67 14 floor 20 30 0"; }  # R_push 바닥(F+7 = 14) — push p90 0 이어도 14
k8() { seed20 90 1 o/r; chk o/r 999 "100 14 p90 20 90 1"; }   # 천장 100

# ── K3 env 우선 · 판정 불가 · 거르기 ─────────────────────────────────────────────────────────────
k9() { seed20 54 7 o/r; out="got=[$(FT_LAND_TOTAL_S=80 cap "$S" o/r 999 2>/dev/null)]"; [ "$out" = "got=[80 14 env 0 0 0]" ]; }
k9b() { seed20 54 7 o/r; out="got=[$(FT_LAND_TOTAL_S=150 cap "$S" o/r 999 2>/dev/null)]"; [ "$out" = "got=[100 14 env 0 0 0]" ]; }
k10() { rm -f "$F"; chk o/r 999 "67 14 floor:없음 0 0 0"; }
k11() { seed20 54 7 o/r; head -n 4 "$F" > "$T/x"; mv "$T/x" "$F"; chk o/r 999 "67 14 floor:n<5 4 0 0"; }
k12() { seed20 54 7 o/r; printf 'garbage 줄\n\n2026-01-01T00:00:00 pr=only\n%s close=3 view=1 fetch=2 gate=48 push=7 left=40\n' "$(tsa 60)" >> "$F"; chk o/r 999 "75 14 p90 20 54 7"; }
k13() {   # repo 칸 섞임(BYZ 15 · 팩 10 · 칸 없는 옛 5) → 팩 착지는 팩 10 + 옛 5 행만 = 15행
  local i t1 t2 t3; t1="$(tsa 900)"; t2="$(tsa 600)"; t3="$(tsa 300)"; : > "$F"
  for i in $(seq 1 15); do row "$t1" "$((100 + i))" 90 1 40 byz/r 14 >> "$F"; done
  for i in $(seq 1 10); do row "$t2" "$((200 + i))" 54 7 40 pack/r 14 >> "$F"; done
  for i in $(seq 1 5); do row "$t3" "$((300 + i))" 54 7 40 "" "" >> "$F"; done
  chk pack/r 999 "75 14 p90 15 54 7"; }
k14() {   # 10만 줄 → 끝 200줄만 · 1초 안 · 값은 같은 표본
  [ -s "$T/big.tsv" ] || python3 -c 'import io,sys
r = "2026-11-21T%02d:%02d:%02d pr=%d close=3 view=1 fetch=2 gate=51 overlap=0 equiv=0 press=0 lint=0 push=6 etc=0 total=0 left=40 repo=o/r rpush=14\n"
with io.open(sys.argv[1], "w") as f:
  for i in range(100000): f.write(r % (i % 24, i % 60, i % 60, i))' "$T/big.tsv"
  cp "$T/big.tsv" "$F"
  local t0 t1 g; t0="$(nowf)"; g="$(cap "$S" o/r 999 2>/dev/null)"; t1="$(nowf)"
  RC14="$(python3 -c "print(round(float('$t1') - float('$t0'), 3))")"; out="got=[$g] ${RC14}초"
  [ "$g" = "78 14 p90 20 57 6" ] && python3 -c "import sys; sys.exit(0 if float('$RC14') < 1.0 else 1)"; }

RC14=0
for c in k1 k2 k3 k4a k4b k4c k5 k6 k7 k7b k8; do "$c"; ck "$c" $?; done
S1=$SECONDS
for c in k9 k9b k10 k11 k12 k13 k14; do "$c"; ck "$c" $?; done
echo "단계별 초: K1·K2 ①~⑧ ${S1} · K3 ⑨~⑭ $((SECONDS - S1)) · ⑭ 함수 1회 ${RC14}초"

# ── 변이 M1~M9 — 사본에서만 · 같은 사례가 FAIL 해야(원본 = PASS) ────────────────────────────────
mut() {   # mut <이름> <사례> <옛 글> <새 글> — lib 사본 1벌에 1곳 치환 · 사례가 FAIL 해야 통과
  local m="$T/mut-$1" c="$2"
  mkdir -p "$m"; cp "$LIB" "$m/ft-merge-lib.sh"
  python3 - "$m/ft-merge-lib.sh" "$3" "$4" <<'PY' || { echo "FAIL M$1 :: 변이 글자 1곳 아님"; fail=$((fail+1)); return; }
import io, sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = io.open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  LIBV="$m/ft-merge-lib.sh"
  if "$c"; then echo "FAIL M$1 :: 변이가 $c 를 통과"; fail=$((fail+1)); else echo "PASS M$1 ($c FAIL)"; fi
  LIBV=""; "$c"; ck "M$1-원본" $?
}
mut 1 k1 'i = int(0.9 * n); if (i > n - 1) i = n - 1; return a[i+1]' '{ t = 0; for (i = 1; i <= n; i++) t += a[i]; return int(t / n) }'   # p90 → 평균
mut 2 k7b 'if (rpush < rf) rpush = rf;' ''   # R_push 바닥 지움(⑦ 짝)
mut 3 k5 't >= cut && ' ''   # prev 30분 창 지움
mut 4 k6 ' && (LEF[last] + 0) <= LRS[last]' ''   # 예산 거절 판정 지움(push=- 만 봄)
mut 5 k8 'if (lim > 100) lim = 100' ''   # 천장 지움
mut 6 k9 'if [ -n "${FT_LAND_TOTAL_S:-}" ]; then' 'if false; then'   # env 우선 지움
mut 7 k13 ' && rv != rp) next' ' && 0) next'   # repo 칸 거르기 지움
mut 8 k14 'tail -n 200 "$f" 2>/dev/null' 'cat "$f" 2>/dev/null'   # tail 지움(파일 전체 읽기) → ⑭ 초
mut 9 k4a '(LEF[last] + 0) <= LRS[last]' '(LEF[last] + 0) < LRS[last]'   # prev 경계 ≤ → <
echo "합계 $SECONDS"   # 시험 1개 70초 상한(하드 룰 22)
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
