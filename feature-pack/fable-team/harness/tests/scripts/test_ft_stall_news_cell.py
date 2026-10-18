"""R320b — 뉴스 첫 줄 `stall=N` 칸: stall-scan.log 마지막 줄(요약)만 읽는다 · 로그 없음·요약 아님 = 칸 없음."""
import test_ft_news_ledger  # noqa: F401, I001 — 먼저 불러야 scripts/fable-team-bin 이 sys.path 에 오른다

import ft_news_ledger as nl  # noqa: E402


def test_cell_reads_last_summary_line(tmp_path):
    state = tmp_path / ".fable-team" / "state"
    state.mkdir(parents=True)
    (state / "stall-scan.log").write_text("2026-10-17T14:00:00 act=a to=m key=a:m x\nstall=2 a=1 b=1 c=0 d=0 seats=60 u=1 ts=1\n", encoding="utf-8")
    assert nl.stall_cell(tmp_path) == "stall=2 a=1 b=1 c=0 d=0"


def test_cell_empty_without_log_or_summary(tmp_path):
    assert nl.stall_cell(tmp_path) == ""
    state = tmp_path / ".fable-team" / "state"
    state.mkdir(parents=True)
    (state / "stall-scan.log").write_text("2026-10-17T14:00:00 act=a to=m key=a:m x\n", encoding="utf-8")
    assert nl.stall_cell(tmp_path) == ""
