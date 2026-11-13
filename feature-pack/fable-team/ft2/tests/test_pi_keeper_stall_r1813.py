"""r1813 ft2 keeper 멈춤 갈래 — 깨움 1회 → 재배정 시험 (카드 r3 반례 ①~⑦ · R1-a · R2-a~c · R3-a~b · 변이 M1~M8 · 보정1 R1-b · M9).
입력(카드 r3 · DA#10): 임시 데이터 root 에 ★실제 core★(cli.run 으로 submit·assign·deliver·start·effect · Lifecycle.progress) ·
업무 repo = 데이터 root 와 다른 임시 git repo(옛 worktree = 그 repo 의 worktree) · ★실제 launch.py★(실행 회차는 PATH 앞 tmux 대역만 ·
`--dry-run` 결과 대조) · 대역 3가지뿐 = tmux(capture 고정 · send·kill·new 기록) · pi 프로세스 argv(ps) · pi 세션 파일(mtime 주입).
주입 시계 · sleep 0 · 실 tmux·launchd·journal·명부 0. 기준판(keeper 갈래 없음) = ① ③ R1-a Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import importlib.util, json, os, shutil, subprocess, sys, time  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
T0, TEAM, W, M = 1794000000.0, "harness", "r9813", 60
H0, H1 = "byz-harness-nano-r9813-t#0", "byz-harness-nano-r9813-t#1"
TMUX = r'''#!__PY__
import glob, json, os, sys
st, a = os.environ["FAKE_TMUX"], sys.argv[1:]
d = json.load(open(st))
name = a[a.index("-t") + 1].lstrip("=").rstrip(":") if "-t" in a else (a[a.index("-s") + 1] if "-s" in a else "")
n = sum(1 for p in glob.glob(os.path.join(os.environ["FAKE_RUNTIME"], "journal*.jsonl")) for x in open(p) if '"dispatch"' in x)
open(st + ".log", "a").write(json.dumps({"a": a, "dispatch": n}) + "\n")
if a[0] == "kill-session": d["alive"].remove(name)
if a[0] == "new-session": d["alive"].append(name)
if a[0] == "send-keys" and "-l" in a and not d.get("noecho"): d["pane"][name] = d["pane"].get(name, "") + a[-1]
json.dump(d, open(st, "w"))
if a[0] == "capture-pane": sys.stdout.write(d["pane"].get(name, "✻ Brewed for 3s\n❯ "))
if a[0] == "display-message":   # r1839 #{session_attached} = 콜론 끝 대상만 숫자 · `=이름` = rc0 빈 줄(실제 tmux 꼴)
    t = a[a.index("-t") + 1]; sys.stdout.write(("%s\n" % d.get("att", {}).get(name, 0) if t.endswith(":") else "\n") if "#{session_attached}" in a else "4242\n")
if a[0] == "has-session" and name not in d["alive"]: sys.stderr.write("can't find session: %s\n" % name)
sys.exit(1 if a[0] == "has-session" and name not in d["alive"] else 0)
'''
PS = '#!/bin/sh\ncat "$FAKE_PS"\n'
STUB = '#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\nexit 0\n'


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _stamp(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(t))


def _git(cwd, *a, at=None):
    env = dict(os.environ, **({"GIT_COMMITTER_DATE": "@%d +0900" % at, "GIT_AUTHOR_DATE": "@%d +0900" % at} if at else {}))
    return subprocess.run(["git", "-C", str(cwd)] + list(a), capture_output=True, text=True, timeout=25, check=True, env=env).stdout.strip()


def _put(path, body):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(body if isinstance(body, str) else json.dumps(body), encoding="utf-8")


def _lines(path):
    return Path(str(path)).read_text(encoding="utf-8").splitlines() if Path(str(path)).exists() else []


class World:
    def __init__(s, tmp, mp, ft2=FT2):
        s.tmp, s.mp, s.ft2, s.t, b = tmp, mp, ft2, T0, tmp / "bin"
        s.root, s.repo, s.sess = tmp / "root", tmp / "work", tmp / "sess"
        s.CLI = _mod(ft2 / "core" / "cli.py", "sc_%d" % id(s))
        s.LC = _mod(ft2 / "core" / "lifecycle.py", "sl_%d" % id(s))
        for name, body in (("tmux", TMUX.replace("__PY__", sys.executable)), ("ps", PS), ("mbox", STUB)):
            _put(b / name, body), (b / name).chmod(0o755)
        s.tm, s.ps, s.mbox = b / "tmux.json", b / "ps.txt", b / "mbox"
        _put(s.tm, {"alive": [], "pane": {}}), _put(s.ps, "node /x/pi --model claude-opus-5-5 --thinking medium\n")
        _put(s.root / ".fable-team" / "seats-harness.json", {"_master": "M-harness"})
        s.env = dict(os.environ, FT_TMUX=str(b / "tmux"), FAKE_TMUX=str(s.tm), FAKE_PS=str(s.ps), FT2_KEEPER_PS=str(b / "ps"),
                     PATH=str(b) + os.pathsep + os.environ["PATH"], FT2_PI_SESSIONS=str(s.sess), FT2_KEEPER_MBOX=str(s.mbox),
                     FAKE_RUNTIME=str(s.runtime()), FT2_PACK_REPO=str(tmp / "없음"))
        mp.setenv("FAKE_RUNTIME", str(s.runtime()))
        s.repo.mkdir(parents=True)
        _git(s.repo, "init", "-q", "-b", "main")
        for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
            _git(s.repo, "config", k, v)
        s.c1 = (_git(s.repo, "commit", "-q", "--allow-empty", "-m", "c1", at=T0 - 3600), _git(s.repo, "rev-parse", "HEAD"))[1]
    def cli(s, at, *argv):
        s.mp.setenv("FT_NOW", _stamp(at))
        out, rc = s.CLI.run(list(argv) + ["--root", str(s.root), "--team", TEAM])
        return out, rc
    def runtime(s):
        return s.root / ".fable-team" / "teams" / TEAM / "runtime"
    def tree(s, attempt="a1"):
        return s.root / ".fable-team" / "teams" / TEAM / "worktrees" / ("%s@%s" % (W, attempt))
    def seat(s, holder=H0, intent=True, step=-20 * M, effect=False, res=(), commit=-20 * M, mtime=-16 * M, turn="stop", state="opened"):
        """실제 core 로 submit → assign → deliver(→ start(→ effect)) · 옛 worktree(업무 repo) · intent · 세션 파일 · tmux 생존."""
        for at, argv in ((T0 - 40 * M, ["submit", "--command", "c-" + W, "--body", "본문", "--work", W]),
                         (T0 - 40 * M, ["assign", "--work", W, "--holder", holder, "--evidence", "v1,v2"] + (["--resources", ",".join(res)] if res else [])),
                         (T0 - 40 * M, ["deliver", "--work", W])) + (((T0 + step, ["start", "--work", W, "--holder", holder, "--gen", "1"]),) if step else ()):
            assert s.cli(at, *argv)[1] == 0
        if effect:
            assert s.cli(T0 + step, "effect", "--work", W, "--holder", holder, "--gen", "1", "--effect", "push")[1] == 0
        tree = s.tree()
        _git(s.repo, "worktree", "add", "-q", "--detach", str(tree), s.c1)
        s.c2 = (_git(tree, "commit", "-q", "--allow-empty", "-m", "c2", at=T0 + commit), _git(tree, "rev-parse", "HEAD"))[1]
        if intent:
            _put(s.runtime() / "launch" / ("%s@a1.intent" % W), {"FT2_HOLDER": holder, "state": state, "worktree": str(tree)})
        s.session(tree, mtime, turn)
        d = json.loads(s.tm.read_text(encoding="utf-8"))
        d["alive"].append(holder)
        _put(s.tm, d)
    def session(s, tree, mtime, turn="stop"):
        f = s.sess / ("--%s--" % str(tree).strip("/").replace("/", "-")) / "s.jsonl"
        last = {"role": "assistant", "stopReason": turn}
        if turn == "error":
            last = {"role": "assistant", "stopReason": "error", "errorMessage": "authentication_failed: Not logged in"}
        _put(f, "\n".join(json.dumps(x) for x in ({"type": "session"}, {"type": "message", "timestamp": "x", "message": last})) + "\n")
        os.utime(f, (T0 + mtime, T0 + mtime))
        return f
    def keeper(s):
        return _mod(s.ft2 / "adapters" / "pi" / "keeper.py", "sk_%d" % id(s)).Keeper(str(s.root), env=s.env, now=lambda: s.t)
    def round(s, dt=None):
        s.t = T0 + (dt or 0)
        s.mp.setenv("FT_NOW", _stamp(s.t))
        s.k = s.keeper()
        s.k.locked(lambda: s.k.team_round(TEAM))
        return s.k.lines
    def tmux(s, verb):
        return [x for x in map(json.loads, _lines(str(s.tm) + ".log")) if x["a"][0] == verb]
    def journal(s):
        return [json.loads(x) for p in sorted(s.runtime().glob("journal*.jsonl")) for x in _lines(p)]
    def kinds(s, kind):
        return sum(rec["kind"] == kind for rec in s.journal())
    def notes(s):
        return _lines(str(s.mbox) + ".log")


def c1(w):   # ① 진척 0 16분 + IDLE → Escape 1 · 문구 1 · Enter 1 · WOKE · 다음 바퀴 깨움 0
    w.seat(step=-16 * M)
    assert ("WOKE harness %s %s" % (W, H0)) in w.round()
    keys = [x["a"][3:] for x in w.tmux("send-keys")]
    assert keys[0] == ["Escape"] and keys[1][0] == "-l" and keys[1][1].startswith("[깨움] ft2 keeper — 일 r9813 진척 0 16분") and keys[2] == ["Enter"]
    w.round(M)
    assert len(w.tmux("send-keys")) == 3


def c2(w):   # ② pane «Working» → 깨움 0
    w.seat(step=-16 * M)
    _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), pane={H0: "⠋ Working...\n"}))
    w.round()
    assert w.tmux("send-keys") == []


def c2b(w):  # ②′ pi 세션 파일 mtime 3분 전 → 깨움 0
    w.seat(step=-16 * M, mtime=-3 * M), w.round()
    assert w.tmux("send-keys") == []


def c2c(w):  # ②″ external_wait 시한 안 → 깨움 0
    w.seat(step=-16 * M)
    assert w.LC.Lifecycle(str(w.root), TEAM, clock=lambda: _stamp(T0 - 16 * M)).progress(W, "L1", "external_wait", deadline=5).result == "접수 성공"
    w.round()
    assert w.tmux("send-keys") == []


def c3(w):   # ③ 깨움 뒤 11분 진척 0 → kill 1 → assign(#1·rotation) 1 → deliver 1 → launch 1 (이 순서) · reassess 0
    w.seat(), w.round()
    assert any(x.startswith("REASSIGNED harness %s %s -> %s" % (W, H0, H1)) for x in w.round(11 * M))
    kill, new = w.tmux("kill-session"), w.tmux("new-session")
    assert [x["a"][-1] for x in kill] == ["=" + H0] and kill[0]["dispatch"] == 1 and len(new) == 1 and new[0]["dispatch"] == 2
    kinds = [r["kind"] for r in w.journal()]
    assert kinds[-2:] == ["dispatch", "deliver"] and w.kinds("reassess") == 0 and w.kinds("complete") == 0
    assert json.loads((w.runtime() / "launch" / ("%s@a2.intent" % W)).read_text(encoding="utf-8"))["state"] == "opened"


def c3b(w):  # ③′ 깨움 뒤 진척 생김(커밋 시각 갱신) → S3 0
    w.seat(), w.round()
    _git(w.tree(), "commit", "-q", "--allow-empty", "-m", "c3", at=T0 + 5 * M)
    w.round(11 * M)
    assert w.tmux("kill-session") == [] and w.kinds("dispatch") == 1


def c4(w):   # ④ start 뒤 effect · result 없음 → 실제 core 사전 판독 hold → kill 0 · assign 0 · 쪽지 1
    w.seat(effect=True), w.round(), w.round(11 * M)
    assert w.tmux("kill-session") == [] and w.kinds("dispatch") == 1
    assert len(w.notes()) == 1 and "결과 미확정 — 사람 확인" in w.notes()[0]


def r1a(w):  # R1-a 실제 core — accept→assign(v1·v2·res1)→deliver→start 미완료 work 를 ③ 경로로
    w.seat(res=("res1",)), w.round(), w.round(11 * M)
    rows = w.journal()
    a2 = [r for r in rows if r["kind"] == "dispatch"][-1]
    assert (a2["attempt"], a2["gen"], a2["holder"], a2["resources"]) == ("a2", 2, H1, [])
    assert rows[-1]["kind"] == "deliver" and rows[-1]["attempt"] == "a2" and w.kinds("reassess") == 0 and w.kinds("complete") == 0
    assert w.cli(T0 + 12 * M, "start", "--work", W, "--holder", H1, "--gen", "2")[1] == 0
    assert w.cli(T0 + 12 * M, "start", "--work", W, "--holder", H0, "--gen", "1")[0]["result"] == "낡은 실행권"
    state = json.loads((w.runtime() / "state.json").read_text(encoding="utf-8"))
    assert state["reservations"]["res1"]["work"] == W
    assert w.cli(T0 + 13 * M, "complete", "--work", W, "--attempt", "a2")[0]["released"] == ["res1"]


def r2a(w):  # R2-a 진척 줄(start) 30분 전 + heartbeat 1초 전 · IDLE → 깨움 1
    w.seat(step=-30 * M, commit=-30 * M, mtime=-20 * M)
    w.LC.Lifecycle(str(w.root), TEAM, clock=lambda: _stamp(T0 - 1)).progress(W, "L1", "heartbeat")
    assert ("WOKE harness %s %s" % (W, H0)) in w.round()


def r2b(w):  # R2-b 진척 줄 kind=progress·tick_kind=progress 3분 전 → 깨움 0
    w.seat(step=-30 * M, commit=-30 * M, mtime=-20 * M)
    w.LC.Lifecycle(str(w.root), TEAM, clock=lambda: _stamp(T0 - 3 * M)).progress(W, "L1", "progress")
    w.round()
    assert w.tmux("send-keys") == []


def r2c(w):  # R2-c 깨움 뒤 세션 파일 mtime 만 갱신(답만 · 진척 줄·커밋 0) 11분 → S3 진행
    w.seat(), w.round()
    w.session(w.tree(), 10 * M)
    w.round(11 * M)
    assert len(w.tmux("kill-session")) == 1 and w.kinds("dispatch") == 2


def r3a(w):  # R3-a 데이터 root ≠ 업무 repo · 옛 worktree HEAD = c2 · argv opus-5-5/medium → --repo·--base c2·--role session
    w.seat(), w.round()
    assert any(x.startswith("REASSIGNED harness %s" % W) and "role=session" in x for x in w.round(11 * M))
    argv = w.k.state["reassigned"]["%s|%s" % (TEAM, W)]["launch"]
    got = dict(zip(argv[1::2], argv[2::2]))
    assert (os.path.realpath(got["--repo"]), got["--base"], got["--role"]) == (os.path.realpath(w.repo), w.c2, "session")
    full, bare = (json.loads(subprocess.run([sys.executable] + a + ["--dry-run"], capture_output=True, text=True, timeout=25,
                                            env=w.env).stdout) for a in (argv, argv[:7]))
    assert (os.path.realpath(full["repo"]), full["base"], full["role"]) == (os.path.realpath(w.repo), w.c2, "session")
    assert (bare["repo"], bare["base"]) == (os.path.abspath(str(w.root)), "origin/main")


def r3b(w):  # R3-b 옛 intent 열림 아님 / worktree 미커밋 변경 / argv 행 0 → kill 0 · assign 0 · 쪽지 1(칸 이름)
    for sub, field in (("i", "intent"), ("d", "clean"), ("r", "role")):
        v = World(w.tmp / sub, w.mp, w.ft2)
        v.seat(state="opening" if sub == "i" else "opened")
        if sub == "d":
            _put(v.tree() / "미커밋.txt", "x")
        if sub == "r":
            _put(v.ps, "pi --model gpt-x --thinking low\n")
        v.round(), v.round(11 * M)
        assert v.tmux("kill-session") == [] and v.kinds("dispatch") == 1, sub
        if sub == "r":   # r1840 K3 — 역할만 못 정함 = 판정 불가 1줄 · 크리티컬 0
            assert v.notes() == [] and sum("역할 못 정함" in x for x in v.k.lines) == 1, v.k.lines
            continue
        assert len(v.notes()) == 1 and field in v.notes()[0], (sub, v.notes())


def r1b(w):  # 보정1 R1(DA#10 #294192) — 깨움 문구 도달 확인 3회 실패 → woke 기록 0 · 11분 뒤 kill·dispatch·launch 0 · 판정 불가 보고만
    w.seat()
    _put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), noecho=True))
    assert any("깨움 도달 확인 3회 실패" in x for x in w.round()) and not any(x.startswith("WOKE") for x in w.k.lines)
    assert w.k.state["woke"] == {} and len(w.tmux("send-keys")) == 3
    lines = w.round(11 * M)
    assert w.tmux("kill-session") == [] and w.kinds("dispatch") == 1 and w.tmux("new-session") == []
    assert any("판정 불가" in x and "깨움 도달 미확인" in x for x in lines) and len(w.tmux("send-keys")) == 3


def c5(w):   # ⑤ 같은 work 두 번째 멈춤(attempt a2) → S3 0 · 쪽지 1 · 같은 날 다시 → 쪽지 0
    w.seat(), w.round(), w.round(11 * M)
    w.session(w.tree("a2"), 11 * M)
    assert ("WOKE harness %s %s" % (W, H1)) in w.round(27 * M)
    w.round(38 * M), w.round(39 * M)
    assert len(w.tmux("kill-session")) == 1 and w.kinds("dispatch") == 2
    assert len(w.notes()) == 1 and "같은 일 두 번 멈춤" in w.notes()[0]


def c6(w):   # ⑥ intent 없는 master 좌석 IDLE 60분 → 행동 0 · 멈춤 갈래 줄 0
    w.seat(holder="byz-harness-master-x#0", intent=False, step=-60 * M, commit=-60 * M, mtime=-60 * M)
    lines = w.round()
    assert w.tmux("send-keys") == [] and w.tmux("kill-session") == [] and not [x for x in lines if "master-x" in x]


def c6b(w):  # ⑥′ LOGGEDOUT → 행동 0 · 로그 1줄
    w.seat(step=-16 * M, turn="error")
    assert sum(x.startswith("LOGGEDOUT harness %s" % W) for x in w.round()) == 1 and w.tmux("send-keys") == []


def c7(w):   # ⑦ pi 세션 파일 못 찾음 → 판정 불가 1줄 · 행동 0
    w.seat(step=-16 * M)
    shutil.rmtree(w.sess)
    assert sum("판정 불가" in x and "pi 세션 파일 없음" in x for x in w.round()) == 1 and w.tmux("send-keys") == []


CASES = {"①": c1, "②": c2, "②′": c2b, "②″": c2c, "③": c3, "③′": c3b, "④": c4, "R1-a": r1a,
         "R2-a": r2a, "R2-b": r2b, "R2-c": r2c, "R3-a": r3a, "R3-b": r3b, "R1-b": r1b, "⑤": c5, "⑥": c6, "⑥′": c6b, "⑦": c7}
KS = "adapters/pi/keeper_stall.py"
MUTANTS = {"M1": ("if BUSY.search(pane[-2000:]):", "if False:", c2),
           "M2": ('[facts["mtime"]] if woke is None', '[] if woke is None', c2b),
           "M3": ('(["send-keys"] + t + ["Escape"], ', "(", c1),
           "M4": ("if d.ex._hold(state, records, work, gen + 1, rotation=True) is not None:", "if False:", c4),
           "M5": ('if wk in k.state.setdefault("reassigned", {}):', "if False:", c5),
           "M6": ("if not holder:", 'if not (holder := holder or [r for r in rows if r.get("kind") == "dispatch" and r.get("work") == work][-1]["holder"]):', c6),
           "M7": ('(r.get("kind") == "progress" and r.get("tick_kind") == "progress")', '(r.get("kind") == "progress")', r2a),
           "M8": (', "--repo", p["repo"], "--base", p["base"], "--role", p["role"]]', "]", r3a),
           "M9": ("        for _ in range(3):\n", '        k.state["woke"][key] = k.now()\n        for _ in range(3):\n', r1b)}   # 보정1: woke 를 확인 전에 기록


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w1", monkeypatch, tree))
    case(World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
