# _disk_reclaim_squash.py — ft-disk-reclaim.sh 의 r2196 squash 길(r2199 에 옆 파일로 뗌 · 동작 그대로).
#   «조상 아님» 이어도 가지 = MERGED PR(base main) headRefName 정확히 1건 · HEAD = headRefOid · 착지 커밋 로컬 있음 ·
#   착지 커밋이 바꾼 파일 전부 HEAD 와 같음 → 조건 통과 · 줄 끝 « squash PR #N». 조회 = 리포마다 1회(FT_RECLAIM_GH · gh --limit 500 · 7초 + 재시도 1)
#   실패 → 그 리포 squash 길 0 · stderr `squash 길 판정 불가 <리포> rc=<rc>`.
#   run · T 는 부르는 쪽이 인자로 넘긴다(run(cmd, t, cwd) → (rc, stdout)).
import json, os, sys
E = os.environ

GH, MERGED = E.get("FT_RECLAIM_GH", "gh"), {}
def merged(repo, run, T):   # r2196 D1 · 리포마다 MERGED PR 목록 1회 · None = 판정 불가(squash 길 0)
    if repo not in MERGED:
        cmd = [GH, "pr", "list", "--state", "merged", "--limit", "500", "--json", "number,headRefName,headRefOid,baseRefName,mergeCommit"]
        for _ in range(2):
            rc, out = run(cmd, min(T, 7), repo)
            if rc == 0: break
        try: v = json.loads(out) if rc == 0 else None
        except ValueError: rc, v = "json", None
        MERGED[repo] = v if isinstance(v, list) else None
        if MERGED[repo] is None: print(f"squash 길 판정 불가 {repo} rc={rc}", file=sys.stderr)
    return MERGED[repo]

def squash_pr(repo, w, run, T):   # r2196 D2 · squash 착지로 ⓑ 를 채우면 PR 번호 · 아니면 None
    b = w.get("branch", "")
    if not b.startswith("refs/heads/") or (prs := merged(repo, run, T)) is None: return None
    m = [x for x in prs if isinstance(x, dict) and x.get("headRefName") == b[11:]]
    if len(m) != 1: return None
    pr = m[0]; mc = (pr.get("mergeCommit") or {}).get("oid") or ""
    if pr.get("baseRefName") != "main" or not w["head"] or pr.get("headRefOid") != w["head"]: return None
    if len(mc) != 40 or mc.strip("0123456789abcdef") or run(["git", "-C", repo, "cat-file", "-e", mc + "^{commit}"])[0]: return None
    rc, out = run(["git", "-C", repo, "diff-tree", "-r", "-z", "--no-commit-id", "--name-only", mc])
    fs = [f for f in out.split("\0") if f]
    if rc or not fs: return None
    rc, _ = run(["git", "--literal-pathspecs", "-C", repo, "diff", "--quiet", w["head"], mc, "--", *fs])
    return pr.get("number") if rc == 0 else None
