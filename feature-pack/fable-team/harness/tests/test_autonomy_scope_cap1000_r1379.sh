#!/usr/bin/env bash
# test_autonomy_scope_cap1000_r1379.sh — approve-scope 물리 상한 max 1000 · daily 1~max · code-max 1~min(max,500) (r1379 · 오빠 직접 지시) 반례 C1~C9 + bin·kit cmp
# 격리: test_autonomy_scope_max200_r1207.sh 와 같은 꼴(임시 FT_ROOT·STATE · FT_NOW 고정 · 가짜 분류기·가짜 슬랙) — 실 범위·실 슬랙·실 원장 0 · 자기 재호출은 real_state_guard(RSG_ACTIVE) 한 번뿐.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; MIRB="$ROOT/harness/kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; LOG="$S/autonomy.log"; mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000
printf '#!/usr/bin/env bash\necho "CLASS docs"\n' > "$T/stub-classify.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/stub-post.sh"
chmod +x "$T/stub-classify.sh" "$T/stub-post.sh"
export FT_SCOPE_CLASSIFY="$T/stub-classify.sh" FT_SCOPE_SLACK_POST="$T/stub-post.sh"

a() { FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; }
lines() { wc -l < "$LOG" | tr -d ' '; }
grant() { run a approve-scope "$@"; }
ALL=docs,ff,revert,code

# C1 — 오빠 값 500/500/200 은 깎이지 않는다
fresh; grant --for 12h --max 500 --daily 500 --classes $ALL --code-max 200 --repos byz,pack
[ $rc = 0 ] && has '^SCOPE-GRANTED' && grep -q ' max=500 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack' "$LOG"
ck "C1 500/500/200 → SCOPE-GRANTED · 원장 그 값(깎임 0)" $?
# C2 — 물리 상한 1000/1000/500
fresh; grant --for 12h --max 1000 --daily 1000 --classes $ALL --code-max 500 --repos byz,pack
[ $rc = 0 ] && has '^SCOPE-GRANTED' && grep -q ' max=1000 daily=1000 classes=docs,ff,revert,code codemax=500 repos=byz,pack' "$LOG"
ck "C2 1000/1000/500 → SCOPE-GRANTED · 원장 그 값" $?
# C3 — 네 자리 --max 단독
fresh; grant --for 12h --max 1000 --classes docs; [ $rc = 0 ] && grep -q ' max=1000 daily=10 classes=docs$' "$LOG"
ck "C3 --max 1000 단독 → 통과(네 자리 자릿수 거름 통과)" $?
# C4 — 1001 거절 · 쓰기 0
fresh; before="$(lines)"; grant --for 12h --max 1001 --classes docs
[ $rc = 2 ] && has '^SCOPE-REJECT --max 는 1~1000\(받은 값: 1001\)' && [ "$(lines)" = "$before" ]
ck "C4 --max 1001 → REJECT rc 2 «1~1000» · 쓰기 0" $?
# C5 — code-max 501 거절(max 1000 이어도)
fresh; before="$(lines)"; grant --for 12h --max 1000 --classes docs,code --code-max 501
[ $rc = 2 ] && has '^SCOPE-REJECT 종류 code 는 --code-max 1~min\(max,500\)\(받은 값: 501\)' && [ "$(lines)" = "$before" ]
ck "C5 --max 1000 --code-max 501 → REJECT rc 2 «1~min(max,500)» · 쓰기 0" $?
# C6 — code-max 는 max 를 따라간다
fresh; before="$(lines)"; grant --for 12h --max 300 --classes docs,code --code-max 301
[ $rc = 2 ] && has '^SCOPE-REJECT 종류 code 는 --code-max 1~min\(max,500\)' && [ "$(lines)" = "$before" ]
ck "C6 --max 300 --code-max 301 → REJECT · 쓰기 0" $?
fresh; grant --for 12h --max 300 --classes docs,code --code-max 300; [ $rc = 0 ] && grep -q ' max=300 daily=10 classes=docs,code codemax=300' "$LOG"
ck "C6b --max 300 --code-max 300 → 통과(max 까지)" $?
# C7 — 자릿수 거름: 긴 수 · 앞자리 0 · 다섯 자리
fresh; before="$(lines)"; grant --for 12h --max 18446744073709551716 --classes docs
[ $rc = 2 ] && has '--max 는 1~1000\(받은 값: 18446744073709551716\)' && [ "$(lines)" = "$before" ]
ck "C7a 긴 수 18446744073709551716 → REJECT(넘침 통과 0) · 쓰기 0" $?
fresh; grant --for 12h --max 01000 --classes docs; [ $rc = 0 ] && grep -q ' max=1000 daily=10 classes=docs$' "$LOG"
ck "C7b --max 01000 → 1000 통과" $?
fresh; before="$(lines)"; grant --for 12h --max 10000 --classes docs; [ $rc = 2 ] && has '--max 는 1~1000\(받은 값: 10000\)' && [ "$(lines)" = "$before" ]
ck "C7c --max 10000 → REJECT · 쓰기 0" $?
fresh; before="$(lines)"; grant --for 12h --max 1000 --classes docs,code --code-max 18446744073709551716
[ $rc = 2 ] && has '--code-max 1~min\(max,500\)' && [ "$(lines)" = "$before" ]
ck "C7d --code-max 18446744073709551716 → REJECT · 쓰기 0" $?
# C8 — daily 는 max 를 따라간다
fresh; before="$(lines)"; grant --for 12h --max 1000 --daily 1001 --classes docs; [ $rc = 2 ] && has '--daily 는 1~max\(1000\)' && [ "$(lines)" = "$before" ]
ck "C8 --max 1000 --daily 1001 → REJECT «1~max(1000)»" $?
# C9 — bin·kit 같은 내용
cmp -s "$BIN/ft-autonomy-scope.sh" "$MIRB/ft-autonomy-scope.sh"; ck "C9 bin·kit ft-autonomy-scope.sh cmp0" $?

echo "---- fail=$fail"
[ "$fail" = 0 ]
