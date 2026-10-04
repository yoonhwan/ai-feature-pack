"""mbox.py send 의 append-only 사본(mailbox.log.jsonl) — Slack 미러 입력 소스 (D1).

mailbox.jsonl 은 consume-on-read 라 recv 하면 행이 사라진다. 미러가 짧은 보고를 놓치지
않으려면 «보낸 모든 행» 이 남는 별도 파일이 필요하다. 기존 큐 동작은 그대로여야 한다.
"""
import json
import os
import subprocess
import sys
from pathlib import Path

MBOX = Path(__file__).resolve().parents[2] / "tools" / "comm-canonical" / "mbox.py"


def _run(box: Path, *args: str, extra_env: dict[str, str] | None = None):
    env = {**os.environ, "FT_MBOX_DIR": str(box), "FT_MBOX_RELAY_DIR": str(box / "relay")}
    env.update(extra_env or {})
    return subprocess.run(
        [sys.executable, str(MBOX), *args], env=env, capture_output=True, text=True, timeout=30
    )


def _log(box: Path) -> list[dict[str, object]]:
    p = box / "mailbox.log.jsonl"
    return [json.loads(ln) for ln in p.read_text(encoding="utf-8").splitlines() if ln.strip()]


def _send(box: Path, to: str, body: str, frm: str = "src#1", extra_env: dict[str, str] | None = None):
    return _run(box, "send", to, frm, body, extra_env=extra_env)


def test_send_appends_row_to_log(tmp_path: Path):
    r = _send(tmp_path, "dst#1", "보고 3줄")
    assert r.returncode == 0, r.stderr
    rows = _log(tmp_path)
    assert [(x["to"], x["from"], x["body"]) for x in rows] == [("dst#1", "src#1", "보고 3줄")]
    assert isinstance(rows[0]["seq"], int) and rows[0]["ts"]


def test_log_survives_recv_consume(tmp_path: Path):
    _send(tmp_path, "dst#1", "읽히면 큐에서 사라지는 짧은 보고")
    assert _run(tmp_path, "recv", "dst#1").returncode == 0
    queue = (tmp_path / "mailbox.jsonl").read_text(encoding="utf-8").strip()
    assert queue == ""  # 큐는 consume-on-read 그대로
    assert [x["body"] for x in _log(tmp_path)] == ["읽히면 큐에서 사라지는 짧은 보고"]


def test_log_keeps_rows_the_ring_drops(tmp_path: Path):
    for i in range(12):  # ring(기본 10) 포화 — 큐는 2건을 버린다
        _send(tmp_path, "dst#1", f"msg-{i}", frm=f"s{i}#1")
    assert len(_log(tmp_path)) == 12


def test_blocked_send_is_not_logged(tmp_path: Path):
    r = _send(tmp_path, "dst#1", "   ")  # EMPTY_BODY 로 BLOCKED
    assert r.returncode == 3
    assert not (tmp_path / "mailbox.log.jsonl").exists()


def test_log_failure_warns_loudly_and_send_still_succeeds(tmp_path: Path):
    (tmp_path / "mailbox.log.jsonl").mkdir()  # open() 이 실패하게 만든다
    r = _send(tmp_path, "dst#1", "사본이 안 써져도 통신은 산다")
    assert r.returncode == 0
    assert "QUEUED" in r.stdout
    assert "WARN" in r.stderr and "mailbox.log.jsonl" in r.stderr  # 조용히 삼키지 않는다
    assert "사본이 안 써져도 통신은 산다" in (tmp_path / "mailbox.jsonl").read_text(encoding="utf-8")


def test_log_rotation_bounds_the_file(tmp_path: Path):
    env = {"FT_MBOX_LOG_MAX_BYTES": "600"}
    for i in range(30):
        _send(tmp_path, "dst#1", f"회전 시험 본문 {i} " + "x" * 40, frm=f"s{i}#1", extra_env=env)
    active = tmp_path / "mailbox.log.jsonl"
    prev = tmp_path / "mailbox.log.jsonl.1"
    assert prev.exists()
    assert active.stat().st_size <= 600 + 400  # 한도 + 한 행
    seqs = [json.loads(ln)["seq"] for p in (prev, active) for ln in p.read_text(encoding="utf-8").splitlines()]
    assert seqs == sorted(seqs) and seqs[-1] == max(seqs)  # 순서 유지 · 최신 행 보존
