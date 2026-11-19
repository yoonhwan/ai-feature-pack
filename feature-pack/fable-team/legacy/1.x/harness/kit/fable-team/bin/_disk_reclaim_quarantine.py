# _disk_reclaim_quarantine.py — ft-disk-reclaim.sh 의 worktree «격리 이동 · 마무리»(r2301 A2 · A2b · A3 · A4)를 옆 파일로 뗌.
#   m = 부르는 쪽 모듈(run · E · under · panes). 격리 자리 = <git common dir>/ft-reclaim-q/ · 표식 = <git common dir>/ft-reclaim-q.tsv(리포마다 고정 파일 1개 · 격리 worktree 안에 쓰지 않는다).
#   A2: 판정이 끝난 worktree 는 지우기 전에 격리 자리로 «먼저 옮기고» 거기서 지운다 — 지우기가 상한에 끊겨도 반쯤 지운 것이 원래 자리에 안 남는다(실사건 11-19).
#   A3: apply 는 들어온 목록과 무관하게 표식 파일을 먼저 훑어 마무리한다 — 예외 1개 = `git worktree remove --force <격리 경로>`(ⓐ 표식 ⓑ HEAD = 표식 HEAD ⓒ status D 줄뿐 ⓓ pane·열린 파일 0).
#   A4: 크기 상한(FT_RECLAIM_MOVE_ONLY_KIB · 기본 1GiB)을 넘는 줄은 옮기기까지만(«MOVED · 지우기 다음 차례»).
import os, time

_G = {}
_c = None

def _num(x):
    try: return int(x)
    except (TypeError, ValueError): return 0

def cap(m):   # A4 크기 상한(KiB) — 숫자가 아니면 기본값
    global _c
    if _c is None: _c = _num(m.E.get("FT_RECLAIM_MOVE_ONLY_KIB", "1048576"))
    return _c

def dirs(m, repo):   # (격리 자리, 표식 파일) · 못 읽으면 (None, None)
    if repo not in _G:
        rc, out = m.run(["git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir"])
        g = os.path.realpath(out.strip()) if rc == 0 and out.strip() else None
        _G[repo] = (os.path.join(g, "ft-reclaim-q"), os.path.join(g, "ft-reclaim-q.tsv")) if g else (None, None)
    return _G[repo]

def home(m, repo, rp):   # 격리 자리 안이면 «격리 자리» (목록 후보도 지우기 대상도 아니다) · 아니면 None
    qd = dirs(m, repo)[0]
    return "격리 자리" if qd and (rp == qd or rp.startswith(qd + "/")) else None

def rows(m, repo):   # 표식 줄 = [원래 경로, 격리 경로, HEAD 40자, 판정 시각] · 못 읽으면 []
    try: return [l.split("\t") for l in open(dirs(m, repo)[1]).read().splitlines() if l.count("\t") == 3]
    except (OSError, TypeError): return []

def _add(m, repo, orig, qp, head):   # 이동 «전»에 표식 1줄 — 중간에 끊겨도 다음 apply 가 정체를 안다
    try:
        with open(dirs(m, repo)[1], "a") as fh: fh.write(f"{orig}\t{qp}\t{head}\t{int(time.time())}\n")
        return True
    except (OSError, TypeError): return False

def _drop(m, repo, qp):   # 그 격리 줄만 지운다(다른 줄 · 다른 리포 표식 그대로)
    f = dirs(m, repo)[1]
    try: lines = open(f).read().splitlines()
    except (OSError, TypeError): return
    keep = [l for l in lines if l.count("\t") != 3 or l.split("\t")[1] != qp]
    if len(keep) == len(lines): return
    try:
        t = f + ".tmp"
        with open(t, "w") as fh: fh.write("".join(l + "\n" for l in keep))
        os.replace(t, f)
    except OSError: pass

def _place(m, repo, p):   # 격리 자리 경로 — <git common dir>/ft-reclaim-q/<이름>(이름이 겹치면 -2 · -3)
    qd = dirs(m, repo)[0]
    if not qd: return None
    try: os.makedirs(qd, exist_ok=True)
    except OSError: return None
    base = os.path.basename(os.path.realpath(p)) or "wt"
    for i in range(1, 100):
        c = os.path.join(qd, base if i == 1 else f"{base}-{i}")
        if not os.path.exists(c) and not os.path.islink(c): return c
    return None

def _dlines(out):   # A3 ⓒ status --porcelain 이 «D 줄뿐» 인가(0줄도 참 · M·A·R·?? 0)
    return all(l.strip() and set(l[:2]) <= set("D ") for l in out.splitlines())

def _done(m, repo, qp, head, op):   # A3 조건 — None = 마무리해도 된다 · "DONE" = 끝난 꼴 · 그 밖 = SKIP 사유
    if not os.path.isdir(qp): return "DONE"   # 표식 있음 ∧ 격리 폴더 없음(영원한 SKIP 0)
    if len(head) != 40: return "격리 마무리 조건"
    if not os.path.isfile(os.path.join(qp, ".git")):   # isfile 먼저 — .git 이 없으면 격리 경로에 git -C 를 부르지 않는다(주 리포 HEAD 를 rc0 으로 내는 함정)
        m.run(["git", "-C", repo, "worktree", "repair", qp])   # rc 는 안 본다(rc 1 이어도 .git 을 되살린다) — «.git 있음 ∧ HEAD = 표식» 으로 판정
        if not os.path.isfile(os.path.join(qp, ".git")): return "격리 마무리 조건"
    rc, out = m.run(["git", "-C", qp, "rev-parse", "HEAD"])
    if rc or out.strip()[:40] != head: return "격리 마무리 조건"                                        # ⓑ
    rc, out = m.run(["git", "-C", qp, "status", "--porcelain"])
    if rc or not _dlines(out): return "격리 마무리 조건"                                              # ⓒ
    rp = os.path.realpath(qp)
    if m.under(rp, m.panes()): return "격리 마무리 조건"                                             # ⓓ 마무리 직전 다시 판정
    op.refresh()
    if op.hit(rp) or op.hit(qp): return "격리 마무리 조건"
    return None

def finish(m, repo, L, op):   # A3: 리포 표식 파일을 훑어 격리 자리를 마무리한다 → (지운 수, 건너뛴 수)
    d = s = 0
    qd = dirs(m, repo)[0]
    if not qd: return 0, 0
    mrk = rows(m, repo); marked = set(r[1] for r in mrk)
    for orig, qp, head, _t in mrk:
        why = _done(m, repo, qp, head, op)
        if why == "DONE":
            L.write(f"DONE\tworktree\tqp={qp}\t격리 폴더 없음 orig={orig}\n"); _drop(m, repo, qp); continue
        if not why:
            rc = m.run(["git", "-C", repo, "worktree", "remove", "--force", qp])[0]   # A3 예외 1개 — 이 줄 밖 --force 0
            why = "시간 초과" if rc == 124 else "지우기 실패" if rc else None
        if why: L.write(f"SKIP\tworktree\t{orig}\t{why}\n"); s += 1
        else: L.write(f"DELETED\tworktree\t-\t{orig}\n"); _drop(m, repo, qp); d += 1
        L.flush()
    try: names = sorted(os.listdir(qd))
    except OSError: names = []
    for n in names:   # 표식 없는 격리 worktree = 손으로 옮겨 넣은 것 — 지우기 0(A3)
        p = os.path.join(qd, n)
        if p in marked or not os.path.isdir(p): continue
        L.write(f"SKIP\tworktree\t{p}\t표식 없음\n"); s += 1
    return d, s

def carry(m, repo, p, head, kib):   # A2·A4: 판정이 끝난 worktree 를 격리 자리로 옮기고 거기서 지운다 → ("done"|"moved"|"skip", 사유)
    qp = _place(m, repo, p)
    if not qp: return "skip", "격리 자리 판정 불가"
    if len(head) != 40: return "skip", "판정 불가"
    if not _add(m, repo, p, qp, head): return "skip", "표식 쓰기 실패"
    if m.run(["git", "-C", repo, "worktree", "move", p, qp])[0] != 0:
        _drop(m, repo, qp); return "skip", "지우기 실패"
    if _num(kib) > cap(m): return "moved", None   # A4: 남은 예산으로 못 끝낼 큰 줄 = 옮기기까지만("MOVED · 지우기 다음 차례")
    rc = m.run(["git", "-C", repo, "worktree", "remove", qp])[0]
    if rc: return "skip", ("시간 초과" if rc == 124 else "지우기 실패")
    _drop(m, repo, qp); return "done", None
