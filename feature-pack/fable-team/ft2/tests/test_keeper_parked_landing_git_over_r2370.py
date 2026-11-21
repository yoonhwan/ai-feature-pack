"""r2370 ft2 keeper — 쉼 work 착지 판정(parked_landing)도 r2357 git 쉼 창을 쓴다(K1 걸기 · K2 거름 · K3 다른 길 그대로).

카드 r2370-keeper-memo-judge-unknown-landing · 반례 집합(동결) ①~⑧ · 변이 M1~M5 · 계약↔시험 대응표 그대로 1:1.
계약 K1 쉼 창 걸기(①·②·③ / M1·M2) · K2 쉼 중 거름(④·⑤ / M3·M4) · K3 다른 길 그대로(⑥·⑦·⑧ / M5).
기준판(고치기 전 코드) Red = ① · ③ · ④ — test_baseline 이 그 세 칸이 잡히고 ②⑤⑥⑦⑧ 은 통과함을 함께 본다.

대역(카드 «시험 입력»): 임시 루트(tmp_path) · 주입 시계 · 가짜 subprocess.run · 가짜 journal 줄(dispatch · parked idle-done) ·
가짜 landing(부름 기록 · Ungraded/예상 밖 오류/«미도달» 주입) · sleep 0 · 네트워크 0 · 실 git·실 tmux·실 원장 0.
바퀴 사이는 새 Keeper(state.json 만 이어짐 = 실제 `keeper --once` 꼴).
"""
import shutil
from pathlib import Path

import pytest

from test_keeper_round_60s import FT2, KP, Rig, line

GOOD, TEAM = "ab" * 20, "cfo"
GIT8, GIT_COST, REST_S, WHEEL = 8.0, 7.0, 600, 125   # 주입 초 · 실제로 흐르는 초(상한 7초) · 쉼 창 · 바퀴 간격


# ── 대역 ─────────────────────────────────────────────────────────────────────
def hands(w):
    """팀·journal 줄·투영·손 — 바퀴마다 다시 건다(Rig.boot 는 자기 손으로 되돌린다)."""
    w.k.teams = lambda: [TEAM]
    w.k.rows_of = lambda team: (
        [{"kind": "dispatch", "work": name, "attempt": "a1", "holder": "h#0"} for name in w.ws]
        + [{"kind": "parked", "work": name, "attempt": "a1", "reason": "idle-done"} for name in w.ws if name in w.parked]
    )
    w.k.project = lambda root, team: {"result": w.mod.OK, "works": {name: {"done": False} for name in w.ws}}
    w.k.landing = lambda team, work: (w.done.append(["land", team, work]), (GOOD, "main", ""))[1]
    w.k.complete = lambda team, work, attempt, landed: (w.done.append(["complete", team, work]), True)[1]
    w.k.settle_nano = lambda team, work, attempt, dispatched, row, why: (w.done.append(["settle", team, work, why]), "WORKING")[1]


def rig(tmp, works=("W1",), parked=None, tip=False, tree=None):
    """쉼 카드 세계 하나 — works 전부 parked(기본) · tip = rev-parse 가 token 을 준다(tips() 3개가 비지 않는다)."""
    w = Rig(tmp, tree)
    w.ws, w.parked = list(works), set(works if parked is None else parked)
    hands(w)
    if tip:
        plain = w.plan
        w.plan = lambda argv, timeout: (0.0, 0, GOOD) if "rev-parse" in argv else plain(argv, timeout)
    return w


def again(w, seconds, landing=None):
    """다음 바퀴 = 주입 시계 seconds · 새 Keeper(state.json 만 이어진다) · 대역 손 다시 · 반환 = 이 바퀴에 한 일."""
    w.t = seconds
    w.boot()
    hands(w)
    if landing is not None:
        w.k.landing = landing
    start = len(w.done)
    w.round()
    return w.done[start:]


def slow_git(w):
    """로컬 git 판독 1회 — 소요 8초 · 상한 7초라 그 자리에서 끊긴다(Ungraded = «판정 불가 … git 7초 넘음»)."""
    plan = w.plan
    w.plan = lambda argv, timeout: (GIT8, 0, "")
    try:
        w.k.call(["git", "-C", str(w.root), "merge-base", "a", "b"])
    finally:
        w.plan = plan


def slow_landing(w, exc=None):
    """landing 손 — 부름 기록 뒤 git 8초(= Ungraded) 또는 exc(예상 밖 오류)."""
    def landing(team, work):
        w.done.append(["land", team, work])
        if exc is not None:
            raise exc("대역")
        slow_git(w)
        return (GOOD, "main", "")
    return landing


def lands(done):
    return [one[2] for one in done if one[0] == "land"]


def completes(done):
    return [one[2] for one in done if one[0] == "complete"]


def keys(w):
    return w.state().get("git_over") or {}


# ── 사본(기준판·변이) ────────────────────────────────────────────────────────
def copy_tree(tmp):
    out = Path(tmp) / "ft2"
    shutil.copytree(FT2, out, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    return out


def patch(tree, *pairs):
    path, text = Path(tree) / KP, (Path(tree) / KP).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, old
        text = text.replace(old, new)
    path.write_text(text, encoding="utf-8")
    return Path(tree)


HEAD = '        if self.before(team, work, "b1"):   # r2369 K1 커서 앞 쉼 카드 = 이 바퀴 몫 0'
K2 = ('        if self.git_rest(team, work, attempt) is not None:   # r2370 K2 — r2357 쉼 창 안 = landing 0(같은 7초 다시 안 씀)\n'
      "            return None\n")
K1 = "            self.git_rest_set(team, work, attempt)   # r2370 K1 — 쉼 카드도 git 7초 넘김 1회에 r2357 쉼 창(REST_S)\n"
EXC = "        except Exception as exc:   # r2115 A2 꼴 — 그 work 1줄 · 다음 work"
MISS = '            if got[2] == "미도달" and tips:\n                memo[key] = tips'


# ── K1 쉼 창 걸기 ────────────────────────────────────────────────────────────
def c1(tmp, tree=None):   # ① 쉼 W1 landing 이 Ungraded → git_over 키(끊긴 시각 + 600) · GIT-OVER 1줄 · complete 0 (기준판 Red)
    w = rig(tmp, tree=tree)
    w.k.landing = slow_landing(w)
    w.round()
    assert keys(w) == {"cfo|W1@a1": GIT_COST + REST_S}, w.state()
    assert len(line(w.k, "GIT-OVER")) == 1, w.k.lines
    assert completes(w.done) == [], w.done


def c2(tmp, tree=None):   # ② 쉼 W1 landing 이 Exception(Ungraded 아님) → «쉼 착지 내부 오류» 1줄 · git_over 키 0
    w = rig(tmp, tree=tree)
    w.k.landing = slow_landing(w, exc=ValueError)
    w.round()
    assert line(w.k, "판정 불가") == ["판정 불가 cfo W1 쉼 착지 내부 오류 ValueError"], w.k.lines
    assert keys(w) == {} and line(w.k, "GIT-OVER") == [], (w.state(), w.k.lines)


def c3(tmp, tree=None):   # ③ 쉼 W1·W2 를 도는 바퀴에서 tips() 가 끊김(Ungraded) → 둘 다 키 · GIT-OVER 2줄 · landing 0 (기준판 Red)
    w = rig(tmp, works=("W1", "W2"), tree=tree)
    plain = w.plan
    w.plan = lambda argv, timeout: (GIT8, 0, "") if "rev-parse" in argv and "origin/main" in argv else plain(argv, timeout)
    w.round()
    assert keys(w) == {"cfo|W1@a1": GIT_COST + REST_S, "cfo|W2@a1": 2 * GIT_COST + REST_S}, w.state()
    assert len(line(w.k, "GIT-OVER")) == 2 and lands(w.done) == [], (w.k.lines, w.done)


# ── K2 쉼 중 거름 ───────────────────────────────────────────────────────────
def c4(tmp, tree=None):   # ④ ① 뒤 다음 바퀴(시계 +120) → W1 landing 부름 0 · 줄 0 (기준판 Red)
    w = rig(tmp, tree=tree)
    w.k.landing = slow_landing(w)
    w.round()
    done = again(w, WHEEL)
    assert lands(done) == [], done
    assert line(w.k, "GIT-OVER") == [] and line(w.k, "판정 불가") == [], w.k.lines


def c5(tmp, tree=None):   # ⑤ ① 뒤 시계 +601 · 바퀴 끝 sweep 뒤 다음 바퀴 → W1 landing 부름 1 · 키 0
    w = rig(tmp, tree=tree)
    w.k.landing = slow_landing(w)
    w.round()
    done = again(w, int(GIT_COST + REST_S) + 1)   # 608초 > 607초 = 풀림
    assert lands(done) == ["W1"], done
    assert "git_over" not in w.state(), w.state()


# ── K3 다른 길 그대로 ───────────────────────────────────────────────────────
def c6(tmp, tree=None):   # ⑥ 쉼 W2 landing «미도달» · tips 있음 → parked_unreached memo = tips · git_over 키 0(지금 그대로)
    w = rig(tmp, works=("W2",), tip=True, tree=tree)
    w.k.landing = lambda team, work: (w.done.append(["land", team, work]), (GOOD, "main", "미도달"))[1]
    w.round()
    assert w.state()["parked_unreached"] == {"cfo|W2@a1": [GOOD, GOOD]}, w.state()
    assert keys(w) == {} and completes(w.done) == [], (w.state(), w.done)


def c7(tmp, tree=None):   # ⑦ 쉼 W2 landing 착지 → complete 1회 · git_over 키 0
    w = rig(tmp, works=("W2",), tree=tree)
    w.round()
    assert completes(w.done) == ["W2"] and keys(w) == {}, (w.done, w.state())


def c8(tmp, tree=None):   # ⑧ 보통 work one_work 가 Ungraded → git_rest_set 1회 · 다음 바퀴 stall 자리 «판정 불가 · git 쉼»(r2357 그대로)
    w = rig(tmp, works=("W3",), parked=(), tree=tree)
    w.k.landing = slow_landing(w)
    w.round()
    assert keys(w) == {"cfo|W3@a1": GIT_COST + REST_S}, w.state()
    done = again(w, WHEEL)
    assert ["settle", TEAM, "W3", "판정 불가 · git 쉼"] in done and lands(done) == [], done


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7, "⑧": c8}
MUTANTS = {"M1": ([(K1, "")], "①"),                                                  # except Ungraded 의 git_rest_set 지움
           "M2": ([(EXC, EXC + "\n            self.git_rest_set(team, work, attempt)   # M2 오류에도 쉼 창")], "②"),   # Exception 갈래에도 걸기
           "M3": ([(K2, "")], "④"),                                                   # 머리 git_rest 검사 지움
           "M4": ([(K2, '        if self.git_key(team, work, attempt) in (self.state.get("git_over") or {}):   # M4 시각 무시\n'
                       "            return None\n")], "⑤"),                          # 키 있으면 0(풀려도 안 봄)
           "M5": ([(MISS, MISS + "\n                self.git_rest_set(team, work, attempt)   # M5 «미도달» 에도 쉼 창")], "⑥")}   # «미도달» 갈래에도 걸기


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    assert CASES[name](tmp_path) is None


def test_baseline(tmp_path):   # 기준판(고치기 전 코드) = ① · ③ · ④ 세 칸만 Red · 나머지 다섯은 통과
    base = patch(copy_tree(tmp_path / "src"), (K2, ""), (K1, ""))
    for name in ("①", "③", "④"):
        with pytest.raises(AssertionError):
            CASES[name](tmp_path / name, base)
    for name in ("②", "⑤", "⑥", "⑦", "⑧"):
        assert CASES[name](tmp_path / name, base) is None


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    pairs, case = MUTANTS[name]
    tree = patch(copy_tree(tmp_path / "m"), *pairs)
    with pytest.raises(AssertionError):   # 사본(변이) = 그 사례가 잡는다
        CASES[case](tmp_path / "m1", tree)
    assert CASES[case](tmp_path / "o1") is None   # 원본으로 같은 사례 1회 = PASS(대조)
