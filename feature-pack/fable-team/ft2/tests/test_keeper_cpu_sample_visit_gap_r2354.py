"""r2354 ft2 keeper — CPU 쉼 표본 수명 = 좌석 판 대조(방문 간격 무관) (카드 반례 ①~⑦ · 계약 K1~K3).
① 표본 0.0 → 700초 뒤 같은 pane_pid 0.0 → idle(기준판 = 600초 지움 → pending) · ② pane_pid 다름 = 새 판 → pending · ③ 4000초 = 상한 넘김 → pending
④ 40초 → idle(지금과 같음) · ⑤ 700초 뒤 busy → first 다시 · ⑥ 바퀴 캐시 ls 에 없는 좌석 = 표본 지움 · ls 실패 = 표본 그대로 · ls 호출 = 바퀴당 1 · 표본별 tmux 0 · ⑦ pane2 는 600초 지움 그대로.
대역 = r2055 settle world(임시 리포 · 가짜 tmux·ps · 주입 시계) · keeper 한 인스턴스에 state·ps·tmux 를 직접 주입 · 실 tmux·실 pi·sleep 0.
변이 M1~M5 = 자매 시험 안(MUTANTS) · 변이마다 원본으로 같은 사례 1회 더 · 시험 1개 70초 안.
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

_spec = importlib.util.spec_from_file_location("r2055_settle_for_r2354", str(Path(__file__).with_name("test_settle_one_path_r2055.py")))
S = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(S)
kw, FT2, TEAM = S.kw, S.FT2, S.TEAM
SEAT = "byz-%s-nano-r9851#0" % TEAM
CHAIN = S.CHAIN
KS = "adapters/pi/keeper_settle.py"


def keeper(w, alive=True, ls_fail=None, cpu=0.0):
    """keeper 1개 — 그 좌석만 살아 있는 tmux 목록 · ps 표(사슬 %cpu) · kickoff 카운터 · 표본 장부 초기화."""
    d = json.loads(w.tm.read_text(encoding="utf-8"))
    d["alive"] = ([SEAT] if alive else []) + [x for x in d["alive"] if x != SEAT]
    kw._put(w.tm, d)
    k = w.keeper()
    real, k.calls = k.call, {"ls": 0, "tmux": 0}
    def call(argv):
        if argv and argv[0] == k.tmux:
            k.calls["tmux"] += 1
            if "list-sessions" in argv:
                k.calls["ls"] += 1
                if ls_fail is not None:
                    return ls_fail
        return real(argv)
    k.call = call
    k.ps_rows = lambda: [(p, pp, cpu if c is None else c, n) for p, pp, c, n in CHAIN]
    k.state = {}
    return k


def sample(k, at, cpu=0.0, pane_pid=100, first=None):
    """cpu 표본 1개 — first 없으면 at(그 표본에서 처음 쉼)."""
    k.state.setdefault("cpu", {})[SEAT] = {"at": at, "cpu": cpu, "first": at if first is None else first,
                                           **({} if pane_pid is None else {"pane_pid": pane_pid})}


def c1(w):   # ① 표본 0.0 → 700초 뒤 같은 pane_pid 0.0 → idle(기준판 = 지워져 pending)
    k = keeper(w)
    sample(k, w.t - 700)
    k.fresh_samples()
    assert SEAT in k.state["cpu"], k.state
    assert k.cpu(SEAT, (100, "pi")) == "idle", k.state


def c2(w):   # ② ① 에서 둘째 표본 pane_pid 다름 = 새 판 좌석 → pending · pane_pid 칸 없는 옛 표본도 같은 길
    for pid, seeded in ((111, 100), (100, None)):
        k = keeper(w)
        sample(k, w.t - 700, pane_pid=seeded)
        k.fresh_samples()
        assert k.cpu(SEAT, (pid, "pi")) == "pending", (pid, seeded, k.state)


def c3(w):   # ③ 4000초 = CPU_SAMPLE_MAX 넘김 → 표본 지움 → pending
    k = keeper(w)
    sample(k, w.t - 4000)
    k.fresh_samples()
    assert SEAT not in k.state["cpu"], k.state
    assert k.cpu(SEAT, (100, "pi")) == "pending", k.state


def c4(w):   # ④ 40초 뒤 0.0 → idle(지금과 같음)
    k = keeper(w)
    sample(k, w.t - 40)
    k.fresh_samples()
    assert k.cpu(SEAT, (100, "pi")) == "idle", k.state


def c5(w):   # ⑤ 700초 뒤 1.2 → busy · first 다시(표본에 first 없음)
    k = keeper(w)
    sample(k, w.t - 700)
    k.fresh_samples()
    k.ps_rows = lambda: [(p, pp, 1.2 if c is None else c, n) for p, pp, c, n in CHAIN]
    assert k.cpu(SEAT, (100, "pi")) == "busy" and "first" not in k.state["cpu"][SEAT], k.state


def c6(w):   # ⑥ 바퀴 캐시 ls: 좌석 없음 = 지움 · ls 실패(서버 없음 아님) = 그대로 · ls 호출 = 바퀴당 1 · 표본별 tmux 0
    k = keeper(w, alive=False)
    sample(k, w.t - 700)
    k.fresh_samples()
    assert SEAT not in k.state["cpu"] and k.calls["ls"] == 1, (k.state, k.calls)
    assert k.cpu(SEAT, (100, "pi")) == "pending", k.state
    k = keeper(w, ls_fail=(2, "", "tmux: lost"))   # 판정 불가 = 지움 0
    sample(k, w.t - 700)
    k.fresh_samples()
    k.fresh_samples()   # 같은 바퀴 = 캐시 재사용(추가 호출 0)
    assert SEAT in k.state["cpu"] and k.calls["ls"] == 1, (k.state, k.calls)
    before = k.calls["tmux"]
    assert k.cpu(SEAT, (100, "pi")) == "idle" and k.calls["tmux"] == before, (k.state, k.calls)


def c7(w):   # ⑦ pane2 표본 600초 넘음 → 지금처럼 지움(K3)
    k = keeper(w)
    k.state = {"round_at": w.t - 100, "pane2": {SEAT: {"first": w.t - 700, "at": w.t - 700}}}
    k.fresh_samples()
    assert SEAT not in k.state["pane2"], k.state


CASES = {"①": c1, "②": c2, "③": c3, "④": c4, "⑤": c5, "⑥": c6, "⑦": c7}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path, monkeypatch):
    CASES[name](S.world(tmp_path, monkeypatch))


MUTANTS = {
    "M1": ([("or now - v.get(\"at\", 0) > CPU_SAMPLE_MAX]:", "or now - v.get(\"at\", 0) > SAMPLE_KEEP]:")], c1),   # 600초 지우기 되살림
    "M2": ([("same = prev.get(\"pane_pid\") == pid", "same = True")], c2),   # pane_pid 대조 삭제
    "M3": ([("or now - v.get(\"at\", 0) > CPU_SAMPLE_MAX", "or False")], c3),   # 상한 3600 삭제
    "M4": ([("(alive is not None and x not in alive) or", "")], c6),   # absent 지우기 삭제
    "M5": ([("(prev is None or v.get(\"at\", 0) < prev) and now - v.get(\"at\", 0) > SAMPLE_KEEP",
             "(alive is not None and x not in alive) or now - v.get(\"at\", 0) > CPU_SAMPLE_MAX")], c7),   # pane2 도 K1 규칙
}


def mutant(tmp_path, monkeypatch, pairs, case):
    """사본 ft2 의 변이(pairs = [(old, new)] · 각 old 1회) → 사례 FAIL · 원본으로 같은 사례 1회 더 = PASS."""
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / KS).read_text(encoding="utf-8")
    for old, new in pairs:
        assert text.count(old) == 1, (KS, old)
        text = text.replace(old, new)
    (tree / KS).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(S.world(tmp_path / "w1", monkeypatch, tree))
    case(S.world(tmp_path / "w2", monkeypatch))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path, monkeypatch):
    pairs, case = MUTANTS[name]
    mutant(tmp_path, monkeypatch, pairs, case)
