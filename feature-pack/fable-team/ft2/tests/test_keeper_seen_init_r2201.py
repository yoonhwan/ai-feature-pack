"""r2201 ft2 keeper — 바퀴 밖에서 만든 Keeper 도 seen · tried · unused 를 갖는다(반례 ③ ④ · 변이 M1 · M2).

카드 r2201-ft2-keeper-seen-init-stall-tests · 계약 K1(초깃값) · K2(바퀴 불변 = _round 가 바퀴마다 비운다).
대역 = test_keeper_round_60s.Rig 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run · 가짜 tmux·mbox ·
sleep 0 · 네트워크 0 · 실 좌석 0. 새 대역 0. 기준판(PR #1513 뒤 · __init__ 초깃값 없음) = ③ Red(AttributeError).
"""
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig

PIN = ("zz", "manual")   # 바퀴가 돌지 않는 자리(팀 목록 밖) — 바퀴 사이에 손으로 넣는 자리


def c_init(w):   # ③ Keeper(...) 직후 at_pos 1번 · left_over 1번 → 예외 0 · seen 에 그 자리 1개
    k = w.k
    assert k.seen == set() and k.tried == set() and k.unused == set(), (k.seen, k.tried, k.unused)   # K1 바퀴 밖 = 빈 set
    k.at, k.at_work = "t1", "w1"
    assert k.at_pos("b1") is True
    k.left_over("t1", "w1")
    assert k.seen == {("t1", "w1", "b1")}, k.seen
    assert k.unused == {("t1", "w1", "b2c"), ("t1", "w1", "stall")}, k.unused   # 안 돈 자리만 뺀다


def c_round(w):   # ④ _round 2번 사이에 at_pos 1번 → 두 번째 _round 뒤 그 자리는 seen 에 없다(바퀴 경계 그대로)
    w.round()
    first = set(w.k.seen)
    w.k.at, w.k.at_work = PIN
    assert w.k.at_pos("b1") is True and PIN + ("b1",) in w.k.seen
    w.round()
    assert PIN + ("b1",) not in w.k.seen, w.k.seen   # 바퀴 시작에 seen 을 비웠다
    assert w.k.seen == first, (w.k.seen, first)   # 같은 세계 = 같은 돈 자리


CASES = {"③": c_init, "④": c_round}
MUTANTS = {   # 사본에서만 · 변이마다 원본 나무로 같은 사례 1회 더(반대 결과 대조)
    "M1": (KP, "        self.seen, self.tried, self.unused = set(), set(), set()", "        self.tried, self.unused = set(), set()", "③"),
    "M2": (KP, "        self.seen = set()   # R10 분모", "        pass   # R10 분모", "④"),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Rig(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w1").mkdir()
    with pytest.raises((AssertionError, AttributeError)):   # 변이 세계 = 그 사례가 선다
        CASES[case](Rig(tmp_path / "w1", tree))
    assert CASES[case](Rig(tmp_path / "c1")) is None   # 원본 나무 = 같은 사례 PASS
