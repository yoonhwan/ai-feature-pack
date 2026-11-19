# _disk_reclaim_apply.py — ft-disk-reclaim.sh 의 apply 쪽 dfree · recheck(r2200 에 옆 파일로 뗌 · 동작 그대로).
#   m = 부르는 쪽 모듈(must · DFP · Abort · entry_bad · REPOS · wt_list · wt_bad · panes).
#   r2301: recheck 가 worktree 줄의 HEAD(40자)도 같이 낸다 — apply 가 격리 표식(원래 경로 · 격리 경로 · HEAD · 시각)을 쓰는 데 쓴다.

def dfree(m):
    try: return int(m.must(["df", "-k", m.DFP], "df").splitlines()[-1].split()[3])
    except (ValueError, IndexError): raise m.Abort("df")

def recheck(m, kind, p, roots, op):   # (사유 | None, 리포, HEAD 40자 | "")
    if kind in roots:
        r = roots[kind]; name = p[len(r) + 1:] if p.startswith(r + "/") else ""
        if not name or "/" in name or name in (".", ".."): return "범위 밖", None, ""
        return m.entry_bad(p, kind, op), None, ""
    for repo in m.REPOS:
        ws = m.wt_list(repo)
        for i, w in enumerate(ws):
            if w["path"] == p: return m.wt_bad(repo, w, i == 0, op, m.panes()), repo, w.get("head") or ""
    return "범위 밖 리포", None, ""
