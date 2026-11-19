"""r2258 ft2 keeper — 쉼(idle-done)으로 멈춘 work 도 착지 줄이 생기면 keeper 가 complete 까지 잇는다(O1 쉼 착지 · O2 소음 0 · O3 불변).
대역 = r1812 World(임시 BYZ·팩 리포 · 가짜 tmux · 주입 시계) + r1960 가짜 gh(FT2_GH · 가지별 출력) + r2026 가짜 card_stage · park·return = 실 CLI(임시 원장).
네트워크 0(임시 bare 리포만) · sleep 0 · ①~⑤ · 변이 M1~M4 · 변이마다 원본으로 같은 사례 1회 더(반대 결과 대조)."""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]


def _mod(name, alias):
    spec = importlib.util.spec_from_file_location(alias, str(FT2 / "tests" / name))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


E = _mod("test_pi_keeper_endings_r1960.py", "r2258_endings")   # world(가짜 gh) · pr(worktree nano/<work> · merged PR)
P = _mod("test_pi_keeper_parked_done_close_r2251.py", "r2258_parked")   # cli · mine
Fake, kw = P.Fake, E.kw
TEAM, STAGED, NOLAND = "harness", ("r-x", "진행→완성", "c0ffee"), "cd" * 20


def counted(k):
    """landing 호출 기록(work 이름) — 판정은 원본 그대로."""
    real, calls = k.landing, []

    def landing(team, work):
        calls.append(work)
        return real(team, work)
    k.landing = landing
    return calls


def keeper(w):
    k = w.keeper()
    k.cs = Fake([STAGED])
    return k, counted(k)


def made(w, mp, work, sha=None, body=None, via="parked", reason="idle-done", tree=False):
    """카드(착지 줄 sha | 본문 body) + dispatch a1(유휴 나노 세션) → 쉼 | 반환 a1 · done 아님 · tree = worktree nano/<work>(merged PR 0)."""
    w.enable()
    if body is None:
        w.card(work, sha)
    else:
        for ref in ("main", "ops/main-base"):
            w.commit("byz", {"design/harness/indices/진행/%s-x.md" % work: body}, ref)
    holder = w.work(work, alive=True, intent=not tree)
    if tree:
        E.pr(w, work, n=0)
    if via == "parked":
        P.cli(w, "park", "--work", work, "--attempt", "a1", "--reason", reason)
    if via == "returned":   # r1990 반환 = owner 0 → claim·start·result 뒤 현역 master 손
        mp.setenv("FT_SEAT", holder)
        gen = P.cli(w, "claim", "--work", work, "--holder", holder)["gen"]
        for verb in ("start", "result"):
            P.cli(w, verb, "--work", work, "--holder", holder, "--gen", str(gen))
        mp.setenv("FT_SEAT", P.MASTER)
        P.cli(w, "return", "--work", work, "--attempt", "a1", "--evidence", "산출 0")
    return holder


def run(w):
    k, calls = keeper(w)
    return w.round(k), calls


def quiet(w, lines, work):
    """O2 — 그 work 줄 0 · 깨움 0 · 쪽지 0 · complete 0."""
    return not P.mine(lines, work) and not w.tmux("send-keys") and not kw._lines(str(w.mbox) + ".log") and w.kinds("complete") == 0


def c1(w, mp):   # ① 쉼 ∧ done 아님 ∧ 착지 줄(조상) → 그 바퀴 complete 1(close 0) · 다음 바퀴 r2251 길 닫기 · 기준판 = complete 0(Red)
    holder = made(w, mp, "r9581", sha=w.pack_sha())
    lines, _ = run(w)
    assert w.kinds("complete") == 1 and E.has(lines, "COMPLETED harness r9581") and w.tmux("kill-session") == [], lines
    lines, _ = run(w)
    assert w.tmux("kill-session") == [["kill-session", "-t", "=" + holder]] and w.kinds("close_receipt") == 1, lines


def c2(w, mp):   # ② 착지 줄 · 어느 ref 에도 조상 아님(미도달) → complete 0 · 줄 0 · 깨움 0 · 두 번째 바퀴(세 tip 같음) landing 0
    made(w, mp, "r9582", sha=NOLAND)
    lines, calls = run(w)
    assert calls.count("r9582") == 1 and quiet(w, lines, "r9582"), (calls, lines)
    lines, calls = run(w)
    assert calls.count("r9582") == 0 and quiet(w, lines, "r9582"), (calls, lines)


def c2b(w, mp):   # ②b ② 뒤 팩 origin/main tip 만 바뀌고 그 tip 이 착지 sha 를 품음(카드 줄 먼저 · 팩 병합 나중) → landing 1 · complete 1
    seed = w.tmp / "seed-pack"
    kw._put(seed / "late.txt", "late"), kw._git(seed, "add", "-A"), kw._git(seed, "commit", "-q", "-m", "late")
    sha = kw._git(seed, "rev-parse", "HEAD")   # push 전 = 팩 clone 에 객체 없음 = 미도달
    made(w, mp, "r9583", sha=sha)
    lines, calls = run(w)
    assert calls.count("r9583") == 1 and quiet(w, lines, "r9583"), (calls, lines)
    kw._git(seed, "push", "-q", "origin", "main")
    lines, calls = run(w)
    assert calls.count("r9583") == 1 and w.kinds("complete") == 1, (calls, lines)


def c2c(w, mp):   # ②c 착지 줄 없음 ∧ PR merged 아님 → complete 0 · 줄 0 · 둘째 바퀴도 landing 1(기억 0) → PR merged(카드 그대로) → 셋째 바퀴 complete 1
    made(w, mp, "r9584", tree=True)
    for _ in range(2):
        lines, calls = run(w)
        assert calls.count("r9584") == 1 and not P.mine(lines, "r9584") and w.kinds("complete") == 0, (calls, lines)
    oid = kw._git(w.tmp / "wt" / "r9584", "rev-parse", "HEAD")
    kw._put(str(w.tmp / "gh") + ".out-r9584", json.dumps([{"number": 7, "mergeCommit": {"oid": oid}, "baseRefName": "main"}]))
    lines, calls = run(w)
    assert calls.count("r9584") == 1 and w.kinds("complete") == 1 and E.has(lines, "COMPLETED harness r9584", "PR #7 병합"), (calls, lines)


def c3(w, mp):   # ③ 착지 줄 있으나 «남은 범위» 줄 없음 → 기존 관문 UNKNOWN 1줄(r2000 꼴) · complete 0
    made(w, mp, "r9585", body="# 인덱스: r9585\n- 상태: 대기\n- 착지: %s\n" % w.pack_sha())
    lines, _ = run(w)
    assert [x for x in lines if x.startswith("UNKNOWN harness r9585 남은 범위")] and w.kinds("complete") == 0, lines


def c4(w, mp):   # ④ 반환 attempt ∧ 착지 줄 → complete 0 · landing 0(O3)
    made(w, mp, "r9586", sha=w.pack_sha(), via="returned")
    lines, calls = run(w)
    assert w.kinds("complete") == 0 and calls.count("r9586") == 0, (calls, lines)


def c5(w, mp):   # ⑤ launch-failed 쉼 ∧ 착지 줄 → 새 쉼 갈래 0(parked_landing 0) · r2058 L2 길(one_work complete) 그대로 · 닫기 0
    k0, _ = keeper(w)
    made(w, mp, "r9587", sha=w.pack_sha(), reason=type(k0).run_once.__globals__["settling"].LAUNCH_FAILED)
    k, _ = keeper(w)
    real, seen = k.parked_landing, []
    k.parked_landing = lambda *a: seen.append(a) or real(*a)
    lines = w.round(k)
    assert seen == [] and w.kinds("complete") == 1 and w.tmux("kill-session") == [], (seen, lines)


CASES = {"①": c1, "②": c2, "②b": c2b, "②c": c2c, "③": c3, "④": c4, "⑤": c5}
KP = "adapters/pi/keeper.py"
MUTANTS = {"M1": ("self.parked_landing(team, work, attempt)", "None", ("①",)),
           "M2": ("elif work in open_:", "elif (work, attempt) in back:", ("④",)),
           "M3": ('rnd["tips"] = pout.split() + bout.split() if', 'rnd["tips"] = bout.split() if', ("②b",)),
           "M4": ('if got[2] == "미도달" and tips:', 'if got[2] in ("미도달", "착지 줄 없음") and tips:', ("②c",))}


def world(tmp, mp, ft2=FT2):
    return E.world(None, tmp, mp, ft2)


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](world(tmp_path, monkeypatch), monkeypatch)


@pytest.mark.parametrize("name,case", [(m, c) for m, (_o, _n, cs) in MUTANTS.items() for c in cs])
def test_mutant(name, case, tmp_path, monkeypatch):
    old, new, _cases = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KP).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / KP).write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(AssertionError):
        CASES[case](world(tmp_path / "w", monkeypatch, tree), monkeypatch)
    CASES[case](world(tmp_path / "o", monkeypatch), monkeypatch)   # 원본 대조 = 같은 사례가 원본에서는 통과(반대 결과)
