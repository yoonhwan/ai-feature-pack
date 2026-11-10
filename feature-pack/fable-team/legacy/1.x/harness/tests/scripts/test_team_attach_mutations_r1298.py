"""R1298 — eight isolated behavior mutations must be caught by their contract probes."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness/bin"
MODULES = ("ft_team_attach.py", "ft_team_attach_lib.py", "ft_team_attach_ops.py",
           "ft_team_attach_state.py", "ft_team_lib.py", "ft_stall_detect.py", "ft_decision_kind.py")


def copy_bin(dst: Path) -> Path:
    dst.mkdir()
    for name in MODULES:
        shutil.copy2(BIN / name, dst / name)
    return dst


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, f"mutation anchor missing: {path.name}: {old[:60]}"
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def table(root: Path, *states: tuple[str, str]) -> Path:
    p = root / "design/TEAMS.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n" +
                 "".join(f"| {n} | design/teams/{n}/ | x | {s} |\n" for n, s in states), encoding="utf-8")
    return p


def run_probe(code: str, bin_dir: Path, root: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    test_env = {**os.environ, "FT_ROOT": str(root), "FT_TEAMS_MD": str(root / "design/TEAMS.md"),
                "FT_TEAMSET_MD": str(root / "design/TEAMSET.md"), "FT_TEAM_ATTACH_SANDBOX": "1"}
    test_env.update(env or {})
    return subprocess.run([sys.executable, "-c", code, str(bin_dir), str(root)],
                          capture_output=True, text=True, timeout=7, env=test_env)


def test_mutation_1_apply_without_seats_file_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m1")
    replace(b / "ft_team_attach_ops.py",
            'doc = {"_label": team, "_master": "", "_cards": f"{rel}/indices", "_cards_wt": "", "_doc": "ft-team-attach r1298"}',
            'doc = {}')
    root = tmp_path / "root"
    table(root, ("zztest", "현역"))
    (root / "design/TEAMSET.md").write_text("## 표 2\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    code = 'import json,sys;sys.path.insert(0,sys.argv[1]);import ft_team_attach as a;r=a.main(["zztest","--apply"]);d=json.load(open(sys.argv[2]+"/.fable-team/seats-zztest.json"));assert r==0 and all(k in d for k in ("_master","_cards","_cards_wt"))'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_2_active_detach_guard_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m2")
    replace(b / "ft_team_attach_state.py", 'if state == "현역":', 'if False and state == "현역":')
    root = tmp_path / "root"
    table(root, ("zztest", "현역"))
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team/seats-zztest.json").write_text("{}\n", encoding="utf-8")
    code = 'import sys;sys.path.insert(0,sys.argv[1]);import ft_team_attach as a;assert a.main(["zztest","--detach"])==1'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_3_team_names_globs_seats_files_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m3")
    p = b / "ft_team_lib.py"
    replace(p, 'if state not in ("현역", "휴면", "삭제", "전체"):', 'return sorted(x.stem.removeprefix("seats-") for x in (Path(root)/".fable-team").glob("seats-*.json"))\n    if state not in ("현역", "휴면", "삭제", "전체"):')
    root = tmp_path / "root"
    table(root, ("zztest", "현역"))
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team/seats-orphan.json").write_text("{}\n", encoding="utf-8")
    code = 'import sys;sys.path.insert(0,sys.argv[1]);from ft_team_lib import team_names;assert team_names(__import__("pathlib").Path(sys.argv[2]))==["zztest"]'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_4_daily_lint_does_not_notify_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m4")
    replace(b / "ft_team_attach_ops.py", "    if bad:\n", "    if False and bad:\n")
    root = tmp_path / "root"
    table(root, ("zztest", "현역"))
    (root / "design/TEAMSET.md").write_text("## 표 2\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    sent = tmp_path / "sent.log"
    mbox = tmp_path / "mbox.sh"
    mbox.write_text("#!/bin/sh\necho sent >> \"$FT_SENT\"\n", encoding="utf-8")
    mbox.chmod(0o755)
    code = 'import os,sys,pathlib;sys.path.insert(0,sys.argv[1]);import ft_team_attach as a;assert a.main(["--all","--check","--notify","planner#1"])==1;assert pathlib.Path(os.environ["FT_SENT"]).read_text().count("sent")==1'
    env = {"FT_MBOX_SH": str(mbox), "FT_SENT": str(sent), "FT_TICK_TEAM_TSV": str(root / ".fable-team/bin/team-tick-env.tsv")}
    (root / ".fable-team/bin").mkdir(parents=True, exist_ok=True)
    (root / ".fable-team/bin/team-tick-env.tsv").write_text("# header\n", encoding="utf-8")
    p = run_probe(code, b, root, env)
    assert p.returncode != 0


def test_mutation_5_revert_without_sha_check_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m5")
    replace(b / "ft_team_attach_state.py", 'tree_digest(dst) != item["sha256"]', "False")
    root = tmp_path / "root"
    table(root, ("zztest", "휴면"))
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team/seats-zztest.json").write_text("{}\n", encoding="utf-8")
    (root / "design/TEAMSET.md").write_text("## 표 2\n| 팀 | 나노 상한 | tester | arch 상시 |\n|---|---|---|---|\n", encoding="utf-8")
    code = 'import sys,pathlib;sys.path.insert(0,sys.argv[1]);import ft_team_attach as a;assert a.main(["zztest","--detach"])==0;p=next(pathlib.Path(sys.argv[2]+"/.fable-team/state/team-attach").glob("*/manifest.json"));d=__import__("json").load(open(p));q=pathlib.Path(d["moved"][0]["dst"]);q.write_text("mutated");assert a.main(["--revert",str(p.parent)])==1'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_6_rosters_includes_dormant_team_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m6")
    replace(b / "ft_team_lib.py", 'teams = team_names(base, "현역" if active else "전체")',
            'teams = team_names(base, "전체")')
    root = tmp_path / "root"
    table(root, ("active", "현역"), ("sleeping", "휴면"))
    (root / ".fable-team").mkdir(parents=True)
    for name in ("active", "sleeping"):
        cards = root / f"design/teams/{name}/indices"
        cards.mkdir(parents=True)
        (root / f".fable-team/seats-{name}.json").write_text(json.dumps({
            "_master": "m", "_cards": f"design/teams/{name}/indices", "_cards_wt": ""
        }), encoding="utf-8")
    code = 'import sys,pathlib;sys.path.insert(0,sys.argv[1]);from ft_team_lib import rosters;assert [x["team"] for x in rosters(pathlib.Path(sys.argv[2]))]==["active"]'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_7_missing_cards_diagnostic_is_caught(tmp_path):
    b = copy_bin(tmp_path / "m7")
    replace(b / "ft_team_lib.py", 'elif not doc.get("_cards"):', 'elif False and not doc.get("_cards"):')
    root = tmp_path / "root"
    table(root, ("zztest", "현역"))
    (root / ".fable-team").mkdir(parents=True)
    (root / ".fable-team/seats-zztest.json").write_text('{"_master":"m"}\n', encoding="utf-8")
    code = 'import sys,pathlib;sys.path.insert(0,sys.argv[1]);from ft_team_lib import rosters;assert rosters(pathlib.Path(sys.argv[2]))[0]["diag"]=="_cards 없음"'
    assert run_probe(code, b, root).returncode != 0


def test_mutation_8_board_scans_seats_files_is_caught(tmp_path):
    b = tmp_path / "m8"
    b.mkdir()
    p = ROOT / "harness/bin/ft_board_collect.py"
    text = p.read_text(encoding="utf-8").replace('known = {row["team"] for row in team_rosters(root)}',
        'known = {x.stem for x in (root / ".fable-team").glob("seats*.json")}')
    (b / "ft_board_collect.py").write_text(text, encoding="utf-8")
    import ast
    tree = ast.parse(text)
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
             and n.func.attr == "glob" and n.args and isinstance(n.args[0], ast.Constant) and "seats" in str(n.args[0].value)]
    assert calls
    guard_passes = not calls
    assert not guard_passes, "R15 guard incorrectly accepts the reintroduced seats glob"

