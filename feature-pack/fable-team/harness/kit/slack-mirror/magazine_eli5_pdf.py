"""쉬운 판 HTML → PDF (판정 609 설계 1) — 슬랙은 HTML 을 소스 글자(text/plain)로 보여 주므로 PDF 를 붙인다.

HTML 은 out 폴더에 그대로 남긴다(업로드만 안 함). 변환 실패 = 쉬운 판 실패와 같은 경로(원인 첫 줄 → 경고 줄 + ERROR, 풀 디테일 PDF 는 계속).
"""
import logging
from collections.abc import Callable
from pathlib import Path

LOG = logging.getLogger("byz_morning_magazine")


def write_eli5(html: str | None, cause: str | None, out: Path, stem: str, date: str, convert: Callable[..., int]) -> tuple[Path | None, Path | None, str | None]:
    """(HTML 경로, PDF 경로, 실패 원인). 쉬운 판이 없으면 (None, None, cause) · PDF 변환이 실패하면 (HTML 경로, None, 원인 첫 줄)."""
    if html is None:
        return None, None, cause
    html_path, pdf_path = out / f"{stem}-eli5.html", out / f"{stem}-eli5.pdf"
    html_path.write_text(html, encoding="utf-8")
    try:
        convert(html_path, pdf_path, f"아침 매거진 {date} 쉬운 판")
    except RuntimeError as e:  # PdfError
        LOG.error("쉬운 판 PDF 변환 실패: %s: %s", type(e).__name__, e)
        return html_path, None, (str(e).splitlines() or [""])[0] or type(e).__name__
    return html_path, pdf_path, None
