#!/usr/bin/env bash
# test_merge_land_ddl_dev_r1347c.sh — r1347 ③: 짝 시험(시험 1개 70 s 상한이라 셋으로 나눔 · 짝 = test_merge_land_ddl_dev_r1347.sh · r1347b)
#   반례 D10 · D11 · D18~D21 + 변이 4·9·12 · 기준판 = 관문 호출 줄만 뺀 land
#   틀 = _merge_ddl_fixture.sh · 실행 비트 0(100644) — `bash <이 파일>` · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐 · 고정 sleep 0 · 실 gh·실 DB·네트워크 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
mkmut base 4 9 12
pretest; tick 사전

# ===== D10: 앞 코멘트 h145 rc=0 · 뒤 코멘트 h146(rc=1) → REJECT(마지막 줄 선택) =====
mkpr 10 d10 "$SQ/69-d10.sql=select 10;" "shared/c10.py=print(10)"; A="$PRSHA"; setc 10 "DDL dev 적용: 69-d10.sql · h145 rc=0" "DDL dev 적용: 69-d10.sql · h146 rc=0"; pre
land "$LAND" 10 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 h146 확인 실패(rc=1)"* ]]; ck "D10 마지막 줄(h146 rc=1) 선택 → REJECT" $?
cnt "$BASE/ft-merge-land.sh" 10 "$A"; landed 10; ck "기준판 D10 → 착지" $?
cnt "$M4/ft-merge-land.sh" 10 "$A"; landed 10; ck "변이 4(첫 줄 선택) → D10 FAIL 재현" $?

# ===== D11: 코멘트 조회 실패 2회 → REJECT «판정 불가 — PR 코멘트 조회 실패» =====
mkpr 11 d11 "$SQ/70-d11.sql=select 11;" "shared/c11.py=print(11)"; A="$PRSHA"; setc 11 "DDL dev 적용: 70-d11.sql · h145 rc=0"; pre
STUB_CFAIL=1 land "$LAND" 11 --approve-sha "$A"
rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 판정 불가 — PR 코멘트 조회 실패 (착지 0)"* ]] && [ "$(grep -c '^COMMENTS' "$STUB_LOG")" = 2 ]; ck "D11 조회 실패(스텁 rc1 ×2) → REJECT «판정 불가» · 시도 2회" $?
STUB_CFAIL=1 cnt "$BASE/ft-merge-land.sh" 11 "$A"; landed 11; ck "기준판 D11 → 착지" $?
tick D10-D11

# ===== D18: --ff 경로 + DDL+코드 · 증거 0 → REJECT =====
mkpr 18 d18 "$SQ/77-d18.sql=select 18;" "shared/c18.py=print(18)"; A="$PRSHA"; pre
land "$LAND" 18 --approve-sha "$A" --ff; rejected "$PM" && [[ "$out" == *"증거 없음 — 77-d18.sql"* ]]; ck "D18 --ff + 증거 0 → REJECT(관문 건너뜀 0)" $?
cnt "$BASE/ft-merge-land.sh" 18 "$A" --ff; landed 18; ck "기준판 D18(--ff) → 착지" $?
cnt "$M9/ft-merge-land.sh" 18 "$A" --ff; landed 18; ck "변이 9(--ff 에서 관문 건너뜀) → D18 FAIL 재현" $?

# ===== D19: 9x 시험 DDL + 코드 → 통과 =====
mkpr 19 d19 "$SQ/90-t18-fixture.sql=select 19;" "shared/c19.py=print(19)"; A="$PRSHA"
land "$LAND" 19 --approve-sha "$A"; landed 19; ck "D19 90-t18-fixture.sql(9x 제외) + 코드 → 착지" $?

# ===== D20: 본문 «h145 rc=0» · 뒤 코멘트 «면제 — 짧음» → 마지막 = 코멘트 → REJECT =====
PRBODY="DDL dev 적용: 78-d20.sql · h145 rc=0"; mkpr 20 d20 "$SQ/78-d20.sql=select 20;" "shared/c20.py=print(20)"; A="$PRSHA"; PRBODY=b; setc 20 "DDL dev 적용: 78-d20.sql · 면제 — 짧음"; pre
land "$LAND" 20 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 면제 사유 10자 미만 — 78-d20.sql"* ]]; ck "D20 본문 뒤 코멘트가 마지막 줄 → 사유 10자 미만 REJECT" $?
cnt "$BASE/ft-merge-land.sh" 20 "$A"; landed 20; ck "기준판 D20 → 착지" $?
PRBODY="DDL dev 적용: 79-d20b.sql · h145 rc=0"; mkpr 21 d20b "$SQ/79-d20b.sql=select 20;" "shared/c20b.py=print(20)"; A="$PRSHA"; PRBODY=b
land "$LAND" 21 --approve-sha "$A"; landed 21; ck "D20 대조: 본문 증거 줄(h145 rc=0)만으로도 통과(본문 먼저 읽음)" $?

# ===== D21: main 자동 병합 C 경로(승인 뒤 main 앞섬 · 겹침 0) + D1 꼴 → REJECT =====
mkpr 22 d21 "$SQ/80-d21.sql=select 21;" "shared/c21.py=print(21)"; A="$PRSHA"; adv "shared/other21.py=print(0)"; pre
land "$LAND" 22 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"main 자동 병합"* && "$out" == *"증거 없음 — 80-d21.sql"* ]]; ck "D21 자동 병합 C 경로 + 증거 0 → REJECT(관문 건너뜀 0)" $?
cnt "$BASE/ft-merge-land.sh" 22 "$A"; landed 22; ck "기준판 D21 → 착지" $?
cnt "$M12/ft-merge-land.sh" 22 "$A"; landed 22; ck "변이 12(자동 병합 C 에서 관문 건너뜀) → D21 FAIL 재현" $?
tick D18-D21
finish
