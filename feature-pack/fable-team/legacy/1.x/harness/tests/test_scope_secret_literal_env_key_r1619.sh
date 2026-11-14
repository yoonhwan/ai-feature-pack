#!/usr/bin/env bash
# test_scope_secret_literal_env_key_r1619.sh — r1619: 코드 리터럴 «"env"» 가 dict 키·첨자 자리면 셸 명령 env 로 읽지 않는다(r1610 PR #871 오탐)
# 명령 자리(os.system·subprocess.run·run(shell=True)·목록 첫 칸·파이프 글)와 섞인 줄은 지금처럼 secret.
# 제품 변경 0 — 빼기는 r1801(autonomy_scope_code_word.py)이 이미 한다. 이 시험은 r1619 사례로 그 동작을 잠근다.
# 기준판(Red) = bin 사본 + 빼기 모듈을 «안 뺌» 으로 바꾼 판(r1801 전 동작) · 임시 origin(bare)+clone · 변이는 사본에서만
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"; CLS="$BIN/autonomy_scope_classify.py"
PACK="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"; export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkf() { local br="$1" p="$2"; shift 2   # mkf <가지> <경로> <줄…> — 파일 하나 쓰고 커밋 → SHA
  git -C "$W" checkout -q -B "$br" "$M0"; mkdir -p "$W/$(dirname "$p")"
  printf '%s\n' "$@" > "$W/$p"; cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
crit() { out="$(python3 "$1" classify "$2" --repo "${3:-$W}" --critical 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }
cp_bin() { mkdir -p "$1"; cp "$BIN"/autonomy_scope_*.py "$BIN"/ft_secret_*.py "$1"/; }
BASE="$T/base"; cp_bin "$BASE"
printf 'def drop(text, mask, *_opt):\n    return mask\n' > "$BASE/autonomy_scope_code_word.py"
SECRET="CRITICAL kind=secret"
ok_new() { local n="$1" b="$2"; shift 2   # 기준판 = secret(오탐 재현) · 지금 판 = CRITICAL-OK
  mkf "$b" "$@"
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; want "$n 기준판 = secret(오탐 재현)" 3 "$SECRET"
  crit "$CLS" "$SHA"; want "$n → CRITICAL-OK" 0 "CRITICAL-OK"; }
no_now() { local n="$1" b="$2"; shift 2; mkf "$b" "$@"; crit "$CLS" "$SHA"; want "$n → secret" 3 "$SECRET"; }
same() { local n="$1" b="$2"; shift 2; mkf "$b" "$@"   # 지금 판 = 기준판(출력·rc 바이트 같음)
  crit "$BASE/autonomy_scope_classify.py" "$SHA"; local brc="$rc" bout="$out"
  crit "$CLS" "$SHA"; [ "$rc" = "$brc" ] && [ "$out" = "$bout" ]; ck "$n (기준판 rc=$brc 같음)" $?; }

# ⓐ Red(기준판) → 지금 판 OK — r1610 시험 꼴 두 줄
ok_new "ⓐ r1610 꼴 dict 키 + env[\"env\"]" ca tests/test_a.py 'E = {' '    "env": {"A": "1"},' '}' 'got = run_tools(env["env"])'
# ⓑ 키·첨자 자리 = 판정 제외
ok_new "ⓑ1 x[\"env\"]" cb1 tests/b1.py 'y = x["env"]'
ok_new "ⓑ2 f()[\"env\"]" cb2 tests/b2.py 'y = f()["env"]'
ok_new "ⓑ3 a[0][\"env\"]" cb3 tests/b3.py 'y = a[0]["env"]'
ok_new "ⓑ4 {'env': 1} 작은따옴표" cb4 tests/b4.py "D = {'env': 1}"
# ⓒ 명령 자리 = 지금처럼 secret
no_now "ⓒ1 os.system(\"env\")" cc1 app/c1.py 'import os' 'os.system("env")'
no_now "ⓒ2 subprocess.run([\"env\"])" cc2 app/c2.py 'import subprocess' 'subprocess.run(["env"])'
no_now "ⓒ3 run(\"env\", shell=True)" cc3 app/c3.py 'run("env", shell=True)'
no_now "ⓒ4 목록 첫 칸 [\"env\"]" cc4 app/c4.py 'cmd = ["env"]'
# ⓒ5 여러 낱말 리터럴은 빼기 대상 아님 = 기준판 그대로(따옴표째 넘겨 판정기가 한 낱말로 읽는 놓침은 r1195 기존 동작 · 범위 밖 보고)
same "ⓒ5 \"env | grep X\" = 지금처럼" cc5 app/c5.py 'cmd = "env | grep X"'
# ⓓ 섞인 줄 — 키 제외가 명령 리터럴까지 지우지 않는다
no_now "ⓓ 키 \"env\": + os.system(\"env\") 한 줄" cd app/d.py 'import os' 'd = {"env": 1}; os.system("env")'
# 실사건 r1610 head(팩 리포 읽기만 · 없으면 SKIP)
R1610=8d22770d
if [ -n "$PACK" ] && git -C "$PACK" cat-file -e "$R1610^{commit}" 2>/dev/null; then
  crit "$CLS" "$(git -C "$PACK" rev-parse "$R1610")" "$PACK"; want "실사건 r1610 head → CRITICAL-OK" 0 "CRITICAL-OK"
else echo "SKIP 실사건 r1610 head (커밋 없음)"; fi

# 변이 — 사본의 빼기 모듈 1곳씩 · 사례가 빨강이면 잡힘
mut() {  # mut <이름> <가지> <옛 글> <새 글> → 변이판 out·rc
  local d="$T/mut_$1"; cp_bin "$d"
  python3 - "$d/autonomy_scope_code_word.py" "$3" "$4" <<'EOF'
import sys; p, old, new = sys.argv[1:4]; t = open(p, encoding="utf-8").read()
assert old in t, old
open(p, "w", encoding="utf-8").write(t.replace(old, new))
EOF
  ck "$1 변이 적용" $?; crit "$d/autonomy_scope_classify.py" "$(git -C "$W" rev-parse "$2")"; }
mut M1 cb4 "        return True   # ② dict 키" "        return False   # ② dict 키"
want "M1 키 제외 빼기 → ⓑ4 {'env': 1} 가 secret(빨강 = 잡힘)" 3 "$SECRET"
mut M2 cc4 'sub = c == "[" and head[-1:] != "" and' 'sub = c == "[" or'
want "M2 첨자 앞 글자 조건 빼기 → ⓒ4 [\"env\"] 가 통과(빨강 = 잡힘)" 0 "CRITICAL-OK"

for f in autonomy_scope_secret.py autonomy_scope_code_word.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "kit 사본 cmp0 $f" $?; done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
