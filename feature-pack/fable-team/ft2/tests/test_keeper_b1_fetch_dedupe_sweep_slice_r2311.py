"""r2311 keeper — 바퀴 안 card_stage 첫 fetch 중복 0(K1·K2) · b3r sweep 팀 쪼개기(K4) · sweep 안쪽 초 SLOW-SEAT(K3).
K1·K2 대역 = r1812 World(임시 리포·가짜 tmux) + 실제 card_stage 모듈 사본(run·pins·card·evidence·commit_tree·push 만 가짜 · git 0).
K3·K4 대역 = 가짜 keeper(주입 시계 self.t · 가짜 git·tmux 손 · Cut = BaseException) 위 실제 CloseOld · 실 tmux kill 0 · 네트워크 0 · sleep 0.
반례 ①~⑧ · ①b · ⑤b · 기준판(BASE git archive) Red = ① ⑤ ⑦ · 변이 M1~M8 = 사본에서만(원본 = 같은 사례 통과 시험이 대조).
"""
import copy
import importlib.util
import shutil
import subprocess
import types

import pytest

import keeper_world_r1812 as kw

FT2, BASE = kw.FT2, "714b220fd3"
KP, CS, KO = "adapters/pi/keeper.py", "adapters/pi/card_stage.py", "adapters/pi/keeper_close_old.py"
FIRST, REFETCH = ("fetch", "-q", "origin", "ops/main-base", "main"), ("fetch", "-q", "origin", "ops/main-base")


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ---- K1·K2 — card_stage 첫 fetch ----
def stage_mod(ft2, pushes=()):
    """실제 card_stage 사본 · git 손만 가짜 — fetch argv 기록 · push 차례(1 = 거절)."""
    cs = _mod(ft2 / CS, "r2311_cs_%d" % id(ft2))
    cs.fetches, plan = [], list(pushes)
    cs.run = lambda cwd, *args: cs.fetches.append(args) if args[:1] == ("fetch",) else ""
    cs.pins = lambda byz: {r: "a" * 40 for r in cs.land.REFS}
    cs.card = lambda byz, root, team, work, sha: ("origin/ops/main-base", "design/harness/indices/진행/%s.md" % work)
    cs.evidence = lambda *a: None
    cs.commit_tree = lambda *a: "c" * 40
    cs.push = lambda byz, sha, ref, timed=False: plan.pop(0) if plan else 0
    cs.done_at = lambda root, team, work: "2026-11-20T00:00:00"
    return cs


def round_k1(tmp, mp, ft2, works=("r9311", "r9312", "r9313"), targets=None, pushes=()):
    tmp.mkdir(parents=True, exist_ok=True)
    w = kw.World(tmp, mp, ft2)
    for work in works:
        w.card(work, w.pack_sha()), w.work(work, intent=False)
    if targets is not None:
        kw._put(w.state / "ft2-keeper" / "FETCH_TARGETS", targets)
    k = w.keeper()
    k.cs = cs = stage_mod(ft2, pushes)
    lines = w.round(k)
    return cs.fetches, sorted(x for x in lines if x.startswith("CARD-STAGE")), lines


def c1(tmp, mp, ft2=FT2):   # ① fresh 바퀴 · 끝난 work 3 → 첫 fetch 0 · 카드 3장 결과
    fetches, staged, lines = round_k1(tmp, mp, ft2)
    assert staged == ["CARD-STAGE harness %s 진행→완성 %s" % (w, "c" * 40) for w in ("r9311", "r9312", "r9313")], lines
    assert fetches == [], fetches


def c1b(tmp, mp, ft2=FT2):   # ①b FETCH_TARGETS root = main 만 → 첫 fetch 지금처럼 1회
    fetches, staged, lines = round_k1(tmp, mp, ft2, works=("r9311",), targets="root\tmain\npack\tmain\n")
    assert staged == ["CARD-STAGE harness r9311 진행→완성 %s" % ("c" * 40)], lines
    assert fetches == [FIRST], fetches


def c2(tmp, mp, ft2=FT2):   # ② push 거절 1회 → 그 work 만 fetch 1회 · 새 끝에서 다시 커밋
    fetches, staged, lines = round_k1(tmp, mp, ft2, works=("r9311",), pushes=(1, 0))
    assert staged == ["CARD-STAGE harness r9311 진행→완성 %s" % ("c" * 40)], lines
    assert fetches == [REFETCH], fetches


def c3(tmp, mp, ft2=FT2):   # ③ root stale(FETCH_TARGETS 밖) → B1 0 · stage 0
    fetches, staged, lines = round_k1(tmp, mp, ft2, works=("r9311",), targets="pack\tmain\n")
    assert staged == [] and fetches == [], (fetches, lines)
    assert any(x.startswith("판정 불가 FETCH_TARGETS 밖") for x in lines), lines


def c4(tmp, mp, ft2=FT2, capsys=None):   # ④ CLI 1회 → 첫 fetch 1회(K2)
    cs = stage_mod(ft2)
    assert cs.main(["--root", str(tmp), "--team", "harness", "--work", "r9311"]) == 0
    assert cs.fetches == [FIRST], cs.fetches


# ---- K3·K4 — sweep ----
class Cut(BaseException):
    pass


class FakeK:
    """가짜 keeper — 주입 시계 t · 남은 몫 = budget - t · git 비용 cost[(좌석, 동사)] · cut = (좌석, 동사) 에서 Cut."""
    MIN_S, tmux, halt = 1, "tmux", False

    def __init__(self, alive, state=None, budget=1000.0, cost=None, cut=None):
        self.t, self.budget, self.cost, self.cut = 0.0, budget, cost or {}, cut
        self.alive, self.state, self.lines, self.kills, self.seen = set(alive), state if state is not None else {}, [], [], []
        self.team_list = []

    def now(self):
        return self.t

    def left(self):
        return self.budget - self.t

    def teams(self):
        return list(self.team_list)

    def alive_sessions(self):
        return set(self.alive)

    def stamp(self):
        return "2026-11-20T01:00:00"

    def log(self, kind, team="", text=""):
        self.lines.append(" ".join(w for w in (kind, team, text) if w))

    def verdict(self, *a):
        self.log("VERDICT", text=" ".join(map(str, a)))
        return True

    def git(self, tree, *args):
        seat = tree.rpartition("/")[2]
        self.seen.append(seat) if args[0] == "status" else None
        self.t += self.cost.get((seat, args[0]), 0.0)
        if self.cut == (seat, args[0]):
            raise Cut("cut")
        return (0, "", "") if args[0] != "rev-parse" else (0, "h" * 40, "")

    def turn_ended(self, *a):
        return True

    def idle(self, *a):
        return True

    def attached(self, seat):
        return "free"

    def call(self, argv):
        self.kills.append(argv[-1][1:])
        self.alive.discard(argv[-1][1:])
        return 0, "", ""

    def probe(self, seat):
        return "absent" if seat not in self.alive else "alive"


def old(team, n=1):
    return "byz-%s-nano-r9%d-x#1" % (team, n)


def new(team, n=1):
    return "byz-%s-nano-r9%d-x#2" % (team, n)


def sweeper(ft2, k, layout):
    """layout = {팀: 좌석 쌍 수} → 실제 CloseOld · endings.latest·intents = 표(장부·intent 파일 0) · resume = 통과(기록 0)."""
    mod = _mod(ft2 / KO, "r2311_ko_%d" % id(k))
    k.team_list = list(layout)
    last = {t: {"w%d" % n: (None, new(t, n)) for n in range(1, c + 1)} for t, c in layout.items()}
    mod.endings = types.SimpleNamespace(latest=lambda kk, team: last.get(team))
    co = mod.CloseOld(k)
    co.intents = lambda team: {s: ("w%d" % n, {"worktree": "/t/" + s}) for n in range(1, layout.get(team, 0) + 1) for s in (old(team, n), new(team, n))}
    co.resume = lambda seat, nw, intent: ""
    return co


def world(layout):
    return {s for t, c in layout.items() for n in range(1, c + 1) for s in (old(t, n), new(t, n))}


L3 = {"ta": 1, "tb": 1, "tc": 1}


def c5(tmp, mp, ft2=FT2):   # ⑤ 둘째 팀 끝 남은 몫 0 → 셋째 팀 0 · cursor = tc · 다음 바퀴 tc 부터 · 다 돌면 지움
    k = FakeK(world(L3), budget=20.5, cost={(old(t), "status"): 10.0 for t in L3})
    sweeper(ft2, k, L3).sweep()
    assert k.kills == [old("ta"), old("tb")] and k.state.get("sweep_cursor") == "tc", (k.kills, k.state)
    k2 = FakeK(k.alive, state=copy.deepcopy(k.state))
    sweeper(ft2, k2, L3).sweep()
    assert k2.kills == [old("tc")] and "sweep_cursor" not in k2.state, (k2.kills, k2.state)


def c5b(tmp, mp, ft2=FT2):   # ⑤b 둘째 팀 안 keep git 에서 Cut → cursor = tb · 다음 바퀴 tb 부터
    k = FakeK(world(L3), cut=(old("tb"), "status"))
    with pytest.raises(Cut):
        sweeper(ft2, k, L3).sweep()
    assert k.kills == [old("ta")] and k.state.get("sweep_cursor") == "tb", (k.kills, k.state)
    k2 = FakeK(k.alive, state=copy.deepcopy(k.state))
    sweeper(ft2, k2, L3).sweep()
    assert k2.seen[:1] == [old("tb")] and k2.kills == [old("tb"), old("tc")] and "sweep_cursor" not in k2.state, (k2.seen, k2.kills, k2.state)


def c6(tmp, mp, ft2=FT2):   # ⑥ 한 팀 좌석 2 · 첫 좌석 뒤 남은 몫 0 → 둘째 좌석도 그 팀에서 마저 · 다음 팀부터 끊음
    lay = {"ta": 2, "tb": 1}
    k = FakeK(world(lay), budget=10.5, cost={(old("ta", 1), "status"): 10.0})
    sweeper(ft2, k, lay).sweep()
    assert k.kills == [old("ta", 1), old("ta", 2)] and k.state.get("sweep_cursor") == "tb", (k.kills, k.state)


def c7(tmp, mp, ft2=FT2):   # ⑦ keep 6초 → SLOW-SEAT 1줄 step=sweep:keep · 4초 = 줄 0
    k = FakeK(world(L3), cost={(old("tb"), "status"): 6.0})
    sweeper(ft2, k, L3).sweep()
    assert [x for x in k.lines if x.startswith("SLOW-SEAT")] == ["SLOW-SEAT tb %s s=6 step=sweep:keep" % old("tb")], k.lines
    k2 = FakeK(world(L3), cost={(old("tb"), "status"): 4.0})
    sweeper(ft2, k2, L3).sweep()
    assert [x for x in k2.lines if x.startswith("SLOW-SEAT")] == [], k2.lines


def c8(tmp, mp, ft2=FT2):   # ⑧ cursor 팀이 목록에 없음 → 처음부터 · 판정 불가 0
    k = FakeK(world(L3), state={"sweep_cursor": "gone"})
    sweeper(ft2, k, L3).sweep()
    assert k.kills == [old(t) for t in L3] and "sweep_cursor" not in k.state, (k.kills, k.state)
    assert not [x for x in k.lines if x.startswith("판정 불가")], k.lines


CASES = {"①": c1, "①b": c1b, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑤b": c5b, "⑥": c6, "⑦": c7, "⑧": c8}


@pytest.mark.parametrize("label", list(CASES))
def test_case(label, tmp_path, monkeypatch):
    CASES[label](tmp_path, monkeypatch)


def base_tree(tmp):
    out = tmp / "base" / "ft2"
    out.mkdir(parents=True)
    top = subprocess.run(["git", "-C", str(FT2), "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=25, check=True).stdout.strip()
    tar = subprocess.run(["git", "-C", top, "archive", BASE + ":feature-pack/fable-team/ft2"], capture_output=True, timeout=25, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(out)], input=tar, timeout=25, check=True)
    return out


@pytest.mark.parametrize("label", ["①", "⑤", "⑦"])
def test_base_red(label, tmp_path, monkeypatch):
    ft2 = base_tree(tmp_path)
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w", monkeypatch, ft2)


MUTANTS = {
    "M1": (KP, "**self.no_fetch())", ")", "①"),
    "M2": (CS, '        run(byz, "fetch", "-q", "origin", ref.split("/", 1)[1])', '        fetch and run(byz, "fetch", "-q", "origin", ref.split("/", 1)[1])', "②"),
    "M3": (CS, "gate=None, fetch=True):", "gate=None, fetch=False):", "④"),
    "M4": (KO, "if n + 1 < len(teams) and left is not None and left < k.MIN_S:", "if False:", "⑤"),
    "M5": (KO, "                self.seat(team, seat, alive, hit)\n",
           "                self.seat(team, seat, alive, hit)\n                if k.left() is not None and k.left() < k.MIN_S:\n                    break\n", "⑥"),
    "M6": (KO, "SEAT_S, SEAT_CAP = 5, 5", "SEAT_S, SEAT_CAP = 50, 5", "⑦"),
    "M7": (KP, " and all(x in self.refs.get(self.root, ()) for x in want)", "", "①b"),
    "M8": (KO, 'k.state["sweep_cursor"] = teams[n]   #', 'k.state["sweep_cursor"] = teams[min(n + 1, len(teams) - 1)]   #', "⑤b"),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, before, after, label = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = tree / rel
    text = path.read_text(encoding="utf-8")
    assert text.count(before) == 1, (name, before)
    path.write_text(text.replace(before, after), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w", monkeypatch, tree)
