"""R144 — `ft-seat-status.sh turn --file` 이 꼬리 창(FT_SEAT_TAIL_BYTES)보다 긴 턴에서도 WORKING 을 내는지.

합성 jsonl 만 쓴다 — 실 좌석 기록 읽기 0. 창은 작게(CAP) 잡아 «끝 레코드가 창 밖» 을 만든다.
출력 1줄(`--json` 아님): STATE TURN_END_ISO DURATION_MS REPORTED SOURCE
"""

import json
import os
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[3] / "harness" / "bin" / "ft-seat-status.sh"
MASTER = "t-master#1"
CAP, START = 4096, 1024


def _end(ts: str = "2026-10-13T01:00:00Z") -> dict:
    return {"type": "system", "subtype": "turn_duration", "timestamp": ts, "durationMs": 1234}


def _msg(kind: str, text: str = "x") -> dict:
    return {"type": kind, "message": {"role": kind, "content": [{"type": "text", "text": text}]}}


def _report() -> dict:
    cmd = f"bash mbox.sh send {MASTER} me hi"
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "input": {"command": cmd}}]}}


def _turn(tmp_path: Path, records: list[dict], *, flags: tuple[str, ...] = (), start: int = START) -> str:
    f = tmp_path / "seat.jsonl"
    f.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")
    env = {**os.environ, "FT_SEAT_TAIL_BYTES": str(CAP), "FT_SEAT_TAIL_START": str(start), "FT_MASTER_SEAT": MASTER}
    for k in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY"):
        env.pop(k, None)
    r = subprocess.run(["bash", str(SCRIPT), "turn", "--file", str(f), *flags], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    return r.stdout.strip()


def _long_open_turn() -> list[dict]:
    """턴 끝 레코드 1개 + 그 뒤 창(CAP)을 넘는 user/assistant 기록."""
    return [_end(), _msg("user", "go")] + [_msg("assistant", "w" * 100) for _ in range(80)]


def test_long_turn_default_mode_is_working(tmp_path):
    row = _turn(tmp_path, _long_open_turn()).split()
    assert row[0] == "WORKING" and row[3] == "-"


def test_long_turn_no_reported_is_working(tmp_path):
    assert _turn(tmp_path, _long_open_turn(), flags=("--no-reported",)).split()[0] == "WORKING"


def test_first_window_is_cap_both_modes_working(tmp_path):
    for flags in ((), ("--no-reported",)):
        row = _turn(tmp_path, _long_open_turn(), flags=flags, start=CAP).split()
        assert row[0] == "WORKING", flags


def test_first_turn_in_progress_small_file_is_working(tmp_path):
    for flags in ((), ("--no-reported",)):
        row = _turn(tmp_path, [_msg("user", "go"), _msg("assistant")], flags=flags).split()
        assert row[0] == "WORKING", flags


def test_no_user_assistant_in_window_stays_unknown(tmp_path):
    giant = {"type": "system", "subtype": "x", "pad": "p" * (CAP * 3)}
    assert _turn(tmp_path, [_end(), giant]).split()[0] == "UNKNOWN"


def test_two_ends_nothing_after_is_idle(tmp_path):
    assert _turn(tmp_path, [_end(), _msg("user"), _end("2026-10-13T02:00:00Z")]).split()[0] == "IDLE"


def test_enqueue_only_after_end_is_pending(tmp_path):
    recs = [_end(), _msg("user"), _end("2026-10-13T02:00:00Z"), {"type": "queue-operation", "operation": "enqueue"}]
    assert _turn(tmp_path, recs).split()[0] == "PENDING"


def test_previous_turn_mbox_send_is_reported_yes(tmp_path):
    recs = [_end(), _msg("user"), _report(), _end("2026-10-13T02:00:00Z")]
    row = _turn(tmp_path, recs).split()
    assert row[0] == "IDLE" and row[3] == "yes"
