"""r2055a core — 쉼(park) 동사 · 용량(capacity) 셈 · 의무 장부(remaining) 그대로 (카드 반례 ③⑧⑪⑬⑭⑮ core 칸 · 변이 M1·M2).
임시 원장만(실 runtime·tmux 0) · 공개 CLI(cli.run) · sleep 0.
기준판(팩 origin/main 91b0b064) = park 동사·capacity 칸 없음 → 7칸 모두 Red(사용법·KeyError · ⑬ 은 park 가 없어 Red · 동작 기대는 지킴).
"""
import importlib.util
import json
import shutil
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
TEAM, W, NANO = "harness", "r9055", "byz-harness-nano-r9055#0"


def _mod(path, alias):
    spec = importlib.util.spec_from_file_location(alias, str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Ledger:
    def __init__(self, tmp, ft2=FT2):
        self.root, self.ft2 = tmp / "root", ft2
        self.cli = _mod(ft2 / "core" / "cli.py", "r2055_cli_%d" % id(self))

    def run(self, *argv):
        return self.cli.run(list(argv) + ["--root", str(self.root), "--team", TEAM])

    def ok(self, *argv):
        out, rc = self.run(*argv)
        assert rc == 0, (argv, out)
        return out

    def open(self, work=W, res="R", holder=NANO, command=None):
        """접수 → 배정(자원 R) → 전달 = 최신 attempt · owner·예약 있음."""
        self.ok("submit", "--command", command or "c-" + work, "--body", "본문", "--work", work)
        out = self.ok("assign", "--work", work, "--holder", holder, "--evidence", "v1,v2", "--resources", res)
        self.ok("deliver", "--work", work)
        return out["attempt"]

    def proj(self):
        return self.ok("project")

    def state(self):
        return json.loads((self.runtime / "state.json").read_text(encoding="utf-8"))

    @property
    def runtime(self):
        return self.root / ".fable-team" / "teams" / TEAM / "runtime"

    def snap(self):
        return tuple(p.read_bytes() for p in sorted(self.runtime.rglob("*")) if p.is_file() and p.name != "writer.lock")


def c3(t):   # ③ 세션 0 · owner 남음 → park(launch-failed) · owner·예약 해제 · 용량 −1 · 의무 그대로
    a = t.open()
    before = t.proj()
    out = t.ok("park", "--work", W, "--attempt", a, "--reason", "launch-failed")
    after, st = t.proj(), t.state()
    assert out["stage"] == "parked" and out["released"] == ["R"], out
    assert W not in st["owners"] and "R" not in st["reservations"] and st["parked"][W]["attempt"] == a
    assert after["capacity"] == before["capacity"] - 1 and after["remaining"] == before["remaining"] == 1


def c8(t):   # ⑧ 쉼 work 에 새 dispatch(같은 자원 R) → 배정 성공 · parked 지워짐
    a = t.open()
    t.ok("park", "--work", W, "--attempt", a, "--reason", "idle-done")
    out = t.ok("assign", "--work", W, "--holder", NANO, "--evidence", "v1,v2", "--resources", "R")
    assert out["attempt"] == "a2" and W not in t.state()["parked"] and t.proj()["capacity"] == 1, out


def c11(t):   # ⑪ 같은 work command 2개(accept 만) → 의무 2줄 · 용량 1칸
    t.ok("submit", "--command", "c1-" + W, "--body", "본문", "--work", W)
    t.ok("submit", "--command", "c2-" + W, "--body", "본문", "--work", W)
    p = t.proj()
    assert (p["remaining"], p["capacity"]) == (2, 1), p


def c11b(t):   # ⑪′ 용량 상한 = work 단위 · 쉼 제외(상한 8 · 쉼 1 → 9번째 접수 성공)
    for n in range(8):
        a = t.open("w%d" % n, res="R%d" % n)
    assert t.run("submit", "--command", "c-x", "--body", "b", "--work", "x")[0]["result"] == "용량 부족"
    t.ok("park", "--work", "w7", "--attempt", a, "--reason", "idle-done")
    assert t.run("submit", "--command", "c-x", "--body", "b", "--work", "x")[0]["result"] == "접수 성공"
    p = t.proj()
    assert (p["remaining"], p["capacity"]) == (9, 8), p


def c13(t):   # ⑬ 쉼 W(done 0 · owner 0) → 마감 gate PENDING_NOT_ZERO:1 그대로 · 재개 queue 에 W 남음
    a = t.open()
    t.ok("park", "--work", W, "--attempt", a, "--reason", "idle-done")
    lc = _mod(t.ft2 / "core" / "lifecycle.py", "r2055_lc_%d" % id(t)).Lifecycle(str(t.root), TEAM)
    assert lc._blockers(*lc._state_records()) == ["PENDING_NOT_ZERO:1"]
    ro = _mod(t.ft2 / "core" / "reopen.py", "r2055_ro_%d" % id(t)).Reopen(str(t.root), TEAM)
    state, records = lc._state_records()
    assert [row["work"] for row in ro._load_list(state, records)["queue"]] == [W]


def c14(t):   # ⑭ park journal 줄 뒤 state 전 crash → 복구 → parked 앞섬 · 두 번째 park = HOLD 멱등 · 예약 0
    a = t.open()
    dmod = _mod(t.ft2 / "core" / "dispatch.py", "r2055_dp_%d" % id(t))

    def boom(step):
        if step == "after_parked_journal":
            raise RuntimeError("crash 주입")
    with pytest.raises(RuntimeError):
        dmod.Dispatch(str(t.root), TEAM, on_step=boom).park(W, a, "idle-done")
    assert W in t.state()["owners"]   # state 는 앞 판(crash)
    p = t.proj()
    assert p["capacity"] == 0 and p["works"][W]["owner"] is None, p
    out, rc = t.run("park", "--work", W, "--attempt", a, "--reason", "idle-done")
    assert (out["result"], rc) == ("완료 유보", 1) and sum(1 for r in t.journal() if r["kind"] == "parked") == 1, out
    assert t.ok("assign", "--work", W, "--holder", NANO, "--evidence", "v1,v2", "--resources", "R")["attempt"] == "a2"


def c15(t):   # ⑮ 효과 의도 뒤 결과 0 · uncertain 표식 · 낡은 attempt · 완료 → 거절 · 쓰기 0
    a = t.open()
    gen = t.ok("claim", "--work", W, "--holder", NANO)["gen"]
    t.ok("start", "--work", W, "--holder", NANO, "--gen", str(gen))
    t.ok("effect", "--work", W, "--holder", NANO, "--gen", str(gen), "--effect", "push")
    before = t.snap()
    for att in (a, "a9"):
        out, rc = t.run("park", "--work", W, "--attempt", att, "--reason", "idle-done")
        assert (out["result"], rc) == ("접수 거부", 1) and t.snap() == before, out
    t.ok("result", "--work", W, "--holder", NANO, "--gen", str(gen))
    t.ok("complete", "--work", W, "--attempt", a)
    before = t.snap()
    out, rc = t.run("park", "--work", W, "--attempt", a, "--reason", "idle-done")
    assert (out["result"], rc, "완료" in out["reason"]) == ("접수 거부", 1, True) and t.snap() == before, out
    out, _ = t.run("park", "--work", W, "--attempt", a, "--reason", "아무거나")
    assert out["result"] == "접수 거부"


def _journal(t):
    return [json.loads(x) for p in sorted(t.runtime.glob("journal*.jsonl")) for x in p.read_text(encoding="utf-8").splitlines()]


Ledger.journal = _journal
CASES = {"③": c3, "⑧": c8, "⑪": c11, "⑪′": c11b, "⑬": c13, "⑭": c14, "⑮": c15}
MUTANTS = {   # 변이 = 사본 1곳 · 원본 같은 사례 1회 더 = PASS
    "M1": ("core/record.py", 'kept = {res: row for res, row in kept.items() if row.get("work") != work}\n            parked[work]',
           "parked[work]", c8),
    "M2": ("core/intake.py", "remaining = record.capacity(state, records, self._remaining(records, state))", "remaining = self._remaining(records, state)", c11b),
}


@pytest.mark.parametrize("name", list(CASES))
def test_case(name, tmp_path):
    CASES[name](Ledger(tmp_path))


@pytest.mark.parametrize("name", list(MUTANTS))
def test_mutant(name, tmp_path):
    rel, old, new, case = MUTANTS[name]
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / rel).read_text(encoding="utf-8")
    assert text.count(old) == 1, (name, old)
    (tree / rel).write_text(text.replace(old, new), encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    with pytest.raises(AssertionError):
        case(Ledger(tmp_path / "w1", tree))
    case(Ledger(tmp_path / "w2"))
