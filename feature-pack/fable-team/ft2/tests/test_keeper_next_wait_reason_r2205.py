"""r2205 ft2 keeper — 대기 카드 «- 대기 사유:» 줄(값이 풀기 값이 아님) = 고르지 않음 + NEXT-SKIP 1줄 (반례 ②~⑧ · 변이 M1·M2).
대역 = r1871 world(r1812 keeper_world 임시 root·git·가짜 tmux·launch·record) + 짝 표 cards.tsv(⑤).
실 tmux·명부·카드·설치 0 · sleep 0. 기준판 = ② Red(대기 사유 카드를 고름) · ⑤ ⑥ 도 Red.
"""
import importlib.util, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2205_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
S, W3 = "m7-solo-mount-init", "r9873"
KN = "adapters/pi/keeper_next.py"
WAIT = "- 배정: 없음\n- 대기 사유: %s\n"
REASON = "선행 = 재현 1회"
SKIP = "NEXT-SKIP harness %s 건너뜀 — 대기 사유 줄 · 풀기 = «- 대기 사유: 없음»" % S
V65 = "design/teams/v65/indices/대기/%s.md" % S


def world(tmp, mp, ft2, head):
    return base.world(tmp, mp, {S: head}, ft2=ft2)


def blocked(w, k=None):
    lines = w.round(k)
    assert base.launched(w) == [] and base.count(w, "accept", S) == 0, (base.launched(w), lines)
    return lines


def picked(w):
    lines = w.round()
    assert base.launched(w) == [S] and SKIP not in lines, (base.launched(w), lines)


def c2(tmp, mp, ft2):   # ② 배정 없음 · 대기 사유 값 · 선행 줄 없음 → 후보 0 · NEXT-SKIP 1줄 · [다음 없음] 대기사유 1
    w = world(tmp, mp, ft2, WAIT % REASON)
    assert blocked(w).count(SKIP) == 1
    assert len(base.notes(w)) == 1 and "막힌 사유별 대기사유 1" in base.notes(w)[0], base.notes(w)


def c3a(tmp, mp, ft2):   # ③ 값 «없음» → 후보
    picked(world(tmp, mp, ft2, WAIT % "없음"))


def c3b(tmp, mp, ft2):   # ③ 값 «충족 …» → 후보
    picked(world(tmp, mp, ft2, WAIT % "충족 (재현 1회 끝)"))


def c4(tmp, mp, ft2):   # ④ 값 빈 글 → 후보
    picked(world(tmp, mp, ft2, "- 배정: 없음\n- 대기 사유:\n"))


def c5(tmp, mp, ft2):   # ⑤ 짝 표(cards.tsv) 대기 카드(팀 폴더 밖 v65)에 ② 줄 → 후보 0
    w = base.world(tmp, mp, None, ft2=ft2, enable=False)
    w.commit("byz", {V65: "# 인덱스: %s\n%s- 상태: 대기\n" % (S, WAIT % REASON)}, "main")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\nv65\t.\torigin/main\tdesign/teams/v65/indices\n")
    kw._put(w.runtime() / "cards.tsv", "%s\t%s\n" % (S, V65))
    w.enable()
    assert blocked(w).count(SKIP) == 1


def c6(tmp, mp, ft2):   # ⑥ ② 를 두 바퀴(같은 keeper · 새 keeper) → 1줄만 · 값을 바꾸면 1줄 더
    w = world(tmp, mp, ft2, WAIT % REASON)
    k = w.keeper()
    blocked(w, k)
    base.close(w, base.W2)
    assert blocked(w, k).count(SKIP) == 1
    base.close(w, W3)
    assert SKIP not in blocked(w)
    w.commit("byz", {"design/harness/indices/대기/%s.md" % S: "# 인덱스: %s\n%s- 상태: 대기\n" % (S, WAIT % "사전 DA 뒤")}, "main")
    base.close(w, "r9874")
    assert blocked(w).count(SKIP) == 1


def c7(tmp, mp, ft2):   # ⑦ «- 배정: 대기(사람 · …)» 도 있음 → 막는 사유 = 사람(순서 그대로) · 대기 사유 줄 0
    w = world(tmp, mp, ft2, "- 배정: 대기(사람 · 11-18)\n- 대기 사유: %s\n" % REASON)
    assert SKIP not in blocked(w)
    assert len(base.notes(w)) == 1 and "막힌 사유별 사람 1" in base.notes(w)[0], base.notes(w)


def c8(tmp, mp, ft2):   # ⑧ ft2 owner 있음 → «배정됨»(기준판과 같음) · 대기 사유 줄 0
    w = world(tmp, mp, ft2, WAIT % REASON)
    w.work(S, done=False, intent=False, turn=None)   # owner = 손 submit 1회(accept 셈 0 으로 보지 않는다)
    lines = w.round()
    assert base.launched(w) == [] and SKIP not in lines, (base.launched(w), lines)
    assert any("막힌 사유별 배정됨 1" in x for x in base.notes(w)), base.notes(w)


CASES = {"②": c2, "③a": c3a, "③b": c3b, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
MUTANTS = {"M1": ("|배정|대기 사유:|재개:|상태", "|배정|재개:|상태", ("②",)),
           "M2": (r'r"- (긴급|우선|대상|선행|배정|재개:|대기 사유:)"', r'r"- (긴급|우선|대상|선행|배정|재개:)"', ("⑤",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch, kw.FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for case in cases:
        (tmp_path / case / "m").mkdir(parents=True), (tmp_path / case / "o").mkdir()
        with pytest.raises(AssertionError):
            CASES[case](tmp_path / case / "m", monkeypatch, tree)
        CASES[case](tmp_path / case / "o", monkeypatch, kw.FT2)   # 원본으로 같은 사례 1회 더 = PASS
