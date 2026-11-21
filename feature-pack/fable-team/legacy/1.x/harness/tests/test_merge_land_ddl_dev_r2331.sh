#!/usr/bin/env bash
# test_merge_land_ddl_dev_r2331.sh — r2331: 착지 DDL 검사가 두 자리 이상 번호 파일(91~99 · 100 이상)도 DDL 로 세고, -rollback·-fixture 꼬리만 뺀다
#   반례 ①~⑩ + ⑦b + 변이 M1~M5 · 기준판 Red = ① ② · 회귀(r1347·r1347b·r1347c)는 이 파일 안에서 돌리지 않고 카드 시험 줄에서 따로
#   틀 = _merge_ddl_fixture.sh · 실행 비트 0(100644) — `bash <이 파일>` · 고정 sleep 0 · 실 gh·실 DB·네트워크 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
BASE="$(mutf base ft-merge-land.sh "$GATE" '')"                                                                        # 기준판 = 관문 호출 줄만 뺀 land
M1="$(mutf m1 ft-merge-lib.sh '[0-9]{2,}' '[0-8][0-9]')"                                                               # 거름을 00~89 로 되돌림
M2="$(mutf m2 ft-merge-lib.sh '[0-9]{2,}' '[0-9]{2}')"                                                                  # 세 자리 번호 빠짐
M3="$(mutf m3 ft-merge-lib.sh ' && [[ "$p" != *-fixture.sql ]]' '')"                                                     # -fixture 거름 지움
M4="$(mutf m4 ft-merge-lib.sh 're.escape(n)' 're.escape(n.split("-")[0])+r"(?:-[^ ]*)"')"                                # 이름 대조 → 번호 대조
M5="$(mutf m5 ft-merge-lib.sh 're.escape(n)' 'r"[^ ]+"')"                                                               # 아무 증거 1줄이면 전부
pretest; tick 사전
ran 5 0; ran 77 0   # h5 · h77 = rc=0 (틀 기본값 h145=rc0 · h146=rc1)

# ===== ① 94-x.sql(A) + 코드 · 증거 0 → REJECT · 기준판은 착지(Red) =====
mkpr 31 d1 "$SQ/94-a1.sql=select 1;" "scripts/a.py=print(1)"; A="$PRSHA"; pre
land "$LAND" 31 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 증거 없음 — 94-a1.sql (코드 1개 동반)"* ]]; ck "① 94 + 코드 · 증거 0 → REJECT «증거 없음 — 94-a1.sql» · 착지 0" $?
cnt "$BASE/ft-merge-land.sh" 31 "$A"; landed 31; ck "기준판 ① → 증거 없이 착지(Red)" $?
cnt "$M1/ft-merge-land.sh" 31 "$A"; landed 31; ck "변이 M1([0-8][0-9] 되돌림) → ① FAIL 재현" $?
tick ①

# ===== ② 102-x.sql(A) + 코드 · 증거 0 → REJECT(세 자리) =====
mkpr 32 d2 "$SQ/102-a2.sql=select 2;" "scripts/b.py=print(2)"; A="$PRSHA"; pre
land "$LAND" 32 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 증거 없음 — 102-a2.sql"* ]]; ck "② 102 + 코드 · 증거 0 → REJECT(세 자리 번호)" $?
cnt "$BASE/ft-merge-land.sh" 32 "$A"; landed 32; ck "기준판 ② → 착지(Red)" $?
cnt "$M2/ft-merge-land.sh" 32 "$A"; landed 32; ck "변이 M2({2,} → 두 자리 고정) → ② FAIL 재현" $?

# ===== ③ 87-x.sql + 코드 · 증거 0 → REJECT(지금과 같음) =====
mkpr 33 d3 "$SQ/87-a3.sql=select 3;" "scripts/c.py=print(3)"; A="$PRSHA"; pre
land "$LAND" 33 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 증거 없음 — 87-a3.sql"* ]]; ck "③ 87 + 코드 · 증거 0 → REJECT(기존과 같음)" $?
tick ②-③

# ===== ④ 94-x.sql + 코드 · 증거 줄 «h77 rc=0» + h77.ran rc=0 → 통과 =====
mkpr 34 d4 "$SQ/94-a4.sql=select 4;" "scripts/d.py=print(4)"; A="$PRSHA"; setc 34 "DDL dev 적용: 94-a4.sql · h77 rc=0"; pre
land "$LAND" 34 --approve-sha "$A"; landed 34 && [ "$(oshow $SQ/94-a4.sql)" = "select 4;" ]; ck "④ 94 + 증거 줄(h77 rc=0) → 착지" $?

# ===== ⑤ 90-t17-fixture.sql(M) + 코드 · 증거 0 → 통과(fixture = DDL 0) =====
mkpr 35 d5 "$SQ/90-t17-fixture.sql=select 5;" "scripts/e.py=print(5)"; A="$PRSHA"; pre
cnt "$M3/ft-merge-land.sh" 35 "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 90-t17-fixture.sql"* ]]; ck "변이 M3(-fixture 거름 지움) → ⑤ FAIL 재현" $?
land "$LAND" 35 --approve-sha "$A"; landed 35; ck "⑤ 90-t17-fixture.sql + 코드 · 증거 0 → 착지(fixture 제외)" $?
tick ④-⑤

# ===== ⑥ 94-x.sql + 94-x-rollback.sql + 코드 · 94 증거만 → 통과(rollback = DDL 0) =====
mkpr 36 d6 "$SQ/94-a6.sql=select 6;" "$SQ/94-a6-rollback.sql=drop 6;" "scripts/f.py=print(6)"; A="$PRSHA"; setc 36 "DDL dev 적용: 94-a6.sql · h5 rc=0"; pre
land "$LAND" 36 --approve-sha "$A"; landed 36; ck "⑥ rollback 은 대상 밖 → 착지" $?

# ===== ⑦ 93-a.sql + 93-a-gate.sql + 코드 · «93-a.sql» 1줄만 → REJECT(파일마다 증거) =====
mkpr 37 d7 "$SQ/93-a7.sql=select 7;" "$SQ/93-a7-gate.sql=alter 7;" "scripts/g.py=print(7)"; A="$PRSHA"; setc 37 "DDL dev 적용: 93-a7.sql · h5 rc=0"; pre
land "$LAND" 37 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"REJECT DDL dev 적용 증거 없음 — 93-a7-gate.sql"* ]]; ck "⑦ 같은 번호 짝 파일 증거 0 → REJECT «93-a7-gate.sql»(번호 묶음 인정 0)" $?
cnt "$M4/ft-merge-land.sh" 37 "$A"; landed 37; ck "변이 M4(이름 → 번호 대조) → ⑦ FAIL 재현" $?

# ===== ⑦b 같은 PR 두 줄(같은 h5) → 통과 =====
setc 37 "DDL dev 적용: 93-a7.sql · h5 rc=0" "DDL dev 적용: 93-a7-gate.sql · h5 rc=0"
land "$LAND" 37 --approve-sha "$A"; landed 37; ck "⑦b 파일마다 1줄(같은 h5) → 착지" $?
tick ⑥-⑦b

# ===== ⑧ 93-a.sql + 94-b.sql + 코드 · 93 증거만 → REJECT «94-b.sql»(다른 번호 인정 0) =====
mkpr 38 d8 "$SQ/93-a8.sql=select 8;" "$SQ/94-b8.sql=select 88;" "scripts/h.py=print(8)"; A="$PRSHA"; setc 38 "DDL dev 적용: 93-a8.sql · h5 rc=0"; pre
land "$LAND" 38 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 94-b8.sql"* ]]; ck "⑧ 다른 번호 DDL 증거 0 → REJECT «94-b8.sql»" $?
cnt "$M5/ft-merge-land.sh" 38 "$A"; landed 38; ck "변이 M5(아무 증거 1줄이면 전부) → ⑧ FAIL 재현" $?

# ===== ⑨ 94 만(코드 0) · 94 + design/·docs/·*.md 만 → 조회 0 통과 =====
mkpr 39 d9a "$SQ/94-a9.sql=select 9;"; A="$PRSHA"; pre
land "$LAND" 39 --approve-sha "$A"; landed 39 && ! grep -q '^COMMENTS' "$STUB_LOG"; ck "⑨ 코드 0 → 착지 · 코멘트 조회 0" $?
mkpr 40 d9b "$SQ/94-a9b.sql=select 99;" "design/x/d9.md=doc" "docs/y/d9.md=doc" "notes9.md=doc"; A="$PRSHA"; pre
land "$LAND" 40 --approve-sha "$A"; landed 40 && ! grep -q '^COMMENTS' "$STUB_LOG"; ck "⑨ design/·docs/·*.md 만 동반 → 착지 · 조회 0" $?
tick ⑧-⑨

# ===== ⑩ 9-x.sql(한 자리) · sub/94-x.sql(하위 폴더) → DDL 0(거름 밖 · 지금과 같음) =====
mkpr 41 d10 "$SQ/9-a10.sql=select 10;" "$SQ/sub/94-a10.sql=select 101;" "scripts/i.py=print(10)"; A="$PRSHA"; pre
land "$LAND" 41 --approve-sha "$A"; landed 41 && ! grep -q '^COMMENTS' "$STUB_LOG"; ck "⑩ 한 자리·하위 폴더는 DDL 0 → 착지 · 조회 0" $?
tick ⑩
finish
