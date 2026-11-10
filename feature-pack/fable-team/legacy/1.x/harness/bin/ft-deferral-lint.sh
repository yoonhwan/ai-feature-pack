#!/usr/bin/env bash
# ft-deferral-lint.sh — 유예 주석(deferral_patterns.txt)이 카드 경로/Issue 번호 없이 추가되면 거부한다. 읽기 전용.
#
# 사용:  git diff <base>...HEAD | ft-deferral-lint.sh        (또는 ft-deferral-lint.sh <diff 파일>)
#        ft-deferral-lint.sh --files <파일…>                 (전수 — 파일의 모든 줄이 대상)
# 실행 위치 = 리포 루트(카드 경로를 거기서 찾는다). 패턴 파일 = 이 스크립트 옆 deferral_patterns.txt (FT_DEFERRAL_PATTERNS 로 교체).
#   OK deferral-lint checked=N exempt=M        exit 0
#   REJECT <파일:행> <사유>: <줄 복사>           exit 1 (1건당 1줄)
#   SUMMARY deferral-lint checked=N rejected=R exempt=M   rc 와 무관하게 마지막 줄(checked = 패턴이 걸린 주석 줄 수, 면제 포함)
#   EXEMPT <파일:행> <이유>                     면제 꼬리를 본 줄(통과로 센다)
#   입력 없음·패턴 파일 없음·--files 대상 없음   exit 2
# 대상 = 주석(`#` `//` `/* */` `<!-- -->` `--` · py 는 docstring 포함) 안의 문구. 문자열 리터럴 안 단어는 대상이 아니다.
# 통과 = 그 줄이 속한 «연속 주석 덩어리»(코드 줄이 끼지 않은 연속 줄) 어딘가에 `→ 카드 <실재 .md 경로>` 또는 `#<숫자>` 가 있음
#        · 오탐 면제 = 같은 줄 `deferral-lint: ok <이유>`.
# 제외 = tests/fixtures/ · design/ · docs/ · *.md · 알 수 없는 확장자.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
export FT_DEFERRAL_PATTERNS="${FT_DEFERRAL_PATTERNS:-$HERE/deferral_patterns.txt}"
IFS= read -r -d '' PY <<'PYEOF' || true
import io, os, re, sys, tokenize

HASH = ('#', [], "'\"")
SLASH = ('//', [('/*', '*/')], "'\"`")
CFG = {'.py': HASH, '.sh': HASH, '.yml': HASH, '.yaml': HASH, '.toml': HASH, '.rb': HASH,
       '.css': (None, [('/*', '*/')], "'\""), '.scss': SLASH,
       '.html': (None, [('<!--', '-->')], ''), '.xml': (None, [('<!--', '-->')], ''),
       '.svg': (None, [('<!--', '-->')], ''), '.vue': (None, [('<!--', '-->')], ''),
       '.sql': ('--', [('/*', '*/')], "'\"")}
for e in ('.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.go', '.java', '.kt', '.swift', '.dart', '.rs', '.c', '.h', '.cpp'):
    CFG[e] = SLASH
CARD = re.compile(r'→\s*카드\s+(\S+?\.md)')
ISSUE = re.compile(r'(?<![\w/])#\d+')
EXEMPT = re.compile(r'deferral-lint:\s*ok\s+(\S.*)')


def excluded(p):
    return p.startswith(('tests/fixtures/', 'design/', 'docs/')) or p.endswith('.md') or os.path.splitext(p)[1] not in CFG


def py_comments(text):
    out, last = {}, None
    for t in tokenize.generate_tokens(io.StringIO(text).readline):
        if t.type == tokenize.COMMENT:
            out.setdefault(t.start[0], []).append(t.string)
        elif t.type == tokenize.STRING and last in (None, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT):
            for k, part in enumerate(t.string.split('\n')):
                out.setdefault(t.start[0] + k, []).append(part)
        if t.type not in (tokenize.NL, tokenize.COMMENT):
            last = t.type
    return out


def scan(text, ext):
    line_c, blocks, quotes = CFG[ext]
    out, i, n, ln = {}, 0, len(text), 1
    while i < n:
        c = text[i]
        if c == '\n':
            ln += 1; i += 1; continue
        blk = next(((o, cl) for o, cl in blocks if text.startswith(o, i)), None)
        if blk:
            j = text.find(blk[1], i + len(blk[0])); j = n if j < 0 else j
            for k, part in enumerate(text[i:j].split('\n')):
                out.setdefault(ln + k, []).append(part)
            ln += text[i:j].count('\n'); i = j + len(blk[1]); continue
        if line_c and text.startswith(line_c, i) and (line_c != '#' or i == 0 or text[i - 1] in ' \t\n;|&('):
            j = text.find('\n', i); j = n if j < 0 else j
            out.setdefault(ln, []).append(text[i:j]); i = j; continue
        if c in quotes:
            j = i + 1
            while j < n and text[j] != c and (text[j] != '\n' or c == '`'):
                if text[j] == '\\': j += 1
                if j < n and text[j] == '\n': ln += 1
                j += 1
            i = j + 1; continue
        i += 1
    return out


def comments(path):
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return None, []
    ext = os.path.splitext(path)[1]
    try:
        found = py_comments(text) if ext == '.py' else scan(text, ext)
    except (tokenize.TokenError, IndentationError, SyntaxError):
        found = scan(text, '.sh')
    return {k: ' '.join(v) for k, v in found.items()}, text.split('\n')


def run_text(com, ln):
    lo = hi = ln
    while lo - 1 in com: lo -= 1
    while hi + 1 in com: hi += 1
    return ' '.join(com[k] for k in range(lo, hi + 1))


def added_lines(diff):
    added, path, hunk, cur = {}, None, False, 0
    for ln in diff.split('\n'):
        if ln.startswith('diff --git'):
            hunk, path = False, None
        elif not hunk and ln.startswith('+++ '):
            p = ln[4:].split('\t')[0].strip()
            path = p[2:] if p.startswith('b/') else None
        elif ln.startswith('@@'):
            m = re.match(r'@@ -\d+(?:,\d+)? \+(\d+)', ln)
            hunk, cur = bool(m and path), int(m.group(1)) if m else 0
        elif hunk and ln.startswith('+'):
            added.setdefault(path, set()).add(cur); cur += 1
        elif hunk and not ln.startswith(('-', '\\')):
            cur += 1
    return added


def main(argv):
    pf = os.environ['FT_DEFERRAL_PATTERNS']
    if not os.path.isfile(pf):
        print('ERR 패턴 파일 없음: ' + pf); return 2
    pats = [p.rstrip('\n') for p in open(pf, encoding='utf-8') if p.strip() and not p.startswith('#')]
    if argv[:1] == ['--files']:
        added = {}
        for f in argv[1:]:
            if not os.path.isfile(f):
                print('ERR 파일 없음: ' + f); return 2
            added[f] = None
    else:
        diff = open(argv[0], encoding='utf-8', errors='replace').read() if argv else sys.stdin.read()
        added = added_lines(diff)
        if not diff.strip():
            print('usage: git diff A...B | ft-deferral-lint.sh | ft-deferral-lint.sh <diff> | --files <파일…>'); return 2
    rej = checked = exempt = 0
    for path in sorted(added):
        if excluded(path):
            continue
        com, lines = comments(path)
        if com is None:
            continue
        for ln in sorted(com):
            if added[path] is not None and ln not in added[path]:
                continue
            hit = next((p for p in pats if p in com[ln]), None)
            if not hit:
                continue
            checked += 1
            raw, tail = lines[ln - 1].strip(), run_text(com, ln)
            ex = EXEMPT.search(com[ln])
            if ex:
                exempt += 1; print('EXEMPT %s:%d %s' % (path, ln, ex.group(1).strip())); continue
            cards = CARD.findall(tail)
            if ISSUE.search(tail) or any(os.path.isfile(c) for c in cards):
                continue
            rej += 1
            why = '유예 주석의 카드 경로 실재 0 (%s)' % cards[0] if cards else '유예 주석에 카드/Issue 0'
            print('REJECT %s:%d %s — ft-index 카드 1장 만들고 경로를 같은 줄에(→ 카드 <경로>.md 또는 #번호): %s' % (path, ln, why, raw))
    if not rej:
        print('OK deferral-lint checked=%d exempt=%d' % (checked, exempt))
    print('SUMMARY deferral-lint checked=%d rejected=%d exempt=%d' % (checked, rej, exempt))
    return 1 if rej else 0


sys.exit(main(sys.argv[1:]))
PYEOF
exec python3 -c "$PY" "$@"
