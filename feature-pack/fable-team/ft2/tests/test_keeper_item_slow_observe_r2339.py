"""r2339 keeper 항목 느림 — b1·b2f 한 항목이 3초를 넘으면 바퀴 끝에 ITEM-SLOW 1줄(부분 단계 초 · 호출 수·초 · 첫 두 낱말).

계약 I1(항목 = b1·b2f 칸만 · timed(work=) 명시 인자 · finally 에 (팀 · work · 칸) 합 + 부분 단계(fn 이름) 초 · 끊김·예외도 셈) ·
I2(self.call 1회마다 지금 항목에 수 +1·초 더함·첫 두 낱말별 초 · 항목 밖 호출은 어느 항목에도 안 든다) ·
I3(셈은 바퀴 시작에 새로 · 바퀴 끝 1회 · 항목 합 ≥ 3초만 · 느린 순 3개 · 넘침 more=N · 넘는 항목 0 = 줄 0) ·
I4(판정·상태 파일·cursor·ROUND·NANO-SLOW 줄 글자 그대로).
반례 ①~⑫ · 변이 M1~M7(사본에서만 · 원본 나무로 같은 사례 1회 더 = 반대 결과 대조).
대역 = test_keeper_round_60s.Rig(주입 시계 · 가짜 subprocess · 가짜 journal·tmux·mbox). sleep 0 · 네트워크 0 · 실 runtime 0.
"""
import json
import pathlib
import shutil

import pytest

from test_keeper_round_60s import Rig, line

KP = "adapters/pi/keeper.py"


def _tree():   # 기준 나무 = 이 시험 파일 옆 ft2
    return pathlib.Path(__file__).resolve().parents[1]


def _rig(tmp, tree):
    """Rig + 이 시험의 대역 이름 고정 — timed 가 fn.__name__ 을 부분 단계 이름으로 쓴다(fill·complete)."""
    w = Rig(tmp, tree)
    g = w.mod.Keeper.__init__.__globals__

    def fill(k, team):
        w.done.append(["fill", team])
    g["closing"].keeper_next.fill = fill

    def complete(team, work, attempt, landed):
        w.done.append(["complete", team, work])
        return True
    w.k.complete = complete
    return w


def _items(w):
    return [x for x in w.k.lines if x.startswith("ITEM-SLOW")]


def _journal(w):
    rows = []
    for path in sorted((w.root / ".fable-team" / "state" / "ft2-keeper").glob("*.jsonl")):
        rows += [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]
    return rows


def _plain(w):   # ITEM-SLOW 줄과 임시 폴더 경로를 지운 로그 = 기준판과 글자 그대로 같아야 한다
    return [x.replace(str(w.root), "<root>") for x in w.k.lines if not x.startswith("ITEM-SLOW")]


def _jplain(w):   # 일지도 같은 식(ITEM-SLOW 줄·임시 폴더 경로만 지운다)
    return [dict(r, line=r["line"].replace(str(w.root), "<root>")) for r in _journal(w) if r["kind"] != "ITEM-SLOW"]


def _landing(w, secs, calls=None):
    """landing 대역 — 주입 시계 secs 초(calls = (낱말, 초, 횟수) 면 바깥 호출로 흐른다)."""
    def landing(team, work):
        w.done.append(["land", team, work])
        if calls:
            w.reads(calls[:2], calls[2], calls[3])
        w.wait(secs)
        return ("ab" * 20, "main", "")
    landing.__name__ = "landing"
    w.k.landing = landing
    return landing


# ── ①~③ 줄이 서는 조건 ───────────────────────────────────────────────────────
def c1(tree, tmp):   # ① b1 항목 1개 4초 → ITEM-SLOW 1줄 · 칸 b1 · 팀/work 맞음
    w = _rig(tmp, tree)
    _landing(w, 4.0)
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-"], w.k.lines


def c2(tree, tmp):   # ② b1 항목 2초 → 줄 0(일지에도 0)
    w = _rig(tmp, tree)
    _landing(w, 2.0)
    w.round()
    assert _items(w) == [] and [r for r in _journal(w) if r["kind"] == "ITEM-SLOW"] == [], w.k.lines


def c3(tree, tmp):   # ③ b2f fill 5초 → 1줄 · 칸 b2f · work «-»
    w = _rig(tmp, tree)
    g = w.mod.Keeper.__init__.__globals__

    def fill(k, team):
        w.done.append(["fill", team])
        w.wait(5.0)
    fill.__name__ = "fill"
    g["closing"].keeper_next.fill = fill
    w.round()
    assert _items(w) == ["ITEM-SLOW b2f t1/- s=5.00 parts=fill:5.00 call=0:0.00 top=-"], w.k.lines


# ── ④·⑨ 외부 호출 셈 ────────────────────────────────────────────────────────
def c4(tree, tmp):   # ④ 항목 안 git 3회 합 3.5초 → call=3:3.50 · top=git+show
    w = _rig(tmp, tree)
    _landing(w, 0.0, ("git", "show", 7.0 / 6, 3))
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=3.50 parts=landing:3.50,complete:0.00 call=3:3.50 top=git+show:3.50"], w.k.lines


def c9(tree, tmp):   # ⑨ fetch 단계 git 10회(5초) → 어느 항목 call 에도 안 셈(item 은 call=0:0.00)
    w = _rig(tmp, tree)
    _landing(w, 4.0)
    w.plan = lambda argv, timeout: (0.5, 0, "")

    def fresh(repo):
        for _ in range(5):
            w.k.call(["git", "show"])
        return True
    w.k.fresh = fresh
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-"], w.k.lines


# ── ⑤ 부분 단계 이름 ─────────────────────────────────────────────────────────
def c5(tree, tmp):   # ⑤ 한 work 의 landing 3초 + complete 1초 → parts=landing:3.00,complete:1.00 · s=4.00
    w = _rig(tmp, tree)
    _landing(w, 3.0)

    def complete(team, work, attempt, landed):
        w.done.append(["complete", team, work])
        w.wait(1.0)
        return True
    complete.__name__ = "complete"
    w.k.complete = complete
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:3.00,complete:1.00 call=0:0.00 top=-"], w.k.lines


# ── ⑥·⑪ 줄 수와 칸 거름 ────────────────────────────────────────────────────
def c6(tree, tmp):   # ⑥ 느린 항목 5개 → 줄 3개 + 마지막 줄 more=2
    w = _rig(tmp, tree)
    w.teams, w.works = ["t1", "t2", "t3", "t4", "t5"], {t: ["w1"] for t in ("t1", "t2", "t3", "t4", "t5")}
    _landing(w, 4.0)
    w.round()
    assert _items(w) == [
        "ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-",
        "ITEM-SLOW b1 t2/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-",
        "ITEM-SLOW b1 t3/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=- more=2"], w.k.lines


def c11(tree, tmp):   # ⑪ b3 60초 + fetch 5초 + b1 항목 4초 → b1 항목 1줄만(b3·fetch 줄 0 · more 0)
    w = _rig(tmp, tree)
    _landing(w, 4.0)

    def retired():
        w.done.append(["retired"])
        w.wait(60.0)
    w.k.retired = retired

    def fresh(repo):
        for _ in range(5):
            w.k.call(["git", "show"])
        return True
    w.k.fresh, w.plan = fresh, (lambda argv, timeout: (0.5, 0, ""))
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-"], w.k.lines


# ── ⑦·⑧ 끊김·예외에도 셈 ───────────────────────────────────────────────────
def c7(tree, tmp):   # ⑦ 예산 끊김(Cut)으로 빠진 항목도 줄에 듦(finally)
    w = _rig(tmp, tree)
    w.k.landing = lambda team, work: (w.reads(("git", "show"), 7.0, 20), ("ab" * 20, "main", ""))[1]
    w.k.landing.__name__ = "landing"
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=45.00 parts=landing:45.00 call=7:45.00 top=git+show:45.00"], w.k.lines
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w1 b1 — 다음 바퀴 여기부터"], w.k.lines


def c8(tree, tmp):   # ⑧ 항목에서 예외 → 줄에 듦 · 판정 줄·다음 work 진행 지금과 같음
    w = _rig(tmp, tree)
    w.works = {"t1": ["w1", "w2"]}

    def landing(team, work):
        w.done.append(["land", team, work])
        if work == "w1":
            w.wait(4.0)
            raise RuntimeError("boom")
        return ("ab" * 20, "main", "")
    landing.__name__ = "landing"
    w.k.landing = landing
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00 call=0:0.00 top=-"], w.k.lines
    assert line(w.k, "판정 불가") == ["판정 불가 t1 w1 내부 오류 RuntimeError"], w.k.lines
    assert ["land", "t1", "w2"] in w.done and ["complete", "t1", "w2"] in w.done, w.done


# ── ⑩·⑫ 손 0 · 바퀴마다 새로 ───────────────────────────────────────────────
def _scenario(tmp, tree):   # ⑩ 같은 입력 1바퀴 — 팀 2(느린 항목 1 · 빠른 항목 1)
    w = _rig(tmp, tree)
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w1"]}

    def landing(team, work):
        w.done.append(["land", team, work])
        w.wait(4.0 if team == "t1" else 1.0)
        return ("ab" * 20, "main", "")
    landing.__name__ = "landing"
    w.k.landing = landing
    w.round()
    return w


def c10(tree, tmp):   # ⑩ 같은 입력으로 고친 판·기준판 → ITEM-SLOW 줄 말고 로그·상태 파일 diff 0
    base = tmp / "base" / "ft2"
    shutil.copytree(tree, base, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (base / KP).read_text(encoding="utf-8")
    assert text.count(EMIT) == 1, EMIT
    (base / KP).write_text(text.replace(EMIT, "        pass"), encoding="utf-8")
    fixed, old = _scenario(tmp / "a", tree), _scenario(tmp / "b", base)
    assert _plain(fixed) == _plain(old), fixed.k.lines   # 경로 글자만 지운다(같은 입력 · 다른 임시 폴더)
    assert _jplain(fixed) == _jplain(old), _jplain(fixed)
    assert fixed.state() == old.state(), (fixed.state(), old.state())


def c12(tree, tmp):   # ⑫ 1바퀴 work A 4초 · 2바퀴 같은 work A 2초 → 1바퀴 줄 1 · 2바퀴 줄 0
    w = _rig(tmp, tree)
    secs = [4.0]

    def landing(team, work):
        w.done.append(["land", team, work])
        w.wait(secs[0])
        return ("ab" * 20, "main", "")
    landing.__name__ = "landing"
    w.k.landing = landing
    w.round()
    assert _items(w) == ["ITEM-SLOW b1 t1/w1 s=4.00 parts=landing:4.00,complete:0.00 call=0:0.00 top=-"], w.k.lines
    first = len(w.k.lines)
    secs[0] = 2.0
    w.round()
    tail = w.k.lines[first:]   # 2바퀴 = 1바퀴 셈이 남지 않는다(누적 0)
    assert tail and [x for x in tail if x.startswith("ROUND")] and not [x for x in tail if x.startswith("ITEM-SLOW")], w.k.lines


CASES = {"1": c1, "2": c2, "3": c3, "4": c4, "5": c5, "6": c6, "7": c7, "8": c8, "9": c9, "10": c10, "11": c11, "12": c12}
EMIT = ('        for text in self.item_slow():   # r2339 I3 넘는 항목만 느린 순 3개 · 넘는 항목 0 = 줄 0\n'
        '            self.log("ITEM-SLOW", text=text)')
SLOW = "        slow = [row for row in got if row[0] >= ITEM_SLOW_S]   # r2339 I3 이 초 이상만"
FINAL = "            self.stage, self.item_cur, dt = prev, outer, self.now() - at"
TOP3 = "        for sec, stage, team, work, parts in slow[:3]:"
LOOK = "        return self.item_call.get(key) or (0, 0.0, {})"
NAME = '                name = getattr(fn, "__name__", None) or "-"'
GATE = "        item, outer = ((self.at, work, stage) if work is not None and stage in ITEM_STAGES else None), self.item_cur"
RESET = "        self.item_parts, self.item_call, self.item_cur = {}, {}, None   # r2339 I3 항목 셈 = 바퀴 1개분(상주 누적 0)"
# 변이 = (파일, 옛 글, 새 글, 잡는 사례)
MUTANTS = {"M1": (KP, SLOW, "        slow = list(got)", "2"),                                     # 3초 거름 지움
           "M2": (KP, "        finally:\n" + FINAL,
                  "        except BaseException:\n            self.stage, self.item_cur = prev, outer\n            raise\n"
                  "        else:\n" + FINAL, "7"),                                                 # 셈을 finally 밖으로
           "M3": (KP, TOP3, "        for sec, stage, team, work, parts in slow:", "6"),            # 3개 상한 지움
           "M4": (KP, LOOK, "        return self.item_call.get(key) or max(self.item_call.values(), key=lambda v: v[0],"
                            " default=(0, 0.0, {}))", "9"),                                       # 항목 밖 호출도 셈
           "M5": (KP, NAME, "                name = stage", "5"),                                 # 칸 이름만
           "M6": (KP, GATE, "        item, outer = (self.at, work, stage), self.item_cur", "11"),   # 칸 거름 지움
           "M7": (KP, RESET, "        self.item_cur = None", "12")}                                # 바퀴 시작 초기화 지움


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    d = tmp_path / "c"
    d.mkdir()
    CASES[name](_tree(), d)


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(_tree(), tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "x").mkdir()
    try:   # 변이 나무 = 사례가 판정을 바꾸면(어떤 실패든) 잡은 것
        CASES[case](tree, tmp_path / "x")
    except BaseException:   # noqa: BLE001
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, case))
    (tmp_path / "o").mkdir()
    assert CASES[case](_tree(), tmp_path / "o") is None   # 원본 나무 = 같은 사례 PASS(반대 결과 대조)
