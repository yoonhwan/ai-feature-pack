"""r2298 keeper — b3 칸(팀 밖 · 고아·승계 닫기)이 가장 느린 칸이면 SLOW-CELL·ROUND slow= 에 «-:b3» · 줄 끝 parts=b3o:X,b3r:Y (관측만).

카드 r2298-keeper-slow-cell-b3-visible · 계약 A1(top 후보 = 팀 칸 + (None, b3)) · A2(parts) · A3(불변 · 팀 칸 0 바퀴 = slow=-:b3) · A4(표본 19:45:40).
대역 = test_keeper_round_60s.Rig 그대로(주입 시계 · 가짜 subprocess.run · 실 tmux·git 0 · sleep 0).
기준판 = FIX 쌍을 거꾸로 되돌린 사본(①②③④ⓑ Red) · ④⑤ = 기준판과 SLOW-CELL·ROUND 바이트 같음 · 변이 M1~M3 = 사본에서만.
"""
import shutil

import pytest

from test_keeper_round_60s import FT2, KP, Rig, field, line

SAMPLE = "tmux+list-sessions"
FIX = [   # (기준판 줄, 고친 줄) — 기준판 = 고친 줄을 기준판 줄로 되돌린 사본
    ("        self.per, self.at = {}, None   #", "        self.per, self.at, self.b3p = {}, None, {}   #"),
    ("        at, prev, self.stage = self.now(), self.stage, stage\n",
     "        at, prev, self.stage, pos = self.now(), self.stage, stage, self.cursor_stage\n"),
    ("            self.per[(self.at, stage)] = self.per.get((self.at, stage), 0.0) + dt\n",
     "            self.per[(self.at, stage)] = self.per.get((self.at, stage), 0.0) + dt\n"
     "            if stage == \"b3\":   # r2298 A2 b3 칸 = b3o·b3r 자리 몫(at_pos 가 적은 자리)\n"
     "                self.b3p[pos] = self.b3p.get(pos, 0.0) + dt\n"),
    ("if kv[0][0]), key=", "if kv[0][0] or kv[0] == (None, \"b3\")), key="),
    ("        if top:   # r1992", "        who = top and (top[0][0] or \"-\")   # r2298 A1 팀 밖 b3 칸 = «-»\n        if top:   # r1992"),
    ("            self.log(\"SLOW-CELL\", top[0][0], ", "            tail += \" parts=b3o:%g,b3r:%g\" % (round(self.b3p.get(\"b3o\", 0.0), 1), round(self.b3p.get(\"b3r\", 0.0), 1)) if top[0] == (None, \"b3\") else \"\"\n"
     "            self.log(\"SLOW-CELL\", who, "),
    ("\"%s:%s:%g\" % (top[0] + (round(top[1], 1),))", "\"%s:%s:%g\" % (who, top[0][1], round(top[1], 1))"),
]
MUT = {"M1": [("if kv[0][0] or kv[0] == (None, \"b3\")), key=", "if kv[0][0]), key=")],
       "M2": [("if kv[0][0] or kv[0] == (None, \"b3\")), key=", "if kv[0][0] or kv[0][0] is None), key=")],
       "M3": [("(round(self.b3p.get(\"b3o\", 0.0), 1), round(self.b3p.get(\"b3r\", 0.0), 1))",
               "(round(self.b3p.get(\"b3r\", 0.0), 1), round(self.b3p.get(\"b3o\", 0.0), 1))")]}


def rig(w, teams=("t1",), b1=0.0, fill=None, b3o=(), b3o_py=0.0, b3r=0.0, cut_b3r=False, fetch=0.0):
    """한 바퀴 — b1 = 첫 팀 landing 초 · fill = {팀: b2f 초} · b3o = 고아 판독 호출 초들 + b3o_py(호출 밖) · b3r = retired 초 · cut_b3r = sweep 호출이 끊김."""
    w.teams, w.works = list(teams), ({teams[0]: ["w1"]} if teams and b1 else {})
    g = w.mod.Keeper.__init__.__globals__
    g["closing"].keeper_next.fill = lambda k, team: w.wait((fill or {}).get(team, 0.0))
    g["endings"].orphans = lambda k, order: ([w.reads(("tmux", "list-sessions"), s) for s in b3o], w.wait(b3o_py))
    w.k.landing = lambda team, work: (w.wait(b1), ("ab" * 20, "main", ""))[1]
    w.k.fresh = lambda repo: (w.wait(fetch / 2), True)[1]
    w.k.close_old.sweep = (lambda: w.reads(("tmux", "list-sessions"), 1.0)) if cut_b3r else (lambda: None)
    w.k.retired = lambda: w.wait(b3r)
    w.round()
    return line(w.k, "SLOW-CELL"), field(w.k, "slow")


def c1(w):   # ① b1(t1)=10 · b3=31(호출 4·3초 + 호출 밖 24) → SLOW-CELL - b3 · slow=-:b3:31 (기준판 = t1:b1:10 = Red)
    cell, slow = rig(w, b1=10, b3o=(4, 3), b3o_py=13, b3r=11)
    assert cell == ["SLOW-CELL - b3 s=31 n=2 slow_call=0 top=%s:4,%s:3 py=24 parts=b3o:20,b3r:11" % (SAMPLE, SAMPLE)], w.k.lines
    assert slow == "-:b3:31", w.k.lines


def c2(w):   # ② parts 차례 b3o·b3r · b3o 만 돈 바퀴(b3r 자리 cut) → b3r:0
    cell, _ = rig(w, teams=(), b3o_py=20, b3r=11)
    assert cell and cell[0].endswith(" parts=b3o:20,b3r:11"), w.k.lines
    w2 = Rig(w.tmp2, w.tree)
    w2.tmp2 = None
    cell, slow = rig(w2, teams=(), fetch=26, b3o_py=20, cut_b3r=True)
    assert field(w2.k, "cut") == "-:-:b3r" and slow == "-:b3:20", w2.k.lines
    assert cell and cell[0].endswith(" parts=b3o:20,b3r:0"), w2.k.lines


def c3(w):   # ③ 표본 2026-11-19 19:45:40 꼴(b1 5.1 · b2f v65 10.6 · b3 98 · b3r 자리 cut) → slow=-:b3:98 · SLOW-CELL - b3
    cell, slow = rig(w, teams=("t1", "v65"), b1=5.1, fill={"v65": 10.6}, b3o_py=98, cut_b3r=True)
    assert slow == "-:b3:98" and field(w.k, "b3") == "98" and field(w.k, "cut") == "-:-:b3r", w.k.lines
    assert len(cell) == 1 and cell[0].startswith("SLOW-CELL - b3 s=98 ") and cell[0].endswith(" parts=b3o:98,b3r:0"), w.k.lines


def c4b(w):   # ④ⓑ 팀 칸 0 바퀴 · b3=0.4 → slow=-:b3:0.4 · SLOW-CELL - b3 1줄 (기준판 = slow=- · SLOW-CELL 0)
    cell, slow = rig(w, teams=(), b3r=0.4)
    assert slow == "-:b3:0.4" and cell == ["SLOW-CELL - b3 s=0.4 n=0 slow_call=0 top=- py=0.4 parts=b3o:0,b3r:0.4"], w.k.lines


CASES = {"①": c1, "②": c2, "③": c3, "④ⓑ": c4b}
SAME = {"④": dict(b1=10, b3o_py=0.5),   # ④ b3=0.5 · b1=10 → 기준판과 바이트 같음
        "⑤": dict(b1=3, fetch=12, b3o_py=1)}   # ⑤ fetch=12(팀 None) · b1=3 · b3=1 → fetch 후보 0 · 기준판과 같음


def tree(tmp, pairs):
    """사본 ft2 — keeper.py 에 (old, new) 쌍을 1회씩 바꿔 쓴다."""
    out = tmp / "ft2"
    shutil.copytree(FT2, out, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (out / KP).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    (out / KP).write_text(text, encoding="utf-8")
    return out


def world(tmp, src=None):
    (tmp / "w").mkdir(parents=True)
    (tmp / "w2").mkdir()
    w = Rig(tmp / "w", src)
    w.tmp2 = tmp / "w2"
    return w


def base(tmp):
    return tree(tmp / "base", [(new, old) for old, new in FIX])


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](world(tmp_path))


@pytest.mark.parametrize("name", list(CASES))
def test_base_red(name, tmp_path):
    w = world(tmp_path, base(tmp_path))
    with pytest.raises(AssertionError):
        CASES[name](w)


@pytest.mark.parametrize("name", list(SAME))
def test_same_as_base(name, tmp_path):
    w, b = world(tmp_path / "f"), world(tmp_path / "b", base(tmp_path))
    got, want = rig(w, **SAME[name]), rig(b, **SAME[name])
    assert got == want and got[1] == ("t1:b1:%g" % SAME[name]["b1"]), (w.k.lines, b.k.lines)
    assert line(w.k, "ROUND") == line(b.k, "ROUND") and not any("parts=" in x for x in w.k.lines), (w.k.lines, b.k.lines)


@pytest.mark.parametrize("name, kills", [("M1", ("①", "③")), ("M2", ("⑤",)), ("M3", ("②",))])
def test_mutant(name, kills, tmp_path):
    src = tree(tmp_path / "m", MUT[name])
    for case in kills:
        if case in SAME:
            w, b = world(tmp_path / ("f" + case), src), world(tmp_path / ("b" + case), base(tmp_path / case))
            with pytest.raises(AssertionError):
                assert rig(w, **SAME[case]) == rig(b, **SAME[case]), w.k.lines
            continue
        w = world(tmp_path / case, src)
        with pytest.raises(AssertionError):
            CASES[case](w)
        CASES[case](world(tmp_path / ("o" + case)))   # 원본 = 같은 사례 통과(반대 결과 대조)
