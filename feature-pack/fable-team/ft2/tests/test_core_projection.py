"""ft2 팀 상태 투영 시험 (r1596 · PR② 일곱째 장).

시험 입력 = 격리 tmp 팀데이터 루트 · 코어 라이브러리(intake·execution·dispatch)로 만든 runtime
(정상 생애 4 · 미확정 1 · 회수 뒤 1). ⓐ 투영 = `record.recover_state` · ⓑ 회수 전후 같음 ·
ⓒ 읽기 전용(sha256 동일 · 새 폴더 0)·legacy_guard rc0 · 변이 M1 = 회수 뒤 `journal_base.proj` 를
안 읽기 → ⓑ FAIL. press 0 · 실 runtime 0 · 기존 ft2 시험은 따로 돌린다(ⓒ «rc 불변»).
재진입 표지 = 없음(자기 파일을 다시 부르는 시험 0).
"""
import hashlib
import importlib.util
import os
import subprocess
import sys

FT_NOW = "2026-11-10T00:00:00"
HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
GUARD = os.path.join(FT2, "tools", "legacy_guard.py")
TEAM, EV = "harness", ("v1", "v2")
OK, HOLD, CORRUPT, RECLAIMED = "접수 성공", "완료 유보", "복구 필요", "회수 결과"
# 시험 인자 = cap 시험과 같은 값(회전을 일으켜 «회수 뒤» 를 만든다 · 제품 기본값 변경 0).
CAPS = dict(total_cap=65536, reserve=4096, segment_cap=1024, state_slack=512, line_max=512)
CLOCK = dict(clock=lambda: FT_NOW)
FIELDS = ("generations", "owners", "deliveries", "done", "uncertain")


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


intake, execution, dispatch = (_load(name) for name in ("intake", "execution", "dispatch"))
record, projection = _load("record"), _load("projection")


def _caps(node, **caps):
    """Execution·Dispatch 는 Intake 기본값을 쓴다 — 시험 인자를 journal 에 직접 걸어 조인다."""
    client = node.rs if hasattr(node, "rs") else node
    for key, value in {**CAPS, **caps}.items():
        setattr(client.journal, "reserve_bytes" if key == "reserve" else key, value)
    return node


def _close(dp, ex, work, holder="h1"):
    """정상 생애 1건 — 배정 → 결과 → 전달 → 완료(+재평가). 회수 조건을 만족시키는 최소 흐름."""
    grant = dp.assign(work, holder, evidence=EV)
    assert grant.result == OK, (work, grant)
    assert ex.result(work, holder, grant.gen, OK).result == OK, work
    assert dp.deliver(work).result == OK, work
    assert dp.complete(work).result == OK, work


def _life(root):
    """정상 생애 4(W1~W4 · 회전용으로 닫는다) · 미확정 1(U1) · 아직 안 집은 접수 1(W9)."""
    client = _caps(intake.Intake(str(root), TEAM, capacity=8, **CLOCK))
    ex, dp = _caps(execution.Execution(str(root), TEAM, **CLOCK)), _caps(dispatch.Dispatch(str(root), TEAM, **CLOCK))
    for work in ("W1", "W2", "W3", "W4"):
        assert client.submit("cmd-" + work, "body-" + work, work=work).result == OK, work
        _close(dp, ex, work)
    assert client.submit("cmd-U1", "body-U1", work="U1").result == OK
    grant = dp.assign("U1", "h2", evidence=EV)
    assert ex.mark_uncertain("U1", "h2", grant.gen, "무응답").result == HOLD
    assert client.submit("cmd-W9", "body-W9", work="W9").result == OK
    return client


def _snapshot(root):
    """runtime 폴더 파일 sha256 — 쓰기 0 판정(카드 ⓒ)."""
    out = {}
    for where, _dirs, names in os.walk(os.path.join(str(root), ".fable-team")):
        for name in sorted(names):
            path = os.path.join(where, name)
            with open(path, "rb") as handle:
                out[os.path.relpath(path, root)] = hashlib.sha256(handle.read()).hexdigest()
    return out


def _raw_state(root, raw):
    """state.json 만 깐 격리 루트 1개 — 손상 state 판독 시험용."""
    runtime = os.path.join(str(root), ".fable-team", "teams", TEAM, "runtime")
    os.makedirs(runtime, exist_ok=True)
    with open(os.path.join(runtime, "state.json"), "w", encoding="utf-8") as handle:
        handle.write(raw)
    return str(root)


def test_a_projection_matches_recover_state(tmp_path):
    """ⓐ — 작업별 {담당·세대·전달·완료·미확정} = recover_state 결과 · 대기 수 = pending 길이."""
    root = tmp_path / "a"
    client = _life(root)
    out = projection.project(str(root), TEAM)
    state = record.recover_state(client.journal.state(), client.records())
    assert out["result"] == OK and out["reason"] == ""
    assert out["revision"] == state["revision"]
    assert out["pending"] == len(state["pending"]) == 6
    assert sorted(out["works"]) == sorted(set().union(*[set(state[name]) for name in FIELDS]))
    for work, row in out["works"].items():
        assert row["owner"] == state["owners"].get(work), work
        assert row["gen"] == state["generations"].get(work, 0), work
        assert row["deliveries"] == (state["deliveries"].get(work) or []), work
        assert row["done"] == (work in state["done"]), work
        assert row["uncertain"] == (work in state["uncertain"]), work
    assert out["works"]["W1"] == {"owner": None, "gen": 1, "deliveries": ["a1"], "done": True,
                                  "uncertain": False}
    assert out["works"]["U1"]["uncertain"] is True and out["works"]["U1"]["owner"]["holder"] == "h2"
    # 아직 안 집은 접수(W9)는 작업 5칸 어디에도 없다 — «대기 수» 가 그 몫을 센다(pending 6 · 작업 5행).
    assert "W9" not in out["works"] and len(out["works"]) == 5


def test_b_reclaim_keeps_projection_same(tmp_path):
    """ⓑ — 회수 전·후 투영 같음(journal_base.proj 사용) · 읽기는 몇 번 해도 같은 값(멱등)."""
    root = tmp_path / "b"
    client = _life(root)
    before = projection.project(str(root), TEAM)
    assert client.journal.closed(), "회전 0 = 회수 대상 없음(시험 입력이 모자라다)"
    reclaimed = client.journal.reclaim()
    assert (reclaimed["result"], bool(reclaimed["reclaimed"])) == (RECLAIMED, True)
    after = projection.project(str(root), TEAM)
    assert after == before
    assert projection.project(str(root), TEAM) == after
    assert after["works"]["W1"]["done"] is True and after["works"]["U1"]["uncertain"] is True


def test_b2_corrupt_state_is_recovery_needed_and_no_works(tmp_path):
    """ⓑ — 손상 state = «복구 필요» 1줄 + 투영 0(추측 0) · journal 손상도 같은 꼴."""
    out = projection.project(_raw_state(tmp_path / "corrupt", "{not json"), TEAM)
    assert (out["result"], out["works"], out["pending"]) == (CORRUPT, {}, 0)
    assert out["reason"]
    broken = _raw_state(tmp_path / "broken", '{"schema": 1, "revision": 1}')
    runtime = os.path.join(broken, ".fable-team", "teams", TEAM, "runtime")
    with open(os.path.join(runtime, "journal.jsonl"), "w", encoding="utf-8") as handle:
        handle.write("{not a record}\n")
    out = projection.project(broken, TEAM)
    assert (out["result"], out["works"]) == (CORRUPT, {}) and out["reason"]


def test_c_projection_writes_nothing(tmp_path):
    """ⓒ — 투영 전·후 runtime 파일 sha256 전부 같음 · 없는 runtime 에 새 폴더 0 · guard rc0."""
    root = tmp_path / "c"
    _life(root)
    before = _snapshot(root)
    first = projection.project(str(root), TEAM)
    assert projection.project(str(root), TEAM) == first
    assert _snapshot(root) == before
    absent = str(tmp_path / "absent")
    assert projection.project(absent, TEAM)["works"] == {}
    assert not os.path.exists(os.path.join(absent, ".fable-team"))
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
    assert client.journal.reclaim()["reclaimed"]
    assert projection.project(str(root), TEAM) == before
    real, projection.record = projection.record, _NoBase(projection.record)
    try:
        assert projection.project(str(root), TEAM) != before
    finally:
        projection.record = real
