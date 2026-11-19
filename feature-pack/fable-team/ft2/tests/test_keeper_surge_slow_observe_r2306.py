"""r2306 keeper — 승계 몰림 때 느림 관측: b3r 자리 안 몫(sweep·retired) + 좌석별 단계 초 SLOW-SEAT (관측만).

카드 r2306-surge-slow-observe · 계약 K1(b3r 나눔) · K2(retire_one 단계 초 · finally · cut=1 · 바퀴당 5줄 + 외 N) · K5(판정·kill·ROUND 본문 그대로).
대역 = test_keeper_round_60s.Rig 그대로(주입 시계 · 가짜 subprocess.run · 실 tmux·git·명부 0 · sleep 0).
기준판 = FIX 를 거꾸로 되돌린 사본(① ② ②b ②c Red) · ③ = 판정 줄·kill 호출 0 기준판과 같음 · 변이 M1·M2·M5·M6 = 사본에서만 + 원본 대조.
"""
import shutil

import pytest

from test_keeper_round_60s import FT2, Rig, line

KP, KC = "adapters/pi/keeper.py", "adapters/pi/keeper_close.py"
ROSTER = "/r2306/seats-t1.json"
CUT = object()   # 그 단계에서 예산 끊김(Cut)
# 기준판 되돌림: ("swap", 고친 글자, 기준판 글자) · ("cut", 머리, 끝, 기준판 글자) = 머리부터 끝까지(끝 포함)를 기준판 글자로
FIX = {
    KP: [("swap", "    def timed(self, stage, fn, *args, part=None):\n", "    def timed(self, stage, fn, *args):\n"),
         ("swap", "fn 결과 · r2306 K1 part = b3r 자리 안 몫 키(b3r.sweep·b3r.retired).", "fn 결과."),
         ("cut", "        self.b3r_parts = {}   # r2306 K1", "초\n", ""),
         ("cut", "            if part:   # r2306 K1", "+ dt\n", ""),
         ("swap", "self.close_old.sweep, part=\"b3r.sweep\")", "self.close_old.sweep)"),
         ("swap", "self.retired, part=\"b3r.retired\")", "self.retired)"),
         ("cut", "            sweep = round(self.b3r_parts.get(\"b3r.sweep\"", "and sweep else \"\"\n", ""),
         ("swap", "round(got[1], 1)) + tail + split)", "round(got[1], 1)) + tail)")],
    KC: [("cut", "SEAT_S, SEAT_CAP = 5, 5", "»\n", ""),
         ("cut", "    def retired(self):\n        \"\"\"r2306 K2", "    def retired_rows(self):\n", "    def retired(self):\n"),
         ("cut", "    def retire_one(self, path, seat, new, alive, nano=None):\n        \"\"\"r2306 K2",
          "    def retire_seat(self, path, seat, new, alive, nano, marks):\n", "    def retire_one(self, path, seat, new, alive, nano=None):\n"),
         ("swap", "self.staged(marks, \"ready\", self.ready_seen, new, seat)", "self.ready_seen(new, seat)"),
         ("swap", "self.staged(marks, \"keep\", self.keep_gate, seat, new, alive)", "self.keep_gate(seat, new, alive)"),
         ("swap", "self.staged(marks, \"look\", lambda: self.look(team, \"-\", \"-\", seat, *self.seat_turn(seat)))",
          "self.look(team, \"-\", \"-\", seat, *self.seat_turn(seat))"),
         ("swap", "self.staged(marks, \"idle\", self.idle, team, \"-\", seat)", "self.idle(team, \"-\", seat)"),
         ("swap", "self.staged(marks, \"close\", self.call, argv, GIT_S)", "self.call(argv, GIT_S)")],
}
MUT = {"M1": {KP: [("part=\"b3r.sweep\")", "part=\"b3r.retired\")")]},   # sweep·retired 를 한 키로 더함
       "M2": {KC: [("            if dt >= SEAT_S:\n", "            if dt >= 0:\n")]},   # SLOW-SEAT 문턱 0초
       "M5": {KC: [("        try:\n            return self.retired_rows()\n        finally:\n            self.slow_seat_lines()\n",
                    "        out = self.retired_rows()\n        self.slow_seat_lines()\n        return out\n")]},   # finally → 정상 반환 뒤
       "M6": {KC: [("rows[:SEAT_CAP]", "rows"), ("        if len(rows) > SEAT_CAP:\n", "        if False:\n")]}}   # 바퀴당 상한 지움


def revert(text, rules):
    for rule in rules:
        if rule[0] == "swap":
            assert text.count(rule[1]) == 1, rule[1]
            text = text.replace(rule[1], rule[2])
            continue
        _, head, end, back = rule
        assert text.count(head) == 1, head
        i = text.index(head)
        j = text.index(end, i) + len(end)
        text = text[:i] + back + text[j:]
    return text


def test_base_is_origin_text(tmp_path):   # 기준판 사본 = r2306 앞 글자(직접 쓴 두 파일의 고침 줄 수 = FIX 수)
    src = tree(tmp_path, base=True)
    for rel in (KP, KC):
        assert "r2306" not in (src / rel).read_text(encoding="utf-8"), rel


def tree(tmp, base=False, mut=None):
    """사본 ft2 — 기준판(base) 또는 변이(mut = {파일: [(old, new)]}) · 원본 폴더 쓰기 0."""
    out = tmp / "ft2"
    shutil.copytree(FT2, out, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    for rel in (KP, KC):
        text = (out / rel).read_text(encoding="utf-8")
        text = revert(text, FIX[rel]) if base else text
        for old, new in (mut or {}).get(rel, []):
            assert text.count(old) == 1, old
            text = text.replace(old, new)
        (out / rel).write_text(text, encoding="utf-8")
    return out


def world(tmp, src=None):
    tmp.mkdir(parents=True, exist_ok=True)
    w = Rig(tmp, src)
    w.teams, w.works = [], {}
    return w


def b3_round(w, sweep, retired):
    """팀 0 바퀴 · b3r 자리 = sweep 초 + retired 초(호출 밖 파이썬 시간) → SLOW-CELL 줄."""
    w.k.close_old.sweep = lambda: w.wait(sweep)
    w.k.retired = lambda: w.wait(retired)
    w.round()
    return line(w.k, "SLOW-CELL")


def seats(w, plan):
    """명부 1개(ROSTER) · 좌석마다 단계 초 plan[seat] = {ready·keep·look·idle·close: 초 | CUT} · keep_gate 값 = plan[seat]["gate"]."""
    k, names = w.k, sorted(plan)
    del k.retired   # Rig 손잡이 → 진짜 retired
    w.verdicts = []

    def step(seat, key, value):
        sec = plan[seat].get(key, 0.0)
        if sec is CUT:
            w.wait(6)
            raise k.cut_at()
        w.wait(sec)
        return value

    k.alive_sessions = lambda: set(names)
    k.teams = lambda: []
    k.rosters = lambda: [(ROSTER, {s: {"_replaced_by": s + "-new", "role": "master"} for s in names})]
    k.closed_seats, k.seat_kind, k.outsiders = (lambda: set()), (lambda seat, row: "master"), (lambda alive, known: None)
    k.ready_seen = lambda new, seat: step(seat, "ready", True)
    k.keep_gate = lambda seat, new, alive: step(seat, "keep", plan[seat].get("gate", ""))
    k.seat_turn = lambda seat: ()
    k.look = lambda team, work, attempt, seat: step(seat, "look", "REST")
    k.idle = lambda team, work, seat: step(seat, "idle", False)   # kill 직전 가드 거짓 = 닫기 0(close 단계 안 감)
    k.verdict = lambda *a: (w.verdicts.append(a[:5]), True)[1]
    return k


def slow(k):
    return line(k, "SLOW-SEAT")


def c1(w):   # ① sweep 3 · retired 4 · b3 top → 꼬리 «parts=b3o:0,b3r:7,b3r.sweep:3,b3r.retired:4»(기준판 = «…b3r:7» 끝 = Red)
    cell = b3_round(w, 3, 4)
    assert len(cell) == 1 and cell[0].endswith(" parts=b3o:0,b3r:7,b3r.sweep:3,b3r.retired:4"), w.k.lines


def c2(w):   # ② A ready 6 · B ready 1 → SLOW-SEAT A 1줄 · B 0줄
    seats(w, {"sA": {"ready": 6}, "sB": {"ready": 1}}).retired()
    assert slow(w.k) == ["SLOW-SEAT seats-t1 sA s=6 ready=6 keep=0 look=0 idle=0 close=- cut=0"], w.k.lines


def c2b(w):   # ②b A 의 look 에서 Cut → SLOW-SEAT A cut=1 · 못 간 단계 «-» · Cut 은 그대로 올라감
    with pytest.raises(w.mod.Cut):
        seats(w, {"sA": {"look": CUT}, "sB": {}}).retired()
    assert slow(w.k) == ["SLOW-SEAT seats-t1 sA s=6 ready=0 keep=0 look=6 idle=- close=- cut=1"], w.k.lines


def c2c(w):   # ②c 5초 넘는 좌석 7개 → 큰 순 5줄 + «SLOW-SEAT 외 2»
    seats(w, {"s%d" % n: {"ready": 5 + n} for n in range(7)}).retired()
    got = slow(w.k)
    assert [x.split()[2] for x in got[:5]] == ["s6", "s5", "s4", "s3", "s2"] and got[5:] == ["SLOW-SEAT 외 2"], w.k.lines


def c3(w):   # ③ keep_gate 6초 · 보존(WORKING) → look·idle·close «-» · 판정 줄 1 · kill 호출 0
    seats(w, {"sA": {"keep": 6, "gate": "keep-last-2"}}).retired()
    assert slow(w.k) == ["SLOW-SEAT seats-t1 sA s=6 ready=0 keep=6 look=- idle=- close=- cut=0"], w.k.lines
    assert w.verdicts == [("t1", "-", "sA", "WORKING", "keep-last-2")] and not w.calls, (w.verdicts, w.calls)


CASES = {"①": c1, "②": c2, "②b": c2b, "②c": c2c, "③": c3}
RED = ("①", "②", "②b", "②c")


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](world(tmp_path))


@pytest.mark.parametrize("name", RED)
def test_base_red(name, tmp_path):
    w = world(tmp_path / "w", tree(tmp_path / "base", base=True))
    with pytest.raises(AssertionError):
        CASES[name](w)


def test_base_same_verdict(tmp_path):   # ③ K5 — 기준판도 같은 판정 줄 · kill 호출 0 · SLOW-SEAT 0
    w = world(tmp_path / "w", tree(tmp_path / "base", base=True))
    seats(w, {"sA": {"keep": 6, "gate": "keep-last-2"}}).retired()
    assert w.verdicts == [("t1", "-", "sA", "WORKING", "keep-last-2")] and not w.calls and not slow(w.k), w.k.lines


def test_round_same_as_base(tmp_path):   # ②b K5 — 바퀴 안 Cut: ROUND·ROUND-CAP 줄 = 기준판 바이트 같음 · 고친 판만 SLOW-SEAT cut=1
    got = []
    for src in (None, tree(tmp_path / "base", base=True)):
        w = world(tmp_path / ("b" if src else "f"), src)
        seats(w, {"sA": {"look": CUT}, "sB": {}})
        w.k.close_old.sweep = lambda: None
        w.round()
        got.append(w.k.lines)
    fixed, base = got
    keep = lambda lines: [x for x in lines if x.startswith(("ROUND", "SLOW-CELL")) and "parts=" not in x]   # noqa: E731
    assert keep(fixed) == keep(base) and slow_lines(fixed) == ["SLOW-SEAT seats-t1 sA s=6 ready=0 keep=0 look=6 idle=- close=- cut=1"] and not slow_lines(base), got


def slow_lines(lines):
    return [x for x in lines if x.startswith("SLOW-SEAT")]


@pytest.mark.parametrize("name, kills", [("M1", ("①",)), ("M2", ("②",)), ("M5", ("②b",)), ("M6", ("②c",))])
def test_mutant(name, kills, tmp_path):
    src = tree(tmp_path / "m", mut=MUT[name])
    for case in kills:
        with pytest.raises(AssertionError):
            CASES[case](world(tmp_path / ("w" + case), src))
        CASES[case](world(tmp_path / ("o" + case)))   # 원본 = 같은 사례 통과(반대 결과 대조)
