"""r1009 아침 매거진 «끝낸 일» 3결함 — ①수집기가 원격 ops/main-base 를 안 읽음 ②완성 카드가 머리 «- 상태: 대기» 를 실음 ③팀이 «teams».

임시 원격(bare) + 원장 사본(origin/main 만 clone) + 임시 git 리포(이동 도구) 픽스처만 — 실 원격·실 indices·홈 쓰기 0.
계약↔시험 대응표(카드 §계약): C1 ⓐⓑ · C2 ⓒ · C3 ⓓ · C4 ⓔ · C5 회귀(짝 cmp0 · 기존 시험은 따로 돌린다).
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE python3 -m pytest tests/scripts/test_magazine_done_work_r1009.py -q
"""
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _magazine_fakes  # noqa: E402,F401 — slack-mirror 경로를 sys.path 에 올린다

import magazine_celebrate as mc  # noqa: E402
import magazine_collect_detail as mcd  # noqa: E402
from magazine_window import MagazineError  # noqa: E402

HARNESS = Path(__file__).resolve().parents[2]  # feature-pack/fable-team/harness
KST = ZoneInfo("Asia/Seoul")
DAY = "2026-10-27"
START = datetime(2026, 10, 26, 0, 0, tzinfo=KST)
END = datetime(2026, 10, 27, 8, 0, tzinfo=KST)
AT = "2026-10-27T01:00:00+09:00"


def card(name: str, head_state: bool, close: bool, move: bool) -> str:
    lines = [f"# 인덱스: {name} (x 팀 · 설명 — 대기 · 착수 0)", "<!-- ledger: design/x/GOAL.md -->"]
    if head_state:
        lines.append("- 상태: 대기 · spawn = master(pi)")
    if close:
        lines.append(f"- 닫힘 판정문: design/x/VERDICT.md §1 — 완성 이동 = master --landed {name}aa")
    lines += ["", "## 골 원문 (항상 이 3줄)", "골 하나", "", "## 골좌표", "증거", "", "## 배경 (한 단락)", f"{name} 배경 첫 줄", "", "## 상태"]
    lines.append("- 2026-10-27 01:00 — 진행→완성 · DA design/x/VERDICT.md#§1" if move else "- 대기")
    lines.append("- 세트: " + "d" * 40 + " · 시험: pytest rc=0 · 이슈: 0")
    return "\n".join(lines) + "\n"


def sh(cwd: Path, *args: str, when: str = AT) -> str:
    env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
    done = subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *args], capture_output=True, text=True, env=env)
    assert done.returncode == 0, done.stderr
    return done.stdout.strip()


def put(repo: Path, rel: str, text: str) -> None:
    path = repo / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


@pytest.fixture
def copy(tmp_path: Path) -> Path:
    """원격(bare) main + ops/main-base · 사본 = origin/main 만 clone(실 원장 사본과 같은 꼴)."""
    remote, seed = tmp_path / "remote.git", tmp_path / "seed"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(remote)], check=True)
    seed.mkdir()
    sh(seed, "init", "-q", "-b", "main")
    put(seed, "design/x/VERDICT.md", "# 판정문\n## §1 닫힘\n본문\n")
    put(seed, "design/teams/ops/indices/완성/a-close.md", card("a-close", True, True, True))
    sh(seed, "add", "-A")
    sh(seed, "commit", "-qm", "c0")
    put(seed, "design/teams/planner/indices/완성/b-move.md", card("b-move", True, False, True))
    sh(seed, "add", "-A")
    sh(seed, "commit", "-qm", "c1")
    put(seed, "design/v65/indices/완성/c-plain.md", card("c-plain", True, False, False))
    sh(seed, "add", "-A")
    sh(seed, "commit", "-qm", "c2")
    sh(seed, "branch", "ops/main-base")  # 하네스 카드는 여기서 완성된다
    sh(seed, "checkout", "-q", "ops/main-base")
    put(seed, "design/harness/indices/완성/d-ops.md", card("d-ops", True, True, True))
    sh(seed, "add", "-A")
    sh(seed, "commit", "-qm", "o1")
    sh(seed, "push", "-q", str(remote), "main", "ops/main-base")
    sh(tmp_path, "clone", "-q", "--single-branch", "--branch", "main", str(remote), str(tmp_path / "copy"))
    return tmp_path / "copy"


def detail(repo: Path, refs: list[str] | None = None) -> dict:
    return mcd.collect_detail(repo, refs or ["origin/main", "origin/ops/main-base"], START, END, [])


def unit(repo: Path, name: str) -> dict:
    return next(u for u in detail(repo)["units"] if u["path"].endswith(name))


def test_c1_ops_main_base_cards_come_in_by_fetching_the_remote_branch(copy):  # ⓐ
    assert "origin/ops/main-base" in mcd.DEFAULT_REFS  # ① 고친 자리 = 기본 ref 가 «원격 추적» 이름
    d = detail(copy)
    assert {u["path"].rsplit("/", 1)[-1] for u in d["units"]} == {"a-close.md", "b-move.md", "c-plain.md", "d-ops.md"}
    assert sh(copy, "rev-parse", "--verify", "-q", "refs/remotes/origin/ops/main-base")  # 0단계 fetch 가 실제로 받았다
    assert next(u for u in d["units"] if u["path"].endswith("d-ops.md"))["ref"] == "origin/ops/main-base"


def test_c1_missing_remote_branch_is_an_error_not_half_a_list(copy):  # ⓑ
    with pytest.raises(MagazineError, match="fetch 실패"):
        detail(copy, ["origin/main", "origin/no-such-branch"])


def test_c2_team_is_the_name_after_teams_slash_keeping_the_old_shape(copy):  # ⓒ
    teams = {u["path"]: u["team"] for u in detail(copy)["units"]}
    assert teams == {
        "design/teams/ops/indices/완성/a-close.md": "ops",
        "design/teams/planner/indices/완성/b-move.md": "planner",
        "design/v65/indices/완성/c-plain.md": "v65",
        "design/harness/indices/완성/d-ops.md": "harness",
    }


def test_c3_done_line_is_the_verdict_line_never_the_head_state(copy):  # ⓓ
    assert unit(copy, "a-close.md")["done"] == "- 닫힘 판정문: design/x/VERDICT.md §1 — 완성 이동 = master --landed a-closeaa"
    assert unit(copy, "b-move.md")["done"] == "- 2026-10-27 01:00 — 진행→완성 · DA design/x/VERDICT.md#§1"
    assert unit(copy, "c-plain.md")["done"] is None
    assert all("- 상태: 대기" not in (u["done"] or "") for u in detail(copy)["units"])  # 머리 «상태» 줄은 안 싣는다


def test_c3_celebrate_uses_ops_ref_team_and_done_line(copy):
    _, done = mc.collect(str(copy), "HEAD", DAY)
    assert [d.chip for d in done] == ["v65 팀 · 카드 완성", "planner 팀 · 카드 완성", "ops 팀 · 카드 완성", "harness 팀 · 카드 완성"]  # git log = 새 커밋 먼저
    assert [d.what for d in done] == [
        "원문 — c-plain",
        "- 2026-10-27 01:00 — 진행→완성 · DA design/x/VERDICT.md#§1",
        "- 닫힘 판정문: design/x/VERDICT.md §1 — 완성 이동 = master --landed a-closeaa",
        "- 닫힘 판정문: design/x/VERDICT.md §1 — 완성 이동 = master --landed d-opsaa",
    ]
    assert all("— 대기 · 착수 0" not in d.head() + d.fact() for d in done)  # 머리에 섞인 «대기» 글도 안 싣는다


def test_m1_local_ref_name_loses_the_ops_cards(copy, monkeypatch):  # 변이 1 — 고침 전 동작이면 이 시험들이 빨강
    monkeypatch.setattr(mcd, "DEFAULT_REFS", ("origin/main", "ops/main-base"))
    with pytest.raises(MagazineError):  # 사본에 로컬 「ops/main-base」 가지는 없다 — 고침 전 이름이면 수집이 통째로 실패한다
        detail(copy, list(mcd.DEFAULT_REFS))


def test_m2_old_team_split_shows_teams(copy, monkeypatch):  # 변이 2 — teams/ 다음 이름을 안 읽으면 «teams»
    monkeypatch.setattr(mcd, "team_of", lambda path: path.split("/")[1])
    assert detail(copy)["units"] and {u["team"] for u in detail(copy)["units"]} >= {"teams"}
    monkeypatch.undo()
    assert "teams" not in {u["team"] for u in detail(copy)["units"]}


# ── ⓔ 이동 도구 — 완성 갈래만 머리 «- 상태:» 줄을 바꾼다(다른 갈래 불변) ──────────────────────────
MOVE = HARNESS / "bin/ft-index-move.sh"
STUBS = ("ft-index-move.sh", "ft-index-move-canon.sh", "ft-index-move-install.sh", "ft_da_hold_gate.py", "ft_git_capped.py",
         "ft-evidence-inject-scan.sh", "ft-team-lib.sh")


@pytest.fixture
def mover(tmp_path: Path) -> dict:
    """ft-index-move 픽스처 — 기존 test_index_move_rule_line.sh 와 같은 최소 꼴(설치: 없음 · 정본 영향 없음 · 규칙 없음)."""
    bindir, repo = tmp_path / "bin", tmp_path / "repo"
    bindir.mkdir()
    for name in STUBS:
        (bindir / name).write_bytes((HARNESS / "bin" / name).read_bytes())
    (bindir / "ft-index-lint.sh").write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    (tmp_path / "state").mkdir()
    (tmp_path / "home/.claude").mkdir(parents=True)
    put(tmp_path, "home/.claude/CLAUDE.md", "# 전역 지침\n")
    idx = repo / "design/harness/indices"
    for state in ("대기", "진행", "완성"):
        (idx / state).mkdir(parents=True)
    put(repo, "design/TEAMS.md", "| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n")
    sh(repo, "init", "-q", "-b", "main")
    sh(repo, "add", "-A")
    sh(repo, "commit", "-qm", "base")
    put(repo, "design/harness/DA-x.md", "# 판정문\n## §1 닫힘 — c1 c2 c3\n")
    return {"repo": repo, "idx": idx, "bin": bindir, "env": {
        **os.environ, "HOME": str(tmp_path / "home"), "FT_INDEX_STATE_DIR": str(tmp_path / "state"),
        "FT_SEATS_JSON": str(tmp_path / "none.json"), "FT_MBOX": "/bin/true", "FT_LAND_REF": "HEAD",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}}

def make_card(fx: dict, folder: str, name: str, head_state: bool) -> Path:
    lines = [f"# 인덱스: {name}"]
    if head_state:
        lines.append("- 상태: 대기 · spawn = master(pi deepseek flash)")
    lines += ["## 상태", "- 정본 영향 없음: 하네스 도구만 바뀐 카드 — 제품 정본 없음", "- 규칙: 없음 — 시험 fixture 카드(규칙 무관)", "- 설치: 없음"]
    path = fx["idx"] / folder / f"{name}.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def move(fx: dict, *args: str) -> tuple[int, str]:
    done = subprocess.run(["bash", str(fx["bin"] / "ft-index-move.sh"), *args], capture_output=True, text=True, env=fx["env"])
    return done.returncode, (done.stdout + done.stderr).strip()


def head_lines(path: Path) -> list[str]:
    return [ln for ln in path.read_text(encoding="utf-8").split("\n") if not ln.startswith("## ")][:4]


def test_c4_done_move_rewrites_the_head_state_line(mover):  # ⓔ①
    src = make_card(mover, "진행", "c1", head_state=True)
    rc, out = move(mover, str(src), "완성", "--da", f"{mover['repo']}/design/harness/DA-x.md#§1", "--seat", "seat#0")
    assert rc == 0 and "MOVED" in out, out
    moved = mover["idx"] / "완성/c1.md"
    head = head_lines(moved)
    assert head[0] == "# 인덱스: c1" and head[1].startswith("- 상태: 완성 · ") and head[1].endswith(" · seat#0"), head
    assert "HEAD-STATE 완성" in out


def test_c4_done_move_without_a_head_state_line_adds_nothing(mover):  # ⓔ②
    src = make_card(mover, "진행", "c2", head_state=False)
    rc, out = move(mover, str(src), "완성", "--da", f"{mover['repo']}/design/harness/DA-x.md#§1")
    assert rc == 0 and "MOVED" in out, out
    moved = mover["idx"] / "완성/c2.md"
    assert not any(ln.startswith("- 상태:") for ln in head_lines(moved)) and "HEAD-STATE" not in out


def test_c4_wait_to_progress_leaves_the_head_state_line_alone(mover):  # ⓔ③
    src = make_card(mover, "대기", "c3", head_state=True)
    rc, out = move(mover, str(src), "진행", "--seat", "seat#0")
    assert rc == 0 and "MOVED" in out, out
    assert head_lines(mover["idx"] / "진행/c3.md")[1] == "- 상태: 대기 · spawn = master(pi deepseek flash)" and "HEAD-STATE" not in out


def test_c5_kit_and_bin_copies_stay_identical():  # C5 회귀 칸
    kit = HARNESS / "kit/fable-team/bin/ft-index-move.sh"
    assert kit.read_bytes() == MOVE.read_bytes()
