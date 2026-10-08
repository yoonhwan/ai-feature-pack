"""설계 §9 시험 8 — playwright 로 PDF 생성 → pdftotext 에 제목 포함 · 한 장. 이 Mac 실측용: playwright 가 없으면 «실패» (건너뛰기 0).

PDF 생성은 예약 실행과 같은 인터프리터(MAGAZINE_PY, 기본 /opt/homebrew/bin/python3)를 자식 프로세스로 쓴다 — 시험 러너 venv 에 playwright 가 없어도 실제 경로를 잰다.
실행: python3 -m pytest tests/scripts/test_magazine_pdf.py -q
"""
import os
import subprocess
from pathlib import Path

from _magazine_fakes import KIT, fake_model

import magazine_render as mr

PY = os.environ.get("MAGAZINE_PY", "/opt/homebrew/bin/python3")
CHILD = "import sys; sys.path.insert(0, sys.argv[1]); from pathlib import Path; import magazine_pdf; magazine_pdf.html_to_pdf(Path(sys.argv[2]), Path(sys.argv[3]))"


def make_pdf(tmp_path: Path, model: dict) -> Path:
    _, html = mr.render(model, ["한 줄", "두 줄", "세 줄"], "t")
    src, out = tmp_path / "m.html", tmp_path / "m.pdf"
    src.write_text(html, encoding="utf-8")
    r = subprocess.run([PY, "-c", CHILD, str(KIT), str(src), str(out)], capture_output=True, text=True, timeout=120)
    assert r.returncode == 0, r.stderr[-800:]
    return out


def text_of(pdf: Path) -> str:
    return subprocess.run(["pdftotext", "-layout", str(pdf), "-"], capture_output=True, text=True, check=True).stdout


def test_pdf_has_korean_title_and_sections(tmp_path: Path):
    pdf = make_pdf(tmp_path, fake_model())
    assert pdf.read_bytes().startswith(b"%PDF")
    out = text_of(pdf)
    assert "아침 매거진 — 2026-10-08" in out and "각주표" in out and "슬랙 미러 요약" in out


def test_long_content_stays_one_page(tmp_path: Path):
    m = fake_model()
    m["seats"] = {"succession": [[f"byz-v65-n{i}#0", f"byz-v65-n{i}#1"] for i in range(47)], "new": [f"byz-harness-n{i}#0" for i in range(77)]}
    m["merges"] = [{"sha": "0" * 40, "at": "t", "title": f"[feature] 긴 변경 {i} (#{1000 + i})", "pr": 1000 + i, "tag": "[feature]"} for i in range(60)]
    pdf = make_pdf(tmp_path, m)
    info = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, check=True).stdout
    assert "Pages:           1" in info


def test_over_limit_raises_instead_of_truncating(tmp_path: Path):
    m = fake_model()
    m["merges"] = [{"sha": "0" * 40, "at": "t", "title": f"[feature] 아주 긴 변경 {i} " + "가" * 60, "pr": 2000 + i, "tag": "[feature]"} for i in range(900)]
    _, html = mr.render(m, ["a", "b", "c"], "t")
    src = tmp_path / "m.html"
    src.write_text(html, encoding="utf-8")
    r = subprocess.run([PY, "-c", CHILD, str(KIT), str(src), str(tmp_path / "m.pdf")], capture_output=True, text=True, timeout=120)
    assert r.returncode != 0 and "한 장 한도" in r.stderr
