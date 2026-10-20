"""file_guard — 첨부 내용 형식은 «확장자 표» 가 정한다 (r620). 인터프리터 판에 따라 .md 가 바뀌지 않는다.

`mimetypes.guess_type` 는 판마다 표가 다르다(python 3.11 = `.md` 모름 · 3.14 = text/markdown).
자주 쓰는 확장자는 표로 고정하고, 표에 없는 확장자만 추측에 맡긴다(magazine_attach 와 같은 꼴).
슬랙 호출 0 · 로컬 파일만.

실행: python3.11 -m pytest tests/scripts/test_file_guard_content_type.py -q
"""
import mimetypes

import pytest
from _thread_fakes import CARD  # noqa: F401 — sys.path 에 키트 경로를 넣는다

import file_guard as fg

TABLE = {
    ".md": "text/markdown",
    ".html": "text/html",
    ".pdf": "application/pdf",
    ".txt": "text/plain",
    ".json": "application/json",
}


@pytest.mark.parametrize("suffix,expected", sorted(TABLE.items()))
def test_known_suffixes_use_the_explicit_table(tmp_path, suffix, expected):
    p = tmp_path / f"a{suffix}"
    p.write_bytes(b"%PDF-x" if suffix == ".pdf" else "정상 본문\n".encode())
    got = fg.check_files([str(p)], "C1")
    assert [c.content_type for c in got] == [expected]


def test_content_type_is_table_value_not_guess_type(tmp_path, monkeypatch):
    """추측 함수가 무엇을 돌려주든 표 확장자는 표 값 — 판 차이를 코드에서 끊는다."""
    monkeypatch.setattr(fg.mimetypes, "guess_type", lambda name: (None, None))
    p = tmp_path / "a.md"
    p.write_text("정상 본문\n", encoding="utf-8")
    assert fg.check_files([str(p)], "C1")[0].content_type == "text/markdown"


def test_unknown_suffix_still_falls_back_to_guess_type(tmp_path, monkeypatch):
    monkeypatch.setattr(fg.mimetypes, "guess_type", lambda name: ("text/x-zzz", None))
    p = tmp_path / "a.zzz"
    p.write_bytes(b"x")
    assert fg.check_files([str(p)], "C1")[0].content_type == "text/x-zzz"


def test_unknown_suffix_without_guess_is_octet_stream(tmp_path):
    p = tmp_path / "a.zzz"
    p.write_bytes(b"x")
    expected = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
    assert fg.check_files([str(p)], "C1")[0].content_type == expected
