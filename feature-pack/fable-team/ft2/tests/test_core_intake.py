"""ft2 코어 입구 시험 (r1576 · PR② 첫 장).

계약 사례 = `ft2/contracts/core/CASES.md`. 입구에 닿는 5건만 본다. `given` 은 자연어 사건
열이라 «given 1줄 = 호출 1개» 대응표를 먼저 둔다.

| 사례 | given 1줄 | 호출 1개 |
|---|---|---|
| case_01_happy_life | 접수 card-1 / card-2 | `Intake.submit("card-1", 본문)` |
| case_03_same_key | 같은 키 재접수 card-x | `Intake.submit("card-x", 본문)` (두 번째) |
| case_06_accept_crash | 자식 crash-accept-pre / -post | 자식 `submit` + 부모 `lookup`/`submit` |
| case_08_expiry_full | 초과 접수 pending-over | `Intake.submit("pending-over", 본문)` |
| case_12_corrupt | state 를 29바이트 손상본으로 교체 | `Intake.submit("card-2", 본문)` |

변이 M1~M5 는 «검사기가 실제로 잡는가»만 본다. 변이 1개 = `Intake` 하위 클래스 1개이고,
격리 tmp 팀 데이터 루트만 쓴다(실 runtime·실 우편함 0).
"""

import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM = "harness"
OK, HOLD, FULL, CORRUPT = "접수 성공", "완료 유보", "용량 부족", "복구 필요"
CORRUPT_LINE = b'{"schema": 1, "revision": 2, '

def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

intake = _load("intake")
record = _load("record")

def _client(root, capacity=8, cls=None, on_step=None):
    return (cls or intake.Intake)(str(root), TEAM, capacity=capacity, on_step=on_step)

def _state_bytes(client):
    return Path(client.state_path).read_bytes()

def _ops(client):
    if not os.path.exists(client.ops_path):
        return []
    with open(client.ops_path, encoding="utf-8") as handle:
        return [json.loads(line)["op"] for line in handle if line.strip()]

def _order_check(client):
    return intake.order_violations(_ops(client))

def _same_key_check(client, command):
    if client.submit(command, "본문-1").result != OK:
        return ["첫 접수 실패"]
    second = client.submit(command, "본문-2")
    attempts = [rec["attempt"] for rec in client.records() if rec["command"] == command]
    found = [] if second.result == HOLD and not second.written else [
        "재요청 %r written=%r" % (second.result, second.written)]
    found += ["journal 중복"] if intake.duplicate_commands(client.records()) else []
    return found + ([] if len(attempts) == 1 else ["attempt %d개" % len(attempts)])

def _capacity_check(client, over="pending-over"):
    before, receipts = _state_bytes(client), _ops(client).count("receipt")
    receipt = client.submit(over, "본문-over")
    found = ["결과 %r" % receipt.result] if receipt.result != FULL else []
    if receipt.written or _ops(client).count("receipt") != receipts:
        found.append("성공 영수 발생")
    if _state_bytes(client) != before:
        found.append("state 변경")
    return found

def _corrupt_check(client, command, before):
    receipt = client.submit(command, "본문-2")
    found = ["결과 %r" % receipt.result] if receipt.result != CORRUPT else []
    if receipt.written or _state_bytes(client) != before:
        found.append("쓰기 발생")
    if os.path.exists(client.body_path(command)):
        found.append("본문 생성")
    return found

def _crash_verdict(client, command):
    look = client.lookup(command)
    found = [] if look is not None and look.result in (OK, HOLD) else ["판정 %r" % (look and look.result)]
    if client.submit(command, "본문-재요청").result not in (OK, HOLD):
        found.append("재요청 결과 이상")
    duplicates = intake.duplicate_commands(client.records())
    found += ["journal 중복 %r" % duplicates] if duplicates else []
    attempts = {rec["attempt"] for rec in client.records() if rec["command"] == command}
    return found + ([] if len(attempts) <= 1 else ["attempt %d개" % len(attempts)])

def test_case_01_accept_succeeds_only_after_durability(tmp_path):
    client = _client(tmp_path / "team")
    first, second = client.submit("card-1", "본문-1"), client.submit("card-2", "본문-2")
    assert (first.result, second.result, first.written, second.written) == (OK, OK, True, True)
    assert _order_check(client) == []
    assert _ops(client).index("journal_fsync") < _ops(client).index("receipt")
    assert os.path.getsize(client.body_path("card-1")) == len("본문-1".encode("utf-8"))
    records = client.records()
    assert [rec["command"] for rec in records] == ["card-1", "card-2"]
    assert [rec["seq"] for rec in records] == [1, 2]
    assert json.loads(_state_bytes(client))["revision"] == 2

def test_case_03_same_key_is_hold_without_new_attempt(tmp_path):
    client = _client(tmp_path / "team")
    assert _same_key_check(client, "card-x") == []
    state = json.loads(_state_bytes(client))
    assert (state["revision"], state["pending"]) == (1, ["card-x"])

def test_case_06_accept_crash(tmp_path):
    for step, lines in (("after_body", 0), ("after_journal", 1)):
        root = tmp_path / step
        assert _crash_run(root, step).returncode == 9
        client = _client(root)
        assert (len(client.records()), os.path.exists(client.state_path)) == (lines, False)
        assert _crash_verdict(client, "card-pre") == []
        assert len(client.records()) == lines

def test_case_08_full_keeps_pending_without_success_ack(tmp_path):
    client = _client(tmp_path / "team", capacity=2)
    for command in ("p-1", "p-2"):
        assert client.submit(command, "본문").result == OK
    assert _capacity_check(client) == []
    assert json.loads(_state_bytes(client))["pending"] == ["p-1", "p-2"]
    # R1(DA HOLD §2): state checkpoint 없이 crash 한 접수도 용량에 센다 = 기준은 journal
    root = tmp_path / "crash"
    assert _crash_run(root, "after_journal", capacity=1).returncode == 9
    crashed = _client(root, capacity=1)
    assert crashed.lookup("card-pre").result == OK
    second = crashed.submit("card-2", "본문-2")
    assert (second.result, second.written, os.path.exists(crashed.body_path("card-2"))) == (FULL, False, False)

def _done_team(root, count, done):  # r1791: done 은 complete event 로(state.done 만 고치면 replay 가 덮는다 · DA)
    client = _client(root, capacity=count)
    assert all(client.submit("card-%d" % n, "본문", work="work-%d" % n).result == OK for n in range(1, count + 1))
    if done:
        client._append_journal(record.build(TEAM, count + 1, "done-1", "a1", "2026-11-13T00:00:00", "",
                                            work="work-1", kind="complete", extra={"after": "a1", "marker": ""}))
    return client

def test_r1791_full_reason_counts_remaining_with_ledger_in_parens(tmp_path):
    for name, count, done, cap, want in (("c1", 3, True, 2, "남은 일 2 >= 상한 2 (접수 장부 3)"),
                                         ("c2", 2, False, 2, "남은 일 2 >= 상한 2 (접수 장부 2)"), ("c3", 3, True, 3, None)):
        client = _done_team(tmp_path / name, count, done)
        client.capacity, before = cap, (_state_bytes(client), Path(client.journal_path).read_bytes())
        got = client.submit("new-card", "본문-new", work="new-work")
        if want is None:
            assert (got.result, got.written) == (OK, True)
            continue
        assert (got.result, got.reason, got.attempt, got.written) == (FULL, want, None, False)
        assert (_state_bytes(client), Path(client.journal_path).read_bytes()) == before

def test_case_12_corrupt_state_needs_recovery(tmp_path):
    client = _client(tmp_path / "team")
    assert client.submit("card-1", "본문-1").result == OK
    with open(client.state_path, "wb") as handle:
        handle.write(CORRUPT_LINE)
    assert os.path.getsize(client.state_path) == 29
    assert _corrupt_check(client, "card-2", _state_bytes(client)) == []
    assert len(client.records()) == 1

def test_case_12_state_pending_not_list_refused_before_write(tmp_path):
    """R2(DA HOLD §2): schema1 인데 pending 형이 틀리면 본문·journal 을 만들기 «전» 에 거절한다."""
    client = _client(tmp_path / "team")
    assert client.submit("card-1", "본문-1").result == OK
    broken_state = dict(json.loads(_state_bytes(client)), pending={})
    with open(client.state_path, "w", encoding="utf-8") as handle:
        json.dump(broken_state, handle)
    before = (_state_bytes(client), Path(client.journal_path).read_bytes())
    receipt = client.submit("card-2", "본문-2")
    assert (receipt.result, receipt.written) == (CORRUPT, False)
    assert (_state_bytes(client), Path(client.journal_path).read_bytes()) == before
    assert not os.path.exists(client.body_path("card-2"))

def test_f_result_words_and_schema_refusal(tmp_path):
    client = _client(tmp_path / "team")
    seen = {client.submit("card-1", "본문-1").result, client.submit("card-1", "본문-1").result}
    assert all(record.is_contract_result(word) for word in seen)
    doomed = dict(json.loads(_state_bytes(client)), schema=2)
    with open(client.state_path, "w", encoding="utf-8") as handle:
        json.dump(doomed, handle)
    receipt = client.submit("card-2", "본문-2")
    assert (receipt.result, receipt.written) == (CORRUPT, False)
    assert json.loads(_state_bytes(client)) == doomed
    assert record.build(TEAM, 1, "card-9", "card-9#a1", "2026-11-10T00:00:00", "bodies/x.body")["schema"] == 1

def test_g_legacy_guard_rc0():
    done = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert done.returncode == 0, done.stdout.decode("utf-8", "replace")

class _ReceiptEarly(intake.Intake):  # M1: 영수를 journal fsync 앞으로
    def _ops(self, op):
        if op == "body_tmp_write":
            super()._ops("receipt")
        super()._ops(op)

class _NoDedup(intake.Intake):  # M2·M3: 같은 command 판정·미확정 본문을 무시
    _prior_receipt = lambda self, records, command: None  # noqa: E731
    _orphan_body = lambda self, command: False  # noqa: E731

class _NoCap(intake.Intake):  # M4: 포화에도 접수
    _full = lambda self, pending: False  # noqa: E731

class _OverwriteCorrupt(intake.Intake):  # M5: 손상 state 를 빈 상태로 덮어씀
    def _state(self):
        try:
            return super()._state()
        except intake.CorruptStateError:
            return {"schema": 1, "revision": 0, "pending": [], "attempts": {}}

def test_mutation_m1_receipt_before_journal_fsync(tmp_path):
    client = _client(tmp_path / "team", cls=_ReceiptEarly)
    client.submit("card-1", "본문-1")
    assert _order_check(client) != []

def test_mutation_m2_new_attempt_on_same_command(tmp_path):
    assert _same_key_check(_client(tmp_path / "team", cls=_NoDedup), "card-x") != []

def test_mutation_m3_crash_retry_as_new_work(tmp_path):
    root = tmp_path / "team"
    assert _crash_run(root, "after_journal").returncode == 9
    assert _crash_verdict(_client(root, cls=_NoDedup), "card-pre") != []

def test_mutation_m4_success_ack_when_full(tmp_path):
    client = _client(tmp_path / "team", capacity=2, cls=_NoCap)
    [client.submit(command, "본문") for command in ("p-1", "p-2")]
    assert _capacity_check(client) != []

def test_mutation_m5_overwrite_corrupt_state(tmp_path):
    client = _client(tmp_path / "team", cls=_OverwriteCorrupt)
    client.submit("card-1", "본문-1")
    with open(client.state_path, "wb") as handle:
        handle.write(CORRUPT_LINE)
    assert _corrupt_check(client, "card-2", _state_bytes(client)) != []

def _crash_run(root, step, capacity=8):
    env = dict(os.environ, FT2_INTAKE_CHILD="1")
    return subprocess.run([sys.executable, os.path.abspath(__file__), str(root), step, str(capacity)],
                          env=env, capture_output=True, timeout=25)

def _child_main(argv):
    root, step, capacity = argv[0], argv[1], int(argv[2])

    def hook(point):
        if point == step:
            os._exit(9)

    _client(root, capacity=capacity, on_step=hook).submit("card-pre", "본문-pre")
    return 0

if __name__ == "__main__":
    if os.environ.get("FT2_INTAKE_CHILD") != "1":
        sys.exit(0)
    sys.exit(_child_main(sys.argv[1:]))
