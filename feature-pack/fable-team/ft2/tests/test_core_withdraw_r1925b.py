"""r1925b core — 접수 철회(withdraw) · 남은 일 · 같은 command 새 attempt · 회수 뒤 판정 (카드 반례 ①~⑬).
임시 원장만(실 runtime·tmux 0) · 공개 CLI(cli.run) + 회수·crash 칸은 라이브러리(segment_cap=1 = 줄마다 segment) · sleep 0.
기준판(팩 origin/main b44edf63) = withdraw 동사 없음 → ⑧ 밖 모든 칸 Red(⑧ 은 모르는 동사도 rc 64 라 기준판에서도 통과).
"""
import fcntl
import importlib.util
import json
from pathlib import Path

import pytest

FT2 = Path(__file__).resolve().parents[1]
TEAM, C, D, NANO = "harness", "c-r9925", "c-r9926", "byz-harness-nano-r9925#0"
MOVED = "%s.%s#a1.withdrawn" % (C, C)


def _mod(name):
    spec = importlib.util.spec_from_file_location("r1925b_" + name, str(FT2 / "core" / (name + ".py")))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


cli, journal, record, intake = _mod("cli"), _mod("journal"), _mod("record"), _mod("intake")


class T:
    def __init__(self, tmp):
        self.root = tmp / "root"
        self.runtime = self.root / ".fable-team" / "teams" / TEAM / "runtime"

    def run(self, *argv):
        return cli.run(list(argv) + ["--root", str(self.root), "--team", TEAM])

    def ok(self, *argv):
        out, rc = self.run(*argv)
        assert rc == 0, (argv, out)
        return out

    def wd(self, cmd=C, why="손 놓은 접수"):
        return self.run("withdraw", "--command", cmd, "--why", why)

    def view(self):   # (state, records) = 잠금 안 판독과 같은 꼴
        j = journal.Journal(str(self.runtime), segment_cap=1, rec=record)
        recs = j.records()
        return record.recover_state(j.state(), recs), recs

    def left(self):
        return record.remaining(*self.view())

    def kinds(self, kind):
        return [r for r in self.view()[1] if r["kind"] == kind]

    def snap(self):   # writer.lock 밖 runtime 파일 전부
        return tuple((p.name, p.read_bytes()) for p in sorted(self.runtime.rglob("*")) if p.is_file() and p.name != "writer.lock")

    def lib(self, on_step=None):   # 회수 칸 = 줄마다 segment
        caps = dict(segment_cap=1, on_step=on_step)
        return intake.Intake(str(self.root), TEAM, **caps), _mod("withdraw").Withdraw(str(self.root), TEAM, **caps)

    def withdrawn_then_d(self, again=False):   # C#a1 철회 → (C#a2) → D 1줄 = 마지막 seq 보존
        gate, wd = self.lib()
        gate.submit(C, "본문")
        assert wd.withdraw(C, "손 놓음")["result"] == "철회 성공"
        if again:
            gate.submit(C, "새 본문")
        gate.submit(D, "d")
        return gate, journal.Journal(str(self.runtime), segment_cap=1, rec=record).reclaim()


@pytest.fixture
def t(tmp_path):
    return T(tmp_path)


def test_c1_c3_withdraw_then_resubmit(t):   # ① 철회 성공 · 1줄 · C 0 · 본문 = .withdrawn · ③ 재submit C#a2 · C 1
    t.ok("submit", "--command", C, "--body", "본문")
    out, rc = t.wd()
    assert (rc, out["result"], out["attempt"]) == (0, "철회 성공", C + "#a1"), out
    assert [r["why"] for r in t.kinds("withdraw")] == ["손 놓은 접수"] and C not in t.left()
    assert not (t.runtime / "bodies" / (C + ".body")).exists()
    assert (t.runtime / "bodies" / MOVED).read_text(encoding="utf-8") == "본문"
    assert t.ok("submit", "--command", C, "--body", "새 본문")["attempt"] == C + "#a2" and t.left().count(C) == 1


def test_c2_capacity_frees(t):   # ② 8/8 → 용량 부족 · 철회 뒤 접수 성공 · capacity 칸도 1 줄어듦
    for n in range(8):
        t.ok("submit", "--command", "c%d" % n, "--body", "b", "--work", "r%d" % n)
    assert t.run("submit", "--command", "x", "--body", "b")[0]["result"] == "용량 부족"
    before = len(record.capacity(*t.view()))
    assert t.wd("c0")[1] == 0 and len(record.capacity(*t.view())) == before - 1
    assert t.run("submit", "--command", "x", "--body", "b")[0]["result"] == "접수 성공"


@pytest.mark.parametrize("kind", ["dispatch", "deliver", "result", "complete"])
def test_c4_c5_assigned_refused(t, kind):   # ④ 배정(assign) · ⑤ deliver·result·complete 1줄 → 철회 거부 · 쓰기 0
    t.ok("submit", "--command", C, "--body", "본문", "--work", "r9925")
    if kind == "dispatch":
        t.ok("assign", "--work", "r9925", "--holder", NANO, "--evidence", "v1,v2")
    else:
        j, seq = journal.Journal(str(t.runtime), rec=record), t.view()[1][-1]["seq"] + 1
        j.append(record.build(TEAM, seq, "r9925", "a1", "2026-11-19T00:00:00", "", "r9925", kind=kind))
    before = t.snap()
    out, rc = t.wd()
    assert (rc, out["result"]) == (1, "접수 거부") and kind in out["reason"], out
    assert t.snap() == before


def test_c6_c7_no_receipt_and_twice(t):   # ⑥ 접수 기록 없음 · ⑦ 둘째 = 이미 철회 · 줄 1
    out, rc = t.wd()
    assert (rc, out["result"]) == (1, "접수 거부") and "접수 기록 없음" in out["reason"] and not t.kinds("withdraw")
    t.ok("submit", "--command", C, "--body", "본문")
    out, rc = [t.wd() for _ in range(2)][1]
    assert (rc, out["result"]) == (1, "완료 유보") and "이미 철회" in out["reason"] and len(t.kinds("withdraw")) == 1


def test_c8_c9_bad_why_and_busy(t):   # ⑧ 사유 빈 값·공백·줄바꿈·201자 → rc 64 · ⑨ writer.lock 점유 → BUSY · 둘 다 쓰기 0
    t.ok("submit", "--command", C, "--body", "본문")
    before = t.snap()
    assert [t.wd(why=why)[1] for why in ("", "   ", "a\nb", "x" * 201)] == [64] * 4 and t.snap() == before
    with open(t.runtime / "writer.lock", "a+") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert t.wd()[0]["result"] == "BUSY"
    assert t.snap() == before


def test_c10_c11_reclaim_keeps_withdrawn(t):   # ⑩ 회수(withdraw seq 2 까지) → C 0 · 재submit C#a2 · ⑪ 옛 영수가 C#a2 를 숨기지 않음
    gate, out = t.withdrawn_then_d()
    assert (out["upto"], out["reclaimed"]) == (2, ["journal.1.jsonl", "journal.2.jsonl"]) and C not in t.left()
    assert gate.submit(C, "새 본문").attempt == C + "#a2"
    assert json.loads((t.runtime / "state.json").read_text())["journal_base"]["receipts"][C] == C + "#a1" and t.left().count(C) == 1
    assert gate.submit(C, "또").reason == "같은 command 기록 = 재부여 0"


def test_c12_crash_after_journal(t):   # ⑫ withdraw journal fsync 뒤 state 전 crash → C 0 · 재submit C#a2
    def boom(step):
        if step == "withdraw_after_journal":
            raise RuntimeError("crash")
    gate, wd = t.lib(on_step=boom)
    gate.submit(C, "본문")
    with pytest.raises(RuntimeError):
        wd.withdraw(C, "손 놓음")
    assert C not in t.left() and len(t.kinds("withdraw")) == 1 and t.lib()[0].submit(C, "새 본문").attempt == C + "#a2"


def test_c13_reclaim_spares_live_body(t):   # ⑬ C#a1 철회 → C#a2 → D → 회수 → C.body = 새 본문 · .withdrawn 지워짐
    _gate, out = t.withdrawn_then_d(again=True)
    assert out["reclaimed"] == ["journal.1.jsonl", "journal.2.jsonl"]
    assert (t.runtime / "bodies" / (C + ".body")).read_text(encoding="utf-8") == "새 본문"
    assert not (t.runtime / "bodies" / MOVED).exists() and t.left().count(C) == 1
