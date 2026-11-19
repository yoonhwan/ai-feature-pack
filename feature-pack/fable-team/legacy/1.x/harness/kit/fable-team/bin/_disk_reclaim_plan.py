# _disk_reclaim_plan.py — ft-disk-reclaim.sh 의 plan(r2277 에 옆 파일로 뗌).
#   m = 부르는 쪽 모듈(Opened · panes · tick · keep · entry_bad · du · run · T · ONLY · REPOS · wt_list · wt_bad · E · HOME · BYZ).
#   r2277 C1 info 기본값 = FT_RECLAIM_ONLY 가 있으면 그 경로들 · 없으면 기본 5경로 · FT_RECLAIM_INFO 를 주면 그 값.
#   r2277 C2 예산 = FT_RECLAIM_PLAN_SEC(기본 55초) · 시계 = 이 모듈을 읽은 때(프로세스 시작 · lsof · tmux · wt_list 시간 포함).
#     칸(tmp · cache · worktree 항목 · info 경로)마다 남은 예산 확인 · du · 판정 호출 상한 = min(T, 남은 예산).
#     예산에 잘린 칸은 훑은 수에 안 셈 · 그때까지 목록 + 끝 줄 «info\t-\t-\t부분 <훑은 수>/<전체 수> · 다음 = ONLY 좁힘» · stdout «… 부분 n/m» · rc 0.
import os, time
START = time.time()

class Budget(Exception): pass

def plan(m, outdir, roots):
    B, T0, run0 = float(m.E.get("FT_RECLAIM_PLAN_SEC", "55")), m.T, m.run
    left = lambda: START + B - time.time()
    def brun(cmd, t=T0, cwd=None):   # 호출 상한 = min(t, 남은 예산) · 예산에 잘리면 Budget
        if (rem := left()) <= 0: raise Budget
        rc, out = run0(cmd, min(t, rem), cwd)
        if rc == 124 and left() <= 0: raise Budget
        return rc, out
    op, pn, rows, hold, n, done, part = m.Opened(), m.panes(), {"tmp": [], "cache": [], "worktree": []}, [], 0, 0, False
    todo = [(kind, r + "/" + name, None) for kind, r in roots.items() for name in sorted(os.listdir(r))]
    todo += [("wt", repo, (i, w)) for repo in m.REPOS for i, w in enumerate(m.wt_list(repo))]
    kept = lambda x: m.keep(os.path.realpath(x[2][1]["path"]) if x[2] else x[1])
    tot = sum(1 for x in todo if kept(x))
    info = m.E.get("FT_RECLAIM_INFO", ":".join(m.ONLY) if m.ONLY else
                   f"{m.HOME}/.claude/projects:{roots['cache']}:{roots['tmp']}:{m.BYZ}/.worktrees:{m.BYZ}/.fable-team/teams")
    ilines, m.run = [], brun
    try:
        for x in todo:
            n += 1; m.tick(n)
            if not kept(x): continue
            m.T = min(T0, left())   # old_enough 안 훑기 상한도 남은 예산
            if m.T <= 0: raise Budget
            got = one(m, x, op, pn)
            if left() <= 0: raise Budget
            if got: (hold if got[0] == "hold" else rows[got[0]]).append(got[1])
            done += 1
        for p in (p for p in info.split(":") if p):
            if left() <= 0: raise Budget
            k = m.du(p) if os.path.exists(p) else None
            if left() <= 0: raise Budget
            ilines.append(f"info\t{k if k is not None else '?'}\t{p}\tinfo")
    except Budget: part = True
    finally: m.run, m.T = run0, T0
    lines = [f"{k}\t{s}\t{p}\t{why}" for k in rows for s, p, why in sorted(rows[k], key=lambda x: -x[0])] + hold + ilines
    lines += [f"info\t-\t-\t부분 {done}/{tot} · 다음 = ONLY 좁힘"] if part else []
    os.makedirs(outdir, exist_ok=True); out = os.path.join(outdir, "candidates.tsv")
    with open(out, "w") as f: f.write("".join(l + "\n" for l in lines))
    cnt = " ".join(f"{k}={len(v)}/{sum(x[0] for x in v)}KiB" for k, v in rows.items())
    print(f"PLAN {out} {cnt} hold={len(hold)}" + (f" 부분 {done}/{tot}" if part else ""))

def one(m, x, op, pn):   # 칸 1개 → ("tmp" | "cache" | "worktree", (KiB, 경로, 근거)) · ("hold", 줄) · None
    kind, p, iw = x
    if not iw:
        return (kind, (k, p, "조건 전부")) if m.entry_bad(p, kind, op) is None and (k := m.du(p)) is not None else None
    (i, w), repo = iw, p
    bad = m.wt_bad(repo, w, i == 0, op, pn)
    tail = f" squash PR #{w['sq']}" if w.get("sq") else ""
    if bad: return "hold", f"hold\t-\t{w['path']}\t{bad}{tail}"
    return ("worktree", (k, w["path"], "repo=" + repo + tail)) if (k := m.du(w["path"])) is not None else None
