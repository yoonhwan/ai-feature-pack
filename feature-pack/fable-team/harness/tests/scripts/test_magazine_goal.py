"""R362 아침 매거진(오빠 확인판) 골 표 — 뿌리 글 첫 줄 뒤 + HTML 맨 위 절 · 무장이면 실패 = 발행 0(rc1) · 비무장이면 WOULD-REJECT 로그 + 골 표 없이 발행. 가짜 Slack · 외부 호출 0.

실행: .venv/bin/python -m pytest tests/scripts/test_magazine_goal.py -q
"""
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from _magazine_fakes import FakeMagazineSlack
from _magazine_ledger import argv, make_env

import magazine_doc as md
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
CANON = ROOT / "tests" / "fixtures" / "goal_table" / "AUTONOMY-GOAL-A6-20261018.md"
TITLE = "매거진 2026-10-16 · 오빠 확인판"


@pytest.fixture
def env(tmp_path, monkeypatch):
    root = tmp_path / "ftroot"
    (root / ".fable-team" / "bin").mkdir(parents=True)
    for f in ("ft-goal-table.sh", "ft_goal_table.py", "ft_goal_ledger.py", "ft_goal_gate.py", "ft_goal_receipt.py", "ft_goal_readjust_state.py", "ft_team_lib.py"):
        shutil.copy(BIN / f, root / ".fable-team" / "bin" / f)
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setenv("FT_GOAL_A6_MD", str(CANON))
    monkeypatch.setenv("FT_GOAL_A6_LEDGER", str(tmp_path / "없는원장.md"))
    return make_env(tmp_path), root


def arm(root: Path) -> None:
    (root / ".fable-team" / "state").mkdir(parents=True, exist_ok=True)
    (root / ".fable-team" / "state" / "goal-gate.armed").write_text("", encoding="utf-8")


def test_root_text_has_the_block_right_after_the_first_line_and_html_has_the_section(env):
    (mag, root) = env
    arm(root)
    slack = FakeMagazineSlack()
    assert md.main(argv(mag, "--publish", slack)) == 0
    lines = slack.roots[0]["text"].splitlines()
    assert lines[0] == TITLE and lines[1].startswith("★골 표 A6 (") and "★/골 표★" in lines
    page = next((mag[0] / "out").glob("*.html")).read_text(encoding="utf-8")
    assert "<h2>자율 골 표</h2>" in page and page.index("자율 골 표") < page.index("오빠 할 일")


def test_armed_gate_failure_publishes_nothing_writes_no_state_and_notifies_planner_once(env, monkeypatch, tmp_path):
    (mag, root) = env
    arm(root)
    (root / ".fable-team" / "seats-planner.json").write_text('{"_master": "planner#9"}', encoding="utf-8")
    stub, log = tmp_path / "mbox-stub.sh", tmp_path / "mbox-stub.log"
    stub.write_text('#!/usr/bin/env bash\necho "$@" >> "$FT_STUB_LOG"\nexit 0\n', encoding="utf-8")
    monkeypatch.setenv("FT_MBOX", str(stub))
    monkeypatch.setenv("FT_STUB_LOG", str(log))
    monkeypatch.setenv("FT_GOAL_A6_MD", str(root / "없는정본.md"))  # 정본 없음 → render ERROR
    slack = FakeMagazineSlack()
    assert md.main(argv(mag, "--publish", slack)) == 1
    assert slack.roots == [] and not (mag[0] / "state.json").exists()
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 1 and "진입점: magazine" in log.read_text(encoding="utf-8")
    assert "REJECT magazine" in (root / ".fable-team" / "state" / "mbox-guard-goal.log").read_text(encoding="utf-8")


def test_unarmed_gate_failure_publishes_without_block_and_logs_would_reject(env, monkeypatch):
    (mag, root) = env
    monkeypatch.setenv("FT_GOAL_A6_MD", str(root / "없는정본.md"))
    slack = FakeMagazineSlack()
    assert md.main(argv(mag, "--publish", slack)) == 0
    assert "★골 표" not in slack.roots[0]["text"] and slack.roots[0]["text"].splitlines()[0] == TITLE
    assert "WOULD-REJECT magazine" in (root / ".fable-team" / "state" / "mbox-guard-goal.log").read_text(encoding="utf-8")


def test_dry_run_prints_the_block_in_the_slack_text(env, capsys):
    (mag, root) = env
    assert md.main(argv(mag, "--dry-run")) == 0
    out = capsys.readouterr().out
    assert "--- 슬랙 뿌리 글 ---" in out and "★골 표 A6 (" in out


KIT = ROOT / "harness" / "kit" / "slack-mirror"


def _stand_in(root: Path, armed_flag: bool) -> subprocess.CompletedProcess:
    """magazine_goal import 가 실패한 상태(설치 누락)의 magazine_doc.goal_block — 무장 = 발행 거절(MirrorError) · 비무장 = 경고 후 빈 글."""
    if armed_flag:
        arm(root)
    code = ("import sys; sys.modules['magazine_goal'] = None; sys.path[:0] = [%r]; import magazine_doc as m\n"
            "try:\n    print('EMPTY' if m.goal_block() == '' else 'BLOCK')\nexcept Exception as e:\n    print(type(e).__name__)\n") % str(KIT)
    return subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=False, env={"FT_ROOT": str(root), "PATH": "/usr/bin:/bin"})


def test_missing_magazine_goal_module_rejects_when_armed_and_goes_on_when_not(tmp_path):
    assert _stand_in(tmp_path / "a", True).stdout.strip() == "MirrorError"
    assert _stand_in(tmp_path / "b", False).stdout.strip() == "EMPTY"
