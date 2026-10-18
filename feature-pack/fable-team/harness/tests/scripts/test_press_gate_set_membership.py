"""press-gate ① 미랜딩 나노 «세트 소속» 표시 (M7 · 오빠 HIL #3 · 차단 기준 불변 — 표시만).

카드: design/v65/indices/진행/M7-press-gate-unlanded-nano-set-membership-display.md §구현 범위·§완료 조건
  ⓐ 되돌린 커밋 + merge 만 남은 브랜치 → ⊘(순 변경 0) · ✗ 는 현행 그대로
  ⓑ worker 순 변경 → ⊕ + 파일 목록 + ✗ 그대로
  ⓒ tests/e2e 만 → ⊕ · ✗ 0(① 이 tests/ 를 빼는 현행 차단 기준 불변)
  ⓓ SET_PATHS 는 ft-press-set-check.sh 한 곳 — 거기서 바꾸면 gate 표시도 따라 바뀐다(복사 정의 0)
격리: 임시 git 저장소 + 가짜 tmux(PATH) + 가짜 seats.json — 실 저장소·tmux·seats.json 접촉 0.
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest
from ft_git_helpers import BIN, commit, git, init_repo

SET_MARK, OUT_MARK = "⊕ press 세트 포함 예정", "⊘ 세트 밖"


@pytest.fixture
def fake(tmp_path):
    root = init_repo(tmp_path / "root")
    commit(root, {"worker/w.py": "w", "tests/e2e/r.py": "r", "docs/d.md": "d"}, "set files")
    (root / ".fable-team").mkdir()
    (root / ".worktrees").mkdir()
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    (fakebin / "tmux").write_text('#!/bin/sh\nprintf "%s\\n" $FT_FAKE_TMUX_SESSIONS\n')
    (fakebin / "tmux").chmod(0o755)
    return root, fakebin


def _nano(root, name):
    git(root, "worktree", "add", "-q", "-b", f"nano/{name}", str(root / ".worktrees" / f"v65-{name}"), "feat")
    return root / ".worktrees" / f"v65-{name}"


def _gate(fake, names, bindir=BIN):
    root, fakebin = fake
    seats = ",".join(f'"ft-v65-temp-{n}#0":{{"role":"nano"}}' for n in names)
    (root / ".fable-team" / "seats.json").write_text("{" + seats + "}")
    env = {**os.environ, "PATH": f"{fakebin}:{os.environ['PATH']}", "FT_PRESS_ROOT": str(root), "FT_PRESS_WT": str(root), "FT_NANO_FEAT": "feat",
           "FT_FAKE_TMUX_SESSIONS": " ".join(f"ft-v65-temp-{n}#0" for n in names)}
    return subprocess.run(["bash", str(bindir / "ft-press-gate.sh")], capture_output=True, text=True, env=env, timeout=120)


def test_relative_invocation_still_shows_membership(fake):  # 라이브 실측(10-03): `bash .worktrees/…/ft-press-gate.sh` 처럼 상대경로로 불러도 cd 뒤 set-check 를 찾는다
    root, fakebin = fake
    wt = _nano(root, "f")
    commit(wt, {"worker/w.py": "w-changed"}, "[fix] worker change")
    (root / ".fable-team" / "seats.json").write_text('{"ft-v65-temp-f#0":{"role":"nano"}}')
    env = {**os.environ, "PATH": f"{fakebin}:{os.environ['PATH']}", "FT_PRESS_ROOT": str(root), "FT_PRESS_WT": str(root), "FT_NANO_FEAT": "feat",
           "FT_FAKE_TMUX_SESSIONS": "ft-v65-temp-f#0"}
    r = subprocess.run(["bash", "./ft-press-gate.sh"], capture_output=True, text=True, env=env, cwd=BIN, timeout=120)
    out = _section1(r)
    assert any(ln.startswith("  ⊕ press 세트 포함 예정") for ln in out) and not any(ln.startswith("  ⚠") for ln in out), r.stdout


def _section1(r):
    return [ln for ln in r.stdout.splitlines() if ln.startswith(("✓ 미랜딩", "✗ 미랜딩", "  ⊕", "  ⊘", "  ⚠", "  ·"))]


def test_reverted_plus_merge_only_is_outside_set(fake):  # ⓐ
    root, _ = fake
    wt = _nano(root, "a")
    sha = commit(wt, {"worker/w.py": "w-changed"}, "[fix] worker change")
    git(wt, "revert", "--no-edit", sha)
    commit(root, {"worker/feat_a.py": "a"}, "feat moves")
    git(wt, "merge", "-q", "--no-edit", "feat")
    commit(root, {"worker/feat_b.py": "b"}, "feat moves on")  # merge «뒤» feat 가 세트 경로를 앞서가야 2점(..)이 ⊕ 로 오탐한다
    r = _gate(fake, ["a"])
    out = _section1(r)
    assert any(ln.startswith("  ⊘ 세트 밖") for ln in out), r.stdout
    assert not any(SET_MARK in ln for ln in out), r.stdout
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 3") for ln in out), r.stdout  # 차단 기준 불변 — 변경·되돌림·merge 3건을 현행대로 센다(카드 실측: k4-003)
    assert r.returncode == 1


def test_worker_net_change_is_in_set_and_still_blocks(fake):  # ⓑ
    root, _ = fake
    wt = _nano(root, "b")
    commit(wt, {"worker/w.py": "w-changed"}, "[fix] worker change")
    r = _gate(fake, ["b"])
    out = _section1(r)
    assert any(ln.startswith("  ⊕ press 세트 포함 예정") and "worker/w.py" in ln for ln in out), r.stdout
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out), r.stdout
    assert r.returncode == 1


def test_runner_only_is_in_set_without_new_block(fake):  # ⓒ
    root, _ = fake
    wt = _nano(root, "c")
    commit(wt, {"tests/e2e/r.py": "r-changed"}, "[test] runner knob")
    r = _gate(fake, ["c"])
    out = _section1(r)
    assert any(ln.startswith("  ⊕ press 세트 포함 예정") and "tests/e2e/r.py" in ln for ln in out), r.stdout
    assert "✓ 미랜딩 제품 커밋 0" in out and not any(ln.startswith("✗ 미랜딩") for ln in out), r.stdout


def test_file_list_is_capped_at_five(fake):
    root, _ = fake
    wt = _nano(root, "d")
    commit(wt, {f"worker/f{i}.py": "x" for i in range(7)}, "[feature] many")
    line = next(ln for ln in _section1(_gate(fake, ["d"])) if "⊕" in ln)
    assert "+2" in line and line.count("worker/f") == 5, line


def test_set_paths_single_source_in_set_check(fake, tmp_path):  # ⓓ
    root, _ = fake
    wt = _nano(root, "e")
    commit(wt, {"docs/d.md": "changed"}, "[docs] doc only")
    assert any(ln.startswith("  ⊘") for ln in _section1(_gate(fake, ["e"])))  # 현행 세트에서 docs/ 는 밖
    alt = Path(tempfile.mkdtemp(dir=tmp_path))
    for n in ("ft-press-gate.sh", "ft-press-set-check.sh"):
        shutil.copy(BIN / n, alt / n)
    chk = alt / "ft-press-set-check.sh"
    chk.write_text(chk.read_text().replace("SET_PATHS=(worker ", "SET_PATHS=(docs worker "))
    out = _section1(_gate(fake, ["e"], bindir=alt))
    assert any(ln.startswith("  ⊕") and "docs/d.md" in ln for ln in out), out  # gate 는 복사 정의 없이 따라 바뀐다
