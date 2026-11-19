"""r2262 C1~C3 ft2 keeper 다음 카드 — 착지 판독 사유가 «판정 불가» 로 시작 = 그 카드 이 바퀴 보류(block «판정 불가» · [다음 없음] 0) (반례 ①~⑧ · 변이 M1~M3).
대역 = r2252 세계(r2113 → r2111 → r1871 world · 임시 root·pack git · 가짜 tmux·launch·record). 팩 낡은 바퀴 = k.stale = {k.pack}(keeper.fresh 가 쓰는 값과 같은 경로 문자열).
choose 를 바로 부른다(바퀴 캐시 열고 닫음 · 같은 keeper = 같은 상태 기억) · ⑧ = 닫기 영수 길(keeper_next.close) · 네트워크 0 · sleep 0. 기준판 = ① ② Red(A·B 고름).
"""
import importlib.util, shutil, types  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2262_r2252", str(HERE / "test_keeper_next_reopen_seat_residue_r2252.py"))
r52 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r52)
base, kw, card = r52.base, r52.kw, r52.card
A, B, C, D, KN = "r9931-a", "r9932-b", "r9933-c", "r9934-d", "adapters/pi/keeper_next.py"
WHY = "판정 불가 · 팩 fetch 실패"
B_LINE, D_LINE = "- 대상(쓰기 = 나노 · 시험 6파일만 tests/x.py)", "- 대상: 팩 feature-pack/x.py"


def pick(w, k, stale=True, how=None):   # 한 바퀴 = 루트(·신선하면 팩) fetch → 바퀴 캐시 열기 → 고르기 1회 → 닫기 · 반환 = (고름, 이번 바퀴 줄)
    kw._git(w.root, "fetch", "-q", "origin")
    if not stale:
        kw._git(w.tmp / "pack", "fetch", "-q", "origin")
    k.stale, n, k.cache["@round"] = {k.pack} if stale else set(), len(k.lines), {}
    try:
        got = (how or (lambda: w.K.closing.keeper_next.choose(k, "harness")))()
    finally:
        k.cache.pop("@round", None)
    return (got or [None])[0], k.lines[n:]


def hold(lines, stem, why=WHY):
    return [x for x in lines if x == "NEXT-SKIP harness %s 착지 판정 불가(%s) — 이 바퀴 보류" % (stem, why[:40])]


def landed(lines, stem):
    return [x for x in lines if x == "NEXT-SKIP harness %s 이미 착지 — 카드 정리 필요" % stem]


def c1(w, mp):   # ① 팩 낡음 · A = 착지 줄(팩 main 조상) · 대상 줄 0 → 고름 0 · 판정 불가 NEXT-SKIP 1줄
    card(w, A, "- 착지: " + w.pack_sha())
    got, lines = pick(w, w.keeper())
    assert got is None and len(hold(lines, A)) == 1, (got, lines)


def c2(w, mp):   # ② 팩 낡음 · B = 착지 줄 · 대상 줄에 팩 낱말 0(r1864 꼴) → 고름 0
    card(w, B, "- 착지: " + w.pack_sha(), B_LINE)
    got, lines = pick(w, w.keeper())
    assert got is None and len(hold(lines, B)) == 1, (got, lines)


def c3(w, mp):   # ③ fetch 정상 · A → «이미 착지» 1줄 · 고름 0
    card(w, A, "- 착지: " + w.pack_sha())
    got, lines = pick(w, w.keeper(), stale=False)
    assert got is None and len(landed(lines, A)) == 1 and not hold(lines, A), (got, lines)


def c4(w, mp):   # ④ 팩 낡음 · C = 착지 줄 없음 · 대상 BYZ → C 고름
    card(w, C, "- 대상: BYZ .fable-team/y")
    got, lines = pick(w, w.keeper())
    assert got == C and not hold(lines, C), (got, lines)


def c5(w, mp):   # ⑤ 팩 낡음 · D = 대상 팩 · 착지 줄 없음 → 팩낡음 보류
    card(w, D, D_LINE)
    got, lines = pick(w, w.keeper())
    assert got is None and "판정 불가 harness 다음 카드 보류 1장 · 팩 fetch 실패" in lines and not hold(lines, D), (got, lines)


def c6(w, mp):   # ⑥ 고를 카드 = A·B 뿐 → [다음 없음] 쪽지 0
    sha = w.pack_sha()
    card(w, A, "- 착지: " + sha), card(w, B, "- 착지: " + sha, B_LINE)
    got, lines = pick(w, w.keeper())
    assert got is None and base.notes(w) == [] and len(hold(lines, A)) == len(hold(lines, B)) == 1, (got, lines, base.notes(w))


def c7(w, mp):   # ⑦ 같은 판정 불가 두 바퀴 → 1줄 · 앞 40자 같고 전문 다름 → 1줄 더 · fetch 정상 → «이미 착지» 1줄
    card(w, A, "- 착지: " + w.pack_sha())
    k = w.keeper()
    assert len(hold(pick(w, k)[1], A)) == 1
    assert pick(w, k)[1] == [], k.lines
    real, one, two = k.landing, "판정 불가 · " + "가" * 40 + " 1", "판정 불가 · " + "가" * 40 + " 2"
    for why in (one, two):   # 줄에 찍는 앞 40자는 같고 전문만 다름 → 바퀴마다 1줄
        k.landing = lambda team, stem, why=why: (None, None, why)
        lines = pick(w, k)[1]
        assert len(hold(lines, A, why)) == 1 and one[:40] == two[:40], lines
    k.landing = real
    got, lines = pick(w, k, stale=False)
    assert got is None and len(landed(lines, A)) == 1 and not hold(lines, A), lines


def c8(w, mp):   # ⑧ 닫기 영수 길(close → held_choose → choose) · ① 세계 → A 다음 일로 안 고름(영수 next 0)
    card(w, A, "- 착지: " + w.pack_sha())
    k, seen = w.keeper(), []
    k.receipt = lambda *a, **kw: seen.append(kw) or types.SimpleNamespace(result="접수 거부", next=None, reason="")   # 거부 = () 영수 1회 더
    nx = w.K.closing.keeper_next
    mp.setattr(nx, "gates", lambda k, team: True), mp.setattr(nx, "penalty_open", lambda k, team: True)
    got, lines = pick(w, k, how=lambda: nx.close(k, "harness", base.W1, "a1", "h", 1) and None)
    assert seen == [{}] and len(hold(lines, A)) == 1, (seen, lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
FIX = '        block = block or landed_hold(k, team, stem)   # r2262 C1'
MUTANTS = {"M1": (FIX, "", ("①", "②")),   # 판정 불가 보류 뺌
           "M2": ('return "판정 불가" if', 'return "착지 모름" if', ("⑥",)),   # block 낱말을 새 낱말로
           "M3": ('[2] or "").startswith("판정 불가") else ""', '[2] or "").startswith("") else ""', ("④",))}   # 사유가 있으면 모두 막음(착지 줄 없음 포함)


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
            run(case, bad, monkeypatch, tree)
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = 반대 결과 대조
