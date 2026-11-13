"""r1812 ft2 keeper 시험 대역 — test_pi_keeper_r1812.py 가 부른다(시험 아님 · 이름에 test_ 없음).
임시 git 리포 2쌍(BYZ 대역 main·ops/main-base · 팩 대역 main) · 가짜 tmux(FT_TMUX · 세션 목록·capture 고정 · 호출 기록) ·
가짜 ft-seat-close·쪽지·reap(인자 기록 · rc 파일) · 주입 시계 · 임시 root 만 쓴다(실 tmux·명부·runtime 0).
"""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
OLD = FT2.parent / "legacy" / "1.x" / "harness"          # ⑤ 1.x 승계 도구 — 임시 cwd 에서 스텁과만 실행
T0, NOW, TEAM, AB = 1794000000.0, "2026-11-13T10:00:00", "harness", "ab" * 20
TEAMS = "| 팀 | 폴더 |\n|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` |\n| planner | `design/teams/planner/` |\n"
TMUX = r'''#!__PY__
import json, os, sys
st, a = os.environ["FAKE_TMUX"], sys.argv[1:]
d, name = json.load(open(st)), sys.argv[-1].lstrip("=").rstrip(":")  # r1822 pane 대상 `=이름:`
open(st + ".log", "a").write(json.dumps(a) + "\n")
if a[0] == "kill-session": d["alive"].remove(name); json.dump(d, open(st, "w"))
if a[0] == "capture-pane": sys.stdout.write(d["pane"].get(name, ""))
if a[0] == "has-session" and name not in d["alive"]: sys.stderr.write("can't find session: %s\n" % name)
if a[0] == "display-message":   # r1839 #{session_attached} · 실제 tmux 처럼 `=이름`(콜론 없음)·없는 세션 = rc0 빈 줄
    t = a[a.index("-t") + 1]; sys.stdout.write("%s\n" % (d.get("att", {}).get(t[1:-1], 0) if t.endswith(":") and t[1:-1] in d["alive"] else "")); sys.exit(d.get("att_rc", 0))
sys.exit(0 if name in d["alive"] or a[0] == "kill-session" else 1)
'''
STUB = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\necho "STUB $1"\nexit "$(cat "$0.rc" 2>/dev/null || echo 0)"\n'
def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)   # 기준판 = keeper.py 없음 → Red
    return module
def _git(cwd, *a):
    return subprocess.run(["git", "-C", str(cwd)] + list(a), capture_output=True, text=True, timeout=25, check=True).stdout.strip()
def _lines(path):
    return Path(str(path)).read_text(encoding="utf-8").splitlines() if Path(str(path)).exists() else []
def _put(path, body):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(body if isinstance(body, str) else json.dumps(body), encoding="utf-8")
class World:
    def __init__(s, tmp, mp, ft2=FT2, old=OLD):
        mp.setenv("FT_NOW", NOW)
        s.tmp, s.ft2, s.old, s.t, s.root, b = tmp, ft2, old, T0, tmp / "root", tmp / "bin"
        s.CLI = _mod(ft2 / "core" / "cli.py", "kc_%d" % id(s))
        for name in ("byz", "pack"):
            _git(tmp.parent, "init", "-q", "--bare", "-b", "main", str(tmp / (name + ".git")))
            _git(tmp, "init", "-q", "-b", "main", "seed-" + name)
            for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false"), ("remote.origin.url", str(tmp / (name + ".git")))):
                _git(tmp / ("seed-" + name), "config", k, v)
            s.commit(name, {"design/TEAMS.md": TEAMS}, "main")
        s.commit("byz", {}, "ops/main-base", new=True)
        _git(tmp, "clone", "-q", str(tmp / "byz.git"), "root"), _git(tmp, "clone", "-q", str(tmp / "pack.git"), "pack")
        for name, body in (("tmux", TMUX.replace("__PY__", sys.executable)), ("close", STUB), ("mbox", STUB),
                           ("reap", '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n')):
            _put(b / name, body), (b / name).chmod(0o755)
        s.tm, s.close, s.mbox, s.state = b / "tmux.json", b / "close", b / "mbox", s.root / ".fable-team" / "state"
        _put(s.tm, {"alive": [], "pane": {}})
        s.env = dict(os.environ, FT_TMUX=str(b / "tmux"), FAKE_TMUX=str(s.tm), FT2_PACK_REPO=str(tmp / "pack"),
                     FT_SEAT_CLOSE_BIN=str(s.close), FT2_KEEPER_MBOX=str(s.mbox), FT_NOW=NOW,
                     FT2_PI_SESSIONS=str(tmp / "pi-sessions"))
        for team in (TEAM, "planner"):
            _put(s.root / ".fable-team" / ("seats-%s.json" % team), {"_master": "M-" + team})
    @property
    def K(s):
        return _mod(s.ft2 / "adapters" / "pi" / "keeper.py", "kp_%d" % id(s))
    def commit(s, name, files, branch, new=False):
        seed = s.tmp / ("seed-" + name)
        if _git(seed, "symbolic-ref", "--short", "HEAD") != branch:
            _git(seed, "checkout", "-q", *(["-b"] if new else []), branch)
        for rel, body in files.items():
            _put(seed / rel, body)
        _git(seed, "add", "-A"), _git(seed, "commit", "-q", "--allow-empty", "-m", "x"), _git(seed, "push", "-q", "origin", branch)
        return _git(seed, "rev-parse", "HEAD")
    def card(s, work, sha=None, stage="진행", folder="design/harness", refs=("main", "ops/main-base")):
        for ref in refs:
            s.commit("byz", {"%s/indices/%s/%s-x.md" % (folder, stage, work): "# 인덱스: %s\n- 상태: 대기\n" % work
                             + ("- 착지: %s\n" % sha if sha else "")}, ref)
    def pack_sha(s):
        return s.commit("pack", {"p.txt": str(os.urandom(4))}, "main")
    def work(s, work, done=False, team=TEAM, intent=True, alive=False, pane="✻ Brewed for 3s\n❯ ", holder=None,
             seat=None, turn="stop"):
        """일 1개 = submit→assign→deliver(→complete) · intent(holder=seat) · Pi 세션 jsonl 마지막 줄 stopReason=turn(None=파일 0)."""
        holder = holder or "byz-%s-nano-%s-t#0" % (team, work)
        steps = [["submit", "--command", "c-" + work, "--body", "본문-" + work, "--work", work],
                 ["assign", "--work", work, "--holder", holder, "--evidence", "v1,v2"], ["deliver", "--work", work]]
        for argv in steps + ([["complete", "--work", work, "--attempt", "a1"]] if done else []):
            out, rc = s.CLI.run(argv + ["--root", str(s.root), "--team", team])
            assert rc == 0, out
        _put(s.state / "ft20-switch" / (team + ".json"), "{}")
        seat, tree = seat or holder, str(s.tmp / "wt" / work)
        if intent:
            body = {"FT2_HOLDER": seat, "state": "opened", "worktree": tree, "at": "2026-01-01T00:00:00"}
            _put(s.runtime(team) / "launch" / ("%s@a1.intent" % work), body)
        if turn:
            last = {"type": "message", "message": {"role": "assistant", "stopReason": turn}}
            _put(Path(s.env["FT2_PI_SESSIONS"]) / ("--%s--" % tree.strip("/").replace("/", "-")) / "s.jsonl",
                 '{"type": "session"}\n' + json.dumps(last) + "\n")
        d = json.loads(s.tm.read_text(encoding="utf-8"))
        d["alive"], d["pane"][seat] = d["alive"] + ([seat] if alive else []), pane
        return _put(s.tm, d) or seat
    def runtime(s, team=TEAM):
        return s.root / ".fable-team" / "teams" / team / "runtime"
    def journal(s, team=TEAM):
        return [json.loads(x) for p in sorted(s.runtime(team).glob("journal*.jsonl")) for x in _lines(p)]
    def kinds(s, kind, team=TEAM):
        return sum(rec["kind"] == kind for rec in s.journal(team))
    def keeper(s):
        return s.K.Keeper(str(s.root), env=s.env, now=lambda: s.t)
    def round(s, k=None):
        k = k or s.keeper()
        assert k.run_once() == 0
        return k.lines
    def tmux(s, verb):
        return [a for a in map(json.loads, _lines(str(s.tm) + ".log")) if a[0] == verb]
    def enable(s, team=TEAM):
        _put(s.root / ".fable-team" / "teams" / team / "CLOSE-NEXT.enabled", "enabled\n")
