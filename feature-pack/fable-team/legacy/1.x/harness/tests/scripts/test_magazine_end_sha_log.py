"""R111 ① — 이력(log)도 창 끝 sha 에서: 창 끝 «뒤» 병합된 옆가지 파일은 그날 실제 상태에 없으므로 싣지도, 읽다 죽지도 않는다.

임시 git 리포: M0(창 앞) → M1(창 안·끝 sha) / 옆가지 S(창 안, M0 에서 갈림) → 병합 M2(창 뒤).
실행: python3 -m pytest tests/scripts/test_magazine_end_sha_log.py -q
"""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _magazine_fakes import KIT  # noqa: E402,F401
import magazine_collect_detail as mcd  # noqa: E402
import magazine_collect_open as mco  # noqa: E402

KST = ZoneInfo("Asia/Seoul")
START, END = datetime(2026, 10, 12, 8, tzinfo=KST), datetime(2026, 10, 13, 8, tzinfo=KST)
SIDE_FILES = {
    "design/loom/DA-side-20261012.md": "# DA\nHOLD 옆가지\n",
    "design/loom/BRIEFING-side-20261012.md": "옆가지 브리핑\n",
    "design/loom/indices/완성/side-card.md": "# 인덱스: side-card\n",
}
EARLY_FILES = {
    "design/loom/DA-early-20261012.md": "# DA\nHOLD 창 끝 전\n",
    "design/loom/BRIEFING-early-20261012.md": "창 끝 전 브리핑\n",
}


def run(repo: Path, when: str, *args: str) -> None:
    env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when}
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True, env=env)


def commit_files(repo: Path, when: str, files: dict[str, str]) -> None:
    for path, text in files.items():
        (repo / path).parent.mkdir(parents=True, exist_ok=True)
        (repo / path).write_text(text, encoding="utf-8")
    run(repo, when, "add", "-A")
    run(repo, when, "commit", "-q", "-m", "c")


def make_repo(tmp_path: Path, late_main: bool = True) -> Path:
    r = tmp_path / "r"
    r.mkdir()
    run(r, "2026-10-11T09:00:00+09:00", "init", "-q", "-b", "main")
    commit_files(r, "2026-10-11T09:00:00+09:00", {"README.md": "x\n"})  # M0
    run(r, "2026-10-12T10:00:00+09:00", "checkout", "-q", "-b", "side")
    commit_files(r, "2026-10-12T12:00:00+09:00", SIDE_FILES)  # S
    run(r, "2026-10-12T12:00:00+09:00", "checkout", "-q", "main")
    commit_files(r, "2026-10-12T11:00:00+09:00", EARLY_FILES)  # M1 = 창 끝 sha (S 는 조상 아님)
    if late_main:  # 없으면 창 끝 뒤 병합의 두 부모(M1·S) 중 날짜가 늦은 S 를 rev-list 가 창 끝으로 고른다
        commit_files(r, "2026-10-12T20:00:00+09:00", {"README.md": "y\n"})
    run(r, "2026-10-14T09:00:00+09:00", "merge", "-q", "--no-ff", "-m", "m", "side")  # M2 = 창 뒤 병합
    return r


def infos(r: Path) -> list[dict[str, object]]:
    return mcd.resolve_refs(r, ["main"], START, END)


def test_e1_detail_appendix_skips_files_merged_after_window_end(tmp_path):
    r = make_repo(tmp_path)
    paths = [a["path"] for a in mcd.collect_detail(r, ["main"], START, END, [])["appendix"]]
    assert paths == ["design/loom/BRIEFING-early-20261012.md"]  # 창 끝 뒤 병합분 미포함(rc 128 아님) · 창 끝 전 병합분은 포함(회귀)


def test_e2_open_holds_skip_files_merged_after_window_end(tmp_path):
    r = make_repo(tmp_path)
    holds = mco._holds(r, infos(r), [f"--since={START.isoformat()}", f"--until={END.isoformat()}"])
    assert [h["path"] for h in holds] == ["design/loom/DA-early-20261012.md"]


def test_e3_detail_units_skip_cards_merged_after_window_end(tmp_path):
    r = make_repo(tmp_path)
    span = [f"--since={START.isoformat()}", f"--until={END.isoformat()}"]
    units, malformed = mcd._units(r, infos(r), span, report=True)
    assert [m["path"] for m in malformed + units if "side-card" in str(m["path"])] == []


def test_e4_end_sha_follows_first_parent_when_side_branch_is_newer_than_main_tip(tmp_path):
    r = make_repo(tmp_path, late_main=False)
    first_parent = mcd.git(r, "rev-list", "-1", "--first-parent", f"--before={END.isoformat()}", "main").strip()
    assert str(infos(r)[0]["end_sha"]) == first_parent  # 옆가지 커밋(S)이 창 끝이 되면 안 된다
    paths = [a["path"] for a in mcd.collect_detail(r, ["main"], START, END, [])["appendix"]]
    holds = mco._holds(r, infos(r), [f"--since={START.isoformat()}", f"--until={END.isoformat()}"])
    assert paths == ["design/loom/BRIEFING-early-20261012.md"] and [h["path"] for h in holds] == ["design/loom/DA-early-20261012.md"]
