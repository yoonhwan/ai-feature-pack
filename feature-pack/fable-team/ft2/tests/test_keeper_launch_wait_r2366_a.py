"""r2366 keeper 가 미룬 열기 ≠ owner-orphan — 반례 ①~④(동결) + 변이 M1·M3.
같은 리포 열기 1개 규칙으로 띄우기를 다음 바퀴로 미룬 나노(owner 있음 · intent 없음 · state fill_open 에 같은 attempt)를 settle 이
[긴급] UNKNOWN 대신 WORKING «launch-wait» 로 보고, 첫 absent 바퀴부터 OPEN_STALE(900초)을 넘으면 지금 그대로 owner-orphan.
대역 = 같은 폴더 keeper_launch_wait_r2366.py · 기준판(팩 main b2476c7f) = ① ② Red · ③ ④ 지킴.
"""
import shutil

import pytest

import keeper_launch_wait_r2366 as h

@pytest.mark.parametrize("name", ["1", "2", "3", "4"])
def test_case(name, tmp_path, monkeypatch):
    h.CASES[name](h.box(tmp_path, monkeypatch, name))



@pytest.mark.parametrize("name", ["M1", "M3"])
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
