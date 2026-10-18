"""ft-nano-cherry-gate.sh 합성 시험 — 격리 임시 git 저장소만 쓴다 (DA 575 H1/H2 회귀 포함)."""

import os
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

GATE = Path(__file__).resolve().parents[3] / "harness" / "bin" / "ft-nano-cherry-gate.sh"
REAL_GIT: str = shutil.which("git") or "git"


def _git(repo: Path, *args: str) -> str:
    env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    return subprocess.run([REAL_GIT, "-C", str(repo), *args], check=True, capture_output=True, text=True, env=env).stdout


def _commit(repo: Path, files: dict[str, str], msg: str) -> None:
    for rel, body in files.items():
        p = repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", msg)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    r = tmp_path / "repo"
    r.mkdir()
    _git(r, "init", "-q", "-b", "feat")
    _commit(r, {"base.txt": "base"}, "base")
    _git(r, "branch", "nano", "feat")
    _git(r, "checkout", "-q", "nano")
    return r


def _run(repo: Path, path_prefix: Path | None = None) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env['PATH']}"
    return subprocess.run(["bash", str(GATE), "feat", "nano", "--repo", str(repo)], capture_output=True, text=True, env=env)


def test_no_plus_commits_is_ok(repo: Path) -> None:
    r = _run(repo)
    assert r.returncode == 0 and r.stdout.startswith("OK")


def test_design_only_commit_warns_and_passes(repo: Path) -> None:
    _commit(repo, {"design/a.md": "x"}, "docs only")
    r = _run(repo)
    assert r.returncode == 0 and r.stdout.startswith("WARN")


def test_code_commit_rejects(repo: Path) -> None:
    _commit(repo, {"a.py": "x"}, "code")
    r = _run(repo)
    assert r.returncode == 1 and r.stdout.startswith("REJECT")


def test_missing_ref_rejects(repo: Path) -> None:
    r = subprocess.run(["bash", str(GATE), "feat", "nope", "--repo", str(repo)], capture_output=True, text=True)
    assert r.returncode == 1 and "브랜치 없음" in r.stdout


def test_diff_tree_failure_rejects(repo: Path, tmp_path: Path) -> None:
    """H1: diff-tree 가 exit 128 이면 WARN 통과가 아니라 REJECT."""
    _commit(repo, {"a.py": "x"}, "code")
    wrap = tmp_path / "wrap"
    wrap.mkdir()
    shim = wrap / "git"
    shim.write_text(f'#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = diff-tree ] && exit 128; done\nexec {REAL_GIT} "$@"\n')
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    r = _run(repo, wrap)
    assert r.returncode == 1 and "diff-tree 실패" in r.stdout


def test_large_mixed_commit_rejects(repo: Path) -> None:
    """H2: 코드 1 + design/ 긴 경로 5000 개 한 커밋 — 파이프 SIGPIPE 로 design 만 판정되던 구멍."""
    files = {"aaa.py": "x"}
    files.update({f"design/v65/{'long-name-segment-' * 4}{i:05d}.md": "d" for i in range(5000)})
    _commit(repo, files, "mixed")
    r = _run(repo)
    assert r.returncode == 1 and r.stdout.startswith("REJECT")


# --- G4c: git cherry «+» 여도 merge-tree 결과가 feat 와 같으면 «내용 랜딩됨» PASS ---


def _lines(**over: str) -> str:
    return "\n".join(over.get(f"l{i}", f"line{i}") for i in range(1, 9)) + "\n"


def _nano_edits_line5(repo: Path) -> None:
    """feat 에 f.py(8줄) → nano 가 5번째 줄을 고친다. 끝나면 feat 로 돌아와 있다."""
    _git(repo, "checkout", "-q", "feat")
    _commit(repo, {"f.py": _lines()}, "add f.py")
    _git(repo, "checkout", "-q", "nano")
    _git(repo, "merge", "-q", "--ff-only", "feat")
    _commit(repo, {"f.py": _lines(l5="NANO")}, "nano edits line5")
    _git(repo, "checkout", "-q", "feat")


def _cherry_pick_nano_onto_feat_with_other_context(repo: Path) -> None:
    """feat 가 2번째 줄(주석)을 먼저 고친 뒤 nano 커밋을 cherry-pick → 문맥이 달라 patch-id ≠ (오늘 모양)."""
    _commit(repo, {"f.py": _lines(l2="# feat comment")}, "feat comment line2")
    _git(repo, "cherry-pick", "nano")


def test_context_differing_cherry_pick_passes(repo: Path) -> None:
    """① 오늘 모양 — cherry 는 «+» 인데 내용은 feat 에 들어와 있다 → PASS(content_landed_via_merge_tree)."""
    _nano_edits_line5(repo)
    _cherry_pick_nano_onto_feat_with_other_context(repo)
    assert _git(repo, "cherry", "feat", "nano").startswith("+"), "전제: patch-id 가 달라야 한다"
    r = _run(repo)
    assert r.returncode == 0 and "content_landed_via_merge_tree" in r.stdout


def test_unlanded_code_still_rejects_when_feat_moved(repo: Path) -> None:
    """② 미랜딩 코드 커밋 — feat 가 다른 파일을 고쳐 앞서 있어도 REJECT."""
    _nano_edits_line5(repo)
    _commit(repo, {"other.py": "y"}, "feat moves on")
    r = _run(repo)
    assert r.returncode == 1 and r.stdout.startswith("REJECT") and "f.py" in r.stdout


def test_feat_edited_same_file_later_passes(repo: Path) -> None:
    """③ cherry-pick 뒤 feat 가 같은 파일의 다른 줄을 더 고침(브랜치 변경은 포함) → PASS."""
    _nano_edits_line5(repo)
    _cherry_pick_nano_onto_feat_with_other_context(repo)
    _commit(repo, {"f.py": _lines(l2="# feat comment", l5="NANO", l8="feat later")}, "feat later edit")
    r = _run(repo)
    assert r.returncode == 0 and "content_landed_via_merge_tree" in r.stdout


def test_merge_conflict_rejects(repo: Path) -> None:
    """④ 같은 줄을 서로 다르게 고침 → merge-tree 충돌(rc=1) → REJECT."""
    _nano_edits_line5(repo)
    _commit(repo, {"f.py": _lines(l5="FEAT")}, "feat edits line5 differently")
    r = _run(repo)
    assert r.returncode == 1 and "충돌" in r.stdout


def test_merge_tree_failure_rc_rejects(repo: Path, tmp_path: Path) -> None:
    """merge-tree 가 rc≠0,1(128) 이면 1행 OID 가 있어도 REJECT — 종료코드를 따로 본다(5c)."""
    _nano_edits_line5(repo)
    _cherry_pick_nano_onto_feat_with_other_context(repo)
    wrap = tmp_path / "wrap"
    wrap.mkdir()
    shim = wrap / "git"
    shim.write_text(f'#!/usr/bin/env bash\nfor a in "$@"; do if [ "$a" = merge-tree ]; then echo deadbeef; exit 128; fi; done\nexec {REAL_GIT} "$@"\n')
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    r = _run(repo, wrap)
    assert r.returncode == 1 and r.stdout.startswith("REJECT") and "merge-tree" in r.stdout


# --- DA 597 H1: «+» 경로 교집합이 아니라 실제 merge delta 를 본다 ---


def _nano_branch_from_feat_with_f(repo: Path) -> None:
    """feat 에 f.py(8줄) 를 만들고 nano 를 그 위로 맞춘 뒤 nano 를 체크아웃해 둔다."""
    _git(repo, "checkout", "-q", "feat")
    _commit(repo, {"f.py": _lines()}, "add f.py")
    _git(repo, "checkout", "-q", "nano")
    _git(repo, "merge", "-q", "--ff-only", "feat")


def test_non_ascii_path_unlanded_rejects_under_quotepath_true(repo: Path) -> None:
    """DA597 ① — core.quotepath=true 에서 한글 경로 «+» 가 교집합 불일치로 PASS 되던 누출."""
    _git(repo, "config", "core.quotepath", "true")
    _commit(repo, {"미랜딩.py": "print(1)\n"}, "non-ascii code")
    _git(repo, "checkout", "-q", "feat")
    r = _run(repo)
    assert r.returncode == 1 and r.stdout.startswith("REJECT") and "미랜딩.py" in r.stdout


def test_feat_rename_with_nano_edit_rejects(repo: Path) -> None:
    """DA597 ② — feat 가 f→g rename, nano 는 f 수정: 실제 delta 는 g.py 라 교집합이 비던 누출."""
    _nano_branch_from_feat_with_f(repo)
    _commit(repo, {"f.py": _lines(l5="NANO")}, "nano edits f")
    _git(repo, "checkout", "-q", "feat")
    _git(repo, "mv", "f.py", "g.py")
    _git(repo, "commit", "-q", "-m", "feat rename")
    r = _run(repo)
    assert r.returncode == 1 and "g.py" in r.stdout


def test_nano_delete_rejects(repo: Path) -> None:
    _nano_branch_from_feat_with_f(repo)
    _git(repo, "rm", "-q", "f.py")
    _git(repo, "commit", "-q", "-m", "nano deletes f")
    _git(repo, "checkout", "-q", "feat")
    r = _run(repo)
    assert r.returncode == 1 and "f.py" in r.stdout


def test_nano_mode_change_rejects(repo: Path) -> None:
    _nano_branch_from_feat_with_f(repo)
    (repo / "f.py").chmod(0o755)
    _git(repo, "commit", "-q", "-am", "nano chmod")
    _git(repo, "checkout", "-q", "feat")
    r = _run(repo)
    assert r.returncode == 1 and "f.py" in r.stdout


def test_nano_reverts_own_change_net_zero_passes(repo: Path) -> None:
    """되돌림 — 되돌린 커밋이 역사에 남아도 최종 merge delta 0 이면 PASS."""
    _nano_branch_from_feat_with_f(repo)
    _commit(repo, {"f.py": _lines(l5="NANO")}, "nano edits f")
    _git(repo, "revert", "--no-edit", "HEAD")
    _git(repo, "checkout", "-q", "feat")
    r = _run(repo)
    assert r.returncode == 0 and "content_landed_via_merge_tree" in r.stdout


# --- G4c r3: 반영 뒤 feat 가 같은 파일을 더 고침(충돌) → tip 내용이 feat 역사에 있으면 PASS · --override ---


def _run_args(repo: Path, *extra: str, ledger: Path | None = None) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    if ledger is not None:
        env["FT_CHERRY_OVERRIDE_LEDGER"] = str(ledger)
    return subprocess.run(["bash", str(GATE), "feat", "nano", "--repo", str(repo), *extra], capture_output=True, text=True, env=env)


def _landed_then_edited_again(repo: Path) -> None:
    """오늘 G4b 모양 — nano 2커밋을 feat 가 «스쿼시 1커밋» 으로 반영(patch-id 불일치 → cherry «+») 한 뒤 같은 줄을 또 고쳐 merge-tree 가 충돌."""
    _git(repo, "checkout", "-q", "feat")
    _commit(repo, {"f.py": _lines()}, "add f.py")
    _git(repo, "checkout", "-q", "nano")
    _git(repo, "merge", "-q", "--ff-only", "feat")
    _commit(repo, {"f.py": _lines(l5="NANO")}, "nano edits line5")
    _commit(repo, {"f.py": _lines(l5="NANO", l8="NANO8")}, "nano edits line8")
    _git(repo, "checkout", "-q", "feat")
    _commit(repo, {"f.py": _lines(l5="NANO", l8="NANO8")}, "feat squash-lands nano")
    _commit(repo, {"f.py": _lines(l5="FEAT-LATER", l8="NANO8")}, "feat edits line5 again")


def test_landed_then_superseded_passes(repo: Path) -> None:
    """⑥ 충돌인데 tip blob 이 feat 역사(cherry-pick 커밋)에 있다 → PASS content_landed_then_superseded."""
    _landed_then_edited_again(repo)
    assert _git(repo, "cherry", "feat", "nano").startswith("+")
    r = _run(repo)
    assert r.returncode == 0 and "content_landed_then_superseded" in r.stdout


def test_tip_blob_not_in_feat_history_rejects(repo: Path) -> None:
    """⑦ 충돌이고 tip blob 이 feat 역사에 없음 → REJECT, 경로 목록."""
    _nano_edits_line5(repo)
    _commit(repo, {"f.py": _lines(l5="FEAT-OTHER")}, "feat edits line5 differently")
    r = _run(repo)
    assert r.returncode == 1 and "f.py" in r.stdout and "새 blob 으로 없음" in r.stdout


def test_override_without_reason_refused(repo: Path, tmp_path: Path) -> None:
    """⑧-a 사유 빈 문자열 → 거부(원장 0행)."""
    _nano_edits_line5(repo)
    _commit(repo, {"f.py": _lines(l5="FEAT-OTHER")}, "feat edits line5 differently")
    ledger = tmp_path / "state" / "ov.log"
    for reason in ("", "   "):
        r = _run_args(repo, "--override", reason, ledger=ledger)
        assert r.returncode == 1 and "사유가 비어" in r.stdout
    assert not ledger.exists()


def test_override_with_reason_passes_and_logs(repo: Path, tmp_path: Path) -> None:
    """⑧-b 사유 있음 → PASS + stderr ERROR + 원장 정확히 1행(사유 포함)."""
    _nano_edits_line5(repo)
    _commit(repo, {"f.py": _lines(l5="FEAT-OTHER")}, "feat edits line5 differently")
    ledger = tmp_path / "state" / "ov.log"
    r = _run_args(repo, "--override", "오빠 판정: 대체 구현으로 폐기", ledger=ledger)
    assert r.returncode == 0 and "OVERRIDE" in r.stdout and "ERROR" in r.stderr
    rows = ledger.read_text(encoding="utf-8").splitlines()
    assert len(rows) == 1 and "오빠 판정: 대체 구현으로 폐기" in rows[0] and "nano=nano" in rows[0]


def test_override_does_not_mask_git_failure(repo: Path, tmp_path: Path) -> None:
    """override 는 내용 REJECT 만 푼다 — merge-tree rc128 같은 git 실패는 그대로 REJECT."""
    _landed_then_edited_again(repo)
    wrap = tmp_path / "wrap"
    wrap.mkdir()
    shim = wrap / "git"
    shim.write_text(f'#!/usr/bin/env bash\nfor a in "$@"; do if [ "$a" = merge-tree ]; then exit 128; fi; done\nexec {REAL_GIT} "$@"\n')
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    env = {**os.environ, "PATH": f"{wrap}{os.pathsep}{os.environ['PATH']}", "FT_CHERRY_OVERRIDE_LEDGER": str(tmp_path / "ov.log")}
    r = subprocess.run(["bash", str(GATE), "feat", "nano", "--repo", str(repo), "--override", "x"], capture_output=True, text=True, env=env)
    assert r.returncode == 1 and "merge-tree 실패" in r.stdout


# --- G4c r4 (DA 599): superseded 증거는 분기 «뒤» feat 의 새 blob 만 · override 메타 git 실패는 행 없이 exit 1 ---


def _shim(tmp_path: Path, body: str) -> Path:
    wrap = tmp_path / "wrap"
    wrap.mkdir()
    shim = wrap / "git"
    shim.write_text(f'#!/usr/bin/env bash\n{body}\nexec {REAL_GIT} "$@"\n')
    shim.chmod(shim.stat().st_mode | stat.S_IEXEC)
    return wrap


def test_rollback_to_pre_branch_blob_rejects(repo: Path) -> None:
    """H1: 분기 전 옛 blob 으로 rollback 한 브랜치는 «feat 역사에 있다» 만으로 PASS 하면 안 된다."""
    _git(repo, "checkout", "-q", "feat")
    _commit(repo, {"f.py": "old\n"}, "old")
    _commit(repo, {"f.py": "new\n"}, "new")
    _git(repo, "branch", "-f", "nano", "feat")
    _git(repo, "checkout", "-q", "nano")
    _commit(repo, {"f.py": "old\n"}, "nano rolls back")
    _git(repo, "checkout", "-q", "feat")
    r = _run(repo)
    assert r.returncode == 1 and "f.py" in r.stdout and "content_landed_then_superseded" not in r.stdout


def test_override_meta_git_failure_exits_1_without_row(repo: Path, tmp_path: Path) -> None:
    """H2: 원장 메타(rev-parse --short) 실패 → 빈 SHA 행 + exit 0 이 아니라 exit 1 · 행 0."""
    _nano_edits_line5(repo)
    _commit(repo, {"f.py": _lines(l5="FEAT-OTHER")}, "feat edits line5 differently")
    wrap = _shim(tmp_path, 'for a in "$@"; do [ "$a" = --short ] && { echo injected >&2; exit 128; }; done')
    ledger = tmp_path / "ov.log"
    env = {**os.environ, "PATH": f"{wrap}{os.pathsep}{os.environ['PATH']}", "FT_CHERRY_OVERRIDE_LEDGER": str(ledger)}
    r = subprocess.run(["bash", str(GATE), "feat", "nano", "--repo", str(repo), "--override", "사유 있음"], capture_output=True, text=True, env=env)
    assert r.returncode == 1 and "메타 조회 실패" in r.stdout
    assert not ledger.exists()


def test_merge_base_failure_rejects(repo: Path, tmp_path: Path) -> None:
    """merge-base rc≠0 → superseded 증거 구간을 못 정하므로 exit 1(override 로도 안 풀림)."""
    _landed_then_edited_again(repo)
    wrap = _shim(tmp_path, 'for a in "$@"; do [ "$a" = merge-base ] && exit 128; done')
    env = {**os.environ, "PATH": f"{wrap}{os.pathsep}{os.environ['PATH']}", "FT_CHERRY_OVERRIDE_LEDGER": str(tmp_path / "ov.log")}
    r = subprocess.run(["bash", str(GATE), "feat", "nano", "--repo", str(repo), "--override", "x"], capture_output=True, text=True, env=env)
    assert r.returncode == 1 and "merge-base 실패" in r.stdout
