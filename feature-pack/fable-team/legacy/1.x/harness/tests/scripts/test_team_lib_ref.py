"""r479 — ft_team_lib ref 판(team_rows_ref · team_cands_ref · team_in_ref): 명단 = `git show <ref>:design/TEAMS.md` · 폴더 = 그 루트에 실재하는 후보.

격리 임시 git 리포 · 체크아웃 TEAMS.md 는 옛 꼴(planner 1행)이고 ref origin/main 명단은 새 꼴(꼴1·꼴2·꼴3) — 판정이 ref 를 따르는지 본다.
실행: python3 -m pytest tests/scripts/test_team_lib_ref.py -q
"""
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "harness" / "bin"))

import ft_team_lib as tl  # noqa: E402
from _team_fixture import HEAD, write_teams  # noqa: E402

REF_ROWS = "| kk | `design/kk/` | x | 현역 |\n| planner | `design/teams/planner/` | x | 현역 |\n| harness | `$FT_HARNESS_ROOT/design/harness/` | x | 현역 |\n"


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True, timeout=7)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    """ref origin/main = 새 꼴 명단 · 체크아웃 = 옛 꼴 명단(planner 꼴1) — 공유 루트·LIVE_ROOT 어긋남 재현."""
    _git(tmp_path, "init", "-q")
    md = tmp_path / "design" / "TEAMS.md"
    md.parent.mkdir(parents=True)
    md.write_text(HEAD + REF_ROWS, encoding="utf-8")
    _git(tmp_path, "add", "-A")
    _git(tmp_path, "commit", "-qm", "ref")
    _git(tmp_path, "update-ref", "refs/remotes/origin/main", "HEAD")
    write_teams(tmp_path, "planner")  # 체크아웃 사본 = 옛 꼴 1행(미커밋)
    return tmp_path


def test_f_rows_ref_reads_ref_not_checkout(repo: Path) -> None:
    rows = tl.team_rows_ref("origin/main", repo)
    assert rows == {"kk": "design/kk/", "planner": "design/teams/planner/", "harness": "$FT_HARNESS_ROOT/design/harness/"}


def test_f_rows_ref_missing_ref_raises(repo: Path) -> None:
    with pytest.raises(tl.TeamPathError, match="명단 ref 못 읽음"):
        tl.team_rows_ref("origin/없는", repo)


def test_g_cands_ref_only_existing_list_form_first(repo: Path) -> None:
    assert tl.team_cands_ref(repo, "planner") == []
    (repo / "design" / "planner").mkdir()
    assert tl.team_cands_ref(repo, "planner") == [repo / "design" / "planner"]
    (repo / "design" / "teams" / "planner").mkdir(parents=True)
    assert tl.team_cands_ref(repo, "planner") == [repo / "design" / "teams" / "planner", repo / "design" / "planner"]


def test_h_in_ref_exactly_one(repo: Path) -> None:
    (repo / "design" / "planner").mkdir()
    assert tl.team_in_ref(repo, "planner") == repo / "design" / "planner"  # ref 꼴2 · 실재 쌍둥이 꼴1 → 그 1개
    (repo / "design" / "kk").mkdir()
    assert tl.team_in_ref(repo, "kk") == repo / "design" / "kk"


@pytest.mark.parametrize("dirs,n", [((), 0), (("design/planner", "design/teams/planner"), 2)])
def test_h_in_ref_zero_or_two_raises_with_cands(repo: Path, dirs: tuple[str, ...], n: int) -> None:
    for d in dirs:
        (repo / d).mkdir(parents=True)
    with pytest.raises(tl.TeamPathError, match=f"실재 후보 {n}개") as e:
        tl.team_in_ref(repo, "planner")
    assert str(repo / "design" / "teams" / "planner") in str(e.value) and str(repo / "design" / "planner") in str(e.value)


def test_h_in_ref_unknown_team_raises(repo: Path) -> None:
    with pytest.raises(tl.TeamPathError, match="팀 명단\\(origin/main:design/TEAMS.md\\)에 없다"):
        tl.team_in_ref(repo, "v65")


def test_h_in_ref_form3_uses_harness_root(repo: Path, tmp_path_factory: pytest.TempPathFactory, monkeypatch: pytest.MonkeyPatch) -> None:
    hr = tmp_path_factory.mktemp("hr")
    (hr / "design" / "harness").mkdir(parents=True)
    monkeypatch.setenv("FT_HARNESS_ROOT", str(hr))
    assert tl.team_in_ref(repo, "harness") == hr / "design" / "harness"  # 꼴3 = 쌍둥이 0


def test_i_team_in_unchanged_reads_checkout(repo: Path) -> None:
    """기존 team_in 은 그대로 체크아웃 TEAMS.md(옛 꼴) — 함수 추가만 · 변경 0."""
    assert tl.team_in(repo, "planner") == repo / "design" / "planner"
    with pytest.raises(tl.TeamPathError, match="kk 은 팀 명단"):
        tl.team_in(repo, "kk")
