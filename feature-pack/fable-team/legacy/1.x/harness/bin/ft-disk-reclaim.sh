#!/usr/bin/env bash
# ft-disk-reclaim.sh plan <산출 폴더> | apply <candidates.tsv>  (r2107) — 디스크 정리: 목록을 먼저 내고, 목록에 있는 줄만 지운다.
#   plan  = <산출 폴더>/candidates.tsv 1파일만 쓴다(그 밖의 쓰기·지우기 0). 줄 = <종류>\t<KiB>\t<경로>\t<근거>
#           종류 tmp · cache · worktree(지울 후보 · 종류 안 크기 큰 순) · hold(조건 하나가 어긋난 worktree · 처음 어긋난 조건) · info(크기 참고).
#   apply = 목록의 tmp · cache · worktree 줄만 위에서부터 · 줄마다 지우기 직전 조건 전부 다시 판정 → 어긋나면 SKIP.
#           tmp · cache = «뿌리 실경로/이름 한 마디» 일 때만 `rm -rf --` · worktree = 그 리포 목록에 있을 때만 `git worktree remove`(--force 0).
#           로그 = 목록과 같은 폴더 deleted.log(DELETED · SKIP 줄 + SUMMARY 또는 ABORT).
#   조건: tmp = 소유자 본인 · 심링크 아님 · 안의 모든 mtime 이 7일 넘음 · 열린 파일 0 · 이름에 탭/줄바꿈 0 / cache = 심링크 아님 · 열린 파일 0 · 이름
#         worktree = 주 아님 · LIVE_ROOT 아님(r2242 · 공용 루트 .fable-team/LIVE_ROOT 1행과 samefile) · locked 아님 · 폴더 있음 · HEAD ⊂ origin/main · status 0줄 · push 안 된 커밋 0 · tmux pane 0 · 열린 파일 0 · index 24시간 넘음
#   지우지 않는 것: 목록 밖 · 뿌리 밖 · 심링크가 가리키는 곳 · 가지 · prune · sudo. 뿌리 실경로가 / 또는 홈이면 rc 2.
#   판정 불가: lsof · tmux · git worktree list · df 가 rc≠0 또는 시간 초과 → `판정 불가 <명령>` · rc 3 · plan 은 목록 0 · apply 는 ABORT 줄 뒤 지우기 0.
#   env: FT_RECLAIM_TMP_ROOT(/private/tmp) · FT_RECLAIM_CACHE_ROOT(~/Library/Caches) · FT_RECLAIM_REPOS(: 구분 · BYZ · 팩)
#        FT_RECLAIM_INFO(: 구분) · FT_RECLAIM_DF_PATH(/System/Volumes/Data) · FT_RECLAIM_TIMEOUT(25초 · 지우기 호출 포함)
#        FT_RECLAIM_ONLY(: 구분 경로 접두 · r2200) = plan 이 실경로로 풀어 그 접두 아래(같거나 «접두/») tmp · cache · worktree 만 잰다 · 없거나 비면 전부
#   지우기가 상한을 넘기면 그 줄 SKIP `시간 초과`(큰 폴더는 다음 apply 로 · rm 이 중간까지 지웠을 수 있음)
#   r2196 squash 길 = 옆 파일 _disk_reclaim_squash.py(r2199) · apply 쪽 dfree · recheck = _disk_reclaim_apply.py(r2200) · 못 읽으면 stderr `판정 불가 squash 모듈` · rc 3 · apply 는 ABORT 줄 뒤 지우기 0.
set -uo pipefail
case "${1:-}" in plan|apply) [ $# -eq 2 ] || { echo "usage: $0 plan <산출 폴더> | apply <candidates.tsv>" >&2; exit 2; } ;;
  *) echo "usage: $0 plan <산출 폴더> | apply <candidates.tsv>" >&2; exit 2 ;; esac
exec python3 - "$@" "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)" <<'PY'
import bisect, json, os, stat, subprocess, sys, time
MODE, ARG = sys.argv[1], sys.argv[2]
sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[3])   # r2199 · bin/__pycache__ 쓰기 0
try: import _disk_reclaim_squash as SQ, _disk_reclaim_apply as AP   # r2196 squash 길(merged · squash_pr · GH · MERGED) · r2200 dfree · recheck = 옆 파일
except Exception: MODE == "apply" and open(os.path.join(os.path.dirname(os.path.abspath(ARG)), "deleted.log"), "a").write("ABORT 판정 불가 squash 모듈 deleted=0 skipped=0\n"); print("판정 불가 squash 모듈", file=sys.stderr); sys.exit(3)
E = os.environ
HOME = os.path.realpath(os.path.expanduser("~"))
BYZ = HOME + "/Project/Agent/BYZ-Work/BYZ-Agents"
T = float(E.get("FT_RECLAIM_TIMEOUT", "25"))
REPOS = [r for r in E.get("FT_RECLAIM_REPOS", BYZ + ":" + HOME + "/Project/ai-feature-pack").split(":") if r]
DFP = E.get("FT_RECLAIM_DF_PATH", "/System/Volumes/Data")
ONLY = [os.path.realpath(x) for x in E.get("FT_RECLAIM_ONLY", "").split(":") if x]   # r2200 plan 경로 접두
def keep(p): return not ONLY or p in ONLY or any(p.startswith(o + "/") for o in ONLY)   # 낱말 경계 = «접두/»

class Abort(Exception): pass

def run(cmd, t=T, cwd=None):   # (rc, stdout) · 시간 초과 = 124 · 실행 못 함 = 127
    try: p = subprocess.run(cmd, capture_output=True, text=True, errors="surrogateescape", timeout=t, cwd=cwd, env=dict(E, GIT_OPTIONAL_LOCKS="0"))
    except subprocess.TimeoutExpired: return 124, ""
    except OSError: return 127, ""
    return p.returncode, p.stdout
def must(cmd, name):
    rc, out = run(cmd)
    if rc != 0: raise Abort(name)
    return out
def root(env, default):
    r = os.path.realpath(E.get(env, default))
    if r in ("/", HOME): print(f"REJECT 뿌리 실경로 {r} = / 또는 홈 — 쓰기 0", file=sys.stderr); sys.exit(2)
    return r
class Opened:   # lsof 스냅샷 · 60초보다 오래되면 새로
    def __init__(s): s.refresh()
    def refresh(s):
        out = must(["lsof", "-nP", "-F", "n"], "lsof")
        s.paths = sorted(l[1:] for l in out.splitlines() if l.startswith("n/")); s.t = time.time()
    def hit(s, p):   # <경로> 같음 또는 <경로>/ 접두
        if time.time() - s.t > 60: s.refresh()
        i = bisect.bisect_left(s.paths, p)
        while i < len(s.paths) and s.paths[i].startswith(p):
            if s.paths[i] == p or s.paths[i].startswith(p + "/"): return True
            i += 1
        return False

def panes(): return [os.path.realpath(l) for l in must(["tmux", "list-panes", "-a", "-F", "#{pane_current_path}"], "tmux").splitlines() if l]
def under(p, xs): return any(x == p or x.startswith(p + "/") for x in xs)
def du(p):
    rc, out = run(["du", "-sk", p])
    try: return int(out.split()[0]) if rc in (0, 1) else None
    except (ValueError, IndexError): return None

def old_enough(p, st, lim):   # 항목과 그 안의 모든 mtime < lim · 안 훑기 T초 넘으면 아님
    if st.st_mtime >= lim: return False
    if not stat.S_ISDIR(st.st_mode): return True
    end, err = time.time() + T, []
    for d, ds, fs in os.walk(p, onerror=err.append):
        if err or time.time() > end: return False
        for n in ds + fs:
            try:
                if os.lstat(os.path.join(d, n)).st_mtime >= lim: return False
            except OSError: return False
    return not err

def entry_bad(p, kind, op):   # tmp · cache 어긋난 조건 · None = 후보
    name = os.path.basename(p)
    if "\t" in name or "\n" in name: return "이름"
    try: st = os.lstat(p)
    except OSError: return "없음"
    if stat.S_ISLNK(st.st_mode): return "심링크"
    if kind == "tmp":
        if st.st_uid != os.getuid(): return "소유자"
        if not old_enough(p, st, time.time() - 7 * 86400): return "나이"
    if op.hit(p): return "열린 파일"
    return None

def wt_list(repo):   # [{path, head, flags}] · 첫 항목 = 주 worktree
    res = []
    for l in must(["git", "-C", repo, "worktree", "list", "--porcelain"], "git worktree list").splitlines():
        if l.startswith("worktree "): res.append({"path": l[9:], "head": "", "flags": set()})
        elif res and l.startswith("HEAD "): res[-1]["head"] = l[5:]
        elif res and l: res[-1]["flags"].add(l.split()[0])
        if res and l.startswith("branch "): res[-1]["branch"] = l[7:]
    return res

def index_mtime(p):
    try:
        g = open(os.path.join(p, ".git")).read().strip()
        g = g[8:] if g.startswith("gitdir: ") else None
        return os.stat(os.path.join(p, g, "index")).st_mtime if g else None
    except OSError: return None

def live_root(repo, p):   # r2242 · <공용 루트>/.fable-team/LIVE_ROOT 1행과 같은 폴더(장치 · inode) · git 실패 = "판정 불가" · 파일 없음 · 못 읽음 · 절대경로 아님 · stat 실패 = None
    rc, g = run(["git", "-C", repo, "rev-parse", "--path-format=absolute", "--git-common-dir"])
    if rc or not g.strip(): return "판정 불가"
    g = g.strip(); g = g[:-5] if g.endswith("/.git") else g
    try:
        v = open(os.path.join(g, ".fable-team", "LIVE_ROOT")).read().split("\n")[0].strip("\r")
        return "LIVE_ROOT" if v.startswith("/") and os.path.samefile(p, v) else None
    except (OSError, ValueError): return None

def wt_bad(repo, w, main, op, pn):   # 처음 어긋난 조건 · None = 후보
    p = w["path"]; rp = os.path.realpath(p)
    if main: return "주 worktree"
    if (lr := live_root(repo, p)): return lr
    if "locked" in w["flags"]: return "locked"
    if not os.path.isdir(p): return "폴더 없음"
    idx = index_mtime(p)
    rc, _ = run(["git", "-C", repo, "merge-base", "--is-ancestor", w["head"] or "-", "origin/main"])
    if rc not in (0, 1): return "판정 불가"
    w["sq"] = SQ.squash_pr(repo, w, run, T) if rc == 1 else None
    if rc == 1 and not w["sq"]: return "조상 아님"
    rc, out = run(["git", "-C", p, "status", "--porcelain"])
    if rc: return "판정 불가"
    if out.strip(): return "수정 파일"
    rc, out = run(["git", "-C", p, "rev-list", "--count", "HEAD", "--not", "--remotes"])
    if rc: return "판정 불가"
    if out.strip() != "0": return "push 안 된 커밋"
    if under(rp, pn) or under(p, pn): return "tmux pane"
    if op.hit(rp) or op.hit(p): return "열린 파일"
    if idx is None: return "판정 불가"
    if idx >= time.time() - 24 * 3600: return "index 최근"
    return None

def tick(n):
    if n % 100 == 0: print(f"진행 {n}", file=sys.stderr)

def plan(outdir, roots):
    op, pn, rows, hold, n = Opened(), panes(), {"tmp": [], "cache": [], "worktree": []}, [], 0
    for kind, r in roots.items():
        for name in sorted(os.listdir(r)):
            n += 1; tick(n); p = r + "/" + name
            if not keep(p): continue
            if entry_bad(p, kind, op) is None and (k := du(p)) is not None: rows[kind].append((k, p, "조건 전부"))
    for repo in REPOS:
        for i, w in enumerate(wt_list(repo)):
            n += 1; tick(n)
            if not keep(os.path.realpath(w["path"])): continue
            bad = wt_bad(repo, w, i == 0, op, pn)
            tail = f" squash PR #{w['sq']}" if w.get("sq") else ""
            if bad: hold.append(f"hold\t-\t{w['path']}\t{bad}{tail}")
            elif (k := du(w["path"])) is not None: rows["worktree"].append((k, w["path"], "repo=" + repo + tail))
    info = E.get("FT_RECLAIM_INFO", f"{HOME}/.claude/projects:{roots['cache']}:{roots['tmp']}:{BYZ}/.worktrees:{BYZ}/.fable-team/teams")
    lines = [f"{k}\t{s}\t{p}\t{why}" for k in rows for s, p, why in sorted(rows[k], key=lambda x: -x[0])] + hold
    lines += [f"info\t{k if os.path.exists(p) and (k := du(p)) is not None else '?'}\t{p}\tinfo" for p in info.split(":") if p]
    os.makedirs(outdir, exist_ok=True); out = os.path.join(outdir, "candidates.tsv")
    with open(out, "w") as f: f.write("".join(l + "\n" for l in lines))
    cnt = " ".join(f"{k}={len(v)}/{sum(x[0] for x in v)}KiB" for k, v in rows.items())
    print(f"PLAN {out} {cnt} hold={len(hold)}")

def apply(tsv, roots):
    log = os.path.join(os.path.dirname(os.path.abspath(tsv)), "deleted.log")
    rows = [l.split("\t") for l in open(tsv).read().splitlines()]
    d = s = 0
    with open(log, "a") as L:
        try:
            before, op = AP.dfree(sys.modules[__name__]), Opened()
            for n, f in enumerate(rows, 1):
                tick(n)
                if not f or f[0] not in ("tmp", "cache", "worktree"): continue
                if len(f) != 4: L.write(f"SKIP\t{f[0]}\t-\t줄 꼴\n"); s += 1; continue
                kind, kib, p = f[0], f[1], f[2]
                why, repo = AP.recheck(sys.modules[__name__], kind, p, roots, op)
                if not why:
                    cmd = ["git", "-C", repo, "worktree", "remove", p] if repo else ["rm", "-rf", "--", p]
                    rc = run(cmd)[0]
                    why = "시간 초과" if rc == 124 else "지우기 실패" if rc else None
                if why: L.write(f"SKIP\t{kind}\t{p}\t{why}\n"); s += 1
                else: L.write(f"DELETED\t{kind}\t{kib}\t{p}\n"); d += 1
                L.flush()
            after = AP.dfree(sys.modules[__name__])
        except Abort as a:
            L.write(f"ABORT 판정 불가 {a} deleted={d} skipped={s}\n"); print(f"판정 불가 {a}", file=sys.stderr); sys.exit(3)
        line = f"SUMMARY freed_gib={(after - before) / 1048576:.1f} before_kib={before} after_kib={after} deleted={d} skipped={s}"
        L.write(line + "\n"); print(line)

roots = {"tmp": root("FT_RECLAIM_TMP_ROOT", "/private/tmp"), "cache": root("FT_RECLAIM_CACHE_ROOT", HOME + "/Library/Caches")}
try:
    plan(ARG, roots) if MODE == "plan" else apply(ARG, roots)
except Abort as a:
    print(f"판정 불가 {a}", file=sys.stderr); sys.exit(3)
PY
