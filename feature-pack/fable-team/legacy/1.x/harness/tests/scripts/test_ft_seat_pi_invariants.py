"""Frozen non-Pi bytes and source/kit identity, against the order's base commit."""
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[5]
HARNESS = ROOT / "feature-pack/fable-team/harness"
BASE = "cff35549"
NAMES = ("ft_seat_pi.py", "ft_seat_pi_turn.py", "ft-seat-status.sh", "ft_team_turns.py",
         "ft_team_state.py", "ft-news-tree.py", "ft_roster_lib.py", "ft_seat_bind.py",
         "ft-seat-retire.sh", "ft-seat-close.sh", "ft-reach-check.sh")


def original(path):
    result = subprocess.run(["git", "show", f"{BASE}:{path.relative_to(ROOT)}"], cwd=ROOT,
                            capture_output=True, timeout=7)
    assert result.returncode == 0, "판정 불가 git show"
    return result.stdout


def strip_insertions(data):
    return re.sub(rb"^[ \t]*# PI ADAPTER BEGIN\n.*?^[ \t]*# PI ADAPTER END\n", b"", data, flags=re.M | re.S)


@pytest.mark.parametrize("name", NAMES)
def test_source_equals_installable_kit(name):
    source = HARNESS / ("comm" if name == "ft-reach-check.sh" else "bin") / name
    assert source.read_bytes() == (HARNESS / "kit/fable-team/bin" / name).read_bytes()


@pytest.mark.parametrize("name", ("ft-seat-status.sh", "ft_team_turns.py", "ft_team_state.py", "ft-news-tree.py",
                                 "ft_seat_bind.py", "ft-seat-retire.sh", "ft-seat-close.sh"))
def test_removing_pi_insertions_recovers_exact_base(name):
    source = HARNESS / "bin" / name
    assert strip_insertions(source.read_bytes()) == original(source)


def test_codex_and_claude_judges_are_byte_identical():
    for folder in ("bin", "kit/fable-team/bin"):
        for name in ("ft_seat_codex.py", "ft_seat_turn.py", "ft_api_outage_util.py", "ft_model_swap.py"):
            path = HARNESS / folder / name
            assert path.read_bytes() == original(path)


def test_roster_non_pi_code_is_byte_identical():
    path = HARNESS / "bin/ft_roster_lib.py"
    assert path.read_bytes().split(b"def pi_seat_resume", 1)[0] == original(path).split(b"def pi_seat_resume", 1)[0]


def test_reach_non_pi_code_is_byte_identical():
    path = HARNESS / "comm/ft-reach-check.sh"
    def strip_pi(data):
        data = strip_insertions(data)
        return re.sub(rb"^pi_seat_dir\(\) \{.*?^PI=0;", b"PI=0;", data, flags=re.M | re.S)
    assert strip_pi(path.read_bytes()) == strip_pi(original(path))
