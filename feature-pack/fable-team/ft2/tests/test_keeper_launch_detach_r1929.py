"""r1929 keeper 가 launch 를 기다리지 않는다 · 끊긴 열기 이어 열기 1회 (반례 ①~⑨ ⑬~⑰ · 변이 M1~M7).
keeper 쪽 = r1871 세계(임시 root·git·가짜 tmux·가짜 launch·가짜 record) · 바퀴는 settle 없이 1회씩(kw.World.round).
launch 쪽 = r1765 시험 대역(가짜 git·tmux·pi · worktree 만 진짜 git) + 임시 git 리포 · 실 tmux·명부·ft2 원장·설치 0 · sleep 0.
① 가짜 launch 는 FIFO 로 막힌다(40초 걸리는 열기 대역 · 자체 alarm 30초) — keeper 바퀴가 그 끝을 기다리지 않음을 본다.
"""
import importlib.util, json, os, shutil, subprocess, time, types  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
def _mod(name, path):
    spec = importlib.util.spec_from_file_location(name, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
nx, pl = _mod("r1929_nx", HERE / "test_pi_keeper_next_card_r1871.py"), _mod("r1929_pl", HERE / "test_pi_launch.py")
kw, B, W1, FT2 = nx.kw, nx.B, nx.W1, nx.kw.FT2
_p = subprocess.Popen(["true"])
DEAD = _p.wait() or _p.pid          # 거둔 자식 pid = 죽은 열기 대역
FIFO = '''import json, os, signal, sys, time
signal.alarm(30)
a, me = sys.argv[1:], os.path.abspath(__file__)
open(me + ".log", "a").write(json.dumps(a) + "\\n")
work = a[a.index("--work") + 1]
intent = os.path.join(a[a.index("--root") + 1], ".fable-team/teams/harness/runtime/launch/%s@a1.intent" % work)
row = {"state": "opening", "pid": os.getpid(), "started": time.time()}
open(intent, "w").write(json.dumps(row))
open(me + ".ready", "w").close()
open(me + ".go").read()
open(intent, "w").write(json.dumps(dict(row, state="opened")))
st = os.environ["FAKE_TMUX"]; d = json.load(open(st)); d["alive"].append("byz-harness-nano-%s#0" % work[:40]); json.dump(d, open(st, "w"))
'''
def raw(w, k=None):
    k = k or w.keeper()
    kw.World.round(w, k)
    return k
def handled(k):
    return "harness|%s@a1" % W1 in k.state["handled"]
def has(k, head, *words):
    return any(x.startswith(head) and all(t in x for t in words) for x in k.lines)
def pre(w, row, resume=None):
    d = w.runtime() / "launch"
    kw._put(d / ("%s@a1.intent" % B), row)
    kw._put(d / ("%s@a1.intent.resume" % B), resume) if resume else None
def c1(w, mp):   # ① 막힌 launch → LAUNCHING · 대기 0 · handled 0 ② opening ∧ pid 살아 있음 → 열기 중 · Popen 0 ③ opened → record · NEXT · handled
    b = w.tmp / "bin"
    kw._put(b / "launch.py", FIFO), [os.mkfifo(str(b / ("launch.py." + x))) for x in ("ready", "go")]
    t0, k = time.monotonic(), raw(w)
    assert time.monotonic() - t0 < 7 and has(k, "LAUNCHING harness " + nx.nh(B), "대기 0") and not handled(k), k.lines
    open(str(b / "launch.py.ready")).read()
    k2 = raw(w)
    assert has(k2, "LAUNCH-WAIT harness " + nx.nh(B), "열기 중 opening") and len(nx.log(w, "launch.py")) == 1 and not handled(k2), k2.lines
    open(str(b / "launch.py.go"), "w").close()
    [p.wait(25) for p in k.cache["spawned"]]
    k3 = raw(w)
    assert "NEXT harness %s -> %s %s" % (W1, B, nx.nh(B)) in k3.lines and handled(k3) and len(nx.log(w, "launch.py")) == 1, k3.lines
def c4(w, mp):   # ④ intent failed(git checkout) → «복구 필요» · handled · Popen 0
    pre(w, {"state": "failed", "step": "git checkout", "reason": "x"})
    k = raw(w)
    assert has(k, "HELD-NEXT harness %s -> %s" % (W1, B), "실패 git checkout", "복구 필요") and handled(k) and B not in nx.launched(w)
def c5k(w, mp):  # ⑤ keeper — opening ∧ pid 죽음 ∧ .resume 없음 → --resume 1회 띄움 · handled 0
    pre(w, {"state": "opening", "pid": DEAD, "started": 1.0})
    k = raw(w)
    assert has(k, "LAUNCHING harness", "이어 열기") and not handled(k) and [json.loads(x)[-1] for x in nx.log(w, "launch.py")] == ["--resume"]
def c8(w, mp):   # ⑧ Popen OSError → «복구 필요» · handled
    k = w.keeper()   # 모듈은 keeper 마다 새로 읽힌다 → 같은 k 로 바퀴
    kl = type(k).close.__globals__["keeper_next"].kl
    mp.setattr(kl, "subprocess", types.SimpleNamespace(DEVNULL=subprocess.DEVNULL, Popen=lambda *a, **kv: (_ for _ in ()).throw(OSError("가짜"))))
    raw(w, k)
    assert has(k, "HELD-NEXT harness", "띄우기 실패", "복구 필요") and handled(k) and B not in nx.launched(w)
def c9(w, mp):   # ⑨ pid 판정 못 함(ps 실패) → 열기 중 · 손 0
    kw._put(w.tmp / "bin" / "ps", "#!/bin/sh\nexit 1\n"), (w.tmp / "bin" / "ps").chmod(0o755)
    w.env["FT2_KEEPER_PS"] = str(w.tmp / "bin" / "ps")
    pre(w, {"state": "opening", "pid": os.getpid(), "started": time.time()})
    k = raw(w)
    assert has(k, "LAUNCH-WAIT harness", "열기 중 opening") and not handled(k) and nx.log(w, "launch.py") == []
def c16(w, mp):  # ⑯ .resume 있음 ∧ 그 pid 죽음 ∧ opened 아님 → «복구 1회 소진» · Popen 0
    pre(w, {"state": "opening", "pid": DEAD, "started": 1.0}, {"pid": DEAD, "started": 1.0, "kind": "resume"})
    k = raw(w)
    assert has(k, "HELD-NEXT harness", "복구 1회 소진", "복구 필요") and handled(k) and B not in nx.launched(w)
def git(root, *a):
    return subprocess.run(["git", "-C", str(root)] + list(a), capture_output=True, text=True, timeout=25, check=True).stdout.strip()
def lw(tmp, add=False, row=True):
    """launch 대역 + 진짜 git root(커밋 1) · add = 끊긴 열기 자리(worktree add --no-checkout) · row = opening 의도(pid 죽음)."""
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    git(root, "init", "-q"), git(root, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "x")
    sha = git(root, "rev-parse", "HEAD")
    git(root, "worktree", "add", "-q", "--no-checkout", "--detach", str(pl._worktree(root)), sha) if add else None
    kw._put(pl._intent(root), {"state": "opening", "pid": DEAD, "started": 1.0, "base_sha": sha}) if row else None
    return root, fake
ENVX = {"FAKE_GIT_REAL_WORKTREE": "1", "REAL_GIT": shutil.which("git")}
def resume(root, fake, launcher, rc=None):
    return pl._launch(root, fake, launcher, extra=["--resume"], rc=rc, env_extra=ENVX)
def subs(fake):
    return [x["sub"] for x in pl._log(fake)]
def state(root):
    return json.loads(pl._intent(root).read_text(encoding="utf-8"))
def c5(tmp, launcher):   # ⑤ launch — HEAD == base_sha → sparse·checkout·tmux 만 다시 · opened ⑤b 경로 없음 → git add 부터
    root, fake = lw(tmp / "a", add=True)
    out, rc = resume(root, fake, launcher)
    assert (rc, out.get("opened")) == (0, True) and subs(fake) == ["worktree", "sparse-checkout", "checkout", "new-session", "has-session"], (out, subs(fake))
    assert state(root)["state"] == "opened"
    root, fake = lw(tmp / "b")
    assert resume(root, fake, launcher)[1] == 0 and subs(fake)[:3] == ["worktree", "worktree", "sparse-checkout"], subs(fake)
def c6(tmp, launcher):   # ⑥ 경로 있음 ∧ worktree 목록에 없음 → failed «자리 불일치» · sparse 0
    root, fake = lw(tmp)
    pl._worktree(root).mkdir(parents=True)
    out, rc = resume(root, fake, launcher)
    assert (rc, out.get("step"), state(root)["state"]) == (2, "끊긴 열기 · 자리 불일치", "failed") and "sparse-checkout" not in subs(fake), out
def c7(tmp, launcher):   # ⑦ 이어 열기 2회째(.resume 있음) → rc1 «이미 복구 예약» · 바깥 호출 0
    root, fake = lw(tmp, add=True)
    kw._put(str(pl._intent(root)) + ".resume", {"pid": DEAD, "started": 1.0, "kind": "resume"})
    out, rc = resume(root, fake, launcher)
    assert (rc, "이미 복구 예약" in out.get("reason", ""), subs(fake)) == (1, True, []), (out, subs(fake))
def c13(tmp, launcher):  # ⑬⑭ --resume A·B 동시 → 예약 1 · sparse 1 · 진 쪽 rc1 · 가짜 link 순서(B 가 A 예약 전에 «있나» 를 봄)도 예약 1
    root, fake = lw(tmp, add=True)
    procs = [subprocess.Popen(pl._argv(launcher, root, ["--resume"]), env=pl._env(fake, None, ENVX), stdout=subprocess.PIPE, text=True) for _ in "AB"]
    [p.communicate(timeout=70) for p in procs]
    assert sorted(p.returncode for p in procs) == [0, 1] and subs(fake).count("sparse-checkout") == 1, subs(fake)
    plan, spot = _mod("r1929_plan_%d" % id(tmp), launcher.parent / "launch_plan.py"), str(tmp / "x.resume")
    assert plan.reserve(spot, {"pid": 1}) is True
    real, os.path.exists = os.path.exists, lambda _: False
    try:
        second = plan.reserve(spot, {"pid": 2})
    finally:
        os.path.exists = real
    assert second is False and json.loads(Path(spot).read_text(encoding="utf-8"))["pid"] == 1
def c15(tmp, launcher):  # ⑮ 예약 뒤 checkout 실패 → intent failed · .resume 남음(다음 바퀴 = ④ «복구 필요»)
    root, fake = lw(tmp, add=True)
    out, rc = resume(root, fake, launcher, rc={"git": 1})
    assert (rc, state(root)["step"], Path(str(pl._intent(root)) + ".resume").exists()) == (2, "git checkout", True), out
def c17(tmp, launcher):  # ⑰ 처음 열기 예약 파일은 판독하면 늘 pid 있음 — 첫 바깥 호출 순간·opening 순간 둘 다
    root, fake = pl._paths(tmp)
    pl._runtime(root)
    mod, seen = _mod("r1929_launch_%d" % id(tmp), launcher), []
    def spy(cmd, cwd, env, timeout):
        seen.append(mod.read_intent(str(pl._intent(root))))
        return (0, pl.FAKE_SHA) if "--verify" in cmd else (0, "")
    os.environ["PATH"], path, mod.call = str(fake) + os.pathsep + os.environ["PATH"], os.environ["PATH"], spy
    try:
        out = mod.open_seat({"root": str(root), "team": pl.TEAM, "work": pl.WORK})
    finally:
        os.environ["PATH"] = path
    assert out[1] == 0 and [x.get("state") for x in seen[:2]] == ["claiming", "opening"] and all(x.get("pid") == os.getpid() for x in seen[:2]), (out, seen)
KEEPER = {"①": c1, "④": c4, "⑤k": c5k, "⑧": c8, "⑨": c9, "⑯": c16}
LAUNCHER = {"⑤": c5, "⑥": c6, "⑦": c7, "⑬": c13, "⑮": c15, "⑰": c17}
def run(name, tmp, mp, ft2=FT2):
    if name in KEEPER:
        return KEEPER[name](nx.world(tmp, mp, nx.TWO, ft2=ft2), mp)
    tmp.mkdir(parents=True, exist_ok=True)
    LAUNCHER[name](tmp, ft2 / "adapters" / "pi" / "launch.py")
KL, LP, LA = "adapters/pi/keeper_launch.py", "adapters/pi/launch_plan.py", "adapters/pi/launch.py"
ALIVE = '    if got.get("state") not in ("claiming", "opening") or alive(k, got) != "dead":'
MUTANTS = {"M1": (KL, "child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=fh, stderr=fh, env=k.env, cwd=k.root, start_new_session=True)", "child = k.call(argv, LAUNCH_S)", "①"),
           "M2": (KL, ALIVE, '    if got.get("state") not in ("claiming", "opening"):', "①"),
           "M3": (KL, ALIVE, '    if got.get("state") not in ("claiming", "opening") or True:', "⑤k"),
           "M4": (LA, '    if not planner.reserve(plan["intent"] + ".resume", own):', '    if not planner.reserve(plan["intent"] + ".resume", own) and False:', "⑦"),
           "M5": (LP, "    if exists and head == sha:", "    if exists:", "⑥"),
           "M6": (LP, "        os.link(tmp, path)", "        (_ for _ in ()).throw(FileExistsError()) if os.path.exists(path) else shutil.copyfile(tmp, path)", "⑬"),
           "M7": (KL, '    if os.path.exists(base + ".intent.resume"):', "    if False:", "⑯")}
@pytest.mark.parametrize("name", list(KEEPER) + list(LAUNCHER))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)
@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    shutil.copytree(FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    [(tmp_path / sub).mkdir() for sub in ("w1", "w2")]
    with pytest.raises(AssertionError):
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
