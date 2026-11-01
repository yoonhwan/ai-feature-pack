"""R1298 R6/R12/R13/R14 — 현역·휴면·파생 진단의 경계."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
sys.path.insert(0, str(BIN))

import ft_team_attach  # noqa: E402
import ft_teamset  # noqa: E402
from ft_stall_detect import load_teams  # noqa: E402
from ft_team_lib import rosters, team_names  # noqa: E402


def teams(root: Path, state: str = "현역") -> Path:
    path = root / "design/TEAMS.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n"
        f"| alpha | design/teams/alpha/ | x | {state} |\n",
        encoding="utf-8",
    )
    return path


def test_R6_active_team_detach_is_rejected_without_writes(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path)
    seats = tmp_path / ".fable-team/seats-alpha.json"
    seats.parent.mkdir(parents=True)
    seats.write_text('{"_master":"m","_cards":"design/teams/alpha/indices","_cards_wt":""}\n', encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(md))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")

    assert ft_team_attach.main(["alpha", "--detach"]) == 1
    assert "현역 팀은 --detach" in capsys.readouterr().out
    assert seats.is_file() and not (tmp_path / ".fable-team/state/team-attach").exists()


def test_R12_revert_rejects_a_changed_snapshot_member(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path, "휴면")
    teamset = tmp_path / "design/TEAMSET.md"
    teamset.write_text("## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| alpha | 3 | 0 | 상시 |\n", encoding="utf-8")
    seats = tmp_path / ".fable-team/seats-alpha.json"
    seats.parent.mkdir(parents=True)
    seats.write_text('{"_master":"m"}\n', encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(md))
    monkeypatch.setenv("FT_TEAMSET_MD", str(teamset))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")

    assert ft_team_attach.main(["alpha", "--detach"]) == 0
    snap = next((tmp_path / ".fable-team/state/team-attach").glob("*/manifest.json"))
    retired = next((tmp_path / ".fable-team/retired").glob("seats-alpha.json.*"))
    retired.write_text("changed\n", encoding="utf-8")
    assert ft_team_attach.main(["--revert", str(snap.parent)]) == 1
    assert "sha256·경로 불일치" in capsys.readouterr().out
    assert not seats.exists() and retired.read_text(encoding="utf-8") == "changed\n"


def test_R13_missing_active_roster_is_not_zero(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path)
    monkeypatch.setenv("FT_TEAMS_MD", str(md))

    rows = rosters(tmp_path)
    load_teams(tmp_path)

    assert team_names(tmp_path) == ["alpha"]
    assert rows[0]["diag"] == "명부 없음"
    assert ft_teamset.cap_of({"teams": {}, "default": 3}, "alpha", {"alpha"}) is None
    assert "WARN alpha 판정 불가(명부 없음)" in capsys.readouterr().out


def test_R14_orphan_roster_is_excluded_from_team_names(tmp_path, monkeypatch):
    md = teams(tmp_path)
    roster_dir = tmp_path / ".fable-team"
    roster_dir.mkdir()
    cards = tmp_path / "design/teams/alpha/indices"
    cards.mkdir(parents=True)
    (roster_dir / "seats-alpha.json").write_text(
        json.dumps({"_master": "m", "_cards": "design/teams/alpha/indices", "_cards_wt": ""}), encoding="utf-8"
    )
    (roster_dir / "seats-orphan.json").write_text("{}", encoding="utf-8")
    monkeypatch.setenv("FT_TEAMS_MD", str(md))

    assert team_names(tmp_path) == ["alpha"]
    assert [row["team"] for row in rosters(tmp_path)] == ["alpha"]
