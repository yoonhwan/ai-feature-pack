"""magazine_git — md 를 ops/magazine 전용 워크트리에 커밋·push (설계 §6 push 계약 · 오빠 판정 348).

★force 0 · ops/magazine 외 push 0 · main 체크아웃 0★. 워크트리 없음·다른 브랜치·미커밋·push 거부는 전부 raise —
슬랙 게시 «전»에 불리므로 링크가 깨진 글은 나가지 않는다.
"""
import subprocess
from pathlib import Path

BRANCH = "ops/magazine"
REL_DIR = "design/harness/magazine"


class GitError(RuntimeError):
    pass


def _git(wt: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(wt), *args], capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        tail = ((r.stderr or r.stdout).strip().splitlines() or ["출력 없음"])[-1]
        raise GitError(f"git {args[0]} 실패(rc={r.returncode}): {tail}")
    return r.stdout.strip()


def check_worktree(wt: Path) -> None:
    if not (wt / ".git").exists():
        raise GitError(f"매거진 워크트리 없음: {wt} (install-magazine.sh 가 만든다)")
    branch = _git(wt, "rev-parse", "--abbrev-ref", "HEAD")
    if branch != BRANCH:
        raise GitError(f"워크트리 브랜치가 {BRANCH} 가 아님: {branch}")
    if _git(wt, "status", "--porcelain"):
        raise GitError(f"워크트리에 미커밋 파일이 있음: {wt}")


def publish_md(wt: Path, md_text: str, filename: str, date: str) -> str:
    """md 1개를 커밋하고 ops/magazine 만 push. 반환 = 커밋 sha. 같은 내용이 이미 커밋돼 있으면 HEAD sha 를 그대로 쓴다."""
    check_worktree(wt)
    target = wt / REL_DIR / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(md_text, encoding="utf-8")
    rel = f"{REL_DIR}/{filename}"
    _git(wt, "add", "--", rel)
    if _git(wt, "status", "--porcelain", "--", rel):
        _git(wt, "commit", "-m", f"[docs] 아침 매거진 {date} (자동)", "--", rel)
    _git(wt, "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    return _git(wt, "rev-parse", "HEAD")


def blob_url(repo: str, sha: str, filename: str) -> str:
    return f"https://github.com/{repo}/blob/{sha}/{REL_DIR}/{filename}"
