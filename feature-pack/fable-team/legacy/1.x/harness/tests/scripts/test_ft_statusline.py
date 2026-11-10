"""ft-statusline.sh — Claude Code statusLine 교체본 (R129 · DESIGN-statusline-native-20261012 §3).

실행: python3 -m pytest tests/scripts/test_ft_statusline.py -q
"""
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "harness" / "bin" / "ft-statusline.sh"
KIT = ROOT / "harness" / "kit" / "fable-team" / "bin" / "ft-statusline.sh"
SAMPLE = '{"model":{"display_name":"Sonnet 5.5"},"effort":{"level":"high"},"context_window":{"used_percentage":38}%s}'


def _stubs(tmp_path, tmux_name=None):
    d = tmp_path / "fakebin"
    d.mkdir()
    log = tmp_path / "spawned.log"
    for n in ("node", "jq", "git"):
        (d / n).write_text(f'#!/bin/sh\necho {n} >> "{log}"\n', encoding="utf-8")
        (d / n).chmod(0o755)
    if tmux_name:
        (d / "tmux").write_text(f"#!/bin/sh\necho '{tmux_name}'\n", encoding="utf-8")
        (d / "tmux").chmod(0o755)
    return d, log


def _run(tmp_path, stdin, tmux_name=None, in_tmux=False):
    d, log = _stubs(tmp_path, tmux_name)
    env = {k: v for k, v in os.environ.items() if k != "TMUX"}
    env["PATH"] = f"{d}:{env['PATH']}"
    if in_tmux:
        env["TMUX"] = "/tmp/tmux-0/default,1,0"
    r = subprocess.run(["sh", str(SCRIPT)], input=stdin, capture_output=True, text=True, env=env, timeout=10)
    return r, log


def test_percentage_leads_the_line(tmp_path):
    r, _ = _run(tmp_path, SAMPLE % "")
    assert r.returncode == 0
    assert r.stdout.startswith("ctx:38%")
    assert r.stdout.count("\n") == 1


@pytest.mark.parametrize("stdin", ["", '{"context_window":{"used_percentage":null}}'])
def test_null_or_empty_input_still_prints_one_line_rc0(tmp_path, stdin):
    r, _ = _run(tmp_path, stdin)
    assert r.returncode == 0
    assert r.stdout.startswith("ctx:?%")
    assert r.stdout.count("\n") == 1


def test_tmux_session_name_is_used_when_in_tmux(tmp_path):
    r, _ = _run(tmp_path, SAMPLE % ',"session_name":"stdin-name"', tmux_name="byz-harness-master-claude#39", in_tmux=True)
    assert "byz-harness-master-claude#39" in r.stdout
    assert "stdin-name" not in r.stdout


def test_stdin_session_name_when_not_in_tmux(tmp_path):
    r, _ = _run(tmp_path, SAMPLE % ',"session_name":"stdin-name"', tmux_name="should-not-be-used")
    assert "stdin-name" in r.stdout
    assert "should-not-be-used" not in r.stdout


def test_question_mark_when_no_name_anywhere(tmp_path):
    r, _ = _run(tmp_path, SAMPLE % "")
    assert r.stdout.rstrip("\n").endswith("| ?")


def test_no_node_jq_git_spawned(tmp_path):
    _, log = _run(tmp_path, SAMPLE % ',"session_name":"x"', tmux_name="t", in_tmux=True)
    assert not log.exists()


def test_kit_copy_is_byte_identical():
    assert SCRIPT.read_bytes() == KIT.read_bytes()
