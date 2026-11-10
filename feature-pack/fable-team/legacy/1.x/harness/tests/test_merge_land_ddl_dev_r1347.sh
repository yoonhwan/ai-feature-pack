#!/usr/bin/env bash
# test_merge_land_ddl_dev_r1347.sh — r1347 ①: ft-merge-land 가 «DDL 파일 + 그 DDL 을 쓰는 코드» 를 같이 올리는 PR 을 dev 적용 증거 줄 없이 착지하지 않는다
#   반례 D1~D9 + D17 + 변이 1·2·3·5·10 · 기준판 = 관문 호출 줄만 뺀 land · 짝 시험 = r1347b(D12~D16) · r1347c(D10·D11·D18~D21) — 시험 1개 70 s 상한이라 셋으로 나눔
#   틀 = _merge_ddl_fixture.sh · 실행 비트 0(100644) — `bash <이 파일>` · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐 · 고정 sleep 0 · 실 gh·실 DB·네트워크 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
mkmut base 1 2 3 5 10
pretest; tick 사전

# ===== D1: DDL + 코드 · 증거 줄 0 → REJECT «증거 없음 — 60-…sql» · 기준판은 착지 =====
mkpr 1 d1 "$SQ/60-d1.sql=select 1;" "shared/c1.py=print(1)"; A="$PRSHA"; pre
land "$LAND" 1 --approve-sha "$A"
rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 증거 없음 — 60-d1.sql (코드 1개 동반)"* && "$out" == *"(착지 0)"* ]]; ck "D1 → REJECT «DDL dev 적용 증거 없음 — 60-d1.sql (코드 1개 동반)» · 착지 0 · main 불변" $?
cnt "$BASE/ft-merge-land.sh" 1 "$A"; landed 1; ck "기준판 D1 → 증거 없이 착지(관문 전 동작 재현)" $?

# ===== D2: D1 + 코멘트 «61-….sql · h145 rc=0» · h145.ran 마지막 rc=0 → 통과 =====
mkpr 2 d2 "$SQ/61-d2.sql=select 2;" "shared/c2.py=print(2)"; A="$PRSHA"; setc 2 "DDL dev 적용: 61-d2.sql · h145 rc=0"
land "$LAND" 2 --approve-sha "$A"; landed 2 && [ "$(oshow $SQ/61-d2.sql)" = "select 2;" ]; ck "D2 증거 줄(h145 rc=0) → 착지" $?

# ===== D3: h146.ran 마지막 rc=1 → REJECT «h146 확인 실패(rc=1)» =====
mkpr 3 d3 "$SQ/62-d3.sql=select 3;" "shared/c3.py=print(3)"; A="$PRSHA"; setc 3 "DDL dev 적용: 62-d3.sql · h146 rc=0"; pre
land "$LAND" 3 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 h146 확인 실패(rc=1)"* ]]; ck "D3 h146.ran rc=1 → REJECT «h146 확인 실패(rc=1)»" $?
cnt "$BASE/ft-merge-land.sh" 3 "$A"; landed 3; ck "기준판 D3 → 착지" $?
cnt "$M3/ft-merge-land.sh" 3 "$A"; landed 3; ck "변이 3(rc 확인 제거) → D3 FAIL 재현(착지)" $?

# ===== D4: h147.ran 없음 → REJECT «확인 실패(기록 없음)» =====
mkpr 4 d4 "$SQ/63-d4.sql=select 4;" "shared/c4.py=print(4)"; A="$PRSHA"; setc 4 "DDL dev 적용: 63-d4.sql · h147 rc=0"; pre
land "$LAND" 4 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 h147 확인 실패(기록 없음)"* ]]; ck "D4 h147.ran 없음 → REJECT «h147 확인 실패(기록 없음)»" $?
cnt "$BASE/ft-merge-land.sh" 4 "$A"; landed 4; ck "기준판 D4 → 착지" $?

# ===== D5: DDL 만(코드 0 · md 1) → 통과 · 코멘트 조회 0 =====
mkpr 5 d5 "$SQ/64-d5.sql=select 5;" "design/x/d5.md=doc"; A="$PRSHA"; pre
cnt "$M1/ft-merge-land.sh" 5 "$A"; rejected "$PM" && [[ "$out" == *"DDL dev 적용 증거 없음 — 64-d5.sql"* ]]; ck "변이 1(코드 0 조건 제거) → D5 FAIL 재현(DDL 만인데 REJECT)" $?
land "$LAND" 5 --approve-sha "$A"; landed 5 && ! grep -q '^COMMENTS' "$STUB_LOG"; ck "D5 DDL 만 → 통과 · 코멘트 조회 0" $?

# ===== D6 + D17: 코드만(DDL 0) → 통과 · 코멘트 추가 조회 0 =====
mkpr 6 d6 "shared/c6.py=print(6)"; A="$PRSHA"; pre
cnt "$M10/ft-merge-land.sh" 6 "$A"; grep -q '^COMMENTS' "$STUB_LOG"; ck "변이 10(코멘트 늘 조회) → D17 FAIL 재현(조회 발생)" $?
land "$LAND" 6 --approve-sha "$A"; landed 6; ck "D6 코드만 → 통과" $?
! grep -q '^COMMENTS' "$STUB_LOG"; ck "D17 DDL 없는 PR → 코멘트 추가 조회 0(스텁 호출 기록 0줄)" $?

# ===== D7: DDL 65 + 65-rollback + 코드 · 65 증거만 → 통과(rollback 제외) =====
mkpr 7 d7 "$SQ/65-d7.sql=select 7;" "$SQ/65-d7-rollback.sql=drop 7;" "shared/c7.py=print(7)"; A="$PRSHA"; setc 7 "DDL dev 적용: 65-d7.sql · h145 rc=0"; pre
cnt "$M2/ft-merge-land.sh" 7 "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 65-d7-rollback.sql"* ]]; ck "변이 2(rollback 제외 제거) → D7 FAIL 재현" $?
land "$LAND" 7 --approve-sha "$A"; landed 7; ck "D7 rollback 은 대상 밖 → 착지" $?

# ===== D8: DDL 2개(66·67) + 코드 · 66 증거만 → REJECT «67-…sql» =====
mkpr 8 d8 "$SQ/66-d8a.sql=select 8;" "$SQ/67-d8b.sql=select 88;" "shared/c8.py=print(8)"; A="$PRSHA"; setc 8 "DDL dev 적용: 66-d8a.sql · h145 rc=0"; pre
land "$LAND" 8 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 67-d8b.sql"* ]]; ck "D8 둘째 DDL 증거 없음 → REJECT «67-d8b.sql»" $?
cnt "$BASE/ft-merge-land.sh" 8 "$A"; landed 8; ck "기준판 D8 → 착지" $?
cnt "$M5/ft-merge-land.sh" 8 "$A"; landed 8; ck "변이 5(DDL 파일마다 → 첫 파일만) → D8 FAIL 재현" $?

# ===== D9: «면제 — 사유 ≥10자» → 통과 + WARN 1줄 · 사유 9자 → REJECT =====
mkpr 9 d9 "$SQ/68-d9.sql=select 9;" "shared/c9.py=print(9)"; A="$PRSHA"; setc 9 "DDL dev 적용: 68-d9.sql · 면제 — abcdefghi"; pre
land "$LAND" 9 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 면제 사유 10자 미만 — 68-d9.sql"* ]]; ck "D9 사유 9자 → REJECT" $?
setc 9 "DDL dev 적용: 68-d9.sql · 면제 — 함수 변경 없는 주석 수정만"
land "$LAND" 9 --approve-sha "$A"; landed 9 && [[ "$out" == *"WARN DDL dev 적용 면제 68-d9.sql — 함수 변경 없는 주석 수정만"* ]] && [ "$(grep -c '^WARN DDL dev 적용 면제' <<<"$out")" = 1 ]; ck "D9 면제 사유 ≥10자 → 착지 + WARN 1줄" $?

tick D1-D9
finish
