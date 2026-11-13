"""r1840 keeper 착지 대기 헛울림 0 · 역할 = intent 칸 (카드 반례 ①~⑤ · 변이 M1~M5 · DA#10 #295168).
입력 = r1813 시험 대역(World: 실제 core · 실제 launch.py · 가짜 tmux·ps·세션 파일 · 주입 시계) 재사용 · sleep 0 · 실 tmux·pi 0.
기준판(팩 origin/main) = ① ② ④ Red. 변이는 사본에서만 · 변이마다 원본으로 1회 더.
"""
import importlib.util, json, os, shutil, subprocess, sys  # noqa: E401
from pathlib import Path
import pytest

FT2 = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("r1813_world_for_r1840", str(FT2 / "tests" / "test_pi_keeper_stall_r1813.py"))
B = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(B)
W, M, H0, H1, T0, TEAM = B.W, B.M, B.H0, B.H1, B.T0, B.TEAM
# ④ 열기 순간의 intent 를 남기는 tmux 대역(new-session 때 intent 파일 복사 · 그 밖은 r1813 대역에 넘김)
SNAP = '#!/bin/sh\n[ "$1" = new-session ] && cat "$FAKE_RUNTIME"/launch/*.intent >> "$0.snap"\nexec "$FAKE_TMUX_REAL" "$@"\n'


def _intent(w, attempt="a1"):
    return json.loads((w.runtime() / "launch" / ("%s@%s.intent" % (W, attempt))).read_text(encoding="utf-8"))


def _set_intent(w, **kv):
    B._put(w.runtime() / "launch" / ("%s@a1.intent" % W), dict(_intent(w), **kv))


def _pids(w):   # argv 판독 = #{pane_pid} 조회만(r1839 #{session_attached} 조회는 셈 밖)
    return [x for x in w.tmux("display-message") if "#{pane_pid}" in x["a"]]


def _wake_lines(w):
    return [x for x in w.k.lines if x.startswith("WOKE")]


def c1(w):   # ① 최신 attempt 마지막 단계 = result · 진척 20분 0 · IDLE → 깨움 0 · 재배정 0 · tmux 호출 0 · 로그 0
    w.seat(step=-20 * M)
    assert w.cli(T0 - 20 * M, "result", "--work", W, "--holder", H0, "--gen", "1")[1] == 0
    for dt in (0, 11 * M, 30 * M):
        lines = w.round(dt)
        assert not [x for x in lines if H0 in x], lines   # 착지 판독(B1) 줄은 holder 를 안 담는다
    assert B._lines(str(w.tm) + ".log") == [] and w.kinds("dispatch") == 1 and w.notes() == []


def c1b(w):  # ①′ result 뒤 complete → check 대상 밖 · 깨움 0
    w.seat(step=-20 * M)
    assert w.cli(T0 - 20 * M, "result", "--work", W, "--holder", H0, "--gen", "1")[1] == 0
    assert w.cli(T0 - 19 * M, "complete", "--work", W, "--attempt", "a1")[1] == 0
    w.round()
    assert _wake_lines(w) == [] and not [x for x in w.tmux("send-keys") if "-l" in x["a"]]


def c1c(w):  # ①″ 옛 attempt(a1) 에 result · 새 dispatch(a2)+deliver 뒤 단계 없음 → K1 해당 없음 → 새 holder 깨움 1
    w.seat(step=-40 * M, commit=-40 * M)
    assert w.cli(T0 - 39 * M, "result", "--work", W, "--holder", H0, "--gen", "1")[1] == 0
    assert w.cli(T0 - 30 * M, "assign", "--work", W, "--holder", H1, "--evidence", "v1,v2", "--rotation", "true")[1] == 0
    assert w.cli(T0 - 30 * M, "deliver", "--work", W)[1] == 0
    tree = w.tree("a2")
    B._git(w.repo, "worktree", "add", "-q", "--detach", str(tree), w.c1)
    B._put(w.runtime() / "launch" / ("%s@a2.intent" % W), {"FT2_HOLDER": H1, "state": "opened", "worktree": str(tree), "role": "session"})
    w.session(tree, -20 * M)
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"].append(H1)
    B._put(w.tm, d)
    assert ("WOKE harness %s %s" % (W, H1)) in w.round()


def c2(w):   # ② intent role 칸 없음 · argv `--model` 만 → 깨움 뒤 11분: 재배정 0 · 판정 불가 1 · 크리티컬 0 · reassigned 0 · kill 0
    w.seat()
    B._put(w.ps, "node /x/pi --model claude-opus-5-5\n")
    w.round()
    lines = w.round(11 * M)
    hit = [x for x in lines if x.startswith("판정 불가") and "역할 못 정함(intent role 칸 없음 · argv" in x and "재배정 0" in x]
    assert len(hit) == 1, lines
    assert w.notes() == [] and w.k.state.get("reassigned", {}) == {} and w.tmux("kill-session") == [] and w.kinds("dispatch") == 1
    assert not [x for x in lines if x.startswith("HELD-STALL")]


def c3(w):   # ③ intent role=session → argv 판독 0(display-message 0) · 재배정 진행(assign·deliver·launch)
    w.seat()
    _set_intent(w, role="session")
    B._put(w.ps, "pi --model gpt-x --thinking low\n")
    w.round()
    assert any(x.startswith("REASSIGNED harness %s %s -> %s" % (W, H0, H1)) and "role=session" in x for x in w.round(11 * M))
    assert _pids(w) == [] and w.kinds("dispatch") == 2 and len(w.tmux("new-session")) == 1


def c3b(w):  # ③′ intent role=없는역할 → 표에 없음 → argv 판독(opus-5-5/medium = session) · 대신 0
    w.seat()
    _set_intent(w, role="없는역할")
    w.round()
    assert any(x.startswith("REASSIGNED harness %s" % W) and "role=session" in x for x in w.round(11 * M)), w.k.lines
    assert len(_pids(w)) == 1


def c4(w):   # ④ launch.py 실행(대역 git·tmux) → opening·opened intent 둘 다 role = --role 값 · 기본 = session
    for sub, extra, want in (("d", [], "session"), ("m", ["--role", "master"], "master")):
        v = B.World(w.tmp / sub, w.mp, w.ft2)
        for argv in (["submit", "--command", "c-" + W, "--body", "본문", "--work", W],
                     ["assign", "--work", W, "--holder", H0, "--evidence", "v1,v2"], ["deliver", "--work", W]):
            assert v.cli(T0, *argv)[1] == 0
        snap = v.tmp / "bin2" / "tmux"
        B._put(snap, SNAP), snap.chmod(0o755)
        env = dict(v.env, PATH=str(snap.parent) + os.pathsep + v.env["PATH"], FAKE_TMUX_REAL=v.env["FT_TMUX"])
        argv = [sys.executable, str(v.ft2 / "adapters" / "pi" / "launch.py"), "--root", str(v.root), "--team", TEAM, "--work", W,
                "--repo", str(v.repo), "--base", v.c1] + extra
        done = subprocess.run(argv, capture_output=True, text=True, timeout=25, env=env)
        assert done.returncode == 0, done.stdout + done.stderr
        opening = [json.loads(x) for x in B._lines(str(snap) + ".snap")]
        assert [x["state"] for x in opening] == ["opening"] and opening[0].get("role") == want, (sub, opening)
        got = _intent(v)
        assert got["state"] == "opened" and got.get("role") == want, (sub, got)


def c5(w):   # ⑤ 진짜 멈춤(마지막 단계 effect · 진척 20분 · IDLE) → 깨움 1(회귀 · 재배정 경로는 r1813 ③·④)
    w.seat(effect=True)
    assert ("WOKE harness %s %s" % (W, H0)) in w.round()
    assert len(w.tmux("send-keys")) == 3


CASES = {"①": c1, "①′": c1b, "①″": c1c, "②": c2, "③": c3, "③′": c3b, "④": c4, "⑤": c5}
KS, LA = "adapters/pi/keeper_stall.py", "adapters/pi/launch.py"
MUTANTS = {"M1": (KS, '[-1:] == ["result"]:', '[-1:] == ["없음"]:', c1),
           "M2": (KS, "for r in mine[cut:] if", "for r in mine if", c1c),
           "M3": (KS, "if not role and not missing:", "if False:", c2),
           "M4": (KS, 'intent.get("role") if intent.get("role") in models.role_defaults() else None', 'intent.get("role")', c3b),
           "M5": (LA, 'dict(env, state="opening", role=item["role"],', 'dict(env, state="opening",', c4)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](B.World(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(B.World(tmp_path / "w1", monkeypatch, tree))
    case(B.World(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
