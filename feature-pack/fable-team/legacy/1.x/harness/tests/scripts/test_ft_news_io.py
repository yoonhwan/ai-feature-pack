"""ft_news_io.read_ledger — 판정 원장(VERDICTS-planner-*-YYYYMMDD.md) 전날·오늘 줄 읽기 (R118a 에서 남긴 읽기 · R125 에서 초안 출력 경로 삭제).

실행: python3 -m pytest tests/scripts/test_ft_news_io.py -q
"""
import json
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "harness" / "bin"))

import ft_news_io as io  # noqa: E402


def test_read_ledger_returns_yesterday_and_today_lines_only(tmp_path):
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / ".fable-team" / "seats-planner.json").write_text(json.dumps({"_cards_wt": "wt"}), encoding="utf-8")
    d = tmp_path / ".worktrees" / "wt" / "design" / "planner"
    d.mkdir(parents=True)
    (d.parent / "TEAMS.md").write_text("| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | planner#9 | 현역 |\n", encoding="utf-8")  # R383
    for day, line in (("20261011", "- 1 옛"), ("20261012", "- 2 어제"), ("20261013", "- 3 오늘")):
        (d / f"VERDICTS-planner-9-{day}.md").write_text(f"{line}\n", encoding="utf-8")
    assert io.read_ledger(tmp_path, datetime(2026, 10, 13, 15, 0)) == ["- 2 어제", "- 3 오늘"]
