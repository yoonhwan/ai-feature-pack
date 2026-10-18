"""M7 FT 게이트 시험 공용 — 격리 임시 git 저장소 헬퍼 (실 저장소·tmux·seats.json 접촉 0)."""

import os
import shutil
import subprocess
from pathlib import Path

BIN = Path(__file__).resolve().parents[3] / "harness" / "bin"
REAL_GIT: str = shutil.which("git") or "git"
_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


def git(repo: Path, *args: str) -> str:
    return subprocess.run([REAL_GIT, "-C", str(repo), *args], check=True, capture_output=True, text=True, env={**os.environ, **_ENV}).stdout


def commit(repo: Path, files: dict[str, str], msg: str, date: str | None = None) -> str:
    for rel, body in files.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
    git(repo, "add", "-A")
    if date is None:
        git(repo, "commit", "-q", "-m", msg)
    else:  # 커밋 시각(committer date)을 과거로 고정 — reflog «이벤트 시각» 과 «커밋 시각» 을 가르는 시험용
        subprocess.run([REAL_GIT, "-C", str(repo), "commit", "-q", "-m", msg], check=True, capture_output=True, text=True,
                       env={**os.environ, **_ENV, "GIT_COMMITTER_DATE": date, "GIT_AUTHOR_DATE": date})
    return git(repo, "rev-parse", "HEAD").strip()


def init_repo(path: Path, branch: str = "feat") -> Path:
    path.mkdir(parents=True, exist_ok=True)
    git(path, "init", "-q", "-b", branch)
    commit(path, {"base.txt": "base"}, "base")
    return path


def copy_py_helpers(dest: Path) -> None:
    """ft-nano-spawn.sh 가 같은 폴더에서 부르는 순수 판정 도우미(ft_*.py: ft_raised · ft_teamset · ft_spawn_queue …) 전부 복사 — 새 도우미가 생겨도 따라간다(R345)."""
    for helper in BIN.glob("ft_*.py"):
        shutil.copy(helper, dest / helper.name)
    shutil.copy(BIN / "ft-team-lib.sh", dest / "ft-team-lib.sh")  # R383: ft-nano-spawn.sh 가 같은 폴더의 팀 폴더 해석 lib 를 source 한다(없으면 REJECT)


def run_script(name: str, *args: str, cwd: Path | None = None, extra_env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    env = {**os.environ, **(extra_env or {})}
    return subprocess.run(["bash", str(BIN / name), *args], capture_output=True, text=True, cwd=cwd, env=env)
