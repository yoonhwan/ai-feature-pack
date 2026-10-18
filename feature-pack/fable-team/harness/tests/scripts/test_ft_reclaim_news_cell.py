"""R332 — 뉴스 첫 줄 `reclaimed=N` 칸: reclaim.log «마지막 PREVENTIVE 요약줄»만 읽는다 · 로그 없음·요약 없음 = 칸 생략이 아니라 `reclaimed=미관측` 명시(DA⑥ H3)."""
import subprocess
import types

import test_ft_news_ledger  # noqa: F401, I001 — 먼저 불러야 scripts/fable-team-bin 이 sys.path 에 오른다

import ft_news_ledger as nl  # noqa: E402

TABLE = "# 2026-10-17 22:10:00 caller=? need=9999 why=preventive mode=preventive dry=0\n후보 | 종류 | 승인 근거 | 결과\nRECLAIMED 2\n"


def _log(tmp_path, text):
    state = tmp_path / ".fable-team" / "state"
    state.mkdir(parents=True)
    (state / "reclaim.log").write_text(text, encoding="utf-8")


def test_cell_reads_last_preventive_summary(tmp_path):
    _log(tmp_path, TABLE + "PREVENTIVE reclaimed=2 candidates=5 skipped=3\n# 다음 회차 on-reject\nRECLAIMED 1\n" + TABLE + "PREVENTIVE reclaimed=0 candidates=4 skipped=4\nRECLAIMED 9\n")
    assert nl.reclaim_cell(tmp_path) == "reclaimed=0"


def test_cell_says_unobserved_without_log_or_summary(tmp_path):
    assert nl.reclaim_cell(tmp_path) == "reclaimed=미관측"
    _log(tmp_path, "# 2026-10-17 22:10:00 caller=x need=2 why=agents=17 mode=-\nRECLAIMED 2\n")
    assert nl.reclaim_cell(tmp_path) == "reclaimed=미관측"


def test_lock_skip_line_is_unobserved_not_zero(tmp_path):
    _log(tmp_path, "PREVENTIVE skipped=lock\n")
    assert nl.reclaim_cell(tmp_path) == "reclaimed=미관측"


def test_decision_line_shows_unobserved_when_no_log(tmp_path, monkeypatch):
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / ".fable-team" / "seats-planner.json").write_text("{}", encoding="utf-8")

    class Done:
        returncode, stdout, stderr = 0, "결정 인터뷰 0건 · 스크립트 0건\n", ""

    monkeypatch.setattr(nl, "subprocess", types.SimpleNamespace(run=lambda *a, **k: Done(), TimeoutExpired=subprocess.TimeoutExpired))
    assert nl.decision_line(tmp_path) == "결정 인터뷰 0건 · 스크립트 0건 · reclaimed=미관측"


def test_decision_line_appends_reclaimed_cell_after_stall(tmp_path, monkeypatch):
    (tmp_path / ".fable-team").mkdir()
    (tmp_path / ".fable-team" / "seats-planner.json").write_text("{}", encoding="utf-8")
    state = tmp_path / ".fable-team" / "state"
    state.mkdir()
    (state / "stall-scan.log").write_text("stall=1 a=1 b=0 c=0 d=0 seats=3 u=1 ts=1\n", encoding="utf-8")
    (state / "reclaim.log").write_text("PREVENTIVE reclaimed=3 candidates=4 skipped=1\n", encoding="utf-8")

    class Done:
        returncode, stdout, stderr = 0, "결정 인터뷰 0건 · 스크립트 0건\n", ""

    # 모듈 전체(subprocess.run)가 아니라 ft_news_ledger 가 보는 이름만 갈아 끼운다 — conftest 의 git 가드가 같은 subprocess 를 쓴다
    monkeypatch.setattr(nl, "subprocess", types.SimpleNamespace(run=lambda *a, **k: Done(), TimeoutExpired=subprocess.TimeoutExpired))
    assert nl.decision_line(tmp_path) == "결정 인터뷰 0건 · 스크립트 0건 · stall=1 a=1 b=0 c=0 d=0 · reclaimed=3"
