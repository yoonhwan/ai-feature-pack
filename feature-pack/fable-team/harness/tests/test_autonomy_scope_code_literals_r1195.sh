#!/usr/bin/env bash
# test_autonomy_scope_code_literals_r1195.sh — r1195: 코드 파일(셔뱅 없음)은 «문자열 리터럴 안» 글만 셸 판정 · 식별자 괄호 «(env)» 는 부분 셸 아님
# 임시 origin(bare)+clone · gh·실 원격 0 · 기준판 = git 의 HEAD 판 사본($T/base) · 변이는 사본($T/mut)에서만
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
same() {  # same <이름> <가지> — 새 판과 기준판 출력·rc 가 같다
  run "$BASE/autonomy_scope_classify.py" "$(git -C "$W" rev-parse "$2")"; local brc="$rc" bout="$out"
  run "$CLS" "$(git -C "$W" rev-parse "$2")"
  [ "$rc" = "$brc" ] && [ "$out" = "$bout" ]; ck "$1 (기준판 rc=$brc 같음)" $?
}
BASE="$T/base"; mkdir -p "$BASE"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$BASE"/
python3 - "$BASE/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()   # 기준판 = r1195 전 분기(식별자 set( 만 가린 전문)
old = 'kept = "".join(c if m or c == "\\n" else " " for c, m in zip(full, mask)).split("\\n")'
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, 'kept = shield_set_call(full).split("\\n")'))
EOF
ck "기준판 사본(r1195 전 분기)" $?

python3 -I -m py_compile "$BIN/autonomy_scope_secret.py"; ck "py_compile secret" $?
# R1 — pytest 픽스처 이름 env 를 받는 def (ccu PR 5253 꼴)
mkf r1 tests/test_backoff.py 'async def test_r2(env):' '    env.events.append(1)'
run "$BASE/autonomy_scope_classify.py" "$SHA"; want "R1 기준판 = secret «env 전체 출력»(오판 재현)" 3 "FORBID kind=secret"
run "$CLS" "$SHA"; want "R1 .py «async def test_r2(env):» → secret 0" 0 "CLASS code"
# R2 — 식별자 호출 괄호
mkf r2 app/show.py 'print(env)' 'set_env(env)'
run "$CLS" "$SHA"; want "R2 .py «print(env)»·«set_env(env)» → secret 0" 0 "CLASS code"
# R3·R4 — 리터럴 안 명령은 지금처럼
mkf r3 app/leak.py 'import os' 'os.system("env")'
run "$CLS" "$SHA"; want "R3 .py «os.system(\"env\")» → secret «env 전체 출력»" 3 "FORBID kind=secret 추가 줄: env"
same "R3 기준판 대조" r3
mkf r4 app/tee.py 'import subprocess' 'subprocess.run("printenv | tee out.txt", shell=True)'
same "R4 .py «subprocess.run(\"printenv | tee out.txt\", shell=True)»" r4
mkf r4b app/multi.py 'X = """' 'env' '"""'
same "R4b .py 여러 줄 따옴표 안 env" r4b
# R5 — 셸 길 그대로
mkf r5 scripts/sub.sh '( env )'
run "$CLS" "$SHA"; want "R5 .sh «( env )» → secret" 3 "FORBID kind=secret"
same "R5 기준판 대조" r5
mkf r5b tools/dumpenv 'env'
same "R5b 확장자 없는 스크립트 «env»" r5b
# R6 — 셔뱅 있는 .py = 전문 셸 판정
mkf r6 app/sh.py '#!/bin/bash' 'print(env)'
run "$CLS" "$SHA"; want "R6 셔뱅 .py «print(env)» → secret(셸 문맥)" 3 "FORBID kind=secret"
same "R6 기준판 대조" r6

# 변이 — 리터럴 밖 가림 끔(= 옛 전문 판정) → R1 빨강
MUT="$T/mut"; mkdir -p "$MUT"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$MUT"/
python3 - "$MUT/autonomy_scope_secret.py" <<'EOF'
import sys; p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old = 'c if m or c == "\\n" else " "'
assert old in t
open(p, "w", encoding="utf-8").write(t.replace(old, "c"))
EOF
run "$MUT/autonomy_scope_classify.py" "$(git -C "$W" rev-parse r1)"; want "변이: 리터럴 밖 가림 끔 → R1 빨강(FORBID secret)" 3 "FORBID kind=secret"

cmp -s "$BIN/autonomy_scope_secret.py" "$KIT/autonomy_scope_secret.py"; ck "kit 사본 cmp0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
