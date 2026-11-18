"""r2182 ft2 keeper [다음 없음] — 막힌 카드 이름(사유마다 3장) · «(원장)» 표시 · 풀기 명령 꼴 · 지문 열쇠 · 팀당 하루 3통 (반례 ②~⑩ · 변이 M1~M5).
대역 = r1871 world(임시 root·git·가짜 tmux·launch·record·mbox) · 날짜 = w.t 주입 · 실 리포·실 mbox·실 keeper 바퀴·설치 0 · sleep 0.
기준판 = ② ③ ⑥ Red(이름 0 · 같은 날 둘째 통 0). ⑩ = choose 결과·journal 줄이 기준판 값(시험에 박은 값)과 같음.
"""
import datetime, hashlib, importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2182_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
KN, A, B = "adapters/pi/keeper_next.py", "r9101-a", "r9102-b"
HUMAN = "- 배정: 대기(사람 · 2026-11-13T09:00)\n"
FIX = "원장이 카드 줄과 다르면: bash .fable-team/bin/ft-card-assign-watch.sh record <카드> clear <사유>"
FIVE = ["r920%d-h" % i for i in range(1, 6)]


def put_ledger(w, stem, reason):
    body = {"state": "waiting", "reason": reason, "since": 1.0} if reason else {"state": "none"}   # "" = clear 뒤 꼴
    kw._put(w.state / "card-assign" / (stem + ".json"), body)


def again(w, work, dt=60):   # 다른 일을 닫아 choose 를 한 바퀴 더(같은 날 · dt 초 뒤)
    base.close(w, work)
    w.t += dt
    w.round()


def c2(w):   # ② 원장(선행) A + 카드 줄(사람) B → 1통 · 기준 장수 글 그대로 · A(원장) · B 표시 없음 · 풀기 줄 1
    w.round()
    n = base.notes(w)
    assert len(n) == 1 and "막힌 사유별 사람 1 선행 1" in n[0], n
    assert A + "(원장)" in n[0] and B in n[0] and B + "(원장)" not in n[0] and n[0].count(FIX) == 1, n


def c3(w):   # ③ 한 사유 5장 → 이름순 앞 3장 + «외 2»
    w.round()
    n = base.notes(w)
    assert len(n) == 1 and "사람 %s · %s · %s 외 2" % tuple(FIVE[:3]) in n[0] and FIVE[3] not in n[0] and FIVE[4] not in n[0], n


def c4(w):   # ④ 카드 줄이 막은 카드뿐 → 이름 · «(원장)» 0 · 풀기 줄 0
    w.round()
    n = base.notes(w)
    assert len(n) == 1 and B in n[0] and "(원장)" not in n[0] and FIX not in n[0], n


def c5(w):   # ⑤ 같은 날 같은 입력 둘째 바퀴 → 0통 더
    w.round()
    again(w, base.W2)
    assert len(base.notes(w)) == 1, base.notes(w)


def c6(w):   # ⑥ 같은 날 원장 1장을 풀어 막힌 꼴이 바뀜 → 1통 더 · 새 글에 A(원장) 0 · 풀기 줄 0
    w.round()
    put_ledger(w, A, "")
    again(w, base.W2)
    n = base.notes(w)
    assert len(n) == 2 and A + "(원장)" not in n[1] and FIX not in n[1] and A in n[1], n


def c7(w):   # ⑦ 같은 날 막힌 꼴이 4번 바뀜 → 합 3통
    w.round()
    for i, reason in enumerate(("정지", "DA", "사람")):
        put_ledger(w, A, reason)
        again(w, "r987%d" % (i + 3))
    assert len(base.notes(w)) == 3, base.notes(w)


def c7g(w):   # ⓖ 옛 열쇠로 이미 나간 1통도 하루 3통에 든다 → 이 날 새로 2통만
    day = datetime.datetime.fromtimestamp(w.t).strftime("%Y-%m-%d")
    kw._put(w.state / "ft2-keeper" / "state.json", {"sent": {"%s|next-none|harness" % day: day + "T00:24:00"}})
    w.round()
    for i, reason in enumerate(("정지", "DA")):
        put_ledger(w, A, reason)
        again(w, "r987%d" % (i + 3))
    assert len(base.notes(w)) == 2, base.notes(w)


def c8(w):   # ⑧ ready 1장 → 쪽지 0
    w.round()
    assert base.notes(w) == [] and base.launched(w) == [B], (base.notes(w), base.launched(w))


def c9(w):   # ⑨ 다음 날 같은 입력 → 더 0통(r2266 C2 · 같은 지문은 날 무관 0통 · 다른 지문 다음 날 1통 = r2266 ⑤)
    w.round()
    again(w, base.W2, 86400)
    assert len(base.notes(w)) == 1, base.notes(w)


def c9h(w):   # ⓕ 글에 안 보이는 4번째 뒤 카드만 바뀌어도 지문이 바뀐다 → 1통 더
    w.round()
    put_ledger(w, FIVE[4], "사람")
    again(w, base.W2)
    assert len(base.notes(w)) == 2 and FIVE[4] not in base.notes(w)[1], base.notes(w)


def c9s(w):   # ⓗ 원장 seat 카드 = 원장 reason 이 있어도 «(원장)» 0
    kw._put(w.state / "card-assign" / (A + ".json"), {"state": "seat", "seat": "byz-harness-nano-old#0", "reason": "선행"})
    w.round()
    n = base.notes(w)
    assert len(n) == 1 and "배정됨 " + A in n[0] and "(원장)" not in n[0] and FIX not in n[0], n


def ledger_a(w):
    put_ledger(w, A, "선행")


CASES = {"②": (c2, {A: "", B: HUMAN}, ledger_a), "③": (c3, {s: HUMAN for s in FIVE}, None),
         "④": (c4, {B: HUMAN}, None), "⑤": (c5, {A: "", B: HUMAN}, ledger_a), "⑥": (c6, {A: HUMAN, B: HUMAN}, ledger_a),
         "⑦": (c7, {A: "", B: HUMAN}, ledger_a), "⑦ⓖ": (c7g, {A: "", B: HUMAN}, ledger_a),
         "⑧": (c8, {A: "", B: ""}, ledger_a), "⑨": (c9, {A: "", B: HUMAN}, ledger_a),
         "ⓕ": (c9h, {s: HUMAN for s in FIVE}, None), "ⓗ": (c9s, {A: "", B: HUMAN}, None)}
# ⑩ 기준판(838dd6c418) 에서 잰 값 — (launch 된 카드, journal (kind, work) 줄 목록 json 의 sha1 앞 12자)
BASE = {"②": ([], "fd1234b9922c"), "③": ([], "fd1234b9922c"), "④": ([], "fd1234b9922c"), "⑤": ([], "08320ca81136"),
        "⑥": ([], "08320ca81136"), "⑦": ([], "85ae292216a3"), "⑦ⓖ": ([], "55b6991aeaae"), "⑧": ([B], "303059f6cc00"),
        "⑨": ([], "08320ca81136"), "ⓕ": ([], "08320ca81136"), "ⓗ": ([], "fd1234b9922c")}


def run(name, tmp, mp, ft2=kw.FT2):
    case, cards, pre = CASES[name]
    w = base.world(tmp, mp, cards, ft2=ft2)
    if pre:
        pre(w)
    case(w)
    return w


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    w = run(name, tmp_path, monkeypatch)
    rows = [(r["kind"], r.get("work")) for r in w.journal()]   # ⑩ choose 결과 · journal 줄(기준판과 같음)
    assert (base.launched(w), hashlib.sha1(json.dumps(rows).encode()).hexdigest()[:12]) == BASE[name], (base.launched(w), rows)


MUTANTS = {"M1": ("NAMES, NONE_CAP = True,", "NAMES, NONE_CAP = False,", "②"),
           "M2": ('("(원장)" if own else "")', '""', "②"),
           "M3": ("cut[:3]", "cut", "③"),
           "M4": ('"%s|%s" % (key, fp)', "key", "⑥"),
           "M5": (">= NONE_CAP", ">= 99", "⑦")}


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
        run(case, tmp_path / "w1", monkeypatch, tree)
    run(case, tmp_path / "w2", monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
