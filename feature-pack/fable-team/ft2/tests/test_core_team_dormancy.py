"""ft2 코어 팀 휴면 순서 시험 (r1726 · 카드 r1726-ft20-team-dormancy-sequence).

계약 = 시작 조건 10칸 판독 → 5단계(나노 정리 → 재검사 → 팀 기록 확정 → arch·DA → 팀장) 영수 →
r1714 표식 1줄. 조건 하나라도 어긋나면 휴면 0 + 이유 1줄, 단계 1 뒤 새 접수면 2단계에서 중단(팀장 그대로),
crash 뒤 재실행은 영수 있는 단계를 건너뛴다, 휴면 뒤 접수는 영속 큐에 남고 자동 재개설은 없다.

| 사례 | given 1줄 | 호출 1개 |
|---|---|---|
| ① 조건 모두 0 | 빈 팀 runtime | `dormant(board)` = 5단계 영수 + 표식 |
| ② 미처리 쪽지 1 | `mail=1` | 휴면 0 + 이유 1줄(쓰기 0) |
| ③ 좌석 cron 1 | `cron=1` | 휴면 0 + 이유 |
| ④ 미커밋 1 | `dirty=["a.py"]` / `.serena` 잡음만 | 휴면 0 / 통과 |
| ⑤ 단계 1 뒤 새 접수 | 재검사가 accept 1줄을 본다 | 2단계 중단 · 표식 0 |
| ⑥ 단계 3 뒤 crash | on_step 3회째 예외 | 재실행이 4단계부터 · 3단계 두 번 0 |
| ⑦ 휴면 뒤 접수 | 표식 → 접수 q-1 | 큐에 남음 · claim 거부 · 자동 재개설 0 |
| ⑧ h 장 수 | ① 의 반환 | `hil=1` |

시험 입력 = 격리 tmp 팀 runtime 루트 · FT_NOW 고정 시계 · sleep 0 · 사례 70초 안.
변이 M1 재검사 삭제 → ⑤ FAIL · M2 영수 건너뛰기 삭제 → ⑥ 에서 3단계 두 번 FAIL · M3 cron 검사 삭제 → ③ FAIL.
재진입 표지 = 없음(자기 파일을 다시 부르는 시험 0).

끝에 «r1498 이관표 받는 행 8개»(1·2·3·5·7·9·10·11) 시험이 따로 있다 — 행마다 표의 «멈춤/자동 닫힘» 사건을
입력 1개로 대응한다(행 2 = 좌석 cron · 행 3 = 고아 주기 루프 · 행 7·9 = 단계 1 영수 판정 불가 · 행 10 = .serena 잡음).
"""
import importlib.util
import os

import pytest

FT_NOW = "2026-11-10T00:00:00"
HERE = os.path.dirname(os.path.abspath(__file__))
FT2 = os.path.dirname(HERE)
CORE = os.path.join(FT2, "core")
TEAM = "harness"
OK, HOLD, REFUSED, BUSY = "접수 성공", "완료 유보", "접수 거부", "BUSY"
CLOCK = dict(clock=lambda: FT_NOW)


def _load(name):
    spec = importlib.util.spec_from_file_location("ft2_core_" + name, os.path.join(CORE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record, intake, execution, lifecycle = (_load(name) for name in
                                       ("record", "intake", "execution", "lifecycle"))


def _board(**kw):
    """journal 밖 7칸 + 단계 입력 — 기본 = «전부 0»."""
    board = {"mail": 0, "ownership": 0, "cards": 0, "lands": 0, "hil": 0, "cron": 0, "dirty": [],
             "team_record": {"revision": 0, "generation": "g1", "last_step": "team-lead",
                             "resume": "runtime/"},
             "arch_da": "arch APPROVE · DA APPROVE"}
    board.update(kw)
    return board


def _lines(node):
    return len(node._state_records()[1])


def _marker(node):
    return "goal:dormant:" + TEAM in (node._state_records()[0].get("done") or {})


def _pending(node):
    state, records = node._state_records()
    return sorted(work for work in record.remaining(state, records))


def _close_keys(node):
    return [rec["work"] for rec in node._state_records()[1] if rec["kind"] == "close"]


def test_1_all_clear_runs_five_steps_in_order(tmp_path):
    """① 조건 모두 0 → 5단계 순서대로 영수 5 + 표식 1줄. 단계 영수 = close 줄(seq 증가)."""
    node = lifecycle.Lifecycle(str(tmp_path / "c1"), TEAM, **CLOCK)
    out = node.dormant(_board())
    assert (out.result, out.status, out.written) == (OK, "DORMANT", True)
    assert out.steps == lifecycle.DORMANCY_STEPS                  # 순서 고정 · 5단계
    assert out.skipped == ()                                      # 건너뛴 단계 0 (전부 이번 호출)
    state, records = node._state_records()
    keys = _close_keys(node)
    assert keys == ["goal:dormant-step:%s:%s" % (TEAM, step)
                    for step in lifecycle.DORMANCY_STEPS[:-1]] + ["goal:dormant:" + TEAM]
    assert [rec["seq"] for rec in records] == [1, 2, 3, 4, 5]        # 영수 4 + 표식 1
    assert state["done"]["goal:dormant:" + TEAM]["at"] == FT_NOW
    assert state["revision"] == 5


def test_2_unread_mail_blocks_dormancy(tmp_path):
    """② 미처리 쪽지 1 → 휴면 0 + 이유 1줄 · 쓰기 0 · 표식 0."""
    node = lifecycle.Lifecycle(str(tmp_path / "c2"), TEAM, **CLOCK)
    lines = _lines(node)
    out = node.dormant(_board(mail=1))
    assert (out.result, out.status, out.written) == (HOLD, "NOT_DORMANT", False)
    assert out.blockers == ("mail:1",)
    assert out.reason and "\n" not in out.reason                 # 이유 1줄
    assert _lines(node) == lines                                 # 휴면 0 = 쓰기 0
    assert _marker(node) is False


def test_3_seat_cron_blocks_dormancy(tmp_path):
    """③ 좌석 cron 1 → 휴면 0 + 이유(M3 cron 검사 삭제 = FAIL)."""
    node = lifecycle.Lifecycle(str(tmp_path / "c3"), TEAM, **CLOCK)
    out = node.dormant(_board(cron=1))
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("cron:1",))
    assert _marker(node) is False


def test_4_dirty_blocks_but_serena_noise_passes(tmp_path):
    """④ 미커밋 1 → 휴면 0 · `.serena` 잡음만이면 통과(A2 · closeout-policy)."""
    blocked = lifecycle.Lifecycle(str(tmp_path / "c4a"), TEAM, **CLOCK)
    out = blocked.dormant(_board(dirty=["a.py"]))
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("dirty:1",))
    assert _marker(blocked) is False
    passed = lifecycle.Lifecycle(str(tmp_path / "c4b"), TEAM, **CLOCK)
    noise = passed.dormant(_board(dirty=[".serena/project.yml", ".serena/cache/x.pkl"]))
    assert (noise.status, noise.written) == ("DORMANT", True)


def test_5_new_intake_after_step_one_aborts_at_rescan(tmp_path):
    """⑤ 단계 1 뒤 새 접수 → 2단계 중단 · 표식 0(팀장 그대로) · 영수 1단계만."""
    node = _LateAccept(str(tmp_path / "c5"), TEAM, **CLOCK)
    out = node.dormant(_board())
    assert (out.result, out.status) == (HOLD, "ABORTED")
    assert out.steps == ("nano-cleanup",)                         # 2단계 영수 0
    assert out.written is True                                    # 1단계 영수는 남는다
    assert "재검사 중단" in out.reason
    assert _marker(node) is False                                 # 팀장 그대로
    assert _close_keys(node) == ["goal:dormant-step:%s:nano-cleanup" % TEAM]
    client = intake.Intake(str(tmp_path / "c5"), TEAM, **CLOCK)
    assert client.submit("q-late", "body", work="q-late").result == OK   # 표식 0 = 실행권 살아 있다
    assert execution.Execution(str(tmp_path / "c5"), TEAM, **CLOCK).claim("q-late", "h1").result == OK


def test_6_crash_after_step_three_resumes_at_four(tmp_path):
    """⑥ 단계 3 뒤 crash → 재실행이 4단계부터 · 3단계 두 번 0(M2 영수 건너뛰기 삭제 = FAIL)."""
    root, seen = str(tmp_path / "c6"), []

    def hook(step):
        if step == "after_dormancy_step":
            seen.append(step)
            if len(seen) == 3:
                raise RuntimeError("crash")

    with pytest.raises(RuntimeError):
        lifecycle.Lifecycle(root, TEAM, clock=lambda: FT_NOW, on_step=hook).dormant(_board())
    node = lifecycle.Lifecycle(root, TEAM, **CLOCK)
    out = node.dormant(_board())
    assert out.skipped == ("nano-cleanup", "rescan", "team-record")
    assert out.steps == ("arch-da", "team-lead")
    keys = _close_keys(node)
    assert keys.count("goal:dormant-step:%s:team-record" % TEAM) == 1     # 같은 단계 두 번 0
    assert keys == ["goal:dormant-step:%s:%s" % (TEAM, step)
                    for step in lifecycle.DORMANCY_STEPS[:-1]] + ["goal:dormant:" + TEAM]


def test_7_intake_after_dormancy_stays_queued(tmp_path):
    """⑦ 휴면 뒤 접수 → 큐에 남음 · claim 거부 · 재실행은 멱등(자동 재개설 0)."""
    root, node = str(tmp_path / "c7"), None
    node = lifecycle.Lifecycle(root, TEAM, **CLOCK)
    assert node.dormant(_board()).status == "DORMANT"
    client = intake.Intake(root, TEAM, **CLOCK)
    assert client.submit("q-1", "body", work="q-1").result == OK
    grant = execution.Execution(root, TEAM, **CLOCK).claim("q-1", "h1")
    assert (grant.result, "휴면 표식" in grant.reason) == (REFUSED, True)
    assert _pending(node) == ["q-1"]                              # 큐에 남는다(버림 0)
    lines = _lines(node)
    again = node.dormant(_board())
    assert (again.result, again.status, again.written) == (HOLD, "DORMANT", False)
    assert again.steps == () and again.skipped == lifecycle.DORMANCY_STEPS
    assert _lines(node) == lines                                   # 자동 재개설 0 = 쓰기 0
    assert _marker(node) is True


def test_8_kill_approval_is_one_card_per_dormancy(tmp_path):
    """⑧ h 장 수 = 휴면 1회 1장(`hil=1`) — 두 번째 휴면도 0(멱등)."""
    node = lifecycle.Lifecycle(str(tmp_path / "c8"), TEAM, **CLOCK)
    assert node.dormant(_board()).hil == 1
    assert node.dormant(_board()).hil == 0


def test_9_missing_board_slot_never_passes(tmp_path):
    """판독 칸 «미기재» = 판정 불가 = 휴면 0(하드 룰 20 — 통과로 쓰지 않는다)."""
    node = lifecycle.Lifecycle(str(tmp_path / "c9"), TEAM, **CLOCK)
    board = _board()
    board.pop("hil")
    out = node.dormant(board)
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("hil:미기재",))
    assert _marker(node) is False


class _LateAccept(lifecycle.Lifecycle):
    """⑤ 입력 — 재검사가 «단계 1 뒤 접수 q-late» 1줄을 본다(잠금 밖 가짜 journal 줄)."""

    def _rescan_records(self):
        records = list(super()._rescan_records())
        records.append({"seq": records[-1]["seq"] + 1, "kind": "accept", "work": "q-late"})
        return records


class _NoLateCheck(lifecycle.Lifecycle):
    """M1 — 재검사 삭제(단계 1 뒤 접수를 보지 않는다)."""

    def _late_records(self, snapshot):
        return []


class _NoStepSkip(lifecycle.Lifecycle):
    """M2 — 영수 건너뛰기 삭제(이미 영수한 단계도 다시 쓴다)."""

    def _receipted(self, done):
        return ()


class _NoCronCheck(lifecycle.Lifecycle):
    """M3 — cron 검사 삭제(좌석 주기 루프가 남아도 휴면)."""

    def _board_blockers(self, board):
        return [row for row in super()._board_blockers(board) if not row.startswith("cron:")]


def test_m1_without_rescan_breaks_case_5(tmp_path):
    node = _NoLateCheck(str(tmp_path / "m1"), TEAM, **CLOCK)
    assert node.dormant(_board()).status != "ABORTED"              # 계약은 ABORTED


def test_m2_without_step_skip_breaks_case_6(tmp_path):
    root = str(tmp_path / "m2")

    def hook(step):
        if step == "after_dormancy_step" and len([1]) == 1:
            raise RuntimeError("crash")

    with pytest.raises(RuntimeError):
        lifecycle.Lifecycle(root, TEAM, clock=lambda: FT_NOW, on_step=hook).dormant(_board())
    mutant = _NoStepSkip(root, TEAM, **CLOCK)
    assert mutant.dormant(_board()).status == "DORMANT"
    keys = _close_keys(mutant)
    assert keys.count("goal:dormant-step:%s:nano-cleanup" % TEAM) == 2   # 계약은 1


def test_m3_without_cron_check_breaks_case_3(tmp_path):
    node = _NoCronCheck(str(tmp_path / "m3"), TEAM, **CLOCK)
    assert node.dormant(_board(cron=1)).status != "NOT_DORMANT"    # 계약은 NOT_DORMANT


# --- r1498 이관표 받는 행 8개(1·2·3·5·7·9·10·11) — 행마다 «멈춤 또는 자동 닫힘» 사건 입력 1개 ---


def _step_body_of(node, step):
    key = "goal:dormant-step:%s:%s" % (TEAM, step)
    return next(rec["body"] for rec in node._state_records()[1] if rec.get("work") == key)


def test_r1498_row1_team_record_receipt_is_step_three(tmp_path):
    """행 1 CLOSEOUT 손작성 → 자동: 3단계 «팀 기록 확정» 영수(R·세대·마지막 단계·복구 위치)."""
    node = lifecycle.Lifecycle(str(tmp_path / "r1"), TEAM, **CLOCK)
    assert node.dormant(_board()).status == "DORMANT"
    body = _step_body_of(node, "team-record")
    assert body == "R=0 gen=g1 last=team-lead resume=runtime/"


def test_r1498_row2_seat_cron_blocks(tmp_path):
    """행 2 «Running scheduled task» 좌석 cron → 멈춤: 시작 조건 미충족 = 휴면 0 + 이유 1줄."""
    node = lifecycle.Lifecycle(str(tmp_path / "r2"), TEAM, **CLOCK)
    out = node.dormant(_board(cron=["ft-issues-daily"]))
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("cron:1(ft-issues-daily)",))
    assert "cron" in out.reason and "\n" not in out.reason


def test_r1498_row3_orphan_loop_blocks(tmp_path):
    """행 3 고아 주기 루프 ft-pm-watchd → 멈춤: 주기 루프 0 미충족 = 휴면 0."""
    node = lifecycle.Lifecycle(str(tmp_path / "r3"), TEAM, **CLOCK)
    out = node.dormant(_board(cron=["ft-pm-watchd"]))
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("cron:1(ft-pm-watchd)",))
    assert _marker(node) is False


def test_r1498_row5_one_kill_card_covers_steps_four_five(tmp_path):
    """행 5 kill h 6장 → 자동: 휴면 1회 h 1장 안에서 단계 4·5 영수(`hil=1`)."""
    node = lifecycle.Lifecycle(str(tmp_path / "r5"), TEAM, **CLOCK)
    out = node.dormant(_board())
    assert (out.hil, out.steps[-2:]) == (1, ("arch-da", "team-lead"))
    assert (node.dormant(_board()).hil, 0) == (0, 0)              # 두 번째 휴면 = h 0


def test_r1498_row7_rc_zero_alone_is_not_a_receipt(tmp_path):
    """행 7 kill 직후 확인 경합 → 자동: 단계 영수 = 실제 부재 확인 · rc0 만으로 영수 0."""
    node = lifecycle.Lifecycle(str(tmp_path / "r7"), TEAM, **CLOCK)
    out = node.dormant(_board(nano_cleanup={"rc": 0}))
    assert (out.status, out.steps, out.written) == ("ABORTED", (), False)
    assert "부재 확인 없음" in out.reason
    assert _close_keys(node) == []                               # 영수 0 · 표식 0


def test_r1498_row9_unreadable_evidence_stops_step_one(tmp_path):
    """행 9 나노 닫기 증거 판정 불가 → 멈춤: 그 나노 손 0 + 이유 1줄."""
    node = lifecycle.Lifecycle(str(tmp_path / "r9"), TEAM, **CLOCK)
    out = node.dormant(_board(nano_cleanup="cards_wt 사본 판독 불가"))
    assert (out.status, out.written) == ("ABORTED", False)
    assert out.reason.endswith("nano_cleanup 판정 불가 = 그 나노 손 0")
    assert _marker(node) is False


def test_r1498_row10_serena_noise_is_not_dirty(tmp_path):
    """행 10 spawn 이 고치는 .serena/project.yml → 자동: 미커밋으로 세지 않는다(PLAN :180)."""
    node = lifecycle.Lifecycle(str(tmp_path / "r10"), TEAM, **CLOCK)
    assert node.dormant(_board(dirty=[".serena/project.yml"])).status == "DORMANT"
    blocked = lifecycle.Lifecycle(str(tmp_path / "r10b"), TEAM, **CLOCK)
    assert blocked.dormant(_board(dirty=["a.py", ".serena/project.yml"])).blockers == ("dirty:1",)


def test_r1498_row11_landing_or_install_wait_blocks(tmp_path):
    """행 11 ft-merge-land 70초 잘림(착지·설치 대기) → 멈춤: 시작 조건 미충족 = 휴면 0 + 이유 1줄."""
    node = lifecycle.Lifecycle(str(tmp_path / "r11"), TEAM, **CLOCK)
    out = node.dormant(_board(lands=1))
    assert (out.status, out.blockers) == ("NOT_DORMANT", ("lands:1",))
    assert _marker(node) is False
