#!/usr/bin/env bash
# test_merge_land_boot_smoke_r2384b.sh — r2384 K4·K5: 병합 트리에 scripts/ci/boot_smoke.py 가 있으면 ft-merge-land 가 기동 smoke 를 1회 부른다(7초 · 시간 초과만 재시도 1)
#   반례 ⑰~⑱ + ⑭b(정정 r2 H1 · 실 worker 가 scripts.* import) + 변이 M8·M9 · ⑭~⑯·M7·기준판 Red = test_merge_land_boot_smoke_r2384.sh
#   틀 = _merge_ddl_fixture.sh + _merge_boot_smoke_fixture.sh · 실 원격·실 gh·실 python 앱 0 · 고정 sleep 0 · 실행 비트 0 — `bash <이 파일>` · 1개 70초 상한이라 a(⑭~⑯)·b(⑰~⑱)로 쪼갬
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_boot_smoke_fixture.sh"
pretest; tick 사전

# ===== ⑰ 남은 예산 ≤ 7초 → 시도 상한 = 남은 − 1 · 0 이하 = «판정 불가» · 호출 0 =====
mkpr 54 b17 "$BOOTPY" "$WPY"; SB52="$PRSHA"; . "$LIB"
mode hang; t0=$SECONDS; o17="$(fm_boot_smoke "$W" "$SB52" 5)"; r17=$?; el=$((SECONDS - t0))
[ "$r17" = 1 ] && [[ "$o17" == "기동 smoke 판정 불가"* ]] && [ "$(calls)" = 1 ] && [ "$el" -ge 3 ] && [ "$el" -le 5 ]; ck "⑰ 남은 5초 → 시도 상한 4초 1회 · rc1 «판정 불가» (${el}s)" $?
mode ok; o17="$(fm_boot_smoke "$W" "$SB52" 1)"; r17=$?
[ "$r17" = 1 ] && [[ "$o17" == "기동 smoke 판정 불가"* ]] && [ "$(calls)" = 0 ]; ck "⑰ 남은 1초 → 시도 상한 0 → «판정 불가» · 호출 0" $?
mode ok; o17="$(fm_boot_smoke "$W" 0000000000000000000000000000000000000000 30)"; r17=$?
[ "$r17" = 1 ] && [[ "$o17" == "기동 smoke 판정 불가"* ]] && [ "$(calls)" = 0 ]; ck "⑰ git 실패(없는 커밋) → «판정 불가» rc1(대상 밖 아님 · 하드 룰 20)" $?
tick ⑰

# ===== ⑭b(정정 r2 H1) 실 worker 꼴: worker.main 이 scripts.rag(scripts/ci 밖)를 import → 풀 트리에 scripts/rag 있음 · rc0 착지 · M9 =====
mkpr 55 b14b "$BOOTPY" "$WPY" "worker/services/loom.py=import scripts.rag" "scripts/rag/r.py=x=1"; A="$PRSHA"; pre; mode needrag
land "$LAND" 55 --approve-sha "$A"; landed 55 && grep -qx 'BOOT OK worker gateway' <<<"$out" && [ "$(calls)" = 1 ]; ck "⑭b worker 가 scripts.rag import → 트리에 scripts/rag · BOOT OK · 착지 · 호출 1" $?
rewind; mode needrag; cnt "$M9/ft-merge-land.sh" 55 "$A"; rejected "$PM" && [[ "$out" == *"REJECT 기동 smoke 실패 BOOT FAIL worker.main ModuleNotFoundError: No module named 'scripts.rag'"* ]]; ck "변이 M9(풀 목록 scripts 빠짐) → ⑭b FAIL 재현(거짓 REJECT)" $?
mode needrag; cnt "$LAND" 55 "$A"; landed 55; ck "M9 뒤 원본 같은 ⑭b 1회 더 → 착지" $?
tick ⑭b

# ===== ⑱ 스크립트 없는 리포 → «대상 밖» · 호출 0 · 다른 단계 출력 지금과 같음 · M8 =====
mkpr 53 b18 "$WPY" "scripts/x.py=print(3)"; A="$PRSHA"; pre; mode ok
LRT="$T/.fable-team/state/land-record-turn.jsonl"   # 차례 장부 = 앞 착지가 남긴 행에 따라 «정리 차례» 줄이 달라진다 → 대조 두 착지 앞에서 비운다
rm -f "$LRT"; cnt "$SAME/ft-merge-land.sh" 53 "$A"; o18="$out"; landed 53 && [ "$(calls)" = 0 ] && ! grep -q '기동 smoke\| boot=' <<<"$o18"; ck "⑱ 스크립트 없음 → 착지 · 호출 0 · smoke 줄·boot= 0" $?
mode ok; rm -f "$LRT"; cnt "$BASE/ft-merge-land.sh" 53 "$A"; nz() { sed -E 's/[0-9a-f]{7,40}/H/g; s/[0-9]+/N/g' <<<"$1"; }
diff <(nz "$o18") <(nz "$out") >&2; ck "⑱ 출력 = 기준판과 같음(sha·숫자만 다름)" $?
[ "$(fm_boot_smoke "$W" "$(sha "$W" b18)" 30)" = "기동 smoke 대상 밖" ]; ck "⑱ fm_boot_smoke → «기동 smoke 대상 밖» rc0" $?
cnt "$M8/ft-merge-land.sh" 53 "$A"; [ "$rc" = 1 ] && [[ "$out" == *"REJECT 기동 smoke 대상 밖"* ]]; ck "변이 M8(대상 밖 = REJECT) → ⑱ FAIL 재현" $?
mode ok; cnt "$LAND" 53 "$A"; landed 53 && [ "$(calls)" = 0 ]; ck "M8 뒤 원본 같은 ⑱ 1회 더 → 착지 · 호출 0" $?
tick ⑱
[ "$(awk '/^fm_boot_smoke\(\) \{/{f=1} f{n++} f&&/^\}/{print n; exit}' "$LIB")" -le 40 ]; ck "fm_boot_smoke 본문 ≤ 40줄" $?
finish
