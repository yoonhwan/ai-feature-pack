"""ft2 코어 진행 구분·골 마감 시험 (r1594 · PR② 다섯째 장).

계약 사례 = `ft2/contracts/core/cases/10-progress-distinction.json` · `11-close-race.json`.
시험 입력 = 격리 tmp 팀 runtime 루트 · FT_NOW 고정 시계(clock=lambda: FT_NOW) · 사례 given 순서 그대로.
ⓐ 진행 구분(사례 10) · ⓑ 마감 경합(사례 11) · ⓒ 기존 ft2 시험 불변(따로 실행) · 변이 M1 heartbeat=진행 ·
M2 revision 대조 삭제. 재진입 표지 = 없음(자기 파일을 다시 부르는 시험 0).
"""
import importlib.util
import json
import os

FT_NOW = "2026-11-10T00:00:00"
HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
CASES = os.path.join(FT2, "contracts", "core", "cases")
TEAM = "harness"
OK, HOLD, REFUSED = "접수 성공", "완료 유보", "접수 거부"
CLOCK = dict(clock=lambda: FT_NOW)


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, execution, dispatch, lifecycle = (_load(name) for name in
                                                 ("record", "intake", "execution", "dispatch", "lifecycle"))


def _case(name):
    with open(os.path.join(CASES, name), encoding="utf-8") as handle:
        return json.load(handle)


def _seed_lanes(node):
    """사례 10 given 순서: B 진척 1 · C 진척+외부 대기 · D 진척+heartbeat · A 진척 2."""
    for lane, kind in (("lane-b", "progress"), ("lane-c", "progress"), ("lane-c", "external_wait"),
                       ("lane-d", "progress"), ("lane-d", "heartbeat"),
                       ("lane-a", "progress"), ("lane-a", "progress")):
        out = node.progress("card-" + lane, lane, kind, deadline=5 if kind == "external_wait" else None)
        assert out.result == OK and out.written is True, (lane, kind, out)


def test_a_case_10_progress_distinction(tmp_path):
    node = lifecycle.Lifecycle(str(tmp_path / "p"), TEAM, **CLOCK)
    _seed_lanes(node)
    scan = node.scan(stall_after=3)
    lanes = scan.lanes
    assert scan.result == HOLD == _case("10-progress-distinction.json")["expect"]["처리 결과"]
    assert scan.tick == 7
    assert lanes["lane-a"]["stalled"] is False                     # A 진척 = 멈춤 아님
    assert "lane-b" in scan.stalled_lanes                          # B 침묵 = 멈춤
    assert lanes["lane-c"]["stalled"] is False                     # C 외부 대기 = 시한 보존
    assert lanes["lane-c"]["wait_deadline"] == 8
    assert "lane-d" in scan.stalled_lanes                          # D heartbeat 재무장 0
    assert lanes["lane-d"]["rearm"] == 0
    assert lanes["lane-d"]["progress_age"] >= lanes["lane-d"]["heartbeat_age"]
    assert scan.stalled_lanes == ["lane-b", "lane-d"]
    state, records = node._state_records()
    assert state["revision"] == 7 and len(records) == 7            # revision 변화 참


def test_a_external_wait_needs_deadline(tmp_path):
    node = lifecycle.Lifecycle(str(tmp_path / "p2"), TEAM, **CLOCK)
    out = node.progress("card-c", "lane-c", "external_wait")
    assert out.result == REFUSED and out.written is False
    assert node.progress("card-c", "lane-c", "chatter").result == REFUSED
    assert node.scan().lanes == {} and node._state_records()[1] == []


def _race(root):
    """사례 11 given 순서: 접수 card-1 · 실행권 · 착수 · 효과 · 결과 · 근거 · revision 읽기."""
    node = lifecycle.Lifecycle(root, TEAM, **CLOCK)
    client = intake.Intake(root, TEAM, **CLOCK)
    ex = execution.Execution(root, TEAM, **CLOCK)
    dp = dispatch.Dispatch(root, TEAM, **CLOCK)
    assert client.submit("card-1", "body", work="card-1").result == OK
    gen = ex.claim("card-1", "h1").gen
    assert ex.start("card-1", "h1", gen).result == OK
    assert ex.effect("card-1", "h1", gen, "band:external-send").result == OK
    assert ex.result("card-1", "h1", gen).result == OK
    assert dp.complete("card-1").written is True
    return node, client, ex, dp


def test_b_case_11_close_race(tmp_path):
    root = str(tmp_path / "race")
    node, client, ex, dp = _race(root)
    read_rev = node._state_records()[0]["revision"]
    assert client.submit("goal-new", "body", work="goal-new").result == OK
    lines = len(node._state_records()[1])
    race = node.close("card-1", read_rev)                          # 읽어 둔 revision = 낡았다
    assert race.result == HOLD == _case("11-close-race.json")["expect"]["처리 결과"]
    assert (race.status, race.written) == ("RETRY", False)
    assert len(node._state_records()[1]) == lines                  # RETRY = 쓰기 0
    refused = node.close("card-1", node._state_records()[0]["revision"])
    assert (refused.status, refused.written) == ("REFUSED", False)
    assert refused.blockers == ["PENDING_NOT_ZERO:1"]              # goal-new 가 아직 안 끝났다
    gen = ex.claim("goal-new", "h1").gen
    ex.start("goal-new", "h1", gen)
    ex.effect("goal-new", "h1", gen, "band:external-send")
    ex.result("goal-new", "h1", gen)
    dp.complete("goal-new")
    closed = node.close("card-1", node._state_records()[0]["revision"])
    assert (closed.status, closed.result, closed.written) == ("CLOSED", OK, True)
    state, records = node._state_records()
    key = "goal:card-1"
    assert state["done"][key]["marker"] == "" and state["done"][key]["at"] == FT_NOW
    assert client.journal._work_closed(key, records, state) is True       # 마감 = 회수 조건 아님
    assert client.journal._segment_closed([records[-1]], records, state) is True   # 그 segment 회수 대상
    assert node.close("card-1", state["revision"]).status == "CLOSED"    # 멱등 = 쓰기 0
    assert len(node._state_records()[1]) == len(records)


def test_b_blocker_words_are_canonical(tmp_path):
    """원자료 blockers 낱말 = GRANTED/STARTED · UNCERTAIN · PENDING_NOT_ZERO."""
    root = str(tmp_path / "words")
    node, client = lifecycle.Lifecycle(root, TEAM, **CLOCK), intake.Intake(root, TEAM, **CLOCK)
    client.submit("w1", "body", work="w1")
    execution.Execution(root, TEAM, **CLOCK).claim("w1", "h1")
    out = node.close("g", node._state_records()[0]["revision"])
    assert out.blockers == ["PENDING_NOT_ZERO:1", "GRANTED:w1"]
    ex = execution.Execution(root, TEAM, **CLOCK)
    ex.start("w1", "h1", ex._state_records()[0]["generations"]["w1"])
    assert "STARTED:w1" in node.close("g", node._state_records()[0]["revision"]).blockers


class _HeartbeatAsProgress(lifecycle.Lifecycle):
    def _kind_of(self, kind):
        return "progress" if kind == "heartbeat" else kind


class _NoRevisionCheck(lifecycle.Lifecycle):
    def _revision_stale(self, state, revision):
        return False


def test_m1_heartbeat_counted_as_progress_breaks_case_10(tmp_path):
    node = _HeartbeatAsProgress(str(tmp_path / "m1"), TEAM, **CLOCK)
    _seed_lanes(node)
    assert node.scan(stall_after=3).stalled_lanes == ["lane-b"]    # 계약은 ["lane-b", "lane-d"]
    assert node.scan(stall_after=3).stalled_lanes != ["lane-b", "lane-d"]


def test_m2_close_without_revision_check_breaks_case_11(tmp_path):
    root = str(tmp_path / "m2")
    node, client, _ex, _dp = _race(root)
    node = _NoRevisionCheck(root, TEAM, **CLOCK)
    read_rev = node._state_records()[0]["revision"]
    client.submit("goal-new", "body", work="goal-new")
    assert node.close("card-1", read_rev).status != "RETRY"        # 계약은 RETRY
