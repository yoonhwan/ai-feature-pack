"""r2208 ft2 keeper 나노 이름 소문자 — 대문자 stem 카드의 나노 이름도 소문자(이름 lint · ft-mbox seat() 문법) · sha1 꼬리 = 원래 stem ·
40자 넘는 stem 의 원장 seat 이름 우선 그대로 · 대문자 옛 세션 살아 있음 = 이름겹침 · 띄운 열기 잇기 = 띄운 때 이름(ft2 owners[work].holder) (반례 ②~⑧ · 변이 M1 M2).
대역 = r2016 가짜 keeper(이름 함수) · r2111 세계(r1871 world · 가짜 tmux list-sessions) · r2101 세계(fill_open · 가짜 launch·record).
실 tmux·실 좌석·명부·우편함·설치 0 · sleep 0. 기준판 = ② Red(대문자 이름). 변이는 사본에서만 · 원본으로 같은 사례 1회 더.
"""
import hashlib, importlib.util, json, shutil  # noqa: E401
from pathlib import Path
import pytest

HERE = Path(__file__).resolve().parent


def _load(name, alias):
    spec = importlib.util.spec_from_file_location(alias, str(HERE / name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


nd = _load("test_keeper_nano_name_dash_r2016.py", "keeper_r2208_r2016")   # 이름 함수 · 가짜 keeper
r13 = _load("test_keeper_next_reopen_name_tail_r2113.py", "keeper_r2208_r2113")   # 고르기 세계 · card · alive · skip
hc = _load("test_new_card_hold.py", "keeper_r2208_r2101")   # fill 세계 · launched · ledger
kw, TEAM = hc.kw, hc.TEAM
ROOM = "R-room-runner-t15-expire-delete"   # 실사건(room t15)
LONG = "M5-goal6-upper-last-sentence-release-confirm-lag"   # 48자 · 대문자
LOW = "r9003-short-card"
UP = "R9711-Up-card"   # ⑤ ⑦ ⑧ 대문자 stem


def tail(stem):   # 소문자 앞 33자 + «-» + sha1(원래 stem) 6자
    return "byz-harness-nano-%s-%s#0" % (stem[:33].rstrip("-").lower(), hashlib.sha1(stem.encode("utf-8")).hexdigest()[:6])


def old(stem):   # 기준판 이름(대문자 그대로)
    return "byz-harness-nano-%s#0" % stem[:40].rstrip("-")


class LedKeeper(nd.FakeKeeper):
    def __init__(s, led=None):
        super().__init__()
        s.led = led or {}

    def read_json(s, path):
        return s.led


def c2(tmp, mp, ft2):   # ② ROOM → 소문자 이름(기준판 = 대문자 · Red)
    k = LedKeeper()
    got = nd.load(ft2).nano_name(k, "room", ROOM)
    assert got == "byz-room-nano-r-room-runner-t15-expire-delete#0" and k.lines == [], got


def c3(tmp, mp, ft2):   # ③ 40자 넘는 대문자 stem → 소문자 33자 + «-» + sha1(원래 stem) 6자
    got = nd.load(ft2).nano_name(LedKeeper(), "harness", LONG)
    assert got == tail(LONG) and got == got.lower(), got


def c4(tmp, mp, ft2):   # ④ ③ 인데 원장 seat = 대문자 이름 → 그 이름 그대로
    k = LedKeeper({"state": "seat", "seat": old(LONG)})
    assert nd.load(ft2).nano_name(k, "harness", LONG) == old(LONG)


def c6(tmp, mp, ft2):   # ⑥ 소문자 stem → 기준판과 같은 이름
    assert nd.load(ft2).nano_name(LedKeeper(), "harness", LOW) == "byz-harness-nano-%s#0" % LOW


def c5(tmp, mp, ft2):   # ⑤ 대문자 옛 세션 살아 있음 → 이름겹침 · 건너뜀 1줄 · launch 0
    w = r13.base.world(tmp, mp, {}, ft2=ft2)
    r13.card(w, UP)
    r13.alive(w, old(UP))
    lines = w.round()
    assert UP not in r13.base.launched(w) and len(r13.skip(lines, UP, "이름겹침")) == 1, lines


def fill_world(tmp, mp, ft2, owner):   # ⑦ ⑧ 공통 — 설치 전 대문자 이름으로 띄운 열기 · 그 세션 살아 있음 · 원장 seat = 대문자
    w = hc.world(tmp, mp, cards={TEAM: {UP: ""}}, ft2=ft2)
    if owner:
        w.work(UP, intent=False, holder=old(UP), turn=None)
    st = json.loads(w.tm.read_text(encoding="utf-8"))
    st["alive"].append(old(UP))
    kw._put(w.tm, st)
    kw._put(w.state / "card-assign" / (UP + ".json"), {"state": "seat", "seat": old(UP)})
    kw._put(w.kdir / "state.json", {"fill_open": {"%s|%s" % (TEAM, UP): "a1"}})
    return w


def c7(tmp, mp, ft2):   # ⑦ 띄운 열기 잇기 = 그때 이름 → 새 나노 0 · 원장 seat 그대로
    w = fill_world(tmp, mp, ft2, True)
    lines = w.round()
    assert hc.launched(w) == [] and hc.ledger(w, UP) == {"state": "seat", "seat": old(UP)}, lines
    assert "NEXT harness fill:%s -> %s %s" % (UP, UP, old(UP)) in lines, lines


def c8(tmp, mp, ft2):   # ⑧ 그때 이름 못 읽음(owner 없음) → 다시 셈 후퇴 0 · 판정 불가 1줄 · 새 나노 0
    w = fill_world(tmp, mp, ft2, False)
    lines = w.round()
    bad = [x for x in lines if x.startswith("판정 불가 harness fill:%s" % UP) and "다음 바퀴" in x]
    assert hc.launched(w) == [] and len(bad) == 1 and hc.ledger(w, UP) == {"state": "seat", "seat": old(UP)}, lines


CASES = {"②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
KN = "adapters/pi/keeper_next.py"
MUTANTS = {"M1": ("sha1(stem.encode", "sha1(stem.lower().encode", ("③",)),   # sha1 꼬리를 소문자 stem 으로 셈
           "M2": ("nh = then_name(k, team, stem)", "nh = nano_name(k, team, stem)", ("⑦",))}   # 잇기 = 다시 셈


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](tmp_path, monkeypatch, kw.FT2)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old_text, new_text, cases = MUTANTS[name]
    shutil.copytree(kw.FT2, tree := tmp_path / "m" / "ft2", ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KN).read_text(encoding="utf-8")
    assert text.count(old_text) == 1, (name, old_text)
    (tree / KN).write_text(text.replace(old_text, new_text), encoding="utf-8")
    for case in cases:
        bad, good = tmp_path / ("bad" + case), tmp_path / ("good" + case)
        bad.mkdir(), good.mkdir()
        with pytest.raises(AssertionError):
            CASES[case](bad, monkeypatch, tree)
        monkeypatch.undo()
        CASES[case](good, monkeypatch, kw.FT2)   # 원본으로 같은 사례 1회 더 = PASS
