#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286.sh — r2286: 고정 옛 sha 기준판 구간을 가진 1.x 시험 3파일(r1348 · r726 · r728)
#   기본 실행 = 기준판 구간 SKIP 1줄 · 켬(FT_TEST_BASELINE=1) = legacy/1.x 이동 전 경로로 사본을 뜬다.
#   갈래(시험 1개 70초 상한이라 3파일로 나눔 · 같은 몸통):
#     base(기본 · 이 파일) = ① 기본 실행 rc0 · SKIP 1 · FAIL 0   ② 켬 → «사본 못 뜸» 0
#     fake(_fake_r2286.sh)   = ③ 가짜 BASESHA(빈 커밋) + 켬 → «사본 못 뜸» FAIL 1줄 · rc1   ④ 지금 판 bin 1곳 깨뜨림 + 기본 → 그 사례 FAIL · rc1
#     mut(_mut_r2286.sh)     = M1 SKIP 조건 뒤집음 → ① FAIL   M2 이동 전 경로 갈래 제거 → ② FAIL
#   격리 = git clone --shared 사본(mktemp) 안에서만 돈다 · 원 리포 쓰기 0 · 사본에 지금 작업 트리의 3파일을 덮는다.
set -uo pipefail
MODE="${1:-base}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)" || { echo "판정 불가 — git 루트 못 찾음"; exit 1; }
TREL="${HERE#"$TOP"/}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT   # 실경로(/var → /private/var) — 3파일의 «git 루트 기준 상대 경로» 계산이 어긋나지 않게
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
R1348=test_news_relay_spacing_cover_pin_r1348.sh; R726=test_goal_renumber_grace_r726.sh; R728=test_goal_draft_render_no_notice_r728.sh
STAGE0=$SECONDS; STAGES=""; stage() { STAGES="$STAGES $1=$((SECONDS - STAGE0))s"; STAGE0=$SECONDS; }

C="$T/copy"; CT="$C/$TREL"
git clone -q --shared --no-checkout "$TOP" "$C" 2>/dev/null && git -C "$C" checkout -q --detach "$(git -C "$TOP" rev-parse HEAD)" \
  || { echo "판정 불가 — 사본 clone 실패"; exit 1; }
for f in $R1348 $R726 $R728; do cp "$HERE/$f" "$CT/$f" || { echo "판정 불가 — $f 사본 못 덮음"; exit 1; }; done
stage 사본

variant() {  # <원본> <새 이름> <파이썬 정규식> <바꿀 글> — 사본 tests 안에 변형 1개(정확히 1곳 치환)
  python3 - "$CT/$1" "$CT/$2" "$3" "$4" <<'PY' || bad "변형 $2 못 만듦(대상이 1번 나오지 않음)"
import re, sys
src, dst, pat, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
out, n = re.subn(pat, lambda m: new, s, count=0, flags=re.M)
assert n == 1, n
open(dst, "w", encoding="utf-8").write(out)
PY
}
run() {  # <이름> <시험 파일> [VAR=값 …] — 배경 실행 · 결과 = $T/<이름>.{log,rc,sec}
  local n="$1" f="$2"; shift 2
  ( s=$SECONDS; env -u FT_TEST_BASELINE -u R1348_TEST_RUNNING "$@" bash "$CT/$f" > "$T/$n.log" 2>&1
    echo $? > "$T/$n.rc"; echo $((SECONDS - s)) > "$T/$n.sec" ) &
}
cnt() { grep -c -- "$2" "$T/$1.log" 2>/dev/null || true; }
rc() { cat "$T/$1.rc"; }
sec() { cat "$T/$1.sec"; }
in70() { [ "$(sec "$1")" -le 70 ] && ok "$2 ${1} $(sec "$1")초(70초 안)" || bad "$2 ${1} $(sec "$1")초 > 70초"; }
default_ok() {  # <이름> — ① 판정
  [ "$(rc "$1")" = 0 ] && [ "$(cnt "$1" '^SKIP 기준판 구간')" = 1 ] && [ "$(cnt "$1" '^FAIL')" = 0 ]
}
baseline_ok() { [ "$(cnt "$1" '사본 못 뜸')" = 0 ]; }   # ② 판정(rc 는 따지지 않음 · C3)

case "$MODE" in
base)
  echo "== ① 기본 실행 → rc0 · SKIP 1줄 · FAIL 0   ② FT_TEST_BASELINE=1 → «사본 못 뜸» 0"
  run d1348 $R1348; run b1348 $R1348 FT_TEST_BASELINE=1; run d726 $R726; run b726 $R726 FT_TEST_BASELINE=1; wait
  run d728 $R728; run b728 $R728 FT_TEST_BASELINE=1; wait
  for n in 1348 726 728; do
    default_ok "d$n" && ok "① r$n 기본 rc0 · SKIP 1줄 · FAIL 0 · PASS $(cnt "d$n" '^PASS')" \
      || bad "① r$n 기본 rc=$(rc "d$n") SKIP=$(cnt "d$n" '^SKIP 기준판 구간') :: $(grep '^FAIL' "$T/d$n.log" | head -3)"
    in70 "d$n" "①"
    baseline_ok "b$n" && ok "② r$n 켬 → «사본 못 뜸» 0(이동 전 경로로 뜸 · rc=$(rc "b$n") 은 따지지 않음)" \
      || bad "② r$n 켬 → $(grep '사본 못 뜸' "$T/b$n.log" | head -2)"
    in70 "b$n" "②"
  done
  stage 기본·켬;;
fake)
  echo "== ③ 가짜 BASESHA(빈 커밋) + 켬 → «사본 못 뜸» FAIL 1줄 · rc1   ④ 지금 판 bin 1곳 깨뜨림 + 기본 → 그 사례 FAIL · rc1"
  E="$(git -C "$C" commit-tree "$(git -C "$C" hash-object -t tree -w /dev/null)" -m r2286-empty)" || { echo "판정 불가 — 빈 커밋 못 만듦"; exit 1; }
  for f in $R1348 $R726 $R728; do variant "$f" "_r2286_fake_$f" '^BASESHA=[0-9a-f]+' "BASESHA=$E"; done
  BROKEN="$T/broken"; mkdir -p "$BROKEN"; KB="$C/${TREL%/tests}/kit/fable-team/bin"
  cp "$KB"/{ft_goal_table.py,ft_goal_ledger.py,ft_team_lib.py,ft_goal_readjust_state.py} "$BROKEN"/ || bad "④ 깨진 bin 사본 못 뜸"
  python3 - "$BROKEN/ft_goal_table.py" <<'PY' || bad "④ 깨뜨릴 자리(r726 ⓖ1 변이와 같은 자리) 없음"
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = '    if elapsed < 0 or elapsed >= hours * 3600:\n        return ""'
assert s.count(a) == 1
open(p, "w", encoding="utf-8").write(s.replace(a, "", 1))
PY
  variant $R726 "_r2286_broken_$R726" '^TOOL=.*$' 'TOOL="$R2286_BROKEN/ft_goal_table.py"'
  run f1348 "_r2286_fake_$R1348" FT_TEST_BASELINE=1; run f726 "_r2286_fake_$R726" FT_TEST_BASELINE=1
  run f728 "_r2286_fake_$R728" FT_TEST_BASELINE=1; run k726 "_r2286_broken_$R726" R2286_BROKEN="$BROKEN"; wait
  for n in 1348 726 728; do
    [ "$(cnt "f$n" '^FAIL.*사본 못 뜸')" = 1 ] && [ "$(rc "f$n")" = 1 ] && ok "③ r$n 빈 커밋 sha + 켬 → «사본 못 뜸» FAIL 1줄 · rc1" \
      || bad "③ r$n «사본 못 뜸» $(cnt "f$n" '^FAIL.*사본 못 뜸')줄 · rc=$(rc "f$n")(기대 1줄 · rc1)"
    in70 "f$n" "③"
  done
  [ "$(cnt k726 '^FAIL ⓒ1 ')" -ge 1 ] && [ "$(rc k726)" = 1 ] && [ "$(cnt k726 '^SKIP 기준판 구간')" = 1 ] \
    && ok "④ r726 유예 시간 검사 깨뜨림 + 기본 → ⓒ1 FAIL · rc1(꺼짐이 지금 판 사례를 가리지 않음)" \
    || bad "④ r726 깨진 bin 기본 rc=$(rc k726) ⓒ1 FAIL=$(cnt k726 '^FAIL ⓒ1 ')"
  in70 k726 "④"
  stage 가짜·깨짐;;
mut)
  echo "== M1 SKIP 조건 뒤집음 → ① FAIL   M2 이동 전 경로 갈래 제거 → ② FAIL (원본 짝 = base 갈래 ①·②)"
  for f in $R1348 $R726 $R728; do
    variant "$f" "_r2286_m1_$f" '\[ "\$\{FT_TEST_BASELINE:-\}" = 1 \]' '[ "${FT_TEST_BASELINE:-}" != 1 ]'
    variant "$f" "_r2286_m2_$f" '"\$\{2/legacy\\/1\.x\\//\}"' '"$2"'
  done
  run m1_1348 "_r2286_m1_$R1348"; run m2_1348 "_r2286_m2_$R1348" FT_TEST_BASELINE=1
  run m1_726 "_r2286_m1_$R726"; run m2_726 "_r2286_m2_$R726" FT_TEST_BASELINE=1; wait
  run m1_728 "_r2286_m1_$R728"; run m2_728 "_r2286_m2_$R728" FT_TEST_BASELINE=1; wait
  for n in 1348 726 728; do
    default_ok "m1_$n" && bad "M1 r$n SKIP 조건 뒤집어도 ① 이 통과(변이 못 잡음)" \
      || ok "M1 r$n SKIP 조건 뒤집음 → ① FAIL(rc=$(rc "m1_$n") · SKIP $(cnt "m1_$n" '^SKIP 기준판 구간')줄)"
    in70 "m1_$n" "M1"
    baseline_ok "m2_$n" && bad "M2 r$n 이동 전 경로 갈래 지워도 ② 가 통과(변이 못 잡음)" \
      || ok "M2 r$n 이동 전 경로 갈래 제거 → ② FAIL(«사본 못 뜸» $(cnt "m2_$n" '사본 못 뜸')줄)"
    in70 "m2_$n" "M2"
  done
  stage 변이;;
*) echo "판정 불가 — 모르는 갈래 «$MODE»(base · fake · mut)"; exit 1;;
esac

echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT r2286 $MODE fail=$fail"
[ "$fail" = 0 ]
