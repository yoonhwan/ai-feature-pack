"""R1298 R6/R12/R13/R14 — 현역·휴면·파생 진단의 경계."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
sys.path.insert(0, str(BIN))

import ft_team_attach  # noqa: E402
import ft_teamset  # noqa: E402
import ft_all_stop  # noqa: E402
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


def test_allstop_succession_keeps_master_row_when_cards_diagnostic_is_bad(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path)
    old = "byz-alpha-master-claude#0"
    (tmp_path / ".fable-team").mkdir(parents=True)
    (tmp_path / ".fable-team/seats-alpha.json").write_text(
        json.dumps({"_master": old, old: {"role": "master"}}), encoding="utf-8"
    )
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(md))
    monkeypatch.setattr(ft_all_stop, "_alive", lambda _seat: True)

    assert ft_all_stop.succession(old, "byz-alpha-master-claude#1") == (True, "")
    assert "WARN alpha 판정 불가(_cards 없음)" in capsys.readouterr().out


def test_allstop_orphan_keeps_team_rel_error_and_retries_notify(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path)
    subprocess.run(["git", "-C", str(tmp_path), "init", "-q", "-b", "main"], check=True, timeout=7)
    subprocess.run(["git", "-C", str(tmp_path), "-c", "user.name=t", "-c", "user.email=t@t", "add", "design/TEAMS.md"], check=True, timeout=7)
    subprocess.run(["git", "-C", str(tmp_path), "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "teams"], check=True, timeout=7)
    subprocess.run(["git", "-C", str(tmp_path), "update-ref", "refs/remotes/origin/main", "HEAD"], check=True, timeout=7)
    ft = tmp_path / ".fable-team"
    ft.mkdir()
    cards = tmp_path / "design/teams/alpha/indices"
    cards.mkdir(parents=True)
    alpha = "byz-alpha-master-claude#0"
    orphan = "byz-orphan-master-claude#0"
    (ft / "seats-alpha.json").write_text(
        json.dumps({"_master": alpha, "_cards": "design/teams/alpha/indices", "_cards_wt": "", alpha: {"role": "master"}}),
        encoding="utf-8",
    )
    (ft / "seats-orphan.json").write_text(json.dumps({"_master": orphan, orphan: {"role": "master"}}), encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(md))
    sent = []
    monkeypatch.setattr(ft_all_stop, "send", lambda to, body: sent.append((to, body)) or True)

    delivered, failed = ft_all_stop.notify(None, {}, {orphan}, lambda row: ft_all_stop.team_rel(row["team"]))

    assert delivered == [] and failed == [orphan] and sent == []
    assert "팀 명단" in capsys.readouterr().err


def test_apply_without_own_tick_ignores_inherited_tick_paths_in_sandbox(tmp_path, monkeypatch, capsys):
    md = teams(tmp_path)
    teamset = tmp_path / "design/TEAMSET.md"
    teamset.write_text("## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    stale_tsv = tmp_path.parent / "stale-team-tick-env.tsv"
    stale_tsv.write_text("keep\n", encoding="utf-8")
    outside_plists = tmp_path.parent / "stale-launch-agents"
    outside_plists.mkdir(exist_ok=True)
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(md))
    monkeypatch.setenv("FT_TEAMSET_MD", str(teamset))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")
    monkeypatch.setenv("FT_TICK_TEAM_TSV", str(stale_tsv))
    monkeypatch.setenv("FT_TICK_PLIST_DIR", str(outside_plists))

    assert ft_team_attach.main(["alpha", "--apply"]) == 0
    assert "APPLY" in capsys.readouterr().out
    assert stale_tsv.read_text(encoding="utf-8") == "keep\n"
    assert not list(outside_plists.iterdir())
