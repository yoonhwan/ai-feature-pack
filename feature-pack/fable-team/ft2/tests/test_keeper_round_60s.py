"""ft2 keeper 한 바퀴 60초 — 예산 시계 1개(R1~R13 · 반례 ㊳가~너 · ㊴가~아 · ㊷가~마 · 변이 M72~M84 · M94~M97).

대역(카드 «시험 입력»): 임시 루트(tmp_path) · 주입 시계(모듈 전역 time.monotonic = self.now = rig.t) · 가짜 subprocess.run
(카드: «가짜 호출은 요청받은 상한과 자기 소요 중 작은 값만큼 가짜 시계를 올린다 · 호출 1개가 자기 상한보다 길면 상한에서 끊긴 것») ·
가짜 journal·카드·tmux·mbox(호출 인자만 기록) · sleep 0 · 네트워크 0 · 실 runtime·실 tmux·실 명부 읽기·쓰기 0.

r2098 구현 = keeper.py(`call` 문 · 판독 목록 · 구획 시계 · 끊김 2종 · cursor · ROUND 칸 · 꽉 참 손) ·
keeper_report.py(R8 쪽지 미룸 · report 구획 · rep_cursor · alert_out 보내기) · full_alert.py(«보내는 손» 인자 1칸).
"""
import ast
import importlib.util
import json
import os
import shutil
import subprocess
import types
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
PI = FT2 / "adapters" / "pi"
DEAD = {"bash", "git", "tmux", "ps", "gh"}   # 죽은 세션·죽은 우편함을 흉내내는 기본값


def _mod(tree=None):
    base = Path(tree) if tree else FT2
    spec = importlib.util.spec_from_file_location("r2098_keeper_%d_%f" % (os.getpid(), id(object())), str(base / "adapters" / "pi" / "keeper.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Rig:
    """바퀴 하나를 도는 데 필요한 것만 진짜로 둔다 — 예산 문·cursor·ROUND 칸·알림은 실제 코드가 돈다."""

    def __init__(s, tmp, tree=None):
        s.t, s.calls, s.done, s.plan = 0.0, [], [], lambda argv, timeout: (0.0, 0, "")
        s.teams, s.works, s.visits, s.tree = ["t1"], {"t1": ["w1"]}, [], Path(tree) if tree else FT2
        s.mod = _mod(s.tree)
        g = s.mod.Keeper.__init__.__globals__
        g["time"] = types.SimpleNamespace(monotonic=s.clock, time=s.clock)   # R1 monotonic 주입점
        g["subprocess"] = types.SimpleNamespace(run=s.run, TimeoutExpired=subprocess.TimeoutExpired,
                                                CompletedProcess=subprocess.CompletedProcess, SubprocessError=subprocess.SubprocessError)
        g["kf"] = types.SimpleNamespace(targets=lambda k: {}, collect=lambda k: None, nanos=lambda k, teams: {},
                                        background=lambda *a: None, CAP=5)
        g["closing"].keeper_next.fill = lambda k, team: s.done.append(["fill", team])
        g["endings"].ending, g["endings"].orphans = (lambda k, team, work: False), (lambda k, order: s.done.append(["orphans"]))
        g["hold"].check = lambda k, team, work, attempt, rows: s.done.append(["hold", team, work])
        s.root = Path(tmp) / "root"
        for sub in ("state/ft2-keeper", "comm", "teams/harness/runtime"):
            (s.root / ".fable-team" / sub).mkdir(parents=True, exist_ok=True)
        for team in ("harness", "t1", "t2", "t3"):
            (s.root / ".fable-team" / ("seats-%s.json" % team)).write_text(json.dumps({"_master": "M-" + team}), encoding="utf-8")
        (s.root / ".fable-team" / "comm" / "mailbox.log.jsonl").write_text("", encoding="utf-8")
        s.k = s.mod.Keeper(str(s.root), env={"FT2_KEEPER_MBOX": str(s.root / ".fable-team" / "comm" / "mbox.sh"), "FT2_PACK_REPO": str(s.root)},
                           now=s.clock)
        s.k.teams, s.k.rows_of = (lambda: list(s.teams)), s.rows
        s.k.project = lambda root, team: {"result": s.mod.OK, "works": {w: {"done": False} for w in s.works.get(team, [])}}
        s.k.landing, s.k.land_ready = s.landing, (lambda *a: True)
        s.k.complete = lambda team, work, attempt, landed: (s.done.append(["complete", team, work]), True)[1]
        s.k.close = s.close
        s.k.settle_nano = lambda *a: (s.done.append(["settle", a[0], a[1]]), "WORKING")[1]
        s.k.stall = types.SimpleNamespace(check=lambda *a: s.done.append(["stall"]))
        s.k.accept_only = lambda team, rows: s.done.append(["accept", team])
        s.k.retired = lambda: s.done.append(["retired"])
        s.k.probe = lambda seat: (s.visits.append(seat), "alive")[1]

    def clock(s):
        return s.t

    def run(s, argv, **kw):
        s.calls.append(list(argv))
        own, rc, out = s.plan(list(argv), float(kw.get("timeout") or 0.0))
        cap = float(kw.get("timeout") or own or 0.0)
        s.t += min(own, cap) if cap else own
        if rc == "T" or own > cap:   # 상한에서 끊긴 것 = rc None
            raise subprocess.TimeoutExpired(argv, cap)
        return subprocess.CompletedProcess(argv, rc, out, "")

    def rows(s, team):
        return [{"kind": "dispatch", "work": w, "attempt": "a1", "holder": "h#0"} for w in s.works.get(team, [])]

    def landing(s, team, work):
        s.done.append(["land", team, work])
        return ("ab" * 20, "main", "")

    def close(s, team, work, attempt, row, dispatched):
        s.done.append(["close", team, work])

    def reads(s, key=("tmux", "has-session"), seconds=7.0, n=1):
        """판독 호출 n번 — 소요 seconds(상한 7초라 넘으면 그 자리에서 끊긴다)."""
        plan = s.plan
        s.plan = lambda argv, timeout: (seconds, 0, "")
        try:
            for _ in range(n):
                s.k.call(list(key))
        finally:
            s.plan = plan

    def wait(s, seconds):
        """바깥 호출 없이 흐른 초(파이썬 안 시간) — ROUND other= 로만 보인다."""
        s.t += seconds

    def round(s, keeper=None):
        k = keeper or s.k
        assert k.run_once() == 0
        return k.lines

    def room(s, **cells):
        (s.root / ".fable-team" / "state" / "ft2-keeper" / "state.json").write_text(json.dumps(cells), encoding="utf-8")

    def state(s):
        path = s.root / ".fable-team" / "state" / "ft2-keeper" / "state.json"
        return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}

    def ledger(s, *rows):
        with open(s.root / ".fable-team" / "comm" / "mailbox.log.jsonl", "a", encoding="utf-8") as fh:
            for seq, to, body in rows:
                fh.write(json.dumps({"seq": seq, "from": "ft2-full-alert", "to": to, "body": body}, ensure_ascii=False) + "\n")

    def sent(s):
        return [c for c in s.calls if "send" in c]


def line(k, head):
    return [x for x in k.lines if x.startswith(head)]


def field(k, name):
    got = [x for x in k.lines if x.startswith("ROUND")]
    assert got, k.lines
    for word in got[-1].split():
        if word.startswith(name + "="):
            return word.split("=", 1)[1]
    return None


# ── ㊳ 업무 구획 ───────────────────────────────────────────────────────────────
def c_ga(w):   # ㊳가 팀 3 · 첫 팀 work 1 의 b2c 판독이 50초 → 45초에 끊김 · ROUND-CAP 1줄 · cursor 그 자리 · 뒤 자리 0 · wall ≤ 60
    w.teams, w.works = ["t1", "t2", "t3"], {t: ["w1"] for t in ("t1", "t2", "t3")}
    w.k.close = lambda *a: w.reads(("tmux", "has-session"), 7.0, 20)
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w1 b2c — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t1", "work": "w1", "stage": "b2c", "cuts": 1}, w.state()
    assert [d for d in w.done if d[0] == "land"] == [["land", "t1", "w1"]], w.done   # 뒤 팀·뒤 자리 시작 0
    assert float(field(w.k, "wall")) <= 45 and field(w.k, "cut") == "t1:w1:b2c", w.k.lines   # 업무 구획 끝(45초)에서 끊긴다


def c_na(w):   # ㊳나 한 팀 work 5 · 각 b1 판독 14초 → 넷째 work 에서 끊김 · cursor · 다음 바퀴 앞 셋 재판독 0
    w.teams, w.works = ["t1"], {"t1": ["w1", "w2", "w3", "w4", "w5"]}

    def landing(team, work):
        w.done.append(["land", team, work])
        w.reads(("git", "show"), 7.0, 2)
        return ("ab" * 20, "main", "")
    w.k.landing = landing
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w4 b1 — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t1", "work": "w4", "stage": "b1", "cuts": 1}, w.state()
    done, w.k.lines[:] = len(w.done), []
    lines = w.round()   # 다음 바퀴 = 넷째부터(앞 셋 재판독 0)
    assert [d for d in w.done[done:] if d[0] == "land"] == [["land", "t1", "w4"], ["land", "t1", "w5"]], w.done[done:]
    assert "cursor" not in w.state() and line(w.k, "ROUND-CAP") == [], lines


def c_da(w):   # ㊳다 fetch 14초 + 나노 모으기 30초 → 나노는 7초에 멈춤 · 판정 불가 1줄 · 모은 것만 · 팀 고리 시작
    w.plan = lambda argv, timeout: (7.0, 0, "") if "fetch" in argv else (0.0, 0, "")

    def nanos(k, teams):
        w.reads(("git", "show"), 7.0, 10)
        return {}
    w.mod.Keeper.__init__.__globals__["kf"].nanos = nanos
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 나노 가지 모으기 7초 넘음 — 모은 것만"], w.k.lines
    assert round(w.k.nano_s, 1) == 7.0 and [d for d in w.done if d[0] == "land"] == [["land", "t1", "w1"]], w.k.lines


def c_ra(w):   # ㊳라 팀 고리가 44초에 끝남 · b3 고아 판독 25초 → b3o 는 45초에 끊김 · cursor = b3o · report 는 돈다
    w.k.accept_only = lambda team, rows: w.wait(44)
    w.mod.Keeper.__init__.__globals__["endings"].orphans = lambda k, order: w.reads(("tmux", "list-sessions"), 7.0, 6)
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP - - b3o — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"]["stage"] == "b3o" and field(w.k, "cut") == "-:-:b3o", w.state()
    assert field(w.k, "items") != "0/6" and float(field(w.k, "wall")) <= 45, w.k.lines   # R1 업무 구획 끝 = 45초


def c_ma(w):   # ㊳마 send rc None 2회 → 그 바퀴 남은 쪽지 0 · NOTIFY-DEFER · 4통 지문·횟수 미소비 · 다음 바퀴에 나감
    w.k.skip = set()
    w.k.start, w.k.sect = w.t, w.mod.REPORT_S
    w.plan = lambda argv, timeout: (7.0, "T" if "send" in argv else 0, "")   # 보내는 것마다 7초 시간 초과
    keys = ["k%d" % n for n in range(7)]
    for n, key in enumerate(keys):
        w.k.notify("t1", key, "[긴급] 글 %d" % n)
    assert len(w.sent()) == 2, w.sent()   # 시간 초과 2회 = 5통 send 0(E5 3통 상한과 따로 선다)
    assert line(w.k, "NOTIFY-DEFER") == []   # DEFER 줄 = flush 몫(아래)
    assert all(not w.k.blocked(key) for key in keys[2:]), w.state()   # 지문·횟수 미소비
    w.k.flush()
    assert line(w.k, "NOTIFY-DEFER") == ["NOTIFY-DEFER t1 5통 · 다음 바퀴"], w.k.lines


def c_ba(w):   # ㊳바 merge-base 8초 · 남은 몫 30초 → 7초에 끊김 · 판정 불가 1줄 · 다음 자리 · 남은 몫 3초면 ROUND-CAP
    w.k.at, w.k.at_work, w.k.start, w.k.sect = "t1", "w1", w.t, 30.0 + 15.0
    w.plan = lambda argv, timeout: (8.0, 0, "")
    with pytest.raises(BaseException) as got:
        w.k.call(["git", "-C", str(w.root), "merge-base", "a", "b"], 7)
    assert type(got.value).__name__ == "Ungraded" and line(w.k, "판정 불가") == ["판정 불가 t1 w1 git 7초 넘음"], w.k.lines
    w.k.lines[:] = []
    w.k.start, w.k.sect = w.t - 42.0, 45.0   # 남은 몫 3초 = 예산이 다한 것(판정 불가 줄 0)
    with pytest.raises(BaseException) as got:
        w.k.call(["git", "-C", str(w.root), "merge-base", "a", "b"], 7)
    assert type(got.value).__name__ == "Cut" and line(w.k, "판정 불가") == [], w.k.lines


def c_sa(w):   # ㊳사 자리 N개 · 매 바퀴 예산이 몇 자리뿐 → cursor 가 순환 · 2N 바퀴 안에 모든 자리가 1회 이상 판정
    w.teams, w.works = ["t1", "t2"], {"t1": ["w1"], "t2": ["w2"]}
    w.k.close = lambda *a: w.reads(("tmux", "has-session"), 7.0, 20)   # b2c 마다 예산을 다 쓴다
    w.k.probe = lambda seat: "alive"
    seen, total = set(), None
    for _ in range(20):
        lines = w.round()
        total = total or field(w.k, "items")
        seen |= {(d[1], d[2]) for d in w.done if d[0] in ("land", "close")}
        if "cursor" not in w.state() and len(seen) >= 5:
            break
        w.k = w.mod.Keeper(str(w.root), env=w.k.env, now=w.clock)   # 다음 바퀴 = 새 프로세스
        w.k.teams, w.k.rows_of = (lambda: list(w.teams)), w.rows
        w.k.project = lambda root, team: {"result": w.mod.OK, "works": {x: {"done": False} for x in w.works.get(team, [])}}
        w.k.landing, w.k.land_ready = w.landing, (lambda *a: True)
        w.k.complete = lambda team, work, attempt, landed: True
        w.k.close = lambda *a: w.reads(("tmux", "has-session"), 7.0, 20)
        w.k.settle_nano = lambda *a: "WORKING"
        w.k.stall = types.SimpleNamespace(check=lambda *a: None)
        w.k.accept_only, w.k.retired, w.k.probe = (lambda *a: None), (lambda: None), (lambda seat: "alive")
        assert lines is not None and total
    assert {("t1", "w1"), ("t2", "w2")} <= seen, seen


def c_a(w):   # ㊳아 쓰기 직전 남은 몫 6초 = 시작 0(끊김) / 8초 = 시작해 끝낸다
    w.k.start, w.k.sect = w.t - 39.0, 45.0
    with pytest.raises(BaseException) as got:
        w.k.call(["tmux", "kill-session", "-t", "=x"], 7)
    assert type(got.value).__name__ == "Cut" and w.calls == [], w.calls
    w.k.start, w.k.sect = w.t - 37.0, 45.0
    assert w.k.call(["tmux", "kill-session", "-t", "=x"], 7)[0] == 0 and len(w.calls) == 1, w.calls


def c_ja(w):   # ㊳자 모두 빠름 → ROUND 끝에 wall·other·items·cut · cursor 없음
    w.round()
    got, allm = field(w.k, "items").split("/")
    assert got == allm and int(allm) > 0 and field(w.k, "cut") == "-" and field(w.k, "other") == "0", w.k.lines
    assert "cursor" not in w.state() and len(line(w.k, "ROUND-CAP")) == 0, w.k.lines


def c_cha(w):   # ㊳차 호출 사이 파이썬 20초 → 다음 문에서 남은 몫에 반영 · other=20 · wall ≤ 60
    w.k.land_ready = lambda *a: (w.wait(20), True)[1]   # 호출 사이 파이썬 20초(가짜 시계)
    w.round()
    assert field(w.k, "other") == "20" and float(field(w.k, "wall")) <= 60, w.k.lines
    assert line(w.k, "ROUND-CAP") == [], w.k.lines


def c_ta(w):   # ㊳타 fill 1항목 안 호출 10개 · 각 7초 → 45초에 끊김 · cursor = (팀, -, b2f) · 다음 바퀴가 잇는다
    w.mod.Keeper.__init__.__globals__["closing"].keeper_next.fill = lambda k, team: w.reads(("bash", "tool", "submit"), 7.0, 10)
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 - b2f — 다음 바퀴 여기부터"], w.k.lines
    assert w.state()["cursor"] == {"team": "t1", "work": "-", "stage": "b2f", "cuts": 1}, w.state()
    assert float(field(w.k, "wall")) <= 45, w.k.lines


def c_ha(w):   # ㊳하 같은 자리 2바퀴 연속 끊김 → 판정 불가 1줄 + cursor 다음 자리 · 셋째 바퀴 = 다음 자리부터
    def burn(*a):   # 같은 자리에서 두 바퀴 연속 예산을 다 쓴다
        w.reads(("tmux", "has-session"), 7.0, 20)
    w.k.close = burn
    w.round()
    first = w.state()["cursor"]
    w.k = _next(w)
    w.k.close = burn
    w.k.lines[:] = []
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 t1 w1 b2c 예산 2회 넘음 — 건너뜀"], w.k.lines
    assert w.state()["cursor"] == {"team": "t1", "work": "w1", "stage": "stall", "cuts": 0} and first["cuts"] == 1, w.state()
    w.k = _next(w)
    w.k.close = burn
    done = len(w.done)
    w.round()
    assert ["close", "t1", "w1"] not in w.done[done:]   # 셋째 바퀴 = 건너뛴 자리부터(닫기 0)


def _next(w):
    """다음 바퀴 = 새 keeper(프로세스가 갈아 끼는 것과 같은 경계)."""
    w.k = w.mod.Keeper(str(w.root), env=w.k.env, now=w.clock)
    k = w.k
    k.teams, k.rows_of = (lambda: list(w.teams)), w.rows
    k.project = lambda root, team: {"result": w.mod.OK, "works": {x: {"done": False} for x in w.works.get(team, [])}}
    k.landing, k.land_ready = w.landing, (lambda *a: True)
    k.complete = lambda team, work, attempt, landed: True
    k.close = getattr(w, "close_fake", lambda *a: w.done.append(["close", a[0], a[1]]))
    k.settle_nano = lambda *a: "WORKING"
    k.stall = types.SimpleNamespace(check=lambda *a: None)
    k.accept_only = lambda team, rows: w.wait(0)
    k.retired = lambda: None
    k.probe = lambda seat: "alive"
    return k


def c_geo(w):   # ㊳거 끊김이 except Exception 에 먹히지 않고 바퀴까지 올라간다
    def swallow(*a):
        try:
            w.reads(("tmux", "has-session"), 7.0, 20)
        except Exception:   # BaseException(Cut) 은 통과해야 한다
            return
        w.done.append(["swallowed"])
    w.k.close = swallow
    w.round()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w1 b2c — 다음 바퀴 여기부터"] and ["swallowed"] not in w.done, w.done


def c_neo(w):   # ㊳너 report: probe 10개 · 각 2초 → 55초에 끊김 · rep_cursor = 여섯째 · 남은 쪽지는 다음 바퀴 · 마무리(state·ROUND)는 한다
    w.k.accept_only = lambda team, rows: w.wait(44)
    w.k.probe = lambda seat: (w.visits.append(seat), w.reads(("tmux", "capture-pane"), 2.0, 1), "alive")[2]
    seats = {"s%02d#0" % n: {"team": "harness", "since": 0.0} for n in range(1, 11)}
    w.room(open=seats)
    w.round()
    assert w.visits == ["s%02d#0" % n for n in range(1, 7)], w.visits   # 여섯째에서 끊겼다(그 자리에서 섰다)
    assert w.state()["rep_cursor"] == {"seat": "s06#0"}, w.state()
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP - - report — 다음 바퀴 여기부터"], w.k.lines
    assert line(w.k, "ROUND"), w.k.lines


# ── ㊳파 끊김 수렴(순서 5개) ──────────────────────────────────────────────────
def flow(w, steps, cut):
    """그 자리의 호출 순서 — cut 번째 호출 바로 앞에서 예산을 다 써 끊는다(그 자리 전체가 다음 바퀴에 다시 온다)."""
    for index, step in enumerate(steps):
        if cut == index:
            left = w.k.left()
            w.t += max((left or 0.0) - 5.0, 0.0)   # 남은 몫 5초 = 쓰기 시작 0(R2)
            cut = None
        w.k.call(["bash", "tool", step])   # 쓰기 = 자기 상한 7초
        w.done.append(("step", step))
    w.k.notify("t1", "flow", "[긴급] 그 자리 끝")   # 지문 = flow(재실행해도 1통 · 쪽지 중복 0)


def converge(w, steps, where):
    """순서 1개 × 끊은 자리 전부 — 끝 = 같은 일 집합 · 쪽지 1통(지문)·R9 수렴 표의 한 줄."""
    where(w, steps, -1)   # 끊기지 않은 실행 = 기준
    w.round()
    base = {d for d in w.done if d[0] == "step"}
    assert base == {("step", x) for x in steps}, w.done
    table = []
    for cut in range(len(steps)):
        w2 = Rig(Path(w.root.parent) / ("cut" + str(cut)))   # 이 사례만의 임시 루트
        w2.teams, w2.works = w.teams, w.works
        where(w2, steps, cut)
        rounds = 0
        while rounds < 4:   # 뒤 바퀴들
            w2.round()
            rounds += 1
            if "cursor" not in w2.state():
                break
        got = {d for d in w2.done if d[0] == "step"}
        assert got == base and rounds <= 4, (cut, got, base)
        assert len([c for c in w2.sent() if "ft2-keeper" in c]) == 1, w2.sent()   # 쪽지 중복 0
        table.append((cut, len(got), rounds))
    return {tuple(s for s in steps)}, table


def _stage(kind):
    """그 자리(닫기·깨움·재배정·쉼·fill)에 순서를 꽂는 함수 — where(w, steps, cut) 모양."""
    def where(w, steps, cut):
        pending = {"cut": cut}   # 끊김은 첫 바퀴에서 한 번만(뒤 바퀴는 이어서 끝까지 간다)

        def run(*a):
            cut_now, pending["cut"] = pending["cut"], -1   # 끊겨도 다음 바퀴는 안 끊긴다
            flow(w, steps, cut_now)
            return "WORKING" if kind == "park" else None
        if kind == "close":
            w.k.close = lambda *a: run()
        elif kind in ("wake", "reassign"):   # 착지 밖 = stall 칸에서 그 순서를 돈다
            w.k.complete, w.k.settle_nano = (lambda *a: False), (lambda *a: "WORKING")
            w.k.stall = types.SimpleNamespace(check=lambda *a: run())
        elif kind == "park":
            w.k.complete = lambda *a: False
            w.k.settle_nano = lambda *a: (run(), "WORKING")[1]
            w.k.stall = types.SimpleNamespace(check=lambda *a: None)
        else:
            w.mod.Keeper.__init__.__globals__["closing"].keeper_next.fill = lambda k, team: run()
    return where


def c_pa1(w):   # ㊳파-닫기 probe → kill-session → receipt
    converge(w, ["probe", "kill-session", "receipt"], _stage("close"))


def c_pa2(w):   # ㊳파-깨움 capture-pane → send-keys
    converge(w, ["capture-pane", "send-keys"], _stage("wake"))


def c_pa3(w):   # ㊳파-재배정 launch → record
    converge(w, ["launch", "record"], _stage("reassign"))


def c_pa4(w):   # ㊳파-쉼 park → released
    converge(w, ["park", "released"], _stage("park"))


def c_pa5(w):   # ㊳파-fill pick → submit → assign
    converge(w, ["pick", "submit", "assign"], _stage("fill"))


# ── ㊴ 꽉 참 알림(전2) ────────────────────────────────────────────────────────
def c_s1(w):   # ㊴가 바퀴 안 full_alert 바깥 호출 0 · alert_out 2줄 · report 머리에서 1통만 시도 · 둘째 0 · wall ≤ 60
    w.k.start, w.k.sect = w.t, w.mod.REPORT_S
    w.k.fa.observe(w.root, "남은 일", "t1", 9, 8)   # 받는 곳 2(팀 master ≠ harness master) = alert_out 2줄
    assert [(r["to"], r["sig"]) for r in w.k.state["alert_out"]] == [("M-t1", "남은 일|t1"), ("M-harness", "남은 일|t1")], w.k.state
    assert w.calls == [], w.calls   # 보내기 = report 구획 몫
    w.plan = lambda argv, timeout: (7.0, "T" if "send" in argv else 0, "")
    w.k.alerts()
    assert len(w.sent()) == 1 and [r["tries"] for r in w.k.state["alert_out"]] == [0, 1], w.k.state
    assert [r["to"] for r in w.k.state["alert_out"]] == ["M-harness", "M-t1"], w.k.state   # 끊긴 줄은 뒤로


def c_s2(w):   # ㊴나 3줄 · 첫 rc 0 · 둘째 rc 1 · 셋째 rc 0 → 앞·뒤 지움 + FULL-ALERT 2줄 · 둘째는 3회 뒤 판정 불가 + jsonl
    w.k.start, w.k.sect = w.t, w.mod.REPORT_S
    w.k.state["alert_out"] = [{"to": to, "body": "글 " + to, "sig": "s|" + to, "tries": 0, "mark": ""} for to in ("A", "B", "C")]
    rows = w.k.state["alert_out"]
    assert len(rows) == 3 and all(r["tries"] == 0 for r in rows), rows
    w.plan = lambda argv, timeout: (7.0, 1 if "send" in argv and argv[3] == "B" else 0, "")
    for _ in range(5):   # 바퀴마다 1줄 1회 시도
        w.k.start = w.t
        w.k.alerts()
    assert len(line(w.k, "FULL-ALERT")) == 2 and len(w.k.state["alert_out"]) == 0, (w.k.lines, w.k.state)
    assert line(w.k, "판정 불가") == ["판정 불가 꽉 참 알림 3회 실패 B"], w.k.lines
    log = w.root / ".fable-team" / "state" / "ft2-full-alert.jsonl"
    assert log.exists() and len(log.read_text(encoding="utf-8").splitlines()) == 1, log


def c_s3(w):   # ㊴다 꽉 참 알림을 넣은 바퀴가 업무 구획에서 끊김 → alert_out 은 state 저장에 들어 있다 · 같은 서명 중복 0
    w.k.close = lambda *a: (w.k.fa.observe(w.root, "keeper 바퀴", "keeper", 89, 60), w.reads(("tmux", "has-session"), 7.0, 20))[1]
    w.round()
    assert line(w.k, "ROUND-CAP") and len(line(w.k, "FULL-ALERT")) == 1, w.k.lines   # 끊긴 바퀴의 알림도 report 구획에서 나간다
    assert [r["sig"] for r in w.state()["alert_out"]] == ["keeper 바퀴|keeper"], w.state()   # 마무리 state 저장에 들어 있다
    w.k = _next(w)
    w.round()
    assert len(line(w.k, "FULL-ALERT")) == 1 and w.state()["alert_out"] == [], w.state()   # 다음 바퀴 report 에서 나감


def c_s4(w):   # ㊴라 긴 쓰기(25초) 직전 남은 몫 24초 = 시작 0 / 26초 = 시작해 끝낸다(wall ≤ 45)
    w.k.start, w.k.sect = w.t - 10.0, 34.0   # 남은 몫 24초(20초 규칙과 따로 선다)
    with pytest.raises(BaseException) as got:
        w.k.call(["bash", "launch.py", "--x"], 25)
    assert type(got.value).__name__ == "Cut" and w.calls == [], w.calls
    w.k.start, w.k.sect = w.t - 8.0, 34.0
    w.plan = lambda argv, timeout: (24.0, 0, "")
    assert w.k.call(["bash", "launch.py", "--x"], 25)[0] == 0 and len(w.calls) == 1, w.calls
    assert w.t <= 45.0


def c_s5(w):   # ㊴마 판독 목록 밖 새 호출(자기 상한 7초) 직전 남은 몫 5초 → 쓰기로 본다 = 시작 0(5초로 줄여 돌리지 않는다)
    w.k.start, w.k.sect = w.t - 40.0, 45.0
    with pytest.raises(BaseException) as got:
        w.k.call(["어떤-도구", "x"], 7)
    assert type(got.value).__name__ == "Cut" and w.calls == [], w.calls


def c_s6(w):   # ㊴바 AST — 기다리는 바깥 호출 = keeper.py 문 1줄 · Popen = 2줄(keeper_launch·keeper_fetch) · full_alert 는 기본 손 1줄
    reach = ("keeper.py", "keeper_land.py", "keeper_close.py", "keeper_next.py", "keeper_report.py", "keeper_stall.py",
             "keeper_settle.py", "keeper_endings.py", "keeper_hold.py", "keeper_fetch.py", "keeper_launch.py", "full_alert.py")   # R13 keeper 바퀴에서 닿는 파일
    wait, popen = {}, {}
    for path in sorted(p for p in PI.glob("*.py") if p.name in reach):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            name = getattr(node.func, "attr", getattr(node.func, "id", ""))
            root = getattr(getattr(node.func, "value", None), "id", "")
            if root == "subprocess" and name in ("run", "call", "check_output"):
                wait.setdefault(path.name, []).append(node.lineno)
            elif root == "subprocess" and name == "Popen":
                popen.setdefault(path.name, []).append(node.lineno)
            elif root == "os" and name in ("system", "popen") or name == "urlopen":
                wait.setdefault(path.name, []).append(node.lineno)
    assert list(wait) == ["full_alert.py", "keeper.py"], wait   # keeper.py = 문 1줄 · full_alert.py = Slack 수신기 기본 손
    assert len(wait["keeper.py"]) == 1 and list(popen) == ["keeper_fetch.py", "keeper_launch.py"], (wait, popen)
    hand = PI.joinpath("keeper.py").read_text(encoding="utf-8")
    assert hand.count("send=self.k.alert_hand(") == 3 and "self.fa = _Alert(self)" in hand   # keeper 는 자기 손을 꽂는다


def c_s7(w):   # ㊴사 끊긴 3바퀴(wall 50초) = 꽉 참 0통 · wall 61초 = 1통 · 다음 정상 바퀴 = 풀림 1통
    w.teams = ["t1", "t2", "t3", "t4"]
    w.works = {team: ["w" + team[1:]] for team in w.teams}   # 커서가 팀을 하나씩 넘어간다 = 세 바퀴 모두 끊긴다
    for _ in range(3):
        w.k = _next(w)
        w.k.accept_only = lambda team, rows: w.wait(50)   # 첫 팀이 예산을 다 쓴다 = 둘째 팀 앞에서 끊김
        w.k.lines[:] = []
        w.round()
        assert line(w.k, "ROUND-CAP") and w.state().get("alert_out", []) == [], (w.k.lines, w.state())
    w.k = _next(w)
    w.k.accept_only = lambda team, rows: w.wait(61)
    w.k.lines[:] = []
    w.round()
    assert [r["sig"] for r in w.state()["alert_out"]] == ["keeper 바퀴|keeper"], w.state()
    w.k = _next(w)
    w.k.accept_only = lambda team, rows: w.wait(1)
    w.k.lines[:] = []
    w.round()
    assert [r["sig"] for r in w.state()["alert_out"]] == ["keeper 바퀴|keeper"] and "풀림" in w.state()["alert_out"][0]["body"], w.state()


# ── ㊷ 동결 반례 F1~F5(수신자 순환) ───────────────────────────────────────────
def _alerts(w, plan, times=1, fresh=True):
    out = []
    for _ in range(times):
        w.plan = plan
        w.k.state.update(w.state())   # keeper 가 다시 떠도 state 그대로 잇는다(R12·F4)
        if fresh:
            w.k.start, w.k.sect = w.t, w.mod.REPORT_S
        before = len(w.sent())
        w.k.alerts()
        out.append(len(w.sent()) - before)
    return out


def c_f1(w):   # ㊷가 A 는 매번 7초 시간 초과 · B 는 바로 rc 0 → 1바퀴 A 1회 · 2바퀴 B 발신 · 3바퀴 A tries 3 = 판정 불가 · B 영구 발신 0 아님
    w.k.state["alert_out"] = [{"to": "A", "body": "글 A", "sig": "s|A", "tries": 0, "mark": ""},
                              {"to": "B", "body": "글 B", "sig": "s|B", "tries": 0, "mark": ""}]
    def plan(argv, timeout):   # A 만 매번 시간 초과
        return (7.0, "T" if "send" in argv and argv[3] == "A" else 0, "")
    assert _alerts(w, plan, 1) == [1] and [r["to"] for r in w.k.state["alert_out"]] == ["B", "A"], w.k.state
    assert w.k.state["alert_out"][1]["tries"] == 1, w.k.state
    assert _alerts(w, plan, 1) == [1] and [r["to"] for r in w.k.state["alert_out"]] == ["A"], w.k.state   # B 나감
    assert line(w.k, "FULL-ALERT") == ["FULL-ALERT B 글 B"], w.k.lines
    assert _alerts(w, plan, 1) == [1] and w.k.state["alert_out"][0]["tries"] == 2, w.k.state   # A 두 번째
    assert _alerts(w, plan, 1) == [1] and w.k.state["alert_out"] == [], w.k.state              # 세 번째 = 지움
    assert line(w.k, "판정 불가") == ["판정 불가 꽉 참 알림 3회 실패 A"], w.k.lines


def c_f2(w):   # ㊷나 A 7초 시간 초과 · 글이 경계보다 큰 seq 로 이미 닿아 있음 = 그 자리에서 성공 처리(tries 0) / 다음 바퀴 앞 도착 = mark 로 확인
    w.k.state["alert_out"] = [{"to": "A", "body": "글 A", "sig": "s|A", "tries": 0, "mark": ""}]
    w.ledger((1, "A", "다른 글"))

    def plan(argv, timeout):
        w.ledger((2, "A", "글 A"))   # 보내는 사이에 닿았다
        return (7.0, "T" if "send" in argv else 0, "")
    assert _alerts(w, plan, 1) == [1] and w.k.state["alert_out"] == [], w.k.state
    assert line(w.k, "FULL-ALERT") == ["FULL-ALERT A 글 A (도착 확인 · rc None)"], w.k.lines
    assert w.k.state["alert_out"] == []   # tries 0 그대로(지움)
    w.k.lines[:] = []
    w.k.state["alert_out"] = [{"to": "A", "body": "글 A", "sig": "s|A", "tries": 1, "mark": 1}]
    w.ledger((2, "A", "글 A"))
    assert _alerts(w, lambda argv, timeout: (7.0, 0, ""), 1) == [0], w.k.state   # 다시 보내기 0
    assert w.k.state["alert_out"] == [] and line(w.k, "FULL-ALERT") == ["FULL-ALERT A 글 A (도착 확인 · rc -)"], w.k.lines


def c_f3(w):   # ㊷다 report 머리 남은 몫 5초 → send 0 · tries 0 · 순서·mark 그대로 · 다음 바퀴(10초)에 첫 줄부터
    w.k.state["alert_out"] = [{"to": "A", "body": "글 A", "sig": "s|A", "tries": 0, "mark": ""},
                              {"to": "B", "body": "글 B", "sig": "s|B", "tries": 0, "mark": ""}]
    w.k.start, w.k.sect, w.t = 0.0, 55.0, 50.0   # 남은 몫 5초
    assert _alerts(w, lambda argv, timeout: (7.0, 0, ""), 1, False) == [0], w.sent()
    assert [(r["to"], r["tries"], r["mark"]) for r in w.k.state["alert_out"]] == [("A", 0, ""), ("B", 0, "")], w.k.state
    w.k.start, w.k.sect, w.t = 100.0, 155.0, 145.0   # 다음 바퀴 남은 몫 10초
    assert _alerts(w, lambda argv, timeout: (7.0, 0, ""), 1, False) == [1] and w.k.state["alert_out"][0]["to"] == "B", w.k.state


def c_f4(w):   # ㊷라 1바퀴 뒤 state 를 저장하고 keeper 를 새로 만든다 → B 부터 · A tries 1 · mark 그대로
    w.k.state["alert_out"] = [{"to": "A", "body": "글 A", "sig": "s|A", "tries": 0, "mark": ""},
                              {"to": "B", "body": "글 B", "sig": "s|B", "tries": 0, "mark": ""}]
    def plan(argv, timeout):
        return (7.0, "T" if "send" in argv else 0, "")
    _alerts(w, plan, 1)
    w.room(**{k: v for k, v in w.k.state.items()})
    w.k = _next(w)
    assert [r["to"] for r in w.state()["alert_out"]] == ["B", "A"] and w.state()["alert_out"][1]["tries"] == 1, w.state()
    assert _alerts(w, plan, 1) == [1] and w.k.state["alert_out"][0]["to"] == "A", w.k.state   # B 부터 = A 가 남는다


def c_f5(w):   # ㊷마 3곳 모두 시간 초과 → 9바퀴 안에 세 줄 모두 tries 3 · 판정 불가 3줄 · jsonl 3줄 · FULL-ALERT 0 · send 합 9
    w.k.state["alert_out"] = [{"to": to, "body": "글 " + to, "sig": "s|" + to, "tries": 0, "mark": ""} for to in ("A", "B", "C")]
    rounds = 0
    while w.k.state["alert_out"] and rounds < 9:
        assert _alerts(w, lambda argv, timeout: (7.0, "T" if "send" in argv else 0, ""), 1) == [1]
        rounds += 1
    log = w.root / ".fable-team" / "state" / "ft2-full-alert.jsonl"
    assert rounds == 9 and len(w.k.state["alert_out"]) == 0, w.k.state
    assert len(line(w.k, "판정 불가")) == 3 and len(line(w.k, "FULL-ALERT")) == 0, w.k.lines
    assert len(log.read_text(encoding="utf-8").splitlines()) == 3 and len(w.sent()) == 9, w.sent()


CASES = {"㊳가": c_ga, "㊳나": c_na, "㊳다": c_da, "㊳라": c_ra, "㊳마": c_ma, "㊳바": c_ba, "㊳사": c_sa,
         "㊳아": c_a, "㊳자": c_ja, "㊳차": c_cha, "㊳타": c_ta, "㊳하": c_ha, "㊳거": c_geo, "㊳너": c_neo,
         "㊴가": c_s1, "㊴나": c_s2, "㊴다": c_s3, "㊴라": c_s4, "㊴마": c_s5, "㊴바": c_s6, "㊴사": c_s7,
         "㊳파-닫기": c_pa1, "㊳파-깨움": c_pa2, "㊳파-재배정": c_pa3, "㊳파-쉼": c_pa4, "㊳파-fill": c_pa5,
         "㊷가": c_f1, "㊷나": c_f2, "㊷다": c_f3, "㊷라": c_f4, "㊷마": c_f5}
KP, KR = "adapters/pi/keeper.py", "adapters/pi/keeper_report.py"
MUTANTS = {
    "M72": (KP, "shrunk, timeout = left < timeout, min(timeout, left)", "shrunk, timeout = False, timeout", ("㊳가", "㊳타")),
    "M73": (KP, "            elif left < timeout or (timeout > CALL_S and time.monotonic() - self.start > LONG_S):   # R2 쓰기 = 시작 0",
            "            elif False:", ("㊳아",)),
    "M74": (KP, '{"team": team, "work": work, "stage": stage, "cuts": cuts}', '{"team": team, "work": "-", "stage": "b1", "cuts": cuts}',
            ("㊳나", "㊳사")),
    "M75": (KP, "        if cuts >= 2:   # R5 — 같은 자리 2바퀴 연속 = 그 자리를 건너뛴다", "        if False:", ("㊳하",)),
    "M76": (KP, "GIT_S, CALL_S, ROUND_S, STALE_S, FETCH_S = 7, 7, 60, 600, 7", "GIT_S, CALL_S, ROUND_S, STALE_S, FETCH_S = 25, 7, 60, 600, 7",
            ("㊳바",)),
    "M77": (KR, "            self.send_stop = self.send_fails >= SEND_FAILS", "            self.send_stop = False", ("㊳마",)),
    "M78": (KP, "class Cut(BaseException):", "class Cut(Exception):", ("㊳거",)),
    "M79": (KP, "        self.sect = REPORT_S   # R1 report 구획(45~55초)", "        self.sect = TAIL_S", ("㊳너",)),
    "M80": (KP, "        self.fa = _Alert(self)", "        self.fa = full_alert", ("㊴가", "㊴바")),
    "M81": (KR, '        if rc == 0 or self.arrived(self.tail_rows(), mark, to, body, "ft2-full-alert") == "있음":', "        if True:",
            ("㊴나",)),
    "M82": (KP, "            elif left < timeout or (timeout > CALL_S and time.monotonic() - self.start > LONG_S):   # R2 쓰기 = 시작 0",
            "            elif left < CALL_S or (timeout > CALL_S and time.monotonic() - self.start > LONG_S):", ("㊴라",)),
    "M83": (KP, '        return "peek" in rest and self.mbox in argv   # mbox peek = 우편함 장부 읽기', "        return True", ("㊴마",)),
    "M84": (KP, 'self.fa.observe(self.root, "keeper 바퀴", "keeper", int(wall), ROUND_S)',
            'self.fa.observe(self.root, "keeper 바퀴", "keeper", ROUND_S if self.cut != "-" else int(wall), ROUND_S)', ("㊴사",)),
    "M94": (KR, '        self.state["alert_out"] = [r for r in rows if r.get("to") != to] + mine', '        self.state["alert_out"] = rows',
            ("㊷가", "㊷라")),
    "M95": (KR, '        row["tries"] = int(row.get("tries") or 0) + 1', '        row["tries"] = int(row.get("tries") or 0)', ("㊷가", "㊷마")),
    "M96": (KR, "        if self.stopping():   # R12 ⑧ 지손 전에 미룸 = tries 0 · 순서 그대로 · mark 그대로\n            return",
            '        if self.stopping():\n            row["tries"] = int(row.get("tries") or 0) + 1\n            return', ("㊷다",)),
    "M97": (KR, '        if mark and self.arrived(self.tail_rows(), mark, to, body, "ft2-full-alert") == "있음":', "        if False:", ("㊷나",)),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Rig(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    (tmp_path / "w1").mkdir()
    try:   # 변이 세계 = 판정 줄이 달라지거나(AssertionError) 값이 없거나(KeyError) 심사가 선다
        CASES[cases[0]](Rig(tmp_path / "w1", tree))
    except BaseException:   # noqa: BLE001 — 어떤 실패든 변이를 잡은 것
        pass
    else:
        pytest.fail("변이 %s 를 사례 %s 가 잡지 못했다" % (name, cases[0]))
    for case in cases[1:]:   # 같은 변이의 다른 사례 = 원본 나무로 PASS(대조)
        (tmp_path / ("w" + case)).mkdir()
        CASES[case](Rig(tmp_path / ("w" + case)))
