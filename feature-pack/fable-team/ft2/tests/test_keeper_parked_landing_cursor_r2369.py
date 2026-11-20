"""r2369 ft2 keeper — 쉼 work 착지 판정(parked_landing)이 바퀴 커서 앞 자리면 그 바퀴에 돌지 않고(K1), 돌다 끊기면 끊긴 자리가 그 work 의 b1 로 남는다(K2). 다른 길은 그대로(K3).

카드 r2369-keeper-b1-cursor-skip-parked-landing · 반례 집합(동결) ①~⑨ · 변이 M1~M8 · 계약↔시험 대응표 그대로 1:1.
계약 K1 커서 거름(①·②·③ / M1·M2·M3) · K2 끊김 자리(④·⑤·⑥ / M4·M5·M6) · K3 다른 길 그대로(⑦·⑧·⑨ / M7·M8).
카드 밖 덧붙임 ⑩~⑬ = 다른 팀 커서 · launch-failed 쉼 · 반환 쉼 · handled ∧ done 닫기 길(게이트가 넓어지지 않았다는 대조) — 대응 변이 0.

대역(카드 «시험 입력»): 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run · 가짜 journal 줄(dispatch · parked idle-done · returned) · 가짜 landing(부름 기록 · 반환·Ungraded 주입) ·
state cursor·team_cursor 주입 · sleep 0 · 네트워크 0 · 실 git·실 tmux·실 원장 0. 바퀴 사이는 새 Keeper(state.json 만 이어짐 = 실제 `keeper --once` 꼴).
"""
import shutil
from pathlib import Path

import pytest

from test_keeper_round_60s import FT2, KP, Rig, line

GOOD, TEAM = "ab" * 20, "cfo"
JOBS = ("W1", "W2", "W3", "W4")   # 쉼 = W1 · W2 · W4 · 보통 work = W3 (카드 동결 세계)


def rig(tmp, works=None, tree=None, parked=("W1", "W2", "W4"), returned=(), done=(), reason=None,
        cursor=None, team_cursor=None, complete=None, tip=False):
    """팀·work·journal 줄 · 투영 done · 대역 손 — 시간·판정은 원본 keeper 가 돈다."""
    w = Rig(tmp, tree)

    def hands():
        w.teams, w.works = sorted(works or {TEAM: JOBS}), {team: list(names) for team, names in (works or {TEAM: JOBS}).items()}
        rows = {}
        for team, names in w.works.items():
            rows[team] = [{"kind": "dispatch", "work": name, "attempt": "a1", "holder": "h#0"} for name in names]
            rows[team] += [{"kind": "parked", "work": name, "attempt": "a1", "reason": reason or "idle-done"} for name in names if name in parked]
            rows[team] += [{"kind": "returned", "work": name, "attempt": "a1"} for name in names if name in returned]
        w.k.teams, w.k.rows_of = (lambda: list(w.teams)), (lambda team: list(rows.get(team) or []))
        w.k.project = lambda root, team: {"result": w.mod.OK, "works": {name: {"done": name in done} for name in w.works.get(team) or []}}
        w.k.stage_card = lambda *a, **kw: w.done.append(["stage", a[0], a[1]])   # r2026 카드 손 = 부름만 센다
        w.k.landing = lambda team, work: (w.done.append(["land", team, work]), (GOOD, "main", ""))[1]
        w.k.complete = complete or (lambda team, work, attempt, landed: (w.done.append(["complete", team, work]), True)[1])

    hands()
    w.hands = hands
    if tip:   # tips() 3개 tip 이 빈 목록이 아니게(rev-parse 가 token 을 준다) — O2 memo 갈래를 재려면 필요하다
        plain = w.plan
        w.plan = lambda argv, timeout: (0.0, 0, "ab" * 20) if "rev-parse" in argv else plain(argv, timeout)
    if cursor or team_cursor:
        cells = {}
        if cursor:
            cells["cursor"] = cursor
        if team_cursor:
            cells["team_cursor"] = team_cursor
        w.room(**cells)
        w.boot()
        hands()
    return w


def again(w):
    """다음 바퀴 = 새 Keeper(state 만 이어진다 · 대역 손 다시). 반환 = 지금까지 done 길이."""
    w.boot()
    w.hands()
    return len(w.done)


def burn(w, names, n=8, seconds=7.0):
    """그 work 의 landing 이 업무 예산(45초)을 다 쓴다 — 다음 호출이 R2 문(남은 몫 < 7초)에서 끊긴다 · 다른 work = 0초."""
    def landing(team, work):
        w.done.append(["land", team, work])
        if work in names:
            w.reads(("git", "show"), seconds, n)
        return (GOOD, "main", "")
    w.k.landing = landing
    return w


def lands(w, start=0):
    return [one[2] for one in w.done[start:] if one[0] == "land"]


def completes(w, start=0):
    return [one[2] for one in w.done[start:] if one[0] == "complete"]


def stage_cards(w, start=0):
    return [tuple(one[1:]) for one in w.done[start:] if one[0] == "stage"]


def cells_at_cut(tmp, tree, complete):
    """④ 바퀴의 셈 = (items, cell_total, 돈 자리) — 끊긴 바퀴 그대로."""
    w = rig(tmp, tree=tree, complete=complete)
    burn(w, ("W4",))
    w.round()
    return (w.k.items, w.k.total, sorted(w.k.seen))


def strip_base(tmp, tree=None):
    """r2369 3줄을 지운 사본 = 기준판(HEAD 코드). ⑤ 가 «기준판과 같은 수» 를 견주는 자리(M5 면 한 줄이 남아 달라진다)."""
    out = (tmp / "base" / "ft2")
    shutil.copytree(Path(tree) if tree else FT2, out, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (out / KP).read_text(encoding="utf-8")
    head, sep, tail = text.partition("        memo, key, self.at_work")
    at = head.index("    def parked_landing")
    end = head.index("\n", head.index('"""', head.index('"""', at) + 3)) + 1   # docstring 줄 끝
    (out / KP).write_text(head[:end] + sep + tail, encoding="utf-8")   # 머리 = HEAD 그대로(변이도 같이 지운다)
    return out


# ── K1 커서 거름 ──────────────────────────────────────────────────────────────
def c1(tmp, tree=None):   # ① 커서 = (cfo · W3 · b1) · 쉼 W1 · W2 가 W3 앞 → 0 · W3 뒤 쉼 W4 = 1 (기준판 Red)
    w = rig(tmp, tree=tree, cursor={"team": TEAM, "work": "W3", "stage": "b1", "cuts": 0})
    w.round()
    assert "W1" not in lands(w) and "W2" not in lands(w), w.done
    assert lands(w).count("W4") == 1 and lands(w).count("W3") == 1, w.done
    assert line(w.k, "ROUND-CAP") == [], w.k.lines


def c2(tmp, tree=None):   # ② team_cursor 만(바퀴 커서 없음) · 쉼 W1 이 그 팀 자리 앞 → W1 = 0
    w = rig(tmp, tree=tree, team_cursor={TEAM: {"work": "W3", "stage": "b1"}})
    w.round()
    assert "W1" not in lands(w) and lands(w).count("W4") == 1, w.done


def c3(tmp, tree=None):   # ③ 커서 없음 → 쉼 W1 · W2 · W4 모두 1씩(지금 그대로)
    w = rig(tmp, tree=tree)
    w.round()
    assert [lands(w).count(one) for one in ("W1", "W2", "W4")] == [1, 1, 1], w.done


# ── K2 끊김 자리 ─────────────────────────────────────────────────────────────
def c4(tmp, tree=None):   # ④ W4 landing 안 Cut · 앞 work 칸 = stall → ROUND-CAP «cfo W4 b1» · cursor = (cfo · W4 · b1) (기준판 Red)
    w = rig(tmp, tree=tree, complete=lambda team, work, attempt, landed: work not in ("W3",))   # W3 complete 0 = stall 자리
    burn(w, ("W4",))
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP cfo W4 b1 — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": TEAM, "work": "W4", "stage": "b1", "cuts": 1}, w.state()


def c5(tmp, tree=None):   # ⑤ ④ 바퀴의 items · cell_total · seen = 기준판과 같은 수(쉼 work 자리 셈 0)
    def keep(team, work, attempt, landed):
        return work != "W3"
    got = cells_at_cut(tmp / "c", tree, keep)
    want = cells_at_cut(tmp / "b", strip_base(tmp, tree), keep)
    assert got == want, (got, want)   # (items, cell_total, 돈 자리)


def c6(tmp, tree=None):   # ⑥ 쉼 W4 의 tips() 안 Cut(첫 git) → ROUND-CAP «cfo W4 b1» · cursor = (cfo · W4 · b1) (기준판 Red)
    w = rig(tmp, tree=tree, cursor={"team": TEAM, "work": "W4", "stage": "b1", "cuts": 0})
    w.k.succeed.sweep = lambda *a: w.wait(44.5)   # work 고리 앞에서 몫을 다 쓴다(남은 0.5초 < MIN_S 1초) → 첫 git(tips) 이 R2 문에서 끊긴다
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP cfo W4 b1 — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": TEAM, "work": "W4", "stage": "b1", "cuts": 1}, w.state()


# ── K3 다른 길 그대로 ────────────────────────────────────────────────────────
def c7(tmp, tree=None):   # ⑦ 커서 = 쉼 W1 자체 → landing 1 · 2바퀴 연속 끊기면 R5 «예산 2회 넘음 — 건너뜀» · 다음 자리
    w = rig(tmp, tree=tree, cursor={"team": TEAM, "work": "W1", "stage": "b1", "cuts": 0})
    burn(w, ("W1",))
    w.round()
    start = again(w)
    burn(w, ("W1",))
    w.round()
    assert lands(w).count("W1") == 2 and lands(w, start).count("W1") == 1, w.done
    assert [x for x in line(w.k, "판정 불가") if "예산 2회" in x] == ["판정 불가 cfo W1 b1 예산 2회 넘음 — 건너뜀"], w.k.lines
    assert w.state()["cursor"] == {"team": TEAM, "work": "W1", "stage": "b2c", "cuts": 0}, w.state()   # R5 다음 자리


def c8(tmp, tree=None):   # ⑧ 커서 뒤 쉼 W4 — O2 memo «미도달» · 착지 주입 complete 1 · Ungraded 주입 None
    miss = lambda team, work: (w.done.append(["land", team, work]), (GOOD, "main", "미도달" if work == "W4" else ""))[1]   # noqa: E731
    w = rig(tmp, tree=tree, tip=True, cursor={"team": TEAM, "work": "W4", "stage": "b1", "cuts": 0})
    w.k.landing = miss
    w.round()
    assert lands(w).count("W4") == 1 and completes(w).count("W4") == 0, w.done
    start = again(w)
    w.k.landing = miss
    w.round()   # 세 tip 같고 memo «미도달» = 다시 안 봄
    assert lands(w, start).count("W4") == 0 and line(w.k, "ROUND-CAP") == [], (w.done[start:], w.k.lines)
    w2 = rig(tmp / "b", tree=tree, tip=True, cursor={"team": TEAM, "work": "W4", "stage": "b1", "cuts": 0})   # 착지 주입
    w2.round()
    assert completes(w2).count("W4") == 1, w2.done
    w3 = rig(tmp / "c", tree=tree, tip=True, cursor={"team": TEAM, "work": "W4", "stage": "b1", "cuts": 0})   # Ungraded 주입
    w3.k.landing = lambda team, work: (w3.done.append(["land", team, work]), w3.k.ungraded())[1]
    w3.round()
    assert lands(w3).count("W4") == 1 and completes(w3).count("W4") == 0 and line(w3.k, "ROUND-CAP") == [], (w3.done, w3.k.lines)


def c9(tmp, tree=None):   # ⑨ 보통 work 가 커서 앞 → one_work «none» · landing 0 · 커서 뒤 보통 work = 1 (지금 그대로)
    w = rig(tmp, works={TEAM: ["W1", "W2"]}, parked=(), tree=tree, cursor={"team": TEAM, "work": "W2", "stage": "b1", "cuts": 0})
    w.round()
    assert "W1" not in lands(w) and lands(w).count("W2") == 1, w.done


# ── 카드 밖 덧붙임(게이트 넓힘 0 대조 · 대응 변이 0) ─────────────────────────
def c10(tmp, tree=None):   # ⑩ 커서가 다른 팀 — 앞 팀 통째로 0 · 그 팀 쉼 카드는 커서 자리라 이 바퀴 돈다
    w = rig(tmp, works={"a1": ["W1"], TEAM: ["W1"]}, parked=("W1",), tree=tree, cursor={"team": TEAM, "work": "W1", "stage": "b1", "cuts": 0})
    w.round()
    assert [(one[1], one[2]) for one in w.done if one[0] == "land"] == [(TEAM, "W1")], w.done


def c11(tmp, tree=None):   # ⑪ launch-failed 쉼 = parked_landing 0 · r2058 L2 길 그대로(landing 1 · complete 1)
    w = rig(tmp, works={TEAM: ["W1"]}, parked=("W1",), tree=tree)
    w.k.rows_of = lambda team: [{"kind": "dispatch", "work": "W1", "attempt": "a1", "holder": "h#0"},
                                {"kind": "parked", "work": "W1", "attempt": "a1", "reason": w.mod.Keeper.run_once.__globals__["settling"].LAUNCH_FAILED}]
    w.round()
    assert lands(w) == ["W1"] and completes(w) == ["W1"], w.done


def c12(tmp, tree=None):   # ⑫ 반환 쉼 = parked_landing 0 · landing 0(r1990 길 그대로)
    w = rig(tmp, works={TEAM: ["W1"]}, parked=(), returned=("W1",), tree=tree)
    w.round()
    assert lands(w) == [] and line(w.k, "ROUND-CAP") == [], (w.done, w.k.lines)


def c13(tmp, tree=None):   # ⑬ handled ∧ done 쉼 카드 = 닫기 길(카드 손 1) — 커서 앞이어도 이 길은 그대로(landing 0)
    w = rig(tmp, works={TEAM: ["W1", "W2"]}, parked=("W1",), done=("W1",), tree=tree, cursor={"team": TEAM, "work": "W2", "stage": "b1", "cuts": 0})
    w.room(handled={"cfo|W1@a1": "2026-01-01T00:00:00"})
    w.boot()
    w.hands()
    w.round()
    assert stage_cards(w) == [(TEAM, "W1")] and "W1" not in lands(w), w.done


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9,
         "⑩": c10, "⑪": c11, "⑫": c12, "⑬": c13}
GATE = '        if self.before(team, work, "b1"):   # r2369 K1 커서 앞 쉼 카드 = 이 바퀴 몫 0'
STAGE = '        self.cursor_stage = "b1"   # r2369 K2 끊긴 자리 = 그 work 의 b1'
TIPS = "            tips = self.tips()"
CALLED = "            return bool(got[0] and not got[2]) and self.timed(\"b1\", self.complete, team, work, attempt, got, work=work)"
MUTANTS = {"M1": ([(GATE, "        if False:   # M1 K1 머리 줄 지움")], "①"),
           "M2": ([(GATE, '        if self.curs is not None and self.key(team, work, "b1") < self.curs:   # M2 바퀴 커서만')], "②"),
           "M3": ([(GATE, "        if self.curs is not None:   # M3 커서 있으면 모두 0")], "①"),
           "M4": ([(STAGE + "\n", "")], "④"),
           "M5": ([(STAGE, '        self.at_pos("b1")   # M5 K2 를 at_pos 로')], "⑤"),
           "M6": ([(STAGE + "\n", ""), (TIPS, TIPS + "\n" + STAGE.replace("        ", "            ", 1))], "⑥"),
           "M7": ([(GATE, '        if self.before(team, work, "b1") or self.key(team, work, "b1") == self.curs:   # M7 커서 자리도 거름')], "⑦"),
           "M8": ([(CALLED, "            return bool(got[0] and not got[2])   # M8 착지 complete 부름 지움")], "⑧")}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    assert CASES[name](tmp_path) is None


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    pairs, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / KP).write_text(text, encoding="utf-8")
    for sub in ("m1", "o1"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):   # 사본(변이) = 그 사례가 잡는다
        CASES[case](tmp_path / "m1", tree)
    assert CASES[case](tmp_path / "o1") is None   # 원본으로 같은 사례 1회 = PASS(대조)
