"""r1824 — dict work(Slack 접수)도 complete 뒤 «남은 일» 에서 빠진다(core record.remaining 1식).

계약: K1 work 가 문자열이 아니면 command 로 done 대조 · K2 문자열 work 는 work 로만 · K3 folded 빼기 그대로.
⑤ 경로(DA 메모): dict accept 는 command 로 assign 하면 «영수 없음» 이라, 실제 공개 Dispatch.complete
직접 호출(work = command)로 done[command] 를 세운다. 배정 관문 확장·가짜 성공 0. 임시 root 만 쓴다.
"""

import importlib.util
import os

CORE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core")
TEAM = "harness"
OK, FULL = "접수 성공", "용량 부족"


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, dispatch = _load("record"), _load("intake"), _load("dispatch")
SLACK = {"route": "slack", "slack": {"channel": "C1", "ts": "1.0"}}
MARK = {"attempt": None, "at": "t", "marker": ""}


def _left(work, done=(), pending=(), folded=()):
    state = {"pending": list(pending), "done": {key: MARK for key in done},
             "journal_base": {"receipts": {key: {} for key in folded}}}
    records = [] if work is None else [{"kind": "accept", "command": "c1", "work": work}]
    return record.remaining(state, records)


def test_case1_dict_work_done_by_command_leaves():
    assert _left(dict(SLACK), done=["c1"]) == []


def test_case1b_dict_work_not_done_stays():
    assert _left(dict(SLACK)) == ["c1"]


def test_case2_str_work_done_leaves():
    assert _left("w1", done=["w1"]) == []


def test_case2b_str_work_command_only_done_stays():
    assert _left("w1", done=["c1"]) == ["c1"]


def test_case3_pending_only_done_by_command_leaves():
    assert _left(None, pending=["c1"], done=["c1"]) == []


def test_case3b_pending_only_not_done_stays():
    assert _left(None, pending=["c1"]) == ["c1"]


def test_case4_folded_receipt_leaves():
    assert _left(dict(SLACK), folded=["c1"]) == []
    assert _left("w1", folded=["c1"]) == []


def test_case5_real_core_capacity_returns_after_complete(tmp_path):
    root = str(tmp_path / "team")
    gate = intake.Intake(root, TEAM, capacity=2)
    assert gate.submit("c1", "본문1", dict(SLACK)).result == OK
    assert gate.submit("c2", "본문2", dict(SLACK)).result == OK
    assert gate.submit("c3", "본문3", dict(SLACK)).result == FULL
    grant = dispatch.Dispatch(root, TEAM).complete("c1")       # 실제 공개 complete 직접 호출(work = command)
    assert (grant.result, grant.written) == (OK, True)
    assert gate.submit("c3", "본문3", dict(SLACK)).result == OK
