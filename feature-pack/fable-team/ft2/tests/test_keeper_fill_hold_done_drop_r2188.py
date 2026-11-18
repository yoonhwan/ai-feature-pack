"""r2188 ft2 keeper 채우기 보류 — 끝난 일의 보류를 지우고 닫기 영수도 같은 보류 목록을 건너뛴다 (반례 ②~⑩ · 변이 M1~M3).
대역 = r1913 world(= r1871 world 꼴 · 임시 root·git·가짜 tmux·launch·record·mbox) · 날짜 = w.t 주입 · 실 리포·실 mbox·실 keeper 바퀴·설치 0 · sleep 0.
채우기 바퀴 = 닫힘 0 · 상한 4 · live 2 / 닫기 바퀴 = W1 닫힘 · 상한 1 · live 0(r1871 «닫기 1장으로 꽉 참 = fill 0»).
기준판 = ② ③ ④ ⑤ ⑥ ⑦ Red(끝난 보류 남음 · 사유 «보류» · 2통 · 닫기 길이 보류 카드를 고름). ① = 기존 시험 다섯 개 그대로 재실행.
"""
import importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_fill_r2188_base", str(HERE / "test_keeper_fill_empty_slot_r1913.py"))
fl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fl)
nx, kw, A, B, C = fl.nx, fl.kw, fl.A, fl.B, fl.C
KN, PW = "adapters/pi/keeper_next.py", "r9881"   # PW = A 의 짝 work(cards.tsv)
KEY = "harness|" + A


def st(w):
    p = w.state / "ft2-keeper" / "state.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def hold(w, val=None):   # A 를 채우기 보류에 둔다(keeper 상태 파일 · 값 = 숫자 꼴 또는 «시각|사유» 꼴)
    s = st(w)
    s.setdefault("fill_hold", {})[KEY] = w.t - 100 if val is None else val
    kw._put(w.state / "ft2-keeper" / "state.json", s)


def human(w, *stems):   # 원장 «사람» 막힘
    for s in stems:
        kw._put(w.state / "card-assign" / (s + ".json"), {"state": "waiting", "reason": "사람", "since": 1.0})


def pair(w, work, stem):   # r1887 짝 표 1줄
    kw._put(w.runtime() / "cards.tsv", "%s\tdesign/teams/harness/indices/대기/%s.md\n" % (work, stem))


def drops(lines):
    return [x for x in lines if x.startswith("FILL-HOLD-DROP")]


def to_close(w):   # 닫기 바퀴 꼴 = W1 닫힘 · 상한 1 · live 0(fill 0)
    nx.close(w, nx.W1)
    w.env["FT2_TEAM_NANO_MAX"] = "1"
    kw._put(w.tm, {"alive": [], "pane": {}})


def state3(w):   # ③ 실사건 꼴 = A(보류 + done) · B(done) · C 사람
    hold(w)
    w.work(A, done=True), w.work(B, done=True)
    human(w, C)


def c2(w, mp):   # ② assign 거부로 보류 → A done(원장 그대로) → 채우기 1회 = 보류 지움 · DROP 1줄 → 다음 바퀴 DROP 0
    human(w, B, C)
    k, _ = fl.keeper(w, mp, ("assign", A))
    w.round(k)
    assert list(st(w)["fill_hold"]) == [KEY], st(w)
    for argv in (["assign", "--work", A, "--holder", "byz-harness-nano-x#0", "--evidence", "v1,v2"], ["deliver", "--work", A],
                 ["complete", "--work", A, "--attempt", "a1"]):
        out, rc = w.CLI.run(argv + ["--root", str(w.root), "--team", "harness"])
        assert rc == 0, out
    assert drops(w.round()) == ["FILL-HOLD-DROP harness %s 끝남" % A] and KEY not in st(w)["fill_hold"], st(w)
    w.t += 60
    assert drops(w.round()) == []


def c3(w, mp):   # ③ 채우기 길 본문 = «끝남 2» · «보류» 글 0
    state3(w)
    w.round()
    n = nx.notes(w)
    assert len(n) == 1 and "막힌 사유별 끝남 2 사람 1" in n[0] and "보류" not in n[0], n


def c4(w, mp):   # ④ 같은 상태 · 닫기 영수 먼저 → 본문 «끝남 2» · fill_hold 에 A 없음
    state3(w)
    to_close(w)
    lines = w.round()
    n = nx.notes(w)
    assert nx.receipts(w) and len(n) == 1 and "막힌 사유별 끝남 2 사람 1" in n[0] and "보류" not in n[0], (n, lines)
    assert KEY not in st(w).get("fill_hold", {}) and drops(lines) == ["FILL-HOLD-DROP harness %s 끝남" % A], lines


def c5(w, mp):   # ⑤ 같은 날 채우기 바퀴 → 닫기 영수 바퀴 → [다음 없음] 1통 · 두 길 같은 글
    state3(w)
    w.round()
    to_close(w)
    w.t += 60
    w.round()
    n = nx.notes(w)
    assert nx.receipts(w) and len(n) == 1 and "막힌 사유별 끝남 2 사람 1" in n[0], n


def c6(w, mp):   # ⑥ A 보류(done 아님 · 이름순 앞) · B 고를 수 있음 → 닫기 영수 다음 카드 = B · A submit 0
    hold(w)
    human(w, C)
    to_close(w)
    w.round()
    assert nx.launched(w) == [B] and nx.count(w, "accept", A) == 0 and KEY in st(w)["fill_hold"], nx.launched(w)


def c7(w, mp):   # ⑦ A 보류뿐 · 나머지 사람 → 닫기 영수 다음 카드 0 · 본문 «보류 1» · «보류 A»
    hold(w)
    human(w, B, C)
    to_close(w)
    w.round()
    n = nx.notes(w)
    assert nx.launched(w) == [] and nx.count(w, "accept", A) == 0, nx.launched(w)
    assert len(n) == 1 and "막힌 사유별 보류 1 사람 2" in n[0] and "보류 " + A in n[0], n


def c8(path, form):   # ⑧ 원장 updated > 보류 시각 → 두 길 모두 A 다시(fill_hold 에 A 없음) · 값 두 꼴
    def case(w, mp):
        hold(w, w.t - 100 if form == "num" else "%s|assign" % (w.t - 100))
        kw._put(w.state / "card-assign" / (A + ".json"), {"state": "none", "updated": w.t + 1})
        human(w, B, C)
        to_close(w) if path == "close" else None
        w.round()
        assert nx.launched(w) == [A] and KEY not in st(w).get("fill_hold", {}), (nx.launched(w), st(w))
    return case


JUDGE = ["판정 불가 harness 다음 카드 고르기 ft2 state — 다음 카드 0"]   # 기준판에서 잰 «판정 불가» 줄


def c9a(w, mp):   # ⑨ⓐ ft2 state 못 읽음 → 보류 지움 0 · «판정 불가» 줄 = 기준판 그대로
    state3(w)
    k = w.keeper()
    mp.setattr(type(k).close.__globals__["keeper_next"], "ft2_state", lambda k, team: None)
    lines = w.round(k)
    assert KEY in st(w)["fill_hold"] and drops(lines) == [] and [x for x in lines if x.startswith("판정 불가")] == JUDGE, lines


def c9b(w, mp):   # ⑨ⓑ A 의 짝 work 가 done → A 보류 지움 · «끝남» 으로 셈
    hold(w)
    pair(w, PW, A)
    w.work(PW, done=True)
    human(w, B, C)
    lines = w.round()
    n = nx.notes(w)
    assert drops(lines) == ["FILL-HOLD-DROP harness %s 끝남" % A] and KEY not in st(w)["fill_hold"], lines
    assert len(n) == 1 and "막힌 사유별 끝남 1 사람 2" in n[0] and "끝남 " + A in n[0], n


def c10(w, mp):   # ⑩ stem 은 done 아님 · 짝 work 만 done → 보류 지움과 choose «끝남» 이 같다 · 두 길 모두 A 재시도 0
    hold(w)
    pair(w, PW, A)
    w.work(PW, done=True)
    w.round()
    assert nx.launched(w) == [B] and nx.count(w, "accept", A) == 0 and KEY not in st(w)["fill_hold"], nx.launched(w)
    to_close(w)
    w.t += 60
    w.round()
    assert A not in nx.launched(w) and nx.count(w, "accept", A) == 0, nx.launched(w)


CASES = {"②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧fill-num": c8("fill", "num"), "⑧fill-str": c8("fill", "str"),
         "⑧close-num": c8("close", "num"), "⑧close-str": c8("close", "str"), "⑨ⓐ": c9a, "⑨ⓑ": c9b, "⑩": c10}


def run(name, tmp, mp, ft2=kw.FT2):
    w = fl.world(tmp, mp, ft2=ft2)
    CASES[name](w, mp)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    run(name, tmp_path, monkeypatch)


MUTANTS = {"M1": ("elif state is not None and ended(stem, pair, done):", "elif False:", ("②", "③", "⑤")),
           "M2": ("choose(k, team, release(k, team))", "choose(k, team, release(k, team) and frozenset())", ("⑥", "⑦")),
           "M3": ("choose(k, team, release(k, team))",
                  'choose(k, team, {x.split("|", 1)[1] for x in k.state.get("fill_hold", {}) if x.split("|")[0] == team})', ("④",))}


@pytest.mark.parametrize("name,case", [(m, c) for m, (_, _, cs) in MUTANTS.items() for c in cs])
def test_mutant(name, case, tmp_path, monkeypatch):
    old, new, _ = MUTANTS[name]
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
