"""R1298 S6 — detach/revert use a read-only launchctl listing and preserve the loaded state."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
sys.path.insert(0, str(BIN))

import ft_team_attach  # noqa: E402


def test_detach_boots_out_listed_service_and_revert_bootstraps(tmp_path, monkeypatch, capsys):
    root = tmp_path
    design = root / "design"
    design.mkdir()
    teams = design / "TEAMS.md"
    teams.write_text("| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| zztest | design/teams/zztest/ | x | 휴면 |\n", encoding="utf-8")
    teamset = design / "TEAMSET.md"
    teamset.write_text("## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| zztest | 0 | 0 | 휴면 1 |\n", encoding="utf-8")
    ft = root / ".fable-team"
    (ft / "state/zztest-tick").mkdir(parents=True)
    (ft / "state/zztest-tick/HEADLINE.md").write_text("09:00 헤드라인 없음 · zztest · 좌석 0\n", encoding="utf-8")
    (ft / "retired").mkdir()
    (ft / "seats-zztest.json").write_text('{"_master":"","_label":"zztest","_cards":"design/teams/zztest/indices","_cards_wt":""}\n', encoding="utf-8")
    tsv = ft / "bin/team-tick-env.tsv"
    tsv.parent.mkdir()
    tsv.write_text("zztest\tseats-zztest.json\t/tmp/s\t/tmp/p\t/tmp/t\tOFF\tON=1\n", encoding="utf-8")
    plist_dir = root / "LaunchAgents"
    plist_dir.mkdir()
    plist = plist_dir / "com.byz.ft-tick-zztest.plist"
    plist.write_bytes(b"plist\n")
    state = root / "loaded.txt"
    state.write_text("com.byz.ft-tick-zztest\n", encoding="utf-8")
    log = root / "launchctl.log"
    stub = root / "launchctl"
    stub.write_text(
        "#!/bin/sh\ncase \"$1\" in\n"
        "list) cat \"$LC_STATE\";;\n"
        "bootout) echo bootout >> \"$LC_LOG\"; : > \"$LC_STATE\";;\n"
        "bootstrap) echo bootstrap >> \"$LC_LOG\"; echo com.byz.ft-tick-zztest > \"$LC_STATE\";;\n"
        "esac\n",
        encoding="utf-8",
    )
    stub.chmod(0o755)
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setenv("FT_TEAMS_MD", str(teams))
    monkeypatch.setenv("FT_TEAMSET_MD", str(teamset))
    monkeypatch.setenv("FT_TICK_TEAM_TSV", str(tsv))
    monkeypatch.setenv("FT_TICK_PLIST_DIR", str(plist_dir))
    monkeypatch.setenv("FT_TICK_LAUNCHCTL", str(stub))
    monkeypatch.setenv("LC_STATE", str(state))
    monkeypatch.setenv("LC_LOG", str(log))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")

    assert ft_team_attach.main(["zztest", "--detach"]) == 0
    snap = next((ft / "state/team-attach").glob("*/manifest.json")).parent
    assert not plist.exists() and not state.read_text(encoding="utf-8")
    assert "bootout" in log.read_text(encoding="utf-8")

    assert ft_team_attach.main(["--revert", str(snap)]) == 0
    capsys.readouterr()
    assert plist.read_bytes() == b"plist\n"
    assert "com.byz.ft-tick-zztest" in state.read_text(encoding="utf-8")
    assert "bootstrap" in log.read_text(encoding="utf-8")

