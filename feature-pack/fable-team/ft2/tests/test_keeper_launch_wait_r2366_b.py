"""r2366 keeper 가 미룬 열기 ≠ owner-orphan — 반례 ⑤~⑧(동결) + 변이 M2·M4·M5.
⑤ 열기 중(opening) · ⑥ launch-failed 끝 · ⑦ owner 없음(session-absent · 원장 풀기) · ⑧ done = 지금 길 그대로.
대역 = 같은 폴더 keeper_launch_wait_r2366.py · 기준판(팩 main b2476c7f) = ⑤~⑧ 지킴(회귀 0).
"""
import shutil

import pytest

import keeper_launch_wait_r2366 as h

@pytest.mark.parametrize("name", ["5", "6", "7", "8"])
def test_case(name, tmp_path, monkeypatch):
    h.CASES[name](h.box(tmp_path, monkeypatch, name))



@pytest.mark.parametrize("name", ["M2", "M4", "M5"])
def test_mutant(name, tmp_path, monkeypatch):
    edits, case = h.MUTANTS[name]   # case = 사례 이름(CASES 키)
    tree = tmp_path / "m" / "ft2"
    shutil.copytree(h.kw.FT2, tree, ignore=shutil.ignore_patterns("tests", "__pycache__"))
    text = (tree / h.KS).read_text(encoding="utf-8")
    for old, new in edits:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    (tree / h.KS).write_text(text, encoding="utf-8")
    for sub in ("w1", "w2"):
        (tmp_path / sub).mkdir()
    try:
        h.CASES[case](h.box(tmp_path / "w1", monkeypatch, case, tree))
    except AssertionError:
        pass
    else:
        raise AssertionError(name + " 변이 = 통과(잡지 못함)")
    h.CASES[case](h.box(tmp_path / "w2", monkeypatch, case))   # 원본으로 같은 사례 1회 더 = PASS
