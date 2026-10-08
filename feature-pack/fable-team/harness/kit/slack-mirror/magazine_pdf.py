"""magazine_pdf — html → 여러 쪽 A4 PDF (playwright chromium · 설계 §4). 별도 브라우저 프로세스라 공유 Chrome :9333 과 무관.

쪽 수 상한 없음(한 장 높이 한도 경로는 없앴다) · 바닥글 「<라벨> · 쪽/전체」 · 120초 안에 못 끝나면 PdfError · 쪽 수는 결과 바이트에서 센다.
"""
import html
import re
from pathlib import Path

INSTALL_HINT = "pip install playwright && playwright install chromium (/opt/homebrew/bin/python3)"
TIMEOUT_MS = 120000
PAGE_OBJ = re.compile(rb"/Type\s*/Page(?![s\w])")


class PdfError(RuntimeError):
    pass


def count_pages(pdf_path: Path) -> int:
    n = len(PAGE_OBJ.findall(pdf_path.read_bytes()))
    if n == 0:
        raise PdfError(f"PDF 쪽 수 0: {pdf_path}")
    return n


def _footer(label: str) -> str:
    return (f'<div style="font-size:8px;width:100%;text-align:center;color:#666">{html.escape(label)} · '
            '<span class="pageNumber"></span>/<span class="totalPages"></span></div>')


def html_to_pdf(html_path: Path, pdf_path: Path, footer: str = "아침 매거진", timeout_ms: int = TIMEOUT_MS) -> int:
    """PDF 를 쓰고 쪽 수를 돌려준다."""
    try:
        from playwright.sync_api import Error as PlaywrightError
        from playwright.sync_api import sync_playwright
    except ImportError as e:
        raise PdfError(f"playwright 없음 — {INSTALL_HINT}") from e
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            try:
                page = browser.new_page()
                page.set_default_timeout(timeout_ms)
                page.goto(html_path.resolve().as_uri(), timeout=timeout_ms)
                page.pdf(path=str(pdf_path), format="A4", margin={"top": "14mm", "bottom": "14mm", "left": "12mm", "right": "12mm"},
                         print_background=True, display_header_footer=True, header_template="<span></span>", footer_template=_footer(footer))
            finally:
                browser.close()
    except PlaywrightError as e:
        raise PdfError(f"PDF 생성 실패: {str(e).splitlines()[0] if str(e) else type(e).__name__}") from e
    if not pdf_path.is_file() or pdf_path.stat().st_size == 0:
        raise PdfError(f"PDF 가 비어 있음: {pdf_path}")
    return count_pages(pdf_path)
