"""magazine_collect — 아침 매거진 자료 6종 → «구조 모델» dict (설계 §8 칸 이름 그대로 · 뒤 덩이와의 계약).

실패는 전부 MagazineError(raise) — 자료 하나라도 못 모으면 반쪽 결과를 돌려주지 않는다(BYZ #0 RULE).
창 닫힘 검사는 호출자(window) 몫 — 여기서는 D 의 경계만 쓴다.
"""
from pathlib import Path

from magazine_collect_gh import collect_gh
from magazine_collect_git import collect_git
from magazine_collect_mbox import collect_mbox
from magazine_window import MagazineError, bounds

__all__ = ["MagazineError", "collect"]


def collect(date: str, *, repo: Path, gh_repo: str, mailbox: Path) -> dict[str, object]:
    start, end = bounds(date)
    git = collect_git(Path(repo), gh_repo, start, end)
    gh = collect_gh(gh_repo, start, end)
    mbox = collect_mbox(Path(mailbox), start, end)
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
    }
