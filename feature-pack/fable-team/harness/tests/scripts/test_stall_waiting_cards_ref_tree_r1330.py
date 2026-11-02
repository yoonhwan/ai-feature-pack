"""r1330 — ft-stall-scan a(대기 카드 있는데 팀장 유휴)가 대기·진행 카드를 «기준 ref 트리» 에서 읽는다(디스크 체크아웃이 뒤처져도 옛 카드 0).

S1 옛 카드(디스크만 대기) 0 · S2 디스크 대기 0 이어도 ref 대기 카드 잡음 · S3 선행 대조도 ref ·
S4 git 상한 넘김 = 그 팀 «a? … 판정 불가» 1줄 + a 0 (다른 팀 그대로) · S5 roots.tsv «기준 ref» 를 읽음 · S6 디스크=ref 면 기준판과 출력이 같음.
R1330_BIN = 시험할 bin 폴더(기본 kit) · R1330_BASE_BIN = 기준판 bin(S6 바이트 대조 · 없으면 S6 은 기대 문장만 본다).
네트워크 0 · 실 루트 0 · 임시 리포(bare origin + 체크아웃) · 자기 재호출 0.
"""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from _stall_world import World, counts
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BIN = Path(os.environ.get("R1330_BIN") or Path(__file__).resolve().parents[2] / "kit/fable-team/bin")
BASE_BIN = os.environ.get("R1330_BASE_BIN")
GIT = shutil.which("git") or "git"
GENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "LC_ALL": "C"}
OK = "# {n}\n- 선행: 없음\n"


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def git(cwd: Path, *args: str) -> str:
    r = subprocess.run([GIT, *args], cwd=cwd, env=GENV, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0, (args, r.stderr)
    return r.stdout.strip()


def put(wt: Path, label: str, files: dict[str, str]) -> None:
    base = wt / f"design/{label}/indices"
    shutil.rmtree(base, ignore_errors=True)
    for rel, text in files.items():
        _ = (base / rel).parent.mkdir(parents=True, exist_ok=True)
        _ = (base / rel).write_text(text, encoding="utf-8")


def repo(w: World, label: str, disk: dict[str, str], ref: dict[str, str], extra_ref: dict[str, str] | None = None) -> Path:
    """그 팀 카드 체크아웃 = 리포 · 디스크는 C1(disk) · origin/main 은 C2(ref) · feature/x 는 extra_ref(있을 때). 체크아웃은 C1 에 머문다(뒤처짐)."""
    wt = w.root / f".worktrees/wt-{label}"
    origin = wt.parent.parent.parent / f"origin-{label}.git"
    git(wt.parent, "init", "-q", "--bare", "-b", "main", str(origin))
    git(wt, "init", "-q", "-b", "main")
    git(wt, "remote", "add", "origin", str(origin))
    put(wt, label, disk)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "-m", "c1 disk")
    c1 = git(wt, "rev-parse", "HEAD")
    put(wt, label, ref)
    git(wt, "add", "-A")
    git(wt, "commit", "-q", "--allow-empty", "-m", "c2 ref")
    git(wt, "push", "-q", "origin", "main")
    if extra_ref is not None:
        put(wt, label, extra_ref)
        git(wt, "add", "-A")
        git(wt, "commit", "-q", "--allow-empty", "-m", "c3 feature")
        git(wt, "update-ref", "refs/heads/feature/x", "HEAD")
    git(wt, "reset", "-q", "--hard", c1)
    return wt


def scan(w: World, bin_dir: Path | str | None = None) -> subprocess.CompletedProcess[str]:
    w.state("t1-master#1", "IDLE", 5)
    return subprocess.run(["bash", str(Path(bin_dir or BIN) / "ft-stall-scan.sh"), "--dry-run"], env=w.env, capture_output=True, text=True, timeout=60)


def cards(a: dict[str, str] | None = None, **kinds: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for kind, names in kinds.items():
        for n in names:
            out[f"{kind}/{n}.md"] = (a or {}).get(n, OK.format(n=n))
    return out


def test_s1_old_card_only_on_disk_is_not_counted(w: World) -> None:
    repo(w, "t1", cards(대기=["old", "new"]), cards(대기=["new"], 완성=["old"]))
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and "대기 카드 1장(new)" in r.stdout and "old" not in r.stdout.split("대기 카드", 1)[1], r.stdout


def test_s2_empty_disk_waiting_but_ref_has_card(w: World) -> None:
    repo(w, "t1", cards(진행=["busy"]), cards(대기=["x"], 진행=["busy"]))
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and "대기 카드 1장(x)" in r.stdout, r.stdout


def test_s3_prerequisite_checked_against_ref_trees(w: World) -> None:
    y = {"y": "# y\n- 선행: indices/진행/z.md\n"}
    repo(w, "t1", cards(y, 대기=["y"]), cards(y, 대기=["y"], 진행=["z"]))  # ref 진행/ 에만 z — 디스크에는 없음
    r = scan(w)
    assert counts(r.stdout)["a"] == "0", r.stdout


def test_s4_git_over_budget_is_one_undecided_line_and_other_team_stays(w: World, tmp_path: Path) -> None:
    w.team("t2", "t2-master#1", ["t2-nano#0"])
    repo(w, "t1", cards(대기=["a"]), cards(대기=["a"]))
    repo(w, "t2", cards(대기=["b"]), cards(대기=["b"]))
    shim = w.stub / "shim"
    _ = (shim / "git").write_text(f'#!/bin/sh\ncase "$PWD" in */wt-t1/*) [ "$1" = ls-tree ] && sleep 1;; esac\nexec {GIT} "$@"\n')
    (shim / "git").chmod(0o755)
    w.env["FT_STALL_GIT_SEC"] = "0.2"
    w.state("t2-master#1", "IDLE", 5)
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and "a? t1 대기 카드 판정 불가 — git 상한 넘김" in r.stdout, r.stdout
    assert "t2-master#1" in r.stdout and "대기 카드 1장(b)" in r.stdout, r.stdout


def test_s5_roots_tsv_basis_ref_is_read(w: World, tmp_path: Path) -> None:
    repo(w, "t1", cards(대기=["a"]), cards(대기=["a"]), extra_ref=cards(대기=["b"]))
    tsv = tmp_path / "roots.tsv"
    _ = tsv.write_text(f"r1330\t{w.root}\t현역\tfeature/x\t.\t기본\n", encoding="utf-8")
    w.env["FT_ROOTS_TSV"] = str(tsv)
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and "대기 카드 1장(b)" in r.stdout, r.stdout


def test_s6_disk_equals_ref_output_same_as_base(w: World) -> None:
    repo(w, "t1", cards(대기=["a", "b"]), cards(대기=["a", "b"]))
    r = scan(w)
    assert counts(r.stdout)["a"] == "1" and "대기 카드 2장(a, b)" in r.stdout, r.stdout
    if BASE_BIN:
        base = scan(w, BASE_BIN)
        assert r.stdout == base.stdout and r.returncode == base.returncode
