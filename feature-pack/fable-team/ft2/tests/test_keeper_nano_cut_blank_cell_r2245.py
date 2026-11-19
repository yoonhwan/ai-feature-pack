"""ft2 keeper ROUND cut 칸 — 나노 가지 모으기 끊김은 업무 구획 끊김이 아니다 (반례 53가~바 · 변이 M133~M136).

카드 ft2-keeper-nano-cut-blank-cell · 계약 N1(나노 Cut = cut 칸·cursor 흔적 0) · N2(«판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만» 1줄 ·
ROUND nano= 칸 · 모은 것만 쓰는 동작 그대로) · N3(뒤 업무 구획의 실제 끊김이 덮는다) · N4(끝까지 돌면 cursor 를 지운다) ·
N5(손 0 — cut_at 자리 셈 · mark_cut · report 구획 · fetch 구간 · keeper_fetch.py · NANO_S).

대역(카드 «시험 입력»): test_keeper_round_60s.Rig 그대로 — 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run(요청 상한과 자기 소요 중
작은 값만큼 시계를 올린다) · 가짜 journal·tmux·mbox(인자만 기록) · sleep 0 · 네트워크 0 · 실 runtime·실 git·실 tmux 0. 새 대역 0.
나노 가지 모으기 대역 = kf.nanos 1곳만(첫 팀 판독 뒤 주입 시계가 7초를 채운다).
"""
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig, field, line

NANO_LINE = "판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만"


def _nanos(w, reads, teams_at=1):
    """kf.nanos 대역 — 첫 팀 호출에서만 `reads` 를 돈다(나노 몫 7초 안 · 넘으면 그 자리에서 Cut)."""
    seen = []

    def nanos(k, teams):
        seen.append(teams)
        if len(seen) == teams_at:
            reads()
        return {}

    w.mod.Keeper.__init__.__globals__["kf"].nanos = nanos


def _nano_cut(w):
    """나노 모으기 첫 판독 7초(몫을 다 씀) → 둘째 팀 판독이 그 자리에서 끊긴다(팀 2개 · Cut 은 나노 안에서 난다)."""
    _nanos(w, lambda: w.reads(("git", "show"), 7.0, 2))


def _fill(w, fn):
    """closing.keeper_next.fill 대역 — 바꾼 손은 이 사례가 끝날 때 되돌린다(모듈 속성이라 다른 시험으로 새지 않게)."""
    node = w.mod.Keeper.__init__.__globals__["closing"].keeper_next
    orig, node.fill = node.fill, fn
    return orig


# ── 53 N1 · N2 · N3 · N4 ─────────────────────────────────────────────────────
def c_ga(w):   # 53가 나노 모으기 중 몫이 다함(팀 2개 · 첫 팀 판독 뒤 +7초) · 업무 구획은 끝까지 돎
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    _nano_cut(w)
    w.round()
    assert line(w.k, "판정 불가") == [NANO_LINE], w.k.lines   # N2 그대로 1줄
    assert field(w.k, "nano") == "7", w.k.lines   # N2 — ROUND nano= 칸 그대로
    assert field(w.k, "cut") == "-", w.k.lines   # N1 — 나노 끊김은 빈 자리 이름(`-:-:-`)을 남기지 않는다
    assert line(w.k, "ROUND-CAP") == [], w.k.lines
    assert "cursor" not in w.state(), w.state()
    assert [d for d in w.done if d[0] == "land"] == [["land", "t1", "w1"], ["land", "t2", "w2"]], w.done   # 끝까지 돎


def c_na(w):   # 53나 53가 를 3바퀴 연속 → 세 줄 모두 cut=-
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    got = []
    for _ in range(3):
        _nano_cut(w)   # 바퀴마다 나노 모으기가 다시 7초를 다 쓴다
        w.k.lines[:] = []
        w.round()
        got.append(field(w.k, "cut"))
        assert line(w.k, "판정 불가") == [NANO_LINE] and line(w.k, "ROUND-CAP") == [], w.k.lines
        assert "cursor" not in w.state(), w.state()
    assert got == ["-", "-", "-"], got


def c_da(w):   # 53다 53가 + 업무 구획에서 둘째 팀의 b2f 가 예산 끊김 → 뒤 끊김이 덮는다
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    _nano_cut(w)
    w.k.close = lambda team, *a: (w.done.append(["close", team]),
                                 w.reads(("tmux", "has-session"), 7.0, 4) if team == "t1" else None)   # 첫 팀 닫기 자리에서 28초

    def fill(k, team):
        w.done.append(["fill", team])
        if team == "t2":   # 둘째 팀 빈 칸 = 예산 끝을 넘긴 뒤 첫 호출
            w.wait(10)
            k.call(["tmux", "has-session"])
    orig = _fill(w, fill)
    try:
        w.round()
    finally:
        _fill(w, orig)
    assert field(w.k, "cut") == "t2:-:b2f", w.k.lines   # N3 — 실제 끊긴 자리 그대로
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t2 - b2f — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t2", "work": "-", "stage": "b2f", "cuts": 1}, w.state()


def c_ra(w):   # 53라 앞 바퀴 cursor = (b, w1, b1) · 이번 바퀴 나노 끊김 · 업무 구획은 b 부터 끝까지 돎
    w.teams, w.works = ["a", "b"], {"a": ["w1"], "b": ["w1"]}
    w.room(cursor={"team": "b", "work": "w1", "stage": "b1", "cuts": 1})
    _nano_cut(w)
    w.round()
    assert field(w.k, "cut") == "-", w.k.lines   # N1
    assert "cursor" not in w.state(), w.state()   # N4 — :522 가 지운다
    assert [d for d in w.done if d[0] == "land"] == [["land", "b", "w1"]], w.done   # 앞 팀 = 안 돈다


def c_ma(w):   # 53마 나노가 끊김 없이 7초를 채움(nano_s >= NANO_S) = 지금 그대로
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    _nanos(w, lambda: w.reads(("git", "show"), 7.0, 1))   # 첫 팀 판독에서 7초를 다 쓴다 · 상한에 안 걸린다
    w.round()
    assert line(w.k, "판정 불가") == [NANO_LINE], w.k.lines
    assert field(w.k, "nano") == "7", w.k.lines   # N2 — 7초를 채운 바퀴도 nano= 칸 그대로
    assert field(w.k, "cut") == "-" and line(w.k, "ROUND-CAP") == [], w.k.lines
    assert "cursor" not in w.state(), w.state()


def c_ba(w):   # 53바 나노 끊김 없음 · ROUND 줄이 고치기 앞 판과 바이트 같음(N5)
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    w.round()
    assert line(w.k, "판정 불가") == [] and field(w.k, "cut") == "-", w.k.lines
    assert line(w.k, "ROUND") == [GOLDEN], (line(w.k, "ROUND"), GOLDEN)


# 53바 기준 = 고치기 앞 판(1ff2c25c)이 낸 ROUND 줄 그대로 — 이 칸이 바뀌면 N5(다른 칸 손 0)를 다시 본다
GOLDEN = ("ROUND s=0 fetch=0 b1=0 b2c=0 b2f=0 b3=0 stall=0 fetch_root=0 fetch_pack=0 wall=0 other=0 "
          "items=8/8 cut=- slow=t1:b1:0")

CASES = {"53가": c_ga, "53나": c_na, "53다": c_da, "53라": c_ra, "53마": c_ma, "53바": c_ba}

FIX = '            self.cut, self.cut_pos = "-", None   # r2245 N1 — 나노 모으기 끊김은 업무 구획 끊김이 아니다(cut 칸·cursor 흔적 0)'
ROUND_LOG = '        self.log("ROUND", text="s=%g %s slow=%s%s%s%s"'
POP_CURSOR = '        if self.cut == "-":   # R4 — 끊기지 않고 바퀴를 다 돌았으면 cursor 를 지운다'
# 변이 = (파일, [(옛 글, 새 글) ...], 잡히는 사례) — 여러 곳을 같이 바꾸는 변이(M134)를 담으려고 목록이다
MUTANTS = {
    "M133": (KP, [(FIX, "            pass")], ("53가", "53나", "53라")),   # :476 갈래에서 되돌리지 않음(지금 판)
    "M134": (KP, [(FIX, "            pass"), (ROUND_LOG, '        self.cut = "-"   # 변이 M134 — 되돌림을 ROUND 줄 앞에서만\n' + ROUND_LOG)],
             ("53라",)),   # 되돌림을 ROUND 줄 바로 앞에서만 = :522 가 먼저 돌아 cursor 가 남는다
    "M135": (KP, [(POP_CURSOR, '        self.cut = "-"   # 변이 M135 — 업무 구획 끝에서 무조건\n' + POP_CURSOR)], ("53다",)),
    "M136": (KP, [('        if nano_cut or self.nano_s >= NANO_S:\n            self.log("판정 불가", text="나노 가지 모으기 7초 넘음 — 모은 것만")',
                    '        if nano_cut or self.nano_s >= NANO_S:\n            pass')], ("53가",)),   # 나노 판정 불가 줄을 지움
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
    try:   # 변이 세계 = 판정 줄이 달라지거나(AssertionError) 값이 없거나(KeyError) 심사가 선다
        CASES[cases[0]](Rig(tmp_path / "w1", tree))
    except BaseException:   # noqa: BLE001 — 어떤 실패든 변이를 잡은 것
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, cases[0]))
    for n, case in enumerate(cases[1:]):   # 같은 변이의 다른 사례 = 원본 나무로 PASS(대조)
        assert CASES[case](Rig(tmp_path / ("c%d%s" % (n, case)), None)) is None
