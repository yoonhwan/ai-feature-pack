"""r2203 ft2 keeper 대신 받는 곳 묶음 — 같은 열쇠는 그날 1건(stand|<날짜> 지문) · 날짜가 바뀌면 1회 더 · none_tell 하루 상한 (반례 ②~⑤ · 변이 M1·M2).
대역 = r2065 test_keeper_notify_recipient world(임시 root·가짜 tmux·가짜 mbox) + 주입 시계(w.t) · 실 우편함·실 keeper 바퀴·설치 0 · sleep 0.
기준판 = ② ⑤ Red(같은 열쇠 3번 → 3건 · [다음 없음] 4번 → 4건). ① = 기존 시험 3개 재실행(이 파일 밖).
"""
import importlib.util
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_notify_r2203", str(Path(__file__).with_name("test_keeper_notify_recipient.py")))
nr = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nr)
FT2, DAY = nr.FT2, 86400


def book(k, team="chatbot"):
    return (k.state.get("undelivered") or {}).get(team, [])


def keep(w):
    """팀장 없는 chatbot · harness 팀장 있음 · flush 는 부르지 않는다(묶음 장부 그대로 본다) · 바퀴 사이 state 는 locked 가 저장."""
    nr.roster(w, "chatbot", _master="", _desk=""), nr.spec(w)
    k = w.keeper()
    k.skip, k.halt = set(), False
    return k


def turn(w, k, *steps):
    k.locked(lambda: [step(k) for step in steps])
    return k


def c2(w):   # ② 같은 열쇠로 notify 3바퀴 → 1건
    k = keep(w)
    for _ in range(3):
        k = turn(w, w.keeper(), lambda k: k.notify("chatbot", "c2|같은", nr.BODY[0]))
        w.t += 60
    assert len(book(k)) == 1, book(k)


def c3(w):   # ③ 같은 팀 · 다른 열쇠 2개 → 2건
    k = keep(w)
    k = turn(w, k, lambda k: k.notify("chatbot", "c3|a", nr.BODY[0]), lambda k: k.notify("chatbot", "c3|b", nr.BODY[1]))
    assert len(book(k)) == 2, book(k)


def c4(w):   # ④ 같은 열쇠 · 날짜를 바꾼 뒤 1번 더 → 1건 더
    k = keep(w)
    k = turn(w, k, lambda k: k.notify("chatbot", "c4|같은", nr.BODY[0]), lambda k: k.notify("chatbot", "c4|같은", nr.BODY[0]))
    assert len(book(k)) == 1, book(k)
    w.t += DAY
    k = turn(w, w.keeper(), lambda k: k.notify("chatbot", "c4|같은", nr.BODY[0]))
    assert len(book(k)) == 2, book(k)


def c5(w):   # ⑤ none_tell 같은 날 지문이 다른 [다음 없음] 4번 → 쌓인 건 NONE_CAP(3) 이하
    k = keep(w)
    kn = w.K.closing.keeper_next
    for i in range(4):
        names = {"DA": [("r9%03d-x" % i, False)]}
        k = turn(w, w.keeper(), lambda k, names=names: kn.none_tell(k, "chatbot", "%s chatbot · 막힌 %d" % (kn.NONE, len(names)), names))
        w.t += 60
    assert 1 <= len(book(k)) <= kn.NONE_CAP, book(k)


CASES = {"②": c2, "③": c3, "④": c4, "⑤": c5}
KS = "adapters/pi/keeper_report.py"
MUTANTS = {
    "M1": (KS, '        self.state["sent"][key] = "stand|%s" % self.stamp()[:10]\n', "", ("②", "⑤")),
    "M2": (KS, 'str(got).startswith(("fail|", "stand|"))', 'str(got).startswith("fail|")', ("④",)),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](nr.world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        sub = tmp_path / ("w%d" % i)
        sub.mkdir()
        with pytest.raises(AssertionError):   # 변이 = 그 사례가 무너진다
            CASES[case](nr.world(sub, monkeypatch, tree))
        orig = tmp_path / ("o%d" % i)   # 원본 대조 = 같은 사례가 원본에서는 선다
        orig.mkdir()
        CASES[case](nr.world(orig, monkeypatch))
