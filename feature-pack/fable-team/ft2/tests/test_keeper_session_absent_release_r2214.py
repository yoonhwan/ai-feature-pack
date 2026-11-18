"""r2214 keeper session-absent 원장 풀기 — 세션 없음 ∧ owner·done 없음이 OPEN_STALE(900초) 넘게 이어지면 1.x 배정 원장 seat 1회 풀기.
카드 반례 ②~⑦(③b~③d · ⑤b~⑤e · ⑥b) · 변이 M1~M6(M1b 포함 · 사본에서만 · 변이마다 원본으로 같은 사례 1회 더 = PASS).
대역 = r1812 keeper_world(임시 root · 가짜 tmux · 주입 시계) + 가짜 ft-card-assign-watch.sh(FT2_CARD_ASSIGN_BIN · 인자 기록 · rc 파일).
settle_nano 를 바퀴마다 직접 부른다(owner 없음 꼴은 코어 CLI 로 못 만듦 · 바퀴 캐시는 바퀴마다 새로). 실 tmux·실 원장·실 좌석 0 · sleep 0.
기준판(팩 main 204ef2a3c6) = ② ③c ⑤b ⑤c ⑤d ⑤e ⑥ ⑥b ⑦ Red 9건(풀기·판정 불가 줄 0) · ③ ③b ③d ④ ⑤ = 지킴 5건.
"""
import importlib.util
import json
import shutil
import sys
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("keeper_world_r2214", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
W, TEAM, KS = "r9214", kw.TEAM, "adapters/pi/keeper_settle.py"
H = "byz-harness-nano-r9214-t#0"
KILL = 'if a[0] == "kill-session"'
EXTRA = ('if a[0] == "has-session" and d.get("err"): sys.stderr.write(d["err"] + "\\n"); sys.exit(1)\n'   # ⑤c 서버 없음 err
         'if a[0] == "list-sessions" and d.get("ls_rc"): sys.exit(d["ls_rc"])\n')                          # ⑤e list-sessions 실패
RECORD = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\n[ -f "$0.rc" ] && exit "$(cat "$0.rc")"\n'
          'printf \'{"state": "none", "released_at": 1}\' > ".fable-team/state/card-assign/$2.json"\n')


class Box:
    def __init__(s, tmp, mp, ft2=kw.FT2):
        s.w = kw.World(tmp, mp, ft2)
        b = tmp / "bin"
        kw._put(b / "tmux", kw.TMUX.replace("__PY__", sys.executable).replace(KILL, EXTRA + KILL, 1))
        kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
        s.rec = b / "record"
        s.w.env.update(FT2_CARD_ASSIGN_BIN=str(s.rec), HOME=str(tmp / "home"))
        s.w.work(W, alive=False)
        s.led({"state": "seat", "seat": H})
        s.k, s.seen = s.w.keeper(), 0

    def led(s, doc):
        kw._put(s.w.state / "card-assign" / (W + ".json"), doc)

    def tm(s, **kv):
        d = json.loads(s.w.tm.read_text(encoding="utf-8"))
        d.update(kv)
        kw._put(s.w.tm, d)

    def round(s, dt=0, owner=None, attempt="a1", halt=False):
        """한 바퀴 = 시계 dt 초 앞으로 · 바퀴 캐시 새로 · settle_nano 1회 → 이 바퀴 새 줄(알림 줄 셈 밖)."""
        s.w.t += dt
        s.k.cache, s.k.halt = {"@round": {}}, halt
        s.k.settle_nano(TEAM, W, attempt, H, {"owner": owner, "done": False}, "")
        new, s.seen = s.k.lines[s.seen:], len(s.k.lines)
        return [x for x in new if not x.startswith("NOTIFIED ")]

    def calls(s):
        return kw._lines(str(s.rec) + ".log")


CLEAR = "record %s clear seat --seat %s" % (W, H)
RELEASED = "RELEASED %s %s %s · 원장 풀림 · 다음 fill 새 attempt" % (TEAM, W, H)
UNSURE = "판정 불가 %s %s %s 원장 풀기 0 · " % (TEAM, W, H)


def _two(b, dt=900, **kv):
    first = b.round(**kv)
    assert first[:1] == ["UNKNOWN %s %s %s %s" % (TEAM, W, H, "owner-orphan" if kv.get("owner") else "session-absent")], first   # O3 판정 그대로
    return b.round(dt, **kv)


def c2(b):    # ② 900초 넘긴 두 바퀴째 → record clear seat 1회 + RELEASED 1줄
    assert _two(b) == [RELEASED] and b.calls() == [CLEAR]


def c3(b):    # ③ 첫 바퀴 → 호출 0 · 지금 줄 그대로(UNKNOWN session-absent 1줄)
    assert b.round() == ["UNKNOWN %s %s %s session-absent" % (TEAM, W, H)] and b.calls() == []


def c3b(b):   # ③b 899초 → 호출 0
    assert _two(b, 899) == [] and b.calls() == []


def c3c(b):   # ③c absent → alive 1바퀴 → absent · 첫 absent 부터 1000초 → 호출 0(시각 지워져 다시 셈)
    b.round(), b.tm(alive=[H]), b.round(500), b.tm(alive=[])
    assert RELEASED not in b.round(500) and b.calls() == []
    assert b.round(900) == [RELEASED] and b.calls() == [CLEAR]   # 다시 센 900초 뒤 = 풀림


def c3d(b):   # ③d 같은 work 새 attempt 의 첫 absent → 호출 0(옛 attempt 시각 안 씀)
    b.round()
    assert RELEASED not in b.round(1000, attempt="a2") and b.calls() == []


def c4(b):    # ④ owner 있음(owner-orphan) 두 바퀴 → 호출 0
    assert _two(b, owner={"holder": H}) == [] and b.calls() == []


def c5(b):    # ⑤ 원장 seat ≠ holder · none · waiting → 호출 0 · 줄 0(첫 바퀴 뒤 900초씩)
    b.round()
    for doc in ({"state": "seat", "seat": "byz-harness-nano-other#0"}, {"state": "none"}, {"state": "waiting", "reason": "사람"}):
        b.led(doc)
        assert b.round(900) == [] and b.calls() == [], doc


def c5b(b):   # ⑤b 대소문자만 다른 세션 → 호출 0 · 판정 불가 1줄
    b.tm(alive=["byz-harness-nano-R9214-t#0"])
    assert _two(b) == [UNSURE + "대소문자만 다른 세션 byz-harness-nano-R9214-t#0"] and b.calls() == []


def c5c(b):   # ⑤c has-session «no server running» → 호출 0 · 판정 불가 1줄
    b.tm(err="no server running on /tmp/tmux-501/default")
    assert _two(b) == [UNSURE + "tmux 서버 없음"] and b.calls() == []


def c5d(b):   # ⑤d ALL_STOP 중 → 호출 0 · 처음 absent 시각은 그대로(정지 풀린 바퀴 = 바로 풀림)
    assert _two(b, halt=True) == [] and b.calls() == []
    assert b.round() == [RELEASED] and b.calls() == [CLEAR]


def c5e(b):   # ⑤e list-sessions rc≠0 → 호출 0 · 판정 불가 1줄
    b.tm(ls_rc=1)
    assert _two(b) == [UNSURE + "tmux list-sessions rc 1"] and b.calls() == []


def c6(b):    # ⑥ 도구 rc 1 → 판정 불가 1줄 · 같은 바퀴 재시도 0
    kw._put(Path(str(b.rec) + ".rc"), "1")
    assert _two(b) == [UNSURE + "원장 풀기 rc 1"] and b.calls() == [CLEAR]


def c6b(b):   # ⑥b ⑤c 조건 세 바퀴 → 판정 불가 줄 1줄만 · 사유가 바뀌면 다시 1줄
    b.tm(err="no server running on /tmp/tmux-501/default")
    assert _two(b) == [UNSURE + "tmux 서버 없음"] and b.round(60) == [] and b.calls() == []
    b.tm(err="", ls_rc=1)
    assert b.round(60) == [UNSURE + "tmux list-sessions rc 1"]


def c7(b):    # ⑦ 풀린 뒤 다음 바퀴(원장 none) → 호출 0 · RELEASED 0
    assert _two(b) == [RELEASED] and b.round(60) == [] and b.calls() == [CLEAR]


CASES = {n: f for n, f in globals().items() if n[:1] == "c" and n[1:2].isdigit()}
MUTANTS = {"M1": ("if now - first < OPEN_STALE:", "if False:", c3),
           "M1b": ('key = "%s|%s|%s|%s" % (team, work, attempt, holder)', 'key = "%s|%s|%s" % (team, work, holder)', c3d),
           "M2": (' or led.get("seat") != holder', "", c5),
           "M3": ("if not owner:   # r2214", "if True:   # r2214", c4),
           "M4": ("x != holder and x.casefold() == holder.casefold()", "x != holder and x == holder", c5b),
           "M5": ("""if rc != 1 or "can't find session" not in err:""", """if rc != 1 or not ("can't find session" in err or "no server running" in err):""", c5c),
           "M6": ("if self.halt:   # r2214", "if False:   # r2214", c5d)}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](Box(tmp_path, monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KS).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(Box(tmp_path / "w1", monkeypatch, tree))
    case(Box(tmp_path / "w2", monkeypatch))   # 원본으로 같은 사례 1회 더 = PASS
