"""tests/scripts 자동 가드 (R121 · 판정 1432) — 시험이 공용 .git/config 를 바꾸지 못하게 한다.

사고(2026-10-13): 시험 실행 환경에 GIT_DIR=<공용 .git> 이 걸려 있어 픽스처의 `git init`·`git config user.*` 가
임시 폴더가 아니라 공용 저장소를 고쳤다(core.bare=true · 작성자 t).
①시험 시작 전 GIT_* 저장소 지정 변수를 지운다(하위 프로세스는 os.environ 을 물려받는다).
②시험 전후로 공용 git config 의 core.bare·user.name·user.email 을 비교해 바뀌었으면 실패시킨다(복원은 사람).
"""

import os
import shutil
import subprocess
from collections.abc import Callable, Iterator
from pathlib import Path

import pytest

from fake_resource_env import fake_comm_root as _fake_comm_root
from fake_resource_env import fake_resource_env as _fake_resource_env

GIT_ENV_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY")
REAL_GIT: str = shutil.which("git") or "git"  # 시험이 PATH 를 비워도 가드의 git 은 살아 있어야 한다
GUARDED_KEYS = r"^(core\.bare|user\.name|user\.email)$"


def _clean_env() -> dict[str, str]:
    return {k: v for k, v in os.environ.items() if k not in GIT_ENV_VARS}


def _common_config(here: Path) -> Path:
    out = subprocess.run([REAL_GIT, "-C", str(here), "rev-parse", "--git-common-dir"],
                         check=True, capture_output=True, text=True, env=_clean_env()).stdout.strip()
    return (here / out).resolve() / "config"


def _snapshot(config: Path) -> dict[str, str]:
    res = subprocess.run([REAL_GIT, "config", "--file", str(config), "--get-regexp", GUARDED_KEYS],
                         capture_output=True, text=True, env=_clean_env())
    return dict(line.split(" ", 1) for line in res.stdout.splitlines() if " " in line)


@pytest.fixture(autouse=True)
def _git_env_guard(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    for var in GIT_ENV_VARS:
        monkeypatch.delenv(var, raising=False)
    config = _common_config(Path(__file__).parent)
    before = _snapshot(config)
    yield
    after = _snapshot(config)
    if after != before:
        pytest.fail(f"공용 git config 가 시험 중 바뀜({config}) — 복원은 사람: 전 {before} → 후 {after}", pytrace=False)


@pytest.fixture(autouse=True)
def _isolated_ft_root(monkeypatch: pytest.MonkeyPatch, tmp_path_factory: pytest.TempPathFactory) -> None:
    """post_guard 의 사람 채널 명부 출처(FT_ROOT)를 빈 `.fable-team/` 로 격리 — 라이브 명부·CI 유무와 무관(R231a 교정 2). 필요한 시험이 덮는다."""
    root = tmp_path_factory.mktemp("ft_root")
    (root / ".fable-team").mkdir()
    monkeypatch.setenv("FT_ROOT", str(root))


@pytest.fixture(autouse=True)
def _ledger_sync_env_off(monkeypatch: pytest.MonkeyPatch) -> None:
    """r584 — 원장 동기화 «이번 틱에 했다»·«실패 문구» 는 ft_news_ledger 가 프로세스 env 에 적는다(틱 자식에 물려주려는 설계).
    한 프로세스에서 여러 시험을 돌리면 앞 시험이 남긴 값이 뒤 시험 머리 줄로 새어 순서 의존 FAIL(test_ft_news_html head 문구)이 된다.
    시험마다 지운다 — 키트의 틱 설계는 그대로."""
    for var in ("FT_LEDGER_SYNCED", "FT_LEDGER_SYNC_ERROR"):
        monkeypatch.delenv(var, raising=False)


@pytest.fixture(autouse=True)
def _allow_tracked_bin(monkeypatch: pytest.MonkeyPatch) -> None:
    """R201: 시험은 추적 사본 원본을 직접 부른다 — ft-live-entry 가 LIVE_BIN(옛 라이브)으로 넘기지 않게 한다."""
    monkeypatch.setenv("FT_ALLOW_TRACKED_BIN", "1")


@pytest.fixture(autouse=True)
def _teamset_off(monkeypatch: pytest.MonkeyPatch) -> None:
    """R351: 팀셋 표는 origin/main 에서 읽는다 — 임시 리포엔 그 표가 없어 nano-spawn 이 REJECT 한다. 표 판정은 tests/harness/test_teamset_gitref.sh 가 본다."""
    monkeypatch.setenv("FT_TEAMSET", "0")


@pytest.fixture
def fake_resource_env(tmp_path: Path) -> Callable[[str], dict[str, str]]:
    """R218 — 자원 문지기 가짜 센서가 걸린 env dict 를 돌려주는 함수(mode = ok|reject). 실 머신 부하·압력과 무관하게 같은 결과."""
    return lambda mode="ok": _fake_resource_env(tmp_path, mode)


@pytest.fixture
def fake_comm_root() -> Callable[[Path], Path]:
    """r537 — 임시 공용 루트(git 리포 + .fable-team/comm·state·LIVE_BIN·seats.json + design/TEAMS.md)를 만드는 함수. 실 공용 루트 0."""
    return _fake_comm_root
