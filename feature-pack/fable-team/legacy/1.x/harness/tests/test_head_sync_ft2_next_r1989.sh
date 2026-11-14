#!/usr/bin/env bash
# test_head_sync_ft2_next_r1989.sh — r1989: --apply 최신화함 성공 끝줄 = «ft2 나노면 다음: ft2_result» · 표 모드·REJECT·이미 최신엔 0 · kit 사본 같은 바이트
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../../harness/bin"; SYNC="$BIN/ft-head-sync.sh"; NEXT="ft2 나노면 다음: ft2_result"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400}"; fail=$((fail+1)); fi; }
syn() { local d="$1"; shift; out="$( ( cd "$d" && bash "$SYNC" "$@" ) 2>&1 )"; rc=$?; }
mkrepo "$T"; git -C "$W" worktree add -q -b nano/a "$T/wt-a" "$M0"; echo m1 > "$W/m.txt"; cm "$W" "main moves"; git -C "$W" push -q origin main
syn "$T" --repo "$W"; [ "$rc" = 0 ] && [[ "$out" != *"$NEXT"* ]]; ck "표 모드 = 그 줄 0" $?
syn "$T" --apply --repo "$W"; [ "$rc" = 2 ] && [[ "$out" != *"$NEXT"* ]]; ck "REJECT(대상 밖 자리) = 그 줄 0" $?
syn "$T/wt-a" --apply --repo "$W"; [ "$rc" = 0 ] && [[ "$out" == *최신화함* ]] && [ "$(printf '%s\n' "$out" | tail -1)" = "$NEXT (다음 일 전에 1회)" ]; ck "--apply 최신화함 = 끝줄 다음 ft2_result" $?
syn "$T/wt-a" --apply --repo "$W"; [ "$rc" = 0 ] && [[ "$out" != *"$NEXT"* ]]; ck "이미 최신 --apply = 그 줄 0" $?
cmp -s "$SYNC" "$HERE/../kit/fable-team/bin/ft-head-sync.sh"; ck "kit 사본 같은 바이트" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
