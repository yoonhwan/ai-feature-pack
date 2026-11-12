"""ft2 재개 1건 = 팀장 1번만 열기 시험 (r1727 · PLAN-ft20-team-reopen-from-record-20261112 · R1·R2) · 사례 = 2절 R1~R8 ·
준비 = r1726 실제 휴면 + TeamRecord `휴면 revision` · 중단 = on_step 예외 · 격리 tmp · 고정 시계 · 가짜 probe·crontab shim ·
sleep·tmux 0 · 변이(사본만) M1 키 중복 → R2·R2c · M2 큐 묶음 → R5 · M3 reopen 분기 → R1·R2c·R2r · M4 휴면 아님 → R2d ·
M5 저장 키 현재 R → R3s-k · M6 unknown=absent → R2c-u · M7 booted done → R2r · M8 `_work_closed` lifted → R2l."""
import functools
import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM, NOW, R, EV = "feature", "2026-11-12T15:00:00", 5, ("v1", "v2")
LEAD, MASTER, KEY = "byz-feature-master-pi#72", "byz-feature-master-pi#71", "5|p1"
OK, HOLD, REFUSED, BUSY = "접수 성공", "완료 유보", "접수 거부", "BUSY"
KEYS = ["goal:dormant:" + TEAM] + ["goal:dormant-step:%s:%s" % (TEAM, s) for s in ("nano-cleanup", "rescan",
                                                                                   "team-record", "arch-da")]
Boom = type("Boom", (RuntimeError,), {})

def _core(path=CORE, alias="ft2_test_ro_"):
    out = {}
    for name in ("reopen", "lifecycle", "dispatch", "team_record"):
        spec = importlib.util.spec_from_file_location(alias + name, os.path.join(path, name + ".py"))
        out[name] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(out[name])
    return SimpleNamespace(ro=out["reopen"], lc=out["lifecycle"], dispatch=out["dispatch"], tr=out["team_record"])

M = _core()

def _record(root, m, r, expect):
    [(Path(root) / name).write_text("x", encoding="utf-8") for name in ("HANDOFF.md", "LESSONS.md")]
    fields = {n: n + ".md" if n in ("HANDOFF", "LESSONS") else "없음" if n in m.tr.POINTERS else "0"
              for n in m.tr.FIELDS}
    assert m.tr.TeamRecord(str(root), TEAM).write(MASTER, expect, dict(fields, **{"휴면 revision": str(r)})).result == OK

def _sleep(root, m, r):                            # r1726 실제 휴면 1회(가짜 board · 조건 10칸 0)
    board = {"mail": 0, "ownership": 0, "cards": 0, "lands": 0, "hil": 0, "cron": 0, "dirty": [], "arch_da": "APPROVE",
             "team_record": {"revision": r, "generation": "g", "last_step": "team-lead", "resume": "runtime/"}}
    return m.lc.Lifecycle(str(root), TEAM, clock=lambda: NOW).dormant(board)

def _dormant(root, m=M, r=R, queue=()):
    os.makedirs(str(root), exist_ok=True)
    _record(root, m, r, 0)
    assert _sleep(root, m, r).result == OK
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    assert [d.rs.submit("q-" + w, "x" * 8, w).result for w in queue] == [OK] * len(queue)
    return d

def _go(root, m=M, event="p1", lead=LEAD, r=R, ack=None, probe="absent", stop=None):
    def step(name):
        if name == stop:
            raise Boom(name)
    look = probe if callable(probe) else (lambda seat: probe)
    return m.ro.Reopen(str(root), TEAM, clock=lambda: NOW, on_step=step, probe=look).reopen(r, event, lead, ack=ack)

def _seen(root, m=M):
    return m.lc.Lifecycle(str(root), TEAM)._state_records()

def _n(root, m=M):
    return len(_seen(root, m)[1])

def _r1(root, m=M, queue=()):
    _dormant(root, m, queue=queue)
    out, (state, records) = _go(root, m), _seen(root, m)
    assert (out.result, out.open, out.lead, out.phase, records[-1]["kind"]) == (OK, True, LEAD, "intent", "reopen")
    assert ([k for k in KEYS if k in state["done"]], sorted(state["lifted"])) == ([], sorted(KEYS))
    assert (out.load["record"]["휴면 revision"], out.load["HANDOFF"], out.load["LESSONS"]) == ("5", "HANDOFF.md", "LESSONS.md")
    return out

def _r1b(root, m=M):
    _r1(root, m)
    assert [(o.result, o.phase, o.written) for o in (_go(root, m, ack="b1"), _go(root, m, ack="b1"))] \
        == [(OK, "booted", True), (HOLD, "booted", False)]

def _again(root, m=M, kw=(), want=()):             # R2 같은 키 · alive / R2d 다른 키 = 휴면 아님 · 둘 다 쓰기 0
    _r1(root, m)
    lines, out = _n(root, m), _go(root, m, **dict(kw))
    assert (out.result, out.open, out.lead, out.reason[:5], _n(root, m)) == tuple(want) + (lines,)

def _crash(root, m=M, probes=(), want=()):                 # R2c·R2c-u — intent 줄 내구화 뒤 state 전 중단 → 새 인스턴스
    _dormant(root, m)
    with pytest.raises(Boom):
        _go(root, m, stop="after_reopen_journal")
    lines, outs = _n(root, m), [_go(root, m, lead="other", probe=p) for p in probes]
    assert ([(o.result, o.open, o.lead, o.written, o.reason[:7]) for o in outs], _n(root, m),
            KEYS[0] in _seen(root, m)[0]["done"]) == (want, lines, False)

_r2c = functools.partial(_crash, probes=("absent",), want=[(OK, True, LEAD, False, "재접수 — 팀")])
_r2cu = functools.partial(_crash, probes=("unknown", lambda seat: 1 / 0), want=[(HOLD, False, LEAD, False, "판정 불가 ·")] * 2)

_r2 = functools.partial(_again, kw={"lead": "other", "probe": "alive"}, want=(HOLD, False, LEAD, "재접수 —"))
_r2d = functools.partial(_again, kw={"event": "p2"}, want=(HOLD, False, None, "휴면 아님"))

def _close(d, work):
    assert [d.rs.submit("c-" + work, "x" * 8, work).result, d.assign(work, LEAD, evidence=EV).result,
            d.ex.result(work, LEAD, 1, OK).result, d.deliver(work, "a1").result,
            d.complete(work, "a1").result] == [OK] * 5

def _r2r(root, m=M, ack=True):                     # R2l = 같은 준비 · R2i = ack 없음(intent 만 = 열린 work)
    _dormant(root, m)
    assert [_go(root, m).result] + ([_go(root, m, ack="b1").result] if ack else []) == [OK] * (1 + ack)
    seq, d = _seen(root, m)[1][-1]["seq"], m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    d.rs.journal.segment_cap = 1024
    [_close(d, work) for work in ("W1", "W2", "W3")]
    out, base = d.rs.journal.reclaim(), d.rs.journal.state().get("journal_base") or {}
    assert (out["result"] == "회수 결과" and base.get("upto", 0) >= seq and KEY in base["proj"]["reopens"]) \
        if ack else base.get("upto", 0) < seq                               # 실제 전진 / intent 만 = 보존
    lines, again = _n(root, m), _go(root, m, probe="alive")
    assert (again.result, again.open, again.lead, _n(root, m)) == (HOLD, False, LEAD, lines)
    return base

def _r2l(root, m=M):
    assert sorted(_r2r(root, m)["proj"]["lifted"]) == sorted(KEYS)       # 지운 키 5 전부 · 그 뒤 다시 휴면 = 새 표식
    _r5d(root, m, again=True)

def _r5d(root, m=M, again=False):                 # 다시 휴면 = 5단계 처음부터 · 새 표식
    out = (again or _r1(root, m)) and _sleep(root, m, R + 1)
    assert (out.result, len(out.steps), KEYS[0] in _seen(root, m)[0]["done"]) == (OK, 5, True)

def _r3sk(root, m=M):                               # 저장 키(5|p1 intent)의 낡은 R — 다시 휴면 R=6 뒤
    _dormant(root, m)
    assert (_go(root, m).result, _record(root, m, R + 1, 1)) == (OK, None)   # 5|p1 intent · 팀 기록 R=6
    _r5d(root, m, again=True)
    lines, out = _n(root, m), _go(root, m)
    assert (out.result, out.open, _n(root, m)) == (REFUSED, False, lines)

def _r5(root, m=M):
    out = _r1(root, m, queue=("W1", "W2", "W3"))
    assert ([row["command"] for row in out.load["queue"]], out.seats_needed) == (["q-W1", "q-W2", "q-W3"], ["W1", "W2", "W3"])
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    assert [d.assign(w, LEAD, evidence=EV).result for w in ("W1", "W2", "W3")] == [OK] * 3
    assert d.rs.submit("q-W1", "x" * 8, "W1").result == HOLD               # 같은 command 재접수 = 같은 행(새 줄 0)
    assert len([rec for rec in _seen(root, m)[1] if rec["kind"] == "dispatch"]) == 3

SCENARIOS = {"R1": _r1, "R1b": _r1b, "R2": _r2, "R2c": _r2c, "R2c-u": _r2cu, "R2d": _r2d, "R2r": _r2r, "R2l": _r2l,
             "R2i": lambda root, m=M: _r2r(root, m, ack=False), "R3s-k": _r3sk, "R5": _r5, "R5d": _r5d}

@pytest.mark.parametrize("case", SCENARIOS.values(), ids=SCENARIOS.keys())
def test_scenarios(tmp_path, case):
    case(tmp_path)

def test_r3_r3s_r4_r7_no_work_stale_queue_busy(tmp_path):
    d = _dormant(tmp_path / "q", queue=("W1", "W2", "W3"))                  # R4 큐 보존 · claim 거절 · reopen 0
    kinds = [rec["kind"] for rec in _seen(tmp_path / "q")[1]]
    assert (kinds.count("accept"), "reopen" in kinds, d.ex.claim("W1", LEAD).result) == (3, False, REFUSED)
    _dormant(tmp_path)
    lines, lock = _n(tmp_path), M.dispatch.Dispatch(str(tmp_path), TEAM).rs._try_lock()
    assert (_go(tmp_path).result, _n(tmp_path)) == (BUSY, lines)               # R7
    lock.close()
    assert [(o.result, o.open) for o in (_go(tmp_path, r=4),)] == [(REFUSED, False)] and _n(tmp_path) == lines
    record = Path(tmp_path) / ".fable-team" / "teams" / TEAM / "TEAM-RECORD.md"
    record.rename(record.with_suffix(".bak"))
    out = _go(tmp_path)
    assert (out.result, out.open, out.reason[:7], _n(tmp_path)) == (HOLD, False, "판정 불가 ·", lines)   # R3s
    record.with_suffix(".bak").rename(record)
    assert _go(tmp_path).seats_needed == []                                   # R3 열린 일 0

def _cli(root, *args, env=None):
    proc = subprocess.run([sys.executable, os.path.join(CORE, "cli.py"), "reopen", "--root", str(root), "--team", TEAM,
                           *args], capture_output=True, text=True, timeout=30, env=env or dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)

def test_r6_r8_cli_rc_and_no_cron(tmp_path):
    _dormant(tmp_path / "t")
    shim, log = tmp_path, tmp_path / "crontab.log"                            # PATH 맨 앞 = 가짜 crontab
    (shim / "crontab").write_text("#!/bin/sh\necho \"$@\" >> %s\n" % log, encoding="utf-8")
    (shim / "crontab").chmod(0o755)
    env, root = dict(os.environ, FT_NOW=NOW, PATH="%s:%s" % (shim, os.environ["PATH"])), tmp_path / "t"
    before, base = {p for p in root.rglob("*")}, ["--event", "p1", "--lead", LEAD]
    refused, (rc, out) = _cli(root, "--revision", "4", *base, env=env)[0], _cli(root, "--revision", "5", *base, env=env)
    assert (refused, rc, out["open"], out["lead"], _cli(root, "--revision", "5", *base, env=env)[0]) == (1, 0, True, LEAD, 1)
    assert _cli(root, "--revision", "x", *base)[0] == 64 and _cli(root, "--revision", "5")[0] == 64
    assert not log.exists() and {p.name for p in set(root.rglob("*")) - before} <= {"journal.jsonl", "state.json"}

MUTANTS = (
    ("M1", "reopen.py", "if row is not None:", "if False:", (_r2, _r2c)),
    ("M2", "reopen.py", "dict.fromkeys(rows)", "rows", (_r5,)),
    ("M3", "record.py", 'elif kind == "reopen" and work:', "elif False:", (_r1, _r2c, _r2r)),
    ("M4", "reopen.py", "if self.lc._dormant_key() not in", "if False and self.lc._dormant_key() not in", (_r2d,)),
    ("M5", "reopen.py", "stale = self._current(revision)   # 저장 키도", "stale = None   # 저장 키도", (_r3sk,)),
    ("M6", "reopen.py", 'if seen == "absent":', 'if seen != "alive":', (_r2cu,)),
    ("M7", "record.py", 'done[rec["work"]] = {"attempt": rec.get("ack")', '_ = {"attempt": rec.get("ack")', (_r2r,)),
    ("M8", "journal.py", 'if done is None and work in (state.get("lifted") or {}):', "if False:", (_r2l,)),
)

@pytest.mark.parametrize("label,name,old,new,cases", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_cases(tmp_path, label, name, old, new, cases):
    copy = Path(shutil.copytree(CORE, tmp_path / "core"))
    text = (copy / name).read_text(encoding="utf-8")
    assert text.count(old) == 1, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    mutant = _core(str(copy), "ft2_mut_ro_%s_" % label)
    for idx, case in enumerate(cases):
        with pytest.raises((AssertionError, KeyError, TypeError)):
            case(tmp_path / ("run%d" % idx), mutant)
