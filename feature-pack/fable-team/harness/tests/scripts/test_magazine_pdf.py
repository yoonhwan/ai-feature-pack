"""설계 §9 시험 4 — playwright 로 «여러 쪽» A4 PDF 생성 → pdftotext/pdfinfo 로 확인. 이 Mac 실측용: playwright 가 없으면 «실패» (건너뛰기 0).

한 장 높이 한도(18000px raise)는 정책 변경으로 없앴다 — 긴 문서는 잘리지 않고 쪽이 늘어난다.
PDF 생성은 예약 실행과 같은 인터프리터(MAGAZINE_PY, 기본 /opt/homebrew/bin/python3)를 자식 프로세스로 쓴다 — 시험 러너 venv 에 playwright 가 없어도 실제 경로를 잰다.
실행: python3 -m pytest tests/scripts/test_magazine_pdf.py -q
"""
import os
import subprocess
from pathlib import Path

import pytest
from _magazine_detail_fixture import fake_full_model
from _magazine_fakes import KIT, fake_model

import magazine_pdf as mp
import magazine_render as mr
import magazine_render_full as mrf

PY = os.environ.get("MAGAZINE_PY", "/opt/homebrew/bin/python3")
CHILD = ("import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path; import magazine_pdf; "
         "print(magazine_pdf.html_to_pdf(Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4], int(sys.argv[5])))")


def make_pdf(tmp_path: Path, html: str, footer: str = "아침 매거진 2026-10-08", timeout_ms: int = 120000) -> tuple[Path, subprocess.CompletedProcess]:
    src, out = tmp_path / "m.html", tmp_path / "m.pdf"
    src.write_text(html, encoding="utf-8")
    r = subprocess.run([PY, "-c", CHILD, str(KIT), str(src), str(out), footer, str(timeout_ms)], capture_output=True, text=True, timeout=180)
    return out, r


def text_of(pdf: Path) -> str:
    return subprocess.run(["pdftotext", "-layout", str(pdf), "-"], capture_output=True, text=True, check=True).stdout


def pages_of(pdf: Path) -> int:
    info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, check=True).stdout
    return int(next(line for line in info.splitlines() if line.startswith("Pages:")).split()[1])


def test_summary_part_only_renders_with_korean_title_and_footer(tmp_path: Path):
    _, html = mr.render(fake_model(), ["한 줄", "두 줄", "세 줄"], "t")
    pdf, r = make_pdf(tmp_path, html)
    assert r.returncode == 0, r.stderr[-800:]
    out = text_of(pdf)
    assert pdf.read_bytes().startswith(b"%PDF") and "아침 매거진 — 2026-10-08" in out and "각주표" in out and "슬랙 미러 요약" in out
    assert "아침 매거진 2026-10-08 · 1/" in out  # 바닥글 «라벨 · 쪽/전체»


def test_long_full_detail_document_spans_many_pages_without_truncation(tmp_path: Path):
    _, html = mrf.render_full(fake_full_model(), ["한 줄", "두 줄", "세 줄"], "t")  # R74 상한 뒤엔 렌더 결과가 짧다 — 변환기만 보려고 각주표 앞에 400줄을 붙인다
    html = html.replace('<h2 id="footnotes"', "".join(f'<p class="ln">전문 {i} 줄</p>' for i in range(400)) + '<h2 id="footnotes"')
    pdf, r = make_pdf(tmp_path, html)
    assert r.returncode == 0, r.stderr[-800:]
    n = pages_of(pdf)
    out = text_of(pdf)
    print(f"[여러 쪽] returned pages={r.stdout.strip()} · pdfinfo Pages={n}")
    assert n >= 2 and int(r.stdout.strip()) == n  # html_to_pdf 가 센 쪽 수 == pdfinfo
    assert "전문 399 줄" in out and "각주표" in out and f"{n}/{n}" in out  # 400줄 끝까지 + 마지막 쪽 바닥글
    assert out.rindex("각주표") > out.rindex("D7 좌석")  # 각주표는 문서 맨 끝


def test_timeout_raises_pdf_error_not_a_hang(tmp_path: Path):
    _, html = mr.render(fake_model(), ["a", "b", "c"], "t")
    _, r = make_pdf(tmp_path, html, timeout_ms=1)
    assert r.returncode != 0 and "PdfError" in r.stderr


def test_count_pages_counts_page_objects_not_the_pages_tree(tmp_path: Path):
    f = tmp_path / "x.pdf"
    f.write_bytes(b"%PDF /Type /Pages /Kids [] /Type /Page /Type/Page /Type /Pages")
    assert mp.count_pages(f) == 2
    f.write_bytes(b"%PDF /Type /Pages only")
    with pytest.raises(mp.PdfError, match="쪽 수 0"):
        mp.count_pages(f)
