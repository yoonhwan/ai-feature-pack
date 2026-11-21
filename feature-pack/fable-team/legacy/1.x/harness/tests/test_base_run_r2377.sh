#!/usr/bin/env bash
# test_base_run_r2377.sh — r2377 · «기준판에서도 같은 시험이 FAILED 인가» 비교 = 한 명령(ft-base-run.sh) · 사본은 $TMPDIR/tmp.ftbase.*/tree 에 살고 끝나면 지운다 + 손 스크립트의 /tmp 고정 export 는 러너 린트가 WARN BASECOPY
#   이 파일 = 반례 ①~⑬ (계약 K1~K4 · ⑬ = 정정 r3 fail-open 금지) · 회귀 ⑭ = test_base_run_r2377_reg.sh(무거워서 밖). 변이 M1~M7 = test_base_run_r2377_mut.sh (70초 상한으로 쪼갬 · 세계는 tests/lib/r2377_fixture.sh 하나)
#   R2377_BIN = 기준판 대조용 bin 폴더. 지정하면 ②~⑦·⑨·⑩ 은 SKIP(그 판에 명령 없음) · 기준판 Red = ①·⑧·⑪
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib/r2377_fixture.sh"
. "$HERE/lib/r2377_cells.sh"

c1;  ck "① 커밋 A · --path 없음 → BASE …/tree 첫 줄 · pwd = 사본 · 내용 = A 트리" "$RES" "$MSG"
if [ "$BASE_MODE" = 1 ]; then
  sk "②~⑦·⑨·⑩" "기준판 모드(R2377_BIN) — 그 판에 ft-base-run.sh 가 없어 «명령 없음» 판정 불가"
else
  c2;  ck "② --path d1 → d1 만 · d2 0" "$RES" "$MSG"
  c3;  ck "③ 없는 ref → 판정 불가 — ref · rc 20 · 사본 0 · 시험 0" "$RES" "$MSG"
  c4;  ck "④ archive 멈춤(2초 상한) → 판정 불가 — archive · rc 20 · 사본 0 · 시험 0 (${T4}초)" "$RES" "$MSG"
  c5;  ck "⑤ -- 없음 · 시험 명령 없음 → rc 2 · 쓰기 0" "$RES" "$MSG"
  c6;  ck "⑥ 시험 rc 0·3 → 명령 rc 0·3" "$RES" "$MSG"
  c7;  ck "⑦ --git → 사본 git HEAD rc0 · status 0줄 · 원 리포 쓰기 0" "$RES" "$MSG"
  c9;  ck "⑨ sleep 30 + 1초째 TERM → 3초 안에 사본 0 · rc 143" "$RES" "$MSG"
  c10; ck "⑩ SIGKILL 두 꼴(--git 없음/있음) → 사본 1개 · 맨 위 .git 0 · --gate G1·G2·G5" "$RES" "$MSG"
fi
c8;  ck "⑧ 시험 끝(rc 0·3) → 남은 사본 0 · 손 스크립트 꼴은 남음(기준판 대조)" "$RES" "$MSG"
c11; ck "⑪ 손 스크립트 두 꼴(글자 · a505 변수) → BASECOPY 1줄 · rc 3 (기준판 = 줄 0 → Red)" "$RES" "$MSG"
if [ "$BASE_MODE" = 1 ]; then
  sk "⑫·⑬" "기준판 모드 — BASECOPY 갈래가 없어 «WARN BASECOPY 뒤 실행» 은 그 판에 존재하지 않는다"
else
  c12x3; ck "⑫ trap 두 꼴 · ft-base-run.sh 부름 → BASECOPY 0 · 러너는 WARN 뒤 실행 · 기존 린트 시험 그대로 (3회 연속)" "$RES" "$MSG"
  c13; ck "⑬ (정정 r3) 가짜 python3(exit 1) → BASECOPY-판정불가 1줄 · rc 3 (fail-open 0)" "$RES" "$MSG"
fi

echo "[시간] 반례 ①~⑬ $((SECONDS - T0))초"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit "$fail"
