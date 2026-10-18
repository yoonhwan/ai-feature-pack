#!/usr/bin/env bash
# test_tmp_trap_lint.sh — ft-tmp-trap-lint.sh (R246): 셸의 `mktemp -d` 는 같은 파일 `trap … rm -rf … $변수` 가 있어야 한다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="$REPO/scripts/fable-team-bin/ft-tmp-trap-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-tmp-trap-lint.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mk() { printf '%s\n' "$2" > "$T/$1"; }
lint() { OUT="$(bash "$SUT" "$@" 2>&1)"; RC=$?; }

mk good.sh   $'#!/bin/bash\nD="$(mktemp -d)"; trap \'rm -rf "$D"\' EXIT\necho hi'
mk brace.sh  $'#!/bin/bash\nD=$(mktemp -d /tmp/x.XXXX)\ntrap "rm -rf ${D}" EXIT'
mk notrap.sh $'#!/bin/bash\nset -e\nD="$(mktemp -d)"\necho hi'
mk other.sh  $'#!/bin/bash\nA="$(mktemp -d)"\nB="$(mktemp -d)"\ntrap \'rm -rf "$A"\' EXIT'
mk novar.sh  $'#!/bin/bash\ncd "$(mktemp -d)" && echo hi'
mk file.sh   $'#!/bin/bash\nF="$(mktemp)"\necho hi > "$F"'
mk cmt.sh    $'#!/bin/bash\n# 예: D="$(mktemp -d)" 는 trap 이 필요하다\necho hi'
mk trapnorm.sh $'#!/bin/bash\nD="$(mktemp -d)"\ntrap \'echo bye\' EXIT'

lint "$T/good.sh";  [ $RC = 0 ] && ok "ⓐ trap rm -rf \$D 있으면 통과" || bad "ⓐ rc=$RC $OUT"
lint "$T/brace.sh"; [ $RC = 0 ] && ok "ⓑ \${D} 형태도 통과" || bad "ⓑ rc=$RC $OUT"
lint "$T/notrap.sh"; { [ $RC = 1 ] && echo "$OUT" | grep -q "REJECT .*notrap.sh:3"; } && ok "ⓒ trap 없음 → REJECT 파일:줄" || bad "ⓒ rc=$RC $OUT"
lint "$T/other.sh"; { [ $RC = 1 ] && echo "$OUT" | grep -q "other.sh:3" && ! echo "$OUT" | grep -q "other.sh:2"; } && ok "ⓓ trap 이 다른 변수(\$A)면 \$B 줄만 REJECT" || bad "ⓓ rc=$RC $OUT"
lint "$T/novar.sh"; { [ $RC = 1 ] && echo "$OUT" | grep -q "novar.sh:2"; } && ok "ⓔ 변수 없는 mktemp -d → REJECT" || bad "ⓔ rc=$RC $OUT"
lint "$T/file.sh";  [ $RC = 0 ] && ok "ⓕ mktemp(파일)은 대상 아님" || bad "ⓕ rc=$RC $OUT"
lint "$T/cmt.sh";   [ $RC = 0 ] && ok "ⓖ 주석 속 mktemp -d 무시" || bad "ⓖ rc=$RC $OUT"
lint "$T/trapnorm.sh"; [ $RC = 1 ] && ok "ⓗ trap 이 rm -rf 가 아니면 REJECT" || bad "ⓗ rc=$RC $OUT"
lint --all --root "$T"; { [ $RC = 0 ] && echo "$OUT" | tail -1 | grep -q '위반 4'; } && ok "ⓘ --all 은 목록 + 개수만 · rc0" || bad "ⓘ rc=$RC $(echo "$OUT" | tail -2)"
lint "$T/nope.sh";  [ $RC = 2 ] && ok "ⓙ 없는 파일 rc2" || bad "ⓙ rc=$RC"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
