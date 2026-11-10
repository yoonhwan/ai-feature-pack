"""r1006 — 뉴스 슬랙 본문에서 골 표·팀 진행·표준절차(마크다운 표)를 빼고 «골표 <sha10>» 표지 1줄만.

왜: 슬랙은 마크다운 표를 못 그려 `|---|`·«…» 로 잘린 글이 된다. 같은 표는 뉴스 HTML 지도가 같은 판정기로 이미 그린다.
이 파일 = 본문 조립 쪽(ⓐ C1 본문 표 줄 0 · ⓔ C5 각주는 목록 줄 · C6 kit 짝 cmp0·200줄). 문 쪽(ⓑ~ⓓ·ⓕ·ⓖ)은 `test_news_body_goal_tag_r1006_gate.py`(r1006 r2 — 파일 200줄 상한 때문에 둘로 나눔 · 내용 변경 0).
실행: pytest tests/scripts/test_news_body_goal_tag_r1006.py -q
"""
import re
import sys
from datetime import datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "fable-team" / "bin"
sys.path.insert(0, str(BIN))

import ft_goal_table as gt  # noqa: E402
import ft_news_ledger_text as lt  # noqa: E402
import ft_news_status as st  # noqa: E402

NOW = datetime(2026, 10, 27, 10, 30)
REL = "design/planner/PLAN-oppa-ledger.md"
CANON = ROOT / "tests" / "fixtures" / "goal_table" / "AUTONOMY-GOAL-A6-20261018.md"
LEAD = "결정 인터뷰 1건 · 스크립트 0건"


@pytest.fixture(autouse=True)
def canon(monkeypatch, tmp_path):
    monkeypatch.setenv("FT_GOAL_A6_MD", str(CANON))
    monkeypatch.setenv("FT_GOAL_A6_LEDGER", str(tmp_path / "없는원장.md"))


@pytest.fixture
def block() -> str:
    return gt.render()


def _sha(block: str) -> str:
    return re.search(r"[0-9a-f]{10}", block.splitlines()[0].split("(")[1]).group(0)


def _new(teams: int) -> dict:
    new = {("now", "", "지금 전체 상태"): ("진행",)}
    new.update({("3", "", f"팀{i}"): ("가" * 60 + str(i),) for i in range(teams)})
    return new


# ── ⓐ C1 본문 표 줄 0 · 표지 1줄 ────────────────────────────────

def test_a_first_part_has_no_table_line_and_exactly_one_tag_line(block):
    teams = gt.render_teams() if hasattr(gt, "render_teams") else ""
    parts = lt.render_parts(NOW, _new(120), [], REL, lead=LEAD, goal=block, teams=teams)
    assert len(parts) >= 2
    assert all("★골 표" not in p and "★팀별 완성 진행" not in p for p in parts)
    assert not [ln for p in parts for ln in p.splitlines() if ln.startswith("|")]  # 표 줄 0
    assert all(p.count("골표 " + _sha(block)) == 1 for p in parts)  # 판마다 표지 1줄
    assert parts[0].splitlines()[1] == LEAD  # 블록이 있던 자리에 lead 가 온다


def test_a_without_goal_the_body_stays_the_same_no_tag_no_table():
    parts = lt.render_parts(NOW, _new(3), [], REL, lead=LEAD)
    assert all("골표" not in p and "|" not in p for p in parts)


# ── ⓔ C5 각주(상태 절) = 목록 줄 · 내용·순서 그대로 · 표 줄 0 ────

def test_e_status_footnote_lines_stay_bullets_in_order_and_carry_no_table(block):
    lines = ["(세션 상태 스냅샷 10:25 · 갱신 안 됨)", "• planner — 일함 1 · 정지 없음 / 해야 할 일: 없음"]
    parts = lt.render_parts(NOW, _new(3), [], REL, lead=LEAD, goal=block, extra=((st.TITLE, lines),))
    got = parts[0].splitlines()
    assert "|---" not in parts[0] and not [ln for ln in got if ln.startswith("|")]  # 표 줄 0
    assert got[-len(lines):] == lines  # 각주(맨 끝) = 내용·순서 그대로
    assert got.index(st.TITLE) < got.index(lines[-1])  # 절 제목 아래


# ── C6 kit 짝 cmp0 · 200줄 상한 ─────────────────────────────────

@pytest.mark.parametrize("name", ["ft_news_ledger_text.py", "ft_goal_gate.py"])
def test_c6_kit_copy_is_identical_and_both_files_stay_under_200_lines(name):
    a, b = (BIN / name).read_bytes(), (KIT / name).read_bytes()
    assert a == b  # kit 짝 cmp0
    assert len(a.decode("utf-8").splitlines()) <= 200
