"""r2210 ft2 keeper — 대기 사유 기억(wait_seen)을 풀림·사라짐에 지운다 · 판독 실패 바퀴는 그대로 (반례 ②~⑥ · 변이 M1).
대역 = r2205 world(r1871 임시 root·git·가짜 tmux) · 바퀴 = 실 run_once 에 team_round 만 choose 1회로 바꿈(닫기·채우기·launch 0).
바퀴마다 새 keeper = 기억은 state.json 으로 잇는다. 실 tmux·명부·카드·설치 0 · sleep 0. 기준판 = ② ④ Red.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_wait_r2210_base", str(HERE / "test_keeper_next_wait_reason_r2205.py"))
r5 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r5)
base, kw, S, SKIP, V65, KN = r5.base, r5.kw, r5.S, r5.SKIP, r5.V65, r5.KN
MINE = "design/harness/indices/대기/%s.md" % S
BODY = "# 인덱스: %s\n- 배정: 없음\n- 대기 사유: %s\n- 상태: 대기\n"


def turn(w):
    """한 바퀴 = 그 팀 choose 1회 → (그 바퀴 NEXT-SKIP 줄 수, 그 바퀴 줄들, 바퀴 뒤 wait_seen)."""
    k = w.keeper()
    kn = type(k).team_round.__globals__["closing"].keeper_next
    k.retired, k.report = (lambda: None), (lambda: None)
    k.team_round = lambda t: kn.choose(k, t) if t == "harness" else None
    assert k.run_once() == 0
    return k.lines.count(SKIP), list(k.lines), seen(k)


def seen(k):
    return json.loads((Path(k.dir) / "state.json").read_text(encoding="utf-8")).get("wait_seen") or {}


def put(w, path, value):   # value None = 카드 파일 지움
    seed = w.tmp / "seed-byz"
    if value is None:
        w.commit("byz", {}, "main")   # seed 를 main 으로 옮긴 뒤 지움
        (seed / path).unlink()
        return w.commit("byz", {}, "main")
    return w.commit("byz", {path: BODY % (S, value)}, "main")


def mine(tmp, mp, ft2):
    return base.world(tmp, mp, {S: "- 배정: 없음\n- 대기 사유: %s\n" % r5.REASON}, ft2=ft2)


def c2(tmp, mp, ft2):   # ② A 막힘 → 풀림(«없음») → A 막힘 → NEXT-SKIP 2줄(기준판 1줄 = Red)
    w = mine(tmp, mp, ft2)
    got = [turn(w)[0]]
    put(w, MINE, "없음")
    got.append(turn(w)[0])
    put(w, MINE, r5.REASON)
    got.append(turn(w)[0])
    assert got == [1, 0, 1], got


def c3(tmp, mp, ft2):   # ③ A 막힘 두 바퀴 → 1줄(O1 · 기억 그대로)
    w = mine(tmp, mp, ft2)
    got = [turn(w)[0], turn(w)[0]]
    assert got == [1, 0], got


def c4(tmp, mp, ft2):   # ④ A 막힘 → 대기에서 빠짐 → 같은 이름 A 로 돌아와 막힘 → 2줄
    w = mine(tmp, mp, ft2)
    got = [turn(w)[0]]
    put(w, MINE, None)
    n, _, book = turn(w)
    assert "harness|%s" % S not in book, book
    put(w, MINE, r5.REASON)
    got += [n, turn(w)[0]]
    assert got == [1, 0, 1], got


def c5(tmp, mp, ft2):   # ⑤ 팀 harness 카드가 풀려도 다른 팀(v65)의 같은 stem 키는 그대로(O4)
    w = mine(tmp, mp, ft2)
    k = w.keeper()
    turn(w)
    state = Path(k.dir) / "state.json"
    d = json.loads(state.read_text(encoding="utf-8"))
    d["wait_seen"]["v65|%s" % S] = "남의 값"
    kw._put(state, d)
    put(w, MINE, "없음")
    book = turn(w)[2]
    assert book.get("v65|%s" % S) == "남의 값" and "harness|%s" % S not in book, book


def c6(tmp, mp, ft2):   # ⑥ 짝 표 카드 A 막힘 → git rc≠0 바퀴(건너뜀) → A 막힘 → 키 그대로 · 1줄(지웠다면 2줄)
    w = base.world(tmp, mp, None, ft2=ft2, enable=False)
    w.commit("byz", {V65: BODY % (S, r5.REASON)}, "main")
    kw._put(w.state / "directive-roots.tsv", "harness\t.\torigin/main\tdesign/harness/indices\nv65\t.\torigin/main\tdesign/teams/v65/indices\n")
    kw._put(w.runtime() / "cards.tsv", "%s\t%s\n" % (S, V65))
    w.enable()
    got = [turn(w)[0]]
    put(w, V65, None)
    n, lines, book = turn(w)
    assert any(x.startswith("판정 불가 harness 짝 표 카드") for x in lines) and "harness|%s" % S in book, (lines, book)
    put(w, V65, r5.REASON)
    got += [n, turn(w)[0]]
    assert got == [1, 0, 0], got


CASES = {"②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6}
MUTANTS = {"M1": ('x.partition("|")[0] == team and ', "", ("⑤",))}


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
