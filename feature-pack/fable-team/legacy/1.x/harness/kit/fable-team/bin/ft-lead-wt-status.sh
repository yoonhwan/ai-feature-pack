#!/usr/bin/env bash
# ft-lead-wt-status.sh [--json] [--repo <dir>] [--seats-dir <dir>] [--no-fetch] [--base <main sha> <ops sha|->]   (r1695 · Issue #8363)
#   팀장 워크트리·가지 현황 집계 — 읽기 전용(쓰기 0 · 정리·삭제·rebase 0).
#   첫 줄 = «BASE main=<sha40> ops=<sha40|없음>» — 이후 모든 판정은 이 두 sha 로만 한다(fetch = 25초 1회 + 재시도 1 · --no-fetch = 로컬 ref 그대로).
#   ① worktree 목록: `git worktree list --porcelain` 의 «모든» 항목 · 1행 = worktree 1개(키 = 경로) · 분류 = 팀장 | 나노 | 그밖(사유).
#   ② 좌석 결속 목록: 명부 seats-*.json 의 _master·_arch 좌석 전부 · 1행 = 좌석 1개 · 공유 worktree = 정상 결속.
#   팀장 행: 좌석들 · 가지 · 착지 대상(BASE 두 sha 중 behind 작은 쪽 · 같으면 main) · behind·ahead · upstream(정보만) · 미커밋 · 바꾼 파일.
#   겹침: 팀장 가지끼리 같은 파일 · 같은 카드 번호(가지 이름·바꾼 카드 파일의 r<번호>).
#   rc 0 = 집계 끝 · 2 = usage · 3 = 판정 불가(git 실패 · «판정 불가 <칸> <사유>» 줄 · 나머지 행은 그대로 출력).
set -uo pipefail
exec python3 - "$@" <<'PY'
import glob, json, os, re, subprocess, sys

USAGE = "usage: ft-lead-wt-status.sh [--json] [--repo <dir>] [--seats-dir <dir>] [--no-fetch] [--base <main sha> <ops sha|->]"
CARD_RX = re.compile(r'(?:^|/)indices/(?:.*/)?r(\d+)-[^/]*\.md$')
BR_RX = re.compile(r'(?:^|[/_-])r(\d+)(?=[-_/.]|$)')
ERRS = []

def git(repo, *a, t=25):
    try:
        p = subprocess.run(['git', '-c', 'core.quotePath=false', '-C', repo, *a], capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        return None, 'timeout %ss' % t
    return (p.stdout if p.returncode == 0 else None), (p.stderr.strip().splitlines() or ['rc=%d' % p.returncode])[-1]

def bad(cell, why):
    ERRS.append('판정 불가 %s %s' % (cell, why))

def args():
    a = sys.argv[1:]; o = {'json': False, 'repo': os.getcwd(), 'seats': None, 'fetch': True, 'base': None}
    while a:
        x = a.pop(0)
        if x == '--json': o['json'] = True
        elif x == '--no-fetch': o['fetch'] = False
        elif x in ('--repo', '--seats-dir') and a: o['repo' if x == '--repo' else 'seats'] = a.pop(0)
        elif x == '--base' and len(a) >= 2: o['base'] = (a.pop(0), a.pop(0))
        else: print(USAGE, file=sys.stderr); sys.exit(2)
    return o

def root_of(repo):
    out, why = git(repo, 'rev-parse', '--path-format=absolute', '--git-common-dir', t=7)
    if out is None: print('판정 불가 repo %s' % why); sys.exit(3)
    d = out.strip()
    return os.path.dirname(d) if os.path.basename(d) == '.git' else d

def resolve_base(root, o):
    if o['base']:
        m, s = o['base']
        return m, (None if s in ('-', '없음', '') else s)
    if o['fetch']:
        specs = ['+refs/heads/main:refs/remotes/origin/main']
        if git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/ops/main-base', t=7)[0]:
            specs.append('+refs/heads/ops/main-base:refs/remotes/origin/ops/main-base')
        ok, why = None, ''
        for _ in range(2):
            ok, why = git(root, '-c', 'gc.auto=0', 'fetch', '-q', 'origin', *specs, t=25)
            if ok is not None: break
        if ok is None: print('판정 불가 BASE fetch %s' % why); sys.exit(3)
    m = (git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/main^{commit}', t=7)[0] or '').strip()
    if not m: print('판정 불가 BASE origin/main 없음'); sys.exit(3)
    s = (git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/ops/main-base^{commit}', t=7)[0] or '').strip()
    return m, (s or None)

def worktrees(root):
    out, why = git(root, 'worktree', 'list', '--porcelain', t=25)
    if out is None: print('판정 불가 worktree-list %s' % why); sys.exit(3)
    items, cur = [], None
    for line in out.split('\n'):
        if line.startswith('worktree '):
            cur = {'path': line[9:], 'head': None, 'branch': None, 'detached': False, 'bare': False}; items.append(cur)
        elif cur is None: continue
        elif line.startswith('HEAD '): cur['head'] = line[5:]
        elif line.startswith('branch '): cur['branch'] = line[7:]
        elif line == 'detached': cur['detached'] = True
        elif line == 'bare': cur['bare'] = True
    return items

def seats(sd):
    rows = []
    for f in sorted(glob.glob(os.path.join(sd, 'seats-*.json'))):
        team = os.path.basename(f)[6:-5]
        try: d = json.load(open(f, encoding='utf-8'))
        except Exception as e: print('판정 불가 명부 %s %s' % (f, e)); sys.exit(3)
        for role in ('_master', '_arch'):
            name = d.get(role)
            if not isinstance(name, str) or not name: continue
            row = d.get(name)
            rows.append({'seat': name, 'team': team, 'role': role[1:], 'wt': row.get('worktree') if isinstance(row, dict) else None})
    return rows

def bind(root, seat_rows, wt_real):
    for s in seat_rows:
        v = s['wt']; cands = []
        if isinstance(v, str) and v:
            cands = [v] if os.path.isabs(v) else [os.path.join(root, '.worktrees', v), os.path.join(root, v)]
        hit = next((os.path.realpath(c) for c in cands if os.path.realpath(c) in wt_real), None)
        s['path'] = wt_real[hit] if hit else None
        s['mismatch'] = None if hit else '좌석 칸 불일치 %s' % (v if v not in (None, '') else '<값 없음>')

def count(root, rng):
    out, why = git(root, 'rev-list', '--count', rng)
    return (int(out.strip()), None) if out is not None else (None, why)

def lead_detail(root, w, base):
    tip = w['head']; r = {'target': None, 'behind': None, 'ahead': None, 'basis': {}, 'files': None, 'cards': [], 'errors': []}
    if not tip: r['errors'].append('판정 불가 tip %s HEAD 없음' % w['path']); return r
    for name, sha in base.items():
        if not sha: continue
        b, why = count(root, '%s..%s' % (tip, sha))
        if b is None: r['errors'].append('판정 불가 behind %s %s' % (w['path'], why)); return r
        r['basis'][name] = b
    r['target'] = min(r['basis'], key=lambda k: (r['basis'][k], k != 'main'))
    tsha = base[r['target']]; r['behind'] = r['basis'][r['target']]
    r['ahead'], why = count(root, '%s..%s' % (tsha, tip))
    if r['ahead'] is None: r['errors'].append('판정 불가 ahead %s %s' % (w['path'], why))
    up, _ = git(w['path'], 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}', t=7)
    r['upstream'] = up.strip() if up else '없음'
    st, why = git(w['path'], 'status', '--porcelain', t=7)
    r['dirty'] = len([l for l in st.split('\n') if l]) if st is not None else None
    if st is None: r['errors'].append('판정 불가 미커밋 %s %s' % (w['path'], why))
    mb, why = git(root, 'merge-base', tip, tsha)
    if mb is None: r['errors'].append('판정 불가 merge-base %s %s' % (w['path'], why)); return r
    fl, why = git(root, 'diff', '--name-only', '--no-renames', mb.strip(), tip)
    if fl is None: r['errors'].append('판정 불가 바꾼파일 %s %s' % (w['path'], why)); return r
    r['files'] = sorted(x for x in fl.split('\n') if x)
    nums = {m.group(1) for m in BR_RX.finditer(w['branch'] or '')}
    nums |= {m.group(1) for f in r['files'] for m in [CARD_RX.search(f)] if m}
    r['cards'] = sorted(nums, key=int)
    return r

def main():
    o = args(); root = root_of(o['repo'])
    m, s = resolve_base(root, o); base = {'main': m, 'ops/main-base': s}
    print('BASE main=%s ops=%s' % (m, s or '없음'), flush=True)
    wts = worktrees(root); wt_real = {os.path.realpath(w['path']): w['path'] for w in wts}
    srows = seats(o['seats'] or os.path.join(root, '.fable-team')); bind(root, srows, wt_real)
    by_path = {}
    for s_ in srows:
        if s_['path']: by_path.setdefault(s_['path'], []).append(s_['seat'])
    rows = []
    for w in wts:
        r = {'path': w['path'], 'branch': (w['branch'] or '').replace('refs/heads/', '', 1) or None, 'head': w['head']}
        if w['path'] in by_path:
            r.update(kind='팀장', seats=by_path[w['path']]); r.update(lead_detail(root, w, base)); ERRS.extend(r['errors'])
        elif (w['branch'] or '').startswith('refs/heads/nano/'): r['kind'] = '나노'
        else:
            r['kind'] = '그밖'
            br = r['branch'] or ''
            r['reason'] = 'bare' if w['bare'] else 'detached' if w['detached'] or not br else 'docs 가지' if br.startswith('docs/') else '좌석 없음 %s' % br
        rows.append(r)
    leads = [r for r in rows if r['kind'] == '팀장']
    ofiles, ocards = [], []
    for i, a in enumerate(leads):
        for b in leads[i + 1:]:
            common = sorted(set(a['files'] or []) & set(b['files'] or []))
            if common: ofiles.append({'a': a['path'], 'b': b['path'], 'files': common})
            cc = sorted(set(a['cards']) & set(b['cards']), key=int)
            if cc: ocards.append({'a': a['path'], 'b': b['path'], 'cards': ['r' + c for c in cc]})
    if o['json']:
        print(json.dumps({'base': base, 'worktrees': rows, 'seats': srows, 'overlaps': {'files': ofiles, 'cards': ocards}, 'errors': ERRS}, ensure_ascii=False))
    else:
        for r in rows:
            if r['kind'] == '팀장':
                f = r['files']; fs = '판정불가' if f is None else '%d:%s%s' % (len(f), ','.join(f[:5]), ',…' if len(f) > 5 else '')
                basis = ','.join('%s:%s' % kv for kv in r['basis'].items())
                print('WT 팀장 %s seats=%s branch=%s target=%s behind=%s ahead=%s basis=%s upstream=%s dirty=%s files=%s' % (
                    r['path'], ','.join(r['seats']), r['branch'] or 'detached', r['target'], r['behind'], r['ahead'], basis, r.get('upstream'), r.get('dirty'), fs))
            elif r['kind'] == '나노': print('WT 나노 %s branch=%s' % (r['path'], r['branch']))
            else: print('WT 그밖 %s 사유=%s' % (r['path'], r['reason']))
        for s_ in srows:
            print('SEAT %s team=%s role=%s wt=%s %s' % (s_['seat'], s_['team'], s_['role'], s_['wt'], ('path=' + s_['path']) if s_['path'] else s_['mismatch']))
        for x in ofiles: print('OVERLAP-FILE %s %s n=%d %s' % (x['a'], x['b'], len(x['files']), ','.join(x['files'][:5])))
        for x in ocards: print('OVERLAP-CARD %s %s %s' % (x['a'], x['b'], ','.join(x['cards'])))
        for e in ERRS: print(e)
    k = lambda n: sum(1 for r in rows if r['kind'] == n)
    print('SUM worktrees=%d 팀장=%d 나노=%d 그밖=%d seats=%d 결속=%d 불일치=%d' % (
        len(rows), k('팀장'), k('나노'), k('그밖'), len(srows), sum(1 for s_ in srows if s_['path']), sum(1 for s_ in srows if not s_['path'])), file=sys.stderr if o['json'] else sys.stdout)
    sys.exit(3 if ERRS else 0)

main()
PY
