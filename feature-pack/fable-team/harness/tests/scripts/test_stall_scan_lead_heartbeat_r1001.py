"""r1001 — 정지 경보의 «팀장 멈춤» 판정을 팀 단위 심박 디바운스로 바꾼다.

팀장 심박 = 그 팀장이 보낸 mbox 쪽지 중 본문 머리 `[정리]` 인 마지막 줄의 ts.
심박 나이 ≤ 15분 = 그 팀장 b·d 경보 0 · 넘거나 없으면 그 팀 1통(`[멈춤]`). 팀장 아닌 좌석은 base 그대로.
R1001_BIN = 시험할 bin 폴더(기본 kit · 셸 짝 tests/test_stall_scan_lead_heartbeat_r1001.sh 가 변이 사본을 넣어 ⓕ 를 본다).
"""
import json
import os
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1001_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh"), *args], env=w.env, capture_output=True, text=True, timeout=60)


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def body_of(line: str) -> str:
    return line.split("|")[4]


def quiet_others(w: World) -> None:
    """다른 좌석을 WORKING 으로 둔다 — u(판정 불가) 칸을 이 카드 판정만 세도록."""
    w.state("planner#1", "WORKING", 0.1)
    w.state("t1-nano#0", "WORKING", 0.1)


def lead_b_candidate(w: World) -> None:
    """팀장 b 후보 — IDLE 5분 + 마지막 글이 미래형 선언(도구 0)."""
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


def add_master_row(w: World, label: str, seat: str) -> None:
    """같은 명부에 «현역 role=master» 행을 하나 더 — 승계 직후 옛·새 둘 다 현역인 상태."""
    p = w.root / f".fable-team/seats-{label}.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d[seat] = {"role": "master"}
    _ = p.write_text(json.dumps(d), encoding="utf-8")
    w.live.append(seat)
    w._tmux()


def set_replaces(w: World, label: str, master: str, olds: list[str]) -> None:
    p = w.root / f".fable-team/seats-{label}.json"
    d = json.loads(p.read_text(encoding="utf-8"))
    d[master] = {**d[master], "_replaces": olds}
    _ = p.write_text(json.dumps(d), encoding="utf-8")


# ── C1 — 심박 나이 ≤ 15분 인 팀장 = b·d 경보 0 ───────────────────────────────
def test_c1a_heartbeat_within_10min_zero(w: World) -> None:  # ⓐ
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 10)
    r = scan(w)
    assert r.returncode == 0, r.stderr
    c = counts(r.stdout)
    assert c["b"] == "0" and c["d"] == "0" and c["f"] == "0", r.stdout
    assert not w.mbox_log() and not w.tmux_log()


def test_c1b_heartbeat_10_to_15min_zero(w: World) -> None:  # ⓑ (여유 5분)
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 14.5)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and not w.mbox_log()


# ── C2 — 15분 넘음 또는 없음 = 그 팀 1통 · 같은 서명 10분 안 재알림 0 ─────────
def test_c2c_heartbeat_over_15min_one_stall_notice(w: World) -> None:  # ⓒ
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 16)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and counts(r.stdout)["b"] == "0", r.stdout
    s = sends(w, "t1-master#1")
    assert len(s) == 1, w.mbox_log()
    assert body_of(s[0]).startswith("[멈춤] t1-master#1 팀장 심박 16분"), s[0]
    assert "--urgent" not in s[0]


def test_c2d_no_heartbeat_at_all_one_stall_notice(w: World) -> None:  # ⓓ 심박을 한 번도 안 보냄
    lead_b_candidate(w)
    w.mail("planner#1", 3, 20, frm="t1-master#1", body="발주 확인")  # 쪽지는 있지만 `[정리]` 가 아니다
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    s = sends(w, "t1-master#1")
    assert len(s) == 1 and "심박 없음" in body_of(s[0]), w.mbox_log()


def test_c2e_same_signature_within_ten_minutes_is_one_notice(w: World) -> None:  # ⓔ 연속 2회
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 16)
    _ = scan(w)
    w.advance(120)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1"  # 감지는 계속되지만 재알림은 10분 뒤
    assert len(sends(w, "t1-master#1")) == 1


def test_c2e2_lead_with_both_kinds_gets_one_notice_per_team(w: World) -> None:  # ⓔ2 «팀당 1통»
    lead_b_candidate(w)
    w.mail("t1-master#1", 7, 4.5, frm="planner#1")  # 미읽음 쪽지(d 후보)도 함께
    w.heartbeat("t1-master#1", 20)
    r = scan(w)
    c = counts(r.stdout)
    assert c["f"] == "1" and c["b"] == "0" and c["d"] == "0", r.stdout
    assert len(sends(w, "t1-master#1")) == 1
    assert len([x for x in w.mbox_log() if x.startswith("ring|t1-master#1")]) == 1


# ── C3 — 팀장 아닌 좌석의 b·d 처리는 base 와 같다 ────────────────────────────
def test_c3_nano_b_and_d_unchanged_with_fresh_lead_heartbeat(w: World) -> None:  # ⓕ
    w.heartbeat("t1-master#1", 1)  # 팀장 심박이 신선해도 나노 판정은 그대로
    w.state("t1-nano#0", "IDLE", 4)
    w.jsonl("t1-nano#0", "지금 착수하겠습니다")
    w.mail("t1-nano#0", 21, 4.5)
    r = scan(w)
    c = counts(r.stdout)
    assert c["b"] == "1" and c["d"] == "1" and c["f"] == "0", r.stdout
    assert not sends(w, "t1-nano#0")  # b+d 동시 = d 한 번(기존 규칙 그대로)
    assert len([x for x in w.mbox_log() if x.startswith("ring|t1-nano#0|21")]) == 1


# ── C4 — 환경 3종 = 판정 불가(u) · 처리 0 · 조용한 «경보 0» 아님 ──────────────
def test_c4_g1_no_mailbox_is_undecidable_not_silent_zero(w: World) -> None:  # ⓖ1
    quiet_others(w)
    lead_b_candidate(w)
    r = scan(w)
    c = counts(r.stdout)
    assert c["u"] == "1" and c["f"] == "0" and c["b"] == "0", r.stdout
    assert "팀장 심박 판정 불가" in r.stdout
    assert not w.mbox_log()


def test_c4_g2_broken_line_makes_it_undecidable(w: World) -> None:  # ⓚ 깨진 줄 1 = 판정 불가(신선 심박이 같이 있어도)
    quiet_others(w)
    lead_b_candidate(w)
    w.raw_mail("{ 깨진 줄")
    w.heartbeat("t1-master#1", 5)
    r = scan(w)
    c = counts(r.stdout)
    assert c["u"] == "1" and c["f"] == "0" and c["b"] == "0", r.stdout
    assert "팀장 심박 판정 불가" in r.stdout
    assert not w.mbox_log()  # 조용한 경보 0 도, 경보 1통도 아니다


def test_c4_g3_budget_over_7s_is_undecidable(w: World) -> None:  # ⓖ3
    w.env["FT_STALL_HEARTBEAT_BUDGET"] = "0.000001"
    quiet_others(w)
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5)
    r = scan(w)
    c = counts(r.stdout)
    assert c["u"] == "1" and c["f"] == "0", r.stdout
    assert "팀장 심박 판정 불가" in r.stdout and not w.mbox_log()


# ── C5 — 심박 발신자는 현역 팀장 이름만(승계 직후 옛 이름도 인정) ───────────────
def test_c5_h_replaces_only_old_name_is_ignored(w: World) -> None:  # ⓛ `_replaces` 에만 있는 옛 이름 = 현역 아님
    lead_b_candidate(w)
    set_replaces(w, "t1", "t1-master#1", ["t1-master#0"])
    w.heartbeat("t1-master#0", 5)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert len(sends(w, "t1-master#1")) == 1


def test_c5_h2_unknown_sender_heartbeat_ignored(w: World) -> None:  # ⓗ 옛 이름이 계보에 없으면 무시
    lead_b_candidate(w)
    w.heartbeat("t1-master#0", 5)
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and len(sends(w, "t1-master#1")) == 1


def test_c5_h3_heartbeat_token_must_be_body_head(w: World) -> None:  # `[정리]` 가 머리가 아니면 심박 아님
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 3, body="보고 — [정리] 한 일 3줄")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1"


def test_c5_h4_future_ts_is_never_fresh(w: World) -> None:  # 시계 어긋난 미래 ts = 신선으로 읽지 않는다
    quiet_others(w)
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", -120)  # 2시간 «미래»
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and counts(r.stdout)["u"] == "1", r.stdout
    assert not w.mbox_log()


# ── attached·rest·stop-ready 팀장은 처리 0(base 게이트 그대로) ──────────────────
def test_attached_lead_listed_but_no_action(w: World) -> None:
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 20)
    w.attach("t1-master#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1" and "attached" in r.stdout and not w.mbox_log()


def test_rested_lead_is_not_a_stall(w: World) -> None:
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "[완료·휴식] 끝났고 다음 일을 진행하겠습니다")
    w.heartbeat("t1-master#1", 30)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and not w.mbox_log()


def test_working_lead_is_not_a_stall(w: World) -> None:
    w.state("t1-master#1", "WORKING", 0.2)
    w.jsonl("t1-master#1", "지금 착수하겠습니다")
    w.heartbeat("t1-master#1", 30)
    assert counts(scan(w).stdout)["f"] == "0"


# ── dry-run 은 아무것도 보내지 않는다 ─────────────────────────────────────────
def test_dry_run_lead_stall_sends_nothing(w: World) -> None:
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 20)
    r = scan(w, "--dry-run")
    assert counts(r.stdout)["f"] == "1" and not w.mbox_log() and not w.scan_log()


# ── r2 반송(DA 1/2 HOLD) — ⓘ env 임계 · ⓙ 수신자 · ⓜ 둘 다 현역 · ⓝ 두 팀장 1통 ──────────
def test_i_env_threshold_is_read(w: World) -> None:  # ⓘ FT_LEAD_HEARTBEAT_MIN=20 이면 16분은 신선
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 16)
    w.env["FT_LEAD_HEARTBEAT_MIN"] = "20"
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and not w.mbox_log(), r.stdout


def test_j_heartbeat_to_nano_is_not_a_heartbeat(w: World) -> None:  # ⓙ 받는이 = master/planner 만
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, to="t1-nano#0")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert "심박 없음" in body_of(sends(w, "t1-master#1")[0])


def test_m_old_name_live_master_counts(w: World) -> None:  # ⓜ 옛·새 둘 다 현역이면 옛 이름 심박도 인정
    lead_b_candidate(w)
    add_master_row(w, "t1", "t1-master#0")
    w.heartbeat("t1-master#0", 5)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and not w.mbox_log(), r.stdout


def test_n_two_live_masters_one_notice_per_team(w: World) -> None:  # ⓝ 승계 직후 두 팀장 · 팀당 1통
    add_master_row(w, "t1", "t1-master#0")
    lead_b_candidate(w)
    w.state("t1-master#0", "IDLE", 6)
    w.jsonl("t1-master#0", "지금 착수하겠습니다")
    w.heartbeat("t1-master#1", 20)
    r = scan(w)
    c = counts(r.stdout)
    assert c["f"] == "1" and c["b"] == "0" and c["d"] == "0", r.stdout  # b 중복 0
    assert len([x for x in w.mbox_log() if x.startswith("send|t1-master#")]) == 1, w.mbox_log()


def test_n2_two_live_masters_fresh_heartbeat_is_zero(w: World) -> None:  # ⓝ 신선 = 경보 0
    add_master_row(w, "t1", "t1-master#0")
    lead_b_candidate(w)
    w.state("t1-master#0", "IDLE", 6)
    w.jsonl("t1-master#0", "지금 착수하겠습니다")
    w.heartbeat("t1-master#0", 5)
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and counts(r.stdout)["b"] == "0", r.stdout
    assert not w.mbox_log()


# ── r3 반송(DA 2/2 HOLD ①②) — ⓞ 억제 키 = 팀 · ⓟ 수신자 = 모든 현역 master ────────
def test_o_suppression_key_is_team_not_seat(w: World) -> None:  # ⓞ 대상 좌석이 바뀌어도 같은 팀 10분 안 0통
    w.env["FT_STALL_PENALTY_AUTO"] = "0"
    add_master_row(w, "t1", "t1-master#0")
    lead_b_candidate(w)
    w.state("t1-master#0", "IDLE", 6)
    w.jsonl("t1-master#0", "지금 착수하겠습니다")
    w.heartbeat("t1-master#1", 20)
    _ = scan(w)
    assert len([x for x in w.mbox_log() if x.startswith("send|t1-master#")]) == 1, w.mbox_log()
    w.advance(120)
    w.state("t1-master#0", "WORKING", 0.1)  # 경보 대상이 #0 → #1 로 바뀐다
    r = scan(w)
    assert counts(r.stdout)["f"] == "1"  # 감지는 계속
    assert len([x for x in w.mbox_log() if x.startswith("send|t1-master#")]) == 1, w.mbox_log()  # 재알림 0


def test_p_other_team_live_master_is_a_recipient(w: World) -> None:  # ⓟ 다른 팀 현역 master 수신 [정리] = 심박
    lead_b_candidate(w)
    w.team("t2", "t2-master#1", [])
    w.state("t2-master#1", "WORKING", 0.1)
    w.heartbeat("t1-master#1", 5, to="t2-master#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "0" and not w.mbox_log(), r.stdout
