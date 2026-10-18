"""뉴스 발행기 import 경로 — 라이브 bin 꼴에서도 PYTHONPATH 없이 magazine_slack·mirror_lib 를 찾는다 (R138).

라이브 bin(`<루트>/.fable-team/bin`)에는 옆 키트 폴더가 없고 설치본은 `~/.hermes/scripts` 에 있다.
서브프로세스 + 가짜 HOME + 가짜 모듈 — 실제 Slack 호출 0, ~/.hermes/scripts 쓰기 0.
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR python3 -m pytest tests/scripts/test_ft_news_publish_import_path.py -q
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
FAKE_MAGAZINE = "def post_root(*a, **k):\n    raise SystemExit('fake')\n\n\ndef permalink(*a, **k):\n    raise SystemExit('fake')\n"  # R217: 발행기가 permalink 도 가져온다
FAKE_MIRROR = "class MirrorError(Exception):\n    pass\n\n\ndef paged(*a, **k):\n    return []\n"


def _fake_modules(folder: Path) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "magazine_slack.py").write_text(FAKE_MAGAZINE, encoding="utf-8")
    (folder / "mirror_lib.py").write_text(FAKE_MIRROR, encoding="utf-8")
    return folder


def _copy_bin(dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    for name in ("ft_news_publish.py", "ft_board_env.py", "ft_goal_gate.py", "ft_goal_receipt.py", "ft_goal_table.py", "ft_goal_ledger.py", "ft_news_post.py", "ft_team_lib.py"):  # R362: 발행 문이 부르는 모듈도 라이브 bin 에 깔린다
        shutil.copy(BIN / name, dest / name)
    return dest / "ft_news_publish.py"


def _run(script: Path, home: Path, **extra: str) -> "subprocess.CompletedProcess[str]":
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "FT_HERMES_SCRIPTS", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")}
    env["HOME"] = str(home)
    env.update(extra)
    return subprocess.run([sys.executable, str(script), "--help"], env=env, capture_output=True, text=True, timeout=30)


def test_live_bin_finds_installed_modules_without_pythonpath(tmp_path):
    script = _copy_bin(tmp_path / "root" / ".fable-team" / "bin")
    _fake_modules(tmp_path / "home" / ".hermes" / "scripts")
    r = _run(script, tmp_path / "home")
    assert r.returncode == 0, r.stderr


def test_repo_original_finds_kit_folder(tmp_path):
    script = _copy_bin(tmp_path / "harness" / "bin")
    _fake_modules(tmp_path / "harness" / "kit" / "slack-mirror")
    (tmp_path / "home").mkdir()
    r = _run(script, tmp_path / "home")
    assert r.returncode == 0, r.stderr


def test_neither_location_fails_loudly_with_searched_paths(tmp_path):
    script = _copy_bin(tmp_path / "root" / ".fable-team" / "bin")
    (tmp_path / "home").mkdir()
    r = _run(script, tmp_path / "home")
    assert r.returncode != 0
    assert str(tmp_path / "home" / ".hermes" / "scripts") in r.stderr
    assert str(tmp_path / "root" / ".fable-team" / "harness-install" / "slack-mirror") in r.stderr


def test_ft_hermes_scripts_env_overrides_install_folder(tmp_path):
    script = _copy_bin(tmp_path / "root" / ".fable-team" / "bin")
    (tmp_path / "home").mkdir()
    custom = _fake_modules(tmp_path / "elsewhere")
    r = _run(script, tmp_path / "home", FT_HERMES_SCRIPTS=str(custom))
    assert r.returncode == 0, r.stderr


def test_installed_folder_wins_over_kit_folder(tmp_path):
    script = _copy_bin(tmp_path / "harness" / "bin")
    kit = _fake_modules(tmp_path / "harness" / "kit" / "slack-mirror")
    (kit / "mirror_lib.py").write_text("raise RuntimeError('kit copy loaded')\n", encoding="utf-8")
    _fake_modules(tmp_path / "home" / ".hermes" / "scripts")
    r = _run(script, tmp_path / "home")
    assert r.returncode == 0, r.stderr
