"""ft2 코어 휴면 경계 시험 (r1714 · 카드 r1714-dormancy-close-marker-cas-no-grant).

경계 = 팀 휴면의 «재검사 → 팀 기록 확정 → 최종 닫힘 영수» 를 writer.lock 안 revision 대조 1건
(`Lifecycle.close("dormant:<팀>", R)`) 으로 묶고, 표식 뒤 접수는 닫는 세대에서 실행권을 받지 못한다.

| 사례 | given 1줄 | 호출 1개 |
|---|---|---|
| ① 재검사 뒤 접수 | R 읽기 → Q 접수 | `close("dormant:harness", R)` = RETRY |
| ② 표식 | 접수 0 | `close("dormant:harness", R)` = CLOSED 1줄 |
| ③ 표식 뒤 접수 | 표식 → Q 접수 | `claim(Q, "h1")` = 접수 거부 |
| ④ 다른 팀 표식 | `close("dormant:other-team", R)` → Q | `claim(Q, "h1")` = 접수 성공 |
| ⑤ 일반 골 마감만 | `close("goal-normal", R)` → Q | `claim(Q, "h1")` = 접수 성공 |

시험 입력 = 격리 tmp 팀 runtime 루트 · FT_NOW 고정 시계 · sleep 0 · 사례 70초 안.
변이 M1 표식 검사 삭제 · M2 표식 접두만 대조 · M3 revision 대조 삭제 = 각각 ③ ④ ① 을 깬다.
재진입 표지 = 없음(자기 파일을 다시 부르는 시험 0).
"""
import importlib.util
import os

import pytest

FT_NOW = "2026-11-10T00:00:00"
HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
TEAM, OTHER = "harness", "other-team"
OK, HOLD, REFUSED, BUSY = "접수 성공", "완료 유보", "접수 거부", "BUSY"
CLOCK = dict(clock=lambda: FT_NOW)


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, execution, lifecycle = (_load(name) for name in
                                       ("record", "intake", "execution", "lifecycle"))


def _lines(node):
    return len(node._state_records()[1])


def _pending(node):
    state, records = node._state_records()
    return sorted(work for work in record.remaining(state, records))


def _marked(root, goal="dormant:" + TEAM):
    """② 표식 1건만 세운 runtime — 접수 0 이므로 CLOSED."""
    node = lifecycle.Lifecycle(root, TEAM, **CLOCK)
    out = node.close(goal, node._state_records()[0]["revision"])
    assert (out.status, out.result, out.written) == ("CLOSED", OK, True)
    return root, node


def test_1_submit_after_rescan_makes_marker_retry(tmp_path):
    """① 재검사 R → 접수 Q → 표식(R) = RETRY · 쓰기 0 · Q pending 그대로(회귀)."""
    root = str(tmp_path / "c1")
    node, client = lifecycle.Lifecycle(root, TEAM, **CLOCK), intake.Intake(root, TEAM, **CLOCK)
    read_rev = node._state_records()[0]["revision"]
    assert client.submit("q-1", "body", work="q-1").result == OK
    lines = _lines(node)
    out = node.close("dormant:" + TEAM, read_rev)
    assert (out.result, out.status, out.written) == (HOLD, "RETRY", False)
    assert _lines(node) == lines                                   # RETRY = 쓰기 0
    assert "goal:dormant:" + TEAM not in node._state_records()[0]["done"]
    assert _pending(node) == ["q-1"]                               # 접수 pending 그대로


def test_2_marker_without_intake_closes_once(tmp_path):
    """② 접수 없음 → 표식 = close 1줄(done 키 = goal:dormant:<팀>) (회귀)."""
    root = str(tmp_path / "c2")
    node = lifecycle.Lifecycle(root, TEAM, **CLOCK)
    out = node.close("dormant:" + TEAM, node._state_records()[0]["revision"])
    assert (out.status, out.result, out.written) == ("CLOSED", OK, True)
    state, records = node._state_records()
    assert len(records) == 1 and records[0]["kind"] == "close"
    assert state["done"]["goal:dormant:" + TEAM]["at"] == FT_NOW
    again = node.close("dormant:" + TEAM, state["revision"])
    assert (again.status, again.written) == ("CLOSED", False)       # 멱등 = 쓰기 0


def test_3_claim_after_marker_is_refused(tmp_path):
    """③ 표식 뒤 접수 Q → claim = 접수 거부 · 쓰기 0 · Q pending (기준판 = 접수 성공 · FAIL)."""
    root, _ = _marked(str(tmp_path / "c3"))
    node, client, ex = lifecycle.Lifecycle(root, TEAM, **CLOCK), intake.Intake(root, TEAM, **CLOCK), \
        execution.Execution(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    lines = _lines(node)
    out = ex.claim("q-1", "h1")
    assert (out.result, out.written) == (REFUSED, False)
    assert "휴면 표식" in out.reason
    assert _lines(node) == lines                                   # claim 줄 0
    state = node._state_records()[0]
    assert "q-1" not in (state.get("generations") or {})
    assert "q-1" not in (state.get("owners") or {})
    assert _pending(node) == ["q-1"]                               # 영속 큐 = planner 판단


def test_4_marker_of_other_team_does_not_block(tmp_path):
    """④ 다른 팀 표식만 있으면 claim 그대로 성공(M2 접두 대조 = FAIL)."""
    root, _ = _marked(str(tmp_path / "c4"), goal="dormant:" + OTHER)
    client, ex = intake.Intake(root, TEAM, **CLOCK), execution.Execution(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    out = ex.claim("q-1", "h1")
    assert (out.result, out.written) == (OK, True)


def test_5_plain_goal_close_does_not_block(tmp_path):
    """⑤ 표식 없음 · 일반 골 close 만 있으면 claim 그대로 성공."""
    root, _ = _marked(str(tmp_path / "c5"), goal="normal-goal")
    client, ex = intake.Intake(root, TEAM, **CLOCK), execution.Execution(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    assert ex.claim("q-1", "h1").result == OK


class _NoMarkerCheck(execution.Execution):
    """M1 — 표식 검사 삭제(claim 이 표식을 보지 않는다)."""

    def _dormant_marker(self, state):
        return None


class _PrefixOnlyMarker(execution.Execution):
    """M2 — 표식 키를 팀 대조 없이 접두로만 본다."""

    def _dormant_marker(self, state):
        return next((key for key in (state.get("done") or {}) if key.startswith("goal:dormant:")), None)


class _NoRevisionCheck(lifecycle.Lifecycle):
    """M3 — revision 대조 삭제."""

    def _revision_stale(self, state, revision):
        return False


def test_m1_without_marker_check_breaks_case_3(tmp_path):
    root, _ = _marked(str(tmp_path / "m1"))
    client = intake.Intake(root, TEAM, **CLOCK)
    ex = _NoMarkerCheck(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    assert ex.claim("q-1", "h1").result != REFUSED                  # 계약은 REFUSED


def test_m2_prefix_only_marker_breaks_case_4(tmp_path):
    if not hasattr(execution.Execution, "_dormant_marker"):    # 기준판 = 표식 검사 자리 자체가 없다
        pytest.skip("기준판에는 변이 결선 자리가 없다(계약 ③ 이 FAIL 하는 그 판)")
    root, _ = _marked(str(tmp_path / "m2"), goal="dormant:" + OTHER)
    client = intake.Intake(root, TEAM, **CLOCK)
    ex = _PrefixOnlyMarker(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    assert ex.claim("q-1", "h1").result != OK                       # 계약은 접수 성공


def test_m3_without_revision_check_breaks_case_1(tmp_path):
    root = str(tmp_path / "m3")
    node, client = _NoRevisionCheck(root, TEAM, **CLOCK), intake.Intake(root, TEAM, **CLOCK)
    read_rev = node._state_records()[0]["revision"]
    assert client.submit("q-1", "body", work="q-1").result == OK
    assert node.close("dormant:" + TEAM, read_rev).status != "RETRY"   # 계약은 RETRY
