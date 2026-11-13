"""r1826 — 판 전환 뒤 상주 라벨(slack-listen) 재기동·확인 줄 · project 투영 remaining 칸.

R1 전환 시 이 루트를 부르는 KeepAlive 라벨만 kickstart · R2 RELOADED / 판정 불가 rc3 · R3 remaining 칸.
launchctl·ps 는 env 로 넣은 대역만 · 실제 launchd 손 0 · 임시 루트만 · sleep 0.
"""
import importlib.util
import json
import plistlib
import stat
import subprocess
import sys
import time
from pathlib import Path

FT2 = Path(__file__).resolve().parents[1]
LABEL, KEEPER = "com.byz.ft2-slack-listen", "com.byz.ft2-keeper"
SLACK = {"route": "slack", "slack": {"channel": "C1", "ts": "1.0"}}


def _load(path, alias):
    spec = importlib.util.spec_from_file_location(alias, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


install = _load(FT2 / "tools" / "install.py", "ft2_install_r1826")
shared = _load(FT2 / "tests" / "test_install.py", "ft2_test_install_r1826")   # make_package 만 빌린다

STUB = """#!%s
import json, os, sys
path = os.path.join(os.environ["R1826_STUB"], "state.json")
st = json.load(open(path))
args = sys.argv[1:]
if os.path.basename(sys.argv[0]) == "ps":                  # ps -o lstart= -p <pid>
    print(st["start"].get(args[-1], "")); sys.exit(0 if args[-1] in st["start"] else 1)
label = args[-1].rsplit("/", 1)[-1]
if args[0] == "print":
    if label not in st["pids"]:
        print("Could not find service", file=sys.stderr); sys.exit(113)
    print("state = running\\n\\tpid = %%s" %% st["pids"][label]); sys.exit(0)
st["kicks"].append(label)
st["pids"][label] = st["after"].get(label, st["pids"][label])
json.dump(st, open(path, "w"))
""" % sys.executable


def _lstart(offset):
    return time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(time.time() + offset))


def world(tmp_path, monkeypatch, pids=None, after=None, start=None, keeper=True):  # 임시 루트 · plist·launchctl·ps 대역
    root, agents, stub = tmp_path / "home", tmp_path / "agents", tmp_path / "stub"
    [folder.mkdir() for folder in (root, agents, stub)]
    for label, alive in ((LABEL, True),) + (((KEEPER, False),) if keeper else ()):
        doc = {"Label": label, "ProgramArguments": ["python3", "-c", "x", str(root), "slack"], "KeepAlive": alive}
        plistlib.dump(doc, open(agents / f"{label}.plist", "wb"))
    plistlib.dump({"Label": "com.byz.ft2-other", "ProgramArguments": ["python3", str(tmp_path / "elsewhere")], "KeepAlive": True},
                  open(agents / "com.byz.ft2-other.plist", "wb"))   # 다른 설치 루트를 부르는 라벨 = 손 0
    for name in ("launchctl", "ps"):
        (stub / name).write_text(STUB, encoding="utf-8")
        (stub / name).chmod(stat.S_IRWXU)
    state = {"pids": {LABEL: 100, KEEPER: 300} if pids is None else pids, "after": {LABEL: 200} if after is None else after,
             "start": {"200": _lstart(3600)} if start is None else start, "kicks": []}
    (stub / "state.json").write_text(json.dumps(state), encoding="utf-8")
    for key, value in (("FT2_LAUNCH_AGENTS", agents), ("FT2_LAUNCHCTL", stub / "launchctl"), ("FT2_PS", stub / "ps"), ("R1826_STUB", stub)):
        monkeypatch.setenv(key, str(value))
    path = stub / "state.json"
    return root, lambda: json.loads(path.read_text())["kicks"], lambda **kv: path.write_text(json.dumps({**json.loads(path.read_text()), **kv}))


def run(capsys, *argv):
    rc = install.main(["install.py", *map(str, argv)])
    return rc, "".join(capsys.readouterr())


def test_case1_switch_reloads_keepalive_label(tmp_path, monkeypatch, capsys):
    root, kicks, patch = world(tmp_path, monkeypatch, pids={KEEPER: 300})   # V1 설치 때 slack-listen 아직 등록 전
    assert run(capsys, "install", shared.make_package(tmp_path, "V1"), root)[0] == 0
    patch(pids={LABEL: 100, KEEPER: 300})
    rc, out = run(capsys, "install", shared.make_package(tmp_path, "V2"), root)
    assert (rc, kicks(), (root / "CURRENT").read_text().strip()) == (0, [LABEL], "V2")
    assert out.count(f"RELOADED {LABEL} pid 100→200 기동 ") == 1 and "≥ CURRENT" in out
    assert f"SKIP {KEEPER} 바퀴마다 새로 뜸" in out and "com.byz.ft2-other" not in out


def test_case1b_no_switch_no_reload(tmp_path, monkeypatch, capsys):
    root, kicks, _ = world(tmp_path, monkeypatch)
    (root / "CURRENT").write_text("V1\n", encoding="utf-8")            # 판 V1 · versions 폴더 없음 → 같은 판 설치 = 전환 0
    assert (run(capsys, "install", shared.make_package(tmp_path, "V1"), root)[0], kicks()) == (0, [])
    assert (run(capsys, "install", tmp_path / "ft2-V1", root)[0], kicks()) == (2, [])   # 이미 있음 = 전환 0


def test_case1c_rollback_reloads(tmp_path, monkeypatch, capsys):
    root, kicks, patch = world(tmp_path, monkeypatch, start={pid: _lstart(3600) for pid in ("200", "201", "202")})
    for version, nxt in (("V1", 201), ("V2", 202)):                  # 바퀴마다 새 pid(100→200→201→202)
        assert run(capsys, "install", shared.make_package(tmp_path, version), root)[0] == 0
        patch(after={LABEL: nxt})
    rc, out = run(capsys, "rollback", root)
    assert (rc, kicks(), (root / "CURRENT").read_text().strip()) == (0, [LABEL] * 3, "V1")
    assert f"RELOADED {LABEL} pid 201→202" in out


def test_case2_keeper_and_unregistered_skip(tmp_path, monkeypatch, capsys):
    root, kicks, _ = world(tmp_path, monkeypatch, pids={KEEPER: 300})
    rc, out = run(capsys, "install", shared.make_package(tmp_path, "V1"), root)
    assert (rc, kicks()) == (0, [])
    assert f"SKIP {KEEPER} 바퀴마다 새로 뜸" in out and f"SKIP {LABEL} 등록 안 됨" in out


def test_case3_same_pid_is_unjudgeable_rc3(tmp_path, monkeypatch, capsys):
    root, kicks, _ = world(tmp_path, monkeypatch, after={LABEL: 100}, start={"100": _lstart(3600)})
    rc, out = run(capsys, "install", shared.make_package(tmp_path, "V1"), root)
    assert (rc, kicks(), (root / "CURRENT").read_text().strip()) == (3, [LABEL], "V1")
    assert out.count(f"RELOAD 판정 불가 {LABEL}") == 1 and "RELOADED" not in out


def test_case3b_start_before_current_is_unjudgeable_rc3(tmp_path, monkeypatch, capsys):
    root, kicks, _ = world(tmp_path, monkeypatch, start={"200": _lstart(-3600)})
    rc, out = run(capsys, "install", shared.make_package(tmp_path, "V1"), root)
    assert (rc, kicks(), (root / "CURRENT").read_text().strip()) == (3, [LABEL], "V1")
    assert f"RELOAD 판정 불가 {LABEL}" in out and "RELOADED" not in out


def test_case3c_launchctl_timeout_twice_is_unjudgeable_rc3(tmp_path, monkeypatch, capsys):
    root, kicks, _ = world(tmp_path, monkeypatch)
    real, calls = subprocess.run, []

    def slow(cmd, **kwargs):                                            # kickstart 만 7초 초과(대역 · sleep 0)
        if "kickstart" in cmd:
            calls.append(kwargs.get("timeout"))
            raise subprocess.TimeoutExpired(cmd, kwargs.get("timeout"))
        return real(cmd, **kwargs)

    monkeypatch.setattr(install.subprocess, "run", slow)
    rc, out = run(capsys, "install", shared.make_package(tmp_path, "V1"), root)
    assert (rc, calls, kicks(), (root / "CURRENT").read_text().strip()) == (3, [7, 7], [], "V1")
    assert f"RELOAD 판정 불가 {LABEL}" in out


def test_case4_projection_remaining_matches_capacity(tmp_path):
    core = FT2 / "core"
    intake, dispatch, projection = (_load(core / f"{name}.py", f"ft2_core_{name}_r1826") for name in ("intake", "dispatch", "projection"))
    root = str(tmp_path / "team")
    gate = intake.Intake(root, "harness", capacity=5)
    assert [gate.submit(cmd, "본문", dict(SLACK)).result for cmd in ("c1", "c2")] == ["접수 성공"] * 2
    assert dispatch.Dispatch(root, "harness").complete("c1").written
    out = projection.project(root, "harness")
    assert (out["remaining"], out["pending"]) == (1, 2)
    assert projection.project(str(tmp_path / "none"), "harness")["remaining"] == 0
