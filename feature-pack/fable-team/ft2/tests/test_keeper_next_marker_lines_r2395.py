"""r2395 ft2 keeper — 대기/ 카드에 «- 대기 사유:» 줄도 «- 배정:» 줄도 없으면 «표식없음»(판정 불가 · 나노 열기 0) + 사유별 수에 싣는다 (반례 ①~⑥ · ⑩ · ⑪ · 변이 M1~M3 · M5 · M6).
대역 = r1871 world(r1812 keeper_world 임시 root·git·가짜 tmux·launch·record) — 실 리포·실 나노·tmux·mbox·설치·sleep 0.
기준판 = REF(착지 전 팩 main 고정 sha 872b495f) keeper_next.py(이 갈래 없음) → ① Red(표식 없는 카드를 그대로 고름) · origin/main 은 안 본다(착지 뒤엔 고친 판 · arch#516 #364686).
표식 있는 다른 길(⑩ «- 배정:» 만 · ⑪ «- 대기 사유:» 만)은 지금 그대로 = K6.
"""
import importlib.util, shutil, subprocess  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2395_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
S, KN = "r9301-plain", "adapters/pi/keeper_next.py"
REF = "872b495f952ca8142ebb0fa9c88d283d4fcf9dd1"   # r2395 기준판 = 이 카드 갈래 **이전** 팩 main 고정 sha(origin/main 은 착지 뒤 «고친 판» 이 되어 기준판이 못 된다 · 고정 sha 는 착지 뒤에도 조상으로 남는다 · arch#516 #364686)
BARE = "- 상태: 대기 · 사유 «사전 DA 전»\n"   # 실사건 꼴 = «대기 사유» 글자만 있고 «- 대기 사유:»·«- 배정:» 줄 0
CARD = "design/harness/indices/대기/%s.md"
SKIP = "NEXT-SKIP harness %s 건너뜀 — 표식 줄 없음 · «- 배정: 없음» 또는 «- 대기 사유: 없음» 한 줄 필요" % S
MARKERS = '("- 배정", WAIT)'


def world(tmp, mp, cards, ft2=kw.FT2, mark=False):
    """표식 줄을 깔지 않은 카드 그대로(mark=False 기본) — base.world 가 까는 해제 표식을 끈다."""
    return base.world(tmp, mp, cards, ft2=ft2, mark=mark)


def one(w, k=None):
    """한 바퀴 — 그 바퀴가 «새로 쓴» 줄만(같은 keeper 의 k.lines 는 누적이다)."""
    k = k or w.keeper()
    n = len(k.lines)
    w.t += 60
    w.round(k)
    return k.lines[n:]


def rounds(w, cards, n=1, k=None):
    """카드 1장을 더 커밋하고 n바퀴(같은 keeper 없으면 새 keeper) — 반환 = 그 바퀴들의 새 로그 줄."""
    w.commit("byz", {CARD % s: "# 인덱스: %s\n%s- 상태: 대기\n" % (s, h) for s, h in cards.items()}, "main")
    out = []
    for _ in range(n):
        out += one(w, k)
    return out


def blocked(w, why="표식없음"):
    """고르지 않음 + [다음 없음] 쪽지의 사유별 수 그대로."""
    note = base.notes(w)
    assert base.launched(w) == [] and base.count(w, "accept", S) == 0, (base.launched(w), note)
    assert len(note) == 1 and ("막힌 사유별 %s 1" % why) in note[0], note
    return note[0]


def c1(tmp, mp, ft2=kw.FT2):   # ① K1 표식 없는 카드 = 열리지 않는다(기준판 Red = 그대로 고름)
    w = world(tmp, mp, {S: BARE}, ft2=ft2)
    one(w)
    blocked(w)


def c2(tmp, mp, ft2=kw.FT2):   # ② K1 사유 이름 = «표식없음» · 쪽지에 카드 이름도 실린다
    w = world(tmp, mp, {S: BARE}, ft2=ft2)
    one(w)
    note = blocked(w)
    assert "막힌 카드 표식없음 %s" % S in note, note


def c3(tmp, mp, ft2=kw.FT2):   # ③ K2 로그 1줄 · 둘째 바퀴 0 · 새 keeper 0(값 그대로)
    w = world(tmp, mp, {S: BARE}, ft2=ft2)
    k = w.keeper()
    assert one(w, k).count(SKIP) == 1
    assert SKIP not in one(w, k) and SKIP not in one(w)   # 같은 keeper 둘째 바퀴 · 새 keeper 바퀴
    base.close(w, base.W2)
    assert SKIP not in one(w, k)


def c4(tmp, mp, ft2=kw.FT2):   # ④ K2 로그 글자 = 카드 이름 + 고칠 꼴(«- 배정: 없음»)
    w = world(tmp, mp, {S: BARE}, ft2=ft2)
    lines = [x for x in one(w) if "표식 줄 없음" in x]
    assert lines == [SKIP] and "«- 배정: 없음»" in lines[0], lines


def c5(tmp, mp, ft2=kw.FT2):   # ⑤ K3 다른 사유와 섞여도 수가 실린다(사람 1 · 표식없음 1)
    w = world(tmp, mp, {S: "- 배정: 없음\n"}, ft2=ft2)   # 표식 있는 카드 1(원장 «사람» 으로 막는다)
    kw._put(w.state / "card-assign" / (S + ".json"), {"state": "waiting", "reason": "사람", "since": 1.0})
    lines = rounds(w, {"r9302-plain": BARE})
    note = base.notes(w)
    assert base.launched(w) == [] and len(note) == 1, (base.launched(w), note, lines)
    assert "막힌 사유별 사람 1 표식없음 1" in note[0], note


def c6(tmp, mp, ft2=kw.FT2):   # ⑥ K3 목록 = 이름순 3장 + «외 1»
    w = world(tmp, mp, dict(("r930%d-plain" % n, BARE) for n in (1, 2, 3, 4)), ft2=ft2)
    one(w)
    note = base.notes(w)
    assert len(note) == 1 and "막힌 사유별 표식없음 4" in note[0], note
    assert "표식없음 r9301-plain · r9302-plain · r9303-plain 외 1" in note[0], note


def c10(tmp, mp, ft2=kw.FT2):   # ⑩ K6 «- 배정: 없음» 한 줄만 있는 옛 꼴 = 지금처럼 열린다
    w = world(tmp, mp, {S: "- 배정: 없음\n"}, ft2=ft2)
    lines = one(w)
    assert base.launched(w) == [S] and not any("표식 줄" in x for x in lines), (base.launched(w), lines)


def c11(tmp, mp, ft2=kw.FT2):   # ⑪ K6 «- 대기 사유:» 한 줄만 = 대기사유 로 막힘(표식없음 아님)
    w = world(tmp, mp, {S: "- 대기 사유: 사전 DA 전\n"}, ft2=ft2)
    lines = one(w)
    note = blocked(w, "대기사유")
    assert not any("표식 줄" in x for x in lines) and any("대기 사유 줄" in x for x in lines), lines
    assert "사전 DA 전" not in note, note


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑩": c10, "⑪": c11}
MUTANTS = {"M1": ('    if not any(x.startswith(("- 배정", WAIT)) for x in lines):', "    if False:", "①"),   # K1 갈래 지움
           "M2": ('            if book.get(key) != "표식없음":', "            if False:", "③"),                 # K2 로그 갈래 지움
           "M3": ('    if ready or why.get("팩낡음") or why.get("판정 불가"):', '    if ready or why.get("팩낡음") or why.get("판정 불가") or why.get("표식없음"):', "⑤"),   # K3 수 싣기 지움
           "M5": ('("- 배정", WAIT)', "(WAIT,)", "⑩"),      # «- 배정:» 만 있는 카드까지 표식없음
           "M6": ('("- 배정", WAIT)', '("- 배정",)', "⑪")}   # «- 대기 사유:» 만 있는 카드까지 표식없음


def baseline(tmp):
    """기준판 = REF(착지 전 고정 sha) 의 keeper_next.py — git 7초(하드 룰 12) · 못 읽으면 이 카드가 더한 줄만 지운 사본(같은 뜻).
    origin/main 을 안 본다: 착지 뒤 origin/main = 고친 판 이라 «기준판 Red» 가 사라진다(arch#516 #364686)."""
    tree = tmp / "base" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = tree / KN
    text = path.read_text(encoding="utf-8")
    try:
        got = subprocess.run(["git", "show", "%s:./%s" % (REF, KN)], cwd=str(kw.FT2), capture_output=True, text=True, timeout=7)
        old = got.stdout if got.returncode == 0 and "표식없음" not in got.stdout else ""
    except (OSError, subprocess.SubprocessError):
        old = ""
    if not old:   # 갈래 2줄(주석 포함)만 지우면 기준판과 같은 판
        cut = [x for x in text.splitlines(keepends=True) if "r2395 K1" not in x and "marker_seen" not in x and "표식 줄 없음 · «- 배정" not in x and 'book.get(key) != "표식없음"' not in x]
        old = "".join(cut)
    path.write_text(old, encoding="utf-8")
    assert "표식없음" not in path.read_text(encoding="utf-8")
    return tree


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch)


def test_baseline_red(tmp_path, monkeypatch):   # 기준판 Red = ①(표식 없는 카드를 그대로 고름)
    tree = baseline(tmp_path / "b")
    with pytest.raises(AssertionError):
        CASES["①"](tmp_path / "b", monkeypatch, tree)
    CASES["①"](tmp_path / "o", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KN).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        CASES[case](tmp_path / "w1", monkeypatch, tree)
    CASES[case](tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
