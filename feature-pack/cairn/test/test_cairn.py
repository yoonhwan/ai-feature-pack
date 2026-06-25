from pathlib import Path
import cairn

GOLDEN = Path(__file__).resolve().parent.parent / "core" / "golden.yaml"


def test_load_plan_reads_projects():
    data = cairn.load_plan(GOLDEN)
    assert data["version"] == 1
    assert [p["id"] for p in data["projects"]] == ["project-a"]
    assert data["projects"][0]["milestones"][1]["id"] == "ms2"


def test_dump_str_roundtrip_preserves_structure():
    data = cairn.load_plan(GOLDEN)
    out = cairn.dump_str(data)
    assert "project-a" in out and "ms2" in out
    # 재로드 동치
    import io
    again = cairn.yaml.load(io.StringIO(out))
    assert again["projects"][0]["id"] == "project-a"


# ── Task2: validate ──────────────────────────────────────────────────────────
import copy


def _good():
    return cairn.load_plan(GOLDEN)


def test_validate_good_is_empty():
    assert cairn.validate(_good()) == []


def test_validate_duplicate_project_id():
    d = _good(); d["projects"].append(copy.deepcopy(d["projects"][0]))
    assert any("duplicate project id" in e for e in cairn.validate(d))


def test_validate_bad_status_enum():
    d = _good(); d["projects"][0]["status"] = "nope"
    assert any("status" in e for e in cairn.validate(d))


def test_validate_missing_required_field():
    d = _good(); del d["projects"][0]["milestones"][0]["name"]
    assert any("name" in e for e in cairn.validate(d))


def test_validate_depends_on_missing_target():
    d = _good(); d["projects"][0]["milestones"][1]["depends_on"] = ["ghost"]
    assert any("ghost" in e for e in cairn.validate(d))


def test_validate_depends_on_cycle():
    d = _good()
    ms = d["projects"][0]["milestones"]
    ms[0]["depends_on"] = ["ms2"]  # ms1->ms2, ms2->ms1 = cycle
    assert any("cycle" in e for e in cairn.validate(d))


def test_validate_self_reference():
    d = _good(); d["projects"][0]["milestones"][0]["depends_on"] = ["ms1"]
    assert any("self" in e or "cycle" in e for e in cairn.validate(d))


# ── Task3: save_atomic ───────────────────────────────────────────────────────
import pytest


def test_save_atomic_writes_valid(tmp_path):
    d = _good()
    target = tmp_path / "all.yaml"
    cairn.save_atomic(d, target)
    assert target.exists()
    reloaded = cairn.load_plan(target)
    assert reloaded["projects"][0]["id"] == "project-a"


def test_save_atomic_rejects_invalid(tmp_path):
    d = _good(); d["projects"][0]["status"] = "nope"
    target = tmp_path / "all.yaml"
    with pytest.raises(ValueError):
        cairn.save_atomic(d, target)
    assert not target.exists()        # 무효면 흔적 없음


def test_save_atomic_no_partial_on_existing(tmp_path):
    target = tmp_path / "all.yaml"
    cairn.save_atomic(_good(), target)
    before = target.read_text()
    bad = _good(); bad["projects"][0]["milestones"][0]["status"] = "nope"
    with pytest.raises(ValueError):
        cairn.save_atomic(bad, target)
    assert target.read_text() == before   # 기존 파일 불변


# ── Task4: render ────────────────────────────────────────────────────────────
def test_render_is_deterministic():
    d = _good()
    assert cairn.render(d) == cairn.render(d)


def test_render_contains_gantt_and_milestones():
    out = cairn.render(_good())
    assert "```mermaid" in out and "gantt" in out
    assert "Project A" in out
    assert "Milestone Design" in out and "Build" in out
    # done 마일스톤은 done 태그
    assert "done," in out or ":done" in out


def test_write_view_creates_file(tmp_path):
    target = tmp_path / "plan.md"
    cairn.write_view(_good(), target)
    assert "gantt" in target.read_text()


# ── Task5: overdue_list + main ───────────────────────────────────────────────
import datetime


def test_overdue_list_flags_past_unfinished():
    d = _good()
    # ms2: end 2026-06-25, active → today 2026-06-30이면 지연
    today = datetime.date(2026, 6, 30)
    res = cairn.overdue_list(d, today)
    ids = [mid for (_p, mid, _e) in res]
    assert "ms2" in ids and "ms1" not in ids   # ms1은 done이라 제외


def test_overdue_excludes_future():
    d = _good()
    today = datetime.date(2026, 6, 1)
    assert cairn.overdue_list(d, today) == []


def test_main_status_runs(capsys):
    rc = cairn.main(["status", "--file", str(GOLDEN)])
    out = capsys.readouterr().out
    assert rc == 0 and "project-a" in out


# ── Task6: transaction + set-status ─────────────────────────────────────────
import subprocess
import os as _os


def _init_repo(tmp_path):
    (tmp_path / ".cairn" / "views").mkdir(parents=True)
    cairn.save_atomic(_good(), tmp_path / ".cairn" / "plan.yaml")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    # 교정#5: git 신원 영구 설정 → transaction commit 시 신원 오류 없음
    subprocess.run(["git", "config", "user.email", "t@t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "config", "user.name", "t"], cwd=tmp_path, check=True)
    subprocess.run(["git", "add", "-A"], cwd=tmp_path, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "seed"], cwd=tmp_path, check=True)
    return tmp_path


def _mp(monkeypatch, repo):
    for attr, val in [("REPO", repo), ("PLAN_PATH", repo / ".cairn" / "plan.yaml"),
                      ("VIEW_PATH", repo / ".cairn" / "views" / "plan.md"),
                      ("LOCK_PATH", repo / ".cairn" / ".lock")]:
        monkeypatch.setattr(cairn, attr, val)


def test_set_status_persists_and_commits(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-status", "project-a", "task", "ms2", "t3", "done"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t3 = cairn.find_task(cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2"), "t3")
    assert t3["status"] == "done"
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo,
                         capture_output=True, text=True).stdout
    assert "set-status" in log


def test_set_status_invalid_status_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-status", "project-a", "task", "ms2", "t3", "nope"])
    assert rc != 0


# ── Task7: 나머지 쓰기 명령 ──────────────────────────────────────────────────
def test_set_date(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["set-date", "project-a", "ms2", "end", "2026-06-27"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2")["end"] == "2026-06-27"


def test_add_task(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["add-task", "project-a", "ms2", "QA Validation"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    names = [t["name"] for t in cairn.find_milestone(
        cairn.find_project(d, "project-a"), "ms2")["tasks"]]
    assert "QA Validation" in names


def test_new_project(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["new-project", "Project B"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert cairn.find_project(d, "project-b") is not None


# ── Task8: validate/revert/self-test ────────────────────────────────────────
def test_self_test_passes_on_golden(capsys):
    rc = cairn.main(["self-test", "--file", str(GOLDEN)])
    assert rc == 0
    assert "self-test OK" in capsys.readouterr().out


def test_self_test_ignores_real_data(tmp_path, capsys):
    """render가 달라지는 변조 파일을 --file로 넘겨도 self-test는 golden 기반으로 rc=0."""
    d = _good()
    # milestone end 날짜 변경 → render(간트) 결과가 golden.view.md와 달라짐
    cairn.find_project(d, "project-a")["milestones"][0]["end"] = "2099-12-31"
    tmp_file = tmp_path / "all.yaml"
    tmp_file.write_text(cairn.dump_str(d))
    rc = cairn.main(["self-test", "--file", str(tmp_file)])
    assert rc == 0
    assert "self-test OK" in capsys.readouterr().out


def test_validate_cli_reports_errors(tmp_path, capsys):
    bad = tmp_path / "bad.yaml"
    d = _good(); d["projects"][0]["status"] = "nope"
    with open(bad, "w") as f: f.write(cairn.dump_str(d))
    rc = cairn.main(["validate", "--file", str(bad)])
    assert rc == 1 and "status" in capsys.readouterr().out


def test_revert_undoes_last(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-status", "project-a", "task", "ms2", "t3", "done"])
    cairn.main(["revert"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t3 = cairn.find_task(cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2"), "t3")
    assert t3["status"] == "todo"   # 되돌려짐


def test_revert_skips_non_plan_head(tmp_path, monkeypatch):
    """비-plan 커밋이 HEAD여도 직전 plan 커밋을 revert해야 한다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    # plan 커밋 생성
    cairn.main(["set-status", "project-a", "task", "ms2", "t3", "done"])
    # 비-plan 커밋으로 HEAD를 밀어냄
    (repo / "README.md").write_text("hello")
    subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "docs: non-plan commit"], cwd=repo, check=True)
    # revert → plan 커밋을 되돌려야 함 (HEAD의 README 변경이 아니라)
    rc = cairn.main(["revert"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t3 = cairn.find_task(cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2"), "t3")
    assert t3["status"] == "todo"   # done → todo 되돌려짐


# ── DA 배치1: F1·F2·F3 ───────────────────────────────────────────────────────

def test_write_cmd_rejects_file_flag(tmp_path, monkeypatch):
    """[F1 재현] 쓰기 명령에 --file이 허용되면 안 됨 (거짓 계약)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    with pytest.raises(SystemExit):
        cairn.main(["set-status", "--file", str(repo / ".cairn" / "plan.yaml"),
                   "project-a", "task", "t3", "done"])


def test_transaction_blocks_dirty_worktree(tmp_path, monkeypatch):
    """[F2 재현] CLI 밖 수동 변경이 있으면 transaction이 중단해야 한다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    plan_file = repo / ".cairn" / "plan.yaml"
    plan_file.write_text(plan_file.read_text() + "# dirty\n")
    rc = cairn.main(["set-status", "project-a", "milestone", "ms1", "done"])
    assert rc != 0


def test_dirty_worktree_cli_clean_error(tmp_path, monkeypatch, capsys):
    """[F2-fix] dirty worktree 시 rc!=0 + stderr에 Traceback 없이 메시지만."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    plan_file = repo / ".cairn" / "plan.yaml"
    plan_file.write_text(plan_file.read_text() + "# dirty\n")
    rc = cairn.main(["set-status", "project-a", "milestone", "ms1", "done"])
    captured = capsys.readouterr()
    assert rc != 0
    assert "Traceback" not in (captured.out + captured.err)
    assert "dirty" in (captured.out + captured.err)


def test_set_status_task_requires_milestone_id(tmp_path, monkeypatch):
    """[F3 재현] milestone id 없이 task set-status → 인자 부족으로 rc!=0."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-status", "project-a", "task", "t3", "done"])
    assert rc != 0


# ── needs#1: project kind id 중복 제거 ────────────────────────────────────────

def test_set_status_project_without_id(tmp_path, monkeypatch):
    """[needs#1] project kind는 id 생략: set-status <proj> project <status>"""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-status", "project-a", "project", "active"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert cairn.find_project(d, "project-a")["status"] == "active"


def test_set_status_project_duplicate_id_rejected(tmp_path, monkeypatch):
    """[needs#1] project kind에 id를 두 번 넣으면 rc!=0 (기존 오동작 방지)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-status", "project-a", "project", "project-a", "active"])
    assert rc != 0


# ── DA 배치2: F4·F5·F6 ───────────────────────────────────────────────────────

# F4: validate 보강
def test_validate_task_depends_on_missing():
    """[F4] task depends_on이 없는 task id를 가리키면 오류."""
    d = _good(); d["projects"][0]["milestones"][1]["tasks"][1]["depends_on"] = ["ghost"]
    assert any("ghost" in e for e in cairn.validate(d))


def test_validate_task_depends_on_cycle():
    """[F4] task depends_on 순환이면 오류."""
    d = _good()
    tasks = d["projects"][0]["milestones"][1]["tasks"]
    tasks[0]["depends_on"] = [tasks[1]["id"]]
    tasks[1]["depends_on"] = [tasks[0]["id"]]
    assert any("cycle" in e for e in cairn.validate(d))


def test_validate_bad_date_format():
    """[F4] start 날짜가 ISO 형식이 아니면 오류."""
    d = _good(); d["projects"][0]["milestones"][1]["start"] = "not-a-date"
    assert any("date" in e or "start" in e for e in cairn.validate(d))


def test_validate_start_after_end():
    """[F4] start > end이면 오류."""
    d = _good()
    d["projects"][0]["milestones"][1]["start"] = "2026-07-01"
    d["projects"][0]["milestones"][1]["end"] = "2026-06-25"
    assert any("start" in e or "end" in e for e in cairn.validate(d))


# F5: render 이스케이프
def test_validate_name_rejects_control_chars():
    """[F5] name에 개행 등 제어문자가 있으면 validate 오류."""
    d = _good(); d["projects"][0]["milestones"][0]["name"] = "Bad\nName"
    assert any("control" in e or "name" in e for e in cairn.validate(d))


def test_render_escapes_colon_in_name():
    """[F5] 마일스톤 name의 콜론이 Mermaid 줄에 raw 노출되면 파싱 깨짐."""
    d = _good(); d["projects"][0]["milestones"][0]["name"] = "Phase: Alpha"
    out = cairn.render(d)
    # "Phase: Alpha" literal이 render 출력에 있으면 Mermaid parser가 깨짐
    assert "Phase: Alpha" not in out


# F6: YAML 파싱오류 처리
def test_main_corrupt_yaml_short_error(tmp_path, capsys):
    """[F6] 손상된 YAML 파일 → rc != 0, traceback 없이 짧은 오류."""
    bad = tmp_path / "bad.yaml"
    bad.write_text(": invalid: yaml: {{{")
    rc = cairn.main(["status", "--file", str(bad)])
    assert rc != 0
    err = capsys.readouterr().err
    assert "Traceback" not in err
    assert len(err.strip()) > 0


# ── G-라운드: 무결성/안전 실버그 ────────────────────────────────────────────

def test_g1_root_file_rejects_before_write_cmd():
    """[G1] 루트 레벨 --file + write 서브커맨드는 SystemExit(argparse 오류)."""
    with pytest.raises(SystemExit):
        cairn.main(["--file", "dummy.yaml", "set-date", "proj", "ms1", "end", "2026-01-01"])


def test_g2_transaction_commit_excludes_unrelated_staged(tmp_path, monkeypatch):
    """[G2] transaction commit이 plan/view 외 staged 파일을 포함하지 않아야 함."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    extra = repo / "README.md"
    extra.write_text("hello")
    subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
    cairn.main(["set-status", "project-a", "milestone", "ms1", "active"])
    committed = subprocess.run(["git", "show", "--name-only", "--format="],
                               cwd=repo, capture_output=True, text=True).stdout
    assert "README.md" not in committed
    staged = subprocess.run(["git", "diff", "--cached", "--name-only"],
                            cwd=repo, capture_output=True, text=True).stdout
    assert "README.md" in staged


def test_g3_rollback_preserves_other_tracked_changes(tmp_path, monkeypatch):
    """[G3] commit 실패 시 plan/view만 복원, 다른 tracked 변경 보존."""
    import stat
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    extra = repo / "NOTES.txt"
    extra.write_text("v1")
    subprocess.run(["git", "add", "NOTES.txt"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "notes"], cwd=repo, check=True)
    extra.write_text("v2")
    hooks_dir = repo / ".git" / "hooks"
    hook = hooks_dir / "pre-commit"
    hook.write_text("#!/bin/sh\nexit 1\n")
    hook.chmod(hook.stat().st_mode | stat.S_IEXEC)
    rc = cairn.main(["set-status", "project-a", "milestone", "ms1", "active"])
    assert rc != 0
    assert extra.read_text() == "v2"


def test_g4_render_fails_on_invalid_data(tmp_path, monkeypatch):
    """[G4] render는 invalid data면 rc!=0 반환(validate 호출 필수)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    pf = repo / ".cairn" / "plan.yaml"
    bad = cairn.load_plan(pf)
    bad["projects"][0]["status"] = "nope"
    with open(pf, "w") as f:
        cairn.yaml.dump(bad, f)
    rc = cairn.main(["render"])
    assert rc != 0


def test_g4_validate_rejects_project_name_control_chars():
    """[G4] project name에 제어문자가 있으면 validate 오류."""
    d = _good()
    d["projects"][0]["name"] = "Bad\nProject"
    assert any("control" in e or "name" in e for e in cairn.validate(d))


# ── S-라운드: 운영 시뮬 핸들러 예외 ─────────────────────────────────────────

# S1: FileNotFoundError — self-test golden 누락
def test_self_test_missing_golden_clean_error(tmp_path, monkeypatch, capsys):
    """[S1] golden.yaml 누락 시 rc!=0, traceback 없이 깔끔한 오류 메시지."""
    monkeypatch.setattr(cairn, "GOLDEN_PATH", tmp_path / "nope.yaml")   # 없는 경로
    rc = cairn.main(["self-test"])
    captured = capsys.readouterr()
    assert rc != 0
    assert "Traceback" not in (captured.out + captured.err)


# S2: YAML 파싱오류 — handler 내부 load (golden 손상)
def test_self_test_corrupt_golden_clean_error(tmp_path, monkeypatch, capsys):
    """[S2] handler 내부 load가 손상된 YAML 만나면 rc!=0, traceback 없음."""
    golden = tmp_path / "golden.yaml"
    golden.write_text(": {{{invalid yaml")
    monkeypatch.setattr(cairn, "GOLDEN_PATH", golden)
    rc = cairn.main(["self-test"])
    captured = capsys.readouterr()
    assert rc != 0
    assert "Traceback" not in (captured.out + captured.err)


# ── Phase 1.6 하드닝 ─────────────────────────────────────────────────────────

# P1.6-1: revert는 plan/view 두 파일만 복원
def test_revert_restores_only_plan_and_view(tmp_path, monkeypatch):
    """[P1.6-1] revert는 plan/view만 부모 상태로 복원 — 같은 커밋에 섞인 무관 파일은 보존."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    pf = repo / ".cairn" / "plan.yaml"
    # 1) 정상 CLI 커밋으로 views/plan.md 생성 + 베이스라인(ms1=active)
    cairn.main(["set-status", "project-a", "milestone", "ms1", "active"])
    # 2) plan 변경(ms1=blocked) + 무관 파일을 하나의 커밋에 수동으로 함께 커밋
    d = cairn.load_plan(pf)
    cairn.find_project(d, "project-a")["milestones"][0]["status"] = "blocked"
    pf.write_text(cairn.dump_str(d))
    other = repo / "other.txt"
    other.write_text("keep-me")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "mixed plan+other"], cwd=repo, check=True)
    # 3) revert → 직전 plan 커밋(mixed)을 되돌림
    rc = cairn.main(["revert"])
    assert rc == 0
    d2 = cairn.load_plan(pf)
    # plan은 부모 상태(blocked→active)로 복원
    assert cairn.find_project(d2, "project-a")["milestones"][0]["status"] == "active"
    # 무관 파일은 보존 (git revert 전체였다면 other 추가가 취소되어 삭제됨)
    assert other.exists() and other.read_text() == "keep-me"


# P1.6-2: project name(section)도 milestone과 동일하게 sanitize
def test_render_escapes_colon_in_project_name():
    """[P1.6-2] project name(section)의 콜론도 milestone과 동일하게 sanitize."""
    d = _good(); d["projects"][0]["name"] = "Proj: X"
    out = cairn.render(d)
    assert "Proj: X" not in out          # raw 콜론 노출 금지
    assert "section Proj- X" in out      # milestone과 동일 규칙(:→-)


# P1.6-4: new-project 빈 slug 즉시 친절 거부
def test_new_project_empty_slug_rejected(tmp_path, monkeypatch, capsys):
    """[P1.6-4] 비ASCII-only 이름 → 빈 slug → traceback 없이 친절한 거부."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["new-project", "한글전용"])
    captured = capsys.readouterr()
    assert rc != 0
    assert "Traceback" not in (captured.out + captured.err)
    msg = (captured.out + captured.err).lower()
    assert "slug" in msg or "ascii" in msg


# ── needs#7: revert/self-test SoT 선행 로드 분리 ─────────────────────────────

def test_revert_works_with_corrupt_sot(tmp_path, monkeypatch):
    """[needs#7] SoT YAML 파싱 불가 상태에서도 revert가 동작해야 함."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-status", "project-a", "milestone", "ms1", "active"])
    (repo / ".cairn" / "plan.yaml").write_text(": {{{invalid yaml")
    rc = cairn.main(["revert"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    # golden ms1 초기 status는 "done" — revert로 active→done 복원
    assert cairn.find_project(d, "project-a")["milestones"][0]["status"] == "done"


def test_self_test_works_with_corrupt_sot(tmp_path, monkeypatch, capsys):
    """[needs#7] SoT YAML 파싱 불가 상태에서도 self-test는 golden으로 독립 통과."""
    monkeypatch.setattr(cairn, "PLAN_PATH", tmp_path / "corrupt.yaml")
    (tmp_path / "corrupt.yaml").write_text(": {{{invalid yaml")
    rc = cairn.main(["self-test"])
    assert rc == 0
    assert "self-test OK" in capsys.readouterr().out


# ── needs#3: remove-task / remove-milestone / remove-project ─────────────────

def test_remove_task_success(tmp_path, monkeypatch):
    """[needs#3] remove-task: t3 삭제 후 ms2에 없어야 함."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["remove-task", "project-a", "ms2", "t3"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    ms2 = cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2")
    assert cairn.find_task(ms2, "t3") is None
    assert cairn.find_task(ms2, "t2") is not None  # 다른 task 보존


def test_remove_task_rejected_when_depended_on(tmp_path, monkeypatch):
    """[needs#3] 다른 task가 depends_on으로 참조 중이면 삭제 거부."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    ms2 = cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2")
    ms2["tasks"].append({"id": "t4", "name": "T4", "status": "todo", "depends_on": ["t3"]})
    cairn.save_atomic(d, repo / ".cairn" / "plan.yaml")
    import subprocess as _sp
    _sp.run(["git", "add", "-A"], cwd=repo, check=True)
    _sp.run(["git", "commit", "-q", "-m", "add t4 dep"], cwd=repo, check=True)
    rc = cairn.main(["remove-task", "project-a", "ms2", "t3"])
    assert rc != 0


def test_remove_milestone_requires_empty_tasks(tmp_path, monkeypatch):
    """[needs#3] task가 있는 milestone 삭제 거부 (leaf-first)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["remove-milestone", "project-a", "ms2"])
    assert rc != 0


def test_remove_milestone_after_emptied(tmp_path, monkeypatch):
    """[needs#3] task 모두 제거 후 milestone 삭제 가능 (ms2: 아무도 참조 안 함)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["remove-task", "project-a", "ms2", "t2"])
    cairn.main(["remove-task", "project-a", "ms2", "t3"])
    rc = cairn.main(["remove-milestone", "project-a", "ms2"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert cairn.find_milestone(cairn.find_project(d, "project-a"), "ms2") is None


def test_remove_milestone_rejected_when_depended_on(tmp_path, monkeypatch):
    """[needs#3] 다른 milestone이 depends_on으로 참조 중이면 task 비워도 거부."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["remove-task", "project-a", "ms1", "t1"])  # ms1을 비워도
    rc = cairn.main(["remove-milestone", "project-a", "ms1"])
    assert rc != 0  # ms2가 depends_on: [ms1] 참조 → 거부


def test_remove_project_requires_empty_milestones(tmp_path, monkeypatch):
    """[needs#3] milestone이 있는 project 삭제 거부 (leaf-first)."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["remove-project", "project-a"])
    assert rc != 0


def test_remove_project_empty(tmp_path, monkeypatch):
    """[needs#3] milestone 없는 project 삭제 가능."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["new-project", "Empty Project"])
    rc = cairn.main(["remove-project", "empty-project"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert cairn.find_project(d, "empty-project") is None


def test_add_task_records_start_and_due_today(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    rc = cairn.main(["add-task", "project-a", "ms2", "New Task"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t = d["projects"][0]["milestones"][1]["tasks"][-1]
    assert t["name"] == "New Task"
    assert t["start"] == "2026-06-25"
    assert t["due"] == "2026-06-25"


def test_add_task_days_offsets_due(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    rc = cairn.main(["add-task", "project-a", "ms2", "Sprint Task", "--days", "3"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t = d["projects"][0]["milestones"][1]["tasks"][-1]
    assert t["start"] == "2026-06-25"
    assert t["due"] == "2026-06-28"


def test_overdue_tasks_flags_past_due(tmp_path):
    d = _good()
    ms2_tasks = d["projects"][0]["milestones"][1]["tasks"]
    ms2_tasks[0]["due"] = "2026-07-01"   # t2 미래 → 제외
    ms2_tasks[1]["due"] = "2026-06-20"   # t3 과거 → 지연
    today = datetime.date(2026, 6, 25)
    res = cairn.overdue_tasks(d, today)
    tids = [tid for (_p, _m, tid, _due) in res]
    assert "t3" in tids and "t2" not in tids


def test_overdue_tasks_skips_done_and_missing_due(tmp_path):
    d = _good()
    d["projects"][0]["milestones"][0]["tasks"][0]["due"] = "2026-06-01"  # t1 done
    today = datetime.date(2026, 6, 25)
    assert cairn.overdue_tasks(d, today) == []


def test_cmd_overdue_reports_tasks(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    d["projects"][0]["milestones"][1]["tasks"][1]["due"] = "2026-06-20"
    cairn.save_atomic(d, repo / ".cairn" / "plan.yaml")
    rc = cairn.main(["overdue", "--today", "2026-06-25"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "t3" in out and "2026-06-20" in out


def test_set_date_task_due(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-date", "project-a", "ms2", "due", "2026-07-05", "--task", "t3"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t3 = next(t for t in d["projects"][0]["milestones"][1]["tasks"] if t["id"] == "t3")
    assert t3["due"] == "2026-07-05"


def test_set_date_task_requires_due_field(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-date", "project-a", "ms2", "start", "2026-07-05", "--task", "t3"])
    assert rc == 1


def test_render_emits_task_due_marker():
    d = _good()
    d["projects"][0]["milestones"][1]["tasks"][1]["due"] = "2026-06-22"
    out = cairn.render(d)
    assert ":milestone," in out
    assert "ms2-t3" in out and "2026-06-22" in out


def test_render_omits_marker_for_task_without_due():
    out = cairn.render(_good())   # golden task엔 due 없음
    assert ":milestone," not in out


def test_p2_schedule_lifecycle_e2e(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    # 1) task 생성 (--days로 due 부여)
    assert cairn.main(["add-task", "project-a", "ms2", "Ship v2", "--days", "5"]) == 0
    # 2) due 당겨 과거로 → 지연 유발
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    new_tid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    assert cairn.main(["set-date", "project-a", "ms2", "due", "2026-06-20", "--task", new_tid]) == 0
    # 3) overdue가 잡는다
    capsys.readouterr()
    assert cairn.main(["overdue", "--today", "2026-06-25"]) == 0
    assert new_tid in capsys.readouterr().out
    # 4) 완료 처리하면 더 이상 지연 아님
    assert cairn.main(["set-status", "project-a", "task", "ms2", new_tid, "done"]) == 0
    capsys.readouterr()
    assert cairn.main(["overdue", "--today", "2026-06-25"]) == 0
    assert new_tid not in capsys.readouterr().out
    # 5) 원장 무결성 + git lineage 보존
    assert cairn.validate(cairn.load_plan(repo / ".cairn" / "plan.yaml")) == []
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo,
                         capture_output=True, text=True).stdout
    assert "add-task" in log and "set-date" in log and "set-status" in log


def test_validate_recovery_edge_missing_target():
    d = _good()
    d["projects"][0]["milestones"][1]["tasks"][0]["return_to"] = "ghost-node"
    errs = cairn.validate(d)
    assert any("return_to" in e and "ghost" in e for e in errs)


def test_validate_recovery_edge_valid_passes():
    d = _good()
    t = d["projects"][0]["milestones"][1]["tasks"][0]
    t["spawned_from"] = "ms1"; t["return_to"] = "ms1"
    assert cairn.validate(d) == []


def test_find_task_anywhere_finds_across_milestones():
    d = _good()
    res = cairn.find_task_anywhere(d, "t1")
    assert len(res) == 1 and res[0][2]["id"] == "t1"


def test_spawn_records_recovery_meta(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    rc = cairn.main(["spawn", "STT fix", "--from", "t2", "--worktree", "feat-stt"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    tasks = d["projects"][0]["milestones"][1]["tasks"]
    new = tasks[-1]
    assert new["name"] == "STT fix"
    assert new["spawned_from"] == "t2"
    assert new["return_to"] == "t2"
    assert new["fanout_depth"] == 1
    assert new["execution_ref"] == "feat-stt"
    assert new["start"] == "2026-06-25"


def test_spawn_unknown_parent_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["spawn", "X", "--from", "nope"])
    assert rc == 1


def test_spawn_return_to_override(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["spawn", "Y", "--from", "t2", "--return-to", "ms1"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["projects"][0]["milestones"][1]["tasks"][-1]["return_to"] == "ms1"


def test_complete_sets_done_and_shows_return(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["spawn", "Z", "--from", "t2"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    new_tid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    capsys.readouterr()
    rc = cairn.main(["complete", new_tid])
    out = capsys.readouterr().out
    assert rc == 0
    d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    done = next(t for t in d2["projects"][0]["milestones"][1]["tasks"] if t["id"] == new_tid)
    assert done["status"] == "done"
    assert "t2" in out


def test_complete_blocks_without_return_to(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["complete", "t1"])
    assert rc == 1


def test_complete_force_overrides(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["complete", "t1", "--force"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t1 = d["projects"][0]["milestones"][0]["tasks"][0]
    assert t1["status"] == "done"
    # [DA#5] return_to 없이 강제 완료한 것은 원장에 추적 표식이 남아야 함
    assert t1["forced_complete"] is True


def test_complete_with_return_to_no_forced_flag(tmp_path, monkeypatch):
    # [DA#5] 정상 완료(return_to 있음)는 forced 표식 없음
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["spawn", "Z", "--from", "t2"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    cid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    cairn.main(["complete", cid])
    d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    done = next(t for t in d2["projects"][0]["milestones"][1]["tasks"] if t["id"] == cid)
    assert "forced_complete" not in done


def test_return_to_existing_node(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["return", "--to", "ms1"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "ms1" in out and "baton resume" in out


def test_return_to_unknown_node_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["return", "--to", "ghost"])
    assert rc == 1


def test_render_recovery_map_shows_edges():
    d = _good()
    t = d["projects"][0]["milestones"][1]["tasks"][0]
    t["spawned_from"] = "t1"; t["return_to"] = "ms1"
    out = cairn.render_recovery_map(d)
    assert "graph TD" in out
    assert "t1" in out and "ms1" in out and t["id"] in out


def test_cmd_map_writes_file(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "MAP_DIR", tmp_path / "cairnmap")
    rc = cairn.main(["map"])
    assert rc == 0
    assert (tmp_path / "cairnmap" / "recovery.md").exists()


def test_validate_rejects_global_duplicate_task_id():
    # [DA#2] 복구 메타가 task id를 전역 참조 → milestone 간 중복은 끊긴 노드 위험
    d = _good()
    d["projects"][0]["milestones"][0]["tasks"].append(
        {"id": "t2", "name": "dup", "status": "todo", "depends_on": []})  # ms2/t2와 충돌
    errs = cairn.validate(d)
    assert any("t2" in e and "duplicate" in e.lower() for e in errs)


def test_add_task_uses_global_unique_id(tmp_path, monkeypatch):
    # [DA#2] add-task도 spawn처럼 전역 유니크 id
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    rc = cairn.main(["add-task", "project-a", "ms1", "New in ms1"])  # ms1엔 t1뿐
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    new = d["projects"][0]["milestones"][0]["tasks"][-1]
    assert new["id"] == "t4"   # 전역 {t1,t2,t3} 다음 → t4 (milestone-local이면 t2로 충돌)


def test_link_sets_refs(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["link", "t2", "--execution-ref", "WT-x", "--session-ref", "byz#9"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = next(t for t in d["projects"][0]["milestones"][1]["tasks"] if t["id"] == "t2")
    assert t2["execution_ref"] == "WT-x"
    assert t2["session_ref"] == "byz#9"


def test_link_merge_back_to_validates_node(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["link", "t2", "--merge-back-to", "ghost"])
    assert rc == 1


def test_link_unknown_node_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["link", "nope", "--execution-ref", "x"])
    assert rc == 1


def test_reconcile_orphans_flags_missing_worktree():
    d = _good()
    t = d["projects"][0]["milestones"][1]["tasks"][0]
    t["execution_ref"] = "feat-gone"
    res = cairn.reconcile_orphans(d, active_refs={"feat-alive"})
    assert any(tid == "t2" and ref == "feat-gone" for (_p, _m, tid, ref) in res)


def test_reconcile_orphans_ok_when_active():
    d = _good()
    d["projects"][0]["milestones"][1]["tasks"][0]["execution_ref"] = "feat-alive"
    assert cairn.reconcile_orphans(d, active_refs={"feat-alive"}) == []


def test_reconcile_orphans_ignores_tasks_without_ref():
    d = _good()
    assert cairn.reconcile_orphans(d, active_refs=set()) == []


def test_active_worktree_refs_preserves_slash_branch(monkeypatch):
    # [DA#3] refs/heads/feature/foo → feature/foo (split("/")[-1]이면 foo로 잘림)
    fake = "worktree /x\nHEAD abc\nbranch refs/heads/feature/foo\n"
    monkeypatch.setattr(cairn, "git",
                        lambda *a, **k: type("R", (), {"stdout": fake, "returncode": 0})())
    assert "feature/foo" in cairn._active_worktree_refs()


def test_active_worktree_refs_raises_on_git_failure(monkeypatch):
    # [DA#4] git worktree list 실패를 silent 빈 set으로 삼키지 않음
    monkeypatch.setattr(cairn, "git",
                        lambda *a, **k: type("R", (), {"stdout": "", "returncode": 128})())
    import pytest
    with pytest.raises(RuntimeError):
        cairn._active_worktree_refs()


def test_hook_scripts_exist_and_call_cairn():
    base = cairn.PKG_DIR / "claude-code" / "hooks"
    pm = (base / "post-merge").read_text()
    pc = (base / "post-checkout").read_text()
    assert "cairn" in pm and "reconcile" in pm
    assert "cairn" in pc


def test_p4_hooks_lifecycle_e2e(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    # 1) spawn으로 노드 만들고 link로 execution_ref 기록
    assert cairn.main(["spawn", "Hook task", "--from", "t2"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    cid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    assert cairn.main(["link", cid, "--execution-ref", "WT-dead", "--merge-back-to", "ms2"]) == 0
    # 2) 활성 worktree 없음 → reconcile_orphans가 잡음
    d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    orphans = cairn.reconcile_orphans(d2, active_refs=set())
    assert any(tid == cid for (_p, _m, tid, _r) in orphans)
    # 3) 활성에 포함되면 orphan 아님
    assert cairn.reconcile_orphans(d2, active_refs={"WT-dead"}) == []
    # 4) merge_back_to 기록 + 원장 무결성 + git lineage
    linked = next(t for t in d2["projects"][0]["milestones"][1]["tasks"] if t["id"] == cid)
    assert linked["merge_back_to"] == "ms2"
    assert cairn.validate(d2) == []
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo,
                         capture_output=True, text=True).stdout
    assert "link" in log and "spawn" in log


def test_p3_recovery_lifecycle_e2e(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    monkeypatch.setattr(cairn, "MAP_DIR", tmp_path / "cairnmap")
    # 1) t2에서 분기
    assert cairn.main(["spawn", "Subtask A", "--from", "t2", "--worktree", "feat-a"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    child = d["projects"][0]["milestones"][1]["tasks"][-1]
    cid = child["id"]
    assert child["spawned_from"] == "t2" and child["return_to"] == "t2"
    # 2) 완료 → return_to 노출
    capsys.readouterr()
    assert cairn.main(["complete", cid]) == 0
    assert "t2" in capsys.readouterr().out
    # 3) 부모로 재앵커 안내
    capsys.readouterr()
    assert cairn.main(["return", "--to", "t2"]) == 0
    assert "baton resume" in capsys.readouterr().out
    # 4) recovery-map 생성
    assert cairn.main(["map"]) == 0
    mp = (tmp_path / "cairnmap" / "recovery.md").read_text()
    assert "graph TD" in mp and cid in mp and "t2" in mp
    # 5) 원장 무결성(복구 엣지 유효) + git lineage
    assert cairn.validate(cairn.load_plan(repo / ".cairn" / "plan.yaml")) == []
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo,
                         capture_output=True, text=True).stdout
    assert "spawn" in log and "complete" in log


def test_find_repo_discovers_from_subdir(tmp_path, monkeypatch):
    # [설치형] cwd 하위에서 실행해도 상위 .cairn 프로젝트를 찾아야 함
    (tmp_path / ".cairn").mkdir()
    sub = tmp_path / "a" / "b"; sub.mkdir(parents=True)
    monkeypatch.chdir(sub)
    assert cairn._find_repo() == tmp_path


def test_find_repo_falls_back_to_cwd_when_no_cairn(tmp_path, monkeypatch):
    # .cairn 없으면 cwd 반환 (신규 프로젝트 init 전)
    monkeypatch.chdir(tmp_path)
    assert cairn._find_repo() == tmp_path
