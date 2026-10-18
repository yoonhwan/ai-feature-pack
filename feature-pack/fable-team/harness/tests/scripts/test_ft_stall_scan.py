"""R320b — ft-stall-scan.sh 감지 4종(a 대기 카드 있는데 IDLE · b 선언 뒤 IDLE · c 정책 정지 · d 답 기다리며 3분+)과 처리.

가짜 세계(_stall_world) — 실 ring·kill 0. 처리 = mbox 스텁 로그·tmux 스텁 로그로 센다.
"""
from pathlib import Path

import pytest

from _stall_world import World, counts


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def rings(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"ring|{to}")]


def test_a_waiting_cards_idle_master_gets_urgent(w: World) -> None:
    w.cards("t1", ["c1", "c2"])
    w.state("t1-master#1", "IDLE", 5)
    r = w.scan()
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["a"] == "1"
    assert len(sends(w, "t1-master#1")) == 1 and "--urgent" in sends(w, "t1-master#1")[0] and "2장" in sends(w, "t1-master#1")[0]


def test_a_working_master_is_zero(w: World) -> None:
    w.cards("t1", ["c1", "c2"])
    w.state("t1-master#1", "WORKING", 0.1)
    assert counts(w.scan().stdout)["a"] == "0" and not w.mbox_log()


def test_a_unmet_prerequisite_or_lint_fail_does_not_count(w: World) -> None:
    w.cards("t1", ["blocked"], "- 선행: design/t1/indices/진행/other.md 가 끝난 뒤\n")
    (w.root / ".worktrees/wt-t1/design/t1/indices/진행").mkdir(parents=True)
    _ = (w.root / ".worktrees/wt-t1/design/t1/indices/진행/other.md").write_text("x")
    w.cards("t1", ["bad"], "LINTBAD\n")
    w.state("t1-master#1", "IDLE", 9)
    assert counts(w.scan().stdout)["a"] == "0"


def test_b_declaration_then_idle_rings_once(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "확인했습니다. 지금 착수하겠습니다")
    r = w.scan()
    assert counts(r.stdout)["b"] == "1"
    assert len(rings(w, "t1-nano#0")) == 1 and len(sends(w, "t1-nano#0")) == 1
    assert any("Escape" in x for x in w.tmux_log())


def test_b_rest_token_excluded(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "[완료·휴식] 끝났고 다음 일을 진행하겠습니다")
    assert counts(w.scan().stdout)["b"] == "0"


def test_b_working_seat_never_rung(w: World) -> None:
    w.state("t1-nano#0", "WORKING", 0.2)
    w.jsonl("t1-nano#0", "지금 착수하겠습니다")
    r = w.scan()
    assert counts(r.stdout)["b"] == "0" and not rings(w, "t1-nano#0") and not w.tmux_log()


def test_b_text_with_tool_call_is_not_stall(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "진행하겠습니다", tool=True)
    assert counts(w.scan().stdout)["b"] == "0"


def test_c_resource_freeze_alerts_planner(w: World) -> None:
    w.freeze()
    r = w.scan()
    assert counts(r.stdout)["c"] == "1"
    s = sends(w, "planner#1")
    assert len(s) == 1 and "[긴급]" in s[0]


def test_d_pending_mail_idle_receiver_rings_first_seq(w: World) -> None:
    w.mail("t1-nano#0", 7, 4.5)
    w.mail("t1-nano#0", 9, 4.0)
    w.state("t1-nano#0", "IDLE", 4)
    r = w.scan()
    assert counts(r.stdout)["d"] == "1"
    assert rings(w, "t1-nano#0") == ["ring|t1-nano#0|7"] and not sends(w, "t1-nano#0")


def test_d_young_mail_is_not_stall(w: World) -> None:
    w.mail("t1-nano#0", 7, 1.0)
    w.state("t1-nano#0", "IDLE", 4)
    assert counts(w.scan().stdout)["d"] == "0"


def test_dry_run_acts_and_logs_nothing(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    r = w.scan("--dry-run")
    assert counts(r.stdout)["a"] == "1" and not w.mbox_log() and not w.scan_log()


def test_same_key_not_reprocessed_within_ten_minutes(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"  # 이 시험은 10분 재처리 억제만 본다(페널티는 test_ft_penalty)
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    _ = w.scan()
    w.advance(120)
    _ = w.scan()
    assert len(sends(w, "t1-master#1")) == 1
    w.advance(600)
    _ = w.scan()
    assert len(sends(w, "t1-master#1")) == 2


def test_attached_seat_listed_but_no_action(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    w.attach("t1-master#1")
    r = w.scan()
    assert counts(r.stdout)["a"] == "1" and "attached" in r.stdout and not w.mbox_log()


def test_closed_seat_excluded(w: World) -> None:
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    import json
    p = w.root / ".fable-team/seats-t1.json"
    d = json.loads(p.read_text())
    d["t1-nano#0"]["role"] = "stop-ready"
    _ = p.write_text(json.dumps(d))
    assert counts(w.scan().stdout)["b"] == "0"


def test_summary_line_is_last_log_line_and_first_stdout_line(w: World) -> None:
    w.cards("t1", ["c1"])
    w.state("t1-master#1", "IDLE", 5)
    r = w.scan()
    assert r.stdout.startswith("stall=1 a=1 b=0 c=0 d=0 seats=")
    assert w.scan_log()[-1].startswith("stall=1 a=1")


def test_unknown_is_counted_separately_with_no_action(w: World) -> None:
    w.state("t1-master#1", "WORKING", 0.1)
    w.state("planner#1", "WORKING", 0.1)
    _ = (w.stub / "turn/t1-nano#0").write_text("UNKNOWN - - - pane\n")
    w.mail("t1-nano#0", 3, 9)
    r = w.scan()
    assert counts(r.stdout)["u"] == "1" and counts(r.stdout)["d"] == "0" and not w.mbox_log()


def _team_env(w: World, label: str, team_cap: int, group_cap: int | None = None, parent: str | None = None) -> None:
    env = w.root / f".fable-team/bin-{label}"
    env.mkdir(parents=True, exist_ok=True)
    lines = [f"export FT_NANO_PREFIX=byz-{label}-nano-", f"export FT_SEATS_JSON={w.root}/.fable-team/seats-{label}.json", f"export FT_TEAM_SEAT_CAP={team_cap}"]
    if group_cap:
        lines.append(f"export FT_GROUP_SEAT_CAP={group_cap}")
    _ = (env / f"{label}-env.sh").write_text("\n".join(lines) + "\n")
    if parent:
        import json
        p = w.root / f".fable-team/seats-{label}.json"
        d = json.loads(p.read_text())
        d["_parent"] = parent
        _ = p.write_text(json.dumps(d))


def test_a_zero_when_team_cap_full_or_policy_stop(w: World) -> None:
    w.team("t3", "byz-t3-master-claude#1", ["byz-t3-nano-c#0"])
    w.cards("t3", ["c1"])
    w.state("byz-t3-master-claude#1", "IDLE", 6)
    _team_env(w, "t3", 2)
    assert counts(w.scan("--dry-run").stdout)["a"] == "0"  # 상한 도달 = 정상 대기
    _team_env(w, "t3", 5)
    assert counts(w.scan("--dry-run").stdout)["a"] == "1"
    w.freeze()
    r = w.scan("--dry-run")
    assert counts(r.stdout)["a"] == "0" and counts(r.stdout)["c"] == "1"


def test_a_zero_when_group_cap_full_and_no_penalty_next_tick(w: World) -> None:  # DA⑥ 반례 ①
    w.team("t3", "byz-t3-master-claude#1", ["byz-t3-nano-c#0"])
    w.cards("t3", ["c1"])
    w.state("byz-t3-master-claude#1", "IDLE", 6)
    _team_env(w, "t3", 9, group_cap=2, parent="p")  # 팀 상한은 여유 · 그룹 합 2/2
    assert counts(w.scan().stdout)["a"] == "0"
    w.advance(120)
    assert counts(w.scan().stdout)["a"] == "0" and not (w.root / ".fable-team/state/PENALTY_STOP").exists()
    _team_env(w, "t3", 9, group_cap=3, parent="p")
    assert counts(w.scan("--dry-run").stdout)["a"] == "1"


def test_cap_checker_error_is_not_a_silent_pass(w: World) -> None:
    w.team("t3", "byz-t3-master-claude#1", ["byz-t3-nano-c#0"])
    w.cards("t3", ["c1"])
    w.state("byz-t3-master-claude#1", "IDLE", 6)
    _team_env(w, "t3", 9, group_cap=3)  # _parent 없음 → ft_seat_cap ERROR
    r = w.scan("--dry-run")
    assert counts(r.stdout)["a"] == "0" and int(counts(r.stdout)["u"]) >= 1 and "a? byz-t3-master-claude#1 상한 판정 불가" in r.stdout


def test_a_recovers_for_resumed_team_during_partial_penalty(w: World) -> None:  # DA⑥ 반례 ②
    w.team("t2", "t2-master#1", ["t2-nano#0"])
    _ = w.penalty("on", "--reason", "시험")
    w.state("t1-master#1", "IDLE", -2)
    w.state("t2-master#1", "IDLE", -2)
    _ = w.scan()
    assert w.penalty("resume", "t1").returncode == 0
    w.cards("t1", ["c1"])
    w.cards("t2", ["c2"])
    w.advance(600)
    r = w.scan("--dry-run")
    assert counts(r.stdout)["a"] == "1" and "t1-master#1" in r.stdout and "t2-master#1" not in r.stdout.split("\n", 1)[1]


def test_b_plus_d_rings_once_with_oldest_seq_and_no_send(w: World) -> None:  # DA⑥ 반례 ③
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    w.mail("t1-nano#0", 7, 5)
    w.mail("t1-nano#0", 9, 4)
    r = w.scan()
    assert counts(r.stdout)["b"] == "1" and counts(r.stdout)["d"] == "1"
    assert rings(w, "t1-nano#0") == ["ring|t1-nano#0|7"] and not sends(w, "t1-nano#0")


def test_one_action_per_seat_across_kinds(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    w.mail("t1-nano#0", 5, 5)
    r = w.scan()
    assert counts(r.stdout)["b"] == "1" and counts(r.stdout)["d"] == "1"
    assert rings(w, "t1-nano#0") == ["ring|t1-nano#0|5"]


def test_log_guard_blocks_repeat_even_without_state_file(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.mail("t1-nano#0", 5, 5)
    w.state("t1-nano#0", "IDLE", 4)
    _ = w.scan()
    (w.root / ".fable-team/state/stall-scan.json").unlink()
    w.advance(120)
    _ = w.scan()
    assert len(rings(w, "t1-nano#0")) == 1


def test_unchanged_jsonl_is_not_reread_next_tick(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "정상 보고였습니다")
    _ = w.scan()
    first = [c for c in w.calls("turn.calls") if c == "t1-nano#0"]
    j1 = w.calls("jsonl.calls").count("t1-nano#0")
    w.advance(120)
    _ = w.scan()
    assert [c for c in w.calls("turn.calls") if c == "t1-nano#0"] == first  # mtime 불변 = 재판정 0
    assert w.calls("jsonl.calls").count("t1-nano#0") == j1  # 경로 재해석 0(후보 아님)


def test_candidate_is_reconfirmed_with_fresh_path(w: World) -> None:
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "착수하겠습니다")
    before = w.calls("jsonl.calls").count("t1-nano#0")
    _ = w.scan()
    assert w.calls("jsonl.calls").count("t1-nano#0") > before + 0 and w.calls("jsonl.calls").count("t1-nano#0") >= 2


def test_overlapping_run_is_skipped(w: World) -> None:
    import fcntl
    (w.root / ".fable-team/state").mkdir(parents=True, exist_ok=True)
    with open(w.root / ".fable-team/state/stall-scan.lock", "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        r = w.scan()
    assert "건너뜀" in r.stdout and not w.mbox_log()


def _hold(w: World, rc: int) -> None:
    _ = (w.root / ".fable-team/state/SPAWN_HOLD").write_text('{"verdict": 2166}')
    sh = w.stub / "hold.sh"
    _ = sh.write_text(f'#!/bin/sh\n[ "$1 $2 $3" = "status --check 2166" ] || exit 9\nexit {rc}\n')
    w.env["FT_SPAWN_HOLD_SH"] = str(sh)


def test_c_valid_spawn_hold_counts_via_r320_status(w: World) -> None:
    _hold(w, 0)
    r = w.scan()
    assert counts(r.stdout)["c"] == "1" and "hold=2166" in r.stdout


def test_c_expired_hold_is_not_a_stop(w: World) -> None:
    _hold(w, 3)
    assert counts(w.scan().stdout)["c"] == "0"


def test_c_hold_checker_failure_is_loud(w: World) -> None:
    _hold(w, 4)
    r = w.scan()
    assert counts(r.stdout)["c"] == "1" and "판정 실패" in r.stdout
