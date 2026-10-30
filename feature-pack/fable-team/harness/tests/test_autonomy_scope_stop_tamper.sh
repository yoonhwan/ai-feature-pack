#!/usr/bin/env bash
# test_autonomy_scope_stop_tamper.sh — 범위 승인 시험 3/4: check-revert · scope-stop · 위변조 판정 (r1197 · 옛 test_autonomy_scope.sh 135~175행 그대로)
# 격리·공용 준비 = lib/autonomy_scope_setup.sh · 다른 세 파일(grant · approve_limits · code_hook)과 상태를 나누지 않는다(구역마다 fresh).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

# check-revert(r298b) — 분류 «전» 첫 단계: rc 4 = 정지 + REJECT · rc 1 = REJECT · rc 0 = 진행
fresh; grant --for 10h --max 5 --classes docs >/dev/null; export STUB_ARGS_LOG="$T/stub-args.log"; : > "$STUB_ARGS_LOG"
run a scope-approve "$(sha 61)"; [ $rc = 0 ]; ck "check-revert rc 0 → 진행(SCOPE-OK)" $?
[ "$(head -1 "$STUB_ARGS_LOG")" = "check-revert --repo $T --remote origin --target main --scope S1" ] && [[ "$(sed -n 2p "$STUB_ARGS_LOG")" == "classify $(sha 61) --repo $T --remote origin --target main --scope S1 --ddl-records "*/scope-ddl-record.tsv ]]; ck "check-revert 가 classify «전» 에 · 인자(--repo ROOT --remote origin --target main --scope S1)" $?
n0="$(lines)"; ls "$AP" > "$T/ap.before"
STUB_REVERT_RC=4 STUB_REVERT_OUT="REVERTED $(sha 61) by $(sha 99)" run a scope-approve "$(sha 62)"
[ $rc = 2 ] && has "정지: REVERTED $(sha 61) by $(sha 99)"; ck "check-revert rc 4 → REJECT + 사유 그대로" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q "^scope-stop S1 [0-9]* REVERTED $(sha 61) by $(sha 99)$" "$LOG"; ck "rc 4 → scope_write_stop(log + .stopped)" $?
[ "$(lines)" = "$((n0 + 1))" ] && ! grep -q "$(sha 62)" "$LOG" && [ ! -e "$AP/$(sha 62)" ] && [ "$(ls "$AP")" = "$(cat "$T/ap.before")" ]; ck "rc 4 쓰기 = stop 1줄뿐(scope-use·승인 0)" $?
[ "$(a mode)" = on ]; ck "REVERTED stop 줄도 위변조 아님" $?
run a scope-status; has '^\[범위 승인 S1 정지: REVERTED '; ck "REVERTED 뒤 status 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; n0="$(lines)"
STUB_REVERT_RC=1 STUB_REVERT_OUT="git 오류" run a scope-approve "$(sha 63)"; [ $rc = 2 ] && has '되돌림 감지 실패 rc=1: git 오류'; ck "check-revert rc 1 → REJECT(닫힌 쪽)" $?
[ "$(lines)" = "$n0" ] && [ ! -e "$S/autonomy-scope/S1.stopped" ] && [ ! -d "$AP" ]; ck "rc 1 → 쓰기 0 · 정지 아님" $?
unset STUB_ARGS_LOG

# ===== scope-stop =====
fresh; grant --for 10h --max 5 --classes docs >/dev/null
run a scope-stop S1 $'탭\t개행\n포함 사유'; [ $rc = 0 ] && has '^SCOPE-STOPPED S1: 탭 개행 포함 사유$'; ck "scope-stop 사유의 탭·개행은 공백으로" $?
[ "$(a mode)" = on ]; ck "stop 줄도 위변조 아님" $?
run a scope-approve "$(sha 41)"; [ $rc = 2 ] && has '정지: 탭 개행 포함 사유'; ck "scope-stop 뒤 scope-approve REJECT" $?
run a scope-stop S1 again; [ $rc = 0 ] && has '이미 정지'; ck "scope-stop 멱등" $?
run a scope-stop S9 x; [ $rc = 2 ]; ck "없는 S → REJECT" $?
run a scope-stop S1 ""; [ $rc = 2 ]; ck "사유 없음 → REJECT" $?
grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 42)"; [ $rc = 0 ]; ck "새 approve-scope(S2) 로만 재개" $?

# ===== 위변조 판정 =====
fresh; grant --for 10h --max 5 --classes docs >/dev/null; printf 'scope-use S1 notasha docs 1\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "scope-use 꼴 틀림 → tamper" $?
fresh; printf 'approve-scope S1 A1 1 until=2 max=3 daily=1 classes=foo\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "classes=foo 줄 → tamper (꼴 밖)" $?
fresh; printf 'approve-scope S1 A1 1 until=2 max=3 daily=1 classes=code codemax=x\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "codemax=x 줄 → tamper (꼴 밖)" $?
fresh; printf 'scope-use S1 %s foo 1\n' "$(sha 1)" >> "$LOG"
[ "$(a mode)" = tamper ]; ck "scope-use 종류 foo → tamper" $?
fresh; printf 'scope-stop S1 1 \n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "사유 빈 scope-stop 줄 → tamper" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 51)"; printf 'junk line\n' >> "$LOG"
run a scope-approve "$(sha 52)"; [ $rc = 2 ] && has '위변조'; ck "위변조 상태 scope-approve REJECT" $?
run a scope-status; has '^\[범위 승인 S1 정지: 위변조'; ck "위변조 status 정지 표시" $?
run a scope-status; rm -rf "$S"; mkdir -p "$S"; run a scope-status; has '^\[범위 승인 없음\]$'; ck "status 승인 없음 꼴" $?

echo "fail=$fail"; [ "$fail" = 0 ]
