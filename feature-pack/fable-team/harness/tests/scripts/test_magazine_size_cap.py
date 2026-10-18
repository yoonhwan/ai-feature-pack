"""R74(판정 812 A안) — 아침 매거진 크기 상한: 한 건 3줄 · 한 절 40건 · 쉬운 판 카드 12장 · md·PDF 경보선(raise).

가짜 모델·가짜 LLM·가짜 PDF 변환기만 쓴다(실 슬랙·실 LLM·실 매거진 파일 0).
실행: python3 -m pytest tests/scripts/test_magazine_size_cap.py -q
"""
import json
import re
import sys
from pathlib import Path

import pytest
from _magazine_detail_fixture import fake_eli5, fake_full_model, fake_pdf
from _magazine_eli5_kit import NOTES, UNIT, model as eli5_model, skill  # noqa: F401 — skill 은 pytest 픽스처
from _magazine_fakes import SUMMARY_OK
from _thread_fakes import ledger, resume_script, seats

import byz_morning_magazine as cli
import magazine_eli5 as me
import magazine_render_cap as mrc
import magazine_render_full as mrf

LINES = ["한 줄", "두 줄", "세 줄"]
GOLDEN = Path(__file__).with_name("_magazine_small_golden.md")
BODY = "\n".join(f"본문 줄 {i}" for i in range(50))
FIXED_H3 = ("요청 원장", "HOLD·REJECT", "승계 ", "신규 좌석", "닫힘 (", "형식 미달")  # 한 건이 아닌 고정 소제목


def section(md: str, name: str) -> str:
    return md.split(f"## {name}")[1].split("\n## ")[0]


def text_lines(n: int, prefix: str = "줄") -> str:
    return "\n".join(f"{prefix} {i}" for i in range(n))


def big_model() -> dict:
    """머지 200 · 판정 300 · 열린 카드 250 — 본문은 전부 50줄."""
    m = fake_full_model()
    m["merges"] = [{"sha": f"{i:010x}" + "0" * 30, "at": "x", "title": f"[feature] 머지 {i} (#{1000 + i})", "pr": 1000 + i, "tag": "[feature]"} for i in range(200)]
    m["detail"]["merge_bodies"] = {mg["sha"]: BODY for mg in m["merges"]}
    m["detail"]["decisions"] = [{"n": 400 + i, "ts": "2026-10-07T20:00:00+09:00", "to": "x#1", "body": BODY, "relay_path": f"/tmp/mbox/{i}.md", "relay_text": BODY,
                                 "rollback": ["되돌림: x"], "more": 0} for i in range(300)]
    m["detail"]["open"]["cards"] = [{"team": "harness", "state": "진행", "path": f"design/harness/indices/진행/c{i}.md", "title": f"카드 {i}", "tail": BODY.split("\n")} for i in range(250)]
    return m


def real_day_model() -> dict:
    """10-10 호 규모(판정 821): 닫힌 단위 41(why 12줄) · 판정 절 16(30줄) · 판정 188(6줄 · 홀수만 relay 25줄) · 머지 87(70줄) · 닫은 이슈 50(8줄)+연 이슈 10 · 카드 226(tail 3줄) · 부록 5(40줄)."""
    m = fake_full_model()
    d = m["detail"]
    d["units"] = [{**d["units"][0], "path": f"design/harness/indices/완성/u{i}.md", "title": f"단위 {i}", "why": text_lines(12, "왜"), "da": f"design/harness/DA-{i}.md#§1"} for i in range(41)]
    d["verdict_sections"] = [{"path": "design/harness/OPS-VERDICTS-20261010.md", "section": f"§{i}", "title": f"판정서 절 {i}", "body": text_lines(30, "절")} for i in range(16)]
    d["decisions"] = [{"n": 600 + i, "ts": "2026-10-09T20:00:00+09:00", "to": "x#1", "body": text_lines(6, "쪽지"), "relay_path": f"/tmp/mbox/r{i}.md",
                       "relay_text": text_lines(25, "전문") if i % 2 else None, "rollback": ["되돌림: x"], "more": i % 3 == 0} for i in range(188)]
    m["merges"] = [{"sha": f"{i:010x}" + "1" * 30, "at": "x", "title": f"[feature] 머지 {i} (#{2000 + i})", "pr": 2000 + i, "tag": "[feature]"} for i in range(87)]
    d["merge_bodies"] = {mg["sha"]: text_lines(70, "커밋") for mg in m["merges"]}
    m["issues_closed"] = [{"number": 3000 + i, "title": f"닫은 {i}", "state": "CLOSED", "url": "https://x"} for i in range(50)]
    m["issues_opened"] = [{"number": 3100 + i, "title": f"연 {i}", "state": "OPEN", "url": "https://x"} for i in range(10)]
    d["issue_evidence"] = {str(i["number"]): text_lines(8, "댓글") for i in m["issues_closed"]}
    d["open"]["cards"] = [{"team": "harness", "state": "진행", "path": f"design/harness/indices/진행/c{i}.md", "title": f"카드 {i}", "tail": ["a", "b", "c"]} for i in range(226)]
    d["appendix"] = [{"path": f"design/harness/BRIEFING-{i}.md", "text": text_lines(40, "브리핑")} for i in range(5)]
    m["verdicts"] = [{"n": 600 + i, "line": f"판정 {600 + i} 줄"} for i in range(188)]
    m["docs"] = [{"path": f"design/harness/DOC-{i}.md", "url": f"https://github.com/o/r/blob/main/{i}.md"} for i in range(46)]  # 1부 구간이 실제 10-10 호(277줄)에 가깝게
    return m


def items_of(md: str) -> list[tuple[str, str]]:
    """2부의 «한 건» (제목 줄, 본문 덩어리) — 고정 소제목은 뺀다. 제목 바로 다음 블록이 본문이어야 한다."""
    blocks = md.split("# 2부 풀 디테일")[1].split("\n\n")
    out = []
    for i, b in enumerate(blocks):
        if b.startswith("### ") and not b[4:].startswith(FIXED_H3):
            out.append((b, blocks[i + 1]))
    return out


def test_big_model_each_section_keeps_20_items_and_counts_the_rest_exactly():
    md, _ = mrf.render_full(big_model(), LINES, "t")
    d3, d4, d6 = section(md, "D3 판정(결정 원문)"), section(md, "D4 main 에 들어간 것"), section(md, "D6 열린 행")
    assert len(re.findall(r"^### 판정 4\d\d$", d3, re.M)) == 20 and "외 280건 — 원문: " in d3
    assert len(re.findall(r"^### \[feature\] 머지", d4, re.M)) == 20 and "외 180건 — 원문: " in d4
    assert len(re.findall(r"^### \[harness/진행\] 카드", d6, re.M)) == 20 and "외 230건 — 원문: " in d6
    tail4 = d4.split("외 180건")[1]  # 빠진 건 = 21번째(0x14)부터 200번째(0xc7)까지 — 위치(sha 앞 10자)가 전부 목록에 있다
    assert "0000000014" in tail4 and "00000000c7" in tail4 and "0000000013" not in tail4
    assert "/tmp/mbox/299.md" in d3.split("외 280건")[1] and "/tmp/mbox/19.md" not in d3.split("외 280건")[1]
    assert "design/harness/indices/진행/c249.md" in d6.split("외 230건")[1]


@pytest.mark.parametrize("make", [big_model, real_day_model, fake_full_model])
def test_every_item_is_title_then_at_most_three_body_lines_then_one_location_line(make):
    md, _ = mrf.render_full(make(), LINES, "t")
    items = items_of(md)
    assert items
    for title, body in items:
        rows = body.split("\n")
        assert all(r.startswith(">") for r in rows) and 2 <= len(rows) <= mrc.ITEM_LINES + 1, (title, body)
        assert rows[-1].startswith("> … 원문: ") and not any(r.startswith("> … 원문: ") for r in rows[:-1]), (title, body)
    assert "본문 줄 3\n" not in md and "본문 줄 49" not in md  # 4번째 줄부터는 어디에도 실리지 않는다


def test_real_day_model_fits_under_the_md_line_alarm_with_measured_values():
    m = real_day_model()
    md, _ = mrf.render_full(m, [f"요약 {i}" for i in range(5)], "t")
    part1 = md.split("# 2부 풀 디테일")[0]
    per = {n: section(md, n).count("\n") for n in ("D1 닫힌 단위", "D2 판정서 절", "D3 판정(결정 원문)", "D4 main 에 들어간 것", "D5 이슈", "D6 열린 행", "D7 좌석", "부록 — 브리핑·마감 문서")}
    print(f"[10-10 규모 md] 전체 {md.count(chr(10))}줄 {len(md.encode())}바이트 · 1부 {part1.count(chr(10))}줄 · 절별 {per} · 각주표 {len(md.split('## 각주표')[1].splitlines())}줄")
    assert 265 <= part1.count("\n") <= 290  # 모델이 실제 10-10 호의 1부(약 277줄)를 닮았는지
    assert md.count("\n") <= mrc.MD_MAX_LINES and len(md.encode()) <= mrc.MD_MAX_BYTES


def test_small_model_has_no_overflow_line_and_short_bodies_are_fully_visible():
    m = fake_full_model()
    m["detail"]["merge_bodies"] = {"1" * 40: "Why: 요약.\nWhat: 미러.\nVerify: 시험."}
    md, _ = mrf.render_full(m, LINES, "t", None)
    assert not re.search(r"^외 \d+건", md.split("# 2부 풀 디테일")[1], re.M)
    assert "> Why: 요약.\n> What: 미러.\n> Verify: 시험.\n> … 원문: 1111111111" in md and "> 본문 1\n> 본문 2\n> 본문 4\n" in md
    assert md == GOLDEN.read_text(encoding="utf-8")  # r1 모양 골든 — 모양이 의도 없이 바뀌면 여기서 잡힌다


def test_cap_item_always_appends_location_and_skips_blank_lines():
    assert mrc.cap_item("t", ["a\n\nb", "c\nd"], "W")[0] == [("h3", "t"), ("lines", "a\nb\nc\n… 원문: W")]
    assert mrc.cap_item("t", ["a"], "W")[0][1] == ("lines", "a\n… 원문: W")
    assert mrc.cap_item("t", [""], "W")[0][1] == ("lines", "… 원문: W")


def easy_llm(seen: list[list[str]]):
    def run(cmd, prompt, timeout):  # noqa: ANN001, ANN202
        batch = json.loads(prompt.rsplit("<자료>\n", 1)[1].split("\n</자료>")[0])
        seen.append([u["path"] for u in batch])
        return json.dumps({"units": [{"ref": u["path"], "icon": "🪟", "analogy": "책상 위 작은 창", "lines": ["한눈에 찾아봐요"]} for u in batch]}, ensure_ascii=False)
    return run


def test_eli5_41_units_give_12_cards_and_29_title_lines_and_llm_sees_only_12(skill, monkeypatch):  # noqa: F811
    m, seen = eli5_model(hil=()), []
    m["detail"]["units"] = [{**UNIT, "path": f"u{i}", "title": f"단위 제목 {i}"} for i in range(41)]
    monkeypatch.setattr(me, "run_cmd", easy_llm(seen))
    page = me.build(m, NOTES, "fake", LINES)
    assert page.count('<article class="unit-card">') == 12
    titles = page.split('<ul class="more-titles">')[1].split("</ul>")[0]
    assert titles.count("<li>") == 29 and "그 밖의 닫힌 일 29건" in page and "단위 제목 12" in titles and "단위 제목 40" in titles and "단위 제목 11" not in titles
    assert sorted(p for batch in seen for p in batch) == sorted(f"u{i}" for i in range(12))  # 가짜 LLM 호출 대상 12개
    assert page.stats["total"] == 41 and "AI 풀이 12/12 (전체 41)" in page


def test_eli5_at_or_under_12_units_has_no_title_list(skill, monkeypatch):  # noqa: F811
    monkeypatch.setattr(me, "run_cmd", easy_llm([]))
    page = me.build(eli5_model(hil=()), NOTES, "fake", LINES)
    assert page.count('<article class="unit-card">') == 1 and "more-titles" not in page and "(전체" not in page


def make_args(tmp_path, slack_base: str = "http://127.0.0.1:9"):
    tmp_path.mkdir(exist_ok=True)
    (tmp_path / "sum.py").write_text(SUMMARY_OK, encoding="utf-8")
    return cli.parse_args(["--summary-cmd", f"python3 {tmp_path / 'sum.py'}", "--out-dir", str(tmp_path / "out"), "--state", str(tmp_path / "state.json"),
                           "--slack-base", slack_base, "--channel", "C1", "--ledger", str(ledger(tmp_path)), "--seats-file", str(seats(tmp_path)),
                           "--resume-script", str(resume_script(tmp_path)), "--date", "2026-10-08", "--no-push"])


@pytest.fixture
def fakes(monkeypatch):
    monkeypatch.setitem(sys.modules, "magazine_eli5", fake_eli5())


def test_md_over_the_line_cap_raises_magazine_size_error_with_values(tmp_path, monkeypatch, fakes):
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(3))
    monkeypatch.setattr(mrc, "MD_MAX_LINES", 50)
    with pytest.raises(mrc.MagazineSizeError, match=r"md 크기 초과 — \d+줄·\d+바이트 \(상한 50줄"):
        cli.make_files(fake_full_model(), make_args(tmp_path))


def test_md_over_the_byte_cap_raises(tmp_path, monkeypatch, fakes):
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(3))
    monkeypatch.setattr(mrc, "MD_MAX_BYTES", 1000)
    with pytest.raises(mrc.MagazineSizeError, match="md 크기 초과"):
        cli.make_files(fake_full_model(), make_args(tmp_path))


def test_pdf_over_the_page_cap_raises_but_at_the_cap_passes(tmp_path, monkeypatch, fakes):
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(mrc.PDF_MAX_PAGES + 1))
    with pytest.raises(mrc.MagazineSizeError, match=rf"{mrc.PDF_MAX_PAGES + 1}쪽 \(상한 {mrc.PDF_MAX_PAGES}쪽\)"):
        cli.make_files(fake_full_model(), make_args(tmp_path))
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(mrc.PDF_MAX_PAGES))
    assert cli.make_files(fake_full_model(), make_args(tmp_path / "ok")).pages == mrc.PDF_MAX_PAGES


def test_size_error_takes_the_existing_failure_path(tmp_path, monkeypatch, fakes, caplog):
    """run() 의 `except Exception` → report_failure — 새 실패 경로를 만들지 않는다(--dry-run 이라 슬랙 게시는 없다)."""
    monkeypatch.setattr(cli, "html_to_pdf", fake_pdf(mrc.PDF_MAX_PAGES + 1))
    (tmp_path / "model.json").write_text(json.dumps(fake_full_model()), encoding="utf-8")
    args = make_args(tmp_path)
    args.model_file, args.dry_run = str(tmp_path / "model.json"), True
    assert cli.run(args) == 1
    assert any("MagazineSizeError" in r.getMessage() and "발행 실패" in r.getMessage() for r in caplog.records)
