"""r867 아침 매거진 «끝낸 일 축하(eli5) + 남은 일 풀 설명» — 임시 원장 사본 + 날짜 고정 git 이력 · 가짜 쉬운 풀이 명령 · Slack 0 · 실 원장 0.

판 날짜 10-16 → 축하 창 = 10-15 00:00 ~ 10-16 08:00 KST(끝 제외).
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE python3 -m pytest tests/scripts/test_magazine_celebrate.py -q
"""
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest
import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다

import magazine_celebrate as mc
import magazine_doc as md
import magazine_eli5
import magazine_celebrate_eli5 as mb

DATE = "2026-10-16"
ROWS = {  # 일 → 상태 (판마다 바꿔 끼운다)
    "가입 메일 고치기": "완료 — 메일 감 (main abc1234)",
    "툴바 접기": "진행 — 시안",
    "키 교체": "진행 — 이름 규칙",
    "음성 보정": "진행 — 빈칸 고치는 중",
    "운영 화면": "진행 — 두 번째 제안서",
    "메일 링크": "오빠 확인 대기",
    "정리 절차": "막힘 — 검토 직전 정지",
}
SHAS: dict[str, str] = {}  # fixture 가 채우는 근거 커밋 앞 10자
CARD = "# 인덱스: r{n}-easy-news — 끝: 닫는 증거\n\n## 골 원문 (항상 이 3줄)\n골\n\n## 배경 (한 단락)\n{bg}\n\n## 상태\n- 완성\n"
FAKE_ELI5 = r'''import json, os, re, sys, time
p = sys.stdin.read()
log = os.environ["ELI5_LOG"]
open(log, "a", encoding="utf-8").write("call\n")
time.sleep(float(os.environ.get("ELI5_SLEEP", "0")))
units = json.loads(re.search(r"<자료>\n(.*)\n</자료>", p, re.S).group(1))
print(json.dumps({"units": [{"ref": u["ref"], "icon": "🌱", "title": "새로 좋아진 일이 생겼어요", "analogy": os.environ.get("ELI5_ANALOGY", "작은 정원에 새 꽃이 피었어요"),
                             "lines": ["이제 더 쉽게 읽을 수 있어요"]} for u in units]}, ensure_ascii=False))
'''


def ledger(rows: dict[str, str]) -> str:
    body = "\n".join(f"| {i} | {task} | 코드 | {state} | |" for i, (task, state) in enumerate(rows.items(), 1))
    return (f"# 오빠 원장\n\n**결론**: 일하는 팀이 셋이에요.\n\n## 1. 오빠가 시킨 일 — 지금 상태\n\n### 10-14 시키신 일\n"
            f"| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |\n|---|---|---|---|---|\n{body}\n\n"
            "## 2. 오빠 할 일 (10-16)\n- 지금:\n  - 키 교체 이름 정하기\n\n"
            "## 3. 팀 작업 (10-16)\n| 팀 | 지금 하는 것 | 다음 |\n|---|---|---|\n| 하네스 | 매거진 고치기 | 시험 |\n")


def commit(repo: Path, when: str, files: dict[str, str | None]) -> str:
    """파일 바꾸고 그 시각으로 커밋 → 앞 10자 sha(원장 행 근거로 쓴다)."""
    for rel, text in files.items():
        path = repo / rel
        if text is None:
            path.unlink()
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when}
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", when], check=True, env=env)
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "--short=10", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def env(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    repo.mkdir()
    for args in (("init", "-q", "-b", "main"), ("config", "user.email", "t@t"), ("config", "user.name", "t")):
        subprocess.run(["git", "-C", str(repo), *args], check=True)
    rows = dict(ROWS)  # r3 — 원장 행 근거 sha 는 실제 커밋(그 커밋 시각이 창 안인가로 판정) · «가입 메일» 의 abc1234 는 없는 커밋 = 축하 0 + WARNING
    commit(repo, "2026-10-14T12:00:00+09:00", {"doc.md": ledger(rows), "design/harness/indices/진행/r901-x.md": CARD.format(n=901, bg="뉴스 창이 빨라졌어요. 이제 1초 만에 떠요.")})
    SHAS["운영"] = commit(repo, "2026-10-14T23:59:00+09:00", {"code/ops.txt": "ops"})
    rows["운영 화면"] = f"완료 — 창 전 착지 (main {SHAS['운영']})"  # 근거 커밋이 창 밖
    commit(repo, "2026-10-14T23:59:59+09:00", {"doc.md": ledger(rows), "design/harness/indices/완성/r899-old.md": CARD.format(n=899, bg="창 밖 카드예요.")})
    commit(repo, "2026-10-15T00:00:00+09:00", {"design/harness/indices/완성/r900-easy-news.md": CARD.format(n=900, bg="아침 뉴스를 쉬운 말로 바꿨어요. 이제 누구나 읽어요.")})
    SHAS["툴바"] = commit(repo, "2026-10-15T09:00:00+09:00", {"code/toolbar.txt": "fold"})
    rows["툴바 접기"] = f"완료 — 배포 화면 확인 (판정 1765 · {SHAS['툴바']})"
    rows["키 교체"] = "완료 — 시험 통과"  # 닫는 증거(커밋 번호) 없음 — 축하 0
    commit(repo, "2026-10-15T10:00:00+09:00", {"doc.md": ledger(rows), "design/harness/indices/진행/r901-x.md": None,
                                               "design/harness/indices/완성/r901-x.md": CARD.format(n=901, bg="뉴스 창이 빨라졌어요. 이제 1초 만에 떠요.")})
    rows["메일 링크"] = f"완료 — 링크 확인 (#1612 · {commit(repo, '2026-10-16T07:00:00+09:00', {'code/mail.txt': 'link'})})"
    commit(repo, "2026-10-16T07:59:59+09:00", {"doc.md": ledger(rows)})
    rows["음성 보정"] = f"완료 — 창 뒤 착지 (main {commit(repo, '2026-10-16T08:00:00+09:00', {'code/voice.txt': 'v'})})"  # 근거 커밋 = 창 끝 = 창 밖
    commit(repo, "2026-10-16T08:00:00+09:00", {"doc.md": ledger(rows), "design/harness/indices/완성/r902-late.md": CARD.format(n=902, bg="창 끝 카드예요.")})
    script = tmp_path / "fake_eli5.py"
    script.write_text(FAKE_ELI5, encoding="utf-8")
    monkeypatch.setenv("ELI5_LOG", str(tmp_path / "calls.log"))
    monkeypatch.setattr(magazine_eli5, "_skill", lambda: "쉬운 말로 써요")
    return tmp_path, repo, f"{sys.executable} {script}"


def run(env, date: str = DATE) -> tuple[int, str]:
    tmp, repo, cmd = env
    rc = md.main(["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", "doc.md", "--date", date, "--out-dir", str(tmp / "out"),
                  "--state", str(tmp / "state.json"), "--eli5-cmd", cmd, "--dry-run"])
    pages = sorted((tmp / "out").glob(f"MAGAZINE-DOC-{date}-*.html"))
    return rc, pages[-1].read_text(encoding="utf-8") if pages else ""


def part1(page: str) -> str:
    return page.split("<h2>끝낸 일</h2>", 1)[1].split('class="part"', 1)[0]


def calls(env) -> int:
    log = env[0] / "calls.log"
    return len(log.read_text(encoding="utf-8").splitlines()) if log.exists() else 0


def test_a_only_closing_evidence_inside_the_window_is_celebrated(env):
    span, done = mc.collect(str(env[1]), "HEAD", "doc.md", DATE)
    assert span == "10-15 00:00 ~ 10-16 08:00"
    # r3 — 카드 축하 재료 = 카드 제목(«끝:» 앞 이름) + sha 만(배경 글 옮기기 삭제 · DA⑥ r2 반례 3)
    assert [d.title for d in done] == ["툴바 접기", "메일 링크", "r901-easy-news", "r900-easy-news"]
    assert [d.chip for d in done] == ["원장 · 오빠가 시킨 일"] * 2 + ["harness 팀 · 카드 완성"] * 2
    rc, page = run(env)
    top = part1(page)
    assert rc == 0 and "툴바 접기" in top and "메일 링크" in top and "r900-easy-news" in top
    for out in ("가입 메일", "운영 화면", "음성 보정", "키 교체", "r899", "r902", "창 밖 카드", "창 끝 카드", "아침 뉴스를"):
        assert out not in top


def test_b_each_done_has_one_easy_paragraph_and_a_cheer_head(env):
    rc, page = run(env)
    top = part1(page)
    assert rc == 0 and "🎉 축하해요! 10-15 00:00 ~ 10-16 08:00 사이에 4건을 끝냈어요" in top
    assert top.count('class="done"') == 4 and top.count("🌱 작은 정원에 새 꽃이 피었어요") == 4 and top.count("<h3>새로 좋아진 일이 생겼어요</h3>") == 4
    assert "원문 — 툴바 접기 · 완료 — 배포 화면 확인" in top  # 쉬운 제목 아래 원문 한 줄(사실 칸)
    for token in ("판정 1765", SHAS["툴바"], "#1612"):
        assert token not in top  # 번호는 근거 표로 · r3 부터 카드 이름은 축하 제목이라 본문에 실린다
    footer = page.split("<footer>")[1]
    assert f"판정 1765 · {SHAS['툴바']}" in footer and "카드 r900-easy-news" in footer


def test_b_zero_done_says_zero_honestly_without_any_call(env):
    rc, page = run(env, "2026-10-20")
    top = part1(page)
    assert rc == 0 and "10-19 00:00 ~ 10-20 08:00 사이에 끝낸 일은 0건이에요" in top
    assert "🎉" not in top and "축하해요" not in top and 'class="done"' not in top and calls(env) == 0


def test_c_remaining_part_follows_with_full_sections_and_no_index(env, capsys):
    rc, page = run(env)
    assert rc == 0 and "WARN 지침" not in capsys.readouterr().out
    i_done, i_part, i_todo = page.index("<h2>끝낸 일</h2>"), page.index('class="part"'), page.index("<h2>오빠 할 일</h2>")
    assert i_done < i_part < i_todo < page.index("<h2>눈여겨볼 열린 일</h2>") < page.index("<h2>팀은 지금</h2>")
    assert "아래는 남은 일이에요" in page and "키 교체 이름 정하기" in page and "검토 직전 정지" in page[i_part:]


def test_d_git_failure_is_an_error_not_a_half_page(env, caplog):
    tmp, repo, cmd = env
    with caplog.at_level(logging.ERROR, logger="magazine_doc"):
        rc = md.main(["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", "doc.md", "--date", DATE, "--out-dir", str(tmp / "out"),
                      "--state", str(tmp / "state.json"), "--eli5-cmd", cmd, "--done-ref", "no-such-ref", "--dry-run"])
    assert rc == 1 and not (tmp / "out").exists() and "발행 실패" in caplog.text


def test_e_seven_second_rule_and_visible_failure(env, monkeypatch, caplog):
    assert mb.TIMEOUT == 7.0 and mb.BATCH_SIZE == 2 and mb.DEADLINE_S <= 70  # 하드 룰 12 — 호출당 7초 · 입력 2장씩 쪼개기 · 전체 70초
    monkeypatch.setattr(mb, "TIMEOUT", 0.3)
    monkeypatch.setenv("ELI5_SLEEP", "2")
    start = time.monotonic()
    with caplog.at_level(logging.ERROR):
        rc, page = run(env)
    top = part1(page)
    assert rc == 0 and time.monotonic() - start < 6
    assert top.count('class="done"') == 4 and top.count("쉬운 풀이 생성 실패 — 호출 실패") == 4 and "쉬운 풀이 생략" in caplog.text
    assert "<h3>툴바 접기</h3>" in top and "원문 —" not in top  # 실패면 제목 = 원문(사실 칸) 그대로


def test_e_easy_text_breaking_the_guide_is_shown_as_failed(env, monkeypatch, capsys):
    monkeypatch.setenv("ELI5_ANALOGY", "다양한 꽃이 피었어요")
    rc, page = run(env)
    top = part1(page)
    assert rc == 0 and "다양한" not in page and top.count("쉬운 풀이 생성 실패 — 지침 위반 문장") == 4
    assert "WARN 지침" not in capsys.readouterr().out


def test_e_whole_batch_deadline_marks_late_batches_as_timeout(env, monkeypatch):
    monkeypatch.setattr(mb, "DEADLINE_S", 0.5)
    monkeypatch.setenv("ELI5_SLEEP", "1.5")
    rc, page = run(env)
    assert rc == 0 and part1(page).count("쉬운 풀이 생성 실패 — 시간 초과") == 4
