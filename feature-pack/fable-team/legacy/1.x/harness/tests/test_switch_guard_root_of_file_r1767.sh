#!/usr/bin/env bash
# test_switch_guard_root_of_file_r1767.sh — r1767 2.0 전환 가드가 카드 «파일» 경로에서 데이터 루트를 찾고, 루트 모름은 rc3 로 멈춘다.
#   반례 ① 카드 파일 → 루트 · spawn rc3  ② 아직 없는 카드·폴더 → 가까운 상위로 루트 · rc3  ③ git 밖 파일 → root_of rc1 · guard rc3 «데이터 루트 판정 불가» 1줄
#        ④ 팀 모름(루트 있음) = INFO rc0 그대로  ⑤ 표식 없음 rc0·쓰기 0 · 깨진 표식 rc3  ⑥ 기존 r1675·r1694 시험 rc0
#   변이 M1~M4 = lib 사본에서만 · 변이마다 원본으로 같은 사례 1회 더(대조)
#   격리: 임시 git 리포(git init · 임시 폴더 안) · FT_FT20_ROOT·FT_TEAM 비움 · 실 표식·명부·카드 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="$HERE/../bin/ft20-switch-lib.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; OUT="$T/out"         # R = 임시 git 리포(데이터 루트) · OUT = git 밖 폴더
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
now() { date +%s; }; secs() { echo "$(( $(now) - $1 ))초"; }
unset FT_FT20_ROOT FT_TEAM FT_SEATS_JSON
t0=$(now)
git init -q "$R" || { echo "FAIL 준비 — git init"; exit 1; }
SW="$R/.fable-team/state/ft20-switch"; mkdir -p "$SW" "$R/design/harness/indices/대기" "$OUT/design/harness/indices/대기"
printf '{"team":"harness","switched_at":"2026-11-12T00:00:00","h":1767}\n' > "$SW/harness.json"
CARD="$R/design/harness/indices/대기/c.md"; printf '# 카드\n- 상태: 대기\n' > "$CARD"
GHOST="$R/design/harness/indices/진행/sub/c.md"      # ② 쌍둥이 경로 꼴 — 파일·폴더 둘 다 아직 없음
OCARD="$OUT/design/harness/indices/대기/c.md"; printf '# 카드\n' > "$OCARD"
echo "준비 $(secs "$t0")"

cases() {  # $1 = lib 경로 · 사례 ①~⑤ 결과를 "<사례> <0|1>" 줄로 낸다(0 = 계약대로)
  local L="$1" r rc o="$T/o.$$"
  ( . "$L"; r="$(ft20_root_of "$CARD")"; [ "$r" = "$R" ] ) >/dev/null 2>&1; echo "①root $?"
  ( . "$L"; ft20_guard_spawn "$(ft20_root_of "$CARD" 2>/dev/null)" "$CARD" "" ) >"$o" 2>&1; rc=$?
  echo "①spawn $([ "$rc" = 3 ] && grep -q 'REJECT 팀 harness 은 2.0 전환됨' "$o" && echo 0 || echo 1)"
  ( . "$L"; r="$(ft20_root_of "$GHOST")"; [ "$r" = "$R" ] ) >/dev/null 2>&1; echo "②root $?"
  ( . "$L"; ft20_guard_spawn "$(ft20_root_of "$GHOST" 2>/dev/null)" "$GHOST" "" ) >"$o" 2>&1; rc=$?
  echo "②spawn $([ "$rc" = 3 ] && grep -q '2.0 전환됨' "$o" && echo 0 || echo 1)"
  ( . "$L"; r="$(ft20_root_of "$OCARD")"; rc=$?; [ "$rc" = 1 ] && [ -z "$r" ] ) >/dev/null 2>&1; echo "③root $?"
  ( . "$L"; ft20_guard_spawn "$(ft20_root_of "$OCARD" 2>/dev/null)" "$OCARD" "" ) >"$o" 2>&1; rc=$?
  echo "③spawn $([ "$rc" = 3 ] && [ "$(grep -c . "$o")" = 1 ] && grep -q 'REJECT 데이터 루트 판정 불가' "$o" && echo 0 || echo 1)"
  ( . "$L"; ft20_switch_guard "" harness ) >"$o" 2>&1; rc=$?
  echo "③guard $([ "$rc" = 3 ] && [ "$(grep -c . "$o")" = 1 ] && grep -q '데이터 루트 판정 불가' "$o" && echo 0 || echo 1)"
  ( . "$L"; ft20_guard_retire "$R" 'nobody-#0' ) >"$o" 2>&1; rc=$?
  echo "④retire $([ "$rc" = 0 ] && grep -q 'INFO 팀 판정 불가' "$o" && echo 0 || echo 1)"
  ( . "$L"; ft20_switch_guard "$R" "" ) >"$o" 2>&1; rc=$?
  echo "④guard $([ "$rc" = 0 ] && grep -q 'INFO 팀 판정 불가' "$o" && echo 0 || echo 1)"
  ( . "$L"; ft20_guard_move "$R" "$R/notes/c.md" ) >"$o" 2>&1; rc=$?
  echo "④move $([ "$rc" = 0 ] && grep -q 'INFO 팀 판정 불가' "$o" && echo 0 || echo 1)"
  ( . "$L"; ft20_switch_guard "$R" aifp "본문" me ) >"$o" 2>&1; rc=$?
  echo "⑤none $([ "$rc" = 0 ] && [ ! -e "$SW/aifp.held" ] && echo 0 || echo 1)"
  printf '{bad' > "$SW/broken.json"
  ( . "$L"; ft20_guard_spawn "$R" "$R/design/broken/indices/대기/c.md" "" ) >"$o" 2>&1; rc=$?
  rm -f "$SW/broken.json"
  echo "⑤broken $([ "$rc" = 3 ] && grep -q '판정 불가' "$o" && echo 0 || echo 1)"
  rm -f "$o"
}
name() { case "$1" in
  ①root) echo "① root_of(카드 파일) = 리포 루트";; ①spawn) echo "① guard_spawn(카드 파일) rc3 «2.0 전환됨»";;
  ②root) echo "② root_of(없는 카드·폴더) = 가까운 상위의 리포 루트";; ②spawn) echo "② guard_spawn(없는 카드) rc3";;
  ③root) echo "③ root_of(git 밖 파일) rc1 · 빈 값";; ③spawn) echo "③ guard_spawn(git 밖 카드) rc3 «데이터 루트 판정 불가» 1줄";;
  ③guard) echo "③ switch_guard(루트 빈 값) rc3 1줄";; ④retire) echo "④ guard_retire(명부·이름 팀 없음) INFO rc0";;
  ④guard) echo "④ switch_guard(팀 빈 값 · 루트 있음) INFO rc0";; ④move) echo "④ guard_move(경로 팀 없음) INFO rc0";;
  ⑤none) echo "⑤ 표식 없는 팀 rc0 · 보류 쓰기 0";; ⑤broken) echo "⑤ 깨진 표식 rc3 판정 불가";; *) echo "$1";; esac; }
t=$(now)
while read -r k v; do ck "$(name "$k")" "$v"; done < <(cases "$LIB")
echo "반례 ①~⑤ $(secs "$t")"

# ── ⑥ 기존 시험 그대로 ────────────────────────────────────────────────────────
for f in test_team_switch_guard_r1675.sh test_root_bin_shim_source_r1694.sh; do
  t=$(now); bash "$HERE/$f" >"$T/$f.log" 2>&1; rc=$?
  ck "⑥ $f rc=$rc $(secs "$t")" "$rc"; [ "$rc" = 0 ] || grep '^FAIL' "$T/$f.log" | head -5
done

# ── 변이 M1~M4(사본에서만 · 변이마다 원본 대조 1회) ──────────────────────────
mut() {  # $1 이름 $2 원문 $3 바꿀 글 → 사본 $T/mut-$1/ft20-switch-lib.sh 에만 적용
  local d="$T/mut-$1"; rm -rf "$d"; mkdir -p "$d"; cp -p "$LIB" "$d/"
  python3 - "$d/ft20-switch-lib.sh" "$2" "$3" <<'PYMUT'
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
if s.count(a) != 1: sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PYMUT
}
pick() { grep "^$2 " <<<"$1" | cut -d' ' -f2; }   # cases 출력에서 사례 하나
t=$(now)
ORIG="$(cases "$LIB")"
mcheck() {  # $1 이름 $2 원문 $3 바꿀 글 $4 깨져야 할 사례
  if ! mut "$1" "$2" "$3"; then ck "$1 — 변이 자리 못 찾음" 1; return; fi
  local m o; m="$(pick "$(cases "$T/mut-$1/ft20-switch-lib.sh")" "$4")"; o="$(pick "$ORIG" "$4")"
  ck "$1 → $4 FAIL(변이=$m) · 원본 대조 PASS(원본=$o)" "$([ "$m" = 1 ] && [ "$o" = 0 ] && echo 0 || echo 1)"
}
mcheck M1 '  [ -f "$p" ] && p="$(dirname -- "$p")"' '  :' ①spawn
mcheck M2 '  while [ ! -e "$p" ]; do p="$(dirname -- "$p")"; done' '  :' ②spawn
mcheck M3 '  [ -n "$root" ] || { echo "REJECT 데이터 루트 판정 불가 — 2.0 전환 표식 검사 못 함 · 1.x 쓰기 0" >&2; return 3; }' '  [ -n "$root" ] || { echo "REJECT 데이터 루트 판정 불가 — 2.0 전환 표식 검사 못 함 · 1.x 쓰기 0" >&2; return 0; }' ③spawn
mcheck M4 '  [ -n "$team" ] || { echo "INFO 팀 판정 불가 — 2.0 전환 표식 검사 건너뜀(표식 없는 팀으로 본다)" >&2; return 0; }' '  [ -n "$team" ] || { echo "INFO 팀 판정 불가 — 2.0 전환 표식 검사 건너뜀(표식 없는 팀으로 본다)" >&2; return 3; }' ④guard
echo "변이 M1~M4 $(secs "$t")"

echo "RUN 1회차 $(secs "$t0") · 사례 $n"
[ "$fail" = 0 ] || { echo "FAIL 합계 $fail"; exit 1; }
echo "PASS 합계 $n"
