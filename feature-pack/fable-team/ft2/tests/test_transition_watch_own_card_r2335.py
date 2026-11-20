"""r2335 works 거름 — 끝난 부모 work 에 «<부모>-impl» 후속 카드가 안 붙는다(카드 r2335-transition-watch-work-prefix-own-card · 사전 DA#41 APPROVE-DESIGN).
계약 W1 정확 우선(장부 전체 book[all] 로 정확 대조 → 칸 교집합만) · W2 접두 거름(주인 카드 s.stems 가 있는 접두는 안 냄) · W3 불변(주인 카드 없는 접두 · 정확 일치 · 위임 칸 그대로).
r2275 대역(world · card · at · once · sends · cells) 재사용 · 실 keeper·실 mbox 0 · sleep 0.
R2335_FT2=<ft2 폴더> 로 대상 바꿈(기준판 대조 = ① ② ⑤b Red) · 변이 = ft2 사본에서만 · 변이마다 원본으로 같은 사례 1회 더.
"""
import importlib.util
import os
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2275_cases_r2335", str(Path(__file__).with_name("test_transition_watch_r2275.py")))
T = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(T)
kw = T.kw
FT2 = Path(os.environ.get("R2335_FT2") or T.FT2)
NOW0, HOUR = T.NOW0, T.HOUR
PARENT = "cfo-b2c-reclaim-regrant-tests"
# 쪽지 머리 — «카드 전이 감시 · <칸> · harness 1장 — »
HEAD = "send M-harness ft2-keeper [크리티컬] 카드 전이 감시 · "
LEDGER = HEAD + "장부 완료 · 카드 열림 · harness 1장 — "


def led(w, work, mode="done"):   # 장부 1개 = done(끝남) · open(점유 중, holder 있음) · parked(세대에만 남음 = owner 해제)
    holder = w.work(work, done=mode == "done", intent=False, turn=None)
    if mode == "parked":
        out, rc = w.CLI.run(["park", "--work", work, "--attempt", "a1", "--reason", "idle-done", "--root", str(w.root), "--team", kw.TEAM])
        assert rc == 0, out
    return holder
def card_in(w, folder, stage, stem):   # 다른 팀 폴더 카드 = s.stems 전역 대조 확인(r2335 ②)
    body = "# 인덱스: %s\n- 상태: %s\n" % (stem, stage)
    return w.commit("byz", {"%s/indices/%s/%s.md" % (folder, stage, stem): body}, "ops/main-base")
def run(w, sec=2 * HOUR):   # 감시 1회 · 주입 시계 = 장부 done(FT_NOW) + sec
    w.t = NOW0 + sec
    return T.once(w)
def cell(w, k, stem):   # 그 카드가 멈춘 칸 이름(위임 칸 포함)
    return T.cells(w, k)[stem]


def c1(w):   # ① W2 — 부모 카드가 완성에 따로 있음 → 접두 work(부모) 안 붙음 · 0통 · 칸 = «대기 · 배정»
    led(w, PARENT)
    T.card(w, "완성", PARENT)
    T.card(w, "대기", PARENT + "-impl")
    k = run(w)
    assert T.sends(w) == [], T.sends(w)
    assert cell(w, k, PARENT + "-impl") == "대기 · 배정", cell(w, k, PARENT + "-impl")
def c2(w):   # ② W2 — 부모 카드가 다른 팀(planner) 폴더에 있어도 s.stems 전역 대조로 거름 · 0통
    led(w, PARENT)
    card_in(w, "design/teams/planner", "완성", PARENT)
    T.card(w, "대기", PARENT + "-impl")
    run(w)
    assert T.sends(w) == [], T.sends(w)
def c3(w):   # ③ W2 불변 — 주인 카드 없는 번호 work 접두(r9403)는 그대로 잡힌다 · 1통 «다시 접수 = r9403-r2»
    led(w, "r9403")
    T.card(w, "대기", "r9403-followup")
    run(w)
    assert T.sends(w) == [LEDGER + "r9403 · 다시 접수 = r9403-r2 · 다음 수 = 다시 접수"], T.sends(w)
def c4(w):   # ④ W1 — 정확 일치(장부 done) + 접두 work(주인 카드 없음) → 정확 이름만 · 1통
    led(w, "r9404-a-b"), led(w, "r9404-a")
    T.card(w, "대기", "r9404-a-b")
    run(w)
    assert T.sends(w) == [LEDGER + "r9404-a-b · 다시 접수 = r9404-a-b-r2 · 다음 수 = 다시 접수"], T.sends(w)
def c5(w):   # ⑤ W1 — 정확 일치 + 주인 카드 있는 접두 work 둘 다 done → 정확만(접두는 거름) · 1통
    led(w, "r9405-a-b"), led(w, "r9405-a")
    T.card(w, "완성", "r9405-a")
    T.card(w, "대기", "r9405-a-b")
    run(w)
    assert T.sends(w) == [LEDGER + "r9405-a-b · 다시 접수 = r9405-a-b-r2 · 다음 수 = 다시 접수"], T.sends(w)
def c5b(w):   # ⑤ⓑ W1 — 정확 work 가 세대에만(parked) 남음 · 접두 work(done · 주인 카드 없음)로 안 내려감 · 0통
    led(w, "r9415-a-b", "parked"), led(w, "r9415-a")
    T.card(w, "대기", "r9415-a-b")
    run(w)
    assert T.sends(w) == [], T.sends(w)
def c6(w):   # ⑥ W2 경계 — 부모 카드 있음 + 장부 done 1시간 안(30분) → 0통 · 칸 = «대기 · 배정»
    led(w, PARENT)
    T.card(w, "완성", PARENT)
    T.card(w, "대기", PARENT + "-impl")
    k = run(w, 30 * 60)
    assert T.sends(w) == [], T.sends(w)
    assert cell(w, k, PARENT + "-impl") == "대기 · 배정", cell(w, k, PARENT + "-impl")
def c7(w):   # ⑦ W3 불변 — 부모 카드는 있어도 장부에 그 접두 work 가 없으면 없던 일을 만들지 않는다 · 0통
    T.card(w, "완성", PARENT)
    T.card(w, "대기", PARENT + "-impl")
    k = run(w)
    assert T.sends(w) == [], T.sends(w)
    assert cell(w, k, PARENT + "-impl") == "대기 · 배정", cell(w, k, PARENT + "-impl")


CASES = {"c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c5b": c5b, "c6": c6, "c7": c7}
TW = ("adapters", "pi", "transition_watch.py")
MUTANTS = {   # 변이 이름 → (글자 바꿈, 사례) — 접두 거름 지움(M1) · 정확 우선 지움(M2) · 거름 방향 뒤집음(M3)
    "M1": ([(" and x not in s.stems", "")], c1),
    "M2": ([('if c["stem"] in book["all"]:', "if False:")], c5b),
    "M3": ([(" and x not in s.stems", " and x in s.stems")], c3),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](T.world(tmp_path / "w", monkeypatch, ft2=FT2))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case = MUTANTS[name]
    copy = tmp_path / "ft2"
    shutil.copytree(FT2, copy, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = copy.joinpath(*TW)
    text = path.read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    with pytest.raises(AssertionError):
        case(T.world(tmp_path / "m", monkeypatch, ft2=copy))
    case(T.world(tmp_path / "o", monkeypatch, ft2=FT2))
