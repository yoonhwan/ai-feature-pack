"""magazine_render_cap — 풀 디테일 2부 크기 상한 (판정 812 A안 · 821 r1): 한 건 = 제목 + 본문 3줄 + 원문 위치 1줄 · 한 절 20건 · 파일 경고선.

넘친 것은 소리 없이 버리지 않는다 — 한 건마다 「… 원문: <위치>」, 절 끝에 「외 N건 — 원문: <위치 목록>」 을 남긴다(#0 RULE).
파일 경고선(md 줄·KB · PDF 쪽)은 건수 상한이 먼저 걸리는 평소엔 발동하지 않는 «마지막 경보선» — 넘으면 raise 한다.
상수는 호출 시점에 읽는다(시험에서 낮춰 쓴다).
"""
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import TypeVar

from magazine_emit import Block

ITEM_LINES = 3
SECTION_ITEMS = 20
MD_MAX_LINES = 1500
MD_MAX_BYTES = 120 * 1024
PDF_MAX_PAGES = 40
T = TypeVar("T")


class MagazineSizeError(RuntimeError):
    """매거진 파일이 상한을 넘었다 — 발행하지 않고 실패 알림 경로를 탄다."""


def cap_item(title: str, candidates: Sequence[str], where: str) -> tuple[list[Block], str]:
    """한 건 = 제목 1줄 + 본문(후보 줄 중 비어 있지 않은 앞 ITEM_LINES 줄) + 「… 원문: <위치>」 1줄(본문이 다 들어가도 항상). → (블록들, 위치)."""
    body = [x for c in candidates for x in str(c).split("\n") if x.strip()][:ITEM_LINES]
    return [("h3", title), ("lines", "\n".join([*body, f"… 원문: {where}"]))], where


def overflow_line(rest_where: Sequence[str]) -> Block:
    return ("p", f"외 {len(rest_where)}건 — 원문: {', '.join(dict.fromkeys(rest_where))}")


def cap_section(items: Sequence[tuple[list[Block], str]]) -> list[Block]:
    """(블록들, 원문 위치) 목록 → 앞 SECTION_ITEMS 건의 블록 + 넘친 건수·위치 한 줄."""
    out = [b for blocks, _ in items[:SECTION_ITEMS] for b in blocks]
    rest = items[SECTION_ITEMS:]
    return out + [overflow_line([w for _, w in rest])] if rest else out


def cap_list(entries: Sequence[T], where: Callable[[T], str]) -> tuple[list[T], list[Block]]:
    """한 줄짜리 항목 목록 → (앞 SECTION_ITEMS 개, 넘침 줄 0~1개)."""
    rest = entries[SECTION_ITEMS:]
    return list(entries[:SECTION_ITEMS]), [overflow_line([where(e) for e in rest])] if rest else []


def check_md(md: str) -> None:
    lines, size = md.count("\n"), len(md.encode("utf-8"))
    if lines > MD_MAX_LINES or size > MD_MAX_BYTES:
        raise MagazineSizeError(f"md 크기 초과 — {lines}줄·{size}바이트 (상한 {MD_MAX_LINES}줄·{MD_MAX_BYTES}바이트)")


def checked_pdf(md: str, html_path: Path, pdf_path: Path, label: str, convert: Callable[[Path, Path, str], int]) -> int:
    """md 상한 → PDF 변환 → 쪽수 상한. 넘으면 MagazineSizeError(쪽수 값 포함)."""
    check_md(md)
    pages = convert(html_path, pdf_path, label)
    if pages > PDF_MAX_PAGES:
        raise MagazineSizeError(f"풀 디테일 PDF 쪽수 초과 — {pages}쪽 (상한 {PDF_MAX_PAGES}쪽)")
    return pages
