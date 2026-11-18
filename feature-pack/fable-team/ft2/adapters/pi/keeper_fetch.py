"""ft 2.0 keeper fetch 대상 (r1975) — ① FETCH_TARGETS 판독 ⑥ 판정 대상 나노 가지 ⑦ 판정 뒤 전체 fetch 백그라운드(기다림 0 · 겹침 0).
keeper.py 가 부른다 · 판정 앞 fetch 자체(ls-remote 신선 · 시도마다 1줄)는 keeper.py fresh 그대로.
"""
import glob, importlib.util, os, re, subprocess, sys, time  # noqa: E401
HERE = os.path.dirname(os.path.abspath(__file__))
CAP, FETCH_S = 5, 7   # 리포당 지정 ref 상한 · 백그라운드도 1회 7초 + 재시도 1
MIN_S = 1   # r2122 C5 남은 몫 < 1초 = 판독 시작 0(keeper.MIN_S 와 같은 값)
_spec = importlib.util.spec_from_file_location("ft2_keeper_fetch_endings", os.path.join(HERE, "keeper_endings.py"))
ends = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ends)
CHILD = """import json, os, subprocess, sys, time
repo, pid, s, tries, rc = sys.argv[1], sys.argv[2], float(sys.argv[3]), [], None
for _ in range(2):
    at = time.monotonic()
    try:
        rc = subprocess.run(["git", "-C", repo, "fetch", "-q", "--no-tags", "origin"], capture_output=True, timeout=s).returncode
    except (OSError, subprocess.TimeoutExpired):
        rc = None
    tries.append("rc=%s s=%.1f" % (rc, time.monotonic() - at))
    if rc == 0:
        break
with open(pid[:-4] + ".json.tmp", "w", encoding="utf-8") as fh:
    json.dump({"ok": rc == 0, "tries": tries}, fh)
os.replace(pid[:-4] + ".json.tmp", pid[:-4] + ".json")
os.path.exists(pid) and os.unlink(pid)
"""


def targets(k):
    """① 줄마다 `<root|pack>\\t<ref …>`(빈 줄·# 무시) → {리포: [ref]} · 파일 없음 = {}(지금 기본) · 깨짐·모르는 별칭·빈 ref·빈 표 = None."""
    try:
        with open(os.path.join(k.dir, "FETCH_TARGETS"), encoding="utf-8") as fh:
            rows = [x.rstrip("\n") for x in fh if x.strip() and not x.lstrip().startswith("#")]
    except (OSError, UnicodeDecodeError) as exc:
        return {} if isinstance(exc, FileNotFoundError) else None
    table, repos = {}, {"root": k.root, "pack": k.pack}
    for alias, tab, names in (x.partition("\t") for x in rows):
        if alias.strip() not in repos or not tab or not names.split():
            return None
        table.setdefault(repos[alias.strip()], []).extend(names.split())
    return table or None


def _head(tree):
    """r2122 C1 worktree 파일 판독(git 0) → (HEAD 가지 · detached = "", 공용 폴더 realpath) · 못 읽음 = None(C2 = git 길)."""
    dot = os.path.join(tree, ".git")
    try:
        if os.path.isdir(dot):   # 일반 clone
            gitdir = dot
        else:   # linked worktree = «gitdir: <경로>» 1줄
            with open(dot, encoding="utf-8") as fh:
                line = fh.readline().strip()
            if not line.startswith("gitdir:") or not line[7:].strip():
                return None
            gitdir = os.path.join(tree, line[7:].strip())
        with open(os.path.join(gitdir, "HEAD"), encoding="utf-8") as fh:
            head = fh.read().strip()
        try:
            with open(os.path.join(gitdir, "commondir"), encoding="utf-8") as fh:
                common = os.path.join(gitdir, fh.read().strip())   # 상대 경로 = gitdir 기준
        except FileNotFoundError:
            common = gitdir
    except (OSError, UnicodeError):
        return None
    return (head[len("ref: refs/heads/"):] if head.startswith("ref: refs/heads/") else ""), os.path.realpath(common)


LOCK_AGE_S, LOCK_CAP, LOCK_S = 60, 3, 1.0   # r2241 묵은 ref 잠금 = 나이 ≥ 60초 · 최대 3개 · 찾기 1초 상한


def lock_note(repos, errs):
    """r2241 O4·O5 — fetch 실패 리포의 묵은 ref 잠금 → «묵은 ref 잠금 N개(<common 기준 경로> <나이>분 · …) · » | "".
    찾는 차례 = stderr ref 이름의 <X>.lock → packed-refs.lock → refs 아래 *.lock 걷기 · 읽기만(stat) · 지우기·git 호출 0 · 1초 넘음 = ""(원인 칸 생략)."""
    end, now, found = time.monotonic() + LOCK_S, time.time(), []
    def take(common, rel):
        try:
            age = now - os.stat(os.path.join(common, rel)).st_mtime
        except OSError:
            return
        if age >= LOCK_AGE_S and rel not in (x for x, _ in found) and len(found) < LOCK_CAP:
            found.append((rel, int(age // 60)))
    for repo in repos:
        seen = None if len(found) >= LOCK_CAP else _head(repo)
        if seen is None:
            continue
        names = re.findall(r"(?:fetching ref |cannot lock ref ')([^\s']+)", errs.get(repo) or "")
        for rel in [n + ".lock" for n in names if ".." not in n and not n.startswith("/")] + ["packed-refs.lock"]:
            take(seen[1], rel)
        for base, dirs, files in os.walk(os.path.join(seen[1], "refs")):
            dirs.sort()
            for f in sorted(files):
                if time.monotonic() > end:
                    return ""
                if f.endswith(".lock"):
                    take(seen[1], os.path.relpath(os.path.join(base, f), seen[1]))
            if len(found) >= LOCK_CAP:
                break
    if not found or time.monotonic() > end:
        return ""
    return "묵은 ref 잠금 %d개(%s) · " % (len(found), " · ".join("%s %d분" % x for x in found))


def _gate(k):   # r2122 C5 판독 시작 전 남은 몫 < MIN_S = 시작 0 · Keeper.call 과 같은 Cut
    if (left := k.left()) is not None and left < MIN_S:
        raise k.cut_at()


def _one(k, tree, work, got):   # worktree 1개 · HEAD = nano/<work> 면 got 에 보탬
    seen = _head(tree)
    if seen is None:   # C2 못 읽음 = 지금 git 길
        if k.git(tree, "rev-parse", "--abbrev-ref", "HEAD")[1].strip() == "nano/" + work:
            got.setdefault(ends._common(k, tree), []).append("nano/" + work)
    elif seen[0] == "nano/" + work:
        got.setdefault(seen[1], []).append("nano/" + work)


def nanos(k, teams):
    """⑥ 그 바퀴 판정 대상(팀마다 최신 dispatch · handled 아님) 중 intent worktree HEAD = nano/<work> → {git common-dir: [가지]}.
    r2122 — HEAD·공용 폴더 = 파일 판독(C1·C2) · 팀마다 journal 1회(C3 · _rows 를 그 팀 행으로 잠시 고정 · finally 원복) · 예산 문(C5)."""
    got = {}
    for team in teams:
        _gate(k)
        keep = ends._rows
        rows = keep(k, team)
        ends._rows = lambda k_, t_, rows=rows, team=team, keep=keep: rows if t_ == team else keep(k_, t_)
        try:
            for work, (attempt, holder) in sorted((ends.latest(k, team) or {}).items()):
                if "%s|%s@%s" % (team, work, attempt) in k.state["handled"]:
                    continue
                _gate(k)
                tree = ends.intent(k, team, work, attempt, holder).get("worktree") or ""
                if os.path.isdir(tree):
                    _one(k, tree, work, got)
        finally:
            ends._rows = keep
    return got


def _pid(k, repo):
    return os.path.join(k.dir, "bg-%s.pid" % ("root" if repo == k.root else "pack"))


def _alive(pid):
    try:
        with open(pid, encoding="utf-8") as fh:
            n = int(fh.read().strip() or 0)
        return n > 0 and (os.kill(n, 0) or True)
    except (OSError, ValueError):
        return False


def background(k, repo):
    """⑦ 전체 fetch(설정 refspec · 원격 추적 ref 만 · 로컬 가지 손 0) 1회를 던지고 끝 · 앞 것 살아 있음 = 새로 0 · 결과 = 다음 바퀴 collect."""
    pid = _pid(k, repo)
    if _alive(pid):
        return k.log("BG-FETCH", text="%s 건너뜀 — 앞 백그라운드 살아 있음" % repo)
    proc = subprocess.Popen([sys.executable, "-c", CHILD, repo, pid, str(FETCH_S)], env=k.env, cwd=k.root, start_new_session=True,
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(pid, "w", encoding="utf-8") as fh:
        fh.write(str(proc.pid))
    k.bg[repo] = proc


def collect(k):
    """⑦ 앞 바퀴 백그라운드 결과 → 리포마다 로그 1줄(성공·실패 · 시도마다 rc·초) · 읽은 결과 파일은 지움."""
    for path in sorted(glob.glob(os.path.join(glob.escape(k.dir), "bg-*.json"))):
        data = k.read_json(path)
        os.unlink(path)
        k.log("BG-FETCH", text="%s %s %s" % (os.path.basename(path)[3:-5], "성공" if data.get("ok") else "실패", " · ".join(data.get("tries") or [])))
