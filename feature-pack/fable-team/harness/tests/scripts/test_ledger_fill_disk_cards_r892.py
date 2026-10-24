"""r892 r3 뉴스 원장 채움 — 하네스 카드($FT_HARNESS_ROOT 꼴 팀)도 디스크 훑기 대신 그 워크트리 HEAD 커밋 한 판에서 읽기 ⓙ~ⓛ.
r1·r2 디스크 훑기 시험(이동 중 건너뜀·재훑기·scandir·읽기 실패 꼬리)은 삭제 — 그 코드가 없어졌다(경쟁 자체 0 · DA⑥ r2 재설계).
임시 하네스 리포(git init · 진행·대기·완성 카드 3장씩 커밋) · 실 원장·mbox 0.
실행: python3 -m pytest tests/scripts/test_ledger_fill_disk_cards_r892.py -q   (ⓕ 변이 = evidence/r892/mutation.sh)
"""
import os
import subprocess
import threading
from datetime import timedelta
from pathlib import Path

import pytest

from test_ledger_fill_r851 import NOW, fill, guard_begin_module, origin_ledger, run, section, world  # noqa: F401  r851 픽스처 그대로
import ft_ledger_fill_src as src

TEAMS = "| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` | byz-harness-master-claude | 현역 |\n"
MAIN: list = [None]  # 팀 명단 리포(시험마다 teams_repo 가 채움)


@pytest.fixture
def hrepo(tmp_path, monkeypatch):
    h = tmp_path / "h"
    base = h / "design/harness/indices"
    for state in ("진행", "대기", "완성"):
        (base / state).mkdir(parents=True)
        for n in (1, 2, 3):
            (base / state / f"{state}{n}.md").write_text(f"# 인덱스: {state}{n} — {state} 일 {n}\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main", str(h)], check=True)
    run(h, "add", "-A")
    run(h, "commit", "-qm", "cards")
    monkeypatch.setenv("FT_HARNESS_ROOT", str(h))
    return h


@pytest.fixture(autouse=True)
def teams_repo(tmp_path):
    """팀 명단 리포(하네스 1줄 · $FT_HARNESS_ROOT 꼴) — cards() 는 team_cards 전체 경로를 탄다."""
    m = tmp_path / "main"
    (m / "design").mkdir(parents=True)
    (m / "design/TEAMS.md").write_text(TEAMS, encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main", str(m)], check=True)
    run(m, "add", "-A")
    run(m, "commit", "-qm", "teams")
    MAIN[0] = m


def cards():
    return src.team_cards(MAIN[0], "HEAD", NOW)["harness"]


def test_j_cards_moving_on_disk_count_equals_fixed_sha(hrepo):
    """디스크에서 카드를 진행↔대기로 계속 옮기는 중(대역 스레드)에도 결과 = 고정 sha 의 카드 수 정확히(경쟁 0)."""
    base, stop, moves = hrepo / "design/harness/indices", threading.Event(), [0]

    def shuffle():
        a, b = base / "진행/진행2.md", base / "대기/진행2.md"
        while not stop.is_set():
            a.rename(b)
            b.rename(a)
            moves[0] += 1
    t = threading.Thread(target=shuffle, daemon=True)
    t.start()
    try:
        got = [cards() for _ in range(20)]
    finally:
        stop.set()
        t.join(5)
    assert moves[0] > 0
    for c in got:
        assert [n for n, _ in c["진행"]] == ["진행1", "진행2", "진행3"] and c["대기"] == 3  # 20번 다 고정 sha 판 그대로
    assert len(got[0]["착지"]) == 3


def test_j_uncommitted_move_seen_after_commit(hrepo):
    """알려진 한계 — 커밋 안 된 이동은 안 보임 · 커밋 뒤 다음 읽기부터 보인다."""
    run(hrepo, "mv", "design/harness/indices/진행/진행2.md", "design/harness/indices/대기/진행2.md")
    assert len(cards()["진행"]) == 3
    run(hrepo, "commit", "-qm", "move")
    c = cards()
    assert [n for n, _ in c["진행"]] == ["진행1", "진행3"] and c["대기"] == 4


@pytest.mark.parametrize("how", ["no_env", "not_git", "missing", "no_commit"])
def test_k_harness_root_broken_is_fill_error(tmp_path, monkeypatch, how):
    if how == "no_env":
        monkeypatch.delenv("FT_HARNESS_ROOT", raising=False)
    else:
        d = tmp_path / "h"
        if how != "missing":
            d.mkdir()
        if how == "no_commit":
            subprocess.run(["git", "init", "-q", str(d)], check=True)
        monkeypatch.setenv("FT_HARNESS_ROOT", str(d))
        monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path))  # tmp 위 리포로 올라가 찾기 0
    with pytest.raises(src.FillError):
        cards()


def test_l_done_card_added_in_window_is_landed_even_via_git_mv(hrepo):
    """착지 창 안 완성/ 추가 카드 = 착지 목록 — 진행→완성 git mv(이름 바꾸기)도 완성/ 기준 «추가»."""
    old = {"GIT_COMMITTER_DATE": f"{NOW - timedelta(days=3):%Y-%m-%dT%H:%M:%S}", "GIT_AUTHOR_DATE": f"{NOW - timedelta(days=3):%Y-%m-%dT%H:%M:%S}"}
    run(hrepo, "commit", "-q", "--amend", "--no-edit", "--date", old["GIT_AUTHOR_DATE"], env=old)  # 처음 카드 = 창 밖
    assert cards()["착지"] == []
    run(hrepo, "mv", "design/harness/indices/진행/진행2.md", "design/harness/indices/완성/진행2.md")
    run(hrepo, "commit", "-qm", "land")
    c = cards()
    assert [n for n, _ in c["착지"]] == ["진행2"] and [n for n, _ in c["진행"]] == ["진행1", "진행3"]


def test_l_subfolder_harness_root_uses_repo_prefix(tmp_path, monkeypatch):
    """FT_HARNESS_ROOT 가 리포 하위 폴더 — 경로 = 리포 루트 기준 prefix + design/harness/."""
    repo = tmp_path / "r"
    card = repo / "sub/design/harness/indices/진행/x1.md"
    card.parent.mkdir(parents=True)
    card.write_text("# 인덱스: x1 — 하위 폴더 카드\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    run(repo, "add", "-A")
    run(repo, "commit", "-qm", "c")
    monkeypatch.setenv("FT_HARNESS_ROOT", str(repo / "sub"))
    assert cards()["진행"] == [("x1", "하위 폴더 카드")]


def test_world_fill_harness_row_from_git_and_tables_unchanged(world, monkeypatch):  # noqa: F811 — r851 픽스처
    """r851 world 전체 채움 — 하네스 행 = 하네스 리포 HEAD 판 · 디스크에만 있는(미커밋) 카드는 안 셈 · 오류 줄 0."""
    h = Path(os.environ["FT_HARNESS_ROOT"])
    (h / "design/harness/indices/진행/uncommitted.md").write_text("# 인덱스: uncommitted — 미커밋 카드\n", encoding="utf-8")
    rc, sha = fill(world)
    team = section(origin_ledger(world), "## 3. 팀 작업")
    assert rc == 0 and sha
    assert any(ln.startswith("| 하네스 | 진행 1장 — «원장 자동 채움»") for ln in team) and not any("미커밋 카드" in ln for ln in team)
