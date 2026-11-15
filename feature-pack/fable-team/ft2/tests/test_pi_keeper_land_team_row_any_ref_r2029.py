"""r2029 keeper — Landing._cards() 는 팀 행이 있는 ref 만 읽는다 · 두 ref 모두 없을 때만 판정 불가.
가짜 git 실행기(실 리포 0) · T1~T5 · TEAMS.md show rc≠0 = 판정 불가(건너뜀 아님 · 하드 룰 20).
"""
import importlib.util
from pathlib import Path

_PATH = Path(__file__).resolve().parents[1] / "adapters" / "pi" / "keeper_land.py"
_SPEC = importlib.util.spec_from_file_location("keeper_land_r2029", str(_PATH))
kl = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(kl)

OPS, MAIN = kl.REFS
ROW = "| team | folder |\n|---|---|\n| knowledge | design/teams/knowledge/ |\n"
NOROW = "| team | folder |\n|---|---|\n| harness | design/teams/harness/ |\n"


def landing(teams, cards):
    """teams = {ref: (rc, TEAMS.md)} · cards = {ref: [경로…]} → Landing (git 만 가짜)."""
    calls = []

    def git(root, *args):
        calls.append(args)
        if args[0] == "show":
            return teams[args[1].split(":")[0]] + ("",)
        ref, folder = args[3], args[5].rsplit("/indices", 1)[0]
        return 0, "\n".join(p for p in cards.get(ref, []) if p.startswith(folder + "/")), ""

    obj = kl.Landing.__new__(kl.Landing)
    obj.root, obj.git, obj.cache, obj.calls = "/byz", git, {}, calls
    return obj


CARD = "design/teams/knowledge/indices/대기/v65.md"


def test_t1_ops_no_row_main_row():
    got = landing({OPS: (0, NOROW), MAIN: (0, ROW)}, {MAIN: [CARD]})._cards("knowledge")
    assert got == [(MAIN, CARD)]


def test_t2_ops_row_main_no_row():
    got = landing({OPS: (0, ROW), MAIN: (0, NOROW)}, {OPS: [CARD]})._cards("knowledge")
    assert got == [(OPS, CARD)]


def test_t3_both_no_row():
    got = landing({OPS: (0, NOROW), MAIN: (0, NOROW)}, {})._cards("knowledge")
    assert isinstance(got, str) and got.startswith("판정 불가") and "팀 행 없음" in got


def test_t4_ops_show_rc128_is_unsure():
    got = landing({OPS: (128, ""), MAIN: (0, ROW)}, {MAIN: [CARD]})._cards("knowledge")
    assert isinstance(got, str) and got.startswith("판정 불가") and "rc 128" in got


def test_t5_both_rows_sum():
    other = "design/teams/knowledge/indices/진행/v66.md"
    got = landing({OPS: (0, ROW), MAIN: (0, ROW)}, {OPS: [CARD], MAIN: [other]})._cards("knowledge")
    assert got == [(OPS, CARD), (MAIN, other)]
