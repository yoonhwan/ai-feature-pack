"""③④ 증거 줄 (M7 범위 1 · REVIEW arch141 §2-2) — 카드 «## 상태» 에 정확히 이 1줄:
    세트: <나노 HEAD 40-hex> · 시험: <명령> rc=<n> · 이슈: 0 | <카드 경로>
인터페이스(이 시험이 고정): bash ft-nano-evidence-check.sh <카드> --repo <나노 워크트리>  (ft-nano-close.sh 가 호출)
  통과 = 줄 존재 ∧ 세트 HEAD == 현재 나노 HEAD ∧ rc=0 ∧ 이슈 칸이 `0` 또는 실재 경로 — 값 추론 금지(없으면 REJECT).
"""

import pytest
from ft_git_helpers import commit, git, init_repo, run_script


@pytest.fixture
def nano(tmp_path):
    return init_repo(tmp_path / "nano", "nano/x")


def _card(tmp_path, nano, line=None, head=None):
    head = head or git(nano, "rev-parse", "HEAD").strip()
    body = "# 카드\n\n## 상태\n- 2026-10-02 · 진행\n"
    body += (line if line is not None else f"- 세트: {head} · 시험: pytest tests/x -q rc=0 · 이슈: 0") + "\n"
    p = tmp_path / "card.md"
    p.write_text(body)
    return p


def _check(card, nano):
    return run_script("ft-nano-evidence-check.sh", str(card), "--repo", str(nano))


def test_valid_line_passes(tmp_path, nano):
    r = _check(_card(tmp_path, nano), nano)
    assert r.returncode == 0, r.stdout


def test_missing_line_rejects(tmp_path, nano):
    p = tmp_path / "card.md"
    p.write_text("## 상태\n- 진행\n")
    r = _check(p, nano)
    assert r.returncode == 1 and r.stdout.startswith("REJECT")


def test_head_mismatch_after_new_commit_rejects(tmp_path, nano):
    card = _card(tmp_path, nano)
    commit(nano, {"later.py": "x"}, "after the test")
    r = _check(card, nano)
    assert r.returncode == 1 and "HEAD" in r.stdout


def test_short_sha_rejects(tmp_path, nano):
    short = git(nano, "rev-parse", "--short", "HEAD").strip()
    assert _check(_card(tmp_path, nano, head=short), nano).returncode == 1


def test_nonzero_rc_rejects(tmp_path, nano):
    head = git(nano, "rev-parse", "HEAD").strip()
    assert _check(_card(tmp_path, nano, line=f"- 세트: {head} · 시험: pytest rc=1 · 이슈: 0"), nano).returncode == 1


def test_issue_card_path_must_exist(tmp_path, nano):
    head = git(nano, "rev-parse", "HEAD").strip()
    line = f"- 세트: {head} · 시험: pytest rc=0 · 이슈: {tmp_path}/no-such.md"
    assert _check(_card(tmp_path, nano, line=line), nano).returncode == 1
    (tmp_path / "issue.md").write_text("# 추가 이슈\n")
    line = f"- 세트: {head} · 시험: pytest rc=0 · 이슈: {tmp_path}/issue.md"
    assert _check(_card(tmp_path, nano, line=line), nano).returncode == 0


def test_issue_column_missing_rejects(tmp_path, nano):
    head = git(nano, "rev-parse", "HEAD").strip()
    assert _check(_card(tmp_path, nano, line=f"- 세트: {head} · 시험: pytest rc=0"), nano).returncode == 1


def _doc_line(nano, reason="문서 감사 — 코드 0"):
    return f"- 세트: {git(nano, 'rev-parse', 'HEAD').strip()} · 시험: 없음(문서) — {reason} · 이슈: 0"


def _doc_repo(tmp_path):
    repo = init_repo(tmp_path / "docrepo", "feat")
    git(repo, "checkout", "-q", "-b", "nano/doc")
    return repo


def test_doc_only_line_passes_when_only_docs_changed(tmp_path):
    repo = _doc_repo(tmp_path)
    commit(repo, {"design/a.md": "x", "docs/b.txt": "y", "README.md": "z"}, "audit")
    r = run_script("ft-nano-evidence-check.sh", str(_card(tmp_path, repo, line=_doc_line(repo))), "--repo", str(repo), "--feat", "feat")
    assert r.returncode == 0 and "없음(문서)" in r.stdout, r.stdout


def test_doc_only_line_with_code_change_rejects(tmp_path):
    repo = _doc_repo(tmp_path)
    commit(repo, {"design/a.md": "x", "worker/w.py": "code"}, "mixed")
    r = run_script("ft-nano-evidence-check.sh", str(_card(tmp_path, repo, line=_doc_line(repo))), "--repo", str(repo), "--feat", "feat")
    assert r.returncode == 1 and "worker/w.py" in r.stdout


def test_doc_only_line_without_reason_rejects(tmp_path):
    repo = _doc_repo(tmp_path)
    head = git(repo, "rev-parse", "HEAD").strip()
    r = run_script("ft-nano-evidence-check.sh", str(_card(tmp_path, repo, line=f"- 세트: {head} · 시험: 없음(문서) · 이슈: 0")), "--repo", str(repo), "--feat", "feat")
    assert r.returncode == 1


def test_doc_only_line_with_missing_feat_ref_rejects(tmp_path):
    repo = _doc_repo(tmp_path)
    r = run_script("ft-nano-evidence-check.sh", str(_card(tmp_path, repo, line=_doc_line(repo))), "--repo", str(repo), "--feat", "no/such")
    assert r.returncode == 1 and "feat" in r.stdout


def test_doc_only_line_with_stale_head_rejects(tmp_path):
    repo = _doc_repo(tmp_path)
    card = _card(tmp_path, repo, line=_doc_line(repo))
    commit(repo, {"design/later.md": "x"}, "later")
    r = run_script("ft-nano-evidence-check.sh", str(card), "--repo", str(repo), "--feat", "feat")
    assert r.returncode == 1 and "HEAD" in r.stdout
