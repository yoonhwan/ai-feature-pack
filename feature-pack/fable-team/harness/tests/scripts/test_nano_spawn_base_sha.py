"""ft-nano-spawn.sh base_sha (M7 범위 3 · master#123 #53338 판정 — master#122 의 기록 구현 위에 카드 대조 REJECT/--recheck).

- worktree-info.json base_sha = 기준 브랜치 HEAD short sha (master#122 기록 · 유지).
- 첫 개설(카드 «## 상태» 에 `base_sha:` 없음) = 카드에 현재 HEAD 40-hex 를 써넣고 진행 · REJECT 0.
- 재개·재spawn(카드에 base_sha 있음) = base_sha..HEAD 사이에 카드 «## 구현 범위» 인용 파일(경로 토큰 · `관련 파일:` 줄)이 바뀌면 REJECT(바뀐 파일·커밋 수 출력) ·
  인용 경로가 없으면 세트 경로 전체 · `--recheck <판정문>` 이 실재하고 현재 HEAD sha(7자 이상 접두)를 적었을 때만 통과.
tmux·tmuxc·lint·move·send 는 스텁(격리 임시 저장소만 쓴다).
"""

import json
import os
import shutil
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, commit, copy_py_helpers, git, init_repo

CARD = "# 카드\n\n## 골 원문\nx\n\n## 구현 범위\n- `worker/w.py` 를 고친다\n\n## 상태\n- 대기\n"
TEAMS_V65 = "| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v65#1 | 현역 |\n"
PLAIN = "# 카드\n\n## 구현 범위\n- 문장만\n\n## 상태\n- 대기\n"


def _exe(path, body):
    path.write_text("#!/bin/bash\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "feat/root")
    commit(repo, {"worker/w.py": "w", "docs/d.md": "d", "design/x.md": "x", "design/TEAMS.md": TEAMS_V65}, "tree")  # R383: v65 폴더는 design/TEAMS.md 로 푼다
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text("{}\n")
    (repo / "design/v65/indices/대기").mkdir(parents=True)
    hb = tmp_path / "bin"
    hb.mkdir()
    shutil.copy(BIN / "ft-nano-spawn.sh", hb)
    copy_py_helpers(hb)  # 문지기 다음 단계 순수 판정 도우미 전부
    for stub in ("ft-index-lint.sh", "ft-proposal-gate.sh", "ft-index-move.sh", "ft-send-verified.sh", "ft-resource-gate.sh", "ft-agent-ready.sh"):
        _exe(hb / stub, "exit 0\n")
    _exe(hb / "ft-sheet-events.sh", 'case "$1" in key) echo k;; esac\nexit 0\n')  # 사건 원장 가짜 — 실제 원장 쓰기 0
    sh = tmp_path / "shim"
    sh.mkdir()
    _exe(sh / "sleep", "exit 0\n")
    _exe(sh / "tmuxc", f"touch {tmp_path}/opened\nexit 0\n")
    _exe(
        sh / "tmux",
        f'case "$1" in has-session) [ -e {tmp_path}/opened ] && [[ "$*" == *"#0"* ]] ; exit $? ;; '
        f'list-panes) echo "ft-v65-temp-slug#0|%1" ;; show-option) echo 1 ;; esac\nexit 0\n',
    )
    return {"repo": repo, "hb": hb, "sh": sh, "tmp": tmp_path}


def _card(env, text=CARD, base=None):
    if base:
        text = text.replace("- 대기\n", f"- base_sha: {base}\n- 대기\n")
    p = env["repo"] / "design/v65/indices/대기/slug.md"
    p.write_text(text)
    return p


def _spawn(env, card, *extra):
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_SEATS_JSON": str(env["repo"] / ".fable-team/seats.json")}
    return subprocess.run(["bash", str(env["hb"] / "ft-nano-spawn.sh"), str(card), *extra], capture_output=True, text=True, cwd=env["repo"], env=e)


def _sha(env, *a):
    return git(env["repo"], "rev-parse", *a, "HEAD").strip()


def _verdict(env, text):
    p = env["tmp"] / "verdict.md"
    p.write_text(text)
    return p


def test_spawn_records_worktree_info_base_sha_short(env):
    short = _sha(env, "--short")
    assert _spawn(env, _card(env)).returncode == 0
    info = json.loads((env["repo"] / ".worktrees/v65-slug/.worktree-info.json").read_text())
    assert info["base_sha"] == short


def test_first_spawn_writes_full_head_into_card_status(env):
    head, card = _sha(env), _card(env)
    assert _spawn(env, card).returncode == 0
    text = card.read_text()
    assert f"base_sha: {head}" in text and text.index("## 상태") < text.index("base_sha:")


def test_first_spawn_without_status_section_appends_one(env):
    head, card = _sha(env), _card(env, "# 카드\n\n## 구현 범위\n- y\n")
    assert _spawn(env, card).returncode == 0
    assert f"## 상태\n- base_sha: {head}" in card.read_text()


def test_respawn_rejects_when_cited_file_changed_with_file_and_commit_count(env):
    base = _sha(env)
    commit(env["repo"], {"worker/w.py": "w2"}, "worker changed")
    commit(env["repo"], {"worker/w.py": "w3"}, "worker changed again")
    r = _spawn(env, _card(env, base=base))
    assert r.returncode == 1 and "REJECT" in r.stdout and "worker/w.py" in r.stdout and "커밋 2개" in r.stdout


def test_respawn_passes_when_only_uncited_file_changed(env):
    base = _sha(env)
    commit(env["repo"], {"docs/d.md": "d2"}, "docs changed")
    assert _spawn(env, _card(env, base=base)).returncode == 0


def test_related_files_line_adds_cited_prefix(env):
    base = _sha(env)
    commit(env["repo"], {"docs/d.md": "d2"}, "docs changed")
    r = _spawn(env, _card(env, CARD + "\n관련 파일: docs/\n", base=base))
    assert r.returncode == 1 and "docs/d.md" in r.stdout


def test_no_cited_paths_defaults_to_whole_set_paths(env):
    base = _sha(env)
    commit(env["repo"], {"worker/other.py": "x"}, "worker other")
    assert _spawn(env, _card(env, PLAIN, base=base)).returncode == 1


def test_no_cited_paths_ignores_non_set_paths(env):
    base = _sha(env)
    commit(env["repo"], {"design/x.md": "x2"}, "design changed")
    assert _spawn(env, _card(env, PLAIN, base=base)).returncode == 0


def test_recheck_passes_when_verdict_names_current_head(env):
    base = _sha(env)
    commit(env["repo"], {"worker/w.py": "w2"}, "worker changed")
    v = _verdict(env, f"판정: 재대조 완료 — feat HEAD {_sha(env, '--short')} 기준\n")
    r = _spawn(env, _card(env, base=base), "--recheck", str(v))
    assert r.returncode == 0 and "RECHECK 통과" in r.stdout


def test_recheck_rejects_when_verdict_names_old_sha(env):
    base = _sha(env)
    commit(env["repo"], {"worker/w.py": "w2"}, "worker changed")
    v = _verdict(env, f"판정: {base} 기준으로 재대조\n")
    assert _spawn(env, _card(env, base=base), "--recheck", str(v)).returncode == 1


def test_recheck_rejects_when_file_missing(env):
    base = _sha(env)
    commit(env["repo"], {"worker/w.py": "w2"}, "worker changed")
    assert _spawn(env, _card(env, base=base), "--recheck", str(env["tmp"] / "nope.md")).returncode == 1


def test_recheck_not_needed_when_nothing_cited_changed(env):
    r = _spawn(env, _card(env, base=_sha(env)))
    assert r.returncode == 0 and "RECHECK" not in r.stdout
