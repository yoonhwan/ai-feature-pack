#!/usr/bin/env bash
# test_merge_land_ddl_dev_r1347b.sh — r1347 ②: 짝 시험(시험 1개 70 s 상한이라 셋으로 나눔 · 짝 = r1347 · r1347c)
#   반례 D12~D16(a·b) + 변이 6·7·8·11 · 기준판 = 관문 호출 줄만 뺀 land · D16 은 남은 초를 직접 주는 함수 단위(고정 sleep 0 · 스텁만 느린 응답을 흉내)
#   틀 = _merge_ddl_fixture.sh · 실행 비트 0(100644) — `bash <이 파일>` · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐 · 실 gh·실 DB·네트워크 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/_merge_ddl_fixture.sh"
mkmut base 6 7 8 11
pretest; tick 사전

# ===== D12: DDL 이름 바꿈(→ 새 경로) + 코드 → 새 경로 증거 요구 =====
adv "$SQ/71-old.sql=create 12"; git -C "$W" checkout -q -B d12 origin/main; git -C "$W" mv "$SQ/71-old.sql" "$SQ/72-new.sql"; put shared/c12.py "print(12)"; cm "$W" "pr 12"; pushpr 12 d12; A="$PRSHA"; pre
land "$LAND" 12 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 72-new.sql"* ]]; ck "D12 DDL 이름 바꿈 → 새 경로 72-new.sql 증거 요구 · REJECT" $?
cnt "$BASE/ft-merge-land.sh" 12 "$A"; landed 12; ck "기준판 D12 → 착지" $?
cnt "$M6/ft-merge-land.sh" 12 "$A"; landed 12; ck "변이 6(--no-renames 제거) → D12 FAIL 재현" $?

# ===== D13: DDL 추가 + 코드 이름 바꿈 → 코드 동반 =====
adv "shared/r13.py=print(13)"; git -C "$W" checkout -q -B d13 origin/main; put "$SQ/73-d13.sql" "select 13;"; git -C "$W" mv shared/r13.py shared/r13b.py; cm "$W" "pr 13"; pushpr 13 d13; A="$PRSHA"; pre
land "$LAND" 13 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 73-d13.sql"* ]]; ck "D13 코드 이름 바꿈 = 코드 동반 → REJECT" $?
cnt "$BASE/ft-merge-land.sh" 13 "$A"; landed 13; ck "기준판 D13 → 착지" $?
cnt "$M6/ft-merge-land.sh" 13 "$A"; landed 13; ck "변이 6(--no-renames 제거) → D13 FAIL 재현" $?

# ===== D14: DDL 추가 + 코드 파일 지우기(D)만 → 코드 동반 =====
adv "shared/r14.py=print(14)"; git -C "$W" checkout -q -B d14 origin/main; put "$SQ/74-d14.sql" "select 14;"; git -C "$W" rm -q shared/r14.py; cm "$W" "pr 14"; pushpr 14 d14; A="$PRSHA"; pre
land "$LAND" 14 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 74-d14.sql"* ]]; ck "D14 코드 지우기만 = 코드 동반 → REJECT" $?
cnt "$BASE/ft-merge-land.sh" 14 "$A"; landed 14; ck "기준판 D14 → 착지" $?
cnt "$M7/ft-merge-land.sh" 14 "$A"; landed 14; ck "변이 7(코드 판별 A·M 만) → D14 FAIL 재현" $?

# ===== D15: core.quotePath=true · 한글 이름 DDL + 코드 → DDL 로 판별 =====
git -C "$W" config core.quotePath true
mkpr 15 d15 "$SQ/75-검색.sql=select 15;" "shared/c15.py=print(15)"; A="$PRSHA"; pre
land "$LAND" 15 --approve-sha "$A"; rejected "$PM" && [[ "$out" == *"증거 없음 — 75-검색.sql"* ]]; ck "D15 quotePath=true 한글 DDL → REJECT" $?
cnt "$BASE/ft-merge-land.sh" 15 "$A"; landed 15; ck "기준판 D15 → 착지" $?
cnt "$M8/ft-merge-land.sh" 15 "$A"; landed 15; ck "변이 8(-z 제거) → D15 FAIL 재현" $?
git -C "$W" config --unset core.quotePath
tick D12-D15

# ===== D16a·D16b: 시간 — 함수 단위(남은 초를 직접 준다 · 착지 도구 총 마감 70 s 불변) =====
mkpr 16 d16 "$SQ/76-d16.sql=select 16;" "shared/c16.py=print(16)"; S16="$PRSHA"; M16="$(omain)"; setc 16 "DDL dev 적용: 76-d16.sql · h145 rc=0"
( . "$LIB"; : > "$STUB_LOG"; fm_ddl_dev_gate "$W" "$M16" "$S16" 16 1 b "" "$FT_GH" ) > "$T/o16a" 2>&1; rc=$?; out="$(cat "$T/o16a")"
[ "$rc" = 1 ] && [[ "$out" == *"DDL dev 적용 판정 불가 — 남은 시간 부족"* ]] && ! grep -q '^COMMENTS' "$STUB_LOG"; ck "D16a 남은 초 1 → 조회 0 · 판정 불가 «남은 시간 부족»" $?
t0=$SECONDS; ( . "$LIB"; : > "$STUB_LOG"; STUB_SLOW=6 fm_ddl_dev_gate "$W" "$M16" "$S16" 16 5 b "" "$FT_GH" ) > "$T/o16b" 2>&1; rc=$?; out="$(cat "$T/o16b")"; el=$((SECONDS - t0))
[ "$rc" = 1 ] && [[ "$out" == *"DDL dev 적용 판정 불가 — PR 코멘트 조회 실패"* ]] && [ "$el" -le 6 ]; ck "D16b 남은 5 s · 스텁 6 s 응답 → 시도 상한 4 s 에 끊겨 REJECT · 소요 ${el}s ≤ 6" $?
t0=$SECONDS; ( . "$M11/ft-merge-lib.sh"; : > "$STUB_LOG"; STUB_SLOW=6 fm_ddl_dev_gate "$W" "$M16" "$S16" 16 5 b "" "$FT_GH" ) > "$T/o16m" 2>&1; rc=$?; out="$(cat "$T/o16m")"; el=$((SECONDS - t0))
[ "$rc" = 0 ] && [ "$el" -ge 6 ]; ck "변이 11(고정 7 s) → D16b FAIL 재현(6 s 응답 통과 · 소요 ${el}s > 남은 5 s)" $?
tick D16

finish
