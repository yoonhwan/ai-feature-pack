"""mbox 가드: 도구 발신자(`ft-` 접두 · `#N` 없음)는 RATE·FANOUT 면제, 좌석 발신자는 그대로 (R380 ②).

격리 FT_MBOX_DIR 픽스처만 쓴다 — 라이브 큐 쓰기 0.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

MBOX = Path(__file__).resolve().parents[2] / "tools" / "comm-canonical" / "mbox.py"
TOOL = "ft-head-lag"


def _send(box: Path, to: str, frm: str, body: str):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay")}
    return subprocess.run(
        [sys.executable, str(MBOX), "send", to, frm, body], env=env, capture_output=True, text=True, timeout=30
    )


def test_tool_sender_eight_distinct_recipients_all_queued(tmp_path: Path):
    rs = [_send(tmp_path, f"dst#{i}", TOOL, f"착지 알림 {i}") for i in range(8)]
    assert [r.returncode for r in rs] == [0] * 8, [r.stderr for r in rs]
    assert all(re.search(r"QUEUED seq=\d+", r.stdout) for r in rs)
    assert "TOOL_SENDER from=ft-head-lag exempt=rate" in rs[5].stderr


def test_seat_sender_sixth_send_still_rate_limited(tmp_path: Path):
    rs = [_send(tmp_path, f"dst#{i}", "byz-x-master-claude#1", f"보고 {i}") for i in range(6)]
    assert [r.returncode for r in rs[:5]] == [0] * 5
    assert rs[5].returncode == 3 and "RATE_LIMIT" in rs[5].stderr


def test_ft_prefixed_seat_with_hash_is_not_a_tool_sender(tmp_path: Path):
    rs = [_send(tmp_path, f"dst#{i}", "ft-v65-arch-fable#40", f"보고 {i}") for i in range(6)]
    assert rs[5].returncode == 3 and "RATE_LIMIT" in rs[5].stderr


def test_tool_sender_same_body_to_three_recipients_no_fanout(tmp_path: Path):
    rs = [_send(tmp_path, f"dst#{i}", TOOL, "같은 착지 본문") for i in range(3)]
    assert [r.returncode for r in rs] == [0] * 3, [r.stderr for r in rs]
    assert "TOOL_SENDER from=ft-head-lag exempt=fanout" in rs[2].stderr


def test_seat_sender_same_body_still_fanout(tmp_path: Path):
    first = _send(tmp_path, "dst#1", "byz-x-master-claude#1", "같은 본문")
    assert first.returncode == 0
    r = _send(tmp_path, "dst#2", "byz-x-master-claude#1", "같은 본문")
    assert r.returncode == 3 and "FANOUT" in r.stderr


def test_tool_sender_empty_body_still_rejected(tmp_path: Path):
    r = _send(tmp_path, "dst#1", TOOL, "   ")
    assert r.returncode == 3 and "EMPTY_BODY" in r.stderr


def _fields(r: subprocess.CompletedProcess[str]) -> list[str]:
    return [kv.split("=")[0] for kv in r.stdout.split() if "=" in kv]


def test_exemption_does_not_change_send_output_fields(tmp_path: Path):
    # 면제는 판정만 — 발신 결과 필드(doorbell 포함 출력 계약)는 좌석 발신과 같다
    tool = _send(tmp_path, "dst#1", TOOL, "알림 a")
    seat = _send(tmp_path, "dst#2", "byz-x-master-claude#1", "알림 b")
    assert _fields(tool) == _fields(seat)
