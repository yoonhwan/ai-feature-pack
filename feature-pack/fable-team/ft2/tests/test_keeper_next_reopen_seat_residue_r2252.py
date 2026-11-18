"""r2252 O1 ft2 keeper 다음 카드 — 쉼 뒤 남은 1.x 원장 seat ∧ stem·짝 work ft2 owner 0 ∧ 재개 줄 참(reopen) = «배정됨» 으로 막지 않음 (반례 ①~④ · 변이 M1 M2).
대역 = r2113 세계(r2111 → r1871 world · 임시 root·git·가짜 tmux·launch·record · launch/<work>@<att>.intent · card-assign 원장 json).
choose 를 바로 부른다(고름 = 반환 stem) · 실 tmux·명부·ft2 원장·우편함·설치 0 · sleep 0. 기준판 = ① Red(NEXT-SKIP «배정됨» · 고름 0).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2252_r2113", str(HERE / "test_keeper_next_reopen_name_tail_r2113.py"))
r13 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r13)
base, kw, hand, card = r13.base, r13.kw, r13.hand, r13.card
S, KN, DAY = "r9925-seat", "adapters/pi/keeper_next.py", "2026-11-16T"
NH = "byz-harness-nano-%s#0" % S


def seat(w):   # 쉼 뒤 꼴 — 옛 holder 원장 seat 남음(쉼은 ft2 owner 만 푼다)
    kw._put(w.state / "card-assign" / (S + ".json"), {"state": "seat", "seat": NH, "since": 1.0, "updated": 1.0})


def owned(w, at):   # owner 있음 = submit → assign → deliver 까지(claim·result 0) + intent
    run = lambda *a: w.CLI.run(list(a) + ["--root", str(w.root), "--team", "harness"])   # noqa: E731
    for argv in (("submit", "--command", "c-" + S, "--body", "b-" + S, "--work", S),
                 ("assign", "--work", S, "--holder", NH, "--evidence", "v1,v2"), ("deliver", "--work", S)):
        out, rc = run(*argv)
        assert rc == 0, out
    kw._put(w.runtime() / "launch" / ("%s@%s.intent" % (S, out["attempt"])), {"FT2_HOLDER": NH, "state": "opened", "at": at})


def pick(w):   # 바퀴의 fetch 자리 = 루트 리포 fetch 1회(카드 읽기 = origin/main) → choose 1회
    kw._git(w.root, "fetch", "-q", "origin")
    k = w.keeper()
    got = w.K.closing.keeper_next.choose(k, "harness")
    return (got or [None])[0], k.lines


def c1(w, mp):   # ① 원장 seat(옛 holder) ∧ owner 0 ∧ 재개 16:28(최신 intent 10:50 뒤) → 고름 1
    hand(w, S, DAY + "10:50:00", holder=NH), seat(w)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    got, lines = pick(w)
    assert got == S and not [x for x in lines if "배정됨" in x], (got, lines)


def c2(w, mp):   # ② 원장 seat ∧ owner 0 ∧ 재개 줄 없음 → «배정됨» 그대로 · 고름 0(쉼 자동 재배정 0)
    seat(w)   # ft2 전달 0 = «전달됨» 막음 0 → 원장 seat 만이 막는다(M2 가 보이는 자리)
    card(w, S)
    got, lines = pick(w)
    assert got is None, (got, lines)


def c3(w, mp):   # ③ 원장 seat ∧ owner 있음 ∧ 재개 줄 → «배정됨» 그대로
    owned(w, DAY + "10:50:00"), seat(w)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    got, lines = pick(w)
    assert got is None, (got, lines)


def c4(w, mp):   # ④ 원장 seat ∧ owner 0 ∧ 재개 10:00 이 최신 intent 10:50 앞 → «배정됨» 그대로
    hand(w, S, DAY + "10:50:00", holder=NH), seat(w)
    card(w, S, "- 재개: " + DAY + "10:00:00")
    got, lines = pick(w)
    assert got is None, (got, lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4}
MUTANTS = {"M1": (' and stem not in owners and reopen(k, team, stem, back,', " and reopen(k, team, stem, back,", ("③",)),   # O1 owner 조건 뺌
           "M2": (' and stem not in owners and reopen(k, team, stem, back, {stem} | pair.get(stem, set()), state):', " and stem not in owners:", ("②",))}   # O1 reopen 조건 뺌


def run(name, tmp, mp, ft2=kw.FT2):
    w = base.world(tmp, mp, {}, ft2=ft2)
    CASES[name](w, mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises(AssertionError):
            run(case, bad, monkeypatch, ft2=tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = 반대 결과 대조
