"""R362 무장 판정 3구현(comm 셸 · 뉴스 ft_goal_gate · 매거진 magazine_goal)의 표식 경로·의미 동일 고정 (DA⑥ H1③ — 판정 함수 1개로 못 묶으면 교차 경로 계약 시험).

표식 = <루트>/.fable-team/state/goal-gate.armed «파일» 이 있을 때만 무장(디렉터리·없음 = 비무장). 실행: .venv/bin/python -m pytest tests/scripts/test_goal_gate_armed_contract.py -q
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(ROOT / "harness" / "bin"), str(ROOT / "harness" / "kit" / "slack-mirror")]

import ft_goal_gate as gate  # noqa: E402
import magazine_goal as mag  # noqa: E402

GUARD = ROOT / "harness" / "comm" / "mbox_guard.sh"


def shell_armed(root: Path) -> bool:
    """mbox_guard.sh 의 goal_armed — DIR = <루트>/.fable-team/comm 로 두면 GUARD_STATE = <루트>/.fable-team/state."""
    comm = root / ".fable-team" / "comm"
    comm.mkdir(parents=True, exist_ok=True)
    script = f'DIR="{comm}"; source "{GUARD}"; goal_armed'
    return subprocess.run(["bash", "-c", script], capture_output=True, check=False).returncode == 0


def py_armed(root: Path) -> bool:
    return gate.armed(root / ".fable-team" / "state")


def mag_armed(root: Path, monkeypatch) -> bool:
    monkeypatch.setenv("FT_ROOT", str(root))
    return mag.armed()


@pytest.mark.parametrize("kind", ["none", "file", "dir"])
def test_the_three_armed_judges_agree(tmp_path, monkeypatch, kind):
    state = tmp_path / ".fable-team" / "state"
    state.mkdir(parents=True)
    if kind == "file":
        (state / "goal-gate.armed").write_text("", encoding="utf-8")
    elif kind == "dir":
        (state / "goal-gate.armed").mkdir()
    want = kind == "file"
    assert (shell_armed(tmp_path), py_armed(tmp_path), mag_armed(tmp_path, monkeypatch)) == (want, want, want)
