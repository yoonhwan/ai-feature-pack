"""r2111 ft2 keeper 다음 카드 — 전달된(손 dispatch 뒤 result 로 owner 0 · done 0) 카드는 원장 풀림 뒤에만 고름 ·
nano_name 과 대소문자만 다른 세션이 살아 있으면 고르지 않음 (반례 ①~⑦ · ⑥b · ⑦b · 변이 M1~M5).
대역 = r1871 world(임시 root·git·가짜 tmux list-sessions·launch·record) + 짝 표 cards.tsv + launch/<work>@<att>.intent + card-assign 원장 json.
실 tmux·명부·ft2 원장·우편함·설치 0 · sleep 0. 기준판 = ① ⑦ Red(전달된 카드·대소문자 겹침 카드를 고름).
"""
import importlib.util, json, shutil, time  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("keeper_next_r2111_base", str(HERE / "test_pi_keeper_next_card_r1871.py"))
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)
kw = base.kw
S, W, KN = "r9881-Lx", "r9883", "adapters/pi/keeper_next.py"
T0, T1, T2 = "2026-11-16T15:37:22", "2026-11-16T15:39:00", "2026-11-16T15:41:19"
FAIL_LS = 'if a[0] == "list-sessions" and d.get("ls_rc"): sys.exit(d["ls_rc"])\n'


def epoch(at):
    return time.mktime(time.strptime(at, "%Y-%m-%dT%H:%M:%S"))


def hand(w, work, at, holder="h"):
    """손 dispatch 1회 = (첫 회만 submit) assign → deliver → claim → start → result(owner 0 · done 0) + intent(at · None = 파일 0)."""
    run = lambda *a: w.CLI.run(list(a) + ["--root", str(w.root), "--team", "harness"])   # noqa: E731
    first = not any(r["kind"] == "accept" and r.get("work") == work for r in w.journal())
    steps = ([("submit", "--command", "c-" + work, "--body", "b-" + work, "--work", work)] if first else []) + [
        ("assign", "--work", work, "--holder", holder, "--evidence", "v1,v2"), ("deliver", "--work", work)]
    for argv in steps:
        out, rc = run(*argv)
        assert rc == 0, out
    att = out["attempt"]
    out, rc = run("claim", "--work", work, "--holder", holder)
    for verb in ("start", "result"):
        out, rc = run(verb, "--work", work, "--holder", holder, "--gen", str(out["gen"]))
        assert rc == 0, out
    if at is not None:
        kw._put(w.runtime() / "launch" / ("%s@%s.intent" % (work, att)), {"FT2_HOLDER": holder, "state": "opened", "at": at})
    return att


def led(w, released=None):
    kw._put(w.state / "card-assign" / (S + ".json"), {"state": "none", "since": 1.0, "updated": 1.0, "released_at": released})


def skip(lines, why):
    return [x for x in lines if x.startswith(("NEXT-SKIP harness %s" % S, "판정 불가 harness %s" % S)) and why in x]


def picked(w):
    return base.count(w, "accept", S) > 1 or S in base.launched(w)


def again(w):   # 둘째 바퀴 = 다른 일 닫힘 → 닫기 뒤 pick 길 1번 더
    base.close(w, base.W2)
    w.t += 60
    return w.round()


def c1(w):   # ① deliveries [a1] · 원장 없음 → 고르지 않음 · «전달됨 1» · launch 0
    hand(w, S, T0)
    lines = w.round()
    assert not picked(w) and base.launched(w) == [], lines
    assert len(skip(lines, "전달됨")) == 1 and any("막힌 사유별 전달됨 1" in x for x in base.notes(w)), (lines, base.notes(w))


def c2(w):   # ② 원장 none · released_at = a1 at + 60초 → 고름 · launch 1
    hand(w, S, T0)
    led(w, epoch(T0) + 60)
    w.round()
    assert base.launched(w) == [S], base.launched(w)


def c3(w):   # ③ 원장 none · released_at = a1 at − 60초(풀림 뒤 또 손으로 엶) → 고르지 않음
    hand(w, S, T0)
    led(w, epoch(T0) - 60)
    lines = w.round()
    assert not picked(w) and len(skip(lines, "전달됨")) == 1, lines


def c4(w):   # ④ deliveries [a1, a2] · a2 at > released_at > a1 at → 고르지 않음(최신 attempt)
    hand(w, S, T0), hand(w, S, T2, holder="h2")
    led(w, epoch(T1))
    lines = w.round()
    assert not picked(w) and len(skip(lines, "전달됨")) == 1, lines


def c5(w):   # ⑤ intent 없음 → 고르지 않음 · «판정 불가» 1줄 · 둘째 바퀴 같은 줄 0
    hand(w, S, None)
    lines = w.round()
    assert not picked(w) and len(skip(lines, "intent")) == 1, lines
    assert skip(again(w), "intent") == [] and not picked(w)


def c5b(w):   # ⑤ at 꼴 깨짐 → 같음
    hand(w, S, "16/11 15:37")
    lines = w.round()
    assert not picked(w) and len(skip(lines, "intent")) == 1, lines
    assert skip(again(w), "intent") == [] and not picked(w)


def c6(w):   # ⑥ 짝 표 W → S · deliveries 가 W 에만 → S 고르지 않음
    base_pair(w)
    hand(w, W, T0)
    lines = w.round()
    assert not picked(w) and len(skip(lines, "전달됨")) == 1, lines


def c6b(w, swap=False):   # ⑥b W [a1] at T0 · S [a1] at T2 · released_at T1 → 고르지 않음 / 시각을 바꿔도 같음
    base_pair(w)
    hand(w, W, T2 if swap else T0), hand(w, S, T0 if swap else T2)
    led(w, epoch(T1))
    lines = w.round()
    assert not picked(w) and len(skip(lines, "전달됨")) == 1, lines


def c7(w):   # ⑦ deliveries 0 · 소문자 세션 살아 있음 → 고르지 않음 · «이름겹침» · launch 0 / 같은 글자 세션만 → 지금과 같음(고름)
    alive(w, base.nh(S))
    lines = w.round()
    assert not picked(w) and base.launched(w) == [] and len(skip(lines, "이름겹침")) == 1, lines
    assert any("막힌 사유별 이름겹침 1" in x for x in base.notes(w)), base.notes(w)


def c7same(w):   # ⑦ 둘째 칸 — 같은 글자 세션만 → 이름겹침 0 · 고름(submit)
    alive(w, base.nh(S).lower())
    lines = w.round()
    assert skip(lines, "이름겹침") == [] and base.count(w, "accept", S) == 1, lines


def c7b(w):   # ⑦b list-sessions rc≠0 · gates 안 거친 choose(바퀴 밖 = ls 캐시 0) → 고르지 않음 · «판정 불가» 1줄 · 둘째 부름 같은 줄 0
    tm = w.tmp / "bin" / "tmux"
    kw._put(tm, tm.read_text(encoding="utf-8").replace(base.LS, FAIL_LS + base.LS, 1)), tm.chmod(0o755)
    kw._put(w.tm, dict(json.loads(w.tm.read_text(encoding="utf-8")), ls_rc=1))
    w.round()   # 바퀴 1회 = fetch(카드 ref) · gates 는 ls 실패로 NEXT-HOLD(고름 0)
    assert not picked(w)
    k, kn = w.keeper(), w.K.closing.keeper_next
    assert kn.choose(k, "harness") is None and len(skip(k.lines, "list-sessions")) == 1, k.lines
    n = len(k.lines)
    assert kn.choose(k, "harness") is None and skip(k.lines[n:], "list-sessions") == [], k.lines[n:]


def base_pair(w):
    path = w.runtime() / "cards.tsv"
    kw._put(path, "%s\tdesign/harness/indices/대기/%s.md\n" % (W, S))


def alive(w, name):   # 나노 상한 2 = 살아 있는 세션 1개로는 칸이 닫히지 않음(고르기 길까지 감)
    w.env["FT2_TEAM_NANO_MAX"] = "2"
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    kw._put(w.tm, dict(d, alive=d["alive"] + [name]))


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑤b": c5b, "⑥": c6, "⑥b": c6b, "⑥b'": lambda w: c6b(w, True),
         "⑦": c7, "⑦'": c7same, "⑦b": c7b}
MUTANTS = {"M1": ("        block = block or delivered(k, team, stem, {stem} | pair.get(stem, set()), state, led)   # r2111 A1\n", "", ("①",)),
           "M2": (" and rel > last", "", ("③",)),
           "M3": ("max(times)", "times[0]", ("④",)),
           "M4": ("{stem} | pair.get(stem, set()), state, led)", "{stem}, state, led)", ("⑥", "⑥b'")),
           "M5": ("x != nh and x.lower() == nh.lower()", "x.lower() == nh.lower()", ("⑦'",))}


def run(name, tmp, mp, ft2=kw.FT2):
    w = base.world(tmp, mp, {S: ""}, ft2=ft2)
    CASES[name](w)


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
        run(case, good, monkeypatch)   # 원본으로 같은 사례 1회 더 = PASS
