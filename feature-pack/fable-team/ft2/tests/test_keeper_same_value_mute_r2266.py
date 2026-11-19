"""r2266 ft2 keeper — 날짜가 아니라 값을 열쇠로: 영구 Unsure 재시도(C1) · [다음 없음](C2) · 팀장 없는 팀 묶음(C3) · 불변(C4).
대역 = r2065 world(r1812 임시 리포·가짜 tmux·가짜 mbox) + 주입 시계 w.t + 가짜 card_stage(work 마다 사유 · 호출 기록) · 실 BYZ 리포·실 push·설치 0 · sleep 0.
반례 ①~⑨ · 변이 M1~M9(사본에서만 · 변이마다 원본으로 같은 사례 1회 더) · 기준판 Red = ① ④ ⑦(⑥ 은 새 로그 줄이라 기준판에도 없다)."""
import importlib.util
import shutil
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
_S = importlib.util.spec_from_file_location("r2266_nr", str(HERE / "test_keeper_notify_recipient.py"))
nr = importlib.util.module_from_spec(_S)
_S.loader.exec_module(nr)
kw, FT2, TEAM, DAY, AT = nr.kw, nr.FT2, nr.TEAM, 86400, "2026-11-13T09:00:00"
NO_LAND, TWO, BOTH, ZERO, SLOW = "착지 줄 없음 %s-x", "두 가지에 진행 카드", "진행·대기 둘 다 카드", "진행 카드 0개", "git fetch 시간초과 7초"


class Fake:
    """card_stage 대역 — work 마다 Unsure 사유(why) · done 없음 work(nodone) · stage 호출 = calls(work 이름)."""
    class Unsure(Exception):
        pass
    spawn = None

    def __init__(self, why, nodone=()):
        self.why, self.nodone, self.calls = dict(why), set(nodone), []

    def done_at(self, root, team, work):
        return None if work in self.nodone else AT

    def stage(self, byz, root, team, work, at, now):
        self.calls.append(work)
        raise self.Unsure(self.why[work] % work if "%s" in self.why[work] else self.why[work])


def cli(w, *argv):
    out, rc = w.CLI.run(list(argv) + ["--root", str(w.root), "--team", TEAM])
    assert rc == 0, (argv, out)


def done(w, work, card=True):
    """카드(두 ref 진행 · 착지 줄) → dispatch → park → complete — keeper 밖(실 CLI) · K1 길 = 바퀴마다 stage_card 자리."""
    if card:
        w.card(work, w.pack_sha())
    w.work(work, intent=False)
    cli(w, "park", "--work", work, "--attempt", "a1", "--reason", "idle-done")
    cli(w, "complete", "--work", work, "--attempt", "a1")


def turn(w, fake):
    k = w.keeper()
    k.cs = fake
    w.round(k)
    return k


def drop(w, branch, rel):
    seed = w.tmp / "seed-byz"
    kw._git(seed, "checkout", "-q", branch), kw._git(seed, "rm", "-q", rel)
    kw._git(seed, "commit", "-q", "-m", "drop"), kw._git(seed, "push", "-q", "origin", branch)


def n(fake, work):
    return fake.calls.count(work)


def c1(w):   # ① 영구 Unsure(착지 줄 없음) · 카드 그대로 · 다음 날 → stage 0회(기준판 1회)
    done(w, "r9601")
    fake = Fake({"r9601": NO_LAND})
    turn(w, fake)
    assert n(fake, "r9601") == 1, fake.calls
    w.t += DAY
    turn(w, fake)
    assert n(fake, "r9601") == 1, fake.calls


def c2(w):   # ② 값이 바뀌면 1회 — blob 바뀜 · 사본 한쪽 지움(두 가지 · 진행·대기) · 0개 → 생김 · BYZ 낡은 바퀴 = 비교 0
    path = "design/harness/indices/%s/%s-x.md"
    done(w, "r9611"), done(w, "r9612")
    w.card("r9613", w.pack_sha(), refs=("main",)), w.card("r9613", w.pack_sha(), stage="대기", refs=("ops/main-base",))
    done(w, "r9613", card=False), done(w, "r9614", card=False), done(w, "r9615")
    fake = Fake({"r9611": NO_LAND, "r9612": TWO, "r9613": BOTH, "r9614": ZERO, "r9615": NO_LAND})
    turn(w, fake)
    assert all(n(fake, "r961%d" % i) == 1 for i in range(1, 6)), fake.calls
    w.commit("byz", {path % ("진행", "r9611"): "# 인덱스: r9611\n- 상태: 대기\n- 고침: 1\n"}, "main")
    drop(w, "ops/main-base", path % ("진행", "r9612")), drop(w, "ops/main-base", path % ("대기", "r9613"))
    w.card("r9614", refs=("main",))
    w.t += DAY
    turn(w, fake)
    assert [n(fake, "r961%d" % i) for i in range(1, 5)] == [2, 2, 2, 2], fake.calls   # 값 바뀜 = 다음 날도 1회
    w.t += DAY
    k, before = w.keeper(), n(fake, "r9615")
    k.cs, k.stale = fake, {str(w.root)}
    k.locked(lambda: (setattr(k, "tried", set()), k.stage_card(TEAM, "r9615")))
    assert n(fake, "r9615") == before + 1, fake.calls   # BYZ 낡음 = 지금 꼴(날 바뀜 = 다시)


def c3(w):   # ③ 일시 사유 = 하루 3회 · 다음 날 1회 · «done 없음» = 값 기억 0 → done 생김 다음 바퀴 1회
    done(w, "r9621"), done(w, "r9622")
    fake = Fake({"r9621": SLOW, "r9622": NO_LAND}, nodone={"r9622"})
    turn(w, fake)
    assert n(fake, "r9621") == 1 and n(fake, "r9622") == 0, fake.calls
    fake.nodone.clear()
    turn(w, fake)
    assert n(fake, "r9622") == 1, fake.calls
    turn(w, fake), turn(w, fake)
    assert n(fake, "r9621") == 3, fake.calls
    w.t += DAY
    turn(w, fake)
    assert n(fake, "r9621") == 4, fake.calls


def tell(w, team, stem, k=None):
    """[다음 없음] 1번 = none_tell(막힌 카드 1장 = 지문) · 새 keeper(state 는 locked 가 저장)."""
    k = k or w.keeper()
    kn = w.K.closing.keeper_next
    names = {"DA": [(stem, False)]}
    k.locked(lambda: kn.none_tell(k, team, "%s %s · 막힌 1" % (kn.NONE, team), names))
    return k


def c4(w):   # ④ [다음 없음] 같은 지문 · 다음 날 → 0통(기준판 1통)
    nr.spec(w)
    tell(w, TEAM, "r9631-a")
    w.t += DAY
    tell(w, TEAM, "r9631-a")
    assert len(nr.sends(w)) == 1, nr.sends(w)


def c5(w):   # ⑤ 지문 바뀜 1통 · 승계(받는 좌석 바뀜) 1통 · 1일째 실패(E3) → 2일째 1통 · 받는 곳 없음(E6) → 다음 날 1통
    nr.spec(w)
    tell(w, TEAM, "r9641-a"), tell(w, TEAM, "r9641-b")
    assert len(nr.sends(w)) == 2, nr.sends(w)
    w.t += DAY
    nr.roster(w, TEAM, _master="M2-harness")
    tell(w, TEAM, "r9641-b")
    assert len(nr.sends(w)) == 3 and nr.sends(w)[-1][1] == "M2-harness", nr.sends(w)
    w.t += DAY
    nr.spec(w, rc=1)
    tell(w, TEAM, "r9641-c")
    w.t += DAY
    nr.spec(w)
    tell(w, TEAM, "r9641-c")
    assert len(nr.sends(w)) == 5 and nr.sends(w)[-1][1] == "M2-harness", nr.sends(w)
    nr.roster(w, TEAM, _master="", _desk="")
    tell(w, TEAM, "r9641-d")
    w.t += DAY
    nr.roster(w, TEAM, _master="M2-harness")
    tell(w, TEAM, "r9641-d")
    assert len(nr.sends(w)) == 6, nr.sends(w)


def c6(w):   # ⑥ 같은 날 3통 뒤 지문 바뀜 → 쪽지 0 · NEXT-NONE-MUTE 1줄 · 같은 지문 다시 → 로그 0
    nr.spec(w)
    lines = []
    for stem in ("r9651-a", "r9651-b", "r9651-c", "r9651-d", "r9651-d"):
        lines += tell(w, TEAM, stem).lines
    mute = [x for x in lines if x.startswith("NEXT-NONE-MUTE")]
    assert len(nr.sends(w)) == 3 and len(mute) == 1, (nr.sends(w), lines)


def c7(w):   # ⑦ 팀장 없는 팀 · 같은 [다음 없음] 3바퀴 × 3일 → 1건 · 날짜 열쇠 같은 판정(open) 3일 → 1건
    nr.roster(w, "chatbot", _master="", _desk=""), nr.spec(w)
    for _day in range(3):
        for _ in range(3):
            k = tell(w, "chatbot", "r9661-a")
            w.t += 60
        k.locked(lambda: k.notify("chatbot", "%s|open|seat-q" % k.stamp()[:10], nr.BODY[0]))
        w.t += DAY
    book = (k.state.get("undelivered") or {}).get("chatbot", [])
    assert len(book) == 2, book


def c8(w):   # ⑧ SKIP_TEAMS 팀 → stage · 쪽지 · 쌓기 0
    nr.spec(w)
    k = w.keeper()
    kw._put(Path(k.dir) / "SKIP_TEAMS", "%s\nchatbot\n" % TEAM)
    done(w, "r9671")
    fake = Fake({"r9671": NO_LAND})
    turn(w, fake)
    nr.roster(w, "chatbot", _master="", _desk="")
    for team in (TEAM, "chatbot"):
        k = w.keeper()
        k.skip = {TEAM, "chatbot"}
        tell(w, team, "r9671-a", k)
    assert fake.calls == [] and nr.sends(w) == [] and not (k.state.get("undelivered") or {}).get("chatbot"), (fake.calls, nr.sends(w), k.state)


def c9(w):   # ⑨ 팀장 있는 팀의 다른 판정 쪽지(날짜 열쇠) = 지금처럼 날마다 1통
    nr.spec(w)
    for _ in range(2):
        k = w.keeper()
        k.locked(lambda: k.notify(TEAM, "%s|open|seat-q" % k.stamp()[:10], nr.BODY[0]))
        w.t += DAY
    assert len(nr.sends(w)) == 2, nr.sends(w)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9}
KP, KN, KR = "adapters/pi/keeper.py", "adapters/pi/keeper_next.py", "adapters/pi/keeper_report.py"
STUCK = '"진행·대기 둘 다 카드", "진행 카드 ")'
MK = '"%s|%s" % (team, to)'
MUTANTS = {"M1": (KP, "book[key][3] == self.hits(team, work)", "True", ("②",)),
           "M2": (KP, STUCK, '"진행·대기 둘 다 카드", "진행 카드 ", "git fetch 시간초과")', ("③",)),
           "M3": (KN, MK, '"%s|%s|%s" % (k.stamp()[:10], team, to)', ("④",)),
           "M4": (KN, 'k.log("NEXT-NONE-MUTE", ', '(lambda *a: None)("NEXT-NONE-MUTE", ', ("⑥",)),
           "M5": (KR, "if tail not in seen:", "if True:", ("⑦",)),
           "M6": (KP, STUCK, '"진행·대기 둘 다 카드", "진행 카드 ", "done 없음")', ("③",)),
           "M7": (KP, "return sorted(out)", "return sorted(out)[:1]", ("②",)),
           "M8": (KN, "body):   # r2266 C2", "body) or True:   # r2266 C2", ("⑤",)),
           "M9": (KN, MK, "team", ("⑤",))}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](nr.world(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    path, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / path).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / path).write_text(text.replace(old, new), encoding="utf-8")
    for i, case in enumerate(cases):
        (tmp_path / ("w%d" % i)).mkdir(), (tmp_path / ("o%d" % i)).mkdir()
        with pytest.raises(AssertionError):   # 변이 = 그 사례가 무너진다
            CASES[case](nr.world(tmp_path / ("w%d" % i), monkeypatch, tree))
        CASES[case](nr.world(tmp_path / ("o%d" % i), monkeypatch))   # 원본 대조 = 같은 사례가 원본에서는 선다
