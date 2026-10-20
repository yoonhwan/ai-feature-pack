#!/usr/bin/env python3
"""ft_queue_bulk.py — 일괄 보류 판정기 (r530 · 오빠 결정 10-20 desk 쪽지 119482 «일괄 보류 절대금지»)

  ft_queue_bulk.py bulk-check --staged [--worktree] [--repo <dir>]   커밋 직전(스테이징 · --worktree = 작업 트리도 담는 커밋 -a)
  ft_queue_bulk.py bulk-check --range A..B [--repo <dir>]            착지 게이트(A 와 B 비교)
대상 = 큐(이름 AUTONOMY-QUEUE.md) 상태 칸(옛 «처리됨») · design/**/indices/**/*.md 카드의 «- 상태:» 줄.
옛 값(없으면 새 줄) → 새 값이 «보류» 인 것만 센다(풀기는 안 셈). 2개 이상 = rc1 «REJECT 일괄 보류 …» · 아니면 rc0 «OK 일괄 보류 <n>줄».
git 실패·인자 오류 = stderr ERROR + rc2. 읽기만 — 파일을 고쳐 쓰지 않는다. 큐 칸 판정 = ft_queue_state(같은 어휘 정본).
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_queue_state import STATE_COLS, ReadError, load_vocab, parse  # noqa: E402

QUEUE = "AUTONOMY-QUEUE.md"
CARD = re.compile(r"^design/(.+/)?indices/.+\.md$")
CARD_STATE = re.compile(r"^- 상태:\s*(.*)$", re.M)
HOLD = "보류"
USAGE = "usage: ft_queue_bulk.py bulk-check --staged [--worktree] | --range A..B  [--repo <dir>]"


class GitError(Exception):
    pass


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    if r.returncode:
        raise GitError(f"git {' '.join(args)}: {r.stderr.decode('utf-8', 'replace').strip()}")
    return r.stdout.decode("utf-8", "surrogateescape")


def blob(repo, spec):
    """<rev>:<경로> · :<경로>(스테이징) 내용 — 없으면 None(새 파일·지운 파일)"""
    r = subprocess.run(["git", "-C", repo, "cat-file", "-p", spec], capture_output=True)
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def name_status(out):
    """git diff --name-status -z 출력 → {새 경로: 옛 경로}(지운 파일 제외)"""
    toks, pairs, i = out.split("\0"), {}, 0
    while i < len(toks) and toks[i]:
        st = toks[i]
        if st[0] in "RC":
            pairs[toks[i + 2]] = toks[i + 1]
            i += 3
        else:
            if st[0] != "D":
                pairs[toks[i + 1]] = toks[i + 1]
            i += 2
    return pairs


def targets(repo, mode, rng, worktree):
    """[(새 경로, 옛 내용, 새 내용)] — 큐·카드만"""
    if mode == "range":
        a, _, b = rng.partition("..")
        if not a or not b:
            raise GitError(f"--range 꼴은 A..B: {rng}")
        pairs = name_status(git(repo, "diff", "--name-status", "-z", "-M", a, b))
        old, new = (lambda p: blob(repo, f"{a}:{p}")), (lambda p: blob(repo, f"{b}:{p}"))
    else:
        pairs = name_status(git(repo, "diff", "--cached", "--name-status", "-z", "-M"))
        top = git(repo, "rev-parse", "--show-toplevel").strip()
        wt = set()
        if worktree:
            wt = {p for p in git(repo, "diff", "--name-only", "-z").split("\0") if p}
            pairs.update({p: pairs.get(p, p) for p in wt})
        old = lambda p: blob(repo, f"HEAD:{p}")  # noqa: E731
        new = lambda p: _read(Path(top, p)) if p in wt else blob(repo, f":{p}")  # noqa: E731
    keep = [(n, o) for n, o in pairs.items() if Path(n).name == QUEUE or CARD.match(n)]
    return [(n, old(o), new(n)) for n, o in keep]


def _read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def queue_rows(text, vocab):
    """[(줄, 상태 밖 칸 묶음, 상태)] — 표·상태 칸을 못 읽으면 None (판정 = ft_queue_state.parse 그대로)"""
    if text is None:
        return None
    with tempfile.TemporaryDirectory() as d:
        p = Path(d, QUEUE)
        p.write_text(text, encoding="utf-8")
        try:
            rows, head_err = parse(p, vocab)
        except ReadError:
            return None
    if head_err:
        return None
    return [(r["line"], tuple((k, v) for k, v in r["cells"].items() if k not in STATE_COLS), r["state"]) for r in rows]


def queue_holds(path, old, new, vocab):
    rows = queue_rows(new, vocab)
    if rows is None:
        if new is not None:
            print(f"WARN 큐 표를 못 읽음(센 것 0): {path}", file=sys.stderr)
        return []
    pool = {}
    for _, key, st in queue_rows(old, vocab) or []:
        pool.setdefault(key, []).append(st)
    hits = []
    for line, key, st in rows:
        prev = pool[key].pop(0) if pool.get(key) else None
        if st == HOLD and prev != HOLD:
            hits.append(f"{Path(path).name}:{line}")
    return hits


def is_hold(text):
    m = CARD_STATE.search(text or "")
    return bool(m and re.match(rf"{HOLD}(?=$|[\s·—(:,])", m.group(1).strip()))


def check(repo, mode, rng=None, worktree=False):
    vocab = load_vocab()
    hits = []
    for path, old, new in targets(repo, mode, rng, worktree):
        if Path(path).name == QUEUE:
            hits += queue_holds(path, old, new, vocab)
        elif is_hold(new) and not is_hold(old):
            hits.append(Path(path).name)
    if len(hits) >= 2:
        print(f"REJECT 일괄 보류 {len(hits)}줄({','.join(hits)}) — 보류는 한 번에 한 줄 · 줄마다 사유·재확인 시각"
              " · 전팀 정지는 줄 대신 ft-spawn-hold.sh 정지 파일(«일시정지»)")
        return 1
    print(f"OK 일괄 보류 {len(hits)}줄")
    return 0


def main(argv):
    args, repo, mode, rng, worktree = argv[1:], ".", None, None, False
    if not args or args.pop(0) != "bulk-check":
        print(USAGE, file=sys.stderr)
        return 2
    while args:
        a = args.pop(0)
        if a == "--staged":
            mode = "staged"
        elif a == "--worktree":
            worktree = True
        elif a in ("--range", "--repo") and args:
            v = args.pop(0)
            rng, mode = (v, "range") if a == "--range" else (rng, mode)
            repo = v if a == "--repo" else repo
        else:
            print(USAGE, file=sys.stderr)
            return 2
    if mode is None:
        print(USAGE, file=sys.stderr)
        return 2
    try:
        return check(repo, mode, rng, worktree)
    except (GitError, ReadError) as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
