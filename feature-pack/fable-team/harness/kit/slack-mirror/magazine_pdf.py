"""magazine_pdf — html → PDF (playwright chromium · 설계 §4). 별도 브라우저 프로세스라 공유 Chrome :9333 과 무관."""
from pathlib import Path

MAX_HEIGHT_PX = 18000  # Chrome 용지 한도(200in≈19200px)보다 낮게 — 넘으면 조용히 잘리지 않고 raise
INSTALL_HINT = "pip install playwright && playwright install chromium (/opt/homebrew/bin/python3)"


class PdfError(RuntimeError):
    pass


def html_to_pdf(html_path: Path, pdf_path: Path, timeout_ms: int = 30000) -> None:
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
                page.goto(html_path.resolve().as_uri(), timeout=timeout_ms)
                # 길어도 PDF 는 «한 장» — 폭은 A4, 높이는 본문 높이에 맞춘 한 페이지(판정 348 렌더 메모 ③)
                height = page.evaluate("Math.ceil(document.documentElement.getBoundingClientRect().height)") + 24
                if height > MAX_HEIGHT_PX:
                    raise PdfError(f"본문이 한 장 한도를 넘었어요: {height}px > {MAX_HEIGHT_PX}px")
                page.pdf(path=str(pdf_path), width="210mm", height=f"{height}px", print_background=True, page_ranges="1")
            finally:
                browser.close()
    except PlaywrightError as e:
        raise PdfError(f"PDF 생성 실패: {str(e).splitlines()[0] if str(e) else type(e).__name__}") from e
    if not pdf_path.is_file() or pdf_path.stat().st_size == 0:
        raise PdfError(f"PDF 가 비어 있음: {pdf_path}")
