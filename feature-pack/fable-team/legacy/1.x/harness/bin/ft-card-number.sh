#!/usr/bin/env bash
# ft-card-number.sh next <팀> <slug> | check <r번호> <팀> | lint <카드 파일>   [--repo <dir>] [--no-fetch] [--base <main sha> <ops sha|->]   (r1695 · Issue #8363)
#   카드 번호 발급 단일화 — 이미 쓴 번호 원본 세 곳:
#     ① BASE 두 sha 트리의 design/**/indices/**/r<번호>-*.md   ② refs/remotes/origin/* 가지 이름의 r<번호>
#     ③ 발급 원장 <루트>/.fable-team/state/card-number/ledger.tsv(번호 · 팀 · slug · 좌석 · 시각 · 추가 전용 · 잠금)  — FT_CARD_NUMBER_LEDGER 로 바꿀 수 있다
#   첫 줄 = «BASE main=<sha40> ops=<sha40|없음>»(fetch = 25초 1회 + 재시도 1 · --no-fetch = 로컬 ref 그대로).
#   next  = 세 원본 최댓값 + 1 을 잠금 안에서 원장에 «먼저» 적고 «ISSUED r<n> …» 출력(같은 번호 두 번 발급 0) · rc 0.
#   check = 그 번호를 «다른 팀» 카드(①)·원장 행(③)이 쓰면 «USED r<n> team=<팀> src=<자리>» 줄 + rc 1 · 없으면 «FREE …» rc 0.
#           ② 가지 이름(팀 모름)은 check 에서 «USED … team=? src=branch:<가지>» 로 전부 센다(lint 는 ①·③ 만 — 자기 카드의 nano/docs 가지를 겹침으로 세지 않게).
#   next 의 ② 는 «트리 최댓값 + BRANCH_GAP(100) 초과» 번호를 뺀다(다른 번호 체계 가지 · 예 docs/knowledge-r3889 · planner#265 결정 #285974) · 경계(= 최댓값+100)는 포함 · 원장·트리 원본은 그대로.
#   lint <카드 파일> = ft-index-lint.sh 가 부르는 check(--no-fetch 고정 · 팀 = design/teams/<팀>/ 또는 design/<팀>/) — 다른 팀 사용이면
#           그 카드가 이미 BASE 에 있으면 «WARN 기존 겹침 1» · 없으면 «BAD …» · 카드 자리가 아닌 파일 = 출력 0 · rc 0(판정 불가 = rc 3).
#   2 = usage · 3 = 판정 불가 <칸> <사유>(git 실패 · 원장 꼴 오류 · 잠금 7초 초과).
#   쓰기 = 원장 1파일(next 만) · 실 리포·워크트리·가지 쓰기 0.
set -uo pipefail
exec python3 - "$@" <<'PY'
import datetime, fcntl, os, re, signal, subprocess, sys

USAGE = "usage: ft-card-number.sh next <팀> <slug> | check <r번호> <팀> | lint <카드 파일>  [--repo <dir>] [--no-fetch] [--base <main sha> <ops sha|->]"
CARD_RX = re.compile(r'^design/(?:.*/)?indices/(?:.*/)?r(\d+)-[^/]*\.md$')
BR_RX = re.compile(r'(?:^|[/_-])r(\d+)(?=[-_/.]|$)')
BRANCH_GAP = 100   # next 전용: 트리 최댓값 + 이 값 초과인 가지 번호는 최댓값 계산에서 뺀다
NAME_RX = re.compile(r'^[a-z0-9][a-z0-9._-]*$')
ROW_RX = re.compile(r'^(\d+)\t([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]+)$')

def git(repo, *a, t=25):
    try:
        p = subprocess.run(['git', '-c', 'core.quotePath=false', '-C', repo, *a], capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        return None, 'timeout %ss' % t
    return (p.stdout if p.returncode == 0 else None), (p.stderr.strip().splitlines() or ['rc=%d' % p.returncode])[-1]

def die(cell, why):
    print('판정 불가 %s %s' % (cell, why)); sys.exit(3)

def usage():
    print(USAGE, file=sys.stderr); sys.exit(2)

def args():
    a = sys.argv[1:]; o = {'repo': os.getcwd(), 'fetch': True, 'base': None}; pos = []
    while a:
        x = a.pop(0)
        if x == '--no-fetch': o['fetch'] = False
        elif x == '--repo' and a: o['repo'] = a.pop(0)
        elif x == '--base' and len(a) >= 2: o['base'] = (a.pop(0), a.pop(0))
        elif x.startswith('-'): usage()
        else: pos.append(x)
    if not ((len(pos) == 3 and pos[0] in ('next', 'check')) or (len(pos) == 2 and pos[0] == 'lint')): usage()
    o['verb'] = pos[0]
    if o['verb'] == 'lint':
        o['file'], o['fetch'] = pos[1], False; return o
    if o['verb'] == 'next':
        o['team'], o['slug'] = pos[1], pos[2]
        if not NAME_RX.match(o['slug']): usage()
    else:
        m = re.match(r'^r(\d+)$', pos[1])
        if not m: usage()
        o['num'], o['team'] = int(m.group(1)), pos[2]
    if not NAME_RX.match(o['team']): usage()
    return o

def team_of(path):
    m = re.match(r'^design/teams/([^/]+)/', path) or re.match(r'^design/([^/]+)/', path)
    return m.group(1) if m else '?'

def resolve_base(root, o):
    if o['base']:
        m, s = o['base']; return m, (None if s in ('-', '없음', '') else s)
    if o['fetch']:
        specs = ['+refs/heads/main:refs/remotes/origin/main']
        if git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/ops/main-base', t=7)[0]:
            specs.append('+refs/heads/ops/main-base:refs/remotes/origin/ops/main-base')
        ok, why = None, ''
        for _ in range(2):
            ok, why = git(root, '-c', 'gc.auto=0', 'fetch', '-q', 'origin', *specs, t=25)
            if ok is not None: break
        if ok is None: die('BASE', 'fetch %s' % why)
    m = (git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/main^{commit}', t=7)[0] or '').strip()
    if not m: die('BASE', 'origin/main 없음')
    s = (git(root, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/ops/main-base^{commit}', t=7)[0] or '').strip()
    return m, (s or None)

def tree_cards(root, base):
    rows = []
    for label, sha in base:
        if not sha: continue
        out, why = git(root, 'ls-tree', '-r', '--name-only', sha, '--', 'design')
        if out is None: die('트리', '%s %s' % (label, why))
        for p in out.split('\n'):
            m = CARD_RX.match(p)
            if m: rows.append((int(m.group(1)), team_of(p), '%s:%s' % (label, p)))
    return rows

def branch_nums(root):
    out, why = git(root, 'for-each-ref', '--format=%(refname:strip=3)', 'refs/remotes/origin', t=7)
    if out is None: die('가지', why)
    return [(int(m.group(1)), b) for b in out.split('\n') for m in BR_RX.finditer(b)]

def ledger_rows(path):
    rows = []
    if not os.path.exists(path): return rows
    for i, line in enumerate(open(path, encoding='utf-8').read().split('\n'), 1):
        if not line: continue
        m = ROW_RX.match(line)
        if not m: die('원장', '%s:%d 꼴 오류' % (path, i))
        rows.append((int(m.group(1)), m.group(2), m.group(3), i))
    return rows

def main():
    o = args()
    out, why = git(o['repo'], 'rev-parse', '--path-format=absolute', '--git-common-dir', t=7)
    if out is None: die('repo', why)
    d = out.strip(); root = os.path.dirname(d) if os.path.basename(d) == '.git' else d
    if o['verb'] == 'lint':
        pre, _ = git(os.path.dirname(os.path.abspath(o['file'])), 'rev-parse', '--show-prefix', t=7)
        o['rel'] = (pre or '').strip() + os.path.basename(o['file']); mm = CARD_RX.match(o['rel'])
        if pre is None or not mm: sys.exit(0)
        o['num'], o['team'] = int(mm.group(1)), team_of(o['rel'])
    m, s = resolve_base(root, o)
    print('BASE main=%s ops=%s' % (m, s or '없음'), flush=True)
    ledger = os.environ.get('FT_CARD_NUMBER_LEDGER') or os.path.join(root, '.fable-team', 'state', 'card-number', 'ledger.tsv')
    cards = tree_cards(root, [('main', m), ('ops', s)])
    if o['verb'] in ('check', 'lint'):
        used = [(t, src) for n, t, src in cards if n == o['num'] and t != o['team']]
        used += [(t, 'ledger:%d slug=%s' % (i, sl)) for n, t, sl, i in ledger_rows(ledger) if n == o['num'] and t != o['team']]
        if o['verb'] == 'check': used += [('?', 'branch:%s' % b) for n, b in branch_nums(root) if n == o['num']]
        if o['verb'] == 'lint':
            if not used: sys.exit(0)
            where = ' '.join('team=%s src=%s' % u for u in used[:3])
            if any(sha and git(root, 'cat-file', '-e', '%s:%s' % (sha, o['rel']), t=7)[0] is not None for sha in (m, s)):
                print('WARN 기존 겹침 1: 카드 번호 r%d 를 다른 팀도 씀(%s) — 재번호는 planner 판단' % (o['num'], where))
            else:
                print('BAD 카드 번호 r%d 가 다른 팀과 겹침(%s) — ft-card-number.sh next %s <slug> 로 새 번호' % (o['num'], where, o['team']))
            sys.exit(0)
        for t, src in used: print('USED r%d team=%s src=%s' % (o['num'], t, src))
        if used: sys.exit(1)
        print('FREE r%d team=%s' % (o['num'], o['team'])); sys.exit(0)
    tmax = max((n for n, _, _ in cards), default=0)
    bmax = max((x for x in branch_nums(root) if x[0] <= tmax + BRANCH_GAP), default=(0, '-'))
    os.makedirs(os.path.dirname(ledger), exist_ok=True)
    signal.signal(signal.SIGALRM, lambda *_: die('잠금', '7초 초과 %s.lock' % ledger))
    with open(ledger + '.lock', 'a') as lk:
        signal.alarm(7); fcntl.flock(lk, fcntl.LOCK_EX); signal.alarm(0)
        lmax = max((n for n, _, _, _ in ledger_rows(ledger)), default=0)
        n = max(tmax, bmax[0], lmax) + 1
        row = '%d\t%s\t%s\t%s\t%s\n' % (n, o['team'], o['slug'], os.environ.get('FT_SEAT') or '-', datetime.datetime.now().strftime('%Y-%m-%dT%H:%M:%S'))
        with open(ledger, 'a', encoding='utf-8') as f:
            f.write(row); f.flush(); os.fsync(f.fileno())
    print('ISSUED r%d team=%s slug=%s max=tree:%d,branch:%d(%s),ledger:%d' % (n, o['team'], o['slug'], tmax, bmax[0], bmax[1], lmax))

main()
PY
