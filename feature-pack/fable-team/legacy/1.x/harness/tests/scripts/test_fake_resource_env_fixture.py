"""R218 — conftest 픽스처 fake_resource_env 가 문지기를 무력화하지 않고 값만 바꾼다."""
import subprocess
from pathlib import Path
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

GATE = Path(__file__).resolve().parents[3] / "harness/bin/ft-resource-gate.sh"


def _check(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["bash", str(GATE), "check"], env=env, capture_output=True, text=True, check=False)


def test_ok_mode_passes(fake_resource_env) -> None:
    r = _check(fake_resource_env("ok"))
    assert r.returncode == 0 and r.stdout.startswith("OK ") and "level=1" in r.stdout


def test_reject_mode_still_rejects(fake_resource_env) -> None:
    r = _check(fake_resource_env("reject"))
    assert r.returncode != 0 and "REJECT resource level=4" in r.stdout


def test_threshold_env_in_caller_shell_is_ignored(fake_resource_env, monkeypatch) -> None:
    for var, val in {"FT_AGENT_MAX": "1", "FT_DISK_MIN_GIB": "99999", "FT_MEM_FREE_MIN_PCT": "99", "FT_MEM_FREE_MIN_SUCC": "99",
                     "FT_PRESSURE_MAX": "0", "FT_PRESSURE_MAX_SUCC": "0", "FT_SWAP_HARD_MIB": "1", "FT_SWAP_MAX_MIB": "1",
                     "FT_SWAP_RATE_MAX": "0", "FT_SWAP_RATE_MAX_SUCC": "0"}.items():
        monkeypatch.setenv(var, val)
    assert _check(fake_resource_env("ok")).returncode == 0
    r = _check(fake_resource_env("reject"))
    assert r.returncode != 0 and "REJECT resource level=4" in r.stdout
