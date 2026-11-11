#!/usr/bin/env bash
# ft-land-overlap.sh <PR번호|가지|sha> [--target main|ops/main-base] [--repo <dir>] [--seats-dir <dir>] [--no-fetch] [--base <main sha> <ops sha|->]   (r1695 · Issue #8363)
#   같은 파일 사전 경고 — 읽기 전용 · 경고만(착지를 막지 않는다 · 막기는 merge-land 의 non-FF 거절 그대로).
#   첫 줄 = «BASE main=<sha40> ops=<sha40|없음>»(ft-lead-wt-status.sh 와 같은 고정 · 이후 판정은 그 sha 로만).
#   선행 착지 겹침 = 후보가 바꾼 파일 ∩ (merge-base(후보, 대상 BASE) 이후 대상 BASE 가 바꾼 파일).
#   동시 작업 겹침 = 후보가 바꾼 파일 ∩ 다른 열린 팀장 가지가 바꾼 파일(ft-lead-wt-status.sh --json 의 팀장 행 · 후보 자신 제외).
#   대상: --target 이 없으면 BASE 두 sha 중 behind 작은 쪽(같으면 main) — 집계 도구와 같은 규칙.
#   둘째 줄 = «TARGET <대상> <sha> merge-base=<sha> candidate=<sha> files=<n>»(독립 대조용).
#   마지막 줄 = «OVERLAP <n> landed=<파일,…|-> open=<좌석:파일,…|->» rc 1 · «CLEAR» rc 0 · 2 = usage · 3 = 판정 불가 <칸> <사유>.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
FT_LEAD_STATUS="${FT_LEAD_STATUS:-$HERE/ft-lead-wt-status.sh}" exec python3 - "$@" <<'PY'
import json, os, subprocess, sys

USAGE = "usage: ft-land-overlap.sh <PR번호|가지|sha> [--target main|ops/main-base] [--repo <dir>] [--seats-dir <dir>] [--no-fetch] [--base <main sha> <ops sha|->]"

def git(repo, *a, t=25):
    try:
        p = subprocess.run(['git', '-c', 'core.quotePath=false', '-C', repo, *a], capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired:
        return None, 'timeout %ss' % t
    return (p.stdout if p.returncode == 0 else None), (p.stderr.strip().splitlines() or ['rc=%d' % p.returncode])[-1]

def die(cell, why):
    print('판정 불가 %s %s' % (cell, why)); sys.exit(3)

def args():
    a = sys.argv[1:]; o = {'cand': None, 'target': None, 'repo': os.getcwd(), 'seats': None, 'fetch': True, 'base': None}
    while a:
        x = a.pop(0)
        if x == '--no-fetch': o['fetch'] = False
        elif x == '--target' and a and a[0] in ('main', 'ops/main-base'): o['target'] = a.pop(0)
        elif x in ('--repo', '--seats-dir') and a: o['repo' if x == '--repo' else 'seats'] = a.pop(0)
        elif x == '--base' and len(a) >= 2: o['base'] = [a.pop(0), a.pop(0)]
        elif not x.startswith('-') and o['cand'] is None: o['cand'] = x
        else: print(USAGE, file=sys.stderr); sys.exit(2)
    if o['cand'] is None: print(USAGE, file=sys.stderr); sys.exit(2)
    return o

def status(o, root):
    cmd = ['bash', os.environ['FT_LEAD_STATUS'], '--json', '--repo', root]
    cmd += ['--base', *o['base']] if o['base'] else ([] if o['fetch'] else ['--no-fetch'])
    if o['seats']: cmd += ['--seats-dir', o['seats']]
    try: p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired: die('집계', 'timeout 60s')
    lines = p.stdout.split('\n')
    if p.returncode not in (0, 3) or len(lines) < 2 or not lines[0].startswith('BASE '):
        die('집계', (lines[0] if lines and lines[0] else 'rc=%d' % p.returncode))
    return lines[0], json.loads(lines[1])

def candidate(root, x, fetch):
    if x.isdigit() and len(x) <= 6:
        ref = 'refs/pull/%s/head' % x
        out, why = None, ''
        for _ in range(2):
            out, why = git(root, 'ls-remote', 'origin', ref, t=7)
            if out is not None: break
        if not out: die('후보', 'PR #%s head 없음 %s' % (x, why))
        sha = out.split()[0]
        if git(root, 'cat-file', '-e', sha + '^{commit}', t=7)[0] is None:
            if not fetch: die('후보', 'PR #%s head %s 로컬 객체 없음(--no-fetch)' % (x, sha[:10]))
            ok = None
            for _ in range(2):
                ok, why = git(root, '-c', 'gc.auto=0', 'fetch', '-q', '--no-write-fetch-head', 'origin', ref, t=25)
                if ok is not None: break
            if ok is None: die('후보', 'PR #%s fetch %s' % (x, why))
        return sha, None
    for r in (x, 'refs/remotes/origin/' + x):
        out, _ = git(root, 'rev-parse', '--verify', '-q', r + '^{commit}', t=7)
        if out: return out.strip(), (None if out.strip().startswith(x) else x)   # sha 로 준 후보 = 가지 이름 없음
    die('후보', '%s 를 커밋으로 풀 수 없음' % x)

def files(root, a, b):
    out, why = git(root, 'diff', '--name-only', '--no-renames', a, b)
    if out is None: die('바꾼파일', why)
    return {f for f in out.split('\n') if f}

def main():
    o = args()
    out, why = git(o['repo'], 'rev-parse', '--path-format=absolute', '--git-common-dir', t=7)
    if out is None: die('repo', why)
    d = out.strip(); root = os.path.dirname(d) if os.path.basename(d) == '.git' else d
    base_line, st = status(o, root)
    print(base_line, flush=True)
    base = st['base']
    cand, cbranch = candidate(root, o['cand'], o['fetch'])
    tgt = o['target']
    if tgt is None:
        basis = {}
        for k, sha in base.items():
            if not sha: continue
            c, why = git(root, 'rev-list', '--count', '%s..%s' % (cand, sha))
            if c is None: die('behind', why)
            basis[k] = int(c.strip())
        tgt = min(basis, key=lambda k: (basis[k], k != 'main'))
    tsha = base.get(tgt)
    if not tsha: die('대상', '%s BASE 없음' % tgt)
    mb, why = git(root, 'merge-base', cand, tsha)
    if mb is None: die('merge-base', why)
    mb = mb.strip()
    mine = files(root, mb, cand)
    print('TARGET %s %s merge-base=%s candidate=%s files=%d' % (tgt, tsha, mb, cand, len(mine)), flush=True)
    landed = sorted(mine & files(root, mb, tsha))
    opened = []
    for r in st['worktrees']:
        if r.get('kind') != '팀장' or r.get('head') == cand or (cbranch and r.get('branch') == cbranch): continue
        if r.get('files') is None: die('동시작업', '%s 바꾼 파일 판정 불가' % r['path'])
        for f in sorted(mine & set(r['files'])): opened.append(('+'.join(r['seats']), f))
    n = len(set(landed) | {f for _, f in opened})
    if n == 0: print('CLEAR'); sys.exit(0)
    print('OVERLAP %d landed=%s open=%s' % (n, ','.join(landed) or '-', ','.join('%s:%s' % p for p in opened) or '-'))
    sys.exit(1)

main()
PY
