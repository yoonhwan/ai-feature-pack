"""r2293 착지 대기 시계 — 반례 ① · ①ⓑ · ①ⓒ · ①d · ⑥ + 변이 M1 · M3 · M5(카드 r2293-landing-wait-alarm-auto-land · 사전 DA#32 APPROVE-DESIGN).
r2275 대역(world · card · at · once · sends · claim) 재사용 · 시계 = World.t(카드 시각 = 실제 커밋 시각) · 실 리포·실 mbox 0 · sleep 0.
R2293_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조) · 변이 = ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2275_cases_r2293", str(Path(__file__).with_name("test_transition_watch_r2275.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
FT2 = Path(os.environ.get("R2293_FT2") or T.FT2)
SET = "- 세트: %s · 시험: bash tests/x.sh rc=0 · 이슈: 0\n" % ("a" * 40)
HEAD = "send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · 착지 대기 · harness 1장 — "
ROW = ', ("착지 대기", "land", "FT2_TW_LAND_WAIT_S", 600, "")'


def got(w):   # 전이 감시 쪽지 = «다음 수» 앞까지
    return [x.split(" · 다음 수 = ")[0] for x in T.sends(w)]
def c1(w):   # ① 세트 증거 줄 · 마지막 커밋 11분 전 · 착지 줄 0 → 1통 · 두 번째 바퀴 0(지문 중복 막기)
    T.card(w, "진행", "r9200-land", SET)
    T.at(w, 11 * 60)
    T.once(w, T.once(w))
    assert got(w) == [HEAD + "r9200-land 세트 뒤 11분 · 착지 줄 0"], T.sends(w)
def c1b(w):   # ①ⓑ 같은 카드 9분 전 → 0통
    T.card(w, "진행", "r9201-early", SET)
    T.at(w, 9 * 60)
    T.once(w)
    assert T.sends(w) == [], T.sends(w)
def c1c(w):   # ①ⓒ 착지 줄 있음 · 11분 → 0통
    T.card(w, "진행", "r9202-landed", SET + T.land(T.pack(w, False)))
    T.at(w, 11 * 60)
    T.once(w)
    assert T.sends(w) == [], T.sends(w)
def c1d(w):   # ①d 장부에 나노 holder 의 열린 work + 세트 증거 줄 + 11분 + 착지 줄 0 → 1통(칸이 ROWS 끝이면 e_seat 가 먼저 = 0통)
    T.card(w, "진행", "r9203-nano", SET)
    T.claim(w, "r9203-nano", "byz-harness-nano-r9203-nano#0")
    T.at(w, 11 * 60)
    T.once(w)
    assert got(w) == [HEAD + "r9203-nano 세트 뒤 11분 · 착지 줄 0"], T.sends(w)
def c6(w):   # ⑥ 나노 발주 틀(goal-close first_body_tail)에 재촉 1줄 실재
    rows = [x.split("\t") for x in (FT2.parent / "goal-close" / "phrases.tsv").read_text(encoding="utf-8").splitlines()]
    tail = next(x[1] for x in rows if x[0] == "first_body_tail")
    assert "착지 대기 5분" in tail and "막힌 단계 · 필요한 손" in tail and "같은 단계 재촉 1회" in tail, tail


CASES = {"c1": c1, "c1b": c1b, "c1c": c1c, "c1d": c1d, "c6": c6}
MUTANTS = {   # 변이 이름 → (글자 바꿈, 사례)
    "M1": ([(' if s.now - at >= s.lim["land"] else None', "")], c1b),   # 10분 검사 삭제
    "M3": ([('"전이|%s|%s|%s|%s" % (row[0], team, day,', '"전이|%s|%s|%s|%s" % (row[0], team, time.time(),')], c1),   # 중복 막기(지문) 무력화
    "M5": ([(ROW, ""), ('("진행 24시간", "prog", "FT2_TW_PROGRESS_S", DAY, ""))', '("진행 24시간", "prog", "FT2_TW_PROGRESS_S", DAY, "")' + ROW + ")")], c1d),   # 칸을 ROWS 끝으로
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](T.world(tmp_path / "w", monkeypatch, ft2=FT2))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy / "adapters" / "pi" / "transition_watch.py"
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(T.world(tmp_path / "m", monkeypatch, ft2=copy))
    case(T.world(tmp_path / "o", monkeypatch, ft2=FT2))
