"""ft_news_io — planner 판정 원장 읽기 (R118a 에서 남긴 부분 · R125: 뉴스 초안 출력 경로는 삭제 — 뉴스 입력은 오빠 원장 하나, ft_news_ledger.py)."""
import json
from datetime import datetime, timedelta
from pathlib import Path


def read_ledger(root: Path, now: datetime) -> list[str]:
    """planner 판정 원장(VERDICTS-planner-*-YYYYMMDD.md) 중 전날·오늘 파일의 줄. 줄마다 시각이 없어 창은 파일 날짜 단위(전날 08:00 보다 넓다)."""
    wt = json.loads((root / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8")).get("_cards_wt", "")
    since = (now - timedelta(days=1)).strftime("%Y%m%d")
    files = sorted(p for p in (root / ".worktrees" / wt / "design" / "planner").glob("VERDICTS-planner-*-*.md") if p.stem[-8:] >= since)
    return [ln for p in files for ln in p.read_text(encoding="utf-8").splitlines()]
