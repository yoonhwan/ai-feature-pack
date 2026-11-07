"""Pi consumer integration; temporary FT_ROOT and synthetic sessions only."""
import importlib.util
import json
import os
import re
import subprocess
from datetime import datetime

import pytest

from test_ft_seat_pi import BIN, END, SEAT, SID, message, write
from test_ft_seat_pi import world as world


def shell(world, command, *args, script="ft-seat-status.sh", env=None):
    return subprocess.run(["bash", str(BIN / script), command, *args], cwd=world[2].parent,
                          env=env, capture_output=True, text=True, timeout=7)


def test_seat_status_all_modes(world):
    path = write(world, [message(stopReason="stop")])
    os.utime(path, (1, 1))
    assert shell(world, "jsonl", SEAT).stdout.strip() == str(path)
    assert json.loads(shell(world, "turn", SEAT, "--json").stdout)["source"] == "pi"
    assert json.loads(shell(world, "turn", "--file", str(path), "--json").stdout)["turn_end"] == END
    for command in ("one", "list", "stalled"):
        result = shell(world, command, SEAT, "--json")
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)[0]["pane"] == "IDLE"
    assert shell(world, "idle", SEAT).stdout.strip() == SEAT


@pytest.mark.parametrize("stop,error,state", [
    ("toolUse", None, "BUSY"), ("error", "invalid_api_key", "LOGGEDOUT"),
    ("error", "503", "UNAVAILABLE"), ("aborted", None, "UNKNOWN"),
])
def test_non_idle_is_never_in_idle_or_stalled(world, stop, error, state):
    fields = {"stopReason": stop}
    if error is not None:
        fields["errorMessage"] = error
    path = write(world, [message(**fields)])
    os.utime(path, (1, 1))
    assert shell(world, "idle", SEAT).stdout == ""
    assert json.loads(shell(world, "stalled", SEAT, "--json").stdout) == []
    assert json.loads(shell(world, "one", SEAT, "--json").stdout)[0]["pane"] == state


def test_explicit_file_classification_does_not_claim_live_binding(world, monkeypatch):
    path = write(world, [message(stopReason="stop")])
    monkeypatch.setenv("FT_TMUX", "/nonexistent/tmux")
    assert shell(world, "turn", SEAT, "--json").returncode != 0
    assert json.loads(shell(world, "turn", "--file", str(path), "--json").stdout)["state"] == "IDLE"


def test_team_locate_turn_at_share_pi_source(world, monkeypatch):
    import ft_team_turns as team
    path = write(world, [message(stopReason="stop")])
    monkeypatch.setattr(team, "find_jsonls", lambda *a, **kw: pytest.fail("Pi entered Claude locator"))
    found = team.locate([SEAT], os.environ["FT_TMUX"], world[0])
    assert found == {SEAT: str(path)}
    assert team.turn_at(found[SEAT], datetime(2026, 11, 7, 2))[0] == "IDLE"
    write(world, [message(stopReason="stop")], name="duplicate")
    assert team.locate([SEAT], os.environ["FT_TMUX"], world[0])[SEAT][0] == "?"


def test_news_tree_unknown_never_falls_back_to_pane(world):
    spec = importlib.util.spec_from_file_location("pi_news_tree", BIN / "ft-news-tree.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    write(world, [message()])
    ctx = {"seats": {SEAT: {"agent": "pi"}}, "alive": {SEAT}, "status_sh": "/must-not-run"}
    assert module.seat_state(ctx, SEAT) == "UNKNOWN"


def test_model_swap_intentionally_excludes_pi(world):
    from ft_model_swap import Swap
    swap = Swap.__new__(Swap)
    swap.tables = [{"_master": SEAT, SEAT: {"agent": "pi", "role": "master"}}]
    assert swap.rows()[0][-1] is False


def test_resume_bind_expect_same_file_and_restart_invalidates(world, tmp_path):
    import ft_roster_lib as roster
    import ft_seat_bind as bind
    path = write(world, [message(stopReason="stop")])
    rec, why = roster.pi_seat_resume(SEAT, None, "synthetic")
    assert not why and rec["jsonl"] == str(path) and rec["uuid"] == SID
    bound = bind.bind(SEAT)
    assert bound["rc"] == 0 and bound["binding"] == rec["binding"]
    saved = tmp_path / "resume.json"
    saved.write_text(json.dumps(rec), encoding="utf-8")
    assert bind.expect(SEAT, str(saved))["rc"] == 0
    tmux = tmp_path / "tmux"
    tmux.write_text(tmux.read_text().replace(SID, "restarted-id"), encoding="utf-8")
    assert bind.expect(SEAT, str(saved))["rc"] != 0
    assert roster.pi_seat_resume(SEAT, None, "synthetic")[0] is None


def test_retire_records_only_bound_session_and_rejects_stale_keep(world, tmp_path):
    write(world, [message(stopReason="stop")])
    env = dict(os.environ, ZC_RESUME_DIR=str(tmp_path / "resume"))
    args = (SEAT, "--record-only", "--verdict", "123", "--seats", str(world[2] / "seats.json"))
    result = shell(world, *args, script="ft-seat-retire.sh", env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    saved = tmp_path / "resume" / (SEAT + ".json")
    before = saved.read_bytes()
    write(world, [message(stopReason="stop")], name="ambiguous")
    result = shell(world, *args, "--keep-existing", script="ft-seat-retire.sh", env=env)
    assert result.returncode != 0 and saved.read_bytes() == before


def test_close_rejects_ambiguous_pi_without_roster_write_or_kill(world, tmp_path):
    write(world, [message(stopReason="stop")])
    write(world, [message(stopReason="stop")], name="ambiguous")
    roster = world[2] / "seats.json"
    before = roster.read_bytes()
    result = shell(world, SEAT, "--reason", "synthetic", "--verdict", "123", "--seats", str(roster),
                   script="ft-seat-close.sh", env=dict(os.environ, ZC_RESUME_DIR=str(tmp_path / "resume")))
    assert result.returncode == 3, result.stdout + result.stderr
    assert roster.read_bytes() == before and "HELD" in result.stdout


def test_close_success_uses_bound_file_with_fake_kill(world, tmp_path):
    path = write(world, [message(stopReason="stop")])
    tmux = tmp_path / "tmux"
    body = tmux.read_text().replace("*) exit 1;;", "has-session|show-options|set-option) exit 0;;\nkill-session) echo fake-kill >> \"$FT_ROOT/killed\";;\n*) exit 1;;")
    tmux.write_text(body, encoding="utf-8")
    reap = tmp_path / "reap.sh"
    reap.write_text('#!/bin/sh\necho "reap synthetic left=0 rc=0"\n', encoding="utf-8")
    env = dict(os.environ, ZC_RESUME_DIR=str(tmp_path / "resume"), FT_SEAT_REAP_BIN=str(reap))
    result = shell(world, SEAT, "--reason", "synthetic", "--verdict", "123", "--seats", str(world[2] / "seats.json"),
                   script="ft-seat-close.sh", env=env)
    assert result.returncode == 0, result.stdout + result.stderr
    saved = json.loads((tmp_path / "resume" / (SEAT + ".json")).read_text())
    assert saved["jsonl"] == str(path) and saved["uuid"] == SID
    assert (tmp_path / "killed").read_text().splitlines() == ["fake-kill"]


def test_retire_ambiguous_binding_keeps_roster_unchanged(world):
    write(world, [message(stopReason="stop")])
    write(world, [message(stopReason="stop")], name="ambiguous")
    roster = world[2] / "seats.json"
    before = roster.read_bytes()
    result = shell(world, SEAT, "synthetic-next#2", "--seats", str(roster), script="ft-seat-retire.sh")
    assert result.returncode != 0 and roster.read_bytes() == before


def test_team_state_explicit_root_dispatches_pi_without_environment(world, tmp_path, monkeypatch):
    import ft_team_state as state
    import ft_team_turns as turns
    write(world, [message(stopReason="toolUse")])
    monkeypatch.setenv("FT_SEAT_RESUME_DIR", str(tmp_path / "empty-resume"))
    monkeypatch.delenv("FT_ROOT")
    monkeypatch.delenv("FT_SEATS_JSON")
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(turns, "locate", lambda seats, *a: {} if not seats else pytest.fail("Pi entered unbound locate"))
    payload = dict(root=str(tmp_path), now="2026-11-07T02:00:00", alive=[SEAT], boards={},
                   rosters={"synthetic": str(world[2] / "seats.json")}, projects=str(world[0]), tmux=os.environ["FT_TMUX"])
    rows = list(state.child_teams(payload))
    assert rows[-1]["v"]["working"] == [SEAT], rows


def test_reach_counts_only_live_uuid_and_ambiguous_is_rc5(world):
    marker = "SYNTHETIC-REACH"
    write(world, [message("user", content=marker)], name="old", sid="old-id")
    write(world, [message("user", content="unrelated")], name="current")
    env = dict(os.environ, FT_REACH_AGENT="pi", FT_REACH_COUNT_ONLY="1")
    script = BIN.parent / "comm" / "ft-reach-check.sh"
    def count():
        return subprocess.run(["bash", str(script), SEAT, marker, "0"], env=env,
                              capture_output=True, text=True, timeout=7)
    result = count()
    assert result.returncode == 0 and result.stdout.strip() == "0", result.stderr
    write(world, [message("user", content=marker)], name="duplicate")
    assert count().returncode == 5


@pytest.mark.parametrize("stat,fg,expected", [("R+", "pi", 0), ("T", "pi", 1), ("R+", "zsh", 1)])
def test_existing_agent_alive_pi_policy_with_synthetic_processes(world, stat, fg, expected):
    script = BIN.parent / "comm/ft-agent-alive.sh"
    body = f'''source "$1"
_seat_agent(){{ echo pi; }}
_ps_rows(){{ printf '100 1 S zsh\\n101 100 {stat} pi\\n'; }}
_aa_run(){{ echo {fg}; }}
_agent_alive 100 synthetic %1
'''
    result = subprocess.run(["bash", "-c", body, "_", str(script)], capture_output=True, text=True, timeout=7)
    assert result.returncode == expected, result.stderr


def _installed_reach_layout(world, tmp_path, layout="mixed"):
    live, project_bin, comm = tmp_path / "live/bin", world[2] / "bin", world[2] / "comm"
    for directory in (live, project_bin, comm):
        directory.mkdir(parents=True)
    (world[2] / "LIVE_BIN").write_text(str(live) + "\n", encoding="utf-8")
    source = (BIN / "ft-root-bin-shim.sh").read_text(encoding="utf-8")
    generator = re.search(r"^shim_body_py\(\) \{.*?^\}", source, re.M | re.S)[0]
    for name in ("ft_seat_pi.py", "ft_seat_pi_turn.py", "ft_seat_codex.py"):
        if layout != "shim_only":
            (live / name).write_bytes((BIN / name).read_bytes())
        if layout == "live_only":
            continue
        generated = subprocess.run(["bash", "-c", 'MARK="# ft-root-bin-shim:"\n' + generator + '\nshim_body_py "$1"', "_", name],
                                   capture_output=True, text=True, timeout=7)
        assert generated.returncode == 0, generated.stderr
        (project_bin / name).write_text(generated.stdout, encoding="utf-8")
    script = comm / "ft-reach-check.sh"
    script.write_bytes((BIN.parent / "comm/ft-reach-check.sh").read_bytes())
    marker = "SYNTHETIC-INSTALLED-REACH"
    write(world, [message("user", content=marker)])
    env = dict(os.environ, FT_REACH_AGENT="pi", FT_REACH_COUNT_ONLY="1")
    return live, project_bin, script, marker, env


def test_installed_reach_uses_live_modules_behind_normal_python_shims(world, tmp_path):
    live, _, script, marker, env = _installed_reach_layout(world, tmp_path)
    count = subprocess.run(["bash", str(script), SEAT, marker, "0"], env=env, capture_output=True, text=True, timeout=7)
    assert count.returncode == 0 and count.stdout.strip() == "1", count.stdout + count.stderr
    live_script = live / "ft-reach-check.sh"
    live_script.write_bytes(script.read_bytes())
    direct = subprocess.run(["bash", str(live_script), SEAT, marker, "0"], env=env, capture_output=True, text=True, timeout=7)
    assert direct.returncode == 0 and direct.stdout.strip() == "1", direct.stdout + direct.stderr
    env.pop("FT_REACH_COUNT_ONLY")
    reached = subprocess.run(["bash", str(script), SEAT, marker, "0", "0"], env=env, capture_output=True, text=True, timeout=7)
    assert reached.returncode == 0 and "REACHED" in reached.stdout, reached.stdout + reached.stderr


def test_installed_reach_shim_only_without_live_modules_is_rc5(world, tmp_path):
    live, project_bin, script, marker, env = _installed_reach_layout(world, tmp_path, "shim_only")
    assert not (live / "ft_seat_pi.py").exists() and (project_bin / "ft_seat_pi.py").exists()
    count = subprocess.run(["bash", str(script), SEAT, marker, "0"], env=env, capture_output=True, text=True, timeout=7)
    assert count.returncode == 5 and count.stdout.strip() == "", count.stdout + count.stderr
    env.pop("FT_REACH_COUNT_ONLY")
    reached = subprocess.run(["bash", str(script), SEAT, marker, "0", "0"], env=env, capture_output=True, text=True, timeout=7)
    assert reached.returncode == 5 and "REACHED" not in reached.stdout, reached.stdout + reached.stderr


def test_installed_reach_live_modules_only_counts_and_reaches(world, tmp_path):
    live, project_bin, script, marker, env = _installed_reach_layout(world, tmp_path, "live_only")
    assert (live / "ft_seat_pi.py").exists() and not (project_bin / "ft_seat_pi.py").exists()
    count = subprocess.run(["bash", str(script), SEAT, marker, "0"], env=env, capture_output=True, text=True, timeout=7)
    assert count.returncode == 0 and count.stdout.strip() == "1", count.stdout + count.stderr
    env.pop("FT_REACH_COUNT_ONLY")
    reached = subprocess.run(["bash", str(script), SEAT, marker, "0", "0"], env=env, capture_output=True, text=True, timeout=7)
    assert reached.returncode == 0 and "REACHED" in reached.stdout, reached.stdout + reached.stderr
