#!/usr/bin/env bash
# test_autonomy_scope_grant.sh — 범위 승인 시험 1/4: bash -n·kit cmp · approve-scope · scope-approve (r1197 · 옛 test_autonomy_scope.sh 43~99행 그대로)
# 격리·공용 준비 = lib/autonomy_scope_setup.sh · 다른 세 파일(approve_limits · stop_tamper · code_hook)과 상태를 나누지 않는다(구역마다 fresh).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

for f in ft-autonomy.sh ft-autonomy-scope.sh ft-autonomy-scope-code.sh; do bash -n "$BIN/$f" 2>/dev/null; ck "bash -n $f" $?; done
python3 -m py_compile "$BIN/autonomy_scope_post.py" 2>/dev/null; ck "py_compile autonomy_scope_post.py" $?
MIRB="$ROOT/harness/kit/fable-team/bin"
cmp -s "$BIN/ft-autonomy.sh" "$MIRB/ft-autonomy.sh" && cmp -s "$BIN/ft-autonomy-scope.sh" "$MIRB/ft-autonomy-scope.sh" && cmp -s "$BIN/ft-autonomy-scope-code.sh" "$MIRB/ft-autonomy-scope-code.sh" && cmp -s "$BIN/autonomy_scope_post.py" "$MIRB/autonomy_scope_post.py"; ck "설치 미러 cmp0 (bin 네 파일)" $?

# ===== approve-scope =====
rm -rf "$S"; mkdir -p "$S"
grant --for 10h --max 5 --classes docs; [ $rc = 2 ] && has 'ON 이 아님'; ck "approve-scope OFF → REJECT rc 2" $?
fresh
grant --for 10h --max 5 --classes docs,code; [ $rc = 2 ] && has '--code-max 1~max\(5\) 필수\(받은 값: 없음\)'; ck "classes 에 code · --code-max 없음 → REJECT (R411)" $?
grant --for 10h --max 5 --classes code --code-max 0; [ $rc = 2 ] && has '--code-max 1~max'; ck "--code-max 0 → REJECT" $?
grant --for 10h --max 5 --classes code --code-max 6; [ $rc = 2 ] && has '--code-max 1~max'; ck "--code-max > max → REJECT" $?
grant --for 10h --max 5 --classes docs --code-max 2; [ $rc = 2 ] && has 'code 가 있을 때만'; ck "code 없는데 --code-max → REJECT" $?
grant --for 73h --max 5 --classes docs; [ $rc = 2 ]; ck "--for 73h → REJECT" $?
grant --for 0h --max 5 --classes docs; [ $rc = 2 ]; ck "--for 0h → REJECT" $?
grant --for 10 --max 5 --classes docs; [ $rc = 2 ]; ck "--for 단위 없음 → REJECT" $?
grant --for 10h --max 101 --classes docs; [ $rc = 2 ] && has '--max 는 1~100\(받은 값: 101\)'; ck "ⓑ --max 101 → REJECT rc 2 «1~100» (r908)" $?
grant --for 10h --max 100 --daily 101 --classes docs; [ $rc = 2 ] && has '--daily 는 1~max\(100\)'; ck "ⓑ --max 100 --daily 101 → REJECT (r908)" $?
grant --for 10h --max 100 --classes code --code-max 101; [ $rc = 2 ] && has '--code-max 1~max\(100\)'; ck "ⓑ --max 100 --code-max 101 → REJECT (r908)" $?
grant --for 10h --max 0 --classes docs; [ $rc = 2 ]; ck "--max 0 → REJECT" $?
grant --for 10h --max 5 --daily 6 --classes docs; [ $rc = 2 ]; ck "--daily > max → REJECT" $?
grant --for 10h --max 5 --classes docs,foo; [ $rc = 2 ]; ck "모르는 종류 → REJECT" $?
grant --for 10h --max 5 --classes docs,docs; [ $rc = 2 ]; ck "종류 중복 → REJECT" $?
grant --for 10h --max 5 --classes docs,,ff; [ $rc = 2 ]; ck "빈 종류 → REJECT" $?
grant --for 10h --classes docs; [ $rc = 2 ]; ck "--max 없음 → REJECT" $?
[ "$(lines)" = 1 ]; ck "REJECT 전부 log 쓰기 0 (모드 줄 1줄만)" $?
grant --for 10h --max 5 --daily 2 --classes docs,ff,revert
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=5 daily=2 classes=docs,ff,revert$'; ck "정상 grant → SCOPE-GRANTED S1" $?
grep -qxF "approve-scope S1 A1 $T0 until=$((T0+36000)) max=5 daily=2 classes=docs,ff,revert" "$LOG"; ck "log 에 approve-scope 줄 꼴" $?
[ "$(a mode)" = on ]; ck "정상 범위 줄은 위변조 아님 (mode=on)" $?
grant --for 5h --max 3 --classes docs; [ $rc = 0 ] && has '^SCOPE-GRANTED S2 .* max=3 daily=3 classes=docs$'; ck "두 번째 grant = S2 · daily 기본 min(10,max)" $?
run a scope-status; has '^\[범위 승인 S2 · A1 · ~[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}까지 · 0/3 · 오늘 0/3 · docs\]$'; ck "앞 grant 자동 대체 — status 는 S2" $?
fresh; grant --for 10h --max 100 --classes docs; [ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=100 daily=10 classes=docs$'; ck "ⓐ --max 100 → 통과 · GR 줄 max=100 (r908)" $?
fresh; grant --for 10h --max 100 --daily 100 --classes docs; [ $rc = 0 ] && has ' max=100 daily=100 classes=docs$'; ck "ⓐ --daily 100 → 통과 (r908)" $?
fresh; grant --for 10h --max 100 --classes code --code-max 100; [ $rc = 0 ] && grep -q ' max=100 daily=10 classes=code codemax=100' "$LOG"; ck "ⓐ --code-max 100 → 통과 · log codemax=100 (r908)" $?
# r908 r2 — 산술 «전» 자릿수 거름(DA⑥ r1): 긴 수는 bash 산술 넘침으로 100 이 되어 상한을 통과했다
fresh; grant --for 10h --max 18446744073709551716 --classes docs; [ $rc = 2 ] && has '--max 는 1~100\(받은 값: 18446744073709551716\)'; ck "ⓓ --max 18446744073709551716 → REJECT rc 2 (넘침 불가 · r908 r2)" $?
fresh; grant --for 10h --max 100 --daily 18446744073709551716 --classes docs; [ $rc = 2 ] && has '--daily 는 1~max\(100\)'; ck "ⓓ --daily 18446744073709551716 → REJECT (r908 r2)" $?
fresh; grant --for 10h --max 100 --classes code --code-max 18446744073709551716; [ $rc = 2 ] && has '--code-max 1~max\(100\)'; ck "ⓓ --code-max 18446744073709551716 → REJECT (r908 r2)" $?
fresh; grant --for 10h --max 0100 --classes docs; [ $rc = 0 ] && has ' max=100 daily=10 classes=docs$'; ck "ⓓ --max 0100 → 통과(100 · 앞자리 0 허용)" $?
fresh; grant --for 10h --max 1000 --classes docs; [ $rc = 2 ] && has '--max 는 1~100\(받은 값: 1000\)'; ck "ⓓ --max 1000(네 자리) → REJECT (r908 r2)" $?

# ===== scope-approve =====
fresh; grant --for 10h --max 5 --daily 3 --classes docs,ff,revert >/dev/null
run a scope-approve "$(sha 1)" --pr 7
[ $rc = 0 ] && has "^SCOPE-OK $(sha 1) class=docs used=1/5 today=1/3$"; ck "범위 안 → SCOPE-OK" $?
[ "$(cat "$AP/$(sha 1)")" = "approve-merge $(sha 1) A1 $T0" ] && grep -qxF "$(cat "$AP/$(sha 1)")" "$LOG"; ck "승인 파일 1줄 == log 한 줄(기존 형식 · 병합 가드 결속)" $?
grep -qxF "scope-use S1 $(sha 1) docs $T0" "$LOG"; ck "log 에 scope-use 줄" $?
printf '%s\t%s\t7\tdocs\t\t\t\n' "$T0" "$(sha 1)" | cmp -s - "$S/autonomy-scope/S1.ledger.tsv"; ck "원장 1행(시각·sha·PR·종류·빈칸 3)" $?
[ "$(awk -F'\t' 'END{print NF}' "$S/autonomy-scope/S1.ledger.tsv")" = 7 ] && [ "$(awk -F'\t' '{print $6}' "$S/autonomy-scope/S1.ledger.tsv")" = "" ]; ck "원장 7칸(시각·sha·PR·종류·판정문·착지 sha·되돌림) · 6번째 = 착지 sha 빈칸 (r298b LEDGER_LANDED_COL)" $?
[ "$(a mode)" = on ]; ck "scope-use·approve-merge 줄 뒤에도 mode=on" $?
n0="$(lines)"; run a scope-approve "$(sha 1)"; [ $rc = 0 ] && has '^SCOPE-NOOP .* used=1/5'; ck "같은 sha 두 번 → SCOPE-NOOP" $?
[ "$(lines)" = "$n0" ]; ck "NOOP 은 쓰기 0 (건수 불변)" $?
run a scope-approve "$(sha 2)"; run a scope-approve "$(sha 3)"; [ $rc = 0 ]; ck "daily 3 안의 3건째 OK" $?
run a scope-approve "$(sha 4)"; [ $rc = 2 ] && has '하루 건수 도달'; ck "daily 도달 → REJECT" $?
[ ! -e "$AP/$(sha 4)" ] && ! grep -q "$(sha 4)" "$LOG"; ck "daily REJECT 쓰기 0" $?
run a scope-status; ! has '정지' && has '^\[범위 승인 S1 · A1 .* 3/5 · 오늘 3/3 · docs,ff,revert\]$'; ck "daily 도달은 정지 아님(내일 풀림)" $?

echo "fail=$fail"; [ "$fail" = 0 ]
