"""r2315 keeper 나노 가지 모으기 — 넘김·끊김 때 팀마다 초 · git 수 · 판독한 work 수 · 가장 느린 work 를 1줄로 남긴다.

계약 N1(팀 셈 = keeper_fetch.nanos 가 돌려준다) · N2(넘김·끊김 때 NANO-SLOW 1줄) · N3(판정·순서·끊김 규칙 불변).
반례 ①~⑦ · 변이 M1~M5(사본에서만 · 원본으로 같은 사례 1회 더 = 반대 결과 대조).
대역 = test_keeper_nano_collect_file_read_r2122 의 K·W(파일 판독 · 가짜 git) + test_keeper_round_60s.Rig(주입 시계 · 가짜 subprocess).
sleep 0 · 네트워크 0 · 실 runtime·실 tmux·실 명부 읽기 0.
"""
import json
import shutil

import pytest

from test_keeper_nano_collect_file_read_r2122 import K, W, load, rp
from test_keeper_round_60s import Rig, line

KP, KF = "adapters/pi/keeper.py", "adapters/pi/keeper_fetch.py"
NANO_LINE = "판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만"


class Got(dict):
    """돌려준 dict + 팀 셈(계약 N1) — 실제 keeper_fetch.Got 과 같은 꼴."""
    stat = None


def _tree():   # 기준 나무 = 이 시험 파일 옆 ft2
    import pathlib
    return pathlib.Path(__file__).resolve().parents[1]


# ── keeper 대역(시계 주입 · kf.nanos 만 갈아 끼운다) ──────────────────────────
def _world(w, plan, stat=None):
    """팀마다 plan[팀] = («ok»|«cut», 초) · stat[팀] = NANO-SLOW 칸에 실릴 셈."""
    w.teams = sorted(plan)
    w.works = {t: ["w" + t[-1]] for t in w.teams}
    g = w.mod.Keeper.__init__.__globals__

    def nanos(k, teams):
        team = teams[0]
        kind, sec = plan[team]
        w.wait(sec)
        if kind == "cut":
            raise k.cut_at()
        got = Got()
        got.stat = {team: dict((stat or {})[team])} if (stat or {}).get(team) else {}
        got["/repo/" + team] = ["nano/" + team]
        return got
    g["kf"].nanos = nanos


def _journal(w):
    rows = []
    for path in sorted((w.root / ".fable-team" / "state" / "ft2-keeper").glob("*.jsonl")):
        rows += [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]
    return rows


def _slow(w):
    return [x for x in w.k.lines if x.startswith("NANO-SLOW")]


# ── N1 팀 셈 ─────────────────────────────────────────────────────────────────
def c1(tree, tmp):   # ① 파일 판독 work 1(git 0) + 못 읽는 work 1(git 2) → 셈 = git 2 · works 2 · 초·rows > 0 · 가장 느린 work
    kf, w = load(tree, "kf_r2315_c1_" + str(id(tmp))), W(tmp)
    repo = w.repo()
    w.job("t", "a", w.linked(repo, "a"))
    bad = w.tmp / "bad" / "x"
    bad.mkdir(parents=True)
    (bad / ".git").write_text("nope\n", encoding="utf-8")   # _head 못 읽음 = git 길
    w.job("t", "x", bad)
    k = K(w.root, fake={str(bad): {"rev-parse": "nano/x", "common": str(w.tmp / "common")}})
    got = kf.nanos(k, ["t"])
    assert got == {rp(repo / ".git"): ["nano/a"], rp(w.tmp / "common"): ["nano/x"]}, got
    cell = got.stat["t"]
    assert (cell["git"], cell["works"]) == (2, 2), cell
    assert cell["s"] > 0 and cell["rows"] > 0 and cell["other"] >= 0, cell
    assert cell["slow"][0] in ("a", "x") and 0 <= cell["slow"][1] <= cell["s"], cell
    assert set(got.stat) == {"t"}, got.stat


# ── N2 넘김 줄 ──────────────────────────────────────────────────────────────
def c2(tree, tmp):   # ② 안 넘김(팀 2 · 각 1초) → NANO-SLOW 0줄(일지에도 0)
    w = Rig(tmp, tree)
    _world(w, {"t1": ("ok", 1.0), "t2": ("ok", 1.0)})
    w.round()
    assert _slow(w) == [] and [r for r in _journal(w) if "NANO-SLOW" in r["line"]] == [], w.k.lines


def c3(tree, tmp):   # ③ 넘김(4초 + 4초) → NANO-SLOW 1줄 · 팀마다 초·rows·git·works·slow·other
    stat = {"t1": {"s": 4.0, "rows": 0.05, "git": 2, "works": 10, "slow": ("w2", 2.5), "other": 1.45},
            "t2": {"s": 4.0, "rows": 0.01, "git": 0, "works": 1, "slow": ("w3", 3.0), "other": 0.99}}
    w = Rig(tmp, tree)
    _world(w, {"t1": ("ok", 4.0), "t2": ("ok", 4.0)}, stat)
    w.round()
    assert _slow(w) == ["NANO-SLOW 합 8.00 · t1 s=4.00 rows=0.05 git=2 works=10 slow=w2:2.50 other=1.45"
                        " · t2 s=4.00 rows=0.01 git=0 works=1 slow=w3:3.00 other=0.99"], w.k.lines


# ── N3 불변 ─────────────────────────────────────────────────────────────────
def c4(tree, tmp):   # ④ 모은 값 그대로 = linked worktree 2개 → 공용 폴더 키 1개 · git 0
    kf, w = load(tree, "kf_r2315_c4_" + str(id(tmp))), W(tmp)
    repo = w.repo()
    for work in ("a", "b"):
        w.job("t", work, w.linked(repo, work))
    k = K(w.root)
    assert kf.nanos(k, ["t"]) == {rp(repo / ".git"): ["nano/a", "nano/b"]} and k.calls == [], k.calls


def c5(tree, tmp):   # ⑤ 끊김 = 옛 줄 글자·team 칸 그대로 · nano_next = 끊긴 팀 · 모은 것만
    w = Rig(tmp, tree)
    _world(w, {"t1": ("ok", 0.5), "t2": ("cut", 0.5)})
    w.round()
    assert line(w.k, "판정 불가") == [NANO_LINE], w.k.lines
    assert [(r["kind"], r["team"]) for r in _journal(w) if r["line"] == NANO_LINE] == [("판정 불가", "t2")], _journal(w)
    assert w.state().get("nano_next") == "t2", w.state()
    assert w.k.nano == {"/repo/t1": ["nano/t1"]}, w.k.nano


# ── N1 rows·other ───────────────────────────────────────────────────────────
def c6(tree, tmp):   # ⑥ rows = journal 판독 초(한 팀 1회 · > 0) · other = 팀 초 − rows − work 초 · 음수 0
    kf, w = load(tree, "kf_r2315_c6_" + str(id(tmp))), W(tmp)
    repo = w.repo()
    w.job("t", "a", w.linked(repo, "a"))
    seen = []
    real = kf.ends._rows
    kf.ends._rows = lambda k_, t_: (seen.append(t_), real(k_, t_))[1]
    try:
        cell = kf.nanos(K(w.root), ["t"]).stat["t"]
    finally:
        kf.ends._rows = real
    assert seen == ["t"], seen
    assert cell["rows"] > 0 and cell["rows"] <= cell["s"], cell
    assert cell["other"] >= 0 and abs(cell["other"] - (cell["s"] - cell["rows"] - cell["slow"][1])) < 0.01, cell


# ── finally ─────────────────────────────────────────────────────────────────
def c7(tree, tmp):   # ⑦ work 안 git 예외 → 그대로 올라온다(삼킴 0) · ends._rows·k.git 원복
    class Boom(K):
        def git(s, repo, *args, **kw):
            s.calls.append((repo, args))
            raise RuntimeError("git boom")
    kf, w = load(tree, "kf_r2315_c7_" + str(id(tmp))), W(tmp)
    bad = w.tmp / "bad" / "a"
    bad.mkdir(parents=True)
    (bad / ".git").write_text("nope\n", encoding="utf-8")
    w.job("t", "a", bad)   # 못 읽는 worktree → git 길에서 터진다
    wrapped, k = kf.ends._rows, Boom(w.root)
    with pytest.raises(RuntimeError):
        kf.nanos(k, ["t"])
    assert kf.ends._rows is wrapped, kf.ends._rows
    assert getattr(k.git, "__func__", None) is Boom.git, k.git   # 되돌림 = 원래 손
    assert k.calls, k.calls


CASES = {"1": c1, "2": c2, "3": c3, "4": c4, "5": c5, "6": c6, "7": c7}
LINE = '            self.log("NANO-SLOW", text=self.nano_slow())'
COND = "        if nano_cut or self.nano_s >= NANO_S:"
GITN = "            git_n += 1"
ROWS = "            rows_s = time.monotonic() - at_rows"
BACK = "            k.git = real_git"
# 변이 = (파일, 옛 글, 새 글, 잡는 사례)
MUTANTS = {"M1": (KP, LINE, "            pass", "3"),                                  # 넘김 줄 지움
           "M2": (KP, COND, "        if True:", "2"),                                 # 넘김 조건 지움 = 늘 씀
           "M3": (KF, GITN, "            pass", "1"),                                 # git 셈 지움
           "M4": (KF, ROWS, "            rows_s = 0.0", "6"),                          # rows 셈 지움
           "M5": (KF, BACK, BACK + "\n            return got", "7")}                   # finally 에서 예외 삼킴


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    d = tmp_path / "c"
    d.mkdir()
    CASES[name](_tree(), d)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(_tree(), tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "x").mkdir()
    try:   # 변이 나무 = 사례가 판정을 바꾸면(어떤 실패든) 잡은 것
        CASES[case](tree, tmp_path / "x")
    except BaseException:   # noqa: BLE001
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, case))
    (tmp_path / "o").mkdir()
    assert CASES[case](_tree(), tmp_path / "o") is None   # 원본 나무 = 같은 사례 PASS(반대 결과 대조)
