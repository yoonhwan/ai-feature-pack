"""magazine_collect_git — origin/main 머지·BRIEFING/CLOSEOUT 추가 문서 (설계 §1 자료 #1·#5).

루트 체크아웃은 옛 브랜치일 수 있어 작업 트리를 읽지 않고 `git fetch origin main` + `git log origin/main` 만 쓴다.
git 실패는 전부 MagazineError (BYZ #0 RULE — 반쪽 결과 0).
"""
import re
import subprocess
from datetime import datetime
from pathlib import Path

from magazine_window import MagazineError

PR_RE = re.compile(r"\(#(\d+)\)\s*$")
TAG_RE = re.compile(r"^(\[[^\]]+\])")
DOC_PREFIXES = ("BRIEFING-", "CLOSEOUT-")
GIT_TIMEOUT = 120


def _git(repo: Path, *args: str) -> str:
    try:
        r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=GIT_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise MagazineError(f"git {args[0]} 실행 실패: {type(e).__name__}") from e
    if r.returncode != 0:
        raise MagazineError(f"git {args[0]} rc={r.returncode}: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else ''}")
    return r.stdout


def _merge(line: str) -> dict[str, object]:
    sha, at, title = line.split("\t", 2)
    pr, tag = PR_RE.search(title), TAG_RE.match(title)
    return {"sha": sha, "at": at, "title": title, "pr": int(pr.group(1)) if pr else None, "tag": tag.group(1) if tag else None}


def collect_git(repo: Path, gh_repo: str, start: datetime, end: datetime) -> dict[str, object]:
    _ = _git(repo, "fetch", "origin", "main")
    span = [f"--since={start.isoformat()}", f"--until={end.isoformat()}"]
    out = _git(repo, "log", "origin/main", "--first-parent", *span, "--format=%H%x09%cI%x09%s")
    merges = [_merge(ln) for ln in out.splitlines() if ln.strip()]
    added = _git(repo, "log", "origin/main", *span, "--diff-filter=A", "--name-only", "--format=")
    paths = list(dict.fromkeys(p for p in added.splitlines() if p.rsplit("/", 1)[-1].startswith(DOC_PREFIXES)))
    return {
        "main": {"from_sha": merges[-1]["sha"] if merges else None, "to_sha": merges[0]["sha"] if merges else None},
        "merges": merges,
        "docs": [{"path": p, "url": f"https://github.com/{gh_repo}/blob/main/{p}"} for p in paths],
    }
