"""press-gate ① «선언 제외» (r1076) — press 카드가 «이 press 가 시험하지 않는 나노» 를 한 줄로 선언하면 ① 셈에서 뺀다.

카드: design/harness/indices/진행/r1076-press-gate-declared-exclusion-unlanded-nano.md §구현 범위·§반례 집합
  R1 ✗ 2개 · 둘 다 선언 → ⊘ 2줄 · ✓ 미랜딩 0 (다른 칸 통과면 rc0 — 여기선 ② 이하가 막아 rc1)
  R2 한 개만 선언 → 남은 1개로 ✗ 미랜딩 1
  R3 선언 줄 없음 → 지금과 같음(✗ 미랜딩 2 · rc1)
  R4 FT_PRESS_CARD 비었음 → 선언 0(지금과 같음)
  R5 선언된 커밋이 세트 HEAD 조상 → «✗ 선언 모순» · rc1
  R6 선언 이름이 ✗ 워크트리에 없음 → «⚠ 선언 이름 없음» (rc 영향 0)
  R7 선언 꼴 틀림(«— 사유» 없음) → «✗ press 제외 선언 꼴 틀림» · rc1
격리: 임시 git 저장소 + 가짜 tmux(PATH) + 가짜 seats.json — 실 저장소·tmux·seats.json 접촉 0.
"""

import os
import subprocess
from pathlib import Path

from ft_git_helpers import BIN, commit, git, init_repo
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

EXCL, CONFLICT, SHAPE, ABSENT = "⊘ 선언 제외", "✗ 선언 모순", "✗ press 제외 선언 꼴 틀림", "⚠ 선언 이름 없음"


def _fixture(tmp_path):
    root = init_repo(tmp_path / "root")
    (root / ".fable-team" / "state").mkdir(parents=True)
    (root / ".fable-team" / "state" / "all-stop.log").write_text("2026-10-21T00:00:00\toff\tinstall\tinit\n")  # ⓪ 전팀 정지 = 꺼짐
    (root / ".worktrees").mkdir()
    fakebin = tmp_path / "fakebin"
    fakebin.mkdir()
    (fakebin / "tmux").write_text('#!/bin/sh\nprintf "%s\\n" $FT_FAKE_TMUX_SESSIONS\n')
    (fakebin / "lsof").write_text("#!/bin/sh\nexit 1\n")   # ② 리스너 없음 — 실 포트 접촉 0
    (fakebin / "curl").write_text("#!/bin/sh\nexit 7\n")   # ③④ 실 서비스 접촉 0
    for f in ("tmux", "lsof", "curl"):
        (fakebin / f).chmod(0o755)
    return root, fakebin


def _nano(root, name):
    """✗ 미랜딩 워크트리 하나 — worker/ 제품 경로에 커밋 1."""
    git(root, "worktree", "add", "-q", "-b", f"nano/{name}", str(root / ".worktrees" / f"v65-{name}"), "feat")
    wt = root / ".worktrees" / f"v65-{name}"
    commit(wt, {"worker/w.py": name}, f"[fix] {name} change")
    return wt


def _gate(root, fakebin, names, card=None, card_arg="__auto__", bindir=BIN, tmp_path=None):
    seats = ",".join(f'"ft-v65-temp-{n}#0":{{"role":"nano"}}' for n in names)
    (root / ".fable-team" / "seats.json").write_text("{" + seats + "}")
    if card is not None:
        (root / "card.md").write_text(card)
    env = {**os.environ, "PATH": f"{fakebin}:{os.environ['PATH']}", "FT_PRESS_ROOT": str(root), "FT_PRESS_WT": str(root),
           "FT_NANO_FEAT": "feat", "FT_FAKE_TMUX_SESSIONS": " ".join(f"ft-v65-temp-{n}#0" for n in names),
           "FT_PRESS_EVID": str(root / "evid"), "FT_PRESS_PERMIT_DIR": str(root / "permits"),
           "FT_ROOT": str(root)}   # ⑤⑥ 실행 상태 파일도 임시 루트 — 실 상태 접촉 0
    card_path = str(root / "card.md") if card_arg == "__auto__" else card_arg
    if card_path:
        env["FT_PRESS_CARD"] = card_path
    for k in ("FT_PRESS_TARGET", "FT_PRESS_PORTS", "FT_PRESS_PORT_BASE", "FT_PRESS_LOAD_MAX"):
        env.pop(k, None)
    return subprocess.run(["bash", str(bindir / "ft-press-gate.sh")], capture_output=True, text=True, env=env, timeout=70)


KEYS = ("미랜딩", "선언 제외", "선언 모순", "선언 꼴", "선언 이름 없음")


def _lines(r):
    return [ln for ln in r.stdout.splitlines() if any(k in ln for k in KEYS)]


def test_r1_both_declared_are_excluded(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    _nano(root, "b")
    r = _gate(root, fakebin, ["a", "b"], card="- press 제외 나노: v65-a, v65-b — 투명디스플레이 press 는 이 수정을 시험하지 않음\n")
    out = _lines(r)
    assert sum(EXCL in ln for ln in out) == 2, r.stdout
    assert "✓ 미랜딩 제품 커밋 0" in out and not any(ln.startswith("✗ 미랜딩") for ln in out), r.stdout


def test_r2_only_declared_one_is_excluded(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    _nano(root, "b")
    r = _gate(root, fakebin, ["a", "b"], card="- press 제외 나노: v65-a — a 는 다른 press 소관\n")
    out = _lines(r)
    assert sum(EXCL in ln for ln in out) == 1, r.stdout
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") and "v65-b" in ln for ln in out), r.stdout
    assert r.returncode == 1


def test_r3_no_declaration_line_blocks_like_before(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    _nano(root, "b")
    r = _gate(root, fakebin, ["a", "b"], card="# 카드\n\n- 다른 줄: v65-a\n")
    out = _lines(r)
    assert sum(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out) == 2, r.stdout   # 워크트리마다 1줄씩(합계 2)
    assert not any(EXCL in ln for ln in out) and r.returncode == 1, r.stdout


def test_r4_empty_card_env_has_no_declaration(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-a — 사유\n", card_arg="")
    out = _lines(r)
    assert any(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out), r.stdout
    assert not any(EXCL in ln or SHAPE in ln for ln in out), r.stdout


def test_r5_declared_commit_already_in_set_is_conflict(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    git(root, "checkout", "-q", "-b", "press")           # press 세트 HEAD = press (feat 는 커밋을 안 가진다)
    git(root, "merge", "-q", "--no-ff", "-m", "land a", "nano/a")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-a — 사유\n")
    out = _lines(r)
    assert any(CONFLICT in ln and "v65-a" in ln for ln in out), r.stdout
    assert r.returncode == 1, r.stdout
    assert not any(EXCL in ln for ln in out), r.stdout


def test_r6_declared_name_absent_warns_only(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-ghost, v65-a — 사유\n")
    out = _lines(r)
    assert any(ABSENT in ln and "v65-ghost" in ln for ln in out), r.stdout
    assert "✓ 미랜딩 제품 커밋 0" in out and r.returncode == 1, r.stdout   # rc 는 다른 칸(②~⑧)이 정한다


def test_r7_malformed_declaration_blocks(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-a\n")
    out = _lines(r)
    assert any(SHAPE in ln for ln in out), r.stdout
    assert r.returncode == 1 and not any(EXCL in ln for ln in out), r.stdout


# ── 변이 2: 고침을 되돌리면 그 단언이 죽는다(빨강 확인) ─────────────────────────
def _mutant(tmp_path, needle, repl):
    alt = tmp_path / "alt"
    alt.mkdir()
    for f in BIN.iterdir():
        if f.name != "ft-press-gate.sh":
            os.symlink(f, alt / f.name)
    src = (BIN / "ft-press-gate.sh").read_text(encoding="utf-8")
    assert needle in src, needle
    (alt / "ft-press-gate.sh").write_text(src.replace(needle, repl, 1), encoding="utf-8")
    return alt


def test_mutation_without_conflict_check_loses_r5(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    git(root, "checkout", "-q", "-b", "press")
    git(root, "merge", "-q", "--no-ff", "-m", "land a", "nano/a")
    alt = _mutant(tmp_path, 'git merge-base --is-ancestor "${h:0:40}" HEAD 2>/dev/null && IN_SET=$((IN_SET+1))', "true")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-a — 사유\n", bindir=alt)
    assert not any(CONFLICT in ln for ln in _lines(r)), r.stdout


def test_mutation_without_exclusion_loses_r1(tmp_path):
    root, fakebin = _fixture(tmp_path)
    _nano(root, "a")
    alt = _mutant(tmp_path, 'if _declared "$(basename "$W")"; then', "if false; then")
    r = _gate(root, fakebin, ["a"], card="- press 제외 나노: v65-a — 사유\n", bindir=alt)
    out = _lines(r)
    assert not any(EXCL in ln for ln in out) and any(ln.startswith("✗ 미랜딩 제품 커밋 1") for ln in out), r.stdout


def test_kit_pair_is_identical():
    kit = BIN.parent / "kit" / "fable-team" / "bin" / "ft-press-gate.sh"
    assert (BIN / "ft-press-gate.sh").read_text(encoding="utf-8") == kit.read_text(encoding="utf-8")
