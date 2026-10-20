"""press-gate ① — 선언 base 가 FEAT 가 아닌 나노(origin/main 기반 등)는 «다른 줄기» 로 표시하고 미랜딩 셈에서 뺀다 (원장 R58).

카드: design/harness/indices/진행/r58-press-gate-other-base-nano.md §구현 범위 3 · §완료 조건
  ⓐ base=main 나노 → ⊘ 다른 줄기 · ✓ 미랜딩 0 (세트 표시 ⊕ 도 생략)
  ⓑ base=feat → 지금처럼 ✗ 4 · rc=1
  ⓒ info 없음 → 지금처럼 센다(조용히)
  ⓓ base=main 인데 base_sha 가 HEAD 조상 아님 → ⚠ base 선언 확인 실패 + ✗ (fail-closed)
  ⓔ base=origin/feat → FEAT 로 취급해 센다
  ⓕ FEAT 나노(✗ 1) + main 나노(⊘) 동시 → ✗ 1 (main 쪽 0 기여)
격리: 임시 git 저장소 + 가짜 tmux(PATH) + 가짜 seats.json — 실 저장소·tmux·seats.json 접촉 0.
"""

# ruff: noqa: F811  (픽스처 `fake` 를 import 해 인자로 받는 pytest 관용)
import json
import os
import subprocess

from ft_git_helpers import BIN, commit, git
from test_press_gate_set_membership import _gate, _nano, _section1, fake  # noqa: F401
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

OTHER = "  ⊘ 다른 줄기"
WARN = "  ⚠ base 선언 확인 실패"


def _info(wt, base, base_sha):
    (wt / ".worktree-info.json").write_text(json.dumps({"base": base, "base_sha": base_sha}))


def _main_nano(root, name, own=True):  # FEAT 에 없는 worker 커밋 3 이 있는 main 에서 갈라진 나노 + (선택) 자기 worker 커밋 1
    if "main" not in git(root, "branch", "--list", "main"):
        git(root, "checkout", "-q", "-b", "main")
        for i in range(3):
            commit(root, {f"worker/m{i}.py": "m"}, f"main commit {i}")
        git(root, "checkout", "-q", "feat")
    sha = git(root, "rev-parse", "main").strip()
    wt = root / ".worktrees" / f"v65-{name}"
    git(root, "worktree", "add", "-q", "-b", f"nano/{name}", str(wt), "main")
    if own:
        commit(wt, {"worker/own.py": "o"}, "[fix] own change")
    return wt, sha


def test_main_based_nano_is_other_trunk_and_not_counted(fake):  # ⓐ
    root, _ = fake
    wt, sha = _main_nano(root, "a")
    _info(wt, "main", sha)
    r = _gate(fake, ["a"])
    out = _section1(r)
    assert any(ln.startswith(OTHER) and "base=main" in ln for ln in out), r.stdout
    assert "✓ 미랜딩 제품 커밋 0" in out and not any(ln.startswith("✗ 미랜딩") for ln in out), r.stdout
    assert not any(ln.startswith(("  ⊕", "  ·")) for ln in out), r.stdout  # 세트 표시·후보 나열도 생략


def test_same_nano_declaring_feat_is_still_counted(fake):  # ⓑ
    root, _ = fake
    wt, sha = _main_nano(root, "b")
    _info(wt, "feat", sha)
    r = _gate(fake, ["b"])
    out = _section1(r)
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 4") for ln in out), r.stdout
    assert not any(ln.startswith((OTHER, WARN)) for ln in out), r.stdout
    assert r.returncode == 1


def test_missing_info_is_counted_silently(fake):  # ⓒ
    root, _ = fake
    _main_nano(root, "c")
    r = _gate(fake, ["c"])
    out = _section1(r)
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 4") for ln in out), r.stdout
    assert not any(ln.startswith((OTHER, WARN)) for ln in out), r.stdout
    assert r.returncode == 1


def test_base_sha_not_ancestor_is_fail_closed(fake):  # ⓓ
    root, _ = fake
    wt, _ = _main_nano(root, "d")
    _info(wt, "main", "0" * 40)
    r = _gate(fake, ["d"])
    out = _section1(r)
    assert any(ln.startswith(WARN) and "base=main" in ln for ln in out), r.stdout
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 4") for ln in out), r.stdout
    assert not any(ln.startswith(OTHER) for ln in out), r.stdout
    assert r.returncode == 1


def test_origin_feat_declaration_is_treated_as_feat(fake):  # ⓔ
    root, _ = fake
    git(root, "update-ref", "refs/remotes/origin/feat", "feat")  # 가짜 원격 ref
    wt = _nano(root, "e")
    commit(wt, {"worker/w.py": "w-changed"}, "[fix] worker change")
    _info(wt, "origin/feat", git(root, "rev-parse", "feat").strip())
    r = _gate(fake, ["e"])
    out = _section1(r)
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out), r.stdout
    assert not any(ln.startswith((OTHER, WARN)) for ln in out), r.stdout
    assert r.returncode == 1


def _merged_main_nano(root, name):  # DA 반례: main 커밋 A → feat 가 main 병합(A ⊂ feat) → feat 기반 나노 N(worker 커밋 1)
    git(root, "checkout", "-q", "-b", "main")
    a = commit(root, {"worker/a.py": "a"}, "main A")
    git(root, "checkout", "-q", "feat")
    git(root, "merge", "-q", "--no-edit", "main")
    wt = _nano(root, name)
    commit(wt, {"worker/n.py": "n"}, "[fix] worker change")
    return wt, a


def _counted_without_other_trunk(r):
    out = _section1(r)
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out), r.stdout
    assert not any(ln.startswith((OTHER, WARN)) for ln in out), r.stdout  # base_sha ⊂ FEAT → 근거 없음 · ⚠ 도 없이 센다
    assert r.returncode == 1


def test_old_main_ancestor_in_feat_is_counted(fake):  # ⓖ
    root, _ = fake
    wt, a = _merged_main_nano(root, "g")
    _info(wt, "main", a)
    _counted_without_other_trunk(_gate(fake, ["g"]))


def test_short_sha_alias_does_not_bypass(fake):  # ⓗ
    root, _ = fake
    wt, a = _merged_main_nano(root, "h")
    _info(wt, "main", a[:7])
    _counted_without_other_trunk(_gate(fake, ["h"]))


def test_feat_ref_lookup_failure_is_fail_closed(fake):  # ⓘ
    root, fakebin = fake
    wt, sha = _main_nano(root, "i")
    _info(wt, "main", sha)
    seats = '{"ft-v65-temp-i#0":{"role":"nano"}}'
    (root / ".fable-team" / "seats.json").write_text(seats)
    env = {**os.environ, "PATH": f"{fakebin}:{os.environ['PATH']}", "FT_PRESS_ROOT": str(root), "FT_PRESS_WT": str(root), "FT_NANO_FEAT": "no-such-feat",
           "FT_FAKE_TMUX_SESSIONS": "ft-v65-temp-i#0"}
    r = subprocess.run(["bash", str(BIN / "ft-press-gate.sh")], capture_output=True, text=True, env=env, timeout=120)
    out = _section1(r)
    assert any(ln.startswith(WARN) for ln in out), r.stdout
    assert not any(ln.startswith(OTHER) for ln in out), r.stdout
    assert r.returncode == 1


def _warned_and_counted(r, n):
    out = _section1(r)
    assert sum(ln.startswith(WARN) for ln in out) == 1, r.stdout
    assert not any(ln.startswith(OTHER) for ln in out), r.stdout
    assert any(ln.startswith(f"✗ 미랜딩 제품 커밋 {n}") for ln in out), r.stdout
    assert r.returncode == 1


def test_base_sha_is_nano_own_tip_not_trusted(fake):  # ⓙ DA r2 반례: base=main · base_sha=나노 자기 tip(main 의 조상 아님)
    root, _ = fake
    wt, _ = _merged_main_nano(root, "j")
    _info(wt, "main", git(wt, "rev-parse", "HEAD").strip())
    _warned_and_counted(_gate(fake, ["j"]), 1)


def test_unrelated_declared_branch_is_not_trusted(fake):  # ⓚ 선언 base 를 base_sha 와 무관한 실재 브랜치로 오기
    root, _ = fake
    git(root, "branch", "side", "feat")
    wt, sha = _main_nano(root, "k")
    _info(wt, "side", sha)
    _warned_and_counted(_gate(fake, ["k"]), 4)


def test_mixed_feat_nano_blocks_and_main_nano_contributes_zero(fake):  # ⓕ
    root, _ = fake
    wt_m, sha = _main_nano(root, "m")
    _info(wt_m, "main", sha)
    wt_f = _nano(root, "f")
    commit(wt_f, {"worker/w.py": "w-changed"}, "[fix] worker change")
    _info(wt_f, "feat", git(root, "rev-parse", "feat").strip())
    r = _gate(fake, ["m", "f"])
    out = _section1(r)
    assert any(ln.startswith(OTHER) and "v65-m" in ln for ln in out), r.stdout
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") and "v65-f" in ln for ln in out), r.stdout
    assert not any(ln.startswith("✗ 미랜딩") and "v65-m" in ln for ln in out), r.stdout
    assert r.returncode == 1
