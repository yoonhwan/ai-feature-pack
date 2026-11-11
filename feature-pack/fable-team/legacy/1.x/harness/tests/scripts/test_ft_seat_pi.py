"""Pi 계약 v3: 합성 session/message와 임시 명부만 사용한다."""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

BIN = Path(__file__).resolve().parents[2] / "bin"
sys.path.insert(0, str(BIN))
SEAT, SID, END = "t-worker-pi#1", "synthetic-session-1", "2026-11-07T01:00:00Z"


def message(role="assistant", **fields):
    return {"type": "message", "timestamp": END, "message": {"role": role, **fields}}


@pytest.fixture
def world(tmp_path, monkeypatch):
    root, cwd = tmp_path / "sessions", tmp_path / "cwd"
    cwd.mkdir()
    (root / "encoded").mkdir(parents=True)
    ft = tmp_path / ".fable-team"
    ft.mkdir()
    (ft / "seats.json").write_text(json.dumps({SEAT: {"agent": "pi"}}), encoding="utf-8")
    tmux = tmp_path / "tmux"
    tmux.write_text(
        "#!/bin/sh\n[ \"${1:-}\" = -u ] && shift\ncase $1 in\n"   # r1701: 제품이 tmux -u 로 부른다(로케일 무관 탭)
        f"list-panes) printf '{SEAT}\\t{os.getpid()}\\t{cwd}\\t0\\n';;\n"
        f"show-environment) echo TMUXC_PI_SESSION_ID={SID};;\n"
        f"list-sessions|ls) echo '{SEAT}';;\n*) exit 1;;\nesac\n", encoding="utf-8")
    tmux.chmod(0o755)
    monkeypatch.setenv("FT_TMUX", str(tmux))
    monkeypatch.setenv("FT_PI_SESSIONS", str(root))
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_SEATS_JSON", str(ft / "seats.json"))
    monkeypatch.setenv("PATH", str(tmp_path) + os.pathsep + os.environ["PATH"])
    monkeypatch.setenv("LC_ALL", "C")
    return root, cwd, ft


def write(world, records, name="one", sid=SID, seat=SEAT):
    root, cwd, _ = world
    path = root / "encoded" / f"{name}.jsonl"
    rows = [{"type": "session", "id": sid, "cwd": str(cwd)},
            {"type": "model_change", "modelId": "synthetic-model"}, *records,
            {"type": "session_info", "id": "record-id-not-session-id", "name": seat}]
    path.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
    return path


def run(world, *args):
    return subprocess.run([sys.executable, str(BIN / "ft_seat_pi.py"),
                           *(args or ("--if-pi", str(world[2]), SEAT))],
                          text=True, capture_output=True, timeout=7)


@pytest.mark.parametrize("records,state", [
    ([message(stopReason="toolUse")], "WORKING"),
    ([message(stopReason="toolUse"), message("toolResult")], "WORKING"),
    ([message(stopReason="stop"), message("user")], "PENDING"),
    ([message(stopReason="stop", content=[{"type": "text", "text": "queued retry pending"}])], "IDLE"),
    ([message(stopReason="error", errorMessage='503 {"error":{"type":"rate_limit_error"}}')], "RATELIMITED"),
    ([message(stopReason="aborted", errorMessage="invalid_api_key")], "LOGGEDOUT"),
    ([message(stopReason="error", errorMessage="503 api_error")], "UNAVAILABLE"),
    ([message()], "UNKNOWN"),
    ([message(stopReason=None), {"type": "context_edit", "timestamp": "ignored"}], "IDLE"),
    ([message(stopReason="error", errorMessage="429"), message("user")], "UNAVAILABLE"),
    ([message(errorMessage="Not logged in")], "LOGGEDOUT"),
    ([message(stopReason="stop"), message("toolResult")], "WORKING"),
    ([message(stopReason="stop"), {"type": "queue-operation", "operation": "enqueue"}], "PENDING"),
    ([message(stopReason="stop"), {"type": "retry_start", "attempt": 1}], "WORKING"),
    ([message(stopReason="error", errorMessage="invalid_api_key quota"), {"type": "retry_start"}], "LOGGEDOUT"),
    ([message(stopReason="stop"), {"type": "retry_start"}, {"type": "retry_end"}], "IDLE"),
    ([message(stopReason="unrecognized")], "UNKNOWN"),
])
def test_contract_turns(world, records, state):
    write(world, records)
    result = run(world)
    assert result.returncode == 0, result.stderr
    row = result.stdout.rstrip().split("\t")
    assert row[0] == state
    assert row[1] == (END if state == "IDLE" else "-")
    assert row[4] == "pi"


def test_same_cwd_other_seat_is_not_selected(world):
    write(world, [message(stopReason="stop")], seat="different-seat")
    assert run(world).returncode != 0


def test_same_cwd_other_seat_does_not_hide_unique_match(world):
    write(world, [message(stopReason="toolUse")], name="other", seat="different-seat")
    write(world, [message(stopReason="stop")])
    assert run(world).stdout.startswith("IDLE\t")


def test_duplicate_uuid_files_are_ambiguous(world):
    write(world, [message(stopReason="stop")])
    write(world, [message(stopReason="stop")], name="two")
    assert run(world).returncode != 0


def test_wrong_cwd_and_missing_live_id_are_rejected(world, tmp_path):
    path = write(world, [message(stopReason="stop")])
    records = path.read_text().replace(str(world[1]), str(tmp_path / "other-cwd"))
    path.write_text(records, encoding="utf-8")
    assert run(world).returncode != 0
    write(world, [message(stopReason="stop")])
    tmux = tmp_path / "tmux"
    tmux.write_text(tmux.read_text().replace("TMUXC_PI_SESSION_ID=", "UNRELATED="), encoding="utf-8")
    assert run(world).returncode != 0


def test_restart_uses_live_uuid(world):
    write(world, [message(stopReason="stop")], name="old", sid="old-session")
    write(world, [message(stopReason="toolUse")], name="new")
    assert run(world).stdout.startswith("WORKING\t")


def test_non_pi_is_rc3(world):
    (world[2] / "seats.json").write_text(json.dumps({SEAT: {"agent": "claude"}}), encoding="utf-8")
    result = run(world)
    assert result.returncode == 3 and result.stdout == ""


def test_external_timeout_is_bounded_and_fail_closed(world, monkeypatch):
    spec = importlib.util.spec_from_file_location("ft_seat_pi", BIN / "ft_seat_pi.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    def timeout(*args, **kwargs):
        assert kwargs["timeout"] <= 7
        raise subprocess.TimeoutExpired("synthetic", kwargs["timeout"])
    monkeypatch.setattr(module, "subprocess", SimpleNamespace(run=timeout, SubprocessError=subprocess.SubprocessError))
    assert module.main(["--if-pi", str(world[2]), SEAT]) != 0
