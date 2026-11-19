"""ft2 keeper 팀 몫 상한 — 한 팀이 업무 몫 절반을 넘으면 그 자리에서 멈추고 다음 팀으로 (반례 ①~⑧ · 변이 M1~M4).

카드 r2323-keeper-team-share-cap · 계약 T1(팀 몫 상한 = TEAM-CAP 1줄 · 남은 몫으로 다음 팀) ·
T2(팀 자리 기억 = state team_cursor · 바퀴 cursor 는 다음 팀 머리 · 감아 돌기 0 · 끝까지 돌면 지움) ·
T3(바퀴 cursor 는 R2 끊긴 자리 우선 · cell_total 은 before() 를 따름) · T4(혼자 남은 팀 = 상한 0 · 판정 규칙·단계 순서 그대로).

대역(카드 «시험 입력»): test_keeper_round_60s.Rig 그대로 — 임시 루트 · 주입 시계 · 가짜 호출 · 가짜 팀 3개 · 칸 초 = 판독 1회 초 ·
sleep 0 · 네트워크 0 · 실 runtime·실 tmux·실 명부 읽기 0. 팀 t1·t2·t3 = A·B·C.

⑦(회귀) = ft2 keeper 시험 전부를 기준판(base)과 견줘 실패 이름 diff 0 — 그중 바퀴 판정에 가장 가까운 두 파일
(test_keeper_round_60s · test_keeper_round_cells)을 사례 7 이 그 자리에서 돌린다. 나머지 파일 대조는 가지 밖 실행(보고에 이름·결과).
"""
import json
import shutil
import subprocess
import sys

import pytest

from test_keeper_round_60s import FT2, KP, Rig, field, line

BRANCH = "nano/r2323-keeper-team-share-cap"
CAP = "TEAM-CAP"


def _world(w, cost, works):
    """팀마다 work 수 · 칸 초 — landing 안 판독 1회가 그 초만큼 간다(주입 시계 · 남은 몫보다 길면 그 자리에서 Cut)."""
    w.teams = sorted(cost)
    w.works = {t: ["w%02d" % (n + 1) for n in range(works[t])] for t in w.teams}   # 이름 = keeper 의 sorted() 차례대로(w01 … w10)
    w.cost = dict(cost)

    def landing(team, work):
        w.done.append(["land", team, work])
        w.reads(("tmux", "has-session"), w.cost[team])
        return ("ab" * 20, "main", "")
    w.k.landing = landing


def _next(w):
    """다음 바퀴 — 줄·기록을 비우고 1바퀴(같은 Keeper · state 는 state.json 그대로)."""
    w.k.lines[:] = []
    w.done[:] = []
    w.round()
    return w.done


def _lands(w, team):
    return [row[2] for row in w.done if row[0] == "land" and row[1] == team]


def _state(w):
    path = w.root / ".fable-team" / "state" / "ft2-keeper" / "state.json"
    return json.loads(path.read_text(encoding="utf-8"))


# ── T1 팀 몫 상한 ────────────────────────────────────────────────────────────
def c_1(w):   # ① A(work 10 · 칸 4초) → 6칸 끝 24초 · 7칸째 앞 TEAM-CAP 1줄 · B·C 차례 돈다(기준판 = A 에서 바퀴 끊김 · B·C 0 → Red)
    _world(w, {"t1": 4.0, "t2": 1.0, "t3": 1.0}, {"t1": 10, "t2": 3, "t3": 3})
    w.round()
    assert line(w.k, CAP) == ["TEAM-CAP t1 w07 b1 s=24 — 다음 팀"], w.k.lines
    assert _lands(w, "t1") == ["w01", "w02", "w03", "w04", "w05", "w06"], w.done
    assert _lands(w, "t2") == ["w01", "w02", "w03"] and _lands(w, "t3") == ["w01", "w02", "w03"], w.done   # 뒤 팀 = 굶지 않는다


def c_2(w):   # ② ① 뒤 = 바퀴 cursor B 머리 · 다음 바퀴 B·C 만(A 0) · 그다음 바퀴 A 는 7칸째부터 · 다 돌면 team_cursor 지움 · items/total 같음
    c_1(w)
    assert _state(w)["team_cursor"] == {"t1": {"work": "w07", "stage": "b1"}}, _state(w)
    assert _state(w)["cursor"] == {"team": "t2", "work": "-", "stage": "b1", "cuts": 0}, _state(w)   # 멈춘 팀 자리 아님 = 다음 팀 머리
    _next(w)
    assert line(w.k, CAP) == [] and line(w.k, "ROUND-CAP") == [], w.k.lines
    assert _lands(w, "t1") == [] and _lands(w, "t2") == ["w01", "w02", "w03"], w.done   # A 0
    assert "cursor" not in _state(w), _state(w)   # 바퀴를 다 돌면 cursor 를 지운다
    _next(w)   # 3바퀴 = 앞부터 · A 는 7칸째부터
    assert _lands(w, "t1") == ["w07", "w08", "w09", "w10"], w.done
    ran, can = field(w.k, "items").split("/")   # 분모가 A 1~6칸을 뺐다(이 바퀴에 돌 수 있는 자리 = 돈 자리)
    assert ran == can, w.k.lines
    assert "t1" not in (_state(w).get("team_cursor") or {}), _state(w)   # 끝까지 돌면 자리 지움


def c_3(w):   # ③ 팀 1개뿐(A) → 상한 0 · 지금처럼 바퀴 몫 끝에서 cut
    _world(w, {"t1": 4.0}, {"t1": 12})
    w.round()
    assert line(w.k, CAP) == [], w.k.lines
    assert "team_cursor" not in _state(w), _state(w)
    assert _state(w)["cursor"] == {"team": "t1", "work": "w12", "stage": "b1", "cuts": 1}, _state(w)
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t1 w12 b1 — 다음 바퀴 여기부터"], w.k.lines


def c_4(w):   # ④ A 가 몫 절반 안에 끝남 → TEAM-CAP 0 · team_cursor 0
    _world(w, {"t1": 4.0, "t2": 1.0}, {"t1": 3, "t2": 2})
    w.round()
    assert line(w.k, CAP) == [], w.k.lines
    assert not (_state(w).get("team_cursor") or {}), _state(w)
    assert "cursor" not in _state(w), _state(w)
    assert _lands(w, "t1") == ["w01", "w02", "w03"] and _lands(w, "t2") == ["w01", "w02"], w.done


def c_5(w):   # ⑤ A 멈춘 뒤 B 도 절반 넘음 · C 남음 → B 도 TEAM-CAP · C 돈다
    # 한 바퀴 업무 몫 45초 = 22.5×2 라 같은 바퀴에 두 번 상한이 서면 C 몫이 0 이 된다(⑥)·그래서 1바퀴 A · 2바퀴 B 로 나눠 같은 뜻을 세운다
    _world(w, {"t1": 4.0, "t2": 1.0, "t3": 1.0}, {"t1": 10, "t2": 1, "t3": 3})
    w.round()
    assert line(w.k, CAP) == ["TEAM-CAP t1 w07 b1 s=24 — 다음 팀"], w.k.lines
    w.cost["t2"], w.works["t2"] = 6.0, ["w%02d" % (n + 1) for n in range(10)]   # 2바퀴 = B 무거움
    _next(w)
    assert line(w.k, CAP) == ["TEAM-CAP t2 w05 b1 s=24 — 다음 팀"], w.k.lines
    assert _lands(w, "t3") == ["w01", "w02", "w03"], w.done   # C 는 돈다
    assert _state(w)["cursor"] == {"team": "t3", "work": "-", "stage": "b1", "cuts": 0}, _state(w)
    assert sorted(_state(w)["team_cursor"]) == ["t1", "t2"], _state(w)


# ── T3 바퀴 cursor ───────────────────────────────────────────────────────────
def c_6(w):   # ⑥ 남은 몫 < MIN_S → 지금 R2 cut 그대로(TEAM-CAP 0)
    _world(w, {"t1": 4.45, "t2": 4.45, "t3": 1.0}, {"t1": 5, "t2": 5, "t3": 3})
    w.round()
    assert line(w.k, CAP) == [], w.k.lines
    assert _state(w)["cursor"] == {"team": "t3", "work": "-", "stage": "b1", "cuts": 1}, _state(w)
    assert line(w.k, "ROUND-CAP") == ["ROUND-CAP t3 - b1 — 다음 바퀴 여기부터"], w.k.lines


def c_8(w):   # ⑧ 한 바퀴에 A TEAM-CAP 뒤 C 에서 R2 cut → 바퀴 cursor = C 끊긴 자리 · team_cursor[A] 그대로
    _world(w, {"t1": 4.0, "t2": 1.0, "t3": 4.0}, {"t1": 10, "t2": 1, "t3": 10})
    w.round()
    assert line(w.k, CAP) == ["TEAM-CAP t1 w07 b1 s=24 — 다음 팀"], w.k.lines
    assert _state(w)["cursor"] == {"team": "t3", "work": "w06", "stage": "b1", "cuts": 1}, _state(w)
    assert _state(w)["team_cursor"] == {"t1": {"work": "w07", "stage": "b1"}}, _state(w)


# ── ⑦ 회귀 · T4 불변 ─────────────────────────────────────────────────────────
def c_7(w):   # ⑦ keeper 시험 전부 = 기준판과 실패 이름 diff 0 — 그 자리에서 바퀴 판정 두 파일을 돌린다(실패 = 이름이 그대로 실패)
    got = subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "test_keeper_round_60s.py", "test_keeper_round_cells.py"],
                         cwd=str(FT2 / "tests"), capture_output=True, text=True, timeout=70)
    assert got.returncode == 0, got.stdout[-1500:] + got.stderr[-800:]


# ── 사례·변이 ────────────────────────────────────────────────────────────────
CASES = {"1": c_1, "2": c_2, "3": c_3, "4": c_4, "5": c_5, "6": c_6, "7": c_7, "8": c_8}

GUARD = "        if not nxt or spent < WORK_S / 2:"
MEMO = '        self.state.setdefault("team_cursor", {})[team] = {"work": work, "stage": stage}'
CURSOR = '        self.state["cursor"] = {"team": nxt[0], "work": "-", "stage": "b1", "cuts": 0}'
# 변이 = (파일, [(옛 글, 새 글)], 잡히는 사례) · 둘째 사례부터 = 원본 나무로 같은 사례(대조)
MUTANTS = {
    "M1": (KP, [(GUARD, "        if not nxt:")], ("1", "1")),   # 상한 비교 지움
    "M2": (KP, [(MEMO, "        pass")], ("2", "2")),   # team_cursor 기억 지움
    "M3": (KP, [('nxt = self.order[self.order.index(team) + 1:]', 'nxt = self.order[self.order.index(team) + 1:] or self.order[:1]')], ("3", "3")),   # «뒤 팀 1개 이상» 조건 지움(감아 돌기)
    "M4": (KP, [(CURSOR, '        self.state["cursor"] = {"team": team, "work": work, "stage": "b1", "cuts": 0}')], ("2", "2")),   # 멈춘 팀 자리로
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


def test_branch_diff(tmp_path):   # 가지 diff = keeper.py · 이 시험 (가지 밖에서는 건너뜀 · git 읽기만)
    def git(*args):
        return subprocess.run(["git", *args], cwd=FT2, capture_output=True, text=True, timeout=7).stdout.strip()
    if git("rev-parse", "--abbrev-ref", "HEAD") != BRANCH:
        pytest.skip("가지 %s 밖" % BRANCH)
    base = git("merge-base", "HEAD", "origin/main")
    names = set(git("diff", "--name-only", base).splitlines()) | set(git("ls-files", "--others", "--exclude-standard", ".").splitlines())
    want = {"adapters/pi/keeper.py", "tests/test_keeper_team_share_cap_r2323.py"}
    assert {n.split("/ft2/", 1)[-1] for n in names} <= want, names
