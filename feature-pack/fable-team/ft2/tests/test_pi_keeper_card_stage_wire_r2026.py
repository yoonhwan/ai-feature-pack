"""r2026 ft2 keeper — complete 접수(done 확인) 직후 card_stage 1회 · Unsure = 다음 바퀴 재시도(같은 work · 하루 3회 상한) · NOOP·STAGED = 끝.
대역 = r1812 World(임시 리포·가짜 tmux·주입 시계 w.t) + 가짜 card_stage(k.cs · 호출 기록) · 실 BYZ 리포·실 push 0 · sleep 0.
T1~T4 · 변이 M1(호출 줄 삭제 → T1 FAIL) · M2(재시도 상한 삭제 → T3 FAIL)."""
import importlib.util
import shutil
from pathlib import Path

import pytest

_S = importlib.util.spec_from_file_location("r2026_kw", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_S)
_S.loader.exec_module(kw)
World, FT2, AT = kw.World, kw.FT2, "2026-11-13T09:00:00"


class Fake:
    """card_stage 대역 — plan 차례로 돌려줌(예외 객체 = raise · None = NOOP · 끝나면 마지막 값 반복)."""
    class Unsure(Exception):
        pass

    def __init__(self, plan):
        self.plan, self.calls = list(plan), []

    def done_at(self, root, team, work):
        return AT

    def stage(self, byz, root, team, work, at, now):
        self.calls.append((team, work, at))
        got = self.plan.pop(0) if len(self.plan) > 1 else self.plan[0]
        if isinstance(got, Exception):
            raise got
        return got


def keeper(w, fake):
    k = w.keeper()
    k.cs = fake
    return k


def start(w, work):
    w.card(work, w.pack_sha()), w.work(work, intent=False)


def t1(w, mp):   # T1 complete 접수 성공 → card_stage 1회(work·at) · CARD-STAGE 1줄
    start(w, "r9261")
    fake = Fake([("r9261-x", "진행→완성", "c0ffee")])
    lines = w.round(keeper(w, fake))
    assert w.kinds("complete") == 1 and fake.calls == [("harness", "r9261", AT)], (fake.calls, lines)
    assert [x for x in lines if x.startswith("CARD-STAGE")] == ["CARD-STAGE harness r9261 진행→완성 c0ffee"], lines
    w.round(keeper(w, fake))
    assert len(fake.calls) == 1   # 성공 = 끝(재시도 0)


def t2(w, mp):   # T2 complete 접수 실패 → card_stage 0
    start(w, "r9262")
    fake = Fake([None])
    k = keeper(w, fake)
    cli = type(k).run_once.__globals__["land"].cli
    mp.setattr(cli, "run", lambda argv: ({"result": "거절"}, 1) if argv[:1] == ["complete"] else (_ for _ in ()).throw(AssertionError(argv)))
    w.round(k)
    assert w.kinds("complete") == 0 and fake.calls == [], fake.calls


def t3(w, mp):   # T3 Unsure → 1줄 · 다음 바퀴 재호출 1회 · 같은 날 3회 뒤 0 · 다음 날 다시 1회
    start(w, "r9263")
    fake = Fake([Fake.Unsure("push 결과 불명")])
    lines = w.round(keeper(w, fake))
    assert len(fake.calls) == 1 and [x for x in lines if x.startswith("Unsure")] == ["Unsure harness r9263 card_stage push 결과 불명"], lines
    w.round(keeper(w, fake))
    assert len(fake.calls) == 2   # 다음 바퀴 1회
    w.round(keeper(w, fake)), w.round(keeper(w, fake))
    assert len(fake.calls) == 3   # 같은 날 3회 뒤 0
    w.t += 86400
    w.round(keeper(w, fake))
    assert len(fake.calls) == 4


def t4(w, mp):   # T4 NOOP(이미 완성) → 재시도 0
    start(w, "r9264")
    fake = Fake([None])
    lines = w.round(keeper(w, fake))
    assert [x for x in lines if x.startswith("NOOP")] == ["NOOP harness r9264 이미 완성"], lines
    w.round(keeper(w, fake))
    assert len(fake.calls) == 1


CASES = {"T1": t1, "T2": t2, "T3": t3, "T4": t4}
KP = "adapters/pi/keeper.py"
MUTANTS = {"M1": ("land.Landing.complete(self, *args) and (self.stage_card(*args[:2]) or True)", "land.Landing.complete(self, *args)", t1),
           "M2": ("        if n >= 3:\n            return None\n", "", t3)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](World(tmp_path, monkeypatch), monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w").mkdir()
    with pytest.raises(AssertionError):
        case(World(tmp_path / "w", monkeypatch, tree), monkeypatch)
