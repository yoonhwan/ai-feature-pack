"""r851 원장 자동 채움 ⓐ~ⓖ — 임시 원장 리포(bare origin + 사본) · 카드·쪽지·질문 장부·ft-hil·AUTONOMY-QUEUE 픽스처 · FT_LEDGER_NOW 고정 · 실 원장·실 push 0.
실행: python3 -m pytest tests/scripts/test_ledger_fill_r851.py -q   (ⓗ 변이 = evidence/r851/mutation.sh)
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(BIN), str(KIT)]

import ft_ledger_fill as lf  # noqa: E402
import ft_ledger_fill_src as src  # noqa: E402
import ft_ledger_fill_tables as tb  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

NOW = datetime.now().replace(second=0, microsecond=0)
REL = "design/teams/planner/PLAN-oppa-ledger.md"
CONCLUSION = "**결론**: 손으로 쓴 결론 문단 — 기계는 이 줄을 바이트 그대로 둔다. 오빠 손: 없음."
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


def ledger(updated: datetime, closed_row: str = "| 2 | 옛 일 닫기 | 코드 | 닫힘 — 오빠 확인 끝 | — |") -> str:
    return "\n".join([
        "# 오빠 원장 — 시킨 일 · 하기로 한 일 · 지금 상태 (정본 · planner 관리)", "",
        f"> 마지막 갱신: {updated:%Y-%m-%d %H:%M} · planner#124 (결론 · 갱신 담당 planner arch#14)", "",
        CONCLUSION, "",
        "## 메인 골 7줄 — 지금 상태 (행 순번 결속)", "",
        "| 골(오빠 원문) | 지금 상태 | 닫히려면 남은 것 |", "|---|---|---|",
        "| 구독 크레딧 | 09:3x: 손으로 쓴 옛 상태 | 실결제 시험 |",
        "| 말풍선 정상화 | 09:3x: 손으로 쓴 옛 상태 | 강의 시험 합격 |", "",
        "---", "## 1. 오빠가 시킨 일 — 지금 상태", "",
        "### 10-12 시키신 일", "| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |", "|---|---|---|---|---|",
        "| 1 | 열린 일 | 발주 | 진행 — 앞 단계 | — |", closed_row, "",
        "## 2. 오빠 할 일 (10-23 06:5x · 아침 묶음 2건)", "1. 손으로 쓴 옛 할 일 하나", "2. 손으로 쓴 옛 할 일 둘", "",
        "## 2-1. 발주한 것 (planner → 팀 · 지금 상태)", "| 발주 | 받은 팀 | 지금 상태 |", "|---|---|---|", "| 사람 칸 | 하네스 | 진행 |", "",
        "## 3. 팀 작업 — 지난밤 기록", "| 팀 | 지금 하는 것 | 다음 |", "|---|---|---|", "| 결제 | 손으로 쓴 옛 줄 | 옛 다음 |", "",
        "## 4. 드러난 문제", "- 사람이 쓴 문제 줄", "",
        "## 5. 완료 보관 (발행 다음 턴에 1절에서 내린다)", "| 순번 | 시키신 일 | 종류 | 닫는 증거 | 내린 날 |", "|---|---|---|---|---|",
        "| 10-15-11 | 옛 보관 줄 | 코드 | 끝 | 10-15 |", ""])


TEAMS = """| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| harness | `$FT_HARNESS_ROOT/design/harness/` | byz-harness-master-claude | 현역 |
| planner | `design/teams/planner/` | byz-planner-master-claude | 현역 |
| cfo | `design/teams/cfo/` | byz-cfo-master-claude | 현역 |
| v65 | `design/teams/v65/` | byz-v65-master-claude | 현역 |
| kk | `design/teams/kk/` | FB_KK | 휴면 |
"""


def run(cwd: Path, *a: str, env: dict | None = None) -> str:
    return subprocess.run(["git", "-C", str(cwd), *a], check=True, capture_output=True, text=True, env={**os.environ, **GIT_ENV, **(env or {})}).stdout


def write(base: Path, rel: str, text: str) -> None:
    (base / rel).parent.mkdir(parents=True, exist_ok=True)
    (base / rel).write_text(text, encoding="utf-8")


@pytest.fixture
def world(tmp_path, monkeypatch):
    origin, repo, root, hroot = tmp_path / "origin.git", tmp_path / "repo", tmp_path / "root", tmp_path / "hroot"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    subprocess.run(["git", "clone", "-q", str(origin), str(repo)], check=True, capture_output=True)
    run(repo, "checkout", "-q", "-b", "main")
    write(repo, "design/TEAMS.md", TEAMS)
    write(repo, REL, ledger(NOW - timedelta(hours=3)))
    write(repo, "design/teams/cfo/indices/진행/cfo-a.md", "# 인덱스: cfo-a — 구독 환불 고침 — Issue #3001 · 157908\n")
    write(repo, "design/teams/cfo/indices/대기/cfo-b.md", "# 인덱스: cfo-b — 대기 일\n")
    write(repo, "design/teams/v65/indices/진행/v65-a.md", "# 인덱스: v65-a — 키보드 고침 d0e1f2a3b4\n")
    write(repo, "design/teams/v65/indices/README.md", "# 안내\n")
    run(repo, "add", "-A")
    run(repo, "commit", "-qm", "base")
    write(repo, "design/teams/cfo/indices/완성/cfo-done.md", "# 인덱스: cfo-done — 잔액 정리 지연 한 줄\n- 착지: main abcdef1234\n")
    write(repo, "design/teams/v65/indices/완성/v65-done.md", "# 인덱스: v65-done — 긴 발화 확정 고침\n")
    run(repo, "add", "-A")
    run(repo, "commit", "-qm", "팀 착지 2")
    run(repo, "push", "-q", "origin", "main")
    write(hroot, "design/harness/indices/진행/r851.md", "# 인덱스: r851 — 원장 자동 채움 — 원장 표\n")
    subprocess.run(["git", "init", "-q", "-b", "main", str(hroot)], check=True)  # r892 r3 — 하네스 카드 = 그 워크트리 HEAD 한 판
    run(hroot, "add", "-A")
    run(hroot, "commit", "-qm", "harness cards")
    (root / ".fable-team/comm").mkdir(parents=True)
    (root / ".fable-team/seats-planner.json").write_text(json.dumps({"_master": "byz-planner-master-claude#9"}), encoding="utf-8")
    ts = (NOW - timedelta(hours=1)).isoformat()
    (root / ".fable-team/comm/mailbox.jsonl").write_text(
        json.dumps({"ts": ts, "from": "byz-cfo-nano-x#0", "body": "[완료·휴식] cfo-done 끝"}, ensure_ascii=False) + "\n"
        + json.dumps({"ts": ts, "from": "byz-v65-master-claude#3", "body": "그냥 쪽지"}, ensure_ascii=False) + "\n", encoding="utf-8")
    mlog = tmp_path / "mbox.log"
    (tmp_path / "mbox.sh").write_text(f'#!/usr/bin/env bash\necho "$@" >> {mlog}\n', encoding="utf-8")
    (tmp_path / "hil.sh").write_text('#!/usr/bin/env bash\nprintf "h5 30\\nh7 3\\n"\n', encoding="utf-8")
    q = tmp_path / "byz_slack_questions.C1.json"
    q.write_text(json.dumps({"open": {"150540": {"seat": "byz-v65-master-claude#238", "what": "가상머신 복구 방법 #2995 오늘 고를까요?", "state": "open"},
                                      "150541": {"seat": "byz-cfo-x#1", "what": "답 전달됨", "state": "delivered"}}}, ensure_ascii=False), encoding="utf-8")
    queue = tmp_path / "AUTONOMY-QUEUE.md"
    queue.write_text("| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 처리됨 |\n|---|---|---|---|---|---|---|\n"
                     "| A2 | t | ddl | 개발 DB 표 한 칸 추가 | 지금 적용 | 운영 값 |  |\n| A2 | t | card | 끝난 것 | x | y | 판정 1715 |\n", encoding="utf-8")
    mag = tmp_path / "magazine-doc.json"
    for k, v in {"FT_ROOT": root, "FT_HARNESS_ROOT": hroot, "FT_LEDGER_QUESTIONS": q, "FT_LEDGER_HIL": tmp_path / "hil.sh",
                 "FT_LEDGER_QUEUE": queue, "FT_MAGAZINE_STATE": mag, "FT_MBOX": tmp_path / "mbox.sh",
                 "FT_LEDGER_FILL_STATE": tmp_path / "state", "FT_LEDGER_NOW": f"{NOW:%Y-%m-%d %H:%M}"}.items():
        monkeypatch.setenv(k, str(v))
    monkeypatch.setattr(lf, "goal_teams", lambda: ["cfo (byz-cfo-master-claude)", "v65 · lecture"])
    return {"origin": origin, "repo": repo, "root": root, "mlog": mlog, "q": q, "mag": mag, "tmp": tmp_path}


BR = "ledger/auto"


def origin_ledger(w, ref: str = BR) -> str:
    return subprocess.run(["git", "-C", str(w["origin"]), "show", f"{ref}:{REL}"], check=True, capture_output=True, text=True).stdout


def sha_of(w, ref: str) -> str:
    r = subprocess.run(["git", "-C", str(w["origin"]), "rev-parse", "--verify", "-q", ref], capture_output=True, text=True)
    return r.stdout.strip()


def n_commits(w, ref: str = BR) -> int:
    """원격 사본 브랜치에만 있는 커밋 수(main 위) — 브랜치 없음 = 0."""
    if not sha_of(w, ref):
        return 0
    return int(subprocess.run(["git", "-C", str(w["origin"]), "rev-list", "--count", f"main..{ref}"], check=True, capture_output=True, text=True).stdout)


def fill(w, at=NOW):
    return lf.fill(w["root"], w["repo"], REL, "origin/main", at, do_fetch=True, push=True)


def section(text: str, prefix: str) -> list[str]:
    lines = text.split("\n")
    i = next(k for k, ln in enumerate(lines) if ln.startswith(prefix))
    j = next((k for k in range(i + 1, len(lines)) if lines[k].startswith("## ")), len(lines))
    return lines[i:j]


def test_a_three_tables_filled_one_commit_conclusion_bytes_kept(world):
    before, main0 = origin_ledger(world, "main"), sha_of(world, "main")
    rc, sha = fill(world)
    after = origin_ledger(world)
    assert rc == 0 and sha and n_commits(world) == 1 and sha_of(world, BR) == sha
    assert sha_of(world, "main") == main0 and origin_ledger(world, "main") == before  # main 쓰기 0(r2 planner 결정 ②)
    head = before.split("## 메인 골")[0]
    assert after.startswith(head) and CONCLUSION in after  # 머리·결론 바이트 그대로
    for keep in ("## 2-1.", "## 4. 드러난 문제"):
        assert section(after, keep) == section(before, keep)
    goal = section(after, "## 메인 골")
    assert "| 구독 크레딧 | 진행 1장 · 최근 완성 1장 — 결제 «구독 환불 고침» · «잔액 정리 지연 한 줄» (기계 채움) | 실결제 시험 |" in goal
    assert "| 말풍선 정상화 | 진행 1장 · 최근 완성 1장 — 실시간 통역 «키보드 고침» · «긴 발화 확정 고침» (기계 채움) | 강의 시험 합격 |" in goal
    todo = section(after, "## 2. 오빠 할 일")
    assert todo[0].startswith(f"## 2. 오빠 할 일 (기계 채움 {NOW:%m-%d %H:%M} · 4건 = 질문 1 · 실행 줄 2 · 자율 큐 1)")
    assert "손으로 쓴 옛 할 일 하나" not in after
    team = section(after, "## 3. 팀 작업")
    assert "| 팀 | 지금 하는 것 | 다음 |" in team and "| 결제 | 진행 1장 — «구독 환불 고침» · 최근 완성 1장 — «잔액 정리 지연 한 줄» · 완료·착지 쪽지 1통 | 대기 카드 1장 |" in team
    assert any(ln.startswith("| 하네스 | 진행 1장 — «원장 자동 채움»") for ln in team) and not any("kk" in ln for ln in team)
    assert run(world["repo"], "status", "--porcelain") == ""  # 작업 트리 손댐 0


def test_b_no_change_no_commit_and_todo_rows_equal_ledger_sum(world):
    fill(world)
    n1 = n_commits(world)
    rc, sha = fill(world, NOW + timedelta(minutes=7))  # 시각만 다른 판 = 같은 판
    assert (rc, sha) == (0, sha_of(world, BR)) and n_commits(world) == n1  # r870 r4 — «변화 없음» = 읽은 판(사본 ⊇ main → 사본 머리)
    rows = [ln for ln in section(origin_ledger(world), "## 2. 오빠 할 일") if re.match(r"\d+\. ", ln)]
    assert len(rows) == 1 + 2 + 1  # 질문 열린 1(전달됨 제외) + h 대기 2 + QUEUE 빈칸 1


def test_c_freshness_61_min_note_and_one_urgent(world):
    stale = ledger(NOW - timedelta(minutes=61))
    assert lf.fresh_note(world["root"], stale, NOW) == "원장 61분 낡음 · 담당 planner arch#14"
    assert lf.fresh_note(world["root"], stale, NOW + timedelta(minutes=1)) == "원장 62분 낡음 · 담당 planner arch#14"
    sent = world["mlog"].read_text(encoding="utf-8").splitlines()
    assert len(sent) == 1 and sent[0].startswith("send byz-planner-master-claude#9 ft-ledger-fill [긴급] 원장 61분 낡음")  # 같은 사건 두 번째 = 0
    assert lf.fresh_note(world["root"], ledger(NOW - timedelta(minutes=60)), NOW) == ""
    lf._ok(lf.state_dir(world["root"]), NOW - timedelta(minutes=5), [])  # 채움 성공 5분 전 = 신선
    assert lf.fresh_note(world["root"], stale, NOW) == ""
    assert lf.freshness("> 마지막 갱신: 2026-10-24 14:0x · planner#124", datetime(2026, 10, 24, 15, 10), "")[0] == 61  # «0x» = 그 10분의 끝(14:09)


def test_c_news_head_and_zero_change_line_carry_note(world, monkeypatch):
    import ft_news_html as fh
    import ft_news_publish as np
    state, lines = world["tmp"] / "news", []
    state.mkdir()
    stamp = f"{NOW:%Y-%m-%d %H:%M}"
    (state / "html.json").write_text(json.dumps({"at": f"{NOW - timedelta(hours=1):%Y-%m-%d %H:%M}", "map_at": stamp}), encoding="utf-8")
    (state / "last.blob").write_text("B\n", encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_NOW", stamp)
    monkeypatch.delenv("FT_NEWS_HEAD", raising=False)
    monkeypatch.delenv("FT_LEDGER_SYNC_ERROR", raising=False)
    monkeypatch.setattr(np, "retry_attach", lambda now: None)
    monkeypatch.setattr(np, "publish_line", lambda text, now: lines.append(text) or 0)
    monkeypatch.setattr(fh, "_ledger_blob", lambda *a: "B")
    monkeypatch.setattr(fh, "_canon_sha", lambda: "")
    monkeypatch.setattr(fh, "ledger_fill", lambda root, repo, rel, cur: cur)
    monkeypatch.setattr(fh, "ledger_fresh", lambda *a: "원장 61분 낡음 · 담당 planner arch#14")
    assert fh.tick(world["root"], state, world["repo"], REL, world["tmp"], "c", "c") == (0, "원장 커밋 0")
    assert lines and lines[0].endswith("변화 없음 · 지도 " + stamp + " · 원장 61분 낡음 · 담당 planner arch#14")
    assert "원장 61분 낡음" in os.environ["FT_NEWS_HEAD"]


def test_c_magazine_stale_ledger_publishes_zero_rc6(world):
    run(world["repo"], "pull", "-q", "origin", "main")
    write(world["repo"], REL, ledger(NOW - timedelta(minutes=61)))
    run(world["repo"], "commit", "-qam", "낡은 원장")
    marker = world["tmp"] / "doc-ran"
    fake = world["tmp"] / "fake_doc.py"
    fake.write_text(f"open({str(marker)!r}, 'w').write('x')\n", encoding="utf-8")
    env = {**os.environ, "FT_LEDGER_REPO": str(world["repo"]), "FT_LEDGER_PATH": REL, "FT_LEDGER_SYNCED": "1",
           "FT_LEDGER_FRESH": str(BIN / "ft-ledger-fill"), "FT_LEDGER_FRESH_GATE": "1", "FT_MAGAZINE_DOC": str(fake)}
    done = subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), "--dry-run"], capture_output=True, text=True, env=env)
    assert done.returncode == 6 and "원장 61분 낡음" in done.stderr and not marker.exists()
    write(world["repo"], REL, ledger(NOW - timedelta(minutes=10)))
    run(world["repo"], "commit", "-qam", "새 원장")
    assert subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), "--dry-run"], capture_output=True, text=True, env=env).returncode == 0 and marker.exists()


def test_d_all_landed_commits_no_15_cap(tmp_path, monkeypatch):
    import ft_news_html as fh
    repo = tmp_path / "r"
    subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
    run(repo, "commit", "-q", "--allow-empty", "-m", "base")
    base = run(repo, "rev-parse", "HEAD").strip()
    for i in range(40):
        run(repo, "commit", "-q", "--allow-empty", "-m", f"착지 {i}")
    monkeypatch.setenv("FT_NEWS_MAIN_REF", "main")
    monkeypatch.delenv("FT_NEWS_COMMITS", raising=False)
    assert len(src.landed_commits(repo, base, "main")) == 40 and len(fh.commits(repo, base)) == 40
    assert len(fh.commits(repo, "")) == 15  # 기준선 없는 첫 판만 15


def test_e_closed_row_moves_only_after_publish_success(world):
    closed = "| 2 | 옛 일 닫기 | 코드 | 닫힘 — 오빠 확인 끝 | — |"
    fill(world)  # 처음 봄 — 발행 기록 없음 = 이동 0
    assert closed in section(origin_ledger(world), "## 1.")
    world["mag"].write_text(json.dumps({"k": {"uploaded": False, "at": f"{NOW + timedelta(minutes=1):%Y-%m-%d %H:%M}"}}), encoding="utf-8")
    fill(world, NOW + timedelta(minutes=2))  # 발행 실패(uploaded False) = 이동 0
    assert closed in section(origin_ledger(world), "## 1.")
    world["mag"].write_text(json.dumps({"k": {"uploaded": True, "at": f"{NOW + timedelta(minutes=1):%Y-%m-%d %H:%M}"}}), encoding="utf-8")
    rc, sha = fill(world, NOW + timedelta(minutes=3))
    text = origin_ledger(world)
    assert rc == 0 and sha and closed not in section(text, "## 1.") and "| 1 | 열린 일 | 발주 | 진행 — 앞 단계 | — |" in text
    five = section(text, "## 5.")
    assert five[-2] == f"| 10-12-2 | 옛 일 닫기 | 코드 | 닫힘 — 오빠 확인 끝 | {NOW + timedelta(minutes=3):%m-%d} |" and "| 10-15-11 | 옛 보관 줄 | 코드 | 끝 | 10-15 |" in five


def test_f_broken_source_skips_only_that_table_error_rc1(world, caplog):
    world["q"].write_text("{깨짐", encoding="utf-8")
    rc, sha = fill(world)
    text = origin_ledger(world)
    assert rc == 1 and sha  # 다른 표는 갱신·커밋 · rc≠0
    assert "1. 손으로 쓴 옛 할 일 하나" in text and "결제 «구독 환불 고침» · «잔액 정리 지연 한 줄» (기계 채움)" in text  # 오빠 할 일 = 옛 표 그대로(새 것처럼 0)
    assert any("오빠 할 일 표 갱신 0" in r.message and r.levelname == "ERROR" for r in caplog.records)
    assert not (lf.state_dir(world["root"]) / "last-ok.json").exists()  # 표 하나라도 실패 = 채움 성공 아님


def _clone(w, name: str) -> Path:
    other = w["tmp"] / name
    subprocess.run(["git", "clone", "-q", str(w["origin"]), str(other)], check=True, capture_output=True)
    return other


def test_f_planner_edit_on_main_wins_when_branch_behind(world):
    fill(world)
    other = _clone(world, "planner")  # planner 손 편집이 main 에 착지 → 사본 브랜치는 main 보다 뒤처짐
    write(other, REL, (other / REL).read_text(encoding="utf-8").replace(CONCLUSION, CONCLUSION + " planner 손 편집."))
    run(other, "commit", "-qam", "planner 손")
    run(other, "push", "-q", "origin", "main")
    main1 = sha_of(world, "main")
    rc, sha = fill(world, NOW + timedelta(minutes=1))
    text = origin_ledger(world)
    parents = run(world["repo"], "rev-list", "--parents", "-n", "1", sha).split()[1:]
    assert rc == 0 and "planner 손 편집." in text and "결제 «구독 환불 고침» · «잔액 정리 지연 한 줄» (기계 채움)" in text
    assert parents[0] == main1 and len(parents) == 2 and sha_of(world, "main") == main1  # main 위 판 · 옛 브랜치 머리 = 두 번째 부모(ff · 강제 0)


def test_f_concurrent_branch_push_retries_on_new_base(world, monkeypatch):
    fill(world)
    other = _clone(world, "rival")
    run(other, "checkout", "-q", "-b", "x", f"origin/{BR}")
    real, calls = lf.gather, []

    def racing(*a):
        if not calls:  # 첫 렌더 직후 다른 판이 사본 브랜치에 먼저 올라감
            write(other, REL, (other / REL).read_text(encoding="utf-8").replace(CONCLUSION, CONCLUSION + " 다른 판."))
            run(other, "commit", "-qam", "다른 판")
            run(other, "push", "-q", "origin", f"x:{BR}")
        calls.append(1)
        return real(*a)
    monkeypatch.setattr(lf, "gather", racing)
    world["q"].write_text(json.dumps({"open": {"9": {"seat": "byz-cfo-x#1", "what": "새 질문", "state": "open"}}}, ensure_ascii=False), encoding="utf-8")  # 바뀜 = push 시도
    rc, sha = lf.fill(world["root"], world["repo"], REL, "origin/main", NOW + timedelta(minutes=9), do_fetch=True, push=True)
    text = origin_ledger(world)
    assert rc == 0 and len(calls) == 2 and "다른 판." in text and "«새 질문»" in text  # 거절 → 다시 받고 새 판 위 1번 더(다른 판 덮기 0)


def test_r2_news_and_magazine_read_branch_when_ahead_else_main(world, monkeypatch):
    import ft_news_ledger as nl
    monkeypatch.delenv("FT_NEWS_MAIN_REF", raising=False)
    repo = world["repo"]
    assert nl.news_cur(repo, REL, ref_mode=True) == sha_of(world, "main")  # 브랜치 없음 = main
    rc, sha = fill(world)
    assert nl.news_cur(repo, REL, ref_mode=True) == sha  # 앞선 사본 브랜치 = 뉴스가 읽는 판
    copy = _clone(world, "news-copy")
    run(copy, "checkout", "-q", "--detach", "origin/main")
    sync = lambda: subprocess.run(["bash", str(BIN / "ft-ledger-repo-sync.sh"), str(copy)], capture_output=True, text=True)  # noqa: E731
    assert sync().returncode == 0 and run(copy, "rev-parse", "HEAD").strip() == sha  # 매거진 사본 = 같은 판
    other = _clone(world, "planner2")
    run(other, "commit", "-q", "--allow-empty", "-m", "main 전진")
    run(other, "push", "-q", "origin", "main")
    run(repo, "fetch", "-q", "origin", "main")
    main2 = sha_of(world, "main")
    assert nl.news_cur(repo, REL, ref_mode=True) == main2  # 브랜치가 main 보다 뒤처짐 = main
    assert sync().returncode == 0 and run(copy, "rev-parse", "HEAD").strip() == main2


def test_f_push_failure_rc1_nothing_landed(world, monkeypatch):
    n0 = n_commits(world)
    run(world["repo"], "remote", "set-url", "--push", "origin", str(world["tmp"] / "없는곳.git"))
    with pytest.raises(src.FillError):
        fill(world)
    assert n_commits(world) == n0 and lf.main(["fill", "--repo", str(world["repo"]), "--push"]) == 1
    assert src.LOCAL_S == 7.0 and lf.REMOTE_S == 10.5  # 7초 룰(원격 = 고정비 3.5 + 7)


def test_g_filled_text_passes_magazine_guide_and_date_rules(world):
    from magazine_date_guard import _QUOTED, _WORD
    from magazine_guide_check import _CMD, RULES
    assert list(tb.GUIDE) == [rx.pattern for _n, rx in RULES[:6]]  # 칸 청소 규칙 = 매거진 지침 검사 글자 그대로
    fill(world)
    text = origin_ledger(world)
    machine = [ln for p in ("## 2. 오빠 할 일", "## 3. 팀 작업") for ln in section(text, p)[1:]] + [ln for ln in section(text, "## 메인 골") if "기계 채움" in ln]
    hits = [(n, ln) for ln in machine for n, rx in RULES if rx.search(_CMD.sub("", ln))]
    assert not hits and not [ln for ln in machine if _WORD.search(_QUOTED.sub("", ln))]


# ── r3: 외부 DA⑥ r1 HOLD 6 반례 그대로(REWORK-r851-r3) ──

def _main_ledger(w, text: str) -> None:
    """원격 main 원장을 text 로(planner 손 편집 대역) — 사본 repo 의 origin/main 도 그 판."""
    write(w["repo"], REL, text)
    run(w["repo"], "commit", "-qam", "planner 손 편집")
    run(w["repo"], "push", "-q", "origin", "main")


@pytest.mark.parametrize("name", ["main", "HEAD", "refs/heads/main", "feature/x", "ledger/", "ledger/../main", "ledger/a.lock"])
def test_r1_branch_outside_ledger_prefix_rejected_push_zero(world, monkeypatch, caplog, name):
    main0 = sha_of(world, "main")
    monkeypatch.setenv("FT_LEDGER_FILL_BRANCH", name)
    assert lf.main(["fill", "--repo", str(world["repo"]), "--push"]) == 1  # 입구 거절 rc1
    assert sha_of(world, "main") == main0 and n_commits(world) == 0 and not sha_of(world, BR)  # main SHA 그대로 · push 0
    assert lf.main(["fresh", "--repo", str(world["repo"])]) == 1
    copy = _clone(world, "copy-" + str(len(name)))
    run(copy, "checkout", "-q", "--detach", "origin/main")
    sync = subprocess.run(["bash", str(BIN / "ft-ledger-repo-sync.sh"), str(copy)], capture_output=True, text=True)
    assert sync.returncode == 1 and "ledger/" in sync.stdout  # 매거진 사본 동기화도 같은 거절


def test_r2_quotepath_true_korean_card_paths_still_counted(world):
    run(world["repo"], "config", "core.quotepath", "true")
    raw = run(world["repo"], "ls-tree", "-r", "--name-only", "origin/main", "--", "design/teams/cfo/indices/")
    assert "\\" in raw  # 이 설정이면 날 git 은 한글 경로를 따옴표·8진수로 낸다(반례 재현)
    cfo = src.team_cards(world["repo"], "origin/main", NOW)["cfo"]
    assert len(cfo["진행"]) == 1 and cfo["대기"] == 1 and [n for n, _t in cfo["착지"]] == ["cfo-done"]


def test_r3_branch_only_advance_news_and_magazine_same_latest(world, monkeypatch):
    import ft_news_ledger as nl
    for k in ("FT_NEWS_MAIN_REF", "FT_LEDGER_FETCH", "FT_LEDGER_SYNC_ERROR", "FT_LEDGER_SYNC_REPEAT"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("FT_NEWS_FETCH_MIN", "0")
    monkeypatch.setenv("FT_NEWS_FETCH_STAMP", str(world["tmp"] / "fetch.stamp"))
    monkeypatch.setenv("FT_NEWS_FETCH_LAST", str(world["tmp"] / "fetch-last"))
    news, mag = _clone(world, "news"), _clone(world, "mag")
    run(mag, "checkout", "-q", "--detach", "origin/main")
    sync = lambda: subprocess.run(["bash", str(BIN / "ft-ledger-repo-sync.sh"), str(mag)], capture_output=True, text=True)  # noqa: E731
    _rc, sha1 = fill(world)
    assert nl.fetch_if_stale(news) == "" and nl.news_cur(news, REL, ref_mode=True) == sha1
    assert sync().returncode == 0 and run(mag, "rev-parse", "HEAD").strip() == sha1
    main0 = sha_of(world, "main")
    world["q"].write_text(json.dumps({"open": {"9": {"seat": "byz-cfo-x#1", "what": "새 질문", "state": "open"}}}, ensure_ascii=False), encoding="utf-8")
    _rc, sha2 = fill(world, NOW + timedelta(minutes=5))  # 사본 브랜치만 전진(main 그대로)
    assert sha2 and sha2 != sha1 and sha_of(world, "main") == main0
    assert nl.fetch_if_stale(news) == "" and nl.news_cur(news, REL, ref_mode=True) == sha2  # 뉴스 = 최신 판(옛 판 «변화 없음» 0)
    assert sync().returncode == 0 and run(mag, "rev-parse", "HEAD").strip() == sha2  # 매거진 = 같은 판


def test_r4_memo_line_before_team_table_kept(world):
    memo = "> planner 메모: 결제 줄은 오빠 확인 뒤 다시 씀 — 손으로 쓴 줄"
    before = origin_ledger(world, "main")
    _main_ledger(world, before.replace("## 3. 팀 작업 — 지난밤 기록\n", f"## 3. 팀 작업 — 지난밤 기록\n{memo}\n"))
    rc, sha = fill(world)
    team = section(origin_ledger(world), "## 3. 팀 작업")
    assert rc == 0 and sha and team[:3] == ["## 3. 팀 작업 — 지난밤 기록", memo, "| 팀 | 지금 하는 것 | 다음 |"]  # 머리·메모 바이트 그대로
    assert "| 결제 | 손으로 쓴 옛 줄 | 옛 다음 |" not in team and any(ln.startswith("| 결제 | 진행 1장") for ln in team)


def test_r4_two_tables_in_team_section_update_zero_error(world, caplog):
    before = origin_ledger(world, "main")
    _main_ledger(world, before.replace("## 4. 드러난 문제", "메모 줄\n| 다른 | 표 |\n|---|---|\n\n## 4. 드러난 문제"))
    rc, sha = fill(world)
    team = section(origin_ledger(world), "## 3. 팀 작업")
    assert rc == 1 and sha and "| 결제 | 손으로 쓴 옛 줄 | 옛 다음 |" in team and "| 다른 | 표 |" in team
    assert any("팀 작업 표 갱신 0" in r.message and "표 2개" in r.message and r.levelname == "ERROR" for r in caplog.records)


def test_r5_not_done_state_row_stays_open(world):
    row = "| 2 | 옛 일 닫기 | 코드 | 완료 아님 — 승인 대기 | — |"
    _main_ledger(world, ledger(NOW - timedelta(hours=3), row))
    fill(world)
    world["mag"].write_text(json.dumps({"k": {"uploaded": True, "at": f"{NOW + timedelta(minutes=1):%Y-%m-%d %H:%M}"}}), encoding="utf-8")
    fill(world, NOW + timedelta(minutes=3))  # 발행 성공 기록이 있어도 상태 낱말이 닫힘 집합 밖 = 내림 0
    text = origin_ledger(world)
    assert row in section(text, "## 1.") and "승인 대기" not in "\n".join(section(text, "## 5."))
    assert [tb.CLOSED.__contains__(s.split("—", 1)[0].strip()) for s in ("닫힘", "닫힘 — 끝", "완료", "완료 아님 — x", "완료됨", "진행 — 완료 직전")] \
        == [True, True, True, False, False, False]


@pytest.mark.parametrize("bad", ['{"open": ["x"]}', '[1, 2]', '{"open": {"1": "문자열"}}', '"글자"'])
def test_r6_question_ledger_wrong_shape_only_that_table_zero(world, caplog, bad):
    world["q"].write_text(bad, encoding="utf-8")
    rc, sha = fill(world)
    text = origin_ledger(world)
    assert rc == 1 and sha and n_commits(world) == 1  # 다른 표는 갱신·커밋 1
    assert "1. 손으로 쓴 옛 할 일 하나" in text and any(ln.startswith("| 결제 | 진행 1장") for ln in section(text, "## 3. 팀 작업"))
    assert any("오빠 할 일 표 갱신 0" in r.message and r.levelname == "ERROR" for r in caplog.records)


# ── r4: 외부 DA⑥ r2 반례 그대로(REWORK-r851-r4 · 원천의 줄은 전부 꼴에 맞거나 원천 전체가 오류 · 걸러내기 0) ──

def _hil(w, out: str) -> None:
    (w["tmp"] / "hil.sh").write_text(f"#!/usr/bin/env bash\nprintf '{out}'\n", encoding="utf-8")  # out = printf 이스케이프(\\n) 그대로


def test_r7_hil_broken_line_rc0_whole_source_error_last_ok_kept_magazine_stale(world, caplog):
    st = lf.state_dir(world["root"])
    st.mkdir(parents=True)
    old = f"{NOW - timedelta(hours=2):%Y-%m-%d %H:%M}"
    (st / "last-ok.json").write_text(json.dumps({"at": old}), encoding="utf-8")
    _hil(world, "h5 30\\nh7 깨짐\\n")  # 대역 rc0 · 둘째 줄만 깨짐
    rc, sha = fill(world)
    text = origin_ledger(world)
    assert rc == 1 and sha  # 다른 표는 갱신·커밋
    assert "1. 손으로 쓴 옛 할 일 하나" in text and "h5" not in "\n".join(section(text, "## 2. 오빠 할 일"))  # 오빠 할 일 = 옛 표 그대로(h7 뺀 3건 0)
    assert any(ln.startswith("| 결제 | 진행 1장") for ln in section(text, "## 3. 팀 작업"))
    errs = [r.message for r in caplog.records if r.levelname == "ERROR"]
    assert len(errs) == 1 and "오빠 할 일 표 갱신 0" in errs[0] and "줄 2" in errs[0] and "h7 깨짐" in errs[0]
    assert json.loads((st / "last-ok.json").read_text(encoding="utf-8")) == {"at": old}  # 성공 기록 0(전 값 그대로)
    env = {**os.environ, "FT_LEDGER_REPO": str(world["repo"]), "FT_LEDGER_PATH": REL, "FT_LEDGER_SYNCED": "1",
           "FT_LEDGER_FRESH": str(BIN / "ft-ledger-fill"), "FT_LEDGER_FRESH_GATE": "1", "FT_MAGAZINE_DOC": str(world["tmp"] / "nope.py")}
    done = subprocess.run(["bash", str(KIT / "magazine_from_news.sh"), "--dry-run"], capture_output=True, text=True, env=env)
    assert done.returncode == 6 and "낡음" in done.stderr  # 매거진 신선도 게이트 = 낡음


def _break_teams(w):
    _main_ledger_file(w, "design/TEAMS.md", TEAMS + "| lecture | `design/teams/lecture/` | 현역 |\n")


def _main_ledger_file(w, rel: str, text: str) -> None:
    write(w["repo"], rel, text)
    run(w["repo"], "commit", "-qam", f"{rel} 손 편집")
    run(w["repo"], "push", "-q", "origin", "main")


BROKEN = {
    "hil": (lambda w: _hil(w, "h5 30\\nh7 깨짐\\n"), "오빠 할 일"),
    "queue": (lambda w: w["tmp"].joinpath("AUTONOMY-QUEUE.md").write_text(
        w["tmp"].joinpath("AUTONOMY-QUEUE.md").read_text(encoding="utf-8") + "| A2 | t | 짧은 행 |\n", encoding="utf-8"), "오빠 할 일"),
    "questions": (lambda w: w["q"].write_text(json.dumps({"open": {
        "150540": {"seat": "byz-v65-master-claude#238", "what": "정상 질문", "state": "open"},
        "150542": {"seat": "byz-cfo-x#1", "state": "open"}}}, ensure_ascii=False), encoding="utf-8"), "오빠 할 일"),  # 열린 항목에 what 없음
    "teams": (_break_teams, "팀 작업"),
    "mailbox": (lambda w: (w["root"] / ".fable-team/comm/mailbox.jsonl").open("a", encoding="utf-8").write("{깨짐\n"), "팀 작업"),
}


@pytest.mark.parametrize("which", list(BROKEN))
def test_r7b_each_source_one_broken_line_only_its_tables_zero(world, caplog, which):
    BROKEN[which][0](world)
    rc, sha = fill(world)
    text = origin_ledger(world)
    todo, team = "\n".join(section(text, "## 2. 오빠 할 일")), section(text, "## 3. 팀 작업")
    assert rc == 1 and sha
    errs = [r.message for r in caplog.records if r.levelname == "ERROR"]
    assert errs and all("꼴 틀림" in e for e in errs) and any(f"{BROKEN[which][1]} 표 갱신 0" in e for e in errs)
    if BROKEN[which][1] == "오빠 할 일":
        assert "1. 손으로 쓴 옛 할 일 하나" in todo and any(ln.startswith("| 결제 | 진행 1장") for ln in team)
    else:
        assert "| 결제 | 손으로 쓴 옛 줄 | 옛 다음 |" in team and "1. 손으로 쓴 옛 할 일 하나" not in todo and "실행 줄" in todo


def test_r7c_blank_and_comment_lines_only_are_fine(world, caplog):
    _hil(world, "\\nh5 30\\n\\nh7 3\\n\\n")
    qf = world["tmp"] / "AUTONOMY-QUEUE.md"
    qf.write_text("# AUTONOMY-QUEUE — 제목\n\n> 메모 줄\n\n" + qf.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    _main_ledger_file(world, "design/TEAMS.md", "# 팀 명단\n\n설명 글줄\n\n" + TEAMS + "\n- 옛 이름 메모\n")
    rc, sha = fill(world)
    todo = "\n".join(section(origin_ledger(world), "## 2. 오빠 할 일"))
    assert rc == 0 and sha and not [r for r in caplog.records if r.levelname == "ERROR"]
    assert "실행 줄 2" in todo and "자율 큐 1" in todo and "질문 1" in todo


# ── r5: 외부 DA⑥ r3 반례 그대로(REWORK-r851-r5 · 쪽지함 꼬리 첫 줄 경계 = 꼬리 앞 1바이트가 개행이면 첫 줄은 완전한 줄) ──

def _big_mailbox(w, first: str) -> Path:
    """쪽지함 > MAILBOX_TAIL · 꼬리 시작 = first 줄 시작(바로 앞 바이트 = 개행)."""
    box = w["root"] / ".fable-team/comm/mailbox.jsonl"
    def filler(n: int) -> str:  # 정확히 n 바이트 줄(옛 시각 · 셈 0)
        base = json.dumps({"ts": (NOW - timedelta(days=3)).isoformat(), "from": "byz-ops-x#0", "body": ""})
        return base.replace('"body": ""', '"body": "' + "x" * (n - 1 - len(base)) + '"') + "\n"
    head = (first + "\n").encode("utf-8")
    rest, body = src.MAILBOX_TAIL - len(head), []
    while rest >= 2000:
        body.append(filler(1000))
        rest -= 1000
    body.append(filler(rest))
    data = "".join(filler(500) for _ in range(5)).encode() + head + "".join(body).encode()
    box.write_bytes(data)
    assert len(data) > src.MAILBOX_TAIL and data[len(data) - src.MAILBOX_TAIL - 1:len(data) - src.MAILBOX_TAIL + len(head)] == b"\n" + head
    return box


def test_r9_tail_starts_at_line_start_done_note_counted(world):
    note = json.dumps({"ts": (NOW - timedelta(hours=1)).isoformat(), "from": "byz-cfo-nano-y#0", "body": "[완료·휴식] 꼬리 첫 줄"}, ensure_ascii=False)
    box = _big_mailbox(world, note)
    assert src.mbox_done(box, NOW) == {"cfo": 1}  # 꼬리 첫 줄 = 완전한 줄 → 셈에 포함
    rc, sha = fill(world)
    assert rc == 0 and sha and any(ln.startswith("| 결제 | ") and "완료·착지 쪽지 1통" in ln for ln in section(origin_ledger(world), "## 3. 팀 작업"))


def test_r9b_tail_starts_at_broken_whole_line_source_error(world, caplog):
    _big_mailbox(world, "{깨짐")
    rc, sha = fill(world)
    team = section(origin_ledger(world), "## 3. 팀 작업")
    errs = [r.message for r in caplog.records if r.levelname == "ERROR"]
    assert rc == 1 and sha and "| 결제 | 손으로 쓴 옛 줄 | 옛 다음 |" in team  # 그 표 갱신 0(다른 표는 커밋)
    assert len(errs) == 1 and "팀 작업 표 갱신 0" in errs[0] and "쪽지함 꼬리" in errs[0] and "{깨짐" in errs[0]
    assert not (lf.state_dir(world["root"]) / "last-ok.json").exists()
