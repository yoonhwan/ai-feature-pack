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


# todos 톱레벨 백로그 검증 (§6.2 통합 모델, H2b)
def _good_with_todos():
    d = _good()
    d["todos"] = [
        {"id": "td1", "project": "project-a", "title": "nested 확장 중 발견",
         "status": "open", "created": "2026-06-26",
         "origin_node": "t1", "ssot": "ssot/a.td1.md", "resolved_by": ["t3"]},
    ]
    return d


def test_validate_accepts_valid_todos():
    assert cairn.validate(_good_with_todos()) == []


def test_validate_todo_unknown_project():
    d = _good_with_todos(); d["todos"][0]["project"] = "ghost"
    assert any("td1" in e and "project" in e for e in cairn.validate(d))


def test_validate_todo_bad_status_vocab():
    # node 어휘 'doing'은 todo에 무효 — 어휘 분리(open/claimed/resolved/dropped)
    d = _good_with_todos(); d["todos"][0]["status"] = "doing"
    assert any("td1" in e and "status" in e for e in cairn.validate(d))


def test_validate_todo_origin_node_missing():
    d = _good_with_todos(); d["todos"][0]["origin_node"] = "ghost"
    assert any("td1" in e and "origin_node" in e for e in cairn.validate(d))


def test_validate_todo_resolved_by_missing():
    d = _good_with_todos(); d["todos"][0]["resolved_by"] = ["ghost"]
    assert any("td1" in e and "resolved_by" in e for e in cairn.validate(d))


def test_validate_todo_duplicate_id():
    d = _good_with_todos(); d["todos"].append(dict(d["todos"][0]))
    assert any("duplicate todo id" in e for e in cairn.validate(d))


def test_validate_todo_origin_node_must_be_task_not_milestone():
    # [M4] origin_node는 task만 — ms id는 거부(복구/연결은 실행단위=task 대상)
    d = _good_with_todos(); d["todos"][0]["origin_node"] = "ms1"
    assert any("td1" in e and "origin_node" in e for e in cairn.validate(d))


def test_validate_todo_resolved_by_must_be_task_not_milestone():
    d = _good_with_todos(); d["todos"][0]["resolved_by"] = ["ms1"]
    assert any("td1" in e and "resolved_by" in e for e in cairn.validate(d))


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


def test_render_milestone_without_dates_derives_from_tasks():
    """마일스톤 start/end 미설정 시 하위 태스크 날짜에서 파생.
    섹션 첫 바가 시작일 없는 ', 1d' 단독이면 mermaid가 'Invalid date'로 거부함."""
    d = _good()
    ms = d["projects"][0]["milestones"][0]
    ms["start"] = None
    ms["end"] = None
    ms["tasks"][0]["start"] = "2026-06-10"
    ms["tasks"][0]["due"] = "2026-06-12"
    out = cairn.render(d)
    ms_line = next(l for l in out.splitlines() if f", {ms['id']}," in l)
    assert not ms_line.rstrip().endswith(", 1d"), ms_line   # 시작일 없는 단독 바 금지
    assert "2026-06-10" in ms_line                          # 파생 시작일 반영


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


def test_remove_task_rejected_when_spawn_referenced(tmp_path, monkeypatch, capsys):
    """[버그] 복구엣지(spawned_from/return_to/merge_back_to)로 참조 중인 task는
    친절한 사전 메시지('referenced by')로 거부 — validate raw 'missing node'가 아니라.
    fan-out 자식이 다른 milestone에 있어도 프로젝트 전역으로 잡는다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    # t9를 ms1(다른 milestone)에 두어 크로스-마일스톤 참조 검증
    ms1 = cairn.find_milestone(cairn.find_project(d, "project-a"), "ms1")
    ms1["tasks"].append({"id": "t9", "name": "T9", "status": "todo",
                         "depends_on": [], "spawned_from": "t3"})
    cairn.save_atomic(d, repo / ".cairn" / "plan.yaml")
    import subprocess as _sp
    _sp.run(["git", "add", "-A"], cwd=repo, check=True)
    _sp.run(["git", "commit", "-q", "-m", "add t9 spawn"], cwd=repo, check=True)
    rc = cairn.main(["remove-task", "project-a", "ms2", "t3"])
    assert rc != 0
    out = capsys.readouterr().out
    assert "t9" in out and "spawned_from" in out and "referenced" in out


def test_remove_task_rejected_cross_project_ref(tmp_path, monkeypatch, capsys):
    """[버그] 다른 프로젝트의 task가 spawned_from으로 참조해도 친절 사전 차단.
    복구엣지는 cross-project fan-out을 허용하므로 사전검사는 data 전체를 순회해야 한다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    d["projects"].append({
        "id": "beta", "name": "Beta", "status": "active",
        "owner": "x", "priority": "medium", "goal": "",
        "milestones": [{"id": "bms1", "name": "B", "status": "active",
                        "start": "2026-06-10", "end": "2026-06-20", "depends_on": [],
                        "tasks": [{"id": "t9", "name": "T9", "status": "todo",
                                   "depends_on": [], "spawned_from": "t3"}]}]})
    cairn.save_atomic(d, repo / ".cairn" / "plan.yaml")
    import subprocess as _sp
    _sp.run(["git", "add", "-A"], cwd=repo, check=True)
    _sp.run(["git", "commit", "-q", "-m", "add beta"], cwd=repo, check=True)
    rc = cairn.main(["remove-task", "project-a", "ms2", "t3"])
    assert rc != 0
    out = capsys.readouterr().out
    assert "t9" in out and "referenced" in out and "spawned_from" in out


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


def test_validate_detects_spawned_from_cycle():
    # spawned_from 단일 부모 체인의 순환은 복구 그래프를 깨뜨림(depth 파생이 루트에
    # 도달 못 함) — validate가 잡아야 한다. t1→t2→t1 순환.
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    a, b = ms["tasks"][0], ms["tasks"][1]
    a["spawned_from"] = b["id"]; b["spawned_from"] = a["id"]
    errs = cairn.validate(d)
    assert any("spawned_from" in e and "cycle" in e for e in errs)


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
    # t3=todo+return_to없음 (t1은 done이라 was_done no-op로 빠짐)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["complete", "t3"])
    assert rc == 1


def test_complete_force_overrides(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["complete", "t3", "--force"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t3 = next(t for t in d["projects"][0]["milestones"][1]["tasks"] if t["id"] == "t3")
    assert t3["status"] == "done"
    # [DA#5] return_to 없이 강제 완료한 것은 원장에 추적 표식이 남아야 함
    assert t3["forced_complete"] is True


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


def test_derive_wt_br_from_execution_ref():
    # execution_ref "worktree/X" → wt=X, br 파생(같은 이름)
    assert cairn._derive_wt_br({"execution_ref": "worktree/distill-store"}) == ("distill-store", "distill-store")
    # branch 오버라이드 우선
    assert cairn._derive_wt_br({"execution_ref": "worktree/x", "branch": "feat/y"}) == ("x", "feat/y")
    # ref 없으면 워크트리 없음(wt=None) + 브랜치는 main 폴백
    assert cairn._derive_wt_br({}) == (None, "main")


def test_node_label_shows_six_fields():
    d = _good()
    t = d["projects"][0]["milestones"][0]["tasks"][0]
    t.update({"start": "2026-06-10", "finished_at": "2026-06-12",
              "execution_ref": "worktree/stt-vad", "session_ref": "session-s1-abc",
              "note": "merge->t3"})
    out = cairn.render_recovery_map(d)
    node = next(l for l in out.splitlines() if l.strip().startswith(f"{t['id']}["))
    assert "st 2026-06-10" in node and "fin 2026-06-12" in node
    assert "wt stt-vad" in node and "br stt-vad" in node
    assert "sess s1-abc" in node           # session- prefix 제거
    assert "note merge->t3" in node


def test_node_label_head_rule_omits_inherited_worktree():
    # 부모와 같은 워크트리를 공유하는 자식은 wt/br 생략 (전이 아님)
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    parent = ms["tasks"][0]; child = ms["tasks"][1]
    parent["execution_ref"] = "worktree/shared"
    child["execution_ref"] = "worktree/shared"; child["spawned_from"] = parent["id"]
    out = cairn.render_recovery_map(d)
    pnode = next(l for l in out.splitlines() if l.strip().startswith(f"{parent['id']}["))
    cnode = next(l for l in out.splitlines() if l.strip().startswith(f"{child['id']}["))
    assert "wt shared" in pnode            # 부모(전이 시작점)엔 표시
    assert "wt shared" not in cnode        # 같은 wt 상속 → 생략


def test_node_label_head_rule_shows_changed_worktree():
    # 옆으로 확장하다 워크트리가 바뀐 자식은 head로 wt 표기
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    parent = ms["tasks"][0]; child = ms["tasks"][1]
    parent["execution_ref"] = "worktree/A"
    child["execution_ref"] = "worktree/B"; child["spawned_from"] = parent["id"]
    out = cairn.render_recovery_map(d)
    cnode = next(l for l in out.splitlines() if l.strip().startswith(f"{child['id']}["))
    assert "wt B" in cnode                 # 워크트리 변경 → head 표기


def test_node_label_main_branch_for_worktreeless_nodes():
    # 워크트리 없는 노드 = main 브랜치. main 리니지의 head(루트)에만 'br main' 표기,
    # 상속 자식은 생략. main은 워크트리가 아니므로 🌿(wt) 아이콘 없음.
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    parent = ms["tasks"][0]; child = ms["tasks"][1]
    for t in (parent, child):
        t.pop("execution_ref", None); t.pop("branch", None); t.pop("merge_back_to", None)
    parent.pop("spawned_from", None)       # 루트
    child["spawned_from"] = parent["id"]
    out = cairn.render_recovery_map(d)
    pnode = next(l for l in out.splitlines() if l.strip().startswith(f"{parent['id']}["))
    cnode = next(l for l in out.splitlines() if l.strip().startswith(f"{child['id']}["))
    assert "br main" in pnode               # main 리니지 head → 표기
    assert "🌿" not in pnode                # main은 워크트리 아님 → wt 아이콘 없음
    assert "br main" not in cnode           # 같은 main 상속 → 생략


def test_recovery_map_focus_includes_descendant_subtree():
    # focus는 직계 자식뿐 아니라 손자(depth2)까지 전체 자손 서브트리를 포함해야
    # stale 손자 노드가 복구 그래프에서 사라지지 않음.
    data = {"projects": [{"milestones": [{"tasks": [
        {"id": "p", "name": "root", "status": "todo"},
        {"id": "c", "name": "child", "status": "todo", "spawned_from": "p"},
        # 손자: done + worktree + 미병합 = stale
        {"id": "g", "name": "grand", "status": "done",
         "spawned_from": "c", "execution_ref": "worktree/g"},
    ]}]}]}
    out = cairn.render_recovery_map(data, focus="p")
    assert "g[" in out                               # 손자 노드 포함
    assert "stale" in out                            # stale 클래스 적용


def test_derive_sess_renders_session_chain():
    # tmuxc 컨텍스트 핸드오프로 #1→#2→#3 늘어난 세션 체인은 first→last (N)로 압축 표시
    assert cairn._derive_sess(
        {"session_chain": ["session-t24-1", "session-t24-2", "session-t24-3"]}
    ) == "t24-1→t24-3 (3)"
    # 단일 체인은 그 하나만
    assert cairn._derive_sess({"session_chain": ["session-t24-1"]}) == "t24-1"
    # 체인 없으면 기존 session_ref 폴백
    assert cairn._derive_sess({"session_ref": "session-x"}) == "x"


def test_cmd_link_add_session_appends_chain(tmp_path, monkeypatch):
    # link --add-session: 세션 핸드오프를 체인에 누적. 기존 session_ref를 시드로,
    # active(session_ref)는 항상 최신으로 갱신.
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["link", "t2", "--session-ref", "session-t2-1"])
    cairn.main(["link", "t2", "--add-session", "session-t2-2"])
    cairn.main(["link", "t2", "--add-session", "session-t2-3"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = next(t for t in d["projects"][0]["milestones"][1]["tasks"] if t["id"] == "t2")
    assert list(t2["session_chain"]) == ["session-t2-1", "session-t2-2", "session-t2-3"]
    assert t2["session_ref"] == "session-t2-3"       # active = 최신


def test_recovery_map_hides_merged_by_default():
    # 병합된(merge_back_to) 노드는 기본 뷰에서 숨김, show_merged=True면 표시
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    merged = ms["tasks"][0]
    merged["merge_back_to"] = ms["tasks"][1]["id"]
    out = cairn.render_recovery_map(d)
    assert not any(l.strip().startswith(f"{merged['id']}[") for l in out.splitlines())
    out2 = cairn.render_recovery_map(d, show_merged=True)
    assert any(l.strip().startswith(f"{merged['id']}[") for l in out2.splitlines())


def test_recovery_map_marks_stale_branch():
    # 워크트리 있고 미병합 done = 스테일 → classDef로 구분
    d = _good()
    stale = d["projects"][0]["milestones"][1]["tasks"][0]
    stale["execution_ref"] = "worktree/orphan"
    stale["status"] = "done"
    stale.pop("merge_back_to", None)
    out = cairn.render_recovery_map(d)
    assert "classDef stale" in out
    assert any(l.strip().startswith("class ") and stale["id"] in l and "stale" in l
               for l in out.splitlines())


def test_recovery_map_distinguishes_fanout_depth():
    # Ops#2: 팬아웃 안의 팬아웃(depth2 재분기)을 depth1과 시각적으로 구분해야
    # nested fan-out임을 그래프에서 읽을 수 있다. depth는 spawned_from 체인 홉 수.
    data = {"projects": [{"milestones": [{"tasks": [
        {"id": "t21", "name": "parent", "status": "doing"},                       # depth0 루트
        {"id": "t23", "name": "d1", "status": "doing", "spawned_from": "t21"},     # depth1
        {"id": "t25", "name": "d2", "status": "doing", "spawned_from": "t23"},     # depth2
    ]}]}]}
    out = cairn.render_recovery_map(data)
    assert "classDef depth1" in out and "classDef depth2" in out
    assert any(l.strip().startswith("class ") and "t23" in l and "depth1" in l
               for l in out.splitlines())
    assert any(l.strip().startswith("class ") and "t25" in l and "depth2" in l
               for l in out.splitlines())
    # depth0 루트는 깊이 클래스 없음 (기본 스타일)
    assert not any(l.strip().startswith("class ") and "t21" in l and "depth" in l
                   for l in out.splitlines())


def test_recovery_map_drops_edges_to_hidden_merged():
    # 숨겨진 merged 노드와 연결된 엣지는 함께 제거(고아 엣지 금지)
    d = _good()
    ms = d["projects"][0]["milestones"][1]
    parent = ms["tasks"][0]; merged = ms["tasks"][1]
    merged["spawned_from"] = parent["id"]
    merged["merge_back_to"] = parent["id"]
    out = cairn.render_recovery_map(d)
    assert f"--> {merged['id']}" not in out
    assert f"{merged['id']} ==merge==>" not in out


def test_cmd_map_passes_show_merged(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    seen = {}
    real = cairn.render_recovery_map
    monkeypatch.setattr(cairn, "render_recovery_map",
                        lambda data, **kw: seen.update(kw) or real(data, **kw))
    cairn.main(["map"])
    assert seen.get("show_merged") is False
    seen.clear()
    cairn.main(["map", "--show-merged"])
    assert seen.get("show_merged") is True


def test_complete_stamps_finished_at(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "_today", lambda: datetime.date(2026, 6, 25))
    cairn.main(["spawn", "Z", "--from", "t2"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    new_tid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    cairn.main(["complete", new_tid])
    d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    done = next(t for t in d2["projects"][0]["milestones"][1]["tasks"] if t["id"] == new_tid)
    assert done["finished_at"] == "2026-06-25"


def test_cmd_map_png_renders_and_opens(tmp_path, monkeypatch, capsys):
    # --png: render_png 호출 + 성공 시 open으로 Preview 표시
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    seen = {}
    monkeypatch.setattr(cairn, "render_png",
                        lambda text, png: seen.setdefault("text", text) or Path(str(png)))
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run",
                        lambda cmd, **kw: opened.append(cmd))
    cairn.main(["map", "--png"])
    out = capsys.readouterr().out
    assert "PNG →" in out
    assert "graph TD" in seen["text"]                 # recovery-map mermaid 전달
    assert any("open" in c for c in opened)           # Preview 호출


def test_cmd_map_png_failure_falls_back(tmp_path, monkeypatch, capsys):
    # render_png 실패(None) → 안내만, open 호출 안 함
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "render_png", lambda text, png: None)
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run", lambda cmd, **kw: opened.append(cmd))
    cairn.main(["map", "--png"])
    out = capsys.readouterr().out
    assert "실패" in out
    assert not any("open" in c for c in opened)


def test_cmd_map_writes_file(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "MAP_DIR", tmp_path / "cairnmap")
    rc = cairn.main(["map"])
    assert rc == 0
    assert cairn._map_path().exists()


def test_cmd_map_html_embeds_mermaid_and_opens(tmp_path, monkeypatch, capsys):
    # --html: mermaid.js CDN을 임베드한 자체완결 HTML 생성 + macOS면 open으로 표시
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    monkeypatch.setattr(cairn, "MAP_DIR", tmp_path / "cairnmap")
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run", lambda cmd, **kw: opened.append(cmd))
    cairn.main(["map", "--html"])
    out = capsys.readouterr().out
    assert "HTML →" in out
    html = cairn._map_path().with_suffix(".html").read_text(encoding="utf-8")
    assert "mermaid.min.js" in html              # CDN 스크립트 임베드(로컬 의존성 0)
    assert "graph TD" in html                    # 그래프 mermaid 텍스트 포함
    assert any("open" in c for c in opened)      # 브라우저로 표시


def test_cmd_render_emits_html_by_default(tmp_path, monkeypatch, capsys):
    # render는 플래그 없이도 기본으로 간트 HTML을 생성 + macOS면 open
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run", lambda cmd, **kw: opened.append(cmd))
    cairn.main(["render"])
    out = capsys.readouterr().out
    assert "HTML →" in out
    html = cairn.VIEW_PATH.with_suffix(".html").read_text(encoding="utf-8")
    assert "mermaid.min.js" in html              # CDN 스크립트 임베드
    assert "gantt" in html                       # 간트차트 mermaid 포함
    assert any("open" in c for c in opened)      # 브라우저로 표시


def test_cmd_render_no_open_skips_browser(tmp_path, monkeypatch, capsys):
    # --no-open: HTML은 생성하되 브라우저는 열지 않음 (조용한 렌더)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run", lambda cmd, **kw: opened.append(cmd))
    cairn.main(["render", "--no-open"])
    assert cairn.VIEW_PATH.with_suffix(".html").exists()   # HTML은 생성
    assert not any("open" in c for c in opened)            # 브라우저는 안 열림


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
    mp = cairn._map_path().read_text()
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


def test_find_repo_prefers_git_toplevel(tmp_path, monkeypatch):
    # [버그] .cairn 없는 git 프로젝트가 상위 ~/.cairn(설치 디렉토리)을 REPO로 오인하면 안 됨.
    # git repo면 toplevel을 써야 한다.
    proj = tmp_path / "proj"; proj.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=proj, check=True)
    sub = proj / "deep"; sub.mkdir()
    monkeypatch.chdir(sub)
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                         cwd=sub, capture_output=True, text=True).stdout.strip()
    assert str(cairn._find_repo()) == top


def test_init_creates_seed_ledger(tmp_path, monkeypatch):
    # [추가스펙] 신규 프로젝트 init → 빈 시드 원장
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    for attr, val in [("REPO", tmp_path), ("PLAN_PATH", tmp_path / ".cairn" / "plan.yaml"),
                      ("VIEW_PATH", tmp_path / ".cairn" / "views" / "plan.md"),
                      ("LOCK_PATH", tmp_path / ".cairn" / ".lock")]:
        monkeypatch.setattr(cairn, attr, val)
    rc = cairn.main(["init"])
    assert rc == 0
    d = cairn.load_plan(tmp_path / ".cairn" / "plan.yaml")
    assert d["version"] == cairn.SCHEMA_VERSION and list(d["projects"]) == []
    # init 후 new-project가 동작해야 함
    assert cairn.main(["new-project", "Demo"]) == 0


def test_init_idempotent(tmp_path, monkeypatch):
    # 이미 초기화된 곳에서 init → no-op, rc 0
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["init"])
    assert rc == 0


def test_render_recovery_map_shows_merge_edge():
    # [DA-sim] merge_back_to가 있으면 머지 엣지가 그려져야 (병합 노드는 기본 숨김 → show_merged)
    d = _good()
    t = d["projects"][0]["milestones"][1]["tasks"][0]
    t["merge_back_to"] = "ms1"
    out = cairn.render_recovery_map(d, show_merged=True)
    assert "ms1" in out
    assert "merge" in out.lower()   # 머지 엣지 표기 존재


def test_spawn_outputs_generated_id(tmp_path, monkeypatch, capsys):
    # [DA-sim UX] spawn이 생성한 task id를 출력해야 후속 link/complete 가능
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["spawn", "Child", "--from", "t2"])
    out = capsys.readouterr().out
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    new_tid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    assert new_tid in out


def test_map_path_differs_by_project(tmp_path, monkeypatch):
    # [DA-sim] recovery-map 산출물이 프로젝트별로 격리돼야 (전역 오염 방지)
    monkeypatch.setattr(cairn, "MAP_DIR", tmp_path / "m")
    monkeypatch.setattr(cairn, "REPO", tmp_path / "projA")
    pa = cairn._map_path()
    monkeypatch.setattr(cairn, "REPO", tmp_path / "projB")
    pb = cairn._map_path()
    assert pa != pb


# === BYZPlan_Ops#1 운영 시뮬 발견 4건: done 노드 상태 전이 검증 ===

def test_complete_on_done_is_noted(tmp_path, monkeypatch, capsys):
    # [Ops#1-1] 이미 done인 태스크 재완료 → 침묵 말고 "이미 완료됨" 안내
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["spawn", "X", "--from", "t2"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    tid = d["projects"][0]["milestones"][1]["tasks"][-1]["id"]
    cairn.main(["complete", tid])
    capsys.readouterr()
    rc = cairn.main(["complete", tid])
    cap = capsys.readouterr(); out = cap.out + cap.err
    assert rc == 0 and "이미" in out


def test_return_to_done_node_warns(tmp_path, monkeypatch, capsys):
    # [Ops#1-2] done 노드로 복귀 시 경고
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-status", "project-a", "task", "ms1", "t1", "done"])
    capsys.readouterr()
    rc = cairn.main(["return", "--to", "t1"])
    cap = capsys.readouterr(); out = cap.out + cap.err
    assert rc == 0 and "경고" in out


def test_spawn_from_done_warns(tmp_path, monkeypatch, capsys):
    # [Ops#1-3] done 노드에서 분기 시 경고 (재개 시나리오라 허용은 유지)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-status", "project-a", "task", "ms1", "t1", "done"])
    capsys.readouterr()
    rc = cairn.main(["spawn", "child", "--from", "t1"])
    cap = capsys.readouterr(); out = cap.out + cap.err
    assert rc == 0 and "경고" in out


def test_spawn_duplicate_name_warns(tmp_path, monkeypatch, capsys):
    # [Ops#1-4] 같은 parent에서 동일 이름 분기 시 경고 (id는 유니크라 허용 유지)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["spawn", "dupname", "--from", "t2"])
    capsys.readouterr()
    rc = cairn.main(["spawn", "dupname", "--from", "t2"])
    cap = capsys.readouterr(); out = cap.out + cap.err
    assert rc == 0 and "경고" in out


# ── Schedule-Ops#1: 크로스-마일스톤 태스크 의존 + depends CLI ──────────────────
def test_validate_allows_cross_milestone_task_depends():
    # 태스크 의존은 프로젝트 전역에서 해소돼야 함 (t1@ms1 → t2@ms2). 현실 일정:
    # QA(다른 마일스톤) 태스크가 Backend 태스크에 의존.
    d = _good()
    d["projects"][0]["milestones"][0]["tasks"][0]["depends_on"] = ["t2"]
    assert not any("missing target" in e for e in cairn.validate(d))


def test_validate_detects_cross_milestone_task_cycle():
    # 마일스톤을 가로지르는 순환도 잡아야 함 (t1@ms1 ↔ t2@ms2).
    d = _good()
    d["projects"][0]["milestones"][0]["tasks"][0]["depends_on"] = ["t2"]
    d["projects"][0]["milestones"][1]["tasks"][0]["depends_on"] = ["t1"]
    assert any("cycle" in e for e in cairn.validate(d))


def test_cmd_depends_add_task_sets_depends_on(tmp_path, monkeypatch):
    # depends CLI: 크로스-마일스톤 태스크 의존을 수기 YAML 없이 설정
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["depends", "project-a", "t1", "--on", "t2"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t1 = d["projects"][0]["milestones"][0]["tasks"][0]
    assert list(t1["depends_on"]) == ["t2"]


def test_cmd_depends_milestone_add_and_remove(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["depends", "project-a", "ms2", "--on", "ms1"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert "ms1" in d["projects"][0]["milestones"][1]["depends_on"]
    cairn.main(["depends", "project-a", "ms2", "--on", "ms1", "--remove"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert "ms1" not in (d["projects"][0]["milestones"][1].get("depends_on") or [])


def test_cmd_depends_type_mismatch_rejected(tmp_path, monkeypatch, capsys):
    # 태스크가 마일스톤에 의존(또는 그 반대)은 금지 — 일정 의존은 동종 간만
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["depends", "project-a", "t1", "--on", "ms1"])
    assert rc != 0


# ── Schedule-Ops#1: 태스크 기간 막대 렌더 (0d 점 → start→due 간격) ──────────────
def test_render_task_shows_duration_bar():
    # 태스크는 start→due 기간 막대로 그려져야 함 (0d 점이 아니라 간격이 보이게)
    d = _good()
    t = d["projects"][0]["milestones"][0]["tasks"][0]  # t1@ms1
    t["start"] = "2026-06-10"; t["due"] = "2026-06-14"
    out = cairn.render(d)
    assert "ms1-t1, 2026-06-10, 2026-06-14" in out
    assert "ms1-t1, 2026-06-14, 0d" not in out


def test_render_task_without_start_falls_back_to_marker():
    # start 없으면 due에 0d 마커로 폴백 (기존 동작 보존)
    d = _good()
    t = d["projects"][0]["milestones"][0]["tasks"][0]
    t.pop("start", None); t["due"] = "2026-06-14"
    out = cairn.render(d)
    assert "milestone, ms1-t1, 2026-06-14, 0d" in out


# ── Schedule-Ops#1: 그룹(제품/목표묶음) 단위 — 마일스톤 위 한 단계 ─────────────
def test_render_groups_milestones_into_sections():
    # group 라벨이 mermaid section으로 묶여 나와야 함
    d = _good()
    d["projects"][0]["milestones"][0]["group"] = "Backend"
    d["projects"][0]["milestones"][1]["group"] = "QA"
    out = cairn.render(d)
    assert "section Project A · Backend" in out
    assert "section Project A · QA" in out


def test_validate_rejects_group_control_chars():
    d = _good()
    d["projects"][0]["milestones"][0]["group"] = "Bad\nGroup"
    assert any("group contains control" in e for e in cairn.validate(d))


def test_cmd_set_group_sets_and_clears(tmp_path, monkeypatch):
    # 빈 문자열 = 그룹 제거 (별도 --clear 플래그 없음)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-group", "project-a", "ms1", "Backend"])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["projects"][0]["milestones"][0]["group"] == "Backend"
    cairn.main(["set-group", "project-a", "ms1", ""])
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert "group" not in d["projects"][0]["milestones"][0]


def test_render_axis_format_compact_dates():
    # x축 날짜 라벨: 연 2자리 + '.' 구분(26.06.10), 주 단위 눈금으로 간격 확보
    out = cairn.render(_good())
    assert "axisFormat %y.%m.%d" in out
    assert "tickInterval 1week" in out


# ---- todos CLI v0 (DA approve된 설계) ----
def test_add_todo_creates_open_todo(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["add-todo", "project-a", "발견작업", "--from", "t1"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    todos = d.get("todos") or []
    assert len(todos) == 1
    td = todos[0]
    assert td["id"] == "td1" and td["status"] == "open"
    assert td["project"] == "project-a" and td["origin_node"] == "t1"
    assert td["title"] == "발견작업" and td["resolved_by"] == []


def test_add_todo_with_ssot_creates_file(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["add-todo", "project-a", "T", "--ssot"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["todos"][0]["ssot"] == "ssot/project-a.td1.md"
    assert (repo / ".cairn" / "ssot" / "project-a.td1.md").exists()


def test_add_todo_ssot_is_committed(tmp_path, monkeypatch):
    # §6.2 — ssot는 best-effort 커밋(원장 git 추적). untracked로 남기지 않음.
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T", "--ssot"])
    tracked = subprocess.run(["git", "-C", str(repo), "ls-files"],
                             capture_output=True, text=True).stdout
    assert ".cairn/ssot/project-a.td1.md" in tracked


def test_add_todo_rejects_unknown_project(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["add-todo", "ghost", "T"]) != 0


def test_add_todo_rejects_nonexistent_from_node(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["add-todo", "project-a", "T", "--from", "zzz"]) != 0


def test_todos_lists(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "AAA"]); capsys.readouterr()
    rc = cairn.main(["todos"]); assert rc == 0
    out = capsys.readouterr().out
    assert "td1" in out and "AAA" in out and "open" in out


def test_todos_empty(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["todos"]); assert rc == 0
    assert "없음" in capsys.readouterr().out


def test_link_todo_adds_resolved_by(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    rc = cairn.main(["link-todo", "td1", "--by", "t1"]); assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["todos"][0]["resolved_by"] == ["t1"]


def test_link_todo_remove(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    cairn.main(["link-todo", "td1", "--by", "t1"])
    rc = cairn.main(["link-todo", "td1", "--by", "t1", "--remove"]); assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["todos"][0]["resolved_by"] == []


def test_link_todo_rejects_nonexistent_node(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    assert cairn.main(["link-todo", "td1", "--by", "zzz"]) != 0


def test_set_status_todo(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    rc = cairn.main(["set-status", "project-a", "todo", "td1", "resolved"]); assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["todos"][0]["status"] == "resolved"


def test_set_status_todo_rejects_bad_vocab(tmp_path, monkeypatch):
    # node 어휘 'doing'은 todo에 무효 — validate가 차단
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    assert cairn.main(["set-status", "project-a", "todo", "td1", "doing"]) != 0


def test_remove_todo(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T"])
    rc = cairn.main(["remove-todo", "td1"]); assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert (d.get("todos") or []) == []


def test_remove_task_blocked_by_todo_resolved_by(tmp_path, monkeypatch, capsys):
    # [H2] 사전검사 — task가 todo.resolved_by에 있으면 친절 차단("referenced by")
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T", "--from", "t1"])
    cairn.main(["link-todo", "td1", "--by", "t3"]); capsys.readouterr()
    rc = cairn.main(["remove-task", "project-a", "ms2", "t3"])
    assert rc != 0
    out = capsys.readouterr().out
    assert "referenced by td1" in out and "resolved_by" in out


def test_remove_task_blocked_by_todo_origin_node(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-todo", "project-a", "T", "--from", "t1"]); capsys.readouterr()
    rc = cairn.main(["remove-task", "project-a", "ms1", "t1"])
    assert rc != 0
    out = capsys.readouterr().out
    assert "referenced by td1" in out and "origin_node" in out


# ── 사람 협업 필드 (assignees/reporters/watchers — 전부 복수) ─────────────────
def _get_task(repo, tid):
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    for p in d["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                if t["id"] == tid:
                    return t
    raise AssertionError(f"no task {tid}")


def test_add_assignee_multi_names_and_dedup(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["add-assignee", "project-a", "t2", "철수", "영희"]) == 0   # 멀티 입력
    cairn.main(["add-assignee", "project-a", "t2", "철수"])   # 중복 무시
    assert _get_task(repo, "t2")["assignees"] == ["철수", "영희"]


def test_rm_assignee_partial_and_noop(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-assignee", "project-a", "t2", "철수", "영희", "민수"])
    cairn.main(["rm-assignee", "project-a", "t2", "영희", "없는사람"])   # 일부 제거 + no-op
    assert _get_task(repo, "t2")["assignees"] == ["철수", "민수"]


def test_add_reporter_and_watcher_are_lists(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-reporter", "project-a", "t2", "철수"])
    cairn.main(["add-watcher", "project-a", "t2", "영희", "민수"])
    t2 = _get_task(repo, "t2")
    assert t2["reporters"] == ["철수"] and t2["watchers"] == ["영희", "민수"]


def test_add_assignee_unknown_task_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["add-assignee", "project-a", "ghost", "철수"]) == 1


def test_no_set_role_commands(tmp_path, monkeypatch):
    # set-assignee/set-reporter 단일 덮어쓰기 명령은 폐기됨
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    import pytest
    with pytest.raises(SystemExit):
        cairn.main(["set-assignee", "project-a", "t2", "철수"])


def test_validate_rejects_control_chars_in_people():
    d = _good()
    t2 = d["projects"][0]["milestones"][1]["tasks"][0]
    t2["assignees"] = ["Bad\nName"]
    assert any("assignees" in e and "control" in e for e in cairn.validate(d))
    t2["assignees"] = ["ok"]; t2["watchers"] = ["good", "bad\tone"]
    assert any("watchers" in e and "control" in e for e in cairn.validate(d))


def test_validate_rejects_non_list_people():
    d = _good()
    d["projects"][0]["milestones"][1]["tasks"][0]["assignees"] = "철수"
    assert any("assignees must be a list" in e for e in cairn.validate(d))


def test_show_prints_people_when_present(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-assignee", "project-a", "t2", "철수", "영희"])
    cairn.main(["add-watcher", "project-a", "t2", "민수"]); capsys.readouterr()
    cairn.main(["show", "project-a"])
    out = capsys.readouterr().out
    assert "👤 철수, 영희" in out and "👁 민수" in out


# ── 사람별 그래프 (render 필터 + --by) ───────────────────────────────────────
def _people_data():
    d = _good()
    ms2_tasks = d["projects"][0]["milestones"][1]["tasks"]   # t2, t3
    ms2_tasks[0]["assignees"] = ["철수", "영희"]; ms2_tasks[0]["start"] = "2026-06-16"; ms2_tasks[0]["due"] = "2026-06-20"
    ms2_tasks[1]["reporters"] = ["철수"]; ms2_tasks[1]["watchers"] = ["영희"]
    ms2_tasks[1]["start"] = "2026-06-16"; ms2_tasks[1]["due"] = "2026-06-22"
    return d


def test_render_assignee_filters_to_matching_milestone():
    d = _people_data()
    out = cairn.render(d, {"assignee": "철수", "person": None, "reporter": None, "watcher": None})
    assert "Build" in out          # ms2엔 철수 assignee(t2)
    assert "Milestone Design" not in out   # ms1엔 사람 없음 → 제외
    assert "Backend Tasks" in out          # t2 매칭
    assert "Frontend Tasks" not in out     # t3 assignee 아님


def test_render_person_is_union_of_roles():
    d = _people_data()
    pf = {"person": "철수", "assignee": None, "reporter": None, "watcher": None}
    out = cairn.render(d, pf)
    # 철수는 t2 assignee + t3 reporter → 둘 다 포함
    assert "Backend Tasks" in out and "Frontend Tasks" in out


def test_render_role_badges_present():
    d = _people_data()
    out = cairn.render(d, {"assignee": "철수", "person": None, "reporter": None, "watcher": None})
    assert "👤철수" in out          # assignee 뱃지


def test_render_person_emphasizes_assignee():
    d = _people_data()
    pf = {"person": "철수", "assignee": None, "reporter": None, "watcher": None}
    out = cairn.render(d, pf)
    # t2(assignee 철수) 라인은 active 태그로 진하게
    t2_line = next(l for l in out.splitlines() if "ms2-t2" in l)
    assert "active" in t2_line


def test_render_by_month_sections():
    d = _good()
    out = cairn.render(d, None, "month")
    assert "2026-06" in out         # ms1/ms2 start 2026-06 → 월 섹션


def test_render_by_quarter_sections():
    d = _good()
    out = cairn.render(d, None, "quarter")
    assert "2026 Q2" in out         # 6월 → Q2


def test_render_by_undated_milestone_section():
    d = _good()
    d["projects"][0]["milestones"][0]["start"] = None
    d["projects"][0]["milestones"][0]["end"] = None
    d["projects"][0]["milestones"][0]["tasks"] = []   # 파생 날짜도 없게
    out = cairn.render(d, None, "quarter")
    assert "(미정)" in out


def test_render_assignee_and_by_combine():
    d = _people_data()
    pf = {"assignee": "철수", "person": None, "reporter": None, "watcher": None}
    out = cairn.render(d, pf, "quarter")
    assert "2026 Q2" in out and "Backend Tasks" in out
    assert "Frontend Tasks" not in out


def test_cmd_render_filter_skips_write_view(tmp_path, monkeypatch, capsys):
    # 필터 렌더는 canonical plan.md를 건드리지 않아야(dirty 방지) → 이후 transaction 정상
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-assignee", "project-a", "t2", "철수"]); capsys.readouterr()
    rc = cairn.main(["render", "--assignee", "철수", "--no-open"])   # --no-open → open 미호출
    assert rc == 0
    assert cairn.VIEW_PATH.with_suffix(".html").exists()
    # plan.md/yaml worktree 깨끗 → 후속 쓰기 명령 성공
    assert cairn.main(["add-reporter", "project-a", "t2", "영희"]) == 0


def test_status_assignee_filter(tmp_path, monkeypatch, capsys):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-assignee", "project-a", "t2", "철수"]); capsys.readouterr()
    cairn.main(["status", "--assignee", "철수"])
    out = capsys.readouterr().out
    assert "matched" in out and "t2" in out
    assert "ms1" not in out          # ms1엔 철수 없음 → 미표시


def test_cmd_map_no_open_skips_browser(tmp_path, monkeypatch):
    # map --no-open: HTML은 생성하되 브라우저는 열지 않음 (render --no-open과 동일)
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    opened = []
    monkeypatch.setattr(cairn.subprocess, "run", lambda cmd, **kw: opened.append(cmd))
    monkeypatch.setattr(cairn.sys, "platform", "darwin")
    rc = cairn.main(["map", "--html", "--no-open"])
    assert rc == 0
    html = cairn._map_path().with_suffix(".html")
    assert html.exists()                              # HTML은 생성
    assert not any("open" in c for c in opened)       # 브라우저는 안 열림


def test_render_badges_without_filter():
    """필터 없는 기본 render에도 작업자 뱃지(👤)가 표시돼야 한다."""
    out = cairn.render(_people_data())
    assert "👤" in out


def test_status_person_filter(tmp_path, monkeypatch, capsys):
    """status --person은 assignee/reporter/watcher 합집합 task를 모두 표시해야 한다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["add-assignee", "project-a", "t2", "철수"]); capsys.readouterr()
    cairn.main(["add-reporter", "project-a", "t3", "철수"]); capsys.readouterr()
    rc = cairn.main(["status", "--person", "철수"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "t2" in out    # assignee 철수
    assert "t3" in out    # reporter 철수


# ── Schema version + migrate ──────────────────────────────────────────────────

def test_validate_rejects_future_version():
    """validate: version > SCHEMA_VERSION이면 error를 반환해야 한다."""
    d = _good()
    d["version"] = 99
    errs = cairn.validate(d)
    assert any("unsupported schema version" in e for e in errs)


def test_load_v1_graceful():
    """v1 원장(사람필드 없음)으로 render 호출 시 예외 없이 정상 동작해야 한다."""
    d = _good()   # golden.yaml은 version=1, 사람필드 없음
    out = cairn.render(d)
    assert "cairn" in out


def test_migrate_v1_to_v2(tmp_path, monkeypatch):
    """v1 원장 migrate → 모든 task에 사람필드 백필 + version==SCHEMA_VERSION."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["migrate"])
    assert rc == 0
    d2 = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d2["version"] == cairn.SCHEMA_VERSION
    for p in d2["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                assert "assignees" in t
                assert "reporters" in t
                assert "watchers" in t


def test_migrate_idempotent(tmp_path, monkeypatch):
    """이미 최신 버전 원장 재migrate → no-op, version 그대로."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["migrate"])                        # v1→v2
    rc = cairn.main(["migrate"])                   # 재실행 → no-op
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert d["version"] == cairn.SCHEMA_VERSION


def test_migrate_dry_run(tmp_path, monkeypatch):
    """--dry-run은 계획만 출력하고 파일을 변경하지 않아야 한다."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    pf = repo / ".cairn" / "plan.yaml"
    original = pf.read_text()
    rc = cairn.main(["migrate", "--dry-run"])
    assert rc == 0
    assert pf.read_text() == original


def test_migrate_rejects_future_version(tmp_path, monkeypatch):
    """미래버전(v99) 원장에 migrate 시도 → rc≠0, 파일·HEAD 불변."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    pf = repo / ".cairn" / "plan.yaml"
    d = cairn.load_plan(pf)
    d["version"] = 99
    pf.write_text(cairn.dump_str(d))
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "v99 inject"], cwd=repo, check=True)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo,
                          capture_output=True, text=True).stdout.strip()
    rc = cairn.main(["migrate"])
    assert rc != 0
    d2 = cairn.load_plan(pf)
    assert d2["version"] == 99
    head2 = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo,
                           capture_output=True, text=True).stdout.strip()
    assert head2 == head


def test_migrate_repairs_v2_missing_fields(tmp_path, monkeypatch):
    """version=2인데 사람필드 누락 task → migrate → 백필 완료."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["migrate"])   # v1→v2
    pf = repo / ".cairn" / "plan.yaml"
    d = cairn.load_plan(pf)
    for p in d["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                if t.get("id") == "t2":
                    t.pop("assignees", None); t.pop("reporters", None); t.pop("watchers", None)
    pf.write_text(cairn.dump_str(d))
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "v2 missing fields"], cwd=repo, check=True)
    rc = cairn.main(["migrate"])
    assert rc == 0
    d2 = cairn.load_plan(pf)
    for p in d2["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                if t.get("id") == "t2":
                    assert "assignees" in t and "reporters" in t and "watchers" in t


def test_version_non_int_graceful():
    """version이 문자열이면 validate가 crash 없이 error를 반환해야 한다."""
    d = _good()
    d["version"] = "99"
    errs = cairn.validate(d)
    assert isinstance(errs, list) and len(errs) > 0
    assert any("version" in e for e in errs)


# ── task note ────────────────────────────────────────────────────────────────

def _find_task(data, tid):
    """로드된 data dict에서 task id로 task 반환."""
    for p in data["projects"]:
        for m in p.get("milestones", []):
            for t in m.get("tasks", []):
                if t.get("id") == tid:
                    return t
    return None


def test_set_note(tmp_path, monkeypatch):
    """set-note <proj> <task> <note> → task.note 저장, _node_summary에 📝."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-note", "project-a", "t2", "짧은 메모"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = _find_task(d, "t2")
    assert t2 is not None and t2.get("note") == "짧은 메모"
    assert "📝" in cairn._node_label(t2, None)


def test_set_note_clear(tmp_path, monkeypatch):
    """set-note <proj> <task> "" → note 키 제거."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-note", "project-a", "t2", "임시메모"])
    rc = cairn.main(["set-note", "project-a", "t2", ""])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = _find_task(d, "t2")
    assert "note" not in t2


def test_note_length_limit(tmp_path, monkeypatch, capsys):
    """281자 note → rc≠0, transaction 진입 전 거부, note 미설정."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    long_note = "가" * 281
    rc = cairn.main(["set-note", "project-a", "t2", long_note])
    assert rc != 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = _find_task(d, "t2")
    assert t2.get("note") is None


def test_note_file_link(tmp_path, monkeypatch):
    """파일경로 note → _node_summary에 🔗."""
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    rc = cairn.main(["set-note", "project-a", "t2", "/path/spec.md"])
    assert rc == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    t2 = _find_task(d, "t2")
    assert "🔗" in cairn._node_label(t2, None)


def test_validate_allows_legacy_note(tmp_path, monkeypatch):
    """기존 원장의 281자 note가 있어도 validate 통과 + add-assignee 무관 작업 통과(회귀 방지)."""
    # 직접 validate 확인
    d = _good()
    t = _find_task(d, "t2")
    t["note"] = "x" * 281
    assert not any("note" in e for e in cairn.validate(d))
    # 실제 transaction 게이트 통과 확인
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    pf = repo / ".cairn" / "plan.yaml"
    d2 = cairn.load_plan(pf)
    t2 = _find_task(d2, "t2")
    t2["note"] = "x" * 281
    pf.write_text(cairn.dump_str(d2))
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "legacy note"], cwd=repo, check=True)
    assert cairn.main(["add-assignee", "project-a", "t2", "철수"]) == 0


# ── C1: project.type enum + task.ssot 스키마 + set-ssot ──────────────────────
def test_validate_default_type_is_work():
    """type 필드 부재 = work(하위호환). golden엔 type 없음 → valid."""
    assert cairn.validate(_good()) == []


def test_validate_accepts_schedule_type():
    d = _good(); d["projects"][0]["type"] = "schedule"
    assert cairn.validate(d) == []


def test_validate_accepts_work_type():
    d = _good(); d["projects"][0]["type"] = "work"
    assert cairn.validate(d) == []


def test_validate_rejects_bad_type():
    d = _good(); d["projects"][0]["type"] = "gantt"
    assert any("type" in e for e in cairn.validate(d))


def test_validate_ssot_control_chars_rejected():
    d = _good(); _find_task(d, "t2")["ssot"] = "/path\x00evil"
    assert any("ssot" in e for e in cairn.validate(d))


def test_validate_accepts_ssot_path():
    d = _good(); _find_task(d, "t2")["ssot"] = "/Users/x/spec.md"
    assert cairn.validate(d) == []


def test_set_ssot_persists_and_commits(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["set-ssot", "project-a", "t2", "/Users/x/spec.md"]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert _find_task(d, "t2")["ssot"] == "/Users/x/spec.md"
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo,
                         capture_output=True, text=True).stdout
    assert "set-ssot" in log


def test_set_ssot_empty_removes(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    cairn.main(["set-ssot", "project-a", "t2", "/Users/x/spec.md"])
    assert cairn.main(["set-ssot", "project-a", "t2", ""]) == 0
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert "ssot" not in _find_task(d, "t2")


# ── C2: apply_ops 뮤테이터 (편집 ops 체인지셋 → data, exec_ref/branch 거부) ──
def _ms(data, mid):
    for p in data["projects"]:
        for m in p.get("milestones", []):
            if m.get("id") == mid:
                return m
    return None


def test_apply_ops_set_task_field():
    d = _good()
    cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "t3"],
                         "field": "due", "value": "2026-07-10"}])
    assert _find_task(d, "t3")["due"] == "2026-07-10"


def test_apply_ops_set_status_and_name():
    d = _good()
    cairn.apply_ops(d, [
        {"op": "set", "target": ["project-a", "ms2", "t3"], "field": "status", "value": "doing"},
        {"op": "set", "target": ["project-a", "ms2", "t3"], "field": "name", "value": "새 이름"}])
    t = _find_task(d, "t3")
    assert t["status"] == "doing" and t["name"] == "새 이름"


def test_apply_ops_rejects_execution_ref():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "t3"],
                             "field": "execution_ref", "value": "worktree/x"}])
        assert False, "execution_ref는 읽기전용이어야 함"
    except ValueError as e:
        assert "execution_ref" in str(e)


def test_apply_ops_rejects_branch():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "t3"],
                             "field": "branch", "value": "feat/x"}])
        assert False
    except ValueError as e:
        assert "branch" in str(e)


def test_apply_ops_rejects_id_change():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "t3"],
                             "field": "id", "value": "t99"}])
        assert False
    except ValueError:
        pass


def test_apply_ops_set_ssot_empty_removes():
    d = _good(); _find_task(d, "t3")["ssot"] = "/x.md"
    cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "t3"],
                         "field": "ssot", "value": ""}])
    assert "ssot" not in _find_task(d, "t3")


def test_apply_ops_set_ms_field():
    d = _good()
    cairn.apply_ops(d, [{"op": "set-ms", "target": ["project-a", "ms2"],
                         "field": "end", "value": "2026-06-30"}])
    assert _ms(d, "ms2")["end"] == "2026-06-30"


def test_apply_ops_set_ms_rejects_id():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "set-ms", "target": ["project-a", "ms2"],
                             "field": "id", "value": "msX"}])
        assert False
    except ValueError:
        pass


def test_apply_ops_add_task_autoid():
    d = _good()
    cairn.apply_ops(d, [{"op": "add-task", "target": ["project-a", "ms2"],
                         "task": {"name": "새 태스크", "status": "todo"}}])
    names = [t["name"] for t in _ms(d, "ms2")["tasks"]]
    assert "새 태스크" in names
    # id 자동생성 + 전역 유니크
    ids = [t["id"] for p in d["projects"] for m in p["milestones"] for t in m["tasks"]]
    assert len(ids) == len(set(ids))


def test_apply_ops_add_task_rejects_frozen():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "add-task", "target": ["project-a", "ms2"],
                             "task": {"name": "x", "execution_ref": "worktree/y"}}])
        assert False
    except ValueError:
        pass


def test_apply_ops_remove_task():
    d = _good()
    cairn.apply_ops(d, [{"op": "remove-task", "target": ["project-a", "ms2", "t3"]}])
    assert _find_task(d, "t3") is None


def test_apply_ops_remove_task_referenced_blocked():
    d = _good(); _find_task(d, "t3")["depends_on"] = ["t2"]
    try:
        cairn.apply_ops(d, [{"op": "remove-task", "target": ["project-a", "ms2", "t2"]}])
        assert False, "역참조 중인 태스크 삭제는 차단되어야 함"
    except ValueError as e:
        assert "referenced" in str(e)


def test_apply_ops_add_and_remove_milestone():
    d = _good()
    cairn.apply_ops(d, [{"op": "add-milestone", "target": ["project-a"],
                         "milestone": {"name": "새 마일스톤"}}])
    new_ms = [m for m in d["projects"][0]["milestones"] if m["name"] == "새 마일스톤"][0]
    cairn.apply_ops(d, [{"op": "remove-milestone", "target": ["project-a", new_ms["id"]]}])
    assert all(m["name"] != "새 마일스톤" for m in d["projects"][0]["milestones"])


def test_apply_ops_remove_milestone_nonempty_blocked():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "remove-milestone", "target": ["project-a", "ms2"]}])
        assert False
    except ValueError:
        pass


def test_apply_ops_unknown_op_rejected():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "frobnicate", "target": ["project-a"]}])
        assert False
    except ValueError as e:
        assert "frobnicate" in str(e)


def test_apply_ops_missing_target_rejected():
    d = _good()
    try:
        cairn.apply_ops(d, [{"op": "set", "target": ["project-a", "ms2", "ghost"],
                             "field": "status", "value": "done"}])
        assert False
    except ValueError:
        pass


# ── C3: serve 편집 백엔드 (to_view / plan_hash / web_save — transaction 경유) ─
def test_to_view_maps_fields():
    d = _good()
    v = cairn.to_view(d)
    assert v["pid"] == "project-a"
    assert v["type"] == "work"   # golden엔 type 없음 → 기본 work
    assert len(v["milestones"]) == 2
    tids = [t["id"] for m in v["milestones"] for t in m["tasks"]]
    assert set(tids) == {"t1", "t2", "t3"}
    # 손실 매핑 키: status→s
    t2 = [t for m in v["milestones"] for t in m["tasks"] if t["id"] == "t2"][0]
    assert t2["s"] == "doing"


def test_to_view_maps_ssot_and_exec():
    d = _good()
    t = _find_task(d, "t3"); t["ssot"] = "/x.md"; t["execution_ref"] = "worktree/z"
    v = cairn.to_view(d)
    t3 = [x for m in v["milestones"] for x in m["tasks"] if x["id"] == "t3"][0]
    assert t3["ssot"] == "/x.md" and t3["exec"] == "worktree/z"


def test_plan_hash_changes_on_edit(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    h1 = cairn.plan_hash()
    cairn.main(["set-status", "project-a", "task", "ms2", "t3", "done"])
    assert cairn.plan_hash() != h1


def test_web_save_applies_ops_via_transaction(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    base = cairn.plan_hash()
    status, body = cairn.web_save(
        [{"op": "set", "target": ["project-a", "ms2", "t3"], "field": "status", "value": "done"}],
        base)
    assert status == 200 and body["ok"]
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert _find_task(d, "t3")["status"] == "done"
    log = subprocess.run(["git", "log", "--oneline"], cwd=repo, capture_output=True, text=True).stdout
    assert "web-sync" in log
    assert body["hash"] == cairn.plan_hash()   # 새 baseHash 반환


def test_web_save_conflict_returns_409(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    status, body = cairn.web_save(
        [{"op": "set", "target": ["project-a", "ms2", "t3"], "field": "status", "value": "done"}],
        "staleHASHstale")
    assert status == 409 and body.get("conflict")
    assert "view" in body and body["hash"] == cairn.plan_hash()
    # 원장 미변경
    d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
    assert _find_task(d, "t3")["status"] == "todo"


def test_web_save_rejects_execution_ref(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    base = cairn.plan_hash()
    status, body = cairn.web_save(
        [{"op": "set", "target": ["project-a", "ms2", "t3"], "field": "execution_ref", "value": "worktree/x"}],
        base)
    assert status == 400 and "execution_ref" in body["error"]
    assert cairn.plan_hash() == base   # 미변경


def test_web_save_invalid_status_rolls_back(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    base = cairn.plan_hash()
    status, body = cairn.web_save(
        [{"op": "set", "target": ["project-a", "ms2", "t3"], "field": "status", "value": "nope"}],
        base)
    assert status == 400 and "error" in body
    assert cairn.plan_hash() == base   # transaction validate 실패 → 원장 미변경


def test_web_save_empty_ops_rejected(tmp_path, monkeypatch):
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    status, body = cairn.web_save([], cairn.plan_hash())
    assert status == 400


# ── C3: serve 서버 스모크 (토큰·Host 검증 + /save transaction) ───────────────
def test_build_view_html_injects_edit_context():
    d = _good()
    html = cairn.build_view_html(d, None, token="TOK123", base_hash="H")
    assert "CAIRN_EDIT" in html and "TOK123" in html
    assert "__CAIRN_" not in html   # 미치환 토큰 없음
    assert '"pid": "project-a"' in html or '"pid":"project-a"' in html


def test_serve_smoke(tmp_path, monkeypatch):
    import json, threading, urllib.request, urllib.error
    repo = _init_repo(tmp_path); _mp(monkeypatch, repo)
    srv, token = cairn._make_server(None, 0)
    th = threading.Thread(target=srv.serve_forever, daemon=True); th.start()
    try:
        base = f"http://127.0.0.1:{srv.server_address[1]}"

        def get(path, headers=None):
            return urllib.request.urlopen(urllib.request.Request(base + path, headers=headers or {}))

        # 무토큰 → 403
        try:
            get("/hash"); assert False, "무토큰은 403이어야 함"
        except urllib.error.HTTPError as e:
            assert e.code == 403
        # 토큰 → 200, hash 일치
        h = json.loads(get(f"/hash?t={token}").read())["hash"]
        assert h == cairn.plan_hash()
        # Host 위조 → 403 (DNS rebinding 방어)
        try:
            get(f"/hash?t={token}", {"Host": "evil.com"}); assert False
        except urllib.error.HTTPError as e:
            assert e.code == 403
        # GET / → 편집 컨텍스트 임베드 HTML
        html = get(f"/?t={token}").read().decode()
        assert "CAIRN_EDIT" in html and token in html
        # POST /save (토큰) → 편집 반영 + web-sync 커밋
        payload = json.dumps({"ops": [{"op": "set", "target": ["project-a", "ms2", "t3"],
                                       "field": "status", "value": "done"}], "baseHash": h}).encode()
        req = urllib.request.Request(base + f"/save?t={token}", data=payload, method="POST",
                                     headers={"Content-Type": "application/json"})
        r = urllib.request.urlopen(req)
        assert r.status == 200
        d = cairn.load_plan(repo / ".cairn" / "plan.yaml")
        assert _find_task(d, "t3")["status"] == "done"
        # POST /save 무토큰 → 403
        try:
            urllib.request.urlopen(urllib.request.Request(base + "/save", data=payload, method="POST",
                                   headers={"Content-Type": "application/json"}))
            assert False
        except urllib.error.HTTPError as e:
            assert e.code == 403
    finally:
        srv.shutdown(); srv.server_close()


# ── install-fix: template 경로가 개발/설치 양쪽 레이아웃에서 발견되어야 함 ──
def test_template_path_exists_dev():
    # 개발 트리(core 옆 docs)에서 실제 template 존재
    assert cairn.TEMPLATE_PATH.exists(), f"template 없음: {cairn.TEMPLATE_PATH}"


def test_find_template_dev_layout(tmp_path):
    # core/cairn.py + ../docs/template (개발 레이아웃)
    (tmp_path/"core").mkdir(); (tmp_path/"docs").mkdir()
    tpl=(tmp_path/"docs"/"plan-view.template.html"); tpl.write_text("x")
    assert cairn._find_template(tmp_path/"core"/"cairn.py") == tpl


def test_find_template_install_layout(tmp_path):
    # 설치본: cairn.py 와 docs/ 가 같은 레벨(versions/<ver>/cairn.py + versions/<ver>/docs/template)
    (tmp_path/"docs").mkdir()
    tpl=(tmp_path/"docs"/"plan-view.template.html"); tpl.write_text("x")
    assert cairn._find_template(tmp_path/"cairn.py") == tpl


def test_self_test_covers_multiview(tmp_path, monkeypatch, capsys):
    # self-test가 멀티뷰 build_view_html 렌더까지 검증해야(사각지대 방지)
    repo=_init_repo(tmp_path); _mp(monkeypatch, repo)
    assert cairn.main(["self-test"]) == 0
    out=capsys.readouterr().out
    assert "OK" in out
