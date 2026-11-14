"""ft 2.0 keeper fetch 대상 (r1975) — ① FETCH_TARGETS 판독 ⑥ 판정 대상 나노 가지 ⑦ 판정 뒤 전체 fetch 백그라운드(기다림 0 · 겹침 0).
keeper.py 가 부른다 · 판정 앞 fetch 자체(ls-remote 신선 · 시도마다 1줄)는 keeper.py fresh 그대로.
"""
import glob, importlib.util, os, subprocess, sys  # noqa: E401
HERE = os.path.dirname(os.path.abspath(__file__))
CAP, FETCH_S = 5, 7   # 리포당 지정 ref 상한 · 백그라운드도 1회 7초 + 재시도 1
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


def nanos(k, teams):
    """⑥ 그 바퀴 판정 대상(팀마다 최신 dispatch · handled 아님) 중 intent worktree HEAD = nano/<work> → {git common-dir: [가지]}."""
    got = {}
    for team in teams:
        for work, (attempt, holder) in sorted((ends.latest(k, team) or {}).items()):
            if "%s|%s@%s" % (team, work, attempt) in k.state["handled"]:
                continue
            tree = ends.intent(k, team, work, attempt, holder).get("worktree") or ""
            if os.path.isdir(tree) and k.git(tree, "rev-parse", "--abbrev-ref", "HEAD")[1].strip() == "nano/" + work:
                got.setdefault(ends._common(k, tree), []).append("nano/" + work)
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
