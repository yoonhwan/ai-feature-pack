"""R81 — ft-nano-spawn.sh 롤백(판정 845·846·847)과 ft-nano-spawn-undo.sh 조건 시험. tmux·tmuxc·슬랙·명부는 전부 격리 스텁.

spawn: ⓐ슬랙 장부 사전 확인(부작용 0) · ③④ 실패 = undo --owned 1회 · ⑤⑥ 실패 = kill 0·undo 0·사람 판정.
undo: 롤백 모드 조건 ⓐ~ⓗ 를 하나씩 깨면 REJECT·kill 0 · 재검사 경합 · 락 · 단독 모드(계획만 · 집행 시점 재검사).
"""
import os
import shutil
import subprocess

import pytest
from _nano_rollback_env import BREAKS, SEAT, commit_in_wt, exe, jsonl, log_row, make_env, owned, roll, roster, tmux_log, undo
from ft_git_helpers import BIN, commit, copy_py_helpers, init_repo

CARD = "# 카드\n\n## 구현 범위\n- `worker/w.py` 를 고친다\n\n## 상태\n- 대기\n"
TEAMS_V65 = "| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | v65#1 | 현역 |\n"
SLACK = "- 슬랙: C1 · 시도 2026-10-10T11:08:00+09:00\n"


@pytest.fixture
def env(tmp_path):
    repo = init_repo(tmp_path / "repo", "feat/root")
    commit(repo, {"worker/w.py": "w", "design/TEAMS.md": TEAMS_V65, "design/v65/SEATBELT-README.md": "# sb\n"}, "tree")  # R383: v65 폴더는 design/TEAMS.md 로 푼다
    (repo / ".fable-team").mkdir()
    (repo / ".fable-team/seats.json").write_text("{}\n")
    (repo / "design/v65/indices/대기").mkdir(parents=True)
    hb, sh = tmp_path / "bin", tmp_path / "shim"
    hb.mkdir()
    sh.mkdir()
    shutil.copy(BIN / "ft-nano-spawn.sh", hb)
    copy_py_helpers(hb)  # 문지기 다음 단계 순수 판정 도우미 전부
    for stub in ("ft-index-lint.sh", "ft-proposal-gate.sh", "ft-index-move.sh", "ft-send-verified.sh", "ft-resource-gate.sh", "ft-agent-ready.sh"):
        exe(hb / stub, "exit 0\n")
    exe(hb / "ft-sheet-events.sh", 'case "$1" in key) echo k;; esac\nexit 0\n')  # 사건 원장 가짜 — 실제 원장 쓰기 0
    exe(hb / "ft-nano-spawn-undo.sh", f'echo "$*" >> {tmp_path}/undo.log\necho "UNDONE $1"\nexit 0\n')
    exe(sh / "sleep", "exit 0\n")
    exe(sh / "tmuxc", f"touch {tmp_path}/opened\nexit ${{TMUXC_RC:-0}}\n")
    exe(sh / "tmux", f'case "$1" in has-session) [ -e {tmp_path}/opened ] && [[ "$*" == *"#0"* ]] ; exit $? ;; '
        f'list-panes) echo "{SEAT}|%1|123" ;; show-option) echo ${{TAG_VAL:-1}} ;; esac\nexit 0\n')
    return {"repo": repo, "hb": hb, "sh": sh, "tmp": tmp_path}


def spawn(env, card_text=CARD, **extra):
    card = env["repo"] / "design/v65/indices/대기/slug.md"
    card.write_text(card_text)
    tp = env["tmp"] / "tp.sh"
    e = {**os.environ, "PATH": f"{env['sh']}{os.pathsep}{os.environ['PATH']}", "FT_SEATS_JSON": str(env["repo"] / ".fable-team/seats.json"),
         "FT_THREAD_POST": str(tp), "FT_TEAMS_REF": "HEAD", **extra}  # R406: 픽스처 명단은 커밋된 HEAD 에만 있다(origin/main ref 0) — 실 리포는 origin/main
    return subprocess.run(["bash", str(env["hb"] / "ft-nano-spawn.sh"), str(card)], capture_output=True, text=True, cwd=env["repo"], env=e), card


def undo_calls(env):
    p = env["tmp"] / "undo.log"
    return p.read_text().splitlines() if p.exists() else []


def seats_text(env):
    return (env["repo"] / ".fable-team/seats.json").read_text()


def test_spawn_unknown_ledger_rejects_before_any_side_effect(env):
    exe(env["tmp"] / "tp.sh", "echo UNKNOWN >&2\nexit 3\n")
    before = CARD.replace("## 상태\n", "## 상태\n" + SLACK)
    r, card = spawn(env, before)
    assert r.returncode == 1 and "슬랙 장부 불명" in r.stdout and "부작용 0" in r.stdout
    assert not (env["tmp"] / "opened").exists() and card.read_text() == before and seats_text(env) == "{}\n"
    assert not (env["repo"] / ".worktrees").exists() and not undo_calls(env)


def test_spawn_tag_failure_rolls_back_via_undo_with_owned_values(env):
    r, _ = spawn(env, TAG_VAL="0")
    assert r.returncode == 1 and "태그 확인 실패" in r.stdout and "UNDONE" in r.stdout
    assert len(undo_calls(env)) == 1 and "--owned %1:123" in undo_calls(env)[0] and seats_text(env) == "{}\n"


def test_spawn_open_failure_with_live_session_rolls_back(env):
    r, _ = spawn(env, TMUXC_RC="1")
    assert r.returncode == 1 and "tmuxc open 실패" in r.stdout and len(undo_calls(env)) == 1


def test_spawn_move_failure_kills_nothing_and_asks_human(env):
    exe(env["hb"] / "ft-index-move.sh", "exit 1\n")
    r, _ = spawn(env)
    assert r.returncode == 1 and "사람 판정" in r.stdout and "⑥ 인덱스 이동" in r.stdout and not undo_calls(env)
    assert SEAT in seats_text(env)


def test_spawn_roster_write_failure_kills_nothing_and_asks_human(env):
    (env["repo"] / ".fable-team/seats.json").chmod(0o444)
    r, _ = spawn(env)
    assert r.returncode == 1 and "사람 판정" in r.stdout and "⑤ 명부 등록" in r.stdout and not undo_calls(env)


def test_spawn_normal_path_unchanged(env):
    r, card = spawn(env)
    assert r.returncode == 0 and "SPAWNED" in r.stdout and not undo_calls(env)
    assert SEAT in seats_text(env) and "base_sha:" in card.read_text()


def test_spawn_card_without_slack_line_never_calls_check(env):
    exe(env["tmp"] / "tp.sh", f"touch {env['tmp']}/tp.called\nexit 0\n")
    r, _ = spawn(env)
    assert r.returncode == 0 and not (env["tmp"] / "tp.called").exists()


# ---- undo — 롤백 모드 ----

def killed(env):
    return "kill-session" in tmux_log(env)


def test_undo_all_conditions_met_kills_once_and_keeps_everything_else(tmp_path):
    e = make_env(tmp_path)
    seats0, card0 = e["seats"].read_text(), e["card"].read_text()
    r = roll(e)
    assert r.returncode == 0 and r.stdout.strip() == f"UNDONE {SEAT}", r.stdout
    log = tmux_log(e)
    assert log.count("kill-session -t %1") == 1 and "set-option -t %1 -u @zc_v65_active" in log
    assert e["seats"].read_text() == seats0 and e["card"].read_text() == card0 and e["wt"].is_dir()
    assert "spawn-undo ROLL" in e["ledger"].read_text() and not (e["state"] / "spawn-undo" / f"{SEAT}.lock").exists()


@pytest.mark.parametrize("name", sorted(BREAKS))
def test_undo_rejects_when_one_condition_breaks_and_kills_nothing(tmp_path, name):
    e = make_env(tmp_path)
    BREAKS[name](e)
    card = e["card"] if e["card"].exists() else e["card"].parents[1] / "slug.md"
    r = undo(e, "--owned", owned(e), "--card", str(card))
    assert r.returncode == 1 and r.stdout.startswith("REJECT"), r.stdout
    assert not killed(e) and "-u @zc_v65_active" not in tmux_log(e)


def test_undo_rejects_foreign_prefix_pane_and_created(tmp_path):
    e = make_env(tmp_path)
    assert undo(e, "--owned", owned(e), "--card", str(e["card"]), FT_NANO_PREFIX="other-").returncode == 1
    assert undo(e, "--owned", "%9:" + owned(e).split(":")[1], "--card", str(e["card"])).returncode == 1
    assert undo(e, "--owned", "%1:1", "--card", str(e["card"])).returncode == 1
    assert not killed(e)


def test_undo_dirty_serena_yaml_only_still_passes_and_jsonl_zero_turns_pass(tmp_path):
    e = make_env(tmp_path)
    jsonl(e, {"type": "user", "message": {"content": [{"type": "tool_result", "content": "x"}]}})
    assert roll(e).returncode == 0 and killed(e)


def test_undo_recheck_catches_mail_arriving_after_tag_unset_and_restores_tag(tmp_path):
    e = make_env(tmp_path)
    (tmp_path / "race").write_text("")
    r = roll(e)
    assert r.returncode == 1 and "ⓓ" in r.stdout and not killed(e)
    assert tmux_log(e).rstrip().endswith("set-option -t %1 @zc_v65_active 1")


def test_undo_lock_held_rejects(tmp_path):
    e = make_env(tmp_path)
    (e["state"] / "spawn-undo" / f"{SEAT}.lock").mkdir(parents=True)
    r = roll(e)
    assert r.returncode == 1 and "락" in r.stdout and not killed(e)


# ---- undo — 단독 모드 ----

def test_standalone_plans_without_killing_and_plan_rechecks_at_run_time(tmp_path):
    e = make_env(tmp_path)
    roster(e)
    jsonl(e)
    (e["tmp"] / "notdir").write_text("")  # R83: ft-hil.sh 실패(HIL_DIR 이 폴더가 아님) = 지금 문구 그대로 + WARN(stderr)
    r = undo(e, "--card", str(e["card"]), HIL_DIR=str(e["tmp"] / "notdir"), HIL_CLIP="0")
    plan = e["state"] / "spawn-undo" / f"{SEAT}.sh.hil"
    assert r.returncode == 0 and r.stdout.strip() == f"PLANNED {SEAT} {plan}" and plan.is_file() and "WARN ft-hil 실패" in r.stderr
    hd = e["tmp"] / "hil-dir"  # R83: ft-hil.sh 성공 = 앞부분 PLANNED <좌석> <경로> 유지 + 짧은 안내 덧붙임
    r2 = undo(e, "--card", str(e["card"]), HIL_DIR=str(hd), HIL_CLIP="0")
    assert r2.stdout.strip() == f"PLANNED {SEAT} {plan} · 사람 ! 실행: ! bash {hd}/h1" and "WARN" not in r2.stderr and f"# ft-hil-entry plan={plan.resolve()}\n" in (hd / "h1").read_text()  # R186: 링크 → 진입 파일(표식 줄에 계획 절대경로)
    assert not killed(e) and "-u @zc_v65_active" not in tmux_log(e)
    penv = {**os.environ, "PATH": f"{e['sh']}{os.pathsep}{os.environ['PATH']}", "HOME": str(e["home"]), "R81_DIR": str(tmp_path),
            "R81_SEAT": SEAT, "R81_WT": str(e["wt"])}
    log_row(e)  # 계획 생성 뒤 쪽지 1건 — 실행 시점 재검사가 중단시킨다
    run = subprocess.run(["bash", str(plan)], capture_output=True, text=True, cwd=e["repo"], env=penv)
    assert run.returncode == 1 and "ⓓ" in run.stdout and not killed(e) and SEAT in e["seats"].read_text()
    (e["comm"] / "mailbox.log.jsonl").write_text("")
    run = subprocess.run(["bash", str(plan)], capture_output=True, text=True, cwd=e["repo"], env=penv)
    assert run.returncode == 0 and killed(e) and SEAT not in e["seats"].read_text() and e["wt"].is_dir()


def test_standalone_rejects_orphan_with_commit_or_user_turn(tmp_path):
    e = make_env(tmp_path)
    roster(e)
    jsonl(e)
    commit_in_wt(e)
    r = undo(e, "--card", str(e["card"]))
    assert r.returncode == 1 and "ⓔ" in r.stdout and not (e["state"] / "spawn-undo" / f"{SEAT}.sh.hil").exists()
