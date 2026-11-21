#!/usr/bin/env bash
# test_merge_land_boot_smoke_r2384.sh — r2384 K4·K5: 병합 트리에 scripts/ci/boot_smoke.py 가 있으면 ft-merge-land 가 기동 smoke 를 1회 부른다(7초 · 시간 초과만 재시도 1)
#   반례 ⑭~⑯ + 변이 M7 · 기준판 Red = ⑭ ⑮(기준판 = 부르는 자리만 뺀 land) · ⑰⑱·M8 = test_merge_land_boot_smoke_r2384b.sh
#   틀 = _merge_ddl_fixture.sh + _merge_boot_smoke_fixture.sh · 실 원격·실 gh·실 python 앱 0 · 고정 sleep 0 · 실행 비트 0 — `bash <이 파일>` · 1개 70초 상한이라 a(⑭~⑯)·b(⑰~⑱)로 쪼갬
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_boot_smoke_fixture.sh"
pretest; tick 사전

# ===== ⑭ 스크립트 있음 · rc 0 → 착지 · 1회 부름 · 단계 초 boot= 따로 · 기준판 = 부름 0(Red) =====
mkpr 51 b14 "$BOOTPY" "$WPY" "gateway/main.py=app=2"; A="$PRSHA"; pre; mode ok
land "$LAND" 51 --approve-sha "$A"; landed 51 && grep -qx 'BOOT OK worker gateway' <<<"$out" && [ "$(calls)" = 1 ] && [ -n "$(bootsec)" ] \
  && tail -n 1 "$T/state/merge-gate.log" | grep -q ' pr=51 .* boot=[0-9]*s'; ck "⑭ smoke rc0 → 착지 · «BOOT OK worker gateway» · 호출 1 · LAND-PHASE boot= · merge-gate.log boot=Ns" $?
grep -q ' tree=ok canary= env=$' "$PYLOG" && grep -q "^CALL scripts/ci/boot_smoke.py pwd=" "$PYLOG" && ! grep -q 'import banner' <<<"$out"; ck "⑭ env -i(PATH·HOME·PYTHONPATH 만) · PYTHONPATH = 병합 트리(스크립트·worker 있음) · 마지막 1줄만" $?
rewind; mode ok; cnt "$BASE/ft-merge-land.sh" 51 "$A"; landed 51 && [ "$(calls)" = 0 ] && [ -z "$(bootsec)" ]; ck "기준판 ⑭ → 부름 0 · boot= 0 (Red)" $?
tick ⑭

# ===== ⑮ rc 1 → REJECT «기동 smoke 실패 …» · 착지 0 · 기준판 = 착지(Red) · M7 =====
mkpr 52 b15 "$BOOTPY" "$WPY"; A="$PRSHA"; pre; mode fail
land "$LAND" 52 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT 기동 smoke 실패 worker.main ImportError: boom"* ]] && [ "$(calls)" = 1 ] && [ -n "$(bootsec)" ]; ck "⑮ smoke rc1 → REJECT «기동 smoke 실패 worker.main …» · 착지 0 · 호출 1(재시도 0)" $?
mode fail; cnt "$BASE/ft-merge-land.sh" 52 "$A"; landed 52; ck "기준판 ⑮ → smoke 없이 착지(Red)" $?
mode fail; cnt "$M7/ft-merge-land.sh" 52 "$A"; landed 52; ck "변이 M7(smoke rc 안 봄) → ⑮ FAIL 재현" $?
mode fail; land "$LAND" 52 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT 기동 smoke 실패 "* ]]; ck "M7 뒤 원본 같은 ⑮ 1회 더 → REJECT" $?
tick ⑮

# ===== ⑯ 가짜 python 8초 멈춤 2회 → REJECT «기동 smoke 판정 불가» 1줄 · 호출 2 · 15초 안 =====
mode hang; t0=$SECONDS; land "$LAND" 52 --approve-sha "$A"; el=$((SECONDS - t0))
rejected "$PM" && [ "$(grep -c '기동 smoke 판정 불가' <<<"$out")" = 1 ] && [ "$(calls)" = 2 ] && [ "$(bootsec)" -le 15 ]; ck "⑯ 멈춤 2회 → REJECT «판정 불가» 1줄 · 호출 2 · boot=$(bootsec)s ≤ 15 (land ${el}s)" $?
tick ⑯

finish
