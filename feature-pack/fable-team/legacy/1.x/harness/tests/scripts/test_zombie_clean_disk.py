"""zombie-clean.sh `disk` — 디스크 임계 점검 + 후보 목록 + 승인 범주 삭제 (R128 · R246).

격리 임시 HOME + 가짜 df/docker(PATH 앞) — 실제 삭제·실제 docker 호출 0.
"""
import os
import stat
import subprocess
from pathlib import Path

ZC = Path(__file__).resolve().parents[3] / "harness/kit/zombie-clean/zombie-clean.sh"

FAKE_DF = """#!/bin/bash
# df -Pk <path> 모사: 사용률만 환경변수로 지정
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/fake 1000 ${FAKE_DF_PCT:-50}0 100 ${FAKE_DF_PCT:-50}% /"
"""

FAKE_DOCKER = """#!/bin/bash
echo "$*" >> "$FAKE_DOCKER_LOG"
if [[ -n "${FAKE_DOCKER_HANG:-}" ]]; then sleep 30; fi
case "$1 $2" in
    "volume ls") for c in a b c; do printf "$c%.0s" $(seq 64); echo; done; echo byz-agents_postgres_data ;;
    "volume prune") echo "Total reclaimed space: 1GB" ;;
    "system df") echo "Local Volumes|29.66GB (63%)" ;;
    "version --format") echo "${FAKE_DOCKER_API-1.43}" ;;
esac
"""


def _exe(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


def _blob(path: Path, mb: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(os.urandom(1024) * 1024 * mb)


def _env(tmp_path: Path, pct: int, **extra: str) -> dict:
    home = tmp_path / "home"
    bindir = tmp_path / "bin"
    home.mkdir(exist_ok=True)
    bindir.mkdir(exist_ok=True)
    _exe(bindir / "df", FAKE_DF)
    _exe(bindir / "docker", FAKE_DOCKER)
    hub = home / ".cache/huggingface/hub"
    _blob(hub / "models--a--b/blob", 2)
    _blob(hub / "datasets--c--d/blob", 1)
    _blob(hub / "keepme-not-approved/blob", 1)
    _blob(home / ".cache/uv/x", 3)
    _blob(home / ".ollama/models/y", 4)
    env = {
        "HOME": str(home),
        "PATH": f"{bindir}:/usr/bin:/bin:/usr/sbin:/sbin",
        "FAKE_DF_PCT": str(pct),
        "FAKE_DOCKER_LOG": str(tmp_path / "docker.log"),
        "ZC_DISK_STAMP": str(tmp_path / "stamp"),
    }
    env.update(extra)
    return env


def _run(tmp_path: Path, pct: int, *args: str, **extra: str) -> subprocess.CompletedProcess:
    env = _env(tmp_path, pct, **extra)
    return subprocess.run(
        ["/bin/bash", str(ZC), "disk", *args],
        env=env, capture_output=True, text=True, timeout=60, check=False,
    )


def _docker_calls(tmp_path: Path) -> str:
    log = tmp_path / "docker.log"
    return log.read_text() if log.exists() else ""


def test_below_threshold_prints_nothing(tmp_path):
    r = _run(tmp_path, 80)
    assert r.returncode == 0
    assert r.stdout == "" and r.stderr == ""


def test_above_threshold_lists_candidates_and_deletes_nothing(tmp_path):
    r = _run(tmp_path, 97)
    assert r.returncode == 0, r.stderr
    assert "97%" in r.stdout
    assert "HF 캐시" in r.stdout and "Docker 미사용 볼륨 3개" in r.stdout and "uv 캐시" in r.stdout
    hub = tmp_path / "home/.cache/huggingface/hub"
    assert (hub / "models--a--b").exists() and (hub / "datasets--c--d").exists()
    assert "prune" not in _docker_calls(tmp_path)


def test_apply_approved_deletes_only_approved_categories(tmp_path):
    r = _run(tmp_path, 97, "--apply-approved")
    assert r.returncode == 0, r.stderr
    home = tmp_path / "home"
    hub = home / ".cache/huggingface/hub"
    assert not (hub / "models--a--b").exists() and not (hub / "datasets--c--d").exists()
    assert (hub / "keepme-not-approved").exists()
    assert (home / ".cache/uv/x").exists() and (home / ".ollama/models/y").exists()
    calls = _docker_calls(tmp_path)
    assert "volume prune -f" in calls and "prune -a" not in calls and "-a" not in calls.split()


def test_prune_skipped_when_docker_api_below_1_42(tmp_path):
    # API < 1.42 는 prune 에 all=true 가 자동 적용돼 이름 있는 볼륨까지 지운다 — prune 금지, HF 삭제는 진행
    r = _run(tmp_path, 97, "--apply-approved", FAKE_DOCKER_API="1.41")
    assert r.returncode != 0 and "ERROR" in r.stderr and "1.42" in r.stderr
    assert "prune" not in _docker_calls(tmp_path)
    assert not (tmp_path / "home/.cache/huggingface/hub/models--a--b").exists()


def test_prune_runs_when_docker_api_is_1_42(tmp_path):
    r = _run(tmp_path, 97, "--apply-approved", FAKE_DOCKER_API="1.42")
    assert r.returncode == 0, r.stderr
    assert "volume prune -f" in _docker_calls(tmp_path)


def test_prune_skipped_when_docker_api_unreadable(tmp_path):
    for bad in ("", "garbage"):
        r = _run(tmp_path, 97, "--apply-approved", FAKE_DOCKER_API=bad)
        assert r.returncode != 0 and "ERROR" in r.stderr, bad
        assert "prune" not in _docker_calls(tmp_path), bad


def test_uv_and_ollama_are_list_only(tmp_path):
    r = _run(tmp_path, 97, "--apply-approved")
    assert "uv 캐시" in r.stdout and "ollama" in r.stdout
    assert "목록만" in r.stdout


def test_dry_run_apply_deletes_nothing(tmp_path):
    r = _run(tmp_path, 97, "--apply-approved", "--dry-run")
    assert r.returncode == 0, r.stderr
    assert (tmp_path / "home/.cache/huggingface/hub/models--a--b").exists()
    assert "prune" not in _docker_calls(tmp_path)


def test_docker_hang_errors_after_7s_rule_not_silent(tmp_path):
    r = _run(tmp_path, 97, FAKE_DOCKER_HANG="1", ZC_DISK_CALL_TIMEOUT_S="1")
    assert r.returncode != 0
    assert "ERROR" in r.stderr and "docker" in r.stderr


def test_slow_size_probe_is_reported_unknown_not_blocking(tmp_path):
    env = _env(tmp_path, 97, ZC_DISK_CALL_TIMEOUT_S="1")
    _exe(tmp_path / "bin/du", "#!/bin/bash\nsleep 30\n")
    r = subprocess.run(["/bin/bash", str(ZC), "disk"], env=env, capture_output=True, text=True, timeout=60, check=False)
    assert r.returncode == 0, r.stderr
    assert "크기 미확인" in r.stdout and "uv 캐시" in r.stdout


def test_default_call_timeout_is_seven_seconds():
    assert "ZC_DISK_CALL_TIMEOUT_S:-7" in (ZC.parent / "zombie-clean-disk.sh").read_text()
