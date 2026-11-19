"""r2287 ft2 keeper — card_stage·card_archive 의 바깥 호출(git spawn · lib bash)이 모두 바퀴 예산 문(남은 몫 ≥ 7초)을 지나고,
SLOW-CELL 줄 끝에 그 칸의 오래 걸린 호출 3개와 호출 밖 초(top=… py=…)를 덧붙인다.
대역 = r1812 World(임시 리포·가짜 tmux·주입 시계 w.t) · 가짜 lib bash(ft_close_marker·ft_no_code·ft_land_kind 1회 6초) · 가짜 git 1회 4초 · sleep 0.
①~⑤ · 변이 M1~M3 = 자매 test_keeper_b1_budget_gate_mut_r2287.py."""
import importlib.util
import shutil
import subprocess
import time
import types
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r2287_kw", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
World, FT2 = kw.World, kw.FT2
GIT_S, BASH_S, WORK_S, CALL_S = 4, 6, 45, 7
LIBS = ("ft-team-lib.sh", "ft-land-kind-lib.sh")
REAL_RUN = subprocess.run


class Seen:
    """바깥 호출 시작 기록 — (길, 시작 때 남은 몫) · lib bash = 가짜(card_stage·card_archive 손 6초) · git = 진짜 + 4초(jump_git)."""
    def __init__(self, w, mp, step=BASH_S):
        self.w, self.k, self.starts, self.step = w, None, [], step
        mp.setattr(subprocess, "run", self.run)

    def left(self):
        return self.k.left() if self.k is not None else None

    def run(self, argv, *a, **kw):
        if not (argv[:1] == ["bash"] and any(x.endswith(LIBS) for x in argv)):
            return REAL_RUN(argv, *a, **kw)
        fn = argv[5] if argv[5:6] and argv[5].startswith("ft_") else "ft_close_marker"   # lib_call = [bash -c 글 x lib fn …] · da_judge = [… lib stem]
        self.starts.append((fn, self.left()))
        self.w.t += 0 if "cwd" in kw else self.step   # keeper.call(cwd=root · 이미 문 안) = 0초 · card_stage·card_archive 손 = 6초
        rc, out = {"ft_no_code": (1, ""), "ft_land_kind": (0, "구현\n"), "ft_close_marker": (1, "")}[fn]
        return subprocess.CompletedProcess(argv, rc, out if kw.get("text") else out.encode(), "" if kw.get("text") else b"")


def keeper(w, mp, seen, git=None):
    """주입 시계 keeper — left() = w.t 기준 · card_stage spawn = git(대역) 을 keeper 가 문으로 감쌈."""
    k = w.keeper()
    mp.setitem(k.run_once.__globals__, "time", types.SimpleNamespace(monotonic=lambda: w.t, time=time.time))
    seen.k = k
    if git:
        mp.setattr(k.cs, "spawn", git(k, k.cs.spawn))
    return k


def jump_git(seen, w):
    """가짜 git 1회 4초 · 카드 본문 show 뒤 남은 몫 5초로 시계를 옮김(주입 시계 · 다음 호출 = lib bash 차례)."""
    jumped = []
    def wrap(k, real):
        def spawn(cwd, args, env=None):
            seen.starts.append(("git " + args[0], k.left()))
            out = real(cwd, args, env)
            w.t += GIT_S
            if not jumped and args[:1] == ["show"] and str(args[1]).endswith("-x.md"):
                jumped.append(w.t)
                w.t = max(w.t, k.start + WORK_S - 5)
            return out
        return spawn
    return wrap


def c1(w, mp):   # ① 대역 — STAGE 대상 카드 여럿 · bash 6초 · git 4초 → 문 밖 시작 0 · 셀 ≤ 45 + 7 · 남은 카드 DEFER · OVER 0
    for work in ("r9871", "r9872"):
        w.card(work, w.land_sha(), refs=("ops/main-base",)), w.work(work, intent=False)
    seen = Seen(w, mp)
    k = keeper(w, mp, seen, jump_git(seen, w))
    t0, lines = w.t, w.round(k)
    late = [x for x in seen.starts if x[1] is not None and x[1] < CALL_S]
    assert seen.starts and not late, (seen.starts, lines)   # 남은 몫 < 7초에 시작한 바깥 호출 0(문 밖 0)
    assert max(k.per.values()) <= WORK_S + CALL_S and w.t - t0 <= WORK_S + CALL_S, (k.per, lines)
    defer = [x.split(" card_stage")[0] for x in lines if x.startswith("DEFER")]
    assert defer and set(defer) <= {"DEFER harness r9871", "DEFER harness r9872"}, lines
    rnd = [x for x in lines if x.startswith("ROUND ")]
    assert len(rnd) == 1 and " OVER" not in rnd[0] and not any(x.startswith("CARD-STAGE") for x in lines), lines


def at_left(w, k, left):
    w.t = k.start + WORK_S - left   # 주입 시계 — 업무 구획 끝까지 left 초


def c2(w, mp):   # ② 남은 몫 6초에서 da_judge 차례 → bash 시작 0 · OutOfRound → DEFER 1줄 · 쓰기 0
    w.card("r9873", w.land_sha(), refs=("ops/main-base",)), w.work("r9873", intent=False)
    seen = Seen(w, mp)
    k = keeper(w, mp, seen)
    def stage(byz, root, team, work, at, now, da=None, gate=None):
        at_left(w, k, 6)
        return k.cs.da_judge(root, "## 판정 §1\n닫힘 — r9873-x — APPROVE\n", "§1", "r9873-x")
    mp.setattr(k.cs, "stage", stage)
    lines = w.round(k)
    assert not [x for x in seen.starts if x[0] == "ft_close_marker"], (seen.starts, lines)
    assert [x.split(" card_stage")[0] for x in lines if x.startswith("DEFER")] == ["DEFER harness r9873"], lines
    assert not any(x.startswith(("CARD-STAGE", "NOOP harness")) for x in lines), lines
    assert "harness|r9873" not in k.state.get("staged", {}), k.state.get("staged")


def archive_mod(w):
    spec = importlib.util.spec_from_file_location("r2287_archive_%d" % id(w), str(w.ft2 / "adapters" / "pi" / "card_archive.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def c3(w, mp):   # ③ card_archive.judge 같은 꼴 → bash 시작 0 · OutOfRound(keeper = DEFER)
    seen, arch = Seen(w, mp), archive_mod(w)
    k = keeper(w, mp, seen)
    k.start, k.sect = w.t, WORK_S
    mp.setattr(arch.cs, "proc", k.gate(arch.cs.proc, lambda argv, *a, **kw: "bash"))
    at_left(w, k, 6)
    K = k.run_once.__globals__
    with pytest.raises(K["OutOfRound"]):
        arch.judge(str(w.root), "## 판정 §1\n닫힘 — r9874-x — 버림\n", "§1", "r9874-x")
    assert seen.starts == [], seen.starts


def c4(w, mp):   # ④ 느린 칸 — 호출 4초 × 3 + 파이썬 5초 → SLOW-CELL 줄 끝 «top=… py=5» · 초 큰 순 · 기존 칸 그대로
    w.card("r9875", w.land_sha(), refs=("ops/main-base",)), w.work("r9875", intent=False)
    seen = Seen(w, mp, 0)
    def git(k, real):
        def spawn(cwd, args, env=None):
            w.t += {"fetch": 4.0, "show": 4.0, "log": 4.0}.get(args[0], 0.0)
            return 0, ""
        return spawn
    k = keeper(w, mp, seen, git)
    def stage(byz, root, team, work, at, now, da=None, gate=None):
        for verb in ("fetch", "show", "log"):
            k.cs.spawn(byz, [verb, "-q"])
        w.t += 5.0   # 호출 밖 파이썬 초
        return "r9875-x", "진행→완성", "c0ffee"
    mp.setattr(k.cs, "stage", stage)
    lines = w.round(k)
    slow = [x for x in lines if x.startswith("SLOW-CELL ")]
    assert len(slow) == 1, lines
    head, _, tail = slow[0].partition(" top=")
    assert head.startswith("SLOW-CELL harness b1 s=17 n=") and " slow_call=" in head, slow
    assert tail == "git+fetch:4,git+show:4,git+log:4 py=5", slow
    rnd = [x for x in lines if x.startswith("ROUND ")]
    assert len(rnd) == 1 and "slow=harness:b1:17" in rnd[0] and "top=" not in rnd[0], rnd


def c5(w, mp):   # ⑤ 바퀴 밖(left None) card_stage·card_archive 손 단독 → 지금과 같은 출력 · 호출 상한 7초 그대로
    seen, arch = Seen(w, mp), archive_mod(w)
    caps = []
    def run(argv, *a, **kw):
        caps.append(kw.get("timeout"))
        return seen.run(argv, *a, **kw)
    mp.setattr(subprocess, "run", run)
    cs = arch.cs
    assert cs.da_judge(str(w.root), "## 판정 §1\n본문\n", "§1", "r9876-x") == "§1 에 r9876-x 닫힘 표식 없음"
    lib = str(w.root / ".fable-team" / "bin" / "ft-land-kind-lib.sh")
    assert cs.sh(["bash", "-c", "x", "x", lib, "ft_no_code"], 7) == (1, "")
    assert cs.sh(["bash", "-c", "x", "x", lib, "ft_land_kind"], 7) == (0, "구현\n")
    assert arch.judge(str(w.root), "## 판정 §1\n닫힘 — r9876-x — 버림\n", "§1", "r9876-x") is None
    assert caps == [7, 7, 7, 7] and [x[1] for x in seen.starts] == [None] * 4, (caps, seen.starts)


CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch), monkeypatch)


def mutant(tmp_path, monkeypatch, rel, pairs, case):
    """사본 ft2 의 변이(pairs = [(old, new)] · 각 old 1회) → 사례 FAIL · 원본으로 같은 사례 1회 더 = PASS."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (rel, old)
        text = text.replace(old, new)
    (tree / rel).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        with monkeypatch.context() as mp:
            case(World(tmp_path / "w1", mp, tree), mp)
    with monkeypatch.context() as mp:
        case(World(tmp_path / "w2", mp), mp)
