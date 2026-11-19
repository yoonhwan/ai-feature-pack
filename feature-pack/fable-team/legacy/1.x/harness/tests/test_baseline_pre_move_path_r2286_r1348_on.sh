#!/usr/bin/env bash
# test_baseline_pre_move_path_r2286_r1348_on.sh — r2286 r1348 켬 몫 — ② 켬 · ③ 빈 커밋 sha
#   몸통 = lib/r2286_baseline_fixture.sh(clone --shared 사본 · 원 리포 쓰기 0) · 시험 1개 70초 · 동시 4개 이하 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
. "$HERE/lib/r2286_baseline_fixture.sh" && r2286_setup || exit 1
TG=r1348
E="$(git -C "$C" commit-tree "$(git -C "$C" hash-object -t tree -w /dev/null)" -m r2286-empty)" || { echo "판정 불가 — 빈 커밋 못 만듦"; exit 1; }
variant $R1348 _r2286_fake_$R1348 '^BASESHA=[0-9a-f]+' "BASESHA=$E"
printf '%s\n' "기준판" > "$T/fake.pfx"   # 가짜 BASESHA 사본으로 도는 사례
stage 준비
run b $R1348 1; run f _r2286_fake_$R1348 1; wait
stage 실행
baseline_ok b && ok "② r1348 켬 → «사본 못 뜸» 0(rc=$(rc b) 은 따지지 않음)" || bad "② r1348 켬 → $(grep '사본 못 뜸' "$T/b.log" | head -2)"
in70 b "②"
[ "$(cnt f "^FAIL.*사본 못 뜸")" = 1 ] && [ "$(rc f)" = 1 ] && [ "$(pass_with f "$T/fake.pfx")" = 0 ] \
  && ok "③ $TG 빈 커밋 sha + 켬 → «사본 못 뜸» FAIL 1줄 · 그 사본 사례 PASS 0 · rc1" \
  || bad "③ $TG «사본 못 뜸» $(cnt f "^FAIL.*사본 못 뜸")줄 · 그 사본 사례 PASS $(pass_with f "$T/fake.pfx") · rc=$(rc f)(기대 1줄 · 0 · rc1)"
in70 f "③"
echo "단계별 초:$STAGES (한 회차 합계 $SECONDS 초)"
echo "RESULT fail=$fail"
[ "$fail" = 0 ]
