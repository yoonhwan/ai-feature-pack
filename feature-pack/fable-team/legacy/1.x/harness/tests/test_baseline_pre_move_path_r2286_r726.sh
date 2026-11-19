#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286_r726.sh — r2286 r726 몫 — ① 기본 · ② 켬 · ③ 빈 커밋 sha · ④ 지금 판 가드 · ⑤ 깨진 bin · ⑥ 회귀 · M1 · M2 · M3(원본 짝 = 같은 파일의 ①·②·④)
#   몸통 = lib/r2286_baseline_fixture.sh(clone --shared 사본 · 원 리포 쓰기 0) · 시험 1개 70초 · 동시 4개 이하 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1
TG=r726
E="$(git -C "$C" commit-tree "$(git -C "$C" hash-object -t tree -w /dev/null)" -m r2286-empty)" || { echo "판정 불가 — 빈 커밋 못 만듦"; exit 1; }
main_tree
variant $R726 _r2286_fake_$R726 '^BASESHA=[0-9a-f]+' "BASESHA=$E"
variant $R726 _r2286_broken_$R726 '^TOOL=.*$' 'TOOL="$R2286_BROKEN/ft_goal_table.py"'
variant $R726 _r2286_m1_$R726 '\[ "\$\{FT_TEST_BASELINE:-\}" = 1 \]' '[ "${FT_TEST_BASELINE:-}" != 1 ]'
variant $R726 _r2286_m2_$R726 '"\$\{2/legacy\\/1\.x\\//\}"' '"$2"'
variant $R726 _r2286_m3_$R726 '^ +GOAL_TABLE_HEADS=.*\n' ''
BROKEN="$T/broken"; mkdir -p "$BROKEN"; KB="$C/${TREL%/tests}/kit/fable-team/bin"
cp "$KB"/{ft_goal_table.py,ft_goal_ledger.py,ft_team_lib.py,ft_goal_readjust_state.py} "$BROKEN"/ || bad "⑤ 깨진 bin 사본 못 뜸"
python3 - "$BROKEN/ft_goal_table.py" <<'PY' || bad "⑤ 깨뜨릴 자리(r726 ⓖ1 변이와 같은 자리) 없음"
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = '    if elapsed < 0 or elapsed >= hours * 3600:\n        return ""'
assert s.count(a) == 1
open(p, "w", encoding="utf-8").write(s.replace(a, "", 1))
PY
printf '%s\n' "ⓐ" "ⓑ3" > "$T/fake.pfx"   # 가짜 BASESHA 사본으로 도는 사례
stage 준비
run d $R726 0; run o $R726 0 "" "$MT"; run b $R726 1; run f _r2286_fake_$R726 1; wait
run k _r2286_broken_$R726 0 "$BROKEN"; run m1 _r2286_m1_$R726 0; run m2 _r2286_m2_$R726 1; run m3 _r2286_m3_$R726 0; wait
stage 실행
default_ok d && ok "① r726 기본 rc0 · SKIP 1줄 · FAIL 0" || bad "① r726 기본 rc=$(rc d) SKIP=$(cnt d '^SKIP 기준판 구간(') :: $(grep '^FAIL' "$T/d.log" | head -3)"
in70 d "①"
set_check r726 d o $R726 "ⓠ 가드 stderr 에 GL-GRACE" "ⓡ relay 유예 = GL-GRACE 1줄"
baseline_ok b && ok "② r726 켬 → «사본 못 뜸» 0(rc=$(rc b) 은 따지지 않음)" || bad "② r726 켬 → $(grep '사본 못 뜸' "$T/b.log" | head -2)"
in70 b "②"
[ "$(cnt f "^FAIL.*사본 못 뜸")" = 1 ] && [ "$(rc f)" = 1 ] && [ "$(pass_with f "$T/fake.pfx")" = 0 ] \
  && ok "③ $TG 빈 커밋 sha + 켬 → «사본 못 뜸» FAIL 1줄 · 그 사본 사례 PASS 0 · rc1" \
  || bad "③ $TG «사본 못 뜸» $(cnt f "^FAIL.*사본 못 뜸")줄 · 그 사본 사례 PASS $(pass_with f "$T/fake.pfx") · rc=$(rc f)(기대 1줄 · 0 · rc1)"
in70 f "③"
g4() { [ "$(cnt "$1" 'grep: empty (sub)expression')" = 0 ] && [ "$(cnt "$1" '^PASS ⓠ 가드는 유예 통과를 막지 않는다')" = 1 ] \
  && [ "$(cnt "$1" '^PASS ⓠ 가드 stderr 에 GL-GRACE')" = 1 ] && [ "$(cnt "$1" '^PASS ⓡ relay 유예 = GL-GRACE 1줄')" = 1 ]; }
g4 d && ok "④ r726 기본 → 지금 판 가드 ⓠ·ⓠ경고·ⓡ PASS · «grep: empty (sub)expression» 0" \
  || bad "④ r726 지금 판 가드 :: grep 빈 식 $(cnt d 'grep: empty (sub)expression')줄 · $(grep -E '^FAIL ⓠ|^FAIL ⓡ' "$T/d.log" | head -3)"
[ "$(cnt k '^FAIL ⓒ1 ')" -ge 1 ] && [ "$(rc k)" = 1 ] && [ "$(cnt k '^SKIP 기준판 구간(')" = 1 ] \
  && ok "⑤ r726 유예 시간 검사 깨뜨림 + 기본 → ⓒ1 FAIL · rc1(꺼짐이 지금 판 사례를 가리지 않음)" \
  || bad "⑤ r726 깨진 bin 기본 rc=$(rc k) ⓒ1 FAIL=$(cnt k '^FAIL ⓒ1 ')"
in70 k "⑤"
default_ok m1 && bad "M1 r726 SKIP 조건 뒤집어도 ① 통과(변이 못 잡음)" || ok "M1 r726 SKIP 조건 뒤집음 → ① FAIL(rc=$(rc m1) · SKIP $(cnt m1 '^SKIP 기준판 구간(')줄)"
in70 m1 "M1"
baseline_ok m2 && bad "M2 r726 이동 전 경로 갈래 지워도 ② 통과(변이 못 잡음)" || ok "M2 r726 이동 전 경로 갈래 제거 → ② FAIL(«사본 못 뜸» $(cnt m2 '사본 못 뜸')줄)"
in70 m2 "M2"
g4 m3 && bad "M3 r726 gtest 머리 이름 2개 지워도 ④ 통과(변이 못 잡음)" || ok "M3 r726 gtest 머리 이름 2개 제거 → ④ FAIL(grep 빈 식 $(cnt m3 'grep: empty (sub)expression')줄)"
in70 m3 "M3"
echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
