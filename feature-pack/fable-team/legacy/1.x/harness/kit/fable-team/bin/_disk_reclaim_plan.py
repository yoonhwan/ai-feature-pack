# _disk_reclaim_plan.py — ft-disk-reclaim.sh 의 plan(r2277 에 옆 파일로 뗌 · 동작 그대로).
#   m = 부르는 쪽 모듈(Opened · panes · tick · keep · entry_bad · du · REPOS · wt_list · wt_bad · E · HOME · BYZ).
import os

def plan(m, outdir, roots):
    op, pn, rows, hold, n = m.Opened(), m.panes(), {"tmp": [], "cache": [], "worktree": []}, [], 0
    for kind, r in roots.items():
        for name in sorted(os.listdir(r)):
            n += 1; m.tick(n); p = r + "/" + name
            if not m.keep(p): continue
            if m.entry_bad(p, kind, op) is None and (k := m.du(p)) is not None: rows[kind].append((k, p, "조건 전부"))
    for repo in m.REPOS:
        for i, w in enumerate(m.wt_list(repo)):
            n += 1; m.tick(n)
            if not m.keep(os.path.realpath(w["path"])): continue
            bad = m.wt_bad(repo, w, i == 0, op, pn)
            tail = f" squash PR #{w['sq']}" if w.get("sq") else ""
            if bad: hold.append(f"hold\t-\t{w['path']}\t{bad}{tail}")
            elif (k := m.du(w["path"])) is not None: rows["worktree"].append((k, w["path"], "repo=" + repo + tail))
    info = m.E.get("FT_RECLAIM_INFO", f"{m.HOME}/.claude/projects:{roots['cache']}:{roots['tmp']}:{m.BYZ}/.worktrees:{m.BYZ}/.fable-team/teams")
    lines = [f"{k}\t{s}\t{p}\t{why}" for k in rows for s, p, why in sorted(rows[k], key=lambda x: -x[0])] + hold
    lines += [f"info\t{k if os.path.exists(p) and (k := m.du(p)) is not None else '?'}\t{p}\tinfo" for p in info.split(":") if p]
    os.makedirs(outdir, exist_ok=True); out = os.path.join(outdir, "candidates.tsv")
    with open(out, "w") as f: f.write("".join(l + "\n" for l in lines))
    cnt = " ".join(f"{k}={len(v)}/{sum(x[0] for x in v)}KiB" for k, v in rows.items())
    print(f"PLAN {out} {cnt} hold={len(hold)}")
