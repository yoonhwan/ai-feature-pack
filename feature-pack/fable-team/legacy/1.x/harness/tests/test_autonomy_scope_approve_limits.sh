#!/usr/bin/env bash
# test_autonomy_scope_approve_limits.sh — 범위 승인 시험 2/4: max 자동 정지 · until·사건 번호 정지 · 분류기 (r1197 · 옛 test_autonomy_scope.sh 101~133행 그대로)
# 이름: test_autonomy_scope_classify.sh 는 분류기 도구 시험으로 따로 있다(겹치지 않게 approve_limits).
# 격리·공용 준비 = lib/autonomy_scope_setup.sh · 다른 세 파일(grant · stop_tamper · code_hook)과 상태를 나누지 않는다(구역마다 fresh).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

# max · 자동 정지 · revert 건수 0
fresh; grant --for 10h --max 2 --daily 2 --classes docs,ff,revert >/dev/null
STUB_OUT="CLASS revert"; export STUB_OUT
run a scope-approve "$(sha 11)"; run a scope-approve "$(sha 12)"; [ $rc = 0 ] && has 'used=0/2'; ck "revert 는 건수 0 (used=0/2)" $?
STUB_OUT="CLASS docs"
run a scope-approve "$(sha 13)"; run a scope-approve "$(sha 14)"; [ $rc = 0 ] && has 'used=2/2'; ck "docs 2건 = max" $?
run a scope-approve "$(sha 15)"; [ $rc = 2 ] && has '건수 도달'; ck "max 도달 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q '^scope-stop S1 ' "$LOG"; ck "max 도달 → 자동 정지(log + .stopped)" $?
STUB_OUT="CLASS revert"; run a scope-approve "$(sha 16)"; [ $rc = 2 ] && has '정지'; ck "정지 뒤 revert 도 REJECT" $?
run a scope-status; has '^\[범위 승인 S1 정지: 건수 도달\(2/2\)\]$'; ck "status 정지 꼴" $?
STUB_OUT="CLASS docs"

# until 지남 · 사건 번호 바뀜
fresh; grant --for 1h --max 5 --classes docs >/dev/null
NOW=$((T0+3600)); run a scope-approve "$(sha 21)"; [ $rc = 2 ] && has '기간 끝 도달'; ck "until 지남 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ]; ck "until 지남 → 자동 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null
a off >/dev/null; a on >/dev/null 2>&1; run a scope-approve "$(sha 22)"; [ $rc = 2 ] && has '사건 번호 바뀜\(A1→A2\)'; ck "OFF→ON 다시 켬(A2) → 옛 S1 REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ]; ck "사건 번호 바뀜 → 자동 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; a off >/dev/null
run a scope-approve "$(sha 23)"; [ $rc = 2 ] && has '자율 모드 OFF'; ck "자율 OFF → REJECT" $?
[ ! -e "$AP/$(sha 23)" ]; ck "OFF REJECT 쓰기 0" $?

# 분류기
fresh; grant --for 10h --max 5 --classes docs,ff >/dev/null; n0="$(lines)"
STUB_OUT="FORBID code-touch" STUB_RC=2 run a scope-approve "$(sha 31)"; [ $rc = 2 ] && has '분류기 거절 rc=2: FORBID code-touch'; ck "분류기 FORBID → REJECT(사유 그대로)" $?
FT_SCOPE_CLASSIFY=/nonexistent run a scope-approve "$(sha 32)"; [ $rc = 2 ] && has '분류기 없음'; ck "분류기 없음 → REJECT" $?
STUB_OUT="garbage" run a scope-approve "$(sha 33)"; [ $rc = 2 ] && has '꼴 틀림'; ck "분류기 출력 꼴 틀림 → REJECT" $?
STUB_OUT="CLASS code" run a scope-approve "$(sha 34)"; [ $rc = 2 ] && has '범위\(docs,ff\) 밖'; ck "종류 code → 범위 밖 REJECT" $?
STUB_OUT="CLASS revert" run a scope-approve "$(sha 35)"; [ $rc = 2 ] && has '범위\(docs,ff\) 밖'; ck "grant 에 없는 종류(revert) → REJECT" $?
[ "$(lines)" = "$n0" ] && [ ! -d "$AP" ]; ck "분류기 REJECT 5종 전부 쓰기 0" $?
run a scope-approve "xyz"; [ $rc = 2 ]; ck "sha 형식 틀림 → REJECT" $?
rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; run a scope-approve "$(sha 36)"; [ $rc = 2 ] && has '활성 범위 승인 없음'; ck "grant 없음 → REJECT" $?

echo "fail=$fail"; [ "$fail" = 0 ]
