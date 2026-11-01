"""R1296 — 집계기 최신 JSON은 임시 루트에 원자적으로 기록한다."""
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
sys.path.insert(0, str(BIN))

import ft_card_assign_watch as assign  # noqa: E402
import ft_decision_count as decision  # noqa: E402
import ft_hil_pending as hil  # noqa: E402
import ft_latest_write as latest_write_module  # noqa: E402
from ft_latest_write import write_latest  # noqa: E402

NOW = "2026-11-02T12:34:56"


def saved(root, kind):
    path = root / ".fable-team/state" / kind / "latest.json"
    return path, json.loads(path.read_text(encoding="utf-8"))


def test_writer_envelope_is_atomic_and_keeps_unicode(tmp_path, monkeypatch):
    root = tmp_path
    monkeypatch.setenv("FT_ROOT", str(root))
    target = write_latest(root, "decision", "ft-decision-count.sh", "결정 1건", [{"seq": 7}], 1793622896)
    path, data = saved(root, "decision")
    assert target == path and set(data) == {"tool", "kind", "written_at", "stamp", "line", "items"}
    assert data == {"tool": "ft-decision-count.sh", "kind": "decision", "written_at": 1793622896,
                    "stamp": None, "line": "결정 1건", "items": [{"seq": 7}]}
    assert path.read_bytes().endswith(b"\n")
    assert list(path.parent.glob("latest.json.tmp-*")) == []


def test_writer_uses_atomic_replace(tmp_path, monkeypatch):
    calls = []
    replace = latest_write_module.os.replace
    monkeypatch.setattr(latest_write_module.os, "replace", lambda src, dst: (calls.append((src, dst)), replace(src, dst))[1])
    write_latest(tmp_path, "hil", "ft-hil.sh --pending", "", [], 1)
    assert len(calls) == 1 and str(calls[0][0]).endswith(f"latest.json.tmp-{os.getpid()}")


def test_decision_opt_in_writes_line_and_detail_items(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_DECISION_NOW", NOW)
    monkeypatch.setattr(decision, "summary", lambda _now: {
        "team": [(7, "byz-cfo-master-claude#1", 31, "본문", "body.txt")], "stale": 0,
        "n": 1, "m": 0, "miss": 0, "notes": "", "detail": [(7, "byz-cfo-master-claude#1", 31, "질문표식", "body.txt")],
    })
    rc = decision.main(["--detail", "--write-latest"])
    out = capsys.readouterr().out
    path, data = saved(tmp_path, "decision")
    assert rc == 0 and out.splitlines()[0] == data["line"]
    assert data["items"] == ["#7 byz-cfo-master-claude#1 31분 질문표식 "]
    assert data["written_at"] == int(datetime.fromisoformat(NOW).timestamp())


def test_decision_default_does_not_write(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_DECISION_NOW", NOW)
    monkeypatch.setattr(decision, "summary", lambda _now: {
        "team": [], "stale": 0, "n": 0, "m": 0, "miss": 0, "notes": "", "detail": [],
    })
    assert decision.main([]) == 0
    assert capsys.readouterr().out.startswith("결정 인터뷰 0건")
    assert not (tmp_path / ".fable-team/state/decision/latest.json").exists()


def test_decision_failure_preserves_old_file(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_DECISION_NOW", NOW)
    old = tmp_path / ".fable-team/state/decision/latest.json"
    old.parent.mkdir(parents=True)
    old.write_text("old\n", encoding="utf-8")
    monkeypatch.setattr(decision, "summary", lambda _now: (_ for _ in ()).throw(decision.ReadError("bad")))
    assert decision.main(["--write-latest"]) == 4
    assert old.read_text(encoding="utf-8") == "old\n"
    assert "latest 안 씀(rc 4)" in capsys.readouterr().err


def test_decision_alarm_call_path_writes_after_summary_line(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_DECISION_NOW", NOW)
    monkeypatch.setattr(decision, "summary", lambda _now: {
        "team": [], "stale": 0, "n": 0, "m": 0, "miss": 0, "notes": "", "detail": [],
    })
    monkeypatch.setattr(decision, "safe_alarm", lambda _s: (print("ALARM"), 0)[1])
    assert decision.main(["--alarm", "--write-latest"]) == 0
    out = capsys.readouterr().out.splitlines()
    _, data = saved(tmp_path, "decision")
    assert out[0] == data["line"] and out[1] == "ALARM"


def test_assignment_status_writes_json_rows_even_when_hot(tmp_path, monkeypatch, capsys):
    rows = [{"kind": "없음", "card": "c1"}]
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setattr(assign, "root", lambda: tmp_path)
    monkeypatch.setattr(assign, "Status", lambda *_a: type("S", (), {"rows": lambda _self: (rows, "2026-11-02", [])})())
    monkeypatch.setattr(assign, "render", lambda *_a: ["배정 없음 1"])
    assign.adir(tmp_path).mkdir(parents=True)
    rc = assign.main(["status", "--json", "--write-latest"])
    out = capsys.readouterr().out.strip()
    _, data = saved(tmp_path, "card-assign")
    assert rc == 1 and json.loads(out) == rows and data["line"] == out
    assert data["items"] == rows and data["stamp"] == "2026-11-02"


def test_assignment_failure_preserves_old_file(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    old = tmp_path / ".fable-team/state/card-assign/latest.json"
    old.parent.mkdir(parents=True)
    old.write_text("old\n", encoding="utf-8")
    monkeypatch.setattr(assign, "root", lambda: tmp_path)
    monkeypatch.setattr(assign, "Status", lambda *_a: type("S", (), {"rows": lambda _self: (_ for _ in ()).throw(assign.Undecided("bad"))})())
    assert assign.main(["status", "--write-latest"]) == 3
    assert old.read_text(encoding="utf-8") == "old\n"
    assert "latest 안 씀(rc 3)" in capsys.readouterr().err


def test_assignment_written_at_uses_fixed_now(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_CARD_ASSIGN_NOW", "1000")
    monkeypatch.setattr(assign.time, "time", lambda: 2000)
    monkeypatch.setattr(assign, "root", lambda: tmp_path)
    monkeypatch.setattr(assign, "Status", lambda *_a: type("S", (), {"rows": lambda _self: ([], "2026-11-02", [])})())
    monkeypatch.setattr(assign, "render", lambda *_a: ["배정 없음 0"])
    assert assign.main(["status", "--write-latest"]) == 0
    capsys.readouterr()
    _, data = saved(tmp_path, "card-assign")
    assert data["written_at"] == 1000


def test_assignment_without_flag_keeps_file_absent(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setattr(assign, "root", lambda: tmp_path)
    monkeypatch.setattr(assign, "Status", lambda *_a: type("S", (), {"rows": lambda _self: ([], "2026-11-02", [])})())
    monkeypatch.setattr(assign, "render", lambda *_a: ["배정 없음 0"])
    assign.adir(tmp_path).mkdir(parents=True)
    assert assign.main(["status"]) == 0
    assert capsys.readouterr().out == "배정 없음 0\n"
    assert not (tmp_path / ".fable-team/state/card-assign/latest.json").exists()


def test_hil_pending_writes_each_rows_and_uses_fixed_now(tmp_path, monkeypatch, capsys):
    root, hdir = tmp_path / "root", tmp_path / "hil"
    root.mkdir()
    hdir.mkdir()
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setenv("FT_HIL_NOW", "1793622896")
    monkeypatch.setattr(hil, "scan", lambda _d, _now=None: [("12", 9, False, None)])
    assert hil.main(["ft_hil_pending.py", str(hdir), "--each", "--write-latest"]) == 0
    out = capsys.readouterr().out.strip()
    _, data = saved(root, "hil")
    assert out == data["line"] == "h12 9"
    assert data["items"] == [{"id": "h12", "minutes": 9}]
    assert data["written_at"] == 1793622896


def test_hil_failure_preserves_old_file(tmp_path, monkeypatch, capsys):
    root, hdir = tmp_path / "root", tmp_path / "hil"
    root.mkdir()
    hdir.mkdir()
    monkeypatch.setenv("FT_ROOT", str(root))
    old = root / ".fable-team/state/hil/latest.json"
    old.parent.mkdir(parents=True)
    old.write_text("old\n", encoding="utf-8")
    monkeypatch.setattr(hil, "scan", lambda *_a: (_ for _ in ()).throw(PermissionError("denied")))
    assert hil.main(["ft_hil_pending.py", str(hdir), "--write-latest"]) == 3
    assert old.read_text(encoding="utf-8") == "old\n"
    assert "latest 안 씀(rc 3)" in capsys.readouterr().err


def test_hil_without_flag_keeps_file_absent(tmp_path, monkeypatch, capsys):
    root, hdir = tmp_path / "root", tmp_path / "hil"
    root.mkdir()
    hdir.mkdir()
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setattr(hil, "scan", lambda *_a: [])
    assert hil.main(["ft_hil_pending.py", str(hdir)]) == 0
    assert capsys.readouterr().out == ""
    assert not (root / ".fable-team/state/hil/latest.json").exists()


def test_hil_wrapper_passes_write_flag(tmp_path):
    root, hdir = tmp_path / "root", tmp_path / "hil"
    root.mkdir()
    hdir.mkdir()
    env = {**os.environ, "FT_ROOT": str(root), "HIL_DIR": str(hdir), "FT_HIL_NOW": "1793622896"}
    run = subprocess.run(["bash", str(BIN / "ft-hil.sh"), "--pending", "--write-latest"], capture_output=True, text=True, env=env, timeout=7)
    assert run.returncode == 0 and run.stdout == ""
    _, data = saved(root, "hil")
    assert data["line"] == "" and data["written_at"] == 1793622896
