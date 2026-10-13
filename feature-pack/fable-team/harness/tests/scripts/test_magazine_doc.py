"""r117 오빠 확인 문서 → 스위스 HTML. 절 나누기 · 표/목록 행 수 보존 · 조립. 네트워크 0.

실행: python3 -m pytest tests/scripts/test_magazine_doc.py -q
"""
import re
import subprocess
from pathlib import Path

import pytest
import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다

import magazine_doc_md as dm

SRC = """# 아침 매거진 샘플 2판 — 전문 (2026-10-13 11:4x · planner 정리)

> 오빠 지시: 「상태를 출력해라」

---

## 1. 오빠가 시킨 일 — 지금 상태

### 어제 시키신 일
| 시키신 일 | 지금 상태 |
|---|---|
| 가입 메일 | 완료 |
| 폰 물결 | 진행 <b>x</b> |

## 2. 완료한 일
- **실시간 통역**: 교정 해결
- **결제**: 메일 13종

## 3. 진행 중인 일
- **유일하게 움직이는 일**: 하네스

## 4. 이후 해야 할 일
- **오빠 차례**: 폰 확인

## ★정리하면서 드러난 문제★
- 카드 상태 줄이 다름
- 전달 누락

## 5. 팀별 상태와 할 일 전체 (각 팀장 회신 원문)

### 실시간 통역(v65)

지금 팀 상태: 전팀 일시 정지

## 진행 중 (2)

- 강의 화면 잇기 — 진행
- 되살리기 — 진행

### 결제(cfo)
## 1. 지금 붙잡고 있는 것
1. 첫째 일
2. 둘째 일
## 4. 카드 밖 열린 줄
- 끝 줄

### 하네스(harness)
## 매거진이 «자동으로» 이 꼴을 만들 수 있나 (합의 제안)
가능. 단 셋이 먼저 필요해요.
1. 카드 상태 줄 표준
2. 연결 칸

### 운영툴(ops)
①지금 팀 상태: 전원 정지
[진행]
- 크레딧 만료 코드 - 진행
"""
CELL_TITLES = ["오빠가 시킨 일 — 지금 상태", "완료한 일", "진행 중인 일", "이후 해야 할 일", "★정리하면서 드러난 문제★"]
TEAM_TITLES = ["실시간 통역(v65)", "결제(cfo)", "하네스(harness)", "운영툴(ops)"]


def test_split_cells_and_teams():
    doc = dm.parse_doc(SRC)
    assert [c.title for c in doc.cells] == CELL_TITLES
    assert [t.title for t in doc.teams] == TEAM_TITLES
    assert [c.key for c in doc.cells + doc.teams] == ["c1", "c2", "c3", "c4", "c5", "t1", "t2", "t3", "t4"]


def test_team_inner_headings_are_not_cells():
    doc = dm.parse_doc(SRC)
    pay = doc.teams[1]
    assert "## 1. 지금 붙잡고 있는 것" in pay.body and "## 4. 카드 밖 열린 줄" in pay.body
    assert "## 매거진이 «자동으로»" in doc.teams[2].body
    assert "## 진행 중 (2)" in doc.teams[0].body


def test_title_and_intro_kept():
    doc = dm.parse_doc(SRC)
    assert doc.title.startswith("아침 매거진 샘플 2판") and "2026-10-13" in doc.title
    assert "상태를 출력해라" in doc.intro


def test_no_section_lines_lost():
    doc = dm.parse_doc(SRC)
    kept = [ln for c in doc.cells + doc.teams for ln in c.body.splitlines() if ln.strip()]
    team_heads = tuple(f"### {t}" for t in TEAM_TITLES)
    src_body = [ln for ln in SRC.splitlines() if ln.strip() and not ln.startswith(("# ", "> ", "---", "## 5.") + team_heads)]
    heads = {c.title for c in doc.cells}
    expected = [ln for ln in src_body if not (ln.startswith("## ") and ln[3:].lstrip("0123456789. ") in heads)]
    assert kept == expected


def test_table_rows_equal_html_rows():
    html = dm.to_html(dm.parse_doc(SRC).cells[0].body)
    assert html.count("<tr><td>") == 2 and html.count("<th>") == 2
    assert "&lt;b&gt;x&lt;/b&gt;" in html and "<b>x</b>" not in html


def test_list_items_equal_html_li():
    for cell in dm.parse_doc(SRC).cells + dm.parse_doc(SRC).teams:
        src_items = [ln for ln in cell.body.splitlines() if re.match(r"(- |\d+\. )", ln)]
        assert dm.to_html(cell.body).count("<li>") == len(src_items), cell.title


def test_bold_and_plain_lines_preserved():
    html = dm.to_html("- **실시간 통역**: 교정 해결\n①지금 팀 상태: 전원 정지\n[진행]")
    assert "<strong>실시간 통역</strong>" in html
    assert "①지금 팀 상태: 전원 정지" in html and "[진행]" in html


def test_missing_teams_zone_means_zero_teams_but_empty_zone_raises():
    assert dm.parse_doc("# 제목\n\n## 1. 시킨 일\n- a\n").teams == []  # R125 — 오빠 원장은 팀 구역이 없다
    with pytest.raises(dm.DocError):
        dm.parse_doc("# 제목\n\n## 1. 시킨 일\n- a\n\n## 5. 팀별 상태\n- 팀 제목 없음\n")


def test_real_source_counts():
    repo = Path(__file__).resolve().parents[2]
    git = ["git", "-C", str(repo), "show", "2a714e0785:design/planner/SAMPLE-magazine-r2-full-20261013.md"]
    got = subprocess.run(git, capture_output=True, text=True, encoding="utf-8")
    if got.returncode != 0:
        pytest.skip("원본 sha 2a714e0785 가 이 클론에 없음 — 로컬(워크트리 공유 저장소)에서만 돈다")
    doc = dm.parse_doc(got.stdout)
    assert len(doc.cells) == 5 and len(doc.teams) == 8
    for cell in doc.cells + doc.teams:
        src_rows = [ln for ln in cell.body.splitlines() if ln.startswith("|") and not re.match(r"\|[-| ]+\|$", ln)]
        html = dm.to_html(cell.body)
        assert html.count("<tr>") == len(src_rows), cell.title
