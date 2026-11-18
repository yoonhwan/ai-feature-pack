"""r2254 O1·O3 ft2 keeper 다음 카드 — 끝난(done) work 카드에 «- 재개:» 줄 = NEXT-SKIP «끝남 … 재개 줄 무시» 1줄(값이 바뀔 때만) · 판정 그대로 (반례 ①~⑤ · 변이 M1 M2).
대역 = r2252 세계(r2113 → r2111 → r1871 world · 임시 root·git·가짜 tmux·launch·record · 짝 표 cards.tsv · card-assign 원장 json).
choose 를 바로 부른다(같은 keeper = 같은 상태 기억 · 바퀴 밖 = 캐시 0) · 실 tmux·명부·ft2 원장·우편함·설치 0 · sleep 0. 기준판 = ① Red(줄 0).
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2254_r2252", str(HERE / "test_keeper_next_reopen_seat_residue_r2252.py"))
r52 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r52)
base, kw, hand, card, seat, NH = r52.base, r52.kw, r52.hand, r52.card, r52.seat, r52.NH
S, PW, KN, DAY = r52.S, "r9926-pair", "adapters/pi/keeper_next.py", r52.DAY
KEY = "harness|" + S


def line(work):
    return "NEXT-SKIP harness %s 건너뜀 — 끝남(ft2 done %s@a1) · 재개 줄 무시 · 끝난 work 는 같은 이름으로 다시 안 열림 · 새 work 이름으로 손 발주" % (S, work)


def ends(lines):
    return [x for x in lines if x.startswith("NEXT-SKIP harness %s " % S) and "끝남" in x]


def pick(w, k):   # 한 바퀴 = 루트 리포 fetch 1회 → 같은 keeper 로 choose 1회 · 반환 = (고름, 이번 바퀴 줄)
    kw._git(w.root, "fetch", "-q", "origin")
    n = len(k.lines)
    got = w.K.closing.keeper_next.choose(k, "harness")
    return (got or [None])[0], k.lines[n:]


def c1(w, mp):   # ① done ∧ 재개 줄 → 끝남 줄 1 · 고름 0
    w.work(S, done=True)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    got, lines = pick(w, w.keeper())
    assert got is None and ends(lines) == [line(S)], (got, lines)


def c2(w, mp):   # ② ① 둘째 바퀴(값 같음) → 줄 0 · 셋째 바퀴 재개 값 바뀜 → 줄 1 · 넷째 재개 줄 지움 → 키 지움(O3)
    w.work(S, done=True)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    k = w.keeper()
    assert ends(pick(w, k)[1]) == [line(S)]
    got, lines = pick(w, k)
    assert got is None and ends(lines) == [], lines
    card(w, S, "- 재개: " + DAY + "17:00:00")
    assert ends(pick(w, k)[1]) == [line(S)]
    card(w, S)
    got, lines = pick(w, k)
    assert got is None and ends(lines) == [] and KEY not in k.state.get("done_skip_seen", {}), (lines, k.state.get("done_skip_seen"))


def c3(w, mp):   # ③ done ∧ 재개 줄 없음 → 줄 0 · 고름 0(대기/ 에 남은 끝난 카드 소음 0)
    w.work(S, done=True)
    card(w, S)
    got, lines = pick(w, w.keeper())
    assert got is None and ends(lines) == [], (got, lines)


def c4(w, mp):   # ④ done 아님 ∧ 재개 줄(쉼 · owner 0 · 원장 seat) → r2252 O1 길 · 고름 1 · 끝남 줄 0 · 키 0
    hand(w, S, DAY + "10:50:00", holder=NH), seat(w)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    k = w.keeper()
    got, lines = pick(w, k)
    assert got == S and ends(lines) == [] and KEY not in k.state.get("done_skip_seen", {}), (got, lines)


def c5(w, mp):   # ⑤ 짝 work 만 done ∧ 재개 줄 → ① 과 같은 줄(work 이름 = 짝 work)
    kw._put(w.runtime() / "cards.tsv", "%s\tdesign/harness/indices/대기/%s.md\n" % (PW, S))
    w.work(PW, done=True)
    card(w, S, "- 재개: " + DAY + "16:28:00")
    got, lines = pick(w, w.keeper())
    assert got is None and ends(lines) == [line(PW)], (got, lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5}
MUTANTS = {"M1": ('if block == "끝남" and back:', 'if block == "끝남":', ("③",)),   # O1 재개 줄 조건 뺌
           "M2": ("if done_book.get(key) != val:", "if True:", ("②",))}   # O1 값 기억 뺌


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
