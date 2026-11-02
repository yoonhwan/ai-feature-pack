#!/usr/bin/env bash
# test_tests_copy_import_closure_r1316.sh — r1316: 시험이 임시 bin 에 .py 를 복사할 때 그 .py 의
#   최상위 «from <로컬모듈> import» 짝도 같이 복사하는지 정적으로 잰다(정본 = bin/<모듈>.py 실재).
#   r1298 이 ft_teamset.py 에 «from ft_team_lib import» 를 넣은 뒤, ft_teamset.py 만 복사하던
#   시험들이 ModuleNotFoundError 로 빨개졌다(r1308 격리 8개 rc1/rc124). 같은 누락의 재발을 막는다.
#   실행: bash test_tests_copy_import_closure_r1316.sh   (100644 · 외부 호출 0 · git 0)
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ME="$(basename -- "$0")"
BIN="$HERE/../bin"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: ${2:-}"; fail=$((fail + 1)); }

cat > "$TMP/scan.py" <<'PYEOF'
"""r1316 static scan: copied .py must carry its local top-level `from X import` pair."""
import fnmatch
import pathlib
import re
import sys

CP = re.compile(r'(?:^|[;&|(]|\s)cp(?:\s|$)')
SEG = re.compile(r'&&|\|\||;')
REC = re.compile(r'cp\s+-[A-Za-z]*[Rra]')
SRCTOK = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?/([^\s"\';)]+)')
FOR = re.compile(r'\bfor\s+(\w+)\s+in\s+([^;]*?)\s*(?:;\s*|\s+)do\b')
PYNAME = re.compile(r'[A-Za-z0-9_.\-*]+\.py')
ASSIGN = re.compile(r'^\s*(\w+)=(.*)$')
TEMPMARK = re.compile(r'\$\{?(?:T|TMP|T0|TMPD|TD)\b|mktemp')


def logical(txt):
    out, buf = [], ''
    for ln in txt.splitlines():
        if ln.rstrip().endswith('\\'):
            buf += ln.rstrip()[:-1] + ' '
            continue
        out.append(buf + ln)
        buf = ''
    if buf:
        out.append(buf)
    return out


def _loop_body(lines, i):
    body = [lines[i]]
    j = i
    if 'done' in lines[i]:
        return body, i
    while j + 1 < len(lines):
        j += 1
        body.append(lines[j])
        if re.search(r'\bdone\b', lines[j]):
            break
    return body, j


def var_table(text):
    """(complete, assigned): «실 bin» 을 가리키는 변수 집합 / 파일에서 값이 대입된 변수 집합."""
    complete, assigned = set(), set()
    for ln in text.splitlines():
        m = ASSIGN.match(ln)
        if not m:
            continue
        name, val = m.group(1), m.group(2)
        assigned.add(name)
        v = val.split('#')[0].strip().strip('"').strip("'")
        if v.endswith('/bin') or v.endswith('/bin/'):
            if not TEMPMARK.search(v):
                complete.add(name)
    return complete, assigned


def copied(text):
    """(names, globs) of .py basenames this file copies into some dir."""
    lines = logical(text)
    complete, assigned = var_table(text)
    names, globs = set(), set()
    i = 0
    while i < len(lines):
        ln = lines[i]
        m = FOR.search(ln)
        if m:
            var = m.group(1)
            lst = PYNAME.findall(m.group(2))
            body, j = _loop_body(lines, i)
            joined = ' '.join(body)
            if CP.search(joined) and re.search(r'\$\{?' + var + r'\}?\b', joined):
                for n in lst:
                    (globs if '*' in n else names).add(n)
            i = j + 1
            continue
        for seg in SEG.split(ln):
            if not CP.search(seg):
                continue
            for v, tok in SRCTOK.findall(seg):
                if '*' in tok:
                    if tok.endswith('.py'):
                        globs.add(tok)         # ft*.py 처럼 «복사 대상 전체» 를 선언한 글롭만 동승으로 센다
                elif tok.endswith('.py'):
                    names.add(tok)
        i += 1
    return names, globs


def localmods(bindir, name):
    """bin/<name> 의 최상위 `from <mod> import` 중 bin 에 실재하는 모듈."""
    p = bindir / name
    out = []
    if not p.is_file():
        return out
    for ln in p.read_text(errors='replace').splitlines():
        m = re.match(r'from\s+([A-Za-z_][A-Za-z0-9_]*)\s+import\b', ln)
        if m and (bindir / (m.group(1) + '.py')).is_file():
            out.append(m.group(1))
    return out


def scan(testsdir, bindir, self_name):
    fails = []
    for f in sorted(testsdir.rglob('*')):
        if not f.is_file() or f.name == self_name or f.suffix not in ('.sh', '.py'):
            continue
        names, globs = copied(f.read_text(errors='replace'))
        for n in sorted(names):
            for mod in localmods(bindir, n):
                if f'{mod}.py' in names or any(fnmatch.fnmatch(f'{mod}.py', g) for g in globs):
                    continue
                fails.append((str(f.relative_to(testsdir)), n, f'{mod}.py'))
    fails = sorted(set(fails))
    return fails


def _main(argv):
    d = b = None
    self_name = '__none__'
    i = 0
    while i < len(argv):
        if argv[i] == '--dir':
            d = pathlib.Path(argv[i + 1]); i += 2
        elif argv[i] == '--bin':
            b = pathlib.Path(argv[i + 1]); i += 2
        elif argv[i] == '--self':
            self_name = argv[i + 1]; i += 2
        else:
            i += 1
    if d is None or b is None or not b.is_dir():
        print('ERROR usage: scan.py --dir <tests> --bin <bin> [--self <name>]')
        return 2
    fails = scan(d, b, self_name)
    for t, n, m in fails:
        print(f'FAIL {t} {n} -> {m} 없음')
    print(f'TOTAL {len(fails)}')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(_main(sys.argv[1:]))
PYEOF

S0=$SECONDS
out="$(python3 "$TMP/scan.py" --dir "$HERE" --bin "$BIN" --self "$ME" 2>&1)"; rc=$?
S1=$SECONDS

# R1 — 이 폴더 전체: 짝 누락 0 (기준판 = 60건 안팎 빨강 · 고친 판 = 0건 rc0)
if [ "$rc" -eq 0 ]; then
  ok "R1 tests/ 짝 누락 0건 rc0 ($(printf '%s\n' "$out" | tail -1))"
else
  bad "R1 tests/ 짝 누락" "$(printf '%s\n' "$out" | head -5 | tr '\n' '|')"
fi

# R2 — 복사 짝이 빠진 임시 시험 1개 = FAIL 1줄 (ft_teamset.py 는 ft_team_lib.py 를 부른다)
mkdir -p "$TMP/r2"
printf 'cp "$SRC/ft_teamset.py" "$T/bin/"\n' > "$TMP/r2/test_only_teamset.sh"
o2="$(python3 "$TMP/scan.py" --dir "$TMP/r2" --bin "$BIN" 2>&1)"; rc2=$?
case "$o2" in
  *"ft_teamset.py -> ft_team_lib.py 없음"*) h2=1 ;;
  *) h2=0 ;;
esac
[ "$rc2" -eq 1 ] && [ "$h2" -eq 1 ] && ok "R2 짝 빠짐 = FAIL 1줄 rc1" || bad "R2 짝 빠짐 판정" "rc=$rc2 out=$(printf '%s' "$o2" | tr '\n' '|')"

# R3 — 둘 다 복사 = 0건 rc0
mkdir -p "$TMP/r3"
printf 'cp "$SRC/ft_teamset.py" "$SRC/ft_team_lib.py" "$T/bin/"\n' > "$TMP/r3/test_both.sh"
o3="$(python3 "$TMP/scan.py" --dir "$TMP/r3" --bin "$BIN" 2>&1)"; rc3=$?
[ "$rc3" -eq 0 ] && ok "R3 둘 다 복사 = rc0" || bad "R3 둘 다 복사" "rc=$rc3 out=$(printf '%s' "$o3" | tr '\n' '|')"

# R4 — «ft*.py» 글롭 복사 = 형제 모듈 동승(짝 누락으로 세지 않는다)
mkdir -p "$TMP/r4"
printf 'cp "$SRC"/ft*.py "$T/bin/"\n' > "$TMP/r4/test_glob.sh"
o4="$(python3 "$TMP/scan.py" --dir "$TMP/r4" --bin "$BIN" 2>&1)"; rc4=$?
[ "$rc4" -eq 0 ] && ok "R4 ft*.py 글롭 = rc0" || bad "R4 ft*.py 글롭" "rc=$rc4 out=$(printf '%s' "$o4" | tr '\n' '|')"

echo "단계별 초: R1=$((S1 - S0))s R2=0s R3=0s R4=0s"
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILED $fail"; exit 1
