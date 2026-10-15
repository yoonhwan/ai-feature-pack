"""R190 아침 매거진 맨 위 3칸(요청한 일 / 완료한 일 / 해야 할 일) 묶기 + 발행 결과 슬랙 링크. 네트워크 0 · 가짜 Slack · 가짜 프록시.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY python3 -m pytest tests/scripts/test_magazine_doc_three.py -q
"""
import json
import logging
import re
from pathlib import Path

import pytest
from _magazine_fakes import FakeMagazineSlack, git
from test_magazine_doc import SRC

import magazine_doc as md
import magazine_doc_md as dm
import magazine_doc_three as three
import magazine_hermes as mh

DATE = "2026-10-15"
LEDGER = """# 오빠 원장 — 시킨 일 · 하기로 한 일 · 지금 상태 (정본 · planner 관리)

> 오빠 지시: 「매거진」
> 마지막 갱신: 2026-10-15 07:5x

---

## 1. 오빠가 시킨 일 — 지금 상태

> 칸(판정 1443): **순번** = 발주 순서

### 어제(10-14) 시키신 일
| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |
|---|---|---|---|---|
|  | 가입 메일 | 코드 | 완료 |  |
|  | 폰 물결 | 코드 | 진행 — 폰 확인 | 100 |
|  | 단가 | 결정 | ✅ push abc | 101 |
|  | 새 일 | 문서 | 보류 — 사유 | 102 |

### 오늘(10-15) 시키신 일
| 순번 | 시키신 일 | 종류 | 지금 상태 | 발주 쪽지 |
|---|---|---|---|---|
|  | 모두 완료 | 코드 | 완료 — 끝 | 103 |

## 2. 오빠 할 일 (아침 큐)
- ✅자율 OFF
- push 승인 5건

## 2-1. 발주한 것 (planner → 팀 · 지금 상태)
| 발주 | 받은 팀 | 지금 상태 |
|---|---|---|
| 매거진 | 하네스 | 완료 — 오빠 «완벽» |
| 뉴스 | 하네스 | 진행 — 개편 |

## 3. 팀 작업 (팀 차례)
- 하네스: 일함

## 4. 드러난 문제
- 카드 상태 줄이 다름

## 5. 완료 보관 (오빠가 매거진에서 «본» 완료 줄)
| 순번 | 시키신 일 | 종류 | 닫는 증거 | 내린 날 |
|---|---|---|---|---|
|  | 어제 내림 | 승인 | ✅ a | 2026-10-14 |
|  | 오늘 내림 | 승인 | ✅ b | 10-15 |
|  | 오래됨 | 승인 | ✅ c | 2026-10-10 |
|  | 날짜 없음 | 승인 | ✅ d | 86850~86856 |
"""
REAL = Path(__file__).resolve().parents[1] / "fixtures" / "magazine" / "PLAN-oppa-ledger-20261014.md"
SEP = re.compile(r"^\|[\s:|-]+\|$")


def data_rows(text: str) -> list[str]:
    lines = text.splitlines()
    return [ln for i, ln in enumerate(lines) if ln.startswith("|") and not SEP.match(ln)
            and not (i + 1 < len(lines) and SEP.match(lines[i + 1]))]


def bullets(text: str) -> list[str]:
    return [ln for ln in text.splitlines() if ln.startswith("- ")]


def cell(cells: list[dm.Cell], word: str) -> dm.Cell:
    return next(c for c in cells if word in c.title)


def split(ledger: str = LEDGER):
    doc = dm.parse_doc(ledger)
    got, rest = three.group_three(doc, DATE)
    return doc, got, rest


def row_sums_hold(doc: dm.Doc, got: list[dm.Cell], dropped: int) -> bool:
    """ⓐ 3칸 행 합 == 원장 §1·§2-1·§5 행 합 − 날짜 창 밖으로 내린 행 · ③ 글머리 == §2 글머리."""
    src = sum(len(data_rows(c.body)) for c in doc.cells if re.match(r"(오빠가 시킨 일|2-1\.|완료 보관)", c.title))
    mine = sum(len(data_rows(c.body)) for c in got[:2])
    return mine == src - dropped and len(bullets(got[2].body)) == len(bullets(cell(doc.cells, "오빠 할 일").body))


def test_a_rows_kept_verbatim_and_sums_equal():
    doc, got, _ = split()
    assert [c.title for c in got] == ["요청한 일", "완료한 일", "해야 할 일"]
    assert row_sums_hold(doc, got, dropped=1)  # 오래됨 1행만 창 밖
    src_lines = LEDGER.splitlines()
    for ln in data_rows(got[0].body) + data_rows(got[1].body) + bullets(got[2].body):
        assert ln in src_lines  # 원문 줄 그대로(바이트 일치)
    all_rows = data_rows(got[0].body) + data_rows(got[1].body)
    assert len(all_rows) == len(set(all_rows))  # 중복 0


def test_b_state_split_done_and_checkmark_go_to_done_rest_to_requested(caplog):
    with caplog.at_level(logging.WARNING, logger="magazine_doc"):
        _, got, _ = split()
    open_rows, done_rows = data_rows(got[0].body), data_rows(got[1].body)
    open_text = "\n".join(open_rows)
    assert len(open_rows) == 3 and all(w in open_text for w in ("폰 물결", "새 일", "뉴스"))  # 모르는 «보류» 도 요청한 일
    assert not any(w in open_text for w in ("가입 메일", "단가", "모두 완료", "매거진"))
    names = " ".join(done_rows)
    for want in ("가입 메일", "단가", "모두 완료", "매거진", "어제 내림", "오늘 내림", "날짜 없음"):
        assert want in names
    assert "오래됨" not in names
    texts = [r.getMessage() for r in caplog.records if r.levelno == logging.WARNING]
    assert any("보류" in t and "1건" in t for t in texts)  # 상태 낱말 모름 경고 1줄
    assert any("날짜" in t and "1건" in t for t in texts)  # §5 날짜 못 읽은 행(쪽지 번호) 경고 1줄


def test_b_headings_and_header_rows_travel_with_rows():
    _, got, _ = split()
    assert "### 어제(10-14) 시키신 일" in got[0].body and "### 오늘(10-15) 시키신 일" not in got[0].body  # 행 0 인 표는 소제목째 뺀다
    assert "### 오늘(10-15) 시키신 일" in got[1].body and "### 어제(10-14) 시키신 일" in got[1].body
    assert got[0].body.count("| 순번 | 시키신 일 |") == 1 and got[0].body.count("| 발주 | 받은 팀 |") == 1
    assert "2-1. 발주한 것" in got[0].body and "2-1. 발주한 것" in got[1].body


def test_c_rest_keeps_team_work_and_problems_below_three():
    doc, got, rest = split()
    assert [c.title for c in rest] == ["팀 작업 (팀 차례)", "드러난 문제"]
    merged = three.with_three(doc, DATE)
    assert [c.title for c in merged.cells] == ["요청한 일", "완료한 일", "해야 할 일", "팀 작업 (팀 차례)", "드러난 문제"]
    assert [c.key for c in merged.cells] == ["c1", "c2", "c3", "c4", "c5"] and merged.teams == doc.teams


def test_d_old_doc_without_target_sections_is_unchanged():
    doc = dm.parse_doc(SRC)
    got, rest = three.group_three(doc, "2026-10-13")
    assert got == [] and rest == doc.cells
    assert three.with_three(doc, "2026-10-13") is doc


def test_table_without_status_header_goes_to_requested_with_warning(caplog):
    doc = dm.parse_doc("# 제목\n\n## 1. 오빠가 시킨 일\n| a | b |\n|---|---|\n| 1 | 2 |\n\n## 2. 오빠 할 일\n- x\n")
    with caplog.at_level(logging.WARNING, logger="magazine_doc"):
        got, _ = three.group_three(doc, DATE)
    assert "| 1 | 2 |" in got[0].body and any("지금 상태" in r.getMessage() for r in caplog.records)


def test_mutation_done_branch_removed_breaks_row_sums(monkeypatch):
    monkeypatch.setattr(three, "_is_done", lambda state: False)
    doc, got, _ = split()
    assert not (len(data_rows(got[1].body)) == 7)  # 완료 행이 §5 만 남는다 → ② 행 수 틀어짐
    assert [c.title for c in got][:1] == ["요청한 일"] and "가입 메일" in got[0].body  # 완료 행이 요청한 일로 샌다


def test_mutation_section5_date_filter_removed_breaks_done_count(monkeypatch):
    monkeypatch.setattr(three, "_in_window", lambda text, date: True)
    _, got, _ = split()
    assert "오래됨" in got[1].body  # 필터가 없으면 옛 행이 들어온다 → 행 합 != 기대


YEAR_END = LEDGER.replace("| 2026-10-14 |", "| 12-31 |").replace("| 10-15 |", "| 2027-01-01 |")


def test_year_boundary_dateless_prev_day_stays_in_done():
    got, _ = three.group_three(dm.parse_doc(YEAR_END), "2027-01-01")
    assert "어제 내림" in got[1].body and "오늘 내림" in got[1].body and "오래됨" not in got[1].body


def test_mutation_year_boundary_fix_removed_drops_row(monkeypatch):
    def naive(text: str, date: str) -> bool | None:  # 보정 전 로직: 연도 없는 날짜를 기준일 연도로만 읽음
        base = three.Date.fromisoformat(date)
        found = three._DAY.findall(text)
        days = [three.Date(int(y) if y else base.year, int(m), int(d)) for y, m, d in found]
        return any(base - three.timedelta(days=1) <= x <= base for x in days) if days else None
    monkeypatch.setattr(three, "_in_window", naive)
    got, _ = three.group_three(dm.parse_doc(YEAR_END), "2027-01-01")
    assert "어제 내림" not in got[1].body  # 보정이 없으면 12-31 행이 사라진다 → 위 단언이 FAIL 해야 정상


def test_real_ledger_rows_sum_and_nothing_lost(caplog):
    text = REAL.read_text(encoding="utf-8")
    doc = dm.parse_doc(text)
    with caplog.at_level(logging.WARNING, logger="magazine_doc"):
        got, rest = three.group_three(doc, "2026-10-14")
    assert [c.title for c in got] == ["요청한 일", "완료한 일", "해야 할 일"]
    src = sum(len(data_rows(c.body)) for c in doc.cells if re.match(r"(오빠가 시킨 일|2-1\.|완료 보관)", c.title))
    assert len(data_rows(got[0].body)) + len(data_rows(got[1].body)) == src  # §5 행은 날짜 못 읽어 전부 보존
    assert len(bullets(got[2].body)) == len(bullets(cell(doc.cells, "오빠 할 일").body))
    assert [c.title for c in rest] == [c.title for c in doc.cells if c.title.startswith(("팀 작업", "드러난 문제"))]


# ---- 렌더 · 발행 출력 -------------------------------------------------------
def fake_fetch(url: str, body: bytes, timeout: float) -> bytes:
    return json.dumps({"content": [{"type": "text", "text": "지금은 쉬는 중이고 곧 이어서 해요."}], "stop_reason": "end_turn", "usage": {"input_tokens": 700}}).encode()


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(mh, "_fetch", fake_fetch)
    repo = tmp_path / "repo"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    for k, v in (("user.email", "t@t"), ("user.name", "t")):
        git(repo, "config", k, v)
    (repo / "doc.md").write_text(LEDGER, encoding="utf-8")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "doc")
    (tmp_path / "tok").write_text("YOONHWAN_BOT_TOKEN=xoxb-test\n", encoding="utf-8")
    return tmp_path, repo


def argv(env, mode: str, slack: FakeMagazineSlack | None = None) -> list[str]:
    tmp, repo = env
    base = ["--src-repo", str(repo), "--src-sha", "HEAD", "--src-path", "doc.md", "--date", DATE, "--out-dir", str(tmp / "out"), "--proxy-url", "http://proxy.test", mode]
    if slack:
        base += ["--state", str(tmp / "state.json"), "--token-file", str(tmp / "tok"), "--slack-base", slack.base, "--channel", "C1"]
    return base


def test_render_puts_three_cells_on_top_with_jump_buttons(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    out = capsys.readouterr().out
    page = next((env[0] / "out").glob("MAGAZINE-DOC-2026-10-15-*.html")).read_text(encoding="utf-8")
    assert "DRY-RUN calls=5" in out  # 3칸 + 팀 작업 + 드러난 문제 — 호출 수 = 칸 수
    assert page.count('<section id="c') == 5 and page.count("지금은 쉬는 중이고 곧 이어서 해요.") == 5
    titles = re.findall(r'<h2 class="section-title">([^<]+)</h2>', page)
    assert titles[:3] == ["요청한 일", "완료한 일", "해야 할 일"]
    assert re.findall(r'<span class="section-index">(\d\d)</span>', page)[:3] == ["01", "02", "03"]
    jump = re.search(r'<nav class="jump"[^>]*>(.*?)</nav>', page, re.S).group(1)
    assert re.findall(r"<a [^>]*>([^<]*)</a>", jump)[:3] == ["요청한 일", "완료한 일", "해야 할 일"]


def test_dry_run_says_no_link(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    assert "SLACK 링크 없음(드라이런)" in capsys.readouterr().out


def test_publish_prints_slack_link_built_from_real_root_ts_and_skip_prints_it_too(env, capsys):
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0
    out = capsys.readouterr().out
    ts = slack.roots[0]["ts"]
    assert f"SLACK https://slack.test/archives/C1/p{ts.replace('.', '')}" in out
    assert md.main(argv(env, "--publish", slack)) == 0
    again = capsys.readouterr().out
    assert "skip" in again and f"SLACK https://slack.test/archives/C1/p{ts.replace('.', '')}" in again


def test_link_failure_is_printed_not_silent_and_publish_still_succeeds(env, capsys, caplog):
    slack = FakeMagazineSlack()
    slack.fail_permalink = True
    with caplog.at_level(logging.WARNING, logger="magazine_doc"):
        assert md.main(argv(env, "--publish", slack)) == 0
    out = capsys.readouterr().out
    assert "published date=2026-10-15" in out and "SLACK 링크 못 만듦 — " in out and "message_not_found" in out
    assert len(slack.roots) == 1 and slack.titles(slack.roots[0]["ts"])
