"""r2380 공용 세계 — 사람 대기 시험 두 파일(반 갈래)이 같이 쓰는 임시 리포·가짜 좌석·mbox 도우미.

임시 리포(bare origin + 체크아웃) · 가짜 명부·tmux·mbox · lint — 네트워크 0 · 실 루트 0 · 실 좌석 깨우기 0.
R2380_BIN = 시험할 bin 폴더(기본 kit) · R2380_BASE_BIN = 기준판 bin(⑲ 대조 · 없으면 기대 문장만).
"""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from _stall_world import NOW, World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R2380_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
BASE_BIN = os.environ.get("R2380_BASE_BIN")
GIT = shutil.which("git") or "git"
GENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "LC_ALL": "C"}
TS = "1795016460.792199"
HUMAN = f"# h\n- 선행: 오빠 승인 대기 (master#66 #340166 · thread {TS})\n"
PLAIN = "# h\n- 선행: 없음\n"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def git(cwd: Path, *args: str, at: float | None = None) -> str:
    env = dict(GENV)
    if at is not None:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = f"@{int(at)} +0000"
    r = subprocess.run([GIT, *args], cwd=cwd, env=env, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, (args, r.stderr)
    return r.stdout.strip()


def make_repo(w: World, label: str, files: dict[str, str], ages: dict[str, float] | None = None) -> Path:
    """그 팀 카드 체크아웃 = 리포 · 파일마다 커밋 1개(시각 = NOW − ages[상대경로]시간) → origin/main push.
    나이 시험은 카드 «마지막 커밋 시각» 을 쓰므로 파일마다 따로 커밋한다(한 커밋에 묶으면 나이가 같아진다)."""
    wt = w.root / f".worktrees/wt-{label}"
    origin = w.root / f"origin-{label}.git"
    git(w.root, "init", "-q", "--bare", "-b", "main", str(origin))
    git(wt, "init", "-q", "-b", "main")
    git(wt, "remote", "add", "origin", str(origin))
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c0", at=NOW - 400 * 3600)
    for rel, text in files.items():
        p = wt / f"design/{label}/indices" / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        _ = p.write_text(text, encoding="utf-8")
        git(wt, "add", "-A")
        git(wt, "commit", "-q", "-m", f"put {rel}", at=NOW - float((ages or {}).get(rel, 0.0)) * 3600)
    git(wt, "push", "-q", "origin", "main")
    return wt


def put(w: World, label: str, rel: str, text: str, hours_ago: float = 0.0) -> None:
    """카드 1장 다시 쓰고 커밋·push — 나이 = hours_ago 시간."""
    wt = w.root / f".worktrees/wt-{label}"
    p = wt / f"design/{label}/indices" / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    _ = p.write_text(text, encoding="utf-8")
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "-m", f"put {rel}", at=NOW - hours_ago * 3600)
    git(wt, "push", "-q", "origin", "main")


def desk(w: World, seat: str = "t1-desk#9") -> None:
    """그 팀 명부에 `_desk` 를 단다(풀림 1통 받을이)."""
    p = w.root / ".fable-team/seats-t1.json"
    doc = json.loads(p.read_text(encoding="utf-8"))
    doc["_desk"] = seat
    _ = p.write_text(json.dumps(doc), encoding="utf-8")


def shim_git(w: World, body: str) -> None:
    """PATH 앞 shim 의 git 을 갈아 끼운다 — «ls-tree» 나 «log» 한 갈래만 실패시키는 데 쓴다."""
    p = w.stub / "shim" / "git"
    _ = p.write_text(f'#!/bin/sh\n{body}\nexec {GIT} "$@"\n')
    p.chmod(0o755)


def scan(w: World, bin_dir: Path | str | None = None, dry: bool = False) -> subprocess.CompletedProcess[str]:
    w.state("t1-master#1", "IDLE", 5)
    args = [str(Path(bin_dir or BIN) / "ft-stall-scan.sh")] + (["--dry-run"] if dry else [])
    return subprocess.run(["bash", *args], env=w.env, capture_output=True, text=True, timeout=90)


def human(w: World, kind: str) -> list[str]:
    return [ln for ln in w.mbox_log() if kind in ln]


