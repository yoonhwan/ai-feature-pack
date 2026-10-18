#!/usr/bin/env bash
# test_mbox_py_link_import.sh — 라이브 꼴 링크 배치(<root>/.fable-team/comm/mbox.py → <root>/.claude/fable-team/bin/mbox.py · 모듈은 bin 에만)에서
# CLI 왕복 + «comm 폴더를 sys.path 에 넣고 import mbox» 가 둘 다 되고 CANON = <root>/.fable-team/comm 인지 본다(DA r1 Q2 · mbox-py-split-200). 라이브 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; SRC="${MBOX_PY_DIR:-$HERE/../../harness/comm}"
T="$(mktemp -d)"; R="$T/root"; fail=0
ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$R/.fable-team/comm" "$R/.claude/fable-team/bin"; git -C "$R" init -q
cp "$SRC"/mbox*.py "$R/.claude/fable-team/bin/"
ln -s ../../.claude/fable-team/bin/mbox.py "$R/.fable-team/comm/mbox.py"
want="$(cd "$R/.fable-team/comm" && pwd -P)"
out="$(cd "$R" && env -u FT_MBOX_DIR python3 .fable-team/comm/mbox.py send zz#1 me#1 "링크 왕복" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "CLI 링크 send rc0" || bad "CLI 링크 send rc=$rc :: $out"
n="$(cd "$R" && env -u FT_MBOX_DIR python3 .fable-team/comm/mbox.py recv zz#1 2>&1 | grep -c '링크 왕복')"
[ "$n" = 1 ] && ok "CLI 링크 recv 1건" || bad "CLI 링크 recv $n건"
got="$(cd "$T" && env -u FT_MBOX_DIR python3 -c 'import os,sys; sys.path.insert(0, sys.argv[1]); import mbox; print(os.path.realpath(mbox.CANON))' "$R/.fable-team/comm" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$got" = "$want" ] && ok "comm 폴더 import mbox rc0 · CANON = 링크 위치" || bad "comm 폴더 import rc=$rc got=$got want=$want"
[ ! -e "$R/.claude/fable-team/bin/.fable-team" ] && [ ! -e "$R/.claude/fable-team/bin/mailbox.jsonl" ] && ok "bin 에 엉뚱한 우편함 0" || bad "bin 에 우편함 생김"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
