"""magazine_collect — 아침 매거진 자료 6종 → «구조 모델» dict (설계 §8 칸 이름 그대로 · 뒤 덩이와의 계약).

실패는 전부 MagazineError(raise) — 자료 하나라도 못 모으면 반쪽 결과를 돌려주지 않는다(BYZ #0 RULE).
창 닫힘 검사는 호출자(window) 몫 — 여기서는 D 의 경계만 쓴다.
`detail` 칸(풀 디테일 · DESIGN-magazine-full-detail §3)은 기존 11칸 위에 더해지는 한 칸이다.
"""
import os
from datetime import datetime
from pathlib import Path

from magazine_collect_decisions import collect_decisions
from magazine_collect_detail import DEFAULT_REFS, collect_detail
from magazine_collect_gh import collect_gh, last_comments
from magazine_collect_git import collect_git
from magazine_collect_mbox import collect_mbox
from magazine_collect_open import collect_open
from magazine_window import MagazineError, bounds

__all__ = ["MagazineError", "collect"]


def _ref_names(refs: list[str] | None) -> list[str]:
    if refs is None:
        env = os.environ.get("MAGAZINE_REFS", "")
        refs = [r.strip() for r in env.split(",") if r.strip()] or list(DEFAULT_REFS)
    return refs


def _detail(repo: Path, refs: list[str], byz_root: Path, mailbox: Path, gh_repo: str, closed: list[int], merges: list[str], start: datetime, end: datetime) -> dict[str, object]:
    d = collect_detail(repo, refs, start, end, merges)
    return {
        "refs": d["refs"],
        "units": d["units"],
        "verdict_sections": d["verdict_sections"],
        "decisions": collect_decisions(mailbox, start, end),
        "merge_bodies": d["merge_bodies"],
        "issue_evidence": last_comments(gh_repo, closed),
        "open": collect_open(repo, d["refs"], byz_root, start, end),
        "seats_closed": d["seats_closed"],
        "appendix": d["appendix"],
    }


def collect(date: str, *, repo: Path, gh_repo: str, mailbox: Path, refs: list[str] | None = None, byz_root: Path | None = None) -> dict[str, object]:
    """refs 기본 = $MAGAZINE_REFS(쉼표) 또는 DEFAULT_REFS · byz_root 기본 = repo (state/*/BREACH.md 를 찾는 루트)."""
    start, end = bounds(date)
    git = collect_git(Path(repo), gh_repo, start, end)
    gh = collect_gh(gh_repo, start, end)
    mbox = collect_mbox(Path(mailbox), start, end)
    closed = [int(str(i["number"])) for i in gh["issues_closed"]]
    detail = _detail(Path(repo), _ref_names(refs), Path(byz_root or repo), Path(mailbox), gh_repo, closed, [str(x["sha"]) for x in git["merges"]], start, end)
    return {
        "date": date,
        "start": start.isoformat(),
        "end": end.isoformat(),
        "main": git["main"],
        "merges": git["merges"],
        "issues_opened": gh["issues_opened"],
        "issues_closed": gh["issues_closed"],
        "verdicts": mbox["verdicts"],
        "mbox": mbox["mbox"],
        "docs": git["docs"],
        "seats": mbox["seats"],
        "detail": detail,
    }
