"""ft2 팀 상태 투영 시험 (r1596 · PR② 일곱째 장).

시험 입력 = 격리 tmp 팀데이터 루트 · 코어 라이브러리(intake·execution·dispatch)로 만든 runtime
(정상 생애 4 · 미확정 1 · 회수 뒤 1). ⓐ 투영 = `record.recover_state` · ⓑ 회수 전후 같음 · R1(DA 회차1)
손상 state·checkpoint = «복구 필요» 1줄 · ⓒ 읽기 전용(sha256 동일 · 새 폴더 0)·guard rc0 · 변이 M1 = 회수 뒤
`journal_base.proj` 를 안 읽기 → ⓑ FAIL. press 0 · 실 runtime 0 · 재진입 표지 = 없음.
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

FT_NOW = "2026-11-10T00:00:00"
HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE, GUARD = os.path.join(FT2, "core"), os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, EV = "harness", ("v1", "v2")
OK, HOLD, CORRUPT, RECLAIMED = "접수 성공", "완료 유보", "복구 필요", "회수 결과"
CAPS = dict(total_cap=65536, reserve=4096, segment_cap=1024, state_slack=512, line_max=512)  # 회전용
CLOCK = dict(clock=lambda: FT_NOW)


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


intake, execution, dispatch, record, projection = (
    _load(name) for name in ("intake", "execution", "dispatch", "record", "projection"))


def _life(root):
    """정상 생애 4(W1~W4 · 회전용으로 닫는다) · 미확정 1(U1) · 아직 안 집은 접수 1(W9)."""
    client = intake.Intake(str(root), TEAM, capacity=8, **CLOCK)
    ex, dp = execution.Execution(str(root), TEAM, **CLOCK), dispatch.Dispatch(str(root), TEAM, **CLOCK)
    for node in (client, ex, dp):                     # cap 시험 값을 journal 에 직접 건다(회전 만들기)
        for key, value in CAPS.items():
            setattr((node.rs if hasattr(node, "rs") else node).journal,
                    "reserve_bytes" if key == "reserve" else key, value)
    for work in ("W1", "W2", "W3", "W4"):
        assert client.submit("cmd-" + work, "body-" + work, work=work).result == OK, work
        grant = dp.assign(work, "h1", evidence=EV)     # 배정 → 결과 → 전달 → 완료(+재평가)
        assert (grant.result, ex.result(work, "h1", grant.gen, OK).result) == (OK, OK), work
        assert (dp.deliver(work).result, dp.complete(work).result) == (OK, OK), work
    assert client.submit("cmd-U1", "body-U1", work="U1").result == OK
    grant = dp.assign("U1", "h2", evidence=EV)
    assert ex.mark_uncertain("U1", "h2", grant.gen, "무응답").result == HOLD
    assert client.submit("cmd-W9", "body-W9", work="W9").result == OK
    return client


def _write_state(root, state):
    """state.json 만 다시 쓴다 — 손상 판독 시험용(제품 쓰기 경로 0). 루트를 돌려준다."""
    path = os.path.join(str(root), ".fable-team", "teams", TEAM, "runtime", "state.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(state if isinstance(state, str) else json.dumps(state))
    return str(root)


def _snapshot(root):
    """runtime 폴더 파일 sha256 — 쓰기 0 판정(카드 ⓒ)."""
    paths = [os.path.join(where, name) for where, _dirs, names in
             os.walk(os.path.join(str(root), ".fable-team")) for name in names]
    return {os.path.relpath(p, root): hashlib.sha256(open(p, "rb").read()).hexdigest() for p in paths}


def test_a_projection_matches_recover_state(tmp_path):
    """ⓐ — 작업별 {담당·세대·전달·완료·미확정} = recover_state 결과 · 대기 수 = pending 길이."""
    root = tmp_path / "a"
    client = _life(root)
    state = record.recover_state(client.journal.state(), client.records())
    out = projection.project(str(root), TEAM)
    assert (out["result"], out["reason"], out["revision"]) == (OK, "", state["revision"])
    assert (out["pending"], len(out["works"])) == (len(state["pending"]), 5) == (6, 5)
    for work, row in out["works"].items():
        assert (row["owner"], row["gen"], row["deliveries"]) == (state["owners"].get(work),
            state["generations"].get(work, 0), state["deliveries"].get(work) or []), work
        assert (row["done"], row["uncertain"]) == (work in state["done"], work in state["uncertain"])
    assert out["works"]["W1"] == {"owner": None, "gen": 1, "deliveries": ["a1"], "done": True, "uncertain": False}
    assert out["works"]["U1"]["uncertain"] is True and out["works"]["U1"]["owner"]["holder"] == "h2"
    assert "W9" not in out["works"]          # 안 집은 접수는 5칸에 없다 — «대기 수» 가 그 몫을 센다


def test_b_reclaim_keeps_projection_same(tmp_path):
    """ⓑ — 회수 전·후 투영 같음(journal_base.proj 사용) · 읽기는 몇 번 해도 같은 값(멱등)."""
    root = tmp_path / "b"
    client = _life(root)
    before = projection.project(str(root), TEAM)
    reclaimed = client.journal.reclaim()
    assert (reclaimed["result"], bool(reclaimed["reclaimed"]), bool(client.journal.closed())) == (RECLAIMED, True, True)
    assert projection.project(str(root), TEAM) == before == projection.project(str(root), TEAM)
    assert before["works"]["W1"]["done"] is True and before["works"]["U1"]["uncertain"] is True


def test_r1_corrupt_state_or_checkpoint_is_recovery_needed(tmp_path):
    """R1(DA 회차1) — 읽을 수 없는 state · 회수 뒤 journal_base.upto 손상 모두 예외가 아니라 결과 칸이다."""
    out = projection.project(_write_state(tmp_path / "raw", "{not json"), TEAM)
    assert (out["result"], out["works"], out["pending"], bool(out["reason"])) == (CORRUPT, {}, 0, True)
    root = tmp_path / "r1"
    client = _life(root)
    assert client.journal.reclaim()["reclaimed"]
    state = client.journal.state()
    state["journal_base"]["upto"] -= 1        # suffix seq 불연속 = recover_state 가 «복구 필요»
    _write_state(root, state)
    before, out = _snapshot(root), projection.project(str(root), TEAM)
    assert (out["result"], out["works"], out["pending"]) == (CORRUPT, {}, 0) and out["reason"]
    assert _snapshot(root) == before                    # 손상 상태에서도 쓰기 0(읽기 전용 유지)


def test_c_projection_writes_nothing(tmp_path):
    """ⓒ — 투영 전·후 runtime 파일 sha256 전부 같음 · 없는 runtime 에 새 폴더 0 · guard rc0."""
    root = tmp_path / "c"
    _life(root)
    before = _snapshot(root)
    first = projection.project(str(root), TEAM)
    assert projection.project(str(root), TEAM) == first and _snapshot(root) == before
    absent = str(tmp_path / "absent")
    assert projection.project(absent, TEAM)["works"] == {} and not os.path.exists(
        os.path.join(absent, ".fable-team"))
    guard = subprocess.run([sys.executable, "-I", GUARD], capture_output=True, timeout=25)
    assert guard.returncode == 0, guard.stdout.decode("utf-8", "replace")


class _NoBase:
    """변이 M1 자리 — 회수 뒤 `journal_base.proj` 를 안 읽고 남은 줄만 접는다."""

    def __init__(self, rec):
        self._rec = rec
    def __getattr__(self, name):
        return getattr(self._rec, name)
    def recover_state(self, state, records):
        return self._rec.recover_state(dict(state, journal_base={}), records)


def test_m1_ignoring_journal_base_breaks_reclaim_equality(tmp_path):
    """M1 — 회수 뒤 base 를 안 읽으면 ⓑ 가 깨진다(제품 자리 1곳 변이)."""
    root = tmp_path / "m1"
    client = _life(root)
    before = projection.project(str(root), TEAM)
    assert client.journal.reclaim()["reclaimed"] and projection.project(str(root), TEAM) == before
    real, projection.record = projection.record, _NoBase(projection.record)
    try:
        assert projection.project(str(root), TEAM) != before
    finally:
        projection.record = real
