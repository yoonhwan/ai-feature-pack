"""r1143 — 팀장 심박 받는이에 현역 role=desk 를 더하고, 창 안 [정리] 0 문구를 «최근 15분 [정리] 0» 으로 바로잡는다.

planner 팀장의 보고처 = desk 라 [정리] 가 전부 desk 앞이다 — 받는이를 role=master 로만 세면 매 스캔 [멈춤] 오탐.
로그는 심박 창(15분) 안만 읽으므로 ts None 의 뜻은 «한 번도 안 보냄» 이 아니라 «창 안 0» 이다.
R1143_BIN = 시험할 bin 폴더(기본 kit · 변이 사본을 넣어 R1·R3 FAIL 을 본다). 자기 재호출 0.
"""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1143_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
sys.path.insert(0, str(BIN))
from ft_stall_detect import lead_alert  # noqa: E402


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def scan(w: World) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(BIN / "ft-stall-scan.sh")], env=w.env, capture_output=True, text=True, timeout=60)


def sends(w: World, to: str) -> list[str]:
    return [r for r in w.mbox_log() if r.startswith(f"send|{to}|")]


def desk_roster(w: World, rows: dict[str, dict[str, str]]) -> None:
    """desk 명부 — 현역 desk#2 (+ 닫힌 행)."""
    _ = (w.root / ".fable-team/seats-desk.json").write_text(json.dumps({"_label": "desk", **rows}), encoding="utf-8")


def log_mail(w: World, to: str, seq: int, minutes_ago: float, frm: str, body: str = "[정리] 한 일 3줄") -> None:
    """recv 뒤 옮겨진 레코드 자리 = mailbox.log.jsonl (r1020)."""
    ts = datetime.fromtimestamp(NOW - minutes_ago * 60).strftime("%Y-%m-%dT%H:%M:%S")
    with open(w.root / ".fable-team/comm/mailbox.log.jsonl", "a", encoding="utf-8") as f:
        _ = f.write(json.dumps({"seq": seq, "ts": ts, "to": to, "from": frm, "body": body}, ensure_ascii=False) + "\n")


def lead_b_candidate(w: World) -> None:
    w.state("t1-master#1", "IDLE", 5)
    w.jsonl("t1-master#1", "확인했습니다. 지금 착수하겠습니다")


# ── R1 — desk(현역 role=desk) 앞 [정리] 5분 전 = 경보 0 ───────────────────────
def test_r1_planner_lead_heartbeat_to_desk_is_fresh(w: World) -> None:  # ⓐ 판정 함수 값
    desk_roster(w, {"desk#2": {"role": "desk"}})
    w.heartbeat("planner#1", 5, to="desk#2")
    alert, age, undec = lead_alert(w.root, w.root / ".fable-team/comm", "planner#1", NOW)
    assert (alert, undec) == (False, False) and age is not None and round(age) == 5


def test_r1_scan_team_lead_to_desk_no_stall(w: World) -> None:  # ⓐ scan 출력
    desk_roster(w, {"desk#2": {"role": "desk"}})
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, to="desk#2")
    r = scan(w)
    assert r.returncode == 0, r.stderr
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert not sends(w, "t1-master#1")


# ── R2 — role=master 앞 [정리] 5분 전 = 경보 0(지금과 같음) ────────────────────
def test_r2_heartbeat_to_master_still_fresh(w: World) -> None:
    desk_roster(w, {"desk#2": {"role": "desk"}})
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, to="planner#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert not sends(w, "t1-master#1")


# ── R3 — 창 밖(20분 전) [정리] 1통뿐 = 경보 1 · 문구 «최근 15분 [정리] 0» ──────
def test_r3_out_of_window_heartbeat_wording(w: World) -> None:  # ⓑ
    desk_roster(w, {"desk#2": {"role": "desk"}})
    lead_b_candidate(w)
    w.mail("x#1", 1, 1)  # 큐는 있다(없으면 판정 불가)
    log_mail(w, "desk#2", 2, 20, frm="t1-master#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    s = sends(w, "t1-master#1")
    assert len(s) == 1, w.mbox_log()
    body = s[0].split("|")[4]
    assert "최근 15분 [정리] 0" in body and "한 번도" not in body, body


# ── R4 — 닫힌 desk(_replaced_by · 다른 역할 키) 앞 = 심박 아님 · 옛 번호 desk 는 셈 ──
def test_r4_closed_desk_other_key_is_not_heartbeat(w: World) -> None:
    desk_roster(w, {"desk#2": {"role": "desk"}, "olddesk#1": {"role": "desk", "_replaced_by": "desk#2"}})
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, to="olddesk#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "1", r.stdout
    assert len(sends(w, "t1-master#1")) == 1


def test_r4_old_number_same_role_key_counts(w: World) -> None:  # r1116 역할 키 — desk#1 = 현역 desk#2 와 같은 키
    desk_roster(w, {"desk#2": {"role": "desk"}})
    lead_b_candidate(w)
    w.heartbeat("t1-master#1", 5, to="desk#1")
    r = scan(w)
    assert counts(r.stdout)["f"] == "0", r.stdout
    assert not sends(w, "t1-master#1")
