"""ft2 닫기 영수 → 다음 발주·다음 카드 시험 (r1725 · PLAN-ft20-master-close-receipt-next-dispatch-20261112 · R1·보정 2).
사례 = 계획 2절 C1~C9·C6z · 중단 = on_step 예외(kill·sleep 0) · 격리 tmp · 고정 시계 · 가짜 probe·좌석 사실 · tmux 0 ·
변이(사본만 · 하나씩) M1 probe 부재 → C3 · M2 사건 중복 → C6 · M3 recover_state 분기 → C6c·C6r · M4 일하는 좌석 → C7 · M5 «dispatch 있으면 재접수» 한 갈래 → C6d(C6·C6c·C6r PASS) · M6 영수 키 done 세우기 → C6z(upto 미전진)."""
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
TEAM, NOW, NANO, NEXT = "feature", "2026-11-12T13:00:00", "byz-feature-nano-r1-x#1", "byz-feature-nano-r2-y#1"
ARCH, DA = "byz-feature-arch-pi#1", "byz-feature-da-pi#1"
OK, HOLD, REFUSED, BUSY = "접수 성공", "완료 유보", "접수 거부", "BUSY"
EV, FOUR = ("v1", "v2"), ("산출 완료", "원격 보존", "팀장 인수", "남은 일 팀장 몫")
ALL, NONE_NEXT = dict.fromkeys(FOUR, True), "[다음 없음]"
Boom = type("Boom", (RuntimeError,), {})

def _core(path=CORE, alias="ft2_test_cn_"):
    out = {}
    for name in ("close_next", "dispatch", "team_record"):
        spec = importlib.util.spec_from_file_location(alias + name, os.path.join(path, name + ".py"))
        out[name] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(out[name])
    return SimpleNamespace(cn=out["close_next"], dispatch=out["dispatch"], tr=out["team_record"])

M = _core()
FIELDS = {name: "없음" if name in M.tr.POINTERS else "0" for name in M.tr.FIELDS}

def _node(root, m=M, probe="absent", stop=None):
    def step(name):
        if name == stop:
            raise Boom(name)
    return m.cn.CloseNext(str(root), TEAM, clock=lambda: NOW, on_step=step,
                          probe=probe if callable(probe) else (lambda seat: probe))

def _facts(root, rows, name="facts.json"):
    (Path(root) / name).write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
    return str(Path(root) / name)

def _close(d, work, holder=NANO):
    assert [d.rs.submit("c-" + work, "x" * 8, work).result, d.assign(work, holder, evidence=EV).result,
            d.ex.result(work, holder, 1, OK).result, d.deliver(work, "a1").result,
            d.complete(work, "a1").result] == [OK] * 5

def _base(root, m=M, waiting=("W2",), enable=True, cap=None):
    os.makedirs(str(root), exist_ok=True)
    d = m.dispatch.Dispatch(str(root), TEAM, clock=lambda: NOW)
    d.rs.journal.segment_cap = cap or d.rs.journal.segment_cap
    _close(d, "W1")
    assert [d.rs.submit("c-" + work, "x" * 8, work).result for work in waiting] == [OK] * len(waiting)
    assert not enable or _node(root, m).enable(_facts(root, {NANO: ALL})).result == OK
    return d

def _go(root, m=M, event="e1", probe="absent", stop=None):
    return _node(root, m, probe, stop).receipt(NANO, 1, "W1", event, NEXT, EV)

def _lines(root, m=M, kind=None, work=None):
    return [rec for rec in _node(root, m).rs.records()
            if (kind is None or rec["kind"] == kind) and (work is None or rec.get("work") == work)]

def _c1(root, m=M):
    _base(root, m)
    out = _go(root, m)
    assert (out.result, out.next, out.attempt, out.holder) == (OK, "W2", "a1", NEXT)
    assert [rec["kind"] for rec in _lines(root, m)[-3:]] == ["close_receipt", "dispatch", "deliver"]
    assert _node(root, m).d.ex._state_records()[0]["owners"]["W2"]["holder"] == NEXT

def _c2(root, m=M):
    _base(root, m, waiting=())
    out = _go(root, m)
    assert (out.result, out.next, len(_lines(root, m, "dispatch"))) == (OK, NONE_NEXT, 1)

def _c3(root, m=M, probes=("alive",), want=((REFUSED, "부재 확인 없음"),)):   # 닫기 rc0 이어도 alive = 발주 0
    _base(root, m)
    lines, outs = len(_lines(root, m)), [_go(root, m, probe=p) for p in probes]
    assert ([(o.result, o.reason[:len(w[1])]) for o, w in zip(outs, want)], len(_lines(root, m))) == (list(want), lines)

def _c6(root, m=M):
    _c1(root, m)
    lines, out = len(_lines(root, m)), _go(root, m)
    assert (out.result, out.written, len(_lines(root, m))) == (HOLD, False, lines) and "재접수" in out.reason

def _crash_then_chain(root, m=M, stop=None):
    _base(root, m)
    with pytest.raises(Boom):
        _go(root, m, stop=stop)
    out = _go(root, m)
    assert (out.result, out.next, out.attempt, out.holder) == (OK, "W2", "a1", NEXT)
    assert _node(root, m).d._intent(_lines(root, m), "W2")["state"] == "delivered"
    assert [len(_lines(root, m, k, w)) for k, w in (("close_receipt", None), ("dispatch", "W2"),
                                                    ("deliver", "W2"))] == [1, 1, 1]   # 다시 e1 = 쓰기 0
    lines = len(_lines(root, m))
    assert (_go(root, m).result, len(_lines(root, m))) == (HOLD, lines)

def _c6r(root, m=M, events=("e1",)):            # C6z = e1(next W2) + e2([다음 없음]) 두 영수 줄 회수(보정 2)
    d = _base(root, m, cap=1024)
    assert [_go(root, m, e).next for e in events] == ["W2", NONE_NEXT][:len(events)]
    rows = _lines(root, m, "close_receipt")
    assert [rec["work"] for rec in rows] == ["close:%s:%s" % (TEAM, e) for e in events]
    assert [d.ex.result("W2", NEXT, 1, OK).result, d.complete("W2", "a1").result, _close(d, "W3"),
            _close(d, "W4")] == [OK, OK, None, None]
    base = (d.rs.journal.reclaim()["result"], d.rs.journal.state()["journal_base"])
    assert base[0] == "회수 결과" and base[1]["upto"] >= rows[-1]["seq"]
    assert sorted(base[1]["proj"]["close_receipts"]) == sorted(events)
    lines, outs = len(_lines(root, m)), [_go(root, m, e) for e in events]
    assert [(o.result, o.written, "재접수" in o.reason) for o in outs] + [len(_lines(root, m))] \
        == [(HOLD, False, True)] * len(events) + [lines]

_c3u = functools.partial(_c3, probes=("unknown", lambda seat: 1 / 0), want=((HOLD, "판정 불가 · "),) * 2)
_c6c = functools.partial(_crash_then_chain, stop="after_close_receipt_journal")
_c6d = functools.partial(_crash_then_chain, stop="after_dispatch")   # DA R1 반례 — 배정(a1) 뒤·전달 전 중단 → a1 전달만
_c6z = functools.partial(_c6r, events=("e1", "e2"))

def _c7(root, m=M):
    d = _base(root, m, enable=False)
    assert d.rs.submit("c-W9", "x" * 8, "W9").result == OK and d.assign("W9", NANO, evidence=EV).result == OK
    out = _node(root, m).enable(_facts(root, {NANO: ALL}))
    assert (out.result, out.reason) == (REFUSED, "켜기 거절 · 일하는 좌석 " + NANO)
    busy = _facts(root, {"S": dict(ALL, **{"진행 work": "W5"})}, "busy.json")
    assert _node(root, m, "alive").enable(busy).reason == "켜기 거절 · 일하는 좌석 S"
    assert _node(root, m, lambda seat: 1 / 0).enable(busy).result == HOLD
    assert not os.path.exists(_node(root, m).marker) and _go(root, m).reason.startswith("켜기 전")

SCENARIOS = {"C1": _c1, "C2": _c2, "C3": _c3, "C3u": _c3u, "C6": _c6, "C6c": _c6c, "C6d": _c6d, "C6r": _c6r,
             "C6z": _c6z, "C7": _c7}

@pytest.mark.parametrize("case", SCENARIOS.values(), ids=SCENARIOS.keys())
def test_scenarios(tmp_path, case):
    case(tmp_path)

def test_c4_arch_da_done_record_only(tmp_path):
    outs = [_node(tmp_path).seat_done(seat, expect, FIELDS) for expect, seat in enumerate((ARCH, DA, NANO))]
    assert [(o.result, o.revision, o.close_request) for o in outs] == [(OK, 1, False), (OK, 2, False), (REFUSED, None, False)]
    assert _lines(tmp_path, kind="close_receipt") == [] and M.tr.TeamRecord(str(tmp_path), TEAM).read().revision == 2

def test_c5_candidates_four_facts_read_only(tmp_path):
    _base(tmp_path, enable=False)
    before, rows = _node(tmp_path).d.ex._state_records()[0], {"A": ALL, "B": dict(ALL, **{"원격 보존": False}), "C": {"산출 완료": True}}
    got = _node(tmp_path).candidates(_facts(tmp_path, rows)).candidate
    assert got["A"] == {"candidate": True, "missing": []} and got["B"] == {"candidate": False, "missing": ["원격 보존"]}
    assert got["C"]["missing"] == list(FOUR[1:]) and _node(tmp_path).d.ex._state_records()[0] == before

def test_c8_busy_writes_nothing(tmp_path):
    _base(tmp_path)
    lines, lock = len(_lines(tmp_path)), _node(tmp_path).rs._try_lock()
    out = _go(tmp_path)
    lock.close()                                         # flock 풀림 = 닫기
    assert (out.result, len(_lines(tmp_path))) == (BUSY, lines)

def _cli(root, verb, *args):
    proc = subprocess.run([sys.executable, os.path.join(CORE, "cli.py"), verb, "--root", str(root), "--team", TEAM,
                           *args], capture_output=True, text=True, timeout=30, env=dict(os.environ, FT_NOW=NOW))
    return proc.returncode, json.loads(proc.stdout)

def test_c9_cli_four_verbs_rc(tmp_path):
    _base(tmp_path, enable=False)
    facts, fields = _facts(tmp_path, {NANO: ALL}), _facts(tmp_path, FIELDS, "fields.json")
    rc, out = _cli(tmp_path, "close-candidates", "--facts_file", facts)
    assert (rc, out["candidate"][NANO]["candidate"], _cli(tmp_path, "close-enable", "--seats_file", facts)[0]) == (0, True, 0)
    assert [_cli(tmp_path, "seat-done", "--seat", s, "--expect", e, "--fields_file", fields)[0]
            for s, e in ((ARCH, "0"), (NANO, "1"))] == [0, 1]
    base = ["--seat", NANO, "--gen", "1", "--work", "W1", "--event", "e1", "--next_holder", NEXT, "--evidence", "v1,v2"]
    rc, out = _cli(tmp_path, "close-receipt", *base)        # CLI 에는 probe 가 없다 = 판정 불가 · 쓰기 0
    assert (rc, out["result"], out["reason"].startswith("판정 불가 · ")) == (1, HOLD, True)
    assert [_cli(tmp_path, "close-receipt", *base[:2], "--gen", g, *base[4:])[0] for g in ("x", "0")] == [64, 1]
    assert _cli(tmp_path, "close-receipt", *base[:-2])[0] == 64

MUTANTS = (
    ("M1", "close_next.py", 'seen = self.probe(seat) if self.probe else "판독기 없음"', 'seen = "absent"', (_c3,)),
    ("M2", "close_next.py", "if seen is not None:", "if False:", (_c6,)),
    ("M3", "record.py", 'elif kind == "close_receipt" and work:', "elif False:", (_c6c, _c6r)),
    ("M4", "close_next.py", "if busy:", "if False:", (_c7,)),
    ("M5", "close_next.py", 'if intent.get("state") == "pending":', "if False:", (_c6d,)),
    ("M6", "record.py", "return marks", "return {}", (_c6z,)),
)

def _mutant(tmp_path, label, name, old, new):
    copy = tmp_path / "core"
    shutil.copytree(CORE, copy)
    text = (copy / name).read_text(encoding="utf-8")
    assert text.count(old) == 1, label
    (copy / name).write_text(text.replace(old, new, 1), encoding="utf-8")
    return _core(str(copy), "ft2_mut_cn_%s_" % label)

@pytest.mark.parametrize("label,name,old,new,cases", MUTANTS, ids=[m[0] for m in MUTANTS])
def test_mutants_break_their_cases(tmp_path, label, name, old, new, cases):
    mutant = _mutant(tmp_path, label, name, old, new)
    for idx, case in enumerate(cases):
        with pytest.raises((AssertionError, KeyError, TypeError)):
            case(tmp_path / ("run%d" % idx), mutant)

def test_m5_keeps_other_resubmit_cases(tmp_path):        # M5 = DA 반례 모델 — C6d 만 깨진다
    mutant = _mutant(tmp_path, "M5k", *MUTANTS[4][1:4])
    assert [case(tmp_path / ("run%d" % idx), mutant) for idx, case in enumerate((_c6, _c6c, _c6r))] == [None] * 3
