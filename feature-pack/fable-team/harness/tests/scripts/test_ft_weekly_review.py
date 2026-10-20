"""주간 점검표 도구 — 사실 칸만 채우고 결정 칸은 비운다 (R131 · 판정 1483·1487).

격리 임시 git 저장소 픽스처 · 가짜 mbox · 가짜 seats/drift 명령 · 실제 launchd·실제 mbox 0.
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR python3 -m pytest tests/scripts/test_ft_weekly_review.py -q
"""
import os
import re
import shutil
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

from _team_fixture import write_teams
from fake_resource_env import fake_comm_root
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
NOW = datetime(2026, 10, 14, 9, 7)  # 수요일 → 주 시작 월요일 = 20261012
MON = "20261012"
SEATS = (
    "byz-planner-master-claude#7 PASS\nbyz-planner-master-claude#8 PASS\n"
    "byz-harness-master-claude#39 PASS\nbyz-harness-master-claude#40 PASS\n"
)
LEDGER_HEAD = "| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |\n|---|---|---|---|---|\n"
QUEUE = (
    "# 대기열\n| # | 일 | 근거 | 결정 |\n|---|---|---|---|\n"
    "| A3 | 법무 | 1252 | |\n| B2 | 결제 | 1450 | |\n| A1 | 폰 | 1362 | **지금** |\n"
)
OPLEDGER = (
    "# 오빠 원장\n" + LEDGER_HEAD
    + "| 1 | 폰 물결 | 코드 | 진행 — 코드 고침 | |\n"
    + "| 2 | 약관 | 문서 | 진행 — 웹 반영 | 83713 |\n"
    + "| 3 | 메일 | 코드 | 완료 | |\n"
)
DUMB = "# 원장\n| # | 일시 | 타입 |\n|---|---|---|\n| 0 | 10-12 | 가 |\n| 1 | 10-09 | 나 |\n| 2 | 10-08 | 다 |\n"
REQ = (
    "# REQUEST-LEDGER\n\n| # | 접수 | 요청자 | 증상 1줄 | Issue | 오빠 값 | 반영 sha |\n|---|---|---|---|---|---|---|\n"
    "| R1 | 10-04 | a | 닫힌 것 | #799 | 머지 GO | dedceb2ba6 |\n"
    "| R5 | 10-06 | b | 머지 커밋에도 골좌표 요구 | #835 | | |\n"
    "| R22 | 10-07 | c | 보류 건 | | 보류 10-07 | |\n"
)
PRIOR_HARNESS = (
    "# 주간 점검 — 하네스 (주 시작 20261005)\n<!-- snap: {\"req_ledger\": 100} -->\n\n"
    "| 항목 | 사실 | 결정 |\n|---|---|---|\n"
    "| H1 card-a | 마지막 변경 8일 | 계속 |\n| H2 R5 | 접수 10-06 | |\n\n"
    "## 이월\n- [이월 1주] H6 .bak · .bak-* 3개 · 결정:\n- [이월 1주] H4 drift · rc=1 · 결정: 해소\n"
)
PRIOR_PLANNER = (
    "# 주간 점검 — planner (주 시작 20261005)\n<!-- snap: {\"dumb_keys\": [\"10-09|나\", \"10-08|다\"]} -->\n\n"
    "| 항목 | 사실 | 결정 |\n|---|---|---|\n| P1 결정 대기열 | 열린 행 1건 | 정리 |\n"
)


def _env():
    return {k: v for k, v in os.environ.items() if not k.startswith(("GIT_", "FT_"))}


def _git(repo, *args, when=None):
    env = _env()
    if when:
        env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = when.strftime("%Y-%m-%dT%H:%M:%S")
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   check=True, capture_output=True, env=env)


def _put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_world(tmp_path):
    planner, harness = tmp_path / "planner", tmp_path / "harness"
    _put(planner / "design/planner/DECISIONS-oppa-queue-20261013.md", QUEUE)
    _put(planner / "design/planner/PLAN-oppa-ledger.md", OPLEDGER)
    _put(planner / "design/planner/weekly/REVIEW-planner-20261005.md", PRIOR_PLANNER)
    for repo in (planner, harness):
        repo.mkdir(exist_ok=True)
        _git(repo, "init", "-q")
        write_teams(repo)  # R382b: 팀 폴더는 각 리포의 TEAMS.md 폴더 칸으로 풀린다
    for name, days in (("card-a", 1), ("card-b", 10), ("card-c", 20)):
        _put(harness / f"design/harness/indices/진행/{name}.md", f"# {name}\n")
        _git(harness, "add", "-A")
        _git(harness, "commit", "-qm", name, when=NOW - timedelta(days=days))
    _put(harness / "design/harness/REQUEST-LEDGER.md", REQ)
    _put(harness / "design/harness/weekly/REVIEW-harness-20261005.md", PRIOR_HARNESS)
    _put(harness / "design/harness/x.sh.bak-1001", "x")
    _put(harness / "scripts/y.bak-1002", "y")
    _put(tmp_path / "dumb.md", DUMB)
    _put(tmp_path / "seats.sh", f"#!/usr/bin/env bash\ncat <<'EOF'\n{SEATS}EOF\n")
    _put(tmp_path / "drift.sh", "#!/usr/bin/env bash\necho 'DRIFT foo.sh'\nexit 1\n")
    _put(tmp_path / "secretscan.sh", "#!/usr/bin/env bash\necho '비밀 기록 스캔: 새 3건 · 마지막 실행 2026-10-17 09:00:00'\n")
    good_mbox(tmp_path)
    return planner, harness


def good_mbox(tmp_path):
    _put(tmp_path / "mbox.sh", f"#!/usr/bin/env bash\nprintf '%s\\t' \"$@\" >> {tmp_path}/mbox.log\necho >> {tmp_path}/mbox.log\n")


def broken_mbox(tmp_path):
    _put(tmp_path / "mbox.sh", "#!/usr/bin/env bash\necho 'ERROR doorbell down'\nexit 9\n")


def run_tool(tmp_path, bin_dir=BIN, now=NOW, planner=None, harness=None):
    env = _env()
    env.update(
        FT_PLANNER_REPO=str(planner or tmp_path / "planner"), FT_HARNESS_REPO=str(harness or tmp_path / "harness"),
        FT_MBOX=f"bash {tmp_path / 'mbox.sh'}", FT_HARNESS_INFO=f"bash {tmp_path / 'seats.sh'}",
        FT_DRIFT_CMD=f"bash {tmp_path / 'drift.sh'}", FT_SECRET_SCAN_CMD=f"bash {tmp_path / 'secretscan.sh'}", FT_DUMB_LEDGER=str(tmp_path / "dumb.md"), FT_LIVE_BIN=str(tmp_path / "livebin"),
        FT_REVIEW_NOW=now.strftime("%Y-%m-%dT%H:%M"),
    )
    cwd = fake_comm_root(tmp_path / "root")  # r537: 도구가 cwd 의 git 공용 루트(.fable-team/ 있는)를 필수로 푼다(r385 _repo_root)
    return subprocess.run(["bash", str(bin_dir / "ft-weekly-review.sh")], capture_output=True, text=True, env=env, cwd=cwd)


def files(tmp_path):
    return (tmp_path / f"planner/design/planner/weekly/REVIEW-planner-{MON}.md",
            tmp_path / f"harness/design/harness/weekly/REVIEW-harness-{MON}.md")


def mbox_calls(tmp_path):
    log = tmp_path / "mbox.log"
    return [ln.rstrip("\t").split("\t") for ln in log.read_text().splitlines()] if log.exists() else []


def parse_row(line):
    return [c.replace("\\|", "|").strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def rows(text):
    return [ln for ln in text.splitlines() if re.match(r"^\| [PH]\d", ln)]


def check_facts(tmp_path):  # 1ⓐ ⓑ
    pl, hn = (p.read_text(encoding="utf-8") for p in files(tmp_path))
    p1 = next(r for r in rows(pl) if r.startswith("| P1"))
    assert "열린 행 2" in p1 and "A3" in p1 and "B2" in p1 and "A1" not in p1
    assert "쪽지 번호 0" in next(r for r in rows(pl) if r.startswith("| P2")) and "1줄" in next(r for r in rows(pl) if r.startswith("| P2"))
    assert "새 행 1" in next(r for r in rows(pl) if r.startswith("| P4"))
    assert "4줄" in next(r for r in rows(pl) if r.startswith("| P5"))
    cards = [r for r in rows(hn) if r.startswith("| H1 ")]
    assert len(cards) == 3 and all(f"{n}일" in " ".join(cards) for n in (1, 10, 20))
    h2 = [r for r in rows(hn) if r.startswith("| H2 ")]
    assert len(h2) == 1 and "R5" in h2[0] and "R22" not in h2[0] and "R1 " not in h2[0]
    assert "rc=1" in next(r for r in rows(hn) if r.startswith("| H4")) and "DRIFT foo.sh" in hn
    h6 = next(r for r in rows(hn) if r.startswith("| H6"))
    assert ".bak-* 2개" in h6 and "지난주" in h6 and "+" in h6
    assert any(r.startswith("| H7") for r in rows(hn))
    h8 = next(r for r in rows(hn) if r.startswith("| H8"))  # R135b ③ — 비밀 기록 스캔 1칸
    assert "비밀 기록 스캔: 새 3건 · 마지막 실행 2026-10-17" in h8


def check_decisions_empty(tmp_path):  # 1ⓒ
    for p in files(tmp_path):
        main = p.read_text(encoding="utf-8").split("## 이월")[0]
        for r in rows(main):
            cols = parse_row(r)
            assert len(cols) == 3 and cols[2] == "", r


def check_rerun_quiet(tmp_path, bin_dir=BIN):  # 1ⓓ
    first = [p.read_text(encoding="utf-8") for p in files(tmp_path)]
    assert len(mbox_calls(tmp_path)) == 2
    res = run_tool(tmp_path, bin_dir=bin_dir, now=NOW + timedelta(minutes=33))
    assert res.returncode == 0, res.stderr
    for p, before in zip(files(tmp_path), first):
        after = p.read_text(encoding="utf-8")
        assert after.startswith(before) and after.count("## 재측정") == 1
    assert len(mbox_calls(tmp_path)) == 2, "같은 주 재실행은 쪽지 0"


def test_creates_both_tables_with_facts(tmp_path):  # 1ⓐ ⓑ
    make_world(tmp_path)
    res = run_tool(tmp_path)
    assert res.returncode == 0, res.stderr
    check_facts(tmp_path)


def test_decision_cells_all_empty(tmp_path):  # 1ⓒ
    make_world(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    check_decisions_empty(tmp_path)


def test_rerun_same_week_adds_one_remeasure_section_and_no_mail(tmp_path):  # 1ⓓ
    make_world(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    check_rerun_quiet(tmp_path)


def test_carry_over_from_last_week(tmp_path):  # 1ⓔ
    make_world(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    hn = files(tmp_path)[1].read_text(encoding="utf-8")
    carry = hn.split("## 이월")[1]
    assert "[이월 1주] H2 R5" in carry
    assert "[이월 2주] H6" in carry
    assert "H4" not in carry and "card-a" not in carry


def test_sends_two_mails_to_current_masters(tmp_path):  # 1ⓕ
    make_world(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    calls = mbox_calls(tmp_path)
    assert [c[1] for c in calls] == ["byz-planner-master-claude#8", "byz-harness-master-claude#40"]
    for c, p in zip(calls, files(tmp_path)):
        assert c[0] == "send" and c[3] == f"[주간 점검] {p}"


def test_unreadable_source_is_said_not_silent(tmp_path):  # #0 RULE
    make_world(tmp_path)
    queue = tmp_path / "planner/design/planner/DECISIONS-oppa-queue-20261013.md"
    queue.chmod(0)
    try:
        res = run_tool(tmp_path)
    finally:
        queue.chmod(0o644)
    assert res.returncode == 0, res.stderr
    pl = files(tmp_path)[0].read_text(encoding="utf-8")
    assert "확인 못 함" in next(r for r in rows(pl) if r.startswith("| P1"))


def test_pipe_in_fact_stays_in_fact_column_and_is_carried(tmp_path):  # C1
    make_world(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    p4 = parse_row(next(r for r in rows(files(tmp_path)[0].read_text(encoding="utf-8")) if r.startswith("| P4")))
    assert len(p4) == 3 and p4[2] == "" and "10-12|가" in p4[1]
    assert run_tool(tmp_path, now=NOW + timedelta(days=7)).returncode == 0
    nxt = tmp_path / "planner/design/planner/weekly/REVIEW-planner-20261019.md"
    assert "[이월 1주] P4" in nxt.read_text(encoding="utf-8").split("## 이월")[1]


def test_seats_stderr_noise_is_not_counted_as_a_seat(tmp_path):  # P5 — 로케일 경고 같은 stderr 줄이 «현역 좌석 N줄» 에 섞이지 않는다
    make_world(tmp_path)
    _put(tmp_path / "seats.sh", f"#!/usr/bin/env bash\necho 'bash: warning: setlocale: LC_ALL: cannot change locale' >&2\ncat <<'EOF'\n{SEATS}EOF\n")
    res = run_tool(tmp_path)
    assert res.returncode == 0, res.stderr
    p5 = next(r for r in rows(files(tmp_path)[0].read_text(encoding="utf-8")) if r.startswith("| P5"))
    assert "현역 좌석 4줄" in p5, p5


def test_malformed_prior_row_raises_not_silent(tmp_path):  # C1
    make_world(tmp_path)
    _put(tmp_path / "planner/design/planner/weekly/REVIEW-planner-20261005.md",
         "| 항목 | 사실 | 결정 |\n|---|---|---|\n| P1 결정 대기열 | a | b | c |\n")
    res = run_tool(tmp_path)
    assert res.returncode != 0 and "3열" in res.stderr
    assert not files(tmp_path)[0].exists()


def notified(path):
    return re.findall(r"<!-- notified: \S+=(ok|fail) -->", path.read_text(encoding="utf-8"))


def test_failed_mail_is_loud_recorded_and_retried_only_for_failures(tmp_path):  # C2
    make_world(tmp_path)
    broken_mbox(tmp_path)
    res = run_tool(tmp_path)
    assert res.returncode != 0 and "ERROR" in res.stderr
    assert [notified(p) for p in files(tmp_path)] == [["fail"], ["fail"]] and not mbox_calls(tmp_path)
    good_mbox(tmp_path)
    assert run_tool(tmp_path, now=NOW + timedelta(minutes=33)).returncode == 0
    assert len(mbox_calls(tmp_path)) == 2 and [notified(p) for p in files(tmp_path)] == [["ok"], ["ok"]]
    assert run_tool(tmp_path, now=NOW + timedelta(minutes=66)).returncode == 0
    assert len(mbox_calls(tmp_path)) == 2, "ok 좌석은 다시 보내지 않는다"


def test_only_failed_seat_is_retried(tmp_path):  # C2
    make_world(tmp_path)
    p, h = files(tmp_path)
    assert run_tool(tmp_path).returncode == 0
    h.write_text(h.read_text(encoding="utf-8").replace("=ok -->", "=fail -->"), encoding="utf-8")
    assert run_tool(tmp_path, now=NOW + timedelta(minutes=33)).returncode == 0
    calls = mbox_calls(tmp_path)
    assert len(calls) == 3 and calls[-1][1] == "byz-harness-master-claude#40" and notified(h) == ["ok"]


def _mutant(tmp_path, old, new):
    bin_dir = tmp_path / "mutant-bin"
    bin_dir.mkdir()
    for name in ("ft-weekly-review.sh", "ft_weekly_review.py", "ft_weekly_table.py", "ft_team_lib.py"):
        shutil.copy(BIN / name, bin_dir / name)
    hit = [n for n in ("ft_weekly_review.py", "ft_weekly_table.py") if old in (bin_dir / n).read_text(encoding="utf-8")]
    assert len(hit) == 1, f"변이 표지 {old!r} 가 도구에 정확히 한 곳 있어야 한다: {hit}"
    target = bin_dir / hit[0]
    target.write_text(target.read_text(encoding="utf-8").replace(old, new), encoding="utf-8")
    return bin_dir


def test_mutant_filled_decision_cell_is_caught(tmp_path):  # 변이 ⓐ → 1ⓒ rc=1
    make_world(tmp_path)
    assert run_tool(tmp_path, bin_dir=_mutant(tmp_path, 'DECISION_CELL = ""', 'DECISION_CELL = "계속"')).returncode == 0
    try:
        check_decisions_empty(tmp_path)
    except AssertionError:
        return
    raise AssertionError("결정 칸을 채운 변이가 시험을 통과했다")


def test_mutant_remail_on_rerun_is_caught(tmp_path):  # 변이 ⓑ → 1ⓓ rc=1
    make_world(tmp_path)
    mutant = _mutant(tmp_path, "MAIL_ON_RERUN = False", "MAIL_ON_RERUN = True")
    assert run_tool(tmp_path, bin_dir=mutant).returncode == 0
    try:
        check_rerun_quiet(tmp_path, bin_dir=mutant)
    except AssertionError:
        return
    raise AssertionError("재실행 때 쪽지를 다시 보내는 변이가 시험을 통과했다")
