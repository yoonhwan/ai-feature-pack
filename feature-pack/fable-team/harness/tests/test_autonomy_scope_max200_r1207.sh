#!/usr/bin/env bash
# test_autonomy_scope_max200_r1207.sh — approve-scope --max 상한 100→200 (r1207 · 오빠 판정 2914 · h567 값) 반례 R1~R5 + bin·kit cmp
# 격리: test_autonomy_scope.sh 와 같은 꼴(임시 FT_ROOT·STATE · FT_NOW 고정 · 가짜 분류기·가짜 슬랙) — 실 범위·실 슬랙 0 · 자기 재호출은 real_state_guard(RSG_ACTIVE) 한 번뿐.
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
fresh() { rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; }   # A1 ON · 모드 줄 1줄
lines() { wc -l < "$LOG" | tr -d ' '; }
grant() { run a approve-scope "$@"; }

# ⓐ R1 — h567 값 그대로
fresh; grant --for 48h --max 200 --daily 100 --classes docs,ff,revert,code --code-max 66 --repos byz,pack
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=200 daily=100 classes=docs,ff,revert,code' \
  && grep -q ' max=200 daily=100 classes=docs,ff,revert,code codemax=66 repos=byz,pack' "$LOG"
ck "ⓐ R1 --max 200 --daily 100 --code-max 66 --repos byz,pack → SCOPE-GRANTED max=200" $?
# ⓐ R4 — 앞자리 0
fresh; grant --for 10h --max 0200 --classes docs; [ $rc = 0 ] && has ' max=200 daily=10 classes=docs$'; ck "ⓐ R4 --max 0200 → 통과(200)" $?
# ⓑ R2 — 201 거절 · 쓰기 0
fresh; grant --for 10h --max 201 --classes docs; [ $rc = 2 ] && has '^SCOPE-REJECT --max 는 1~200\(받은 값: 201\)' && [ "$(lines)" = 1 ]; ck "ⓑ R2 --max 201 → REJECT rc 2 «1~200» · log 쓰기 0" $?
# ⓒ R3 — 긴 수(넘침으로 200 이하가 되지 않음) · 쓰기 0
fresh; grant --for 10h --max 18446744073709551716 --classes docs; [ $rc = 2 ] && has '--max 는 1~200' && [ "$(lines)" = 1 ]; ck "ⓒ R3 --max 18446744073709551716 → REJECT rc 2 · log 쓰기 0" $?
# ⓓ R5 — daily 는 max 를 따라감
fresh; grant --for 10h --max 200 --daily 201 --classes docs; [ $rc = 2 ] && has '--daily 는 1~max\(200\)'; ck "ⓓ R5 --max 200 --daily 201 → REJECT «1~max(200)»" $?
# ⓔ bin·kit 같은 내용
cmp -s "$BIN/ft-autonomy-scope.sh" "$MIRB/ft-autonomy-scope.sh"; ck "ⓔ bin·kit ft-autonomy-scope.sh cmp0" $?

echo "---- fail=$fail"
[ "$fail" = 0 ]
