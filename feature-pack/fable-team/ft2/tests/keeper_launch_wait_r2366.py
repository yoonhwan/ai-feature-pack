"""r2366 대역 — keeper 가 미룬 열기(owner 있음 · intent 없음 · state fill_open 에 같은 attempt) 판정 시험의 공용 부품.

한 사례 = 임시 세계(r1812 keeper_world) 1개 + 나노 1석(세션 없음) + state fill_open 주입 + settle_nano 1바퀴.
실 tmux·실 원장·실 좌석 0 · sleep 0(시계 = 주입 w.t) · 가짜 ft-card-assign-watch.sh(FT2_CARD_ASSIGN_BIN · 인자 기록 · rc 파일).
시험 파일 둘(a = 반례 ①~④ + 변이 M1·M3 · b = 반례 ⑤~⑧ + 변이 M2·M4·M5)이 이 파일을 같이 읽는다 — DA#49 메모 ①(한 번에 53초 = 쪼개기).
"""
import datetime
import importlib.util
import sys
from pathlib import Path


_spec = importlib.util.spec_from_file_location("keeper_world_r2366", str(Path(__file__).with_name("keeper_world_r1812.py")))
kw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kw)
W, TEAM, KS, OPEN_STALE = "r9636", kw.TEAM, "adapters/pi/keeper_settle.py", 900
H = "byz-harness-nano-r9636-t#0"
KILL = 'if a[0] == "kill-session"'
EXTRA = ('if a[0] == "has-session" and d.get("err"): sys.stderr.write(d["err"] + "\\n"); sys.exit(1)\n')
RECORD = ('#!/bin/sh\nprintf "%s\\n" "$*" >> "$0.log"\n[ -f "$0.rc" ] && exit "$(cat "$0.rc")\n'
          'printf \'{"state": "none", "released_at": 1}\' > ".fable-team/state/card-assign/$2.json"\n')
CLEAR = "record %s clear seat --seat %s" % (W, H)


class Box:
    """한 사례 = 세계 1개 · 나노 1석(세션 없음) · fill_open 주입 · settle_nano 1바퀴 = 새 줄."""

    def __init__(s, tmp, mp, ft2=kw.FT2, fill_open=None, intent_state=None, owner=None):
        s.w = kw.World(tmp, mp, ft2)
        b = tmp / "bin"
        kw._put(b / "tmux", kw.TMUX.replace("__PY__", sys.executable).replace(KILL, EXTRA + KILL, 1))
        kw._put(b / "record", RECORD), (b / "record").chmod(0o755)
        s.rec = b / "record"
        s.w.env.update(FT2_CARD_ASSIGN_BIN=str(s.rec), HOME=str(tmp / "home"))
        s.w.work(W, alive=False, intent=False)
        kw._put(s.w.state / "card-assign" / (W + ".json"), {"state": "seat", "seat": H})
        if intent_state is not None:   # intent 1개 = 문턱 안쪽(지금 1분 전 · opening_age·opening_stale = 로컬 naive 시각)
            at = datetime.datetime.fromtimestamp(s.w.t - 60).strftime("%Y-%m-%dT%H:%M:%S")
            kw._put(s.w.runtime(TEAM) / "launch" / ("%s@a1.intent" % W), {"FT2_HOLDER": H, "state": intent_state, "at": at})
        s.k, s.seen, s.owner = s.w.keeper(), 0, owner
        if fill_open is not None:
            s.k.state["fill_open"] = fill_open

    def calls(s):
        return kw._lines(str(s.rec) + ".log")

    def sent(s):
        return [x for x in kw._lines(str(s.w.mbox) + ".log") if x.startswith("send ")]

    def round(s, dt=0, attempt="a1", owner="same"):
        """한 바퀴 = 시계 dt 초 앞으로 · 바퀴 캐시 새로 · settle_nano 1회 → 이 바퀴 새 줄(알림 줄 셈 밖)."""
        s.w.t += dt
        s.k.cache, s.k.halt = {"@round": {}}, False
        owner = s.owner if owner == "same" else owner
        s.k.settle_nano(TEAM, W, attempt, H, {"owner": owner, "done": False}, "")
        new, s.seen = s.k.lines[s.seen:], len(s.k.lines)
        return new


def fill(attempt="a1"):
    return {"%s|%s" % (TEAM, W): attempt}


WORKING = "WORKING %s %s %s launch-wait" % (TEAM, W, H)
ORPHAN = "UNKNOWN %s %s %s owner-orphan" % (TEAM, W, H)


def ruling(lines):
    """이 바퀴 판정 줄만(쪽지 «NOTIFIED» 줄은 빼고 · 꼬리는 startswith 로 본다)."""
    return [x for x in lines if not x.startswith("NOTIFIED")]


def starts(lines, want):
    """판정 줄 수 = 기대 수 ∧ 앞에서부터 같은 낱말(꼬리 = « · …» 는 안 본다)."""
    got = ruling(lines)
    return len(got) == len(want) and all(g.startswith(w) for g, w in zip(got, want))


def c1(b):   # ① owner 있음 · intent 없음 · fill_open 같은 attempt → WORKING «launch-wait» 1줄 · UNKNOWN 0 · [긴급] 0
    got = b.round()
    assert starts(got, [WORKING]), got
    assert b.k.unknown == 0 and b.sent() == [] and b.calls() == []


def c2(b):   # ② ① 과 같되 바퀴 이어 3번 · 첫 바퀴 WORKING · OPEN_STALE 넘긴 둘째 바퀴 = owner-orphan UNKNOWN 1 · 셋째 바퀴도 owner-orphan(WORKING 0 · DA#48 I1)
    got = b.round()
    assert starts(got, [WORKING]) and b.k.unknown == 0, got
    got = b.round(OPEN_STALE)
    assert starts(got, [ORPHAN]) and b.k.unknown == 1, got
    assert len(b.sent()) == 1 and b.k.state["alerts"], b.sent()
    got = b.round()   # 판정 줄은 같은 (UNKNOWN, owner-orphan) 이라 반복 0 · 셈은 바퀴마다
    assert got == [] and b.k.unknown == 2 and b.calls() == [], got   # 문턱 넘긴 뒤에도 첫 시각은 남는다(WORKING 으로 안 돌아감)
    assert len([x for x in b.k.lines if x.startswith("WORKING")]) == 1, b.k.lines   # WORKING 줄은 첫 바퀴 1개뿐


def c3(b):   # ③ ① 과 같되 fill_open 에 그 work 없음 → 첫 바퀴부터 owner-orphan UNKNOWN 1(지금 그대로)
    got = b.round()
    assert starts(got, [ORPHAN]) and b.k.unknown == 1, got


def c4(b):   # ④ fill_open 값 = 다른 attempt → owner-orphan UNKNOWN 1(지금 그대로 · K2)
    got = b.round()
    assert starts(got, [ORPHAN]) and b.k.unknown == 1, got


def c5(b):   # ⑤ intent state opening(문턱 안) · fill_open 있음 → launch-joining 그대로(새 갈래 0)
    got = b.round()
    assert starts(got, ["WORKING %s %s %s launch-joining" % (TEAM, W, H)]), got
    assert b.k.unknown == 0 and b.calls() == []


def c6(b):   # ⑥ intent state failed · owner 있음 · fill_open 있음 → failed_end 길 그대로(park 부름 · UNKNOWN launch-failed)
    got = b.round()
    assert starts(got, ["UNKNOWN %s %s %s launch-failed" % (TEAM, W, H)]), got
    assert b.k.unknown == 1, got


def c7(b):   # ⑦ owner 없음 · intent 없음 · fill_open 있음 → session-absent 그대로(원장 풀기 길)
    got = b.round()
    assert starts(got, ["UNKNOWN %s %s %s session-absent" % (TEAM, W, H)]) and b.k.unknown == 1, got
    assert b.round(OPEN_STALE) and b.calls() == [CLEAR], b.calls()   # r2214 길 = OPEN_STALE 뒤 원장 1회 풀기


def c8(b):   # ⑧ done · absent → PARKED session-absent 그대로
    b.k.settle_nano(TEAM, W, "a1", H, {"owner": b.owner, "done": True}, "")
    assert b.k.lines[-1].startswith("PARKED %s %s %s session-absent" % (TEAM, W, H)), b.k.lines
    assert b.k.unknown == 0


CASES = {"1": c1, "2": c2, "3": c3, "4": c4, "5": c5, "6": c6, "7": c7, "8": c8}
# 사례마다 필요한 세계(기본 = fill_open 같은 attempt · owner 있음)
SETUP = {"1": {"fill_open": fill()}, "2": {"fill_open": fill()}, "3": {"fill_open": {}},
         "4": {"fill_open": fill("a9")}, "5": {"fill_open": fill(), "intent_state": "opening"},
         "6": {"fill_open": fill(), "intent_state": "failed"},
         "7": {"fill_open": fill(), "owner": None}, "8": {"owner": {"holder": H}}}


def box(tmp, mp, name, ft2=kw.FT2):
    cfg = dict(SETUP[name])
    cfg["owner"] = cfg.get("owner", {"holder": H})
    return Box(tmp, mp, ft2, **cfg)


IF = '            if owner and not raw and self.launch_waiting(team, work, attempt):   # r2366 미룬 열기(같은 리포 열기 1개) = 손 0\n'
IF_NORAW = IF.replace('owner and not raw and', 'owner and')   # 의도 검사까지 지운 꼴
TAIL = ('                wait = self.launch_wait(key, first)\n'
        '                if wait:\n'
        '                    return self.verdict(team, work, holder, "WORKING", wait, "열기 미룸 · fill_open 같은 attempt")\n')
BRANCH = IF + TAIL
FAILED_IF = '            if owner and raw.get("state") in ("failed", "closed"):   # 반쪽(r1968·r1973 꼴) = 세션 0 · owner 남음\n'
MUTANTS = {   # 이름: (바꿀 글 [(옛, 새)], 잡아야 하는 사례 이름)
    "M1": ([(BRANCH, '')], "1"),                                                              # 새 갈래 지움 → ① FAIL
    "M2": ([('return "launch-wait" if now - first < OPEN_STALE else ""', 'return "launch-wait"')], "2"),   # 문턱 검사 지움 → ② FAIL
    "M3": ([('(self.state.get("fill_open") or {}).get("%s|%s" % (team, work)) == attempt',
             '(self.state.get("fill_open") or {}).get("%s|%s" % (team, work))')], "4"),        # attempt 비교 지움 → ④ FAIL
    "M4": ([(BRANCH, ''), (FAILED_IF, IF_NORAW + TAIL + FAILED_IF)], "6"),                    # 새 갈래를 failed·closed 앞으로 → ⑥ FAIL
    "M5": ([(IF, IF.replace('owner and not raw and', 'not raw and'))], "7"),                   # owner 검사 지움 → ⑦ FAIL
}


