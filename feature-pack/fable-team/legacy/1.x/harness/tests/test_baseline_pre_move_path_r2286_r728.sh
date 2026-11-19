#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286_r728.sh — r2286 r728 몫 — ① 기본 · ② 켬 · ③ 빈 커밋 sha · ④ ⓓ(r726 통째) · ⑥ 회귀 · M1 · M2(원본 짝 = 같은 파일의 ①·②)
#   몸통 = lib/r2286_baseline_fixture.sh(clone --shared 사본 · 원 리포 쓰기 0) · 시험 1개 70초 · 동시 4개 이하 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1
TG=r728
E="$(git -C "$C" commit-tree "$(git -C "$C" hash-object -t tree -w /dev/null)" -m r2286-empty)" || { echo "판정 불가 — 빈 커밋 못 만듦"; exit 1; }
main_tree
variant $R728 _r2286_fake_$R728 '^BASESHA=[0-9a-f]+' "BASESHA=$E"
variant $R728 _r2286_m1_$R728 '\[ "\$\{FT_TEST_BASELINE:-\}" = 1 \]' '[ "${FT_TEST_BASELINE:-}" != 1 ]'
variant $R728 _r2286_m2_$R728 '"\$\{2/legacy\\/1\.x\\//\}"' '"$2"'
printf '%s\n' "ⓐ" > "$T/fake.pfx"   # 가짜 BASESHA 사본으로 도는 사례
stage 준비
run d $R728 0; run o $R728 0 "" "$MT"; run b $R728 1; run f _r2286_fake_$R728 1; wait
run m1 _r2286_m1_$R728 0; run m2 _r2286_m2_$R728 1; wait
stage 실행
default_ok d && ok "① r728 기본 rc0 · SKIP 1줄 · FAIL 0" || bad "① r728 기본 rc=$(rc d) SKIP=$(cnt d '^SKIP 기준판 구간(') :: $(grep '^FAIL' "$T/d.log" | head -3)"
in70 d "①"
set_check r728 d o $R728 "ⓓ r726 시험 rc0"
[ "$(cnt d '^PASS ⓓ r726 시험 rc0')" = 1 ] && ok "④ r728 ⓓ(r726 통째) PASS" || bad "④ r728 ⓓ :: $(grep '^FAIL ⓓ' "$T/d.log" | head -2)"
baseline_ok b && ok "② r728 켬 → «사본 못 뜸» 0(rc=$(rc b) 은 따지지 않음)" || bad "② r728 켬 → $(grep '사본 못 뜸' "$T/b.log" | head -2)"
in70 b "②"
[ "$(cnt f "^FAIL.*사본 못 뜸")" = 1 ] && [ "$(rc f)" = 1 ] && [ "$(pass_with f "$T/fake.pfx")" = 0 ] \
  && ok "③ $TG 빈 커밋 sha + 켬 → «사본 못 뜸» FAIL 1줄 · 그 사본 사례 PASS 0 · rc1" \
  || bad "③ $TG «사본 못 뜸» $(cnt f "^FAIL.*사본 못 뜸")줄 · 그 사본 사례 PASS $(pass_with f "$T/fake.pfx") · rc=$(rc f)(기대 1줄 · 0 · rc1)"
in70 f "③"
default_ok m1 && bad "M1 r728 SKIP 조건 뒤집어도 ① 통과(변이 못 잡음)" || ok "M1 r728 SKIP 조건 뒤집음 → ① FAIL(rc=$(rc m1) · SKIP $(cnt m1 '^SKIP 기준판 구간(')줄)"
in70 m1 "M1"
baseline_ok m2 && bad "M2 r728 이동 전 경로 갈래 지워도 ② 통과(변이 못 잡음)" || ok "M2 r728 이동 전 경로 갈래 제거 → ② FAIL(«사본 못 뜸» $(cnt m2 '사본 못 뜸')줄)"
in70 m2 "M2"
echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
