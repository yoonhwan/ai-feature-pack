#!/usr/bin/env bash
# test_autonomy_scope_py_shebang_r1645.sh — r1645: 셔뱅 해석기가 «셸 아님이 확실» 하고 확장자가 코드면 셸 분기를 비켜선다(파이썬 셔뱅 .py 의 set() 오탐 0)
# 임시 origin(bare)+clone · 실 홈·실 라이브 0 · 변이는 사본($T/mut)에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
CLS="$BIN/autonomy_scope_classify.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() {  # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  local br="$1" p="$2"; shift 2
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"
}
run() { out="$(python3 "$1" classify "$2" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }

python3 -I -m py_compile "$BIN/autonomy_scope_secret.py"; ck "py_compile secret" $?
# ⓐ 파이썬 셔뱅 .py 의 «식» = FORBID 0
mkf a1 pkg/p.py '#!/usr/bin/env python3' 'ok = set(digest) <= HEX' 'd = sorted(set(a) | set(b))'
run "$CLS" "$SHA"; want "ⓐ python 셔뱅 .py set() 식 → secret 0" 0 "CLASS code"
[[ "$out" != *FORBID* ]]; ck "ⓐ FORBID 0" $?
# ⓑ 파이썬 셔뱅 .py 의 «리터럴 속 명령» = 잡힌다
mkf b2 pkg/q.py '#!/usr/bin/env python3' 'import os' 'os.system("set")'
run "$CLS" "$SHA"; want "ⓑ python 셔뱅 .py 리터럴 속 set → secret" 3 "FORBID kind=secret"
# ⓒ 셸 셔뱅은 그대로(닫힌 쪽 유지)
mkf c1 tools/i1 '#!/bin/sh' 'set'
run "$CLS" "$SHA"; want "ⓒ i1 확장자 없음 #!/bin/sh set → secret" 3 "FORBID kind=secret"
mkf c2 pkg/i4.py '#!/bin/sh' 'set(tags)'
run "$CLS" "$SHA"; want "ⓒ i4 .py #!/bin/sh set(tags) → secret" 3 "FORBID kind=secret"
mkf c3 pkg/r6.py '#!/bin/bash' 'print(env)'
run "$CLS" "$SHA"; want "ⓒ r6 .py #!/bin/bash print(env) → secret" 3 "FORBID kind=secret"
mkf c4 tools/b1.sh '#!/bin/bash' 'set'
run "$CLS" "$SHA"; want "ⓒ b1 .sh set → secret" 3 "FORBID kind=secret"
# ⓓ 판단 못 하는 셔뱅 = 셸로 본다
mkf d1 pkg/envS.py '#!/usr/bin/env -S bash -e' 'set(x)'
run "$CLS" "$SHA"; want "ⓓ env -S bash -e → secret" 3 "FORBID kind=secret"
mkf d2 pkg/envS2.py '#!/usr/bin/env -S python3' 'set(x)'
run "$CLS" "$SHA"; want "ⓓ env -S python3(분해 불가) → secret" 3 "FORBID kind=secret"
mkf d3 pkg/weird.py '#!/opt/x/weird' 'set(x)'
run "$CLS" "$SHA"; want "ⓓ 모르는 해석기 /opt/x/weird → secret" 3 "FORBID kind=secret"

mut() {  # mut <이름> <파이썬 조각> — 사본에서 시험할 파일 하나만 바꾼다
  MUT1="$T/mut1"; [ "$1" = mut2 ] && MUT1="$T/mut2"; [ "$1" = mut3 ] && MUT1="$T/mut3"
  mkdir -p "$MUT1"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$MUT1"/
  python3 - "$MUT1/autonomy_scope_secret.py" "$2" "$3" <<'EOF'
import sys; p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]; t = open(p, encoding="utf-8").read()
assert old in t, old
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
EOF
  ck "$1 사본" $?
}
# M1 — «셸 아님» 조건을 늘 참 → ⓒ 빨강
mut mut1 'return name in NON_SHELL_INTERP or re.fullmatch(r"python3\.\d+", name) is not None' 'return True'
run "$T/mut1/autonomy_scope_classify.py" "$(git -C "$W" rev-parse c2)"; want "변이 M1(늘 참) → i4 빨강(secret 0 = 계약 위반)" 0 "CLASS code"
run "$T/mut1/autonomy_scope_classify.py" "$(git -C "$W" rev-parse c3)"; want "변이 M1(늘 참) → r6 빨강(secret 0 = 계약 위반)" 0 "CLASS code"
# M2 — 조건을 지움(옛 동작) → ⓐ 빨강
mut mut2 'if not (ext in CODE_EXT and non_shell_shebang(full)):   # r1645: 셸 아닌 해석기 + 코드 확장자만 비켜선다' 'if True:'
run "$T/mut2/autonomy_scope_classify.py" "$(git -C "$W" rev-parse a1)"; want "변이 M2(옛 동작) → ⓐ 빨강(FORBID 재현)" 3 "FORBID kind=secret"
# M3 — «-S 판단 못 함» 을 뺌 → ⓓ(env -S python3) 빨강
mut mut3 '        if "-S" in words[1:]:' '        if False:'
run "$T/mut3/autonomy_scope_classify.py" "$(git -C "$W" rev-parse d2)"; want "변이 M3(-S 무시) → ⓓ env -S python3 빨강(secret 0)" 0 "CLASS code"
run "$T/mut3/autonomy_scope_classify.py" "$(git -C "$W" rev-parse d1)"; want "변이 M3 은 env -S bash -e 는 그대로 잡힘" 3 "FORBID kind=secret"

cmp -s "$BIN/autonomy_scope_secret.py" "$KIT/autonomy_scope_secret.py"; ck "kit 사본 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
