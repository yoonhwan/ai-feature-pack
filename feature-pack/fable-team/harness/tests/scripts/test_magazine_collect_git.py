"""아침 매거진 ① git 수집 시험 — 설계 §9-3 (임시 리포 + 가짜 origin · 네트워크 0)."""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

KIT = Path(__file__).resolve().parents[2] / "scripts" / "harness-install" / "slack-mirror"
sys.path.insert(0, str(KIT))
import magazine_collect_git as mg  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START = datetime(2026, 10, 7, 8, tzinfo=KST)
END = datetime(2026, 10, 8, 8, tzinfo=KST)


def git(cwd: Path, *args: str, when: str | None = None) -> str:
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    if when:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = when
    r = subprocess.run(["git", *args], cwd=cwd, env=env, capture_output=True, text=True, check=True)
    return r.stdout.strip()


def commit(cwd: Path, msg: str, when: str, files: dict[str, str] | None = None) -> str:
    for name, body in (files or {"f.txt": msg}).items():
        p = cwd / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body, encoding="utf-8")
    git(cwd, "add", "-A")
    git(cwd, "commit", "-q", "-m", msg, when=when)
    return git(cwd, "rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path: Path):
    """origin(bare) + clone. clone 의 origin/main 에 시간대별 커밋이 있다."""
    origin = tmp_path / "origin.git"
    work = tmp_path / "work"
    git(tmp_path, "init", "-q", "--bare", "-b", "main", str(origin))
    git(tmp_path, "clone", "-q", str(origin), str(work))
    git(work, "checkout", "-q", "-b", "main")
    shas = {
        "before": commit(work, "[chore] 창 전 (#1)", "2026-10-07T07:00:00+0900"),
        "a": commit(work, "[feature] 첫째 (#10)", "2026-10-07T09:00:00+0900"),
        "b": commit(work, "번호 없는 제목", "2026-10-07T12:00:00+0900", {"design/x/BRIEFING-1007.md": "b", "other.md": "o"}),
        "c": commit(work, "[docs] 마감 (#12)", "2026-10-08T07:00:00+0900", {"design/y/CLOSEOUT-kk-1007.md": "c"}),
        "after": commit(work, "[fix] 창 후 (#99)", "2026-10-08T09:00:00+0900"),
    }
    git(work, "push", "-q", "origin", "main")
    return work, shas


def test_merges_first_parent_in_window_parsed(repo):
    work, shas = repo
    out = mg.collect_git(work, "Org/repo", START, END)
    titles = [m["title"] for m in out["merges"]]
    assert titles == ["[docs] 마감 (#12)", "번호 없는 제목", "[feature] 첫째 (#10)"]  # 최신순
    first = out["merges"][2]
    assert first["pr"] == 10 and first["tag"] == "[feature]" and first["sha"] == shas["a"]
    assert first["at"].startswith("2026-10-07T09:00:00")
    assert out["merges"][1]["pr"] is None and out["merges"][1]["tag"] is None


def test_main_range_is_oldest_and_newest_in_window(repo):
    work, shas = repo
    out = mg.collect_git(work, "Org/repo", START, END)
    assert out["main"] == {"from_sha": shas["a"], "to_sha": shas["c"]}


def test_empty_window_has_none_range(repo):
    work, _ = repo
    quiet = datetime(2026, 9, 1, 8, tzinfo=KST)
    out = mg.collect_git(work, "Org/repo", quiet, datetime(2026, 9, 2, 8, tzinfo=KST))
    assert out["merges"] == [] and out["main"] == {"from_sha": None, "to_sha": None}


def test_docs_only_added_briefing_closeout_with_blob_url(repo):
    work, _ = repo
    docs = mg.collect_git(work, "Org/repo", START, END)["docs"]
    paths = sorted(d["path"] for d in docs)
    assert paths == ["design/x/BRIEFING-1007.md", "design/y/CLOSEOUT-kk-1007.md"]
    assert {d["url"] for d in docs} == {
        "https://github.com/Org/repo/blob/main/design/x/BRIEFING-1007.md",
        "https://github.com/Org/repo/blob/main/design/y/CLOSEOUT-kk-1007.md",
    }


def test_modified_briefing_is_not_listed(repo):
    work, _ = repo
    commit(work, "[docs] 수정만", "2026-10-07T13:00:00+0900", {"design/x/BRIEFING-1007.md": "수정"})
    git(work, "push", "-q", "origin", "main")
    docs = mg.collect_git(work, "Org/repo", START, END)["docs"]
    assert [d["path"] for d in docs].count("design/x/BRIEFING-1007.md") == 1


def test_fetch_failure_raises(tmp_path):
    work = tmp_path / "w"
    git(tmp_path, "init", "-q", "-b", "main", str(work))
    git(work, "remote", "add", "origin", str(tmp_path / "없는-origin.git"))
    with pytest.raises(MagazineError, match="fetch"):
        mg.collect_git(work, "Org/repo", START, END)


def test_log_failure_raises(tmp_path):
    origin = tmp_path / "o.git"
    work = tmp_path / "w"
    git(tmp_path, "init", "-q", "--bare", "-b", "other", str(origin))  # main 브랜치 없음 → fetch rc≠0
    git(tmp_path, "clone", "-q", str(origin), str(work))
    with pytest.raises(MagazineError):
        mg.collect_git(work, "Org/repo", START, END)
