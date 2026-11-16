"""Source/kit identity for the Pi seat adapter files."""
from pathlib import Path

import pytest

HARNESS = Path(__file__).resolve().parents[2]
NAMES = ("ft_seat_pi.py", "ft_seat_pi_turn.py", "ft-seat-status.sh", "ft_team_turns.py",
         "ft_team_state.py", "ft-news-tree.py", "ft_roster_lib.py", "ft_seat_bind.py",
         "ft-seat-retire.sh", "ft-seat-close.sh", "ft-reach-check.sh")


@pytest.mark.parametrize("name", NAMES)
def test_source_equals_installable_kit(name):
    source = HARNESS / ("comm" if name == "ft-reach-check.sh" else "bin") / name
    assert source.read_bytes() == (HARNESS / "kit/fable-team/bin" / name).read_bytes()
