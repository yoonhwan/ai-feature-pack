#!/usr/bin/env bash
# test_autonomy_scope_py_shebang_r1645.sh — r1645: 셔뱅 해석기가 «셸 아님이 확실» 하고 확장자가 코드면 셸 분기를 비켜선다(파이썬 셔뱅 .py 의 set() 오탐 0 · env 옵션이 있으면 셸)
# 임시 origin(bare)+clone · 실 홈·실 라이브 0 · 변이는 사본에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() { local br="$1" p="$2"; shift 2   # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
run() { out="$(python3 "$1" classify "$2" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
c() { local n="$1" b="$2" p="$3" erc="$4" pre="$5"; shift 5   # c <이름> <가지> <경로> <기대rc> <기대앞자리> <줄…>
  mkf "$b" "$p" "$@"; run "$CLS" "$SHA"; want "$n" "$erc" "$pre"; }
python3 -I -m py_compile "$BIN/autonomy_scope_secret.py"; ck "py_compile secret" $?
c "ⓐ python 셔뱅 식 → secret 0" a1 pkg/p.py 0 "CLASS code" '#!/usr/bin/env python3' 'ok = set(digest) <= HEX' 'd = sorted(set(a) | set(b))'
[[ "$out" != *FORBID* ]]; ck "ⓐ FORBID 0" $?
c "ⓑ 리터럴 속 set → secret" b2 pkg/q.py 3 "FORBID kind=secret" '#!/usr/bin/env python3' 'import os' 'os.system("set")'
c "ⓒ i1 확장자 없음 #!/bin/sh set → secret" c1 tools/i1 3 "FORBID kind=secret" '#!/bin/sh' 'set'
c "ⓒ i4 .py #!/bin/sh set(tags) → secret" c2 pkg/i4.py 3 "FORBID kind=secret" '#!/bin/sh' 'set(tags)'
c "ⓒ r6 .py #!/bin/bash print(env) → secret" c3 pkg/r6.py 3 "FORBID kind=secret" '#!/bin/bash' 'print(env)'
c "ⓒ b1 .sh set → secret" c4 tools/b1.sh 3 "FORBID kind=secret" '#!/bin/bash' 'set'
c "ⓓ env -S bash -e → secret" d1 pkg/envS.py 3 "FORBID kind=secret" '#!/usr/bin/env -S bash -e' 'set(x)'
c "ⓓ env -S python3(분해 불가) → secret" d2 pkg/envS2.py 3 "FORBID kind=secret" '#!/usr/bin/env -S python3' 'set(x)'
c "ⓓ 모르는 해석기 /opt/x/weird → secret" d3 pkg/weird.py 3 "FORBID kind=secret" '#!/opt/x/weird' 'set(x)'
# E(DA #282761 반례): env 옵션의 «인자» 를 해석기로 보면 실제 실행은 뒤쪽 해석기다 → env 옵션이 있으면 셸로
c "E env -u python3 bash → secret" e1 pkg/eu.py 3 "FORBID kind=secret" '#!/usr/bin/env -u python3 bash' 'set(x)'
c "E env -C /tmp python3 → secret" e2 pkg/eC.py 3 "FORBID kind=secret" '#!/usr/bin/env -C /tmp python3' 'set(x)'
c "E env -P /usr/bin python3 → secret" e3 pkg/eP.py 3 "FORBID kind=secret" '#!/usr/bin/env -P /usr/bin python3' 'set(x)'
mut() { local n="$1"; shift   # mut <이름> <옛1> <새1> [<옛2> <새2>] — 사본 하나만 바꾼다
  MUT1="$T/$n"; mkdir -p "$MUT1"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$MUT1"/
  python3 - "$MUT1/autonomy_scope_secret.py" "$@" <<'EOF'
import sys
p, pr = sys.argv[1], sys.argv[2:]
t = open(p, encoding="utf-8").read()
for old, new in zip(pr[::2], pr[1::2]):
    assert old in t, old
    t = t.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(t)
EOF
  ck "$n 사본" $?; }
mr() { run "$T/$1/autonomy_scope_classify.py" "$(git -C "$W" rev-parse "$2")"; }
# M1 «셸 아님» 조건 늘 참 → ⓒ 빨강 · M2 셔뱅 분기 옛 동작 → ⓐ 빨강 · M3 env 옵션 가드 끄고 옛 거르기 복귀 → E·ⓓ 빨강
mut mut1 'return name in NON_SHELL_INTERP or re.fullmatch(r"python3\.\d+", name) is not None' 'return True'
mr mut1 c2; want "변이 M1(늘 참) → i4 빨강(secret 0)" 0 "CLASS code"
mr mut1 c3; want "변이 M1(늘 참) → r6 빨강(secret 0)" 0 "CLASS code"
mut mut2 'if not (ext in CODE_EXT and non_shell_shebang(full)):   # r1645: 셸 아닌 해석기 + 코드 확장자만 비켜선다' 'if True:'
mr mut2 a1; want "변이 M2(옛 동작) → ⓐ 빨강(FORBID 재현)" 3 "FORBID kind=secret"
mut mut3 'if any(w.startswith("-") for w in words[1:]):' 'if False:' 'words = [w for w in words[1:] if "=" not in w]' 'words = [w for w in words[1:] if not w.startswith("-") and "=" not in w]'
mr mut3 e1; want "변이 M3(env 옵션 가드 끔) → E 빨강(secret 0)" 0 "CLASS code"
mr mut3 d2; want "변이 M3 은 env -S python3 도 빨강" 0 "CLASS code"

cmp -s "$BIN/autonomy_scope_secret.py" "$KIT/autonomy_scope_secret.py"; ck "kit 사본 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
