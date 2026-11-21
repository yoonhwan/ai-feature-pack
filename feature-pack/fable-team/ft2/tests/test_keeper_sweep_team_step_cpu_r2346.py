"""r2346 keeper 승계 끝 구 나노 닫기(b3r.sweep) 팀 단계 — 그 초가 어느 단계(latest·intents·target)에서 났는지와
이 프로세스가 실제로 쓴 CPU 초를 팀 단계 SLOW-SEAT 줄 꼬리에 1개로 남긴다(S1·S2 · 예외·return 이어도 finally S3).
ROWS-SLOW 줄에도 load+active 구간 CPU 초를 붙인다(S6). 계약 S1~S6 · 반례 ①~⑩ · 변이 M1~M5(사본에서만 · 변이마다 원본으로 같은 사례 1회 더).
대역 = 가짜 keeper(주입 벽 시계 k.now · 주입 cpu 시계 · 가짜 git·tmux 손 · log 줄 모음) 위 실제 CloseOld +
임시 runtime(r2319 의 journal 나무 그대로) · 실 tmux·실 장부·실 runtime 0 · 네트워크 0 · sleep 0.
기준판(BASE git archive) Red = ① ⑤ ⑨ · 회귀 = r2281 · r2281 mut · r2311(이 파일 밖 · 따로 돌린다).
"""
import importlib.util
import pathlib
import shutil
import types

import pytest

from test_keeper_rows_cache_r2319 import TEAM as RTEAM, full, world

FT2 = pathlib.Path(__file__).resolve().parents[1]
KO, KE = "adapters/pi/keeper_close_old.py", "adapters/pi/keeper_endings.py"
BASE = "a8f0e3f00b24"   # r2344 끝(이 카드 앞) — 기준판 = 꼬리 없음


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── 가짜 keeper — 주입 벽 시계·cpu 시계 · 손마다 비용 · log 줄만 ────────────────
class Cut(BaseException):
    pass


class K:
    MIN_S, tmux, halt = 1, "tmux", False

    def __init__(s, alive=(), cost=None, cut=None, team_list=()):
        s.t, s.c, s.cost, s.cut = 0.0, 0.0, cost or {}, cut
        s.alive, s.state, s.lines, s.kills = set(alive), {}, [], []
        s.clocks, s.cpuclocks, s.team_list = [], [], list(team_list)

    def now(s):   # 주입 벽 시계
        s.clocks.append(s.t)
        return s.t

    def cpu_now(s):   # 주입 cpu 시계
        s.cpuclocks.append(s.c)
        return s.c

    def spend(s, wall, cpu):
        s.t, s.c = s.t + wall, s.c + cpu

    def teams(s):
        return list(s.team_list)

    def alive_sessions(s):
        return set(s.alive)

    def left(s):
        return 1000.0

    def stamp(s):
        return "2026-11-20T01:00:00"

    def log(s, kind, team="", text=""):
        s.lines.append(" ".join(w for w in (kind, team, text) if w))

    def verdict(s, *a):
        s.log("VERDICT", text=" ".join(map(str, a)))
        return True

    def git(s, tree, *args):
        s.spend(*s.cost.get(args[0], (0.0, 0.0)))
        if s.cut == args[0]:
            raise Cut("cut")
        return (0, "", "") if args[0] != "rev-parse" else (0, "h" * 40, "")

    def turn_ended(s, *a):
        return True

    def idle(s, *a):
        return True

    def attached(s, seat):
        return "free"

    def call(s, argv):
        s.kills.append(argv[-1][1:])
        s.alive.discard(argv[-1][1:])
        return 0, "", ""

    def probe(s, seat):
        return "absent" if seat not in s.alive else "alive"


def old(team="ta", n=1):
    return "byz-%s-nano-r9%d-x#1" % (team, n)


def new(team="ta", n=1):
    return "byz-%s-nano-r9%d-x#2" % (team, n)


def sweeper(ft2, k, plan):
    """plan = latest·intents·target 각 (벽, cpu) · works/trees 수 · none(latest None) · hit(좌석 → 후보)."""
    mod = _mod(ft2 / KO, "r2346_ko_%d" % id(k))
    last = {"w%d" % (n + 1): (None, new(k.team_list[0], n + 1)) for n in range(plan.get("works", 2))}
    trees = {"s%d" % (n + 1): ("w1", {}) for n in range(plan.get("trees", 3))}

    def latest(kk, team):
        kk.spend(*plan.get("latest", (0.0, 0.0)))
        return None if plan.get("none") else last
    mod.endings = types.SimpleNamespace(latest=latest)
    try:
        co = mod.CloseOld(k, cpu=k.cpu_now)   # r2346 주입 cpu 시계
    except TypeError:   # 기준판(이 카드 앞) = cpu 시계 인자 없음
        co = mod.CloseOld(k)

    def intents(team):
        if plan.get("boom") == "intents":
            raise RuntimeError("intents 판독 실패")
        k.spend(*plan.get("intents", (0.0, 0.0)))
        return trees
    co.intents = intents

    def target(team, seat, alive, last_, trees_):
        k.spend(*plan.get("target", (0.0, 0.0)))
        return plan.get("hit", {}).get(seat)
    co.target = target
    co.resume = lambda seat, nw, intent: ""
    return co


def team_lines(k):
    return [x for x in k.lines if x.startswith("SLOW-SEAT")]


def hit_of(seat, nw):
    return ("w1", nw, {"worktree": "/t/" + seat}, {"worktree": "/t/" + nw})


# ── S1·S2 반례 ①~⑧ ─────────────────────────────────────────────────────────
def c1(tmp, mp, ft2=FT2):   # ① 팀 6초(4 + 0.5 + target 3회 1.5) → parts 세 칸 · cpu 합 · n · 새 재기 시계 = 벽 10 · cpu 10
    k = K([old("ta", n) for n in (1, 2, 3)], team_list=["ta"])
    sweeper(ft2, k, {"latest": (4.0, 0.50), "intents": (0.5, 0.25), "target": (0.5, 0.03)}).sweep()
    assert team_lines(k) == ["SLOW-SEAT ta - s=6 step=sweep:team parts=latest:4.00/0.50,intents:0.50/0.25,"
                             "target:1.50/0.09 cpu=0.84 n=work:2,intent:3,alive:3"], k.lines
    assert len(k.cpuclocks) == 10, len(k.cpuclocks)   # 2×(2+3) — 새 재기만
    assert len(k.clocks) == 12, len(k.clocks)         # 새 재기 10 + team() 기존 at·rest 2


def c2(tmp, mp, ft2=FT2):   # ② 팀 3.75초(문턱 밑) → 줄 0(지금 그대로)
    k = K([old()], team_list=["ta"])
    sweeper(ft2, k, {"latest": (3.75, 0.25)}).sweep()
    assert team_lines(k) == [], k.lines


def c3(tmp, mp, ft2=FT2):   # ③ latest None → «판정 불가» 줄 그대로 · 팀 ≥ 5초면 intents·target «-» · intents 부르지 않음
    k = K([old()], team_list=["ta"])
    sweeper(ft2, k, {"latest": (6.0, 0.25), "none": True, "boom": "intents"}).sweep()
    assert [x for x in k.lines if x.startswith("판정 불가")] == [
        "판정 불가 ta 장부 못 읽음 — 승계 끝 구 나노 닫기 0"], k.lines
    assert team_lines(k) == ["SLOW-SEAT ta - s=6 step=sweep:team parts=latest:6.00/0.25,intents:-,target:-"
                             " cpu=0.25 n=work:-,intent:-,alive:0"], k.lines


def c4(tmp, mp, ft2=FT2):   # ④ intents 예외 → 꼬리 latest 값 · intents·target «-» · 예외는 지금처럼 위로
    k = K([old()], team_list=["ta"])
    co = sweeper(ft2, k, {"latest": (5.0, 0.25), "boom": "intents"})
    with pytest.raises(RuntimeError):
        co.sweep()   # sweep finally = slow_lines → 끊겨도 그때까지 잰 값으로 1줄
    assert team_lines(k) == ["SLOW-SEAT ta - s=5 step=sweep:team parts=latest:5.00/0.25,intents:-,target:-"
                             " cpu=0.25 n=work:2,intent:-,alive:0"], k.lines


def c5(tmp, mp, ft2=FT2):   # ⑤ 벽 30초 · cpu 0.3초(굶음 꼴) → cpu=0.30 그대로(벽 초를 cpu 로 쓰지 않음)
    k = K([old()], team_list=["ta"])
    sweeper(ft2, k, {"latest": (30.0, 0.30)}).sweep()
    assert team_lines(k) == ["SLOW-SEAT ta - s=30 step=sweep:team parts=latest:30.00/0.30,intents:0.00/0.00,"
                             "target:0.00/0.00 cpu=0.30 n=work:2,intent:3,alive:1"], k.lines


def c6(tmp, mp, ft2=FT2):   # ⑥ 좌석 one() 몫(keep git 3초)은 팀 단계 초·parts 에 안 섞임(inner 빼기 그대로)
    k = K([old(), new()], cost={"status": (3.0, 0.25)}, team_list=["ta"])
    hit = {old(): hit_of(old(), new())}
    sweeper(ft2, k, {"latest": (4.75, 0.25), "intents": (0.25, 0.0), "target": (0.25, 0.01), "hit": hit}).sweep()
    assert k.kills == [old()], k.kills
    assert team_lines(k) == ["SLOW-SEAT ta - s=5.5 step=sweep:team parts=latest:4.75/0.25,intents:0.25/0.00,"
                             "target:0.50/0.02 cpu=0.27 n=work:2,intent:3,alive:2"], k.lines


def c7(tmp, mp, ft2=FT2):   # ⑦ 좌석 SLOW-SEAT 줄(step=sweep:keep) 글자 그대로 · 그 팀 단계 줄에만 parts 가 붙는다
    k = K([old(), new()], cost={"status": (6.0, 0.25)}, team_list=["ta"])
    hit = {old(): hit_of(old(), new())}
    sweeper(ft2, k, {"latest": (5.0, 0.10), "target": (0.25, 0.0), "hit": hit}).sweep()
    assert team_lines(k) == ["SLOW-SEAT ta %s s=6 step=sweep:keep" % old(),
                             "SLOW-SEAT ta - s=5.5 step=sweep:team parts=latest:5.00/0.10,intents:0.00/0.00,"
                             "target:0.50/0.00 cpu=0.10 n=work:2,intent:3,alive:2"], k.lines


def c8(tmp, mp, ft2=FT2):   # ⑧ SEAT_CAP 넘침 «외 N» 줄 그대로 · 그 팀 단계 줄 0(inner 가 전부 먹음)
    seats = [old("ta", n) for n in range(1, 8)]
    k = K(seats + [new("ta", n) for n in range(1, 8)], cost={"status": (6.0, 0.0)}, team_list=["ta"])
    hit = {s: hit_of(s, new("ta", n)) for n, s in enumerate(seats, 1)}
    sweeper(ft2, k, {"hit": hit}).sweep()
    assert team_lines(k) == ["SLOW-SEAT ta %s s=6 step=sweep:keep" % s for s in seats[:5]] + ["SLOW-SEAT 외 2"], k.lines


# ── S6 ROWS-SLOW 반례 ⑨⑩ ──────────────────────────────────────────────────
class Clock2:   # 가짜 시계 — monotonic(벽) 과 thread_time(cpu) 두 줄
    def __init__(s, wall, cpu):
        s.w, s.c, s.i, s.j = list(wall), list(cpu), 0, 0

    @staticmethod
    def _take(vals, i):
        return vals[min(i, len(vals) - 1)]

    def monotonic(s):
        v = s._take(s.w, s.i)
        s.i += 1
        return v

    def thread_time(s):
        v = s._take(s.c, s.j)
        s.j += 1
        return v


def c9(tmp, mp, ft2=FT2):   # ⑨ ROWS-SLOW 1.5초 · cpu 0.05초 → 줄 끝 cpu=0.05 · 앞 글자 그대로
    ke, w = _mod(ft2 / KE, "r2346_ke9"), world(tmp / "a")
    assert ke._rows(w.k, RTEAM) == full(w, ke)
    n = len(full(w, ke))
    mp.setattr(ke, "time", Clock2([100.0, 100.0, 100.01, 100.01, 101.51], [50.0, 50.05]))   # r2362 시계 2자리(proj·key) 더
    assert ke._rows(w.k, RTEAM) is not None
    assert w.k.lines == ["ROWS-SLOW %s cache=hit load=0.01 active=1.50 n=%d cpu=0.05 proj=0.00 key=0.01 get=0.00" % (RTEAM, n)], w.k.lines


def c10(tmp, mp, ft2=FT2):   # ⑩ ROWS 0.31초(문턱 밑) → 줄 0 그대로
    ke, w = _mod(ft2 / KE, "r2346_ke10"), world(tmp / "a")
    assert ke._rows(w.k, RTEAM) == full(w, ke)
    mp.setattr(ke, "time", Clock2([200.0, 200.01, 200.31], [60.0, 60.99]))
    assert ke._rows(w.k, RTEAM) is not None and w.k.lines == [], w.k.lines


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8, "⑨": c9, "⑩": c10}


@pytest.mark.parametrize("label", list(CASES))
def test_case(label, tmp_path, monkeypatch):
    CASES[label](tmp_path, monkeypatch)


# ── 변이 M1~M5 (사본에서만 · 원본으로 같은 사례 1회 더) ─────────────────────
MUTANTS = {
    "M1": (KO, "self.tail(parts, cpu, last, trees, calls)", '""', "①"),                      # 꼬리 지움
    "M2": (KO, "self.k, self.cpu_now = keeper, cpu or time.thread_time",
           "self.k, self.cpu_now = keeper, (lambda: keeper.now()) if cpu else time.thread_time", "⑤"),   # cpu 자리에 벽 시계
    "M3": (KO, "        finally:\n            rest = k.now() - at - self.inner\n            if rest >= SEAT_S:\n",
           "        finally:\n            pass\n        rest = k.now() - at - self.inner\n        if rest >= SEAT_S:\n", "④"),
    "M4": (KO, "                hit = self.target(team, seat, alive, last, trees)\n"
                "                t1, c1 = k.now(), self.cpu_now()\n"
                "                calls += 1   # r2346 N = 그 팀에서 target 을 부른 세션 수\n"
                "                parts[\"target\"] = parts.get(\"target\", 0.0) + (t1 - t0)\n"
                "                cpu[\"target\"] = cpu.get(\"target\", 0.0) + (c1 - c0)\n"
                "                if hit:\n                    self.seat(team, seat, alive, hit)\n",
           "                hit = self.target(team, seat, alive, last, trees)\n"
           "                if hit:\n                    self.seat(team, seat, alive, hit)\n"
           "                t1, c1 = k.now(), self.cpu_now()\n"
           "                calls += 1   # r2346 N = 그 팀에서 target 을 부른 세션 수\n"
           "                parts[\"target\"] = parts.get(\"target\", 0.0) + (t1 - t0)\n"
           "                cpu[\"target\"] = cpu.get(\"target\", 0.0) + (c1 - c0)\n", "⑥"),
    "M5": (KE, " n=%d cpu=%.2f\" % (\"hit\" if hit else (\"miss\" if key else \"none\"), t1 - t0, t2 - t1, len(rows), spent)",
           " n=%d\" % (\"hit\" if hit else (\"miss\" if key else \"none\"), t1 - t0, t2 - t1, len(rows))", "⑨"),
}


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    rel, before, after, label = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    path = tree / rel
    text = path.read_text(encoding="utf-8")
    assert text.count(before) == 1, (name, before)
    path.write_text(text.replace(before, after), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w1", monkeypatch, tree)
    CASES[label](tmp_path / "w2", monkeypatch, FT2)   # 원본으로 같은 사례 1회 더 = PASS


# ── 기준판 Red (① ⑤ ⑨) ────────────────────────────────────────────────────
def base_tree(tmp):
    import subprocess
    top = subprocess.run(["git", "-C", str(FT2), "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True, timeout=25, check=True).stdout.strip()
    out = tmp / "base" / "ft2"
    out.mkdir(parents=True)
    tar = subprocess.run(["git", "-C", top, "archive", BASE + ":feature-pack/fable-team/ft2"],
                         capture_output=True, timeout=25, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(out)], input=tar, timeout=25, check=True)
    return out


@pytest.mark.parametrize("label", ["①", "⑤", "⑨"])
def test_base_red(label, tmp_path, monkeypatch):
    ft2 = base_tree(tmp_path)
    with pytest.raises(AssertionError):
        CASES[label](tmp_path / "w", monkeypatch, ft2)
