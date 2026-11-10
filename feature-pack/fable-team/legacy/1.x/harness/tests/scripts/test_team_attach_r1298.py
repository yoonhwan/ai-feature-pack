"""R1298 — 팀 명단과 파생 좌석 명부를 한 함수에서 판정한다."""
import ast
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
sys.path.insert(0, str(BIN))

from ft_team_lib import rosters, team_names  # noqa: E402
from ft_stall_detect import load_teams  # noqa: E402
import ft_team_attach  # noqa: E402
import ft_teamset  # noqa: E402

def teams_file(root: Path, *rows: tuple[str, str]) -> None:
    path = root / "design/TEAMS.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n"
        + "".join(f"| {name} | `design/teams/{name}/` | x | {state} |\n" for name, state in rows),
        encoding="utf-8",
    )

def test_team_names_filters_by_state_and_rejects_broken_roster(tmp_path, monkeypatch):
    teams_file(tmp_path, ("alpha", "현역"), ("beta", "휴면"), ("gamma", "삭제"))

    assert team_names(tmp_path) == ["alpha"]
    assert team_names(tmp_path, state="휴면") == ["beta"]
    assert team_names(tmp_path, state="전체") == ["alpha", "beta", "gamma"]

    (tmp_path / "design/TEAMS.md").unlink()
    try:
        team_names(tmp_path)
    except Exception as exc:
        assert "팀 명단 판정 불가" in str(exc)
    else:
        raise AssertionError("없는 명단을 빈 팀 목록으로 처리하면 안 된다")

def test_rosters_reports_each_diagnostic_and_excludes_inactive_teams(tmp_path):
    teams_file(tmp_path, ("missing", "현역"), ("broken", "현역"), ("no_master", "현역"),
               ("no_cards", "현역"), ("no_folder", "현역"), ("good", "현역"), ("sleeping", "휴면"))
    base = tmp_path / ".fable-team"
    base.mkdir()
    (base / "seats-broken.json").write_text("{", encoding="utf-8")
    (base / "seats-no_master.json").write_text('{"_cards":"design/teams/no_master/cards"}', encoding="utf-8")
    (base / "seats-no_cards.json").write_text('{"_master":"design/teams/no_cards/MASTER.md"}', encoding="utf-8")
    (base / "seats-no_folder.json").write_text(
        '{"_master":"design/teams/no_folder/MASTER.md","_cards":"design/teams/no_folder/cards"}', encoding="utf-8"
    )
    good_cards = tmp_path / ".worktrees/good-wt/design/teams/good/cards"
    good_cards.mkdir(parents=True)
    (base / "seats-good.json").write_text(
        '{"_master":"design/teams/good/MASTER.md","_cards":"design/teams/good/cards","_cards_wt":"good-wt"}',
        encoding="utf-8"
    )
    (base / "seats-sleeping.json").write_text("{}", encoding="utf-8")

    result = rosters(tmp_path)

    assert [row["team"] for row in result] == ["missing", "broken", "no_master", "no_cards", "no_folder", "good"]
    assert [row["diag"] for row in result] == ["명부 없음", "JSON 실패", "_master 빔", "_cards 없음", "폴더 없음", "OK"]
    assert result[-1]["cards"] == good_cards
    assert set(result[0]) == {"team", "seats_path", "doc", "cards", "diag"}

def test_stall_load_warns_and_keeps_cards_unread_when_cards_field_is_missing(tmp_path, capsys):
    teams_file(tmp_path, ("zztest", "현역"))
    roster_dir = tmp_path / ".fable-team"
    roster_dir.mkdir()
    master = "byz-zztest-master-claude#0"
    (roster_dir / "seats-zztest.json").write_text(
        json.dumps({"_master": master, master: {"role": "master"}}), encoding="utf-8"
    )

    rows = load_teams(tmp_path)

    assert rows[0]["diag"] == "_cards 없음" and rows[0]["cards"] is None
    assert "WARN zztest 판정 불가(_cards 없음)" in capsys.readouterr().out


def test_attach_check_lists_missing_derived_parts_and_apply_is_idempotent(tmp_path, monkeypatch, capsys):
    teams_file(tmp_path, ("zztest", "현역"))
    teamset = tmp_path / "design/TEAMSET.md"
    teamset.write_text("## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(tmp_path / "design/TEAMS.md"))
    monkeypatch.setenv("FT_TEAMSET_MD", str(teamset))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")
    tsv = tmp_path / ".fable-team/bin/team-tick-env.tsv"
    tsv.parent.mkdir(parents=True, exist_ok=True)
    tsv.write_text("# header\n", encoding="utf-8")
    monkeypatch.setenv("FT_TICK_TEAM_TSV", str(tsv))

    assert ft_team_attach.main(["zztest", "--check"]) == 1
    assert "S2 빠짐" in capsys.readouterr().out
    assert ft_team_attach.main(["zztest", "--apply"]) == 0
    output = capsys.readouterr().out
    assert "변경=4" in output   # r1322: seats · HEADLINE · TEAMSET 행 · ASSIGN.md 틀 1
    seats = tmp_path / ".fable-team/seats-zztest.json"
    headline = tmp_path / ".fable-team/state/zztest-tick/HEADLINE.md"
    assign = tmp_path / ".fable-team/state/team-main/zztest/ASSIGN.md"
    assert assign.is_file() and "제0목표: 진행 중 카드를 완성하고 닫는다" in assign.read_text(encoding="utf-8")
    stamp = (seats.stat().st_mtime_ns, headline.stat().st_mtime_ns, teamset.stat().st_mtime_ns, assign.stat().st_mtime_ns)
    sha = (seats.read_bytes(), headline.read_bytes(), teamset.read_bytes(), assign.read_bytes())

    assert ft_team_attach.main(["zztest", "--apply"]) == 0
    assert "변경=0" in capsys.readouterr().out
    assert (seats.stat().st_mtime_ns, headline.stat().st_mtime_ns, teamset.stat().st_mtime_ns, assign.stat().st_mtime_ns) == stamp
    assert (seats.read_bytes(), headline.read_bytes(), teamset.read_bytes(), assign.read_bytes()) == sha


def test_attach_rejects_missing_team_table_without_writing(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")

    assert ft_team_attach.main(["zztest", "--apply"]) == 3
    assert "팀 명단 판정 불가" in capsys.readouterr().out
    assert not (tmp_path / ".fable-team/seats-zztest.json").exists()


def test_detach_snapshot_revert_restores_files_and_refuses_second_revert(tmp_path, monkeypatch, capsys):
    teams_file(tmp_path, ("zztest", "휴면"))
    teams = tmp_path / "design/TEAMS.md"
    teams.write_text(teams.read_text(encoding="utf-8").replace("design/teams/zztest/", "design/zztest/"), encoding="utf-8")
    teamset = tmp_path / "design/TEAMSET.md"
    teamset.write_text("## 표 2 — 팀별 덮어쓰기\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n| zztest | 3 | 0 | 상시 |\n", encoding="utf-8")
    ft = tmp_path / ".fable-team"
    seats = ft / "seats-zztest.json"
    seats.parent.mkdir(parents=True)
    seats_bytes = b'{"_label":"zztest","_master":"byz-zztest-master-claude#0","_cards":"design/zztest/indices","_cards_wt":""}\n'
    seats.write_bytes(seats_bytes)
    tick = ft / "state/zztest-tick"
    tick.mkdir(parents=True)
    headline_bytes = "09:30 헤드라인 없음 · zztest · 좌석 0\n".encode("utf-8")
    (tick / "HEADLINE.md").write_bytes(headline_bytes)
    directive = ft / "state/directive-roots.tsv"
    directive.write_text("zztest\t.\torigin/main\tdesign/zztest/indices\n", encoding="utf-8")
    tsv = ft / "bin/team-tick-env.tsv"
    tsv.parent.mkdir(parents=True)
    tsv.write_text("# header\nzztest\tseats-zztest.json\t/tmp/a\t/tmp/b\t/tmp/c\tOFF\tON=1\n", encoding="utf-8")
    plist_dir = tmp_path / "Library/LaunchAgents"
    plist_dir.mkdir(parents=True)
    plist = plist_dir / "com.byz.ft-tick-zztest.plist"
    plist_bytes = b"test plist\n"
    plist.write_bytes(plist_bytes)
    launchctl = tmp_path / "launchctl"
    launchctl.write_text(
        "#!/bin/sh\ncase \"$1\" in list) echo '0 0 com.byz.ft-tick-zztest';; esac\necho \"$*\" >> \"$LC_LOG\"\nexit 0\n",
        encoding="utf-8",
    )
    launchctl.chmod(0o755)
    monkeypatch.setenv("FT_ROOT", str(tmp_path))
    monkeypatch.setenv("FT_TEAMS_MD", str(teams))
    monkeypatch.setenv("FT_TEAMSET_MD", str(teamset))
    monkeypatch.setenv("FT_TICK_TEAM_TSV", str(tsv))
    monkeypatch.setenv("FT_TICK_PLIST_DIR", str(plist_dir))
    monkeypatch.setenv("FT_TICK_LAUNCHCTL", str(launchctl))
    monkeypatch.setenv("FT_TEAM_ATTACH_SANDBOX", "1")
    monkeypatch.setenv("LC_LOG", str(tmp_path / "launchctl.log"))

    assert ft_team_attach.main(["zztest", "--detach"]) == 0
    snap = json.loads(next((ft / "state/team-attach").glob("*/manifest.json")).read_text())
    snapshot = Path(snap["snapshot"])
    assert not seats.exists() and not tick.exists() and not plist.exists()
    assert (ft / "retired" / f"seats-zztest.json.{snap['stamp']}").exists()
    assert "zztest" not in tsv.read_text(encoding="utf-8") and "zztest" not in directive.read_text(encoding="utf-8")
    assert "| zztest | 0 | 0 | 휴면" in teamset.read_text(encoding="utf-8")

    assert ft_team_attach.main(["--revert", str(snapshot)]) == 0
    capsys.readouterr()
    assert seats.read_bytes() == seats_bytes and (tick / "HEADLINE.md").read_bytes() == headline_bytes
    assert plist.read_bytes() == plist_bytes
    assert "zztest" in directive.read_text(encoding="utf-8") and "zztest" in tsv.read_text(encoding="utf-8")
    assert teamset.read_text(encoding="utf-8").endswith("| zztest | 3 | 0 | 상시 |\n")
    assert "bootstrap gui/" in (tmp_path / "launchctl.log").read_text(encoding="utf-8")

    assert ft_team_attach.main(["--revert", str(snapshot)]) == 1
    assert "이미 복원된" in capsys.readouterr().out


def test_cap_of_requires_a_published_row_for_active_teams():
    spec = {"teams": {}, "default": 3}
    assert ft_teamset.cap_of(spec, "zztest", {"zztest"}) is None
    assert ft_teamset.cap_of(spec, "zztest", set()) == 3


def test_seven_consumers_have_no_seats_file_globs():
    root = ROOT / "harness"
    names = ("ft_stall_detect.py", "ft_board_collect.py", "ft_queue_watch.py", "ft_all_stop.py",
             "ft_penalty.py", "ft_teamset.py", "ft-tick.sh")
    pattern = re.compile(r"(?:\.glob\(\s*['\"]seats|seats-\*\.json)")
    for folder in (root / "bin", root / "kit/fable-team/bin"):
        for name in names:
            path = folder / name
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".py":
                tree = ast.parse(text)
                calls = (node for node in ast.walk(tree) if isinstance(node, ast.Call))
                uses = [node for node in calls if isinstance(node.func, ast.Attribute) and node.func.attr == "glob"
                        and node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)
                        and "seats" in node.args[0].value]
                assert not uses, f"glob remains: {path}"
            else:
                code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
                assert not pattern.search(code), f"glob remains: {path}"
