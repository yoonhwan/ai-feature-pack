"""ft-disk-census.sh — 워크트리·임시 사본을 «만든 좌석·착지 여부» 로 가르는 읽기 전용 표 (카드 r-disk-drop-worktree-scratch-census §구현 범위 1).
격리 임시 저장소 + tmux 스텁 — 실 워크트리·실 사본 접촉 0 · 시험에 GIT_* 환경을 걸지 않는다(BOOT 25).
"""

import json
import os
import stat
import subprocess

import pytest
from ft_git_helpers import BIN, commit, git, init_repo

SESSIONS = "byz-x-nano-live#0\n"


def _wt(repo, name, branch, base="main"):
    wt = repo / ".worktrees" / name
    git(repo, "worktree", "add", "-q", "-b", branch, str(wt), base)
    (wt / ".worktree-info.json").write_text(json.dumps({"branch": branch}))  # baton wt-create 가 쓰는 파일(gitignored)
    return wt


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "main")
    commit(repo, {".gitignore": ".worktrees/\n.fable-team/\n.worktree-info.json\n"}, "ignore")  # main 커밋의 `add -A` 가 워크트리 gitlink 를 쓸어 담지 않게
    # ① squash 착지 나노 — 조상 아님 · cherry 전부 «-» (같은 patch 가 main 에 있다)
    w = _wt(repo, "v65-sq", "nano/sq")
    commit(w, {"sq.txt": "sq"}, "sq work")
    commit(repo, {"sq.txt": "sq"}, "main lands sq")
    # ② 미착지 나노 — cherry «+»
    w = _wt(repo, "v65-un", "nano/un")
    commit(w, {"un.txt": "un"}, "un work")
    # ③ 착지됐지만 미커밋 1
    w = _wt(repo, "v65-dirty", "nano/dirty")
    commit(w, {"dirty.txt": "d"}, "dirty work")
    commit(repo, {"dirty.txt": "d"}, "main lands dirty")
    (w / "scratch.txt").write_text("uncommitted")
    # ④ 착지됐지만 좌석 살아 있음 (tmux 스텁 byz-x-nano-live#0)
    w = _wt(repo, "v65-live", "nano/live")
    commit(w, {"live.txt": "l"}, "live work")
    commit(repo, {"live.txt": "l"}, "main lands live")
    # ⑤ 카드 «세트» 줄로만 착지 증명 — cherry «+» (squash 로 묶여 patch 가 다름)
    w = _wt(repo, "v65-card", "nano/card")
    tip = commit(w, {"card.txt": "c1"}, "card work 1")
    commit(repo, {"card.txt": "c1", "card-extra.txt": "x"}, "main squash of card")
    # ⑤b 카드 증거 뒤에 미착지 커밋이 더 붙은 가지 — 세트 != tip 이라 착지 아님
    w2 = _wt(repo, "v65-cardx", "nano/cardx")
    tip2 = commit(w2, {"cardx.txt": "c1"}, "cardx work 1")
    commit(repo, {"cardx.txt": "c1", "cardx-extra.txt": "x"}, "main squash of cardx")
    commit(w2, {"cardx-more.txt": "unlanded"}, "cardx work after card evidence")
    for k, t in (("card", tip), ("cardx", tip2)):
        card = repo / f"design/harness/indices/완성/{k}.md"
        card.parent.mkdir(parents=True, exist_ok=True)
        card.write_text(f"# card\n## 상태\n- squash · 세트: {t} · 시험: x rc=0 · 이슈: 0\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "card evidence")
    # ⑥ 커밋 메시지에 카드 ID 만 있는 약한 착지 — «+» · 세트 줄 없음
    w = _wt(repo, "v65-weak", "nano/weak")
    commit(w, {"weak.txt": "w"}, "weak work")
    commit(repo, {"doc.txt": "d"}, "[docs] weak 카드 메모")
    # ⑦ 다른 가지 워크트리
    _wt(repo, "other-feat", "feat/other")
    # ⑦b 착지됐고 «삭제만» 미커밋(지우다 만 껍데기) — 계획 대상 (실작업물 0)
    w = _wt(repo, "v65-shell", "nano/shell")
    commit(w, {"shell.txt": "s"}, "shell work")
    commit(repo, {"shell.txt": "s"}, "main lands shell")
    (w / "shell.txt").unlink()
    # ⑦c 등록부에 «심링크 경로» 로 적힌 repo-* 사본(git 은 실경로로 보고한다)
    real = tmp_path / "real"
    real.mkdir()
    (tmp_path / "link").symlink_to(real)
    git(repo, "worktree", "add", "-q", "--detach", str(real / "repo-abc"), "main")
    (repo / ".fable-team/state").mkdir(parents=True, exist_ok=True)
    (repo / ".fable-team/state/scratch-repos.tsv").write_text(f"{tmp_path / 'link' / 'repo-abc'}\tbyz-x-owner#1\t1\n")
    # ⑧ scratchpad 안 직접 만든 detached 사본
    sp = tmp_path / "claude-501" / "-p--worktrees-harness-live" / "uuid1" / "scratchpad" / "mine"
    sp.parent.mkdir(parents=True)
    git(repo, "worktree", "add", "-q", "--detach", str(sp), "main")
    # tmux 스텁
    sh = tmp_path / "sh"
    sh.mkdir()
    tm = sh / "tmux"
    tm.write_text(f"#!/bin/bash\nprintf '%s' '{SESSIONS}'\n")
    tm.chmod(tm.stat().st_mode | stat.S_IEXEC)
    (repo / ".fable-team/state").mkdir(parents=True, exist_ok=True)
    (repo / "ledger.md").write_text("")  # close 원장 — 닫힘 행 없음
    return {"repo": repo, "sh": sh, "tmp": tmp_path}


def _run(env, *args, sessions=None):
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_RES_ROOT": str(env["repo"]),
         "FT_CENSUS_MAIN": "main", "FT_CENSUS_GB_PER_WT": "1.5"}
    return subprocess.run(["bash", str(BIN / "ft-disk-census.sh"), *args], capture_output=True, text=True, cwd=env["repo"], env=e)


def _rows(env):
    r = _run(env, "--json")
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    return {os.path.basename(x["path"]): x for x in d["rows"]}, d


def test_squash_landed_is_landed_and_plannable(env):
    rows, _ = _rows(env)
    r = rows["v65-sq"]
    assert r["kind"] == "nano" and r["landed"] == "cherry" and r["route"] == "plan:nano-close"


def test_unlanded_has_no_plan(env):
    rows, _ = _rows(env)
    assert rows["v65-un"]["landed"] == "no" and rows["v65-un"]["route"] == "HIL:unlanded"


def test_dirty_landed_has_no_plan(env):
    rows, _ = _rows(env)
    assert rows["v65-dirty"]["dirty"] == 1 and rows["v65-dirty"]["route"] == "keep:dirty"


def test_live_seat_has_no_plan(env):
    rows, _ = _rows(env)
    assert rows["v65-live"]["live"] is True and rows["v65-live"]["route"] == "keep:live-seat"


def test_card_evidence_sha_on_main_counts_as_landed(env):
    rows, _ = _rows(env)
    assert rows["v65-card"]["landed"] == "card" and rows["v65-card"]["route"] == "plan:nano-close"


def test_commit_message_grep_alone_is_weak_not_planned(env):
    rows, _ = _rows(env)
    assert rows["v65-weak"]["landed"] == "grep" and rows["v65-weak"]["route"] == "HIL:weak-landed"


def test_other_branch_is_hil_list_only(env):
    rows, _ = _rows(env)
    assert rows["other-feat"]["kind"] == "other" and rows["other-feat"]["route"] == "HIL:other-branch"


def test_scratchpad_direct_copy_is_kinded_and_owner_from_session_folder(env):
    rows, _ = _rows(env)
    r = rows["mine"]
    assert r["kind"] == "scratchpad-direct" and r["route"] == "register" and r["creator"] == "byz-x-nano-live#0"


def test_summary_table_counts_kind_by_route_with_gb(env):
    _, d = _rows(env)
    s = {(x["kind"], x["route"]): x for x in d["summary"]}
    assert s[("nano", "plan:nano-close")]["count"] == 3 and s[("nano", "plan:nano-close")]["gb"] == 4.5


def test_text_output_has_one_line_per_worktree_and_summary(env):
    r = _run(env)
    assert r.returncode == 0
    assert "v65-sq" in r.stdout and "합계" in r.stdout


def test_tmux_failure_blocks_every_plan_fail_closed(env):
    (env["sh"] / "tmux").write_text("#!/bin/bash\necho 'boom' >&2\nexit 2\n")
    rows, _ = _rows(env)
    assert rows["v65-sq"]["live"] is None and rows["v65-sq"]["route"] == "HIL:tmux-unknown"


def test_read_only_no_worktree_removed(env):
    before = git(env["repo"], "worktree", "list", "--porcelain")
    _run(env)
    assert git(env["repo"], "worktree", "list", "--porcelain") == before
    assert git(env["repo"], "config", "--get", "core.bare").strip() == "false"


def test_deletion_only_dirty_is_not_real_work_and_is_plannable(env):
    rows, _ = _rows(env)
    assert rows["v65-shell"]["dirty"] == 0 and rows["v65-shell"]["route"] == "plan:nano-close"


def test_registry_symlink_path_matches_real_path_of_tmp_repo(env):
    rows, _ = _rows(env)
    r = rows["repo-abc"]
    assert r["kind"] == "tmp-repo" and r["creator"] == "byz-x-owner#1" and r["route"] == "owner:done-note"


def test_unregistered_tmp_repo_is_its_own_route(env):
    git(env["repo"], "worktree", "add", "-q", "--detach", str(env["tmp"] / "real" / "repo-zzz"), "main")
    rows, _ = _rows(env)
    assert rows["repo-zzz"]["route"] == "HIL:unregistered"


# ── §구현 범위 2 — 계획 생성 연결: 착지 ①~③ · 좌석 없음 · 미실작업물인 나노만 .fable-team/state/wt-clean/<seat>.sh (새 삭제 권한 0 · 실행은 ft-wt-sweep) ──
def _plan_env(env):
    wtc = env["tmp"] / "wtc"
    return {"FT_WT_CLEAN_DIR": str(wtc), "FT_WT_AUTOCLEAN": "0", "FT_NANO_LEDGER": str(env["repo"] / "ledger.md"),
            "FT_NANO_LEDGER_WT": str(env["repo"]), "FT_TMUX_BIN": str(env["sh"] / "tmux")}


def _run_plan(env, *args):
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_RES_ROOT": str(env["repo"]),
         "FT_CENSUS_MAIN": "main", **_plan_env(env)}
    return subprocess.run(["bash", str(BIN / "ft-disk-census.sh"), "--plan", *args], capture_output=True, text=True, cwd=env["repo"], env=e)


def _plans(env):
    wtc = env["tmp"] / "wtc"
    return sorted(p.name for p in wtc.glob("*.sh")) if wtc.exists() else []


def test_plan_generates_only_for_landed_seatless_clean_nanos(env):
    r = _run_plan(env)
    assert r.returncode == 0, r.stdout + r.stderr
    assert _plans(env) == ["ft-v65-temp-card#0.sh", "ft-v65-temp-shell#0.sh", "ft-v65-temp-sq#0.sh"]


def test_plan_never_for_unlanded_weak_dirty_live_other(env):
    _run_plan(env)
    names = " ".join(_plans(env))
    for n in ("un#", "weak#", "dirty#", "live#", "other"):
        assert n not in names


def test_plan_is_not_overwritten_when_it_already_exists(env):
    _run_plan(env)
    p = env["tmp"] / "wtc" / "ft-v65-temp-sq#0.sh"
    p.write_text("# 사람이 손댄 계획\n")
    r = _run_plan(env)
    assert p.read_text() == "# 사람이 손댄 계획\n" and "이미 있음" in r.stdout


def test_plan_header_is_close_generator_plan_so_sweep_version_check_applies(env):
    _run_plan(env)
    body = (env["tmp"] / "wtc" / "ft-v65-temp-sq#0.sh").read_text()
    assert "# wt-clean 계획 — ft-nano-close.sh" in body and "# plan-ver: " in body


def test_close_plan_only_rejects_branch_not_bound_to_seat(env):
    wt = env["repo"] / ".worktrees" / "v65-sq"
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", **_plan_env(env)}
    r = subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), "ft-v65-temp-other#0", "--plan-only", str(wt)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.returncode == 1 and "REJECT" in r.stdout and _plans(env) == []


def test_close_plan_only_rejects_live_seat(env):
    wt = env["repo"] / ".worktrees" / "v65-live"
    (env["sh"] / "tmux").write_text("#!/bin/bash\nprintf 'ft-v65-temp-live#0|%%1\\n'\n")
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", **_plan_env(env)}
    r = subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), "ft-v65-temp-live#0", "--plan-only", str(wt)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.returncode == 1 and "REJECT" in r.stdout and _plans(env) == []


def test_plan_runs_past_missing_ledger_row_marks_nothing(env):
    """원장에 닫힘 행이 없는(close 를 거친 적 없는) 좌석의 계획이 «원장 표식 실패» 로 멈추지 않는다."""
    _run_plan(env)
    plan = env["tmp"] / "wtc" / "ft-v65-temp-sq#0.sh"
    baton = env["tmp"] / "baton-stub"
    baton.write_text("#!/bin/bash\nexit 0\n")
    baton.chmod(baton.stat().st_mode | stat.S_IEXEC)
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "BATON_BIN": str(baton), **_plan_env(env)}
    r = subprocess.run(["bash", str(plan)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.stdout.strip().splitlines()[-1].startswith("cleaned"), r.stdout + r.stderr
    assert not (env["repo"] / ".worktrees" / "v65-sq").exists()
    assert git(env["repo"], "rev-parse", "--verify", "nano/sq").strip()  # 브랜치는 남는다


def test_nano_without_info_json_is_not_planned_the_plan_guard_would_skip_it(env):
    (env["repo"] / ".worktrees/v65-sq/.worktree-info.json").unlink()
    rows, _ = _rows(env)
    assert rows["v65-sq"]["route"] == "HIL:no-info"


# ── §구현 범위 2 나머지: scratchpad 사후 등록 · 주인 쪽지 · hil 묶음 표 ──
def _tsv(env):
    p = env["repo"] / ".fable-team/state/scratch-repos.tsv"
    return [ln.split("\t") for ln in p.read_text().splitlines()] if p.exists() else []


def _mbox_stub(env):
    log = env["tmp"] / "mbox.log"
    m = env["tmp"] / "mbox.sh"
    m.write_text(f'#!/bin/bash\necho "$@" >> "{log}"\necho QUEUED\n')
    m.chmod(m.stat().st_mode | stat.S_IEXEC)
    return m, log


def _run_plan2(env, *args, extra=None):
    m, _ = _mbox_stub(env)
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_RES_ROOT": str(env["repo"]), "FT_CENSUS_MAIN": "main",
         "FT_MBOX": str(m), "FT_CENSUS_FROM": "census-test", **_plan_env(env), **(extra or {})}
    return subprocess.run(["bash", str(BIN / "ft-disk-census.sh"), *args], capture_output=True, text=True, cwd=env["repo"], env=e)


def test_plan_registers_scratchpad_direct_copy_once_with_session_owner(env):
    _run_plan2(env, "--plan")
    rows = [r for r in _tsv(env) if r[0].endswith("/scratchpad/mine")]
    assert len(rows) == 1 and rows[0][1] == "byz-x-nano-live#0" and rows[0][2].isdigit()
    _run_plan2(env, "--plan")
    assert len([r for r in _tsv(env) if r[0].endswith("/scratchpad/mine")]) == 1


def test_plan_does_not_register_scratchpad_copy_that_a_process_holds_as_cwd(env):
    sp = next(env["tmp"].glob("claude-501/*/uuid1/scratchpad/mine"))
    holder = subprocess.Popen(["sleep", "30"], cwd=sp)
    try:
        r = _run_plan2(env, "--plan")
    finally:
        holder.kill()
    assert not [x for x in _tsv(env) if x[0].endswith("/scratchpad/mine")] and "cwd" in r.stdout


def test_judged_copy_with_live_owner_gets_one_done_note_and_no_deletion(env):
    # repo-abc 는 main HEAD 사본(착지 = 판정 끝남) · 주인 byz-x-owner#1 이 살아 있다
    (env["sh"] / "tmux").write_text("#!/bin/bash\nprintf 'byz-x-owner#1\\nbyz-x-nano-live#0\\n'\n")
    _, log = _mbox_stub(env)
    _run_plan2(env, "--plan")
    _run_plan2(env, "--plan")  # 두 번째 틱 — 같은 사본 재통지 0
    calls = [ln for ln in log.read_text().splitlines() if "repo-abc" in ln]
    assert len(calls) == 1 and "send byz-x-owner#1 census-test" in calls[0] and "--done" in calls[0]
    assert (env["tmp"] / "real" / "repo-abc").exists()


def test_unjudged_copy_gets_no_note(env):
    (env["sh"] / "tmux").write_text("#!/bin/bash\nprintf 'byz-x-owner#1\\n'\n")
    w = env["tmp"] / "real" / "repo-abc"
    git(w, "checkout", "-q", "--detach")
    commit(w, {"newwork.txt": "x"}, "unlanded work in the copy")
    _, log = _mbox_stub(env)
    _run_plan2(env, "--plan")
    assert not log.exists() or "repo-abc" not in log.read_text()


def test_hil_table_groups_waiting_plans_by_reason(env):
    d = env["tmp"] / "wtc"
    d.mkdir(exist_ok=True)
    for seat, why in (("a#0", "skipped:branch=? (nano/* 아님)"), ("b#0", "skipped:branch=? (nano/* 아님)"), ("c#0", "skipped:실작업물 미커밋 3파일")):
        (d / f"{seat}.sh.hil").write_text("#!/bin/bash\n")
        (d / f"{seat}.sh.log").write_text(f"x\n{why}\n")
    r = _run_plan2(env, "--hil")
    assert r.returncode == 0
    assert "branch=? (nano/* 아님)" in r.stdout and "2" in r.stdout and "실작업물 미커밋" in r.stdout
    assert "HIL 대기 계획 3" in r.stdout


def test_hil_table_also_lists_non_standard_worktrees_without_deleting(env):
    r = _run_plan2(env, "--hil")
    assert "other-feat" in r.stdout and (env["repo"] / ".worktrees/other-feat").exists()


def test_card_evidence_must_equal_branch_tip_extra_unlanded_commit_blocks_plan(env):
    rows, _ = _rows(env)
    r = rows["v65-cardx"]
    assert r["landed"] != "card" and r["route"] in ("HIL:unlanded", "HIL:weak-landed") and "plan" not in r["route"]


def test_plan_only_rejects_unlanded_branch_even_when_called_directly(env):
    wt = env["repo"] / ".worktrees" / "v65-un"
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", **_plan_env(env)}
    r = subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), "ft-v65-temp-un#0", "--plan-only", str(wt)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.returncode == 1 and "착지" in r.stdout and _plans(env) == []


def test_plan_only_rejects_card_branch_with_extra_unlanded_commit(env):
    wt = env["repo"] / ".worktrees" / "v65-cardx"
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", **_plan_env(env)}
    r = subprocess.run(["bash", str(BIN / "ft-nano-close.sh"), "ft-v65-temp-cardx#0", "--plan-only", str(wt)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.returncode == 1 and _plans(env) == []


def test_plan_revalidates_landing_at_execution_time(env):
    """계획 생성 뒤 가지에 미착지 커밋이 붙으면 실행 시점에 거부 — 워크트리·가지 그대로."""
    _run_plan(env)
    plan = env["tmp"] / "wtc" / "ft-v65-temp-sq#0.sh"
    w = env["repo"] / ".worktrees" / "v65-sq"
    commit(w, {"late.txt": "unlanded after plan"}, "late commit after plan generation")
    baton = env["tmp"] / "baton-stub"
    baton.write_text("#!/bin/bash\nexit 0\n")
    baton.chmod(baton.stat().st_mode | stat.S_IEXEC)
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "BATON_BIN": str(baton), **_plan_env(env)}
    r = subprocess.run(["bash", str(plan)], capture_output=True, text=True, cwd=env["repo"], env=e)
    assert r.stdout.strip().splitlines()[-1].startswith("skipped:착지"), r.stdout + r.stderr
    assert w.exists()


def test_hil_table_reads_real_producer_format_sh_log(env):
    """실제 생산자(ft-wt-sweep · close _wt_clean_run)는 <seat>.sh.log 에 쓰고 계획을 <seat>.sh.hil 로 옮긴다."""
    d = env["tmp"] / "wtc"
    d.mkdir(exist_ok=True)
    (d / "z#0.sh.hil").write_text("#!/bin/bash\n")
    (d / "z#0.sh.log").write_text("baton 출력\nskipped:실작업물 미커밋 9파일\n")
    r = _run_plan2(env, "--hil")
    assert "실작업물 미커밋 N파일" in r.stdout and "(사유 로그 없음)" not in r.stdout
