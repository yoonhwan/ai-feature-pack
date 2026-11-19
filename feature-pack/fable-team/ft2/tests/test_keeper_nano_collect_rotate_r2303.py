"""ft2 keeper 나노 가지 모으기 — 끊긴 팀부터 다음 바퀴를 돈다 (반례 ①·①b·①c·②·③·④·⑥ · 변이 M1~M4).

카드 r2303-keeper-nano-collect-rotate-start · 계약 A1(시작 팀 돌림 · 시작 팀 끊김 = 다음 팀) · A2(남긴 팀 없음 = 맨 앞) ·
A3(끊김 줄 team 칸 = 끊긴 팀 · 줄 글자 그대로) · A4(NANO_S 7 · 모은 것만 · 업무 cut·cursor 흔적 0 · table 있음 = 모으기 0).

대역(카드 «시험 입력»): test_keeper_round_60s.Rig 그대로 — 임시 루트 · 주입 시계 · 가짜 subprocess.run · sleep 0 · 네트워크 0.
나노 대역 = kf.nanos 1곳(keeper_fetch.nanos 꼴 · 1초 파일 판독마다 앞에 _gate — 남은 몫 < MIN_S = 그 자리에서 Cut).
팀 a·b·c = t1·t2·t3(Rig 명부 이름).
"""
import json
import shutil
import subprocess

import pytest

from test_keeper_round_60s import FT2, KP, Rig, field, line

NANO_LINE = "판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만"
BRANCH = "nano/r2303-keeper-nano-collect-rotate-start"


def _world(w, cost, teams=None):
    """팀마다 1초 판독 cost[팀]번(판독마다 _gate) · 바퀴마다 (부른 차례, 모은 팀) 을 w.trail 에 남긴다."""
    w.teams = list(teams or sorted(cost))
    w.works = {t: ["w1"] for t in w.teams}
    w.cost, w.trail = dict(cost), []

    def nanos(k, teams):
        team = teams[0]
        w.trail[-1][0].append(team)
        for _ in range(int(w.cost[team])):
            if (left := k.left()) is not None and left < w.mod.MIN_S:   # keeper_fetch._gate 와 같은 문
                raise k.cut_at()
            w.wait(1.0)
        w.trail[-1][1].append(team)
        return {"/repo/" + team: ["nano/" + team]}

    w.mod.Keeper.__init__.__globals__["kf"].nanos = nanos


def _turn(w):
    """바퀴 1개 → (부른 차례, 모은 팀, 바퀴 끝 state 키)."""
    w.trail.append(([], []))
    w.round()
    return w.trail[-1][0], w.trail[-1][1], w.state().get("nano_next")


def _journal(w):
    rows = []
    for path in sorted((w.root / ".fable-team" / "state" / "ft2-keeper").glob("*.jsonl")):
        rows += [json.loads(x) for x in path.read_text(encoding="utf-8").splitlines() if x.strip()]
    return rows


# ── A1 시작 팀 돌림 ─────────────────────────────────────────────────────────
def c_1(w):   # ① a 6 · b 2 · c 1 → 1바퀴 b 끊김 · 2바퀴 b·c · 3바퀴 a 부터 · 3바퀴 안 모두 1회 이상
    _world(w, {"t1": 6.0, "t2": 2.0, "t3": 1.0})
    turns = [_turn(w) for _ in range(3)]
    assert {t for _, got in w.trail for t in got} == {"t1", "t2", "t3"}, w.trail   # 3바퀴 안 모두 1회 이상
    assert turns[:2] == [(["t1", "t2"], ["t1"], "t2"), (["t2", "t3", "t1"], ["t2", "t3"], "t1")], turns
    assert turns[2][:2] == (["t1", "t2"], ["t1"]), turns


def c_1b(w):   # ①b 끊긴 뒤 다 돈 바퀴 → 키 0 · 그다음 바퀴 = 이름 순서 맨 앞부터
    _world(w, {"t1": 6.0, "t2": 2.0, "t3": 1.0})
    assert _turn(w)[2] == "t2", w.trail
    w.cost = dict.fromkeys(w.teams, 1.0)
    assert _turn(w) == (["t2", "t3", "t1"], ["t2", "t3", "t1"], None), (w.trail, w.state())
    assert _turn(w) == (["t1", "t2", "t3"], ["t1", "t2", "t3"], None), (w.trail, w.state())


def c_1c(w):   # ①c a 1 · b 8(혼자 몫 초과) · c 1 → 3바퀴 안 a·c 각 1회 이상 · 같은 키 2바퀴 연속 0 · 팀 1개면 그 팀
    _world(w, {"t1": 1.0, "t2": 8.0, "t3": 1.0})
    keys = [_turn(w)[2] for _ in range(3)]
    got = {t for _, g in w.trail for t in g}
    assert {"t1", "t3"} <= got and "t2" not in got, w.trail
    assert keys == ["t2", "t3", "t2"] and all(a != b for a, b in zip(keys, keys[1:])), (keys, w.trail)
    assert [r["team"] for r in _journal(w) if r["line"] == NANO_LINE] == ["t2", "t2", "t2"], _journal(w)
    w.trail[:] = []
    _world(w, {"t1": 8.0})
    assert _turn(w) == (["t1"], [], "t1") and _turn(w) == (["t1"], [], "t1"), w.trail


# ── A2 남긴 팀 없음 ─────────────────────────────────────────────────────────
def c_2(w):   # ② 남긴 팀 b 가 SKIP_TEAMS 로 빠짐 → 다음 바퀴 a 부터 · 예외 0
    _world(w, {"t1": 6.0, "t2": 2.0, "t3": 1.0})
    assert _turn(w)[2] == "t2", w.trail
    w.teams = ["t1", "t3"]
    assert _turn(w) == (["t1", "t3"], ["t1", "t3"], None), w.trail


# ── A3 끊김 줄 ───────────────────────────────────────────────────────────────
def c_3(w):   # ③ 끊김 줄 team 칸 = 끊긴 팀 · line 글자 = 기준판과 같음
    _world(w, {"t1": 6.0, "t2": 2.0, "t3": 1.0})
    _turn(w)
    assert line(w.k, "판정 불가") == [NANO_LINE], w.k.lines
    rows = [r for r in _journal(w) if r["line"] == NANO_LINE]
    assert [(r["kind"], r["team"]) for r in rows] == [("판정 불가", "t2")], rows


# ── A4 불변 ──────────────────────────────────────────────────────────────────
def c_4(w):   # ④ 모은 값 그대로 · 업무 cut·cursor 흔적 0 · NANO_S 7 · table 있음 = 모으기 0
    assert w.mod.NANO_S == 7
    _world(w, {"t1": 6.0, "t2": 2.0, "t3": 1.0})
    _turn(w)
    assert w.k.nano == {"/repo/t1": ["nano/t1"]}, w.k.nano
    assert field(w.k, "cut") == "-" and "cursor" not in w.state(), (w.k.lines, w.state())
    w.mod.Keeper.__init__.__globals__["kf"].targets = lambda k: {str(w.root): "origin"}
    assert _turn(w)[:2] == ([], []) and w.k.nano == {}, (w.trail, w.k.nano)


# ── ⑥ 바뀐 파일 ──────────────────────────────────────────────────────────────
def c_6(w):   # ⑥ 이 가지의 diff = keeper.py · 이 시험 (가지 밖에서는 건너뜀 · git 읽기만)
    def git(*args):
        return subprocess.run(["git", *args], cwd=FT2, capture_output=True, text=True, timeout=7).stdout.strip()
    if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
        pytest.skip("가지 %s 밖" % BRANCH)
    base = git("merge-base", "HEAD", "origin/main")
    names = set(git("diff", "--name-only", base).splitlines()) | set(git("ls-files", "--others", "--exclude-standard", ".").splitlines())
    want = {"adapters/pi/keeper.py", "tests/test_keeper_nano_collect_rotate_r2303.py"}
    assert {n.split("/ft2/", 1)[-1] for n in names} <= want, names


CASES = {"1": c_1, "1b": c_1b, "1c": c_1c, "2": c_2, "3": c_3, "4": c_4, "6": c_6}

TURN = "        order = order[first:] + order[:first]"
POP = '            self.state.pop("nano_next", None)'
WHO = '        self.who = team if nano_cut else ""'
NEXT = '            self.state["nano_next"] = order[1 % len(order)] if team == order[0] else team'
# 변이 = (파일, [(옛 글, 새 글)], 잡히는 사례) · 둘째 사례부터 = 원본 나무로 같은 사례(대조)
MUTANTS = {
    "M1": (KP, [(TURN, "        order = order")], ("1", "1")),
    "M2": (KP, [(POP, "            pass")], ("1b", "1b")),
    "M3": (KP, [(WHO, '        self.who = ""')], ("3", "3")),
    "M4": (KP, [(NEXT, '            self.state["nano_next"] = team')], ("1c", "1c")),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Rig(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, edits, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    for old, new in edits:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / rel).write_text(text, encoding="utf-8")
    (tmp_path / "w1").mkdir()
    try:   # 변이 나무 = 판정이 달라지면(AssertionError 등) 잡힌 것
        CASES[cases[0]](Rig(tmp_path / "w1", tree))
    except BaseException:   # noqa: BLE001 — 어떤 실패든 변이를 잡은 것
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, cases[0]))
    for n, case in enumerate(cases[1:]):   # 원본 나무 = 같은 사례 PASS(반대 결과 대조)
        assert CASES[case](Rig(tmp_path / ("c%d%s" % (n, case)), None)) is None
