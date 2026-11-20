"""r2369 ft2 keeper — 쉼 work 착지 판정(parked_landing)이 바퀴 커서 앞 자리면 그 바퀴에 돌지 않고(K1), 돌 때 끊기면 끊긴 자리가 그 work 의 b1 로 남는다(K2). 다른 길은 그대로(K3).

카드 r2369-keeper-b1-cursor-skip-parked-landing · 계약 K1(커서 거름 = before 게이트 · 몫 0) ·
K2(끊김 자리 = 그 work 의 b1 · 앞 work 칸 글자 물림 0) · K3(launch-failed 쉼 · done 닫기 길 · 반환 쉼 그대로).

대역 = `test_keeper_round_60s.Rig` 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run · 가짜 journal 줄(dispatch·쉼·반환) · 가짜 카드 손 ·
sleep 0 · 네트워크 0 · 실 git·실 tmux·실 runtime 0. 바퀴 사이는 새 Keeper(state.json 만 이어진다 = 실제 `keeper --once` 꼴).

기준판(base) Red = ① · ④ · ⑥ — 그 셋만 base 에서 실패하고 ② ③ ⑤ ⑦ ⑧ ⑨ 는 base 에서도 통과한다(게이트가 넓어지지 않았다는 대조).
변이 M1~M8 = 각자 맡은 사례를 깨뜨린다(① M1 · ② M2 · ③ M3 · ④ M4 · ⑤ M5 · ⑥ M6 · ⑧ M7 · ⑨ M8) · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조).
"""
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig, line

GOOD, TEAM = "ab" * 20, "t1"


def rig(tmp, works, parked=(), returned=(), done=(), reason=None, tree=None):
    """팀·work·journal 줄(dispatch · 쉼 · 반환) · 투영 done · 대역 손 — 시간·판정은 원본 keeper 가 돈다."""
    w = Rig(tmp, tree)

    def hands():
        w.teams, w.works = sorted(works), {team: list(names) for team, names in works.items()}
        rows = {}
        for team, names in w.works.items():
            rows[team] = [{"kind": "dispatch", "work": name, "attempt": "a1", "holder": "h#0"} for name in names]
            rows[team] += [{"kind": "parked", "work": name, "attempt": "a1", "reason": reason or "idle-done"} for name in names if name in parked]
            rows[team] += [{"kind": "returned", "work": name, "attempt": "a1"} for name in names if name in returned]
        w.k.teams, w.k.rows_of = (lambda: list(w.teams)), (lambda team: list(rows.get(team) or []))
        w.k.project = lambda root, team: {"result": w.mod.OK, "works": {name: {"done": name in done} for name in w.works.get(team) or []}}
        w.k.stage_card = lambda *a, **kw: w.done.append(["stage", a[0], a[1]])   # r2026 카드 손 = 부름만 센다
        w.k.landing = lambda team, work: (w.done.append(["land", team, work]), (GOOD, "main", ""))[1]

    hands()
    w.hands = hands
    return w


def presets(w, **cells):
    """바퀴 cursor · 팀 자리(state) 프리셋 → 새 Keeper(state.json 이어짐 = 실제 `--once` 꼴 · 대역 손 다시)."""
    w.room(**cells)
    w.boot()
    w.hands()
    return w


def again(w):
    """다음 바퀴 = 새 Keeper(state 만 이어진다)."""
    w.boot()
    w.hands()
    return len(w.done)


def burn(w, names, n=8, seconds=7.0):
    """그 (팀 · work) 의 landing 이 업무 예산(45초)을 다 쓴다 — 다음 호출이 R2 문(남은 몫 < 7초)에서 끊긴다 · 다른 자리 = 0초."""
    def landing(team, work):
        w.done.append(["land", team, work])
        if (team, work) in names:
            w.reads(("git", "show"), seconds, n)
        return (GOOD, "main", "")
    w.k.landing = landing
    return w


def lands(w, start=0):
    return [one[2] for one in w.done[start:] if one[0] == "land"]


def completes(w, start=0):
    return [one[2] for one in w.done[start:] if one[0] == "complete"]


def stage_card(w, start=0):
    return [tuple(one[1:]) for one in w.done[start:] if one[0] == "stage"]


# ── K1 커서 거름 ──────────────────────────────────────────────────────────────
def c1(tmp, tree=None):   # ① 커서 뒤(뒤 work)의 쉼 카드 → 이 바퀴 landing 0 · complete 0 · 줄 0 (기준판 Red)
    w = rig(tmp, {TEAM: ["w1", "w2"]}, parked=("w1",), tree=tree)
    presets(w, cursor={"team": TEAM, "work": "w2", "stage": "b1", "cuts": 0})
    w.round()
    assert lands(w) == ["w2"] and completes(w) == ["w2"], w.done
    assert line(w.k, "ROUND-CAP") == [] and line(w.k, "판정 불가") == [], w.k.lines


def c2(tmp, tree=None):   # ② 커서가 그 쉼 카드 자리 — 거르면 안 된다(landing 1 · complete 1 · cursor 지움)
    w = rig(tmp, {TEAM: ["w1"]}, parked=("w1",), tree=tree)
    presets(w, cursor={"team": TEAM, "work": "w1", "stage": "b1", "cuts": 0})
    w.round()
    assert lands(w) == ["w1"] and completes(w) == ["w1"] and "cursor" not in w.state(), (w.done, w.state())


def c3(tmp, tree=None):   # ③ 커서가 다른 팀(t2) — 앞 팀은 통째로 0 · 그 팀 쉼 카드는 커서 자리라 이 바퀴 돈다(게이트 넓힘 0)
    w = rig(tmp, {"t1": ["w1"], "t2": ["w1"]}, parked=("w1",), tree=tree)
    presets(w, cursor={"team": "t2", "work": "w1", "stage": "b1", "cuts": 0})
    w.round()
    assert [(one[1], one[2]) for one in w.done if one[0] == "land"] == [("t2", "w1")] and completes(w) == ["w1"], w.done


# ── K2 끊김 자리 ─────────────────────────────────────────────────────────────
def _carry(tmp, tree=None):
    """앞 팀 t1 이 채우기(b2f)까지 가서 cursor 칸 글자가 «b2f» 인 채 둘째 팀 t2 첫 work(쉼 카드)로 넘어가는 세계."""
    return burn(rig(tmp, {"t1": ["w1"], "t2": ["w1", "w2"]}, parked=("w1",), tree=tree), {("t2", "w1")})


def c4(tmp, tree=None):   # ④ 둘째 팀 쉼 카드가 예산을 먹고 끊긴다 → 끊김 자리 = 그 work 의 b1 (기준판 Red = 앞 팀 칸 글자 b2f)
    w = _carry(tmp, tree)
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t2 w1 b1 — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t2", "work": "w1", "stage": "b1", "cuts": 1}, w.state()


def c5(tmp, tree=None):   # ⑤ 첫 바퀴 · 커서 자리 쉼 카드가 끊긴다 → 둘째 바퀴 그 자리(landing 1 · complete 1 · cursor 지움)
    w = rig(tmp, {TEAM: ["w1"]}, parked=("w1",), tree=tree)
    presets(w, cursor={"team": TEAM, "work": "w1", "stage": "b1", "cuts": 0})
    burn(w, {(TEAM, "w1")})
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w1 b1 — 다음 바퀴 여기부터"], w.k.lines
    start = again(w)   # 둘째 바퀴 · 이번엔 안 끊긴다
    w.round()
    assert lands(w, start) == ["w1"] and completes(w, start) == ["w1"] and "cursor" not in w.state(), (w.done, w.state())


def c6(tmp, tree=None):   # ⑥ ④ 뒤 둘째 바퀴 = 그 쉼 카드부터 다시(기준판 Red = b2f 커서가 그 자리를 건너뛴다 · landing 0)
    w = _carry(tmp, tree)
    w.round()
    assert w.state()["cursor"] == {"team": "t2", "work": "w1", "stage": "b1", "cuts": 1}, w.state()   # 기준판 = 앞 팀 칸 글자 b2f
    start = again(w)
    w.round()
    assert lands(w, start)[:1] == ["w1"] and "w1" in completes(w, start) and "cursor" not in w.state(), (w.done, w.state())


# ── K3 다른 길 그대로 ────────────────────────────────────────────────────────
def c7(tmp, tree=None):   # ⑦ launch-failed 쉼 = parked_landing 0 · r2058 L2 길 그대로(landing 1 · complete 1)
    w = rig(tmp, {TEAM: ["w1"]}, parked=("w1",), tree=tree)
    w.k.rows_of = lambda team: [{"kind": "dispatch", "work": "w1", "attempt": "a1", "holder": "h#0"},
                                {"kind": "parked", "work": "w1", "attempt": "a1", "reason": failure(w)}]
    w.round()
    assert lands(w) == ["w1"] and completes(w) == ["w1"] and line(w.k, "판정 불가") == [], (w.done, w.k.lines)


def failure(w):
    return w.mod.Keeper.run_once.__globals__["settling"].LAUNCH_FAILED


def c8(tmp, tree=None):   # ⑧ 이미 처리한(handled) 쉼 카드 ∧ 투영 done = 닫기 길(카드 손 1) — 커서 앞이어도 이 길은 그대로(landing 0)
    w = rig(tmp, {TEAM: ["w1", "w2"]}, parked=("w1",), done=("w1",), tree=tree)
    presets(w, cursor={"team": TEAM, "work": "w2", "stage": "b1", "cuts": 0}, handled={"t1|w1@a1": "2026-01-01T00:00:00"})
    w.round()
    assert stage_card(w) == [(TEAM, "w1")] and "w1" not in lands(w), w.done


def c9(tmp, tree=None):   # ⑨ 반환 쉼 = parked_landing 0 · landing 0(r1990 길 그대로)
    w = rig(tmp, {TEAM: ["w1"]}, returned=("w1",), tree=tree)
    w.round()
    assert lands(w) == [] and completes(w) == [] and line(w.k, "ROUND-CAP") == [], (w.done, w.k.lines)


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9}
GATE = '        if self.before(team, work, "b1"):   # r2369 K1 커서 앞 쉼 카드 = 이 바퀴 몫 0'
STAGE = '        self.cursor_stage = "b1"   # r2369 K2 끊긴 자리 = 그 work 의 b1'
LANDED = '            got = self.timed("b1", self.landing, team, work, work=work)'
MUTANTS = {"M1": ([(GATE, '        if False:   # M1 게이트 없음')], "①"),
           "M2": ([(GATE, '        if True:   # M2 전부 거름')], "②"),
           "M3": ([(GATE, '        if self.before(team, work, "b1") or self.key(team, work, "b1") == self.curs:   # M3 커서 자리도 거름')], "③"),
           "M4": ([(STAGE + "\n", "")], "④"),
           "M5": ([(STAGE, '        self.cursor_stage = "b2c"   # M5 앞 칸 글자')], "⑤"),
           "M6": ([(STAGE + "\n", ""), (LANDED, LANDED + "\n" + STAGE.replace("        ", "            ", 1))], "⑥"),   # K2 를 landing 뒤로 = 끊김 먼저
           "M7": ([("            if work in gone:\n", "            if work in gone:\n                if self.before(team, work, \"b1\"):\n                    continue\n")], "⑧"),
           "M8": ([("                elif work in open_:   # r2258 O1", "                elif (work, attempt) in back:   # M8 반환까지")], "⑨")}


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
