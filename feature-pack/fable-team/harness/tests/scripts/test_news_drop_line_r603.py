"""r603 — 뉴스 «한 줄 위반 = 판 전체 발행 0» 을 «그 줄만 빼고 각주로 표시해 발행» 으로 (하드 룰 14 재설계 · 설계서 DESIGN-news-partial-publish-drop-line-20261021.md).

무른 위반(린트가 «summary N»·«important N» 으로 꾸는 것) = 그 줄·항목만 빼고 판 각주 «빠진 줄 N개 — <갈래 번호>: <사유>» + 슬랙 본문 요약 끝 «(빠진 줄 N)» + ERROR 로그 1줄.
굳은 위반(절 6·골 6행·시크릿·각주 밖 번호·귀속 없음·뺀 뒤 중요한 일 0) = 지금처럼 발행 0 · 스위치(FT_NEWS_DROP_LINE) 없으면 전부 바이트 그대로.
시험 입력 = HTML·요약 문자열과 가짜 live 뿐(실 모델·슬랙·좌석·press 0).
실행: python3 -m pytest tests/scripts/test_news_drop_line_r603.py -q
"""
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
sys.path[:0] = [str(BIN)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(ROOT / "harness" / "kit" / "slack-mirror"))

import ft_news_html as fh  # noqa: E402
import ft_news_html_lint as lint  # noqa: E402
import ft_news_html_render as fr  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

APPROVAL = "1번 골 마감 승인 대기다"
TEAMS = ["chatbot", "harness", "ops", "v65"]
LIVE = [{"team": t, "live": 1, "working": 1, "unknown": 0} for t in TEAMS]


def _html(important: list[str], auto: str = "ON", working: int = 2, goals: int = 6) -> str:
    lis = "\n".join(f'      <li><div class="what"><strong>일 {i}</strong><span>{d}</span></div>'
                    f'<span class="who">t</span></li>' for i, d in enumerate(important, 1))
    work = '  <section class="goal work">\n    <p class="say">팀</p>\n  </section>\n' * working
    goals_html = '  <section class="goal">\n    골\n  </section>\n' * goals
    h2 = "".join(f"<h2>{h}</h2>" for h in lint.H2)
    return (f"<h1>{lint.H1}</h1>{h2}<section class=\"prio\">\n    <ol>\n{lis}\n    </ol>\n  </section>\n"
            f"{goals_html}{work}<p class=\"foot\">근거: 원장 · 자율 {auto}</p>")


@pytest.fixture
def switch_on(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FT_NEWS_DROP_LINE", "1")


@pytest.fixture
def switch_off(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FT_NEWS_DROP_LINE", raising=False)


def test_r603_a_soft_line_dropped_and_shown(switch_on, caplog):
    """ⓐ 자율 ON 인데 «승인 대기» 줄 — 지금 판 = 발행 0 · 고친 판 = 그 줄 없이 발행 + 각주 + ERROR 1줄."""
    page, summary = _html(["가", "나"]), "가\n나\n" + APPROVAL
    assert len(lint.problems(page, summary)) == 1  # 지금 판 = 위반 1건 = 발행 0(FAIL 기준)

    new_html, new_sum, dropped = fh.drop_soft(page, summary)
    assert [p for p in lint.problems(new_html, new_sum)] == []
    assert APPROVAL not in new_sum
    assert new_sum.splitlines() == ["가", "나 (빠진 줄 1)"]
    assert "빠진 줄 1개 — summary 3: 자율 ON 인데 승인 대기 문장" in new_html
    assert len(dropped) == 1 and dropped[0].startswith("summary 3: ")


def test_r603_a_publish_logs_one_error_line_and_writes_dropped_files(switch_on, tmp_path, monkeypatch, caplog):
    """ⓐ(발행 경로) 무른 위반 = ERROR «무른 위반 1건 — 줄 빼고 발행 (…)» 1줄 · 파일에 빠진 줄 반영."""
    page, summary = _html(["가", "나"]), "가\n나\n" + APPROVAL
    html_p, sum_p = tmp_path / "n.html", tmp_path / "n.txt"
    html_p.write_text(page, encoding="utf-8")
    sum_p.write_text(summary, encoding="utf-8")
    monkeypatch.setitem(sys.modules, "ft_news_publish", _stub_publish(0, {"permalink": "x"}))
    caplog.set_level("ERROR")
    rc, got = fh.publish_files(html_p, sum_p, __import__("datetime").datetime(2026, 10, 21, 6, 0))
    assert rc == 0 and got == {"permalink": "x"}
    assert [r.message for r in caplog.records if "무른 위반" in str(r.message)]  # 1줄
    assert APPROVAL not in sum_p.read_text(encoding="utf-8")
    assert "빠진 줄 1개" in html_p.read_text(encoding="utf-8")


def _stub_publish(rc: int, receipt: dict):
    import types
    mod = types.ModuleType("ft_news_publish")
    mod.publish_html = lambda html_p, summary, now: (rc, receipt)
    return mod


def test_r603_b_status_line_kept_and_model_lines_dropped_from_end(switch_on):
    """ⓑ 요약 상태 줄 + 모델 2줄 = 640B → 뒤에서부터 통째로 빼 600B 안 · 상태 줄 유지 · 줄 중간 자르기 0 · 꼬리 표시."""
    c = {**fr.bucket({}, LIVE), "summary": ["가" * 95, "나" * 95]}
    c["summary"] = [s for s in c["summary"]]
    out = fr.add_status_line(dict(c))
    lines = out["summary"]
    assert lines[0] == fr.status_line(fr.bucket({}, LIVE))
    assert len(lines) <= fr.SUMMARY_LINES and len("\n".join(lines).encode("utf-8")) <= fr.SUMMARY_BYTES
    assert out["dropped"] and "(빠진 줄 " in lines[-1]
    # 남은 모델 줄 = 원문 그대로(꼬리만 뒤에 붙음) — 중간 자르기 0
    for ln in lines[1:]:
        assert ln.split(" (빠진 줄 ")[0] in c["summary"]


def test_r603_c_important_item_dropped(switch_on):
    """ⓒ important 4번째 «모든 팀 멈춤»(일하는 팀 ≥1) → 그 항목만 빼고 발행(중요한 일 3개)."""
    page = _html(["가", "나", "다", "모든 팀 멈춤"])
    new_html, new_sum, dropped = fh.drop_soft(page, "가\n나")
    assert [p for p in lint.problems(new_html, new_sum)] == []
    assert "<strong>일 4</strong>" not in new_html  # 그 항목(lí)만 빠짐(각주 인용에는 문장이 남는다)
    assert len(lint.problems(page, "가\n나")) == 1
    assert dropped[0].startswith("important 4: ")
    assert "빠진 줄 1개" in new_html


def test_r603_d_zero_important_after_drop_is_publish_zero(switch_on):
    """ⓓ 빼고 나니 중요한 일 0개 → 지금과 같이 발행 0(줄 빼기 0)."""
    page = _html(["모든 팀 멈춤"])
    new_html, new_sum, dropped = fh.drop_soft(page, "가\n나")
    assert dropped == [] and new_html == page and new_sum == "가\n나"
    assert any("모든 팀" in p for p in lint.problems(new_html, new_sum))


@pytest.mark.parametrize("case", ["secret", "goal5", "footnum"])
def test_r603_e_hard_violations_publish_zero(switch_on, case):
    """ⓔ 굳은 위반(시크릿 꼴 · 골 5행 · 각주 밖 번호) → 발행 0 유지 · 줄 빼기 0."""
    page, summary = _html(["가", "나"]), "가\n나"
    if case == "secret":
        page = page.replace("자율 ON", "자율 ON sk-" + "a" * 20)
    elif case == "goal5":
        page = _html(["가", "나"], goals=5)
    else:
        page = _html(["가", "나"]).replace("<h2>일하는 팀</h2>", "<h2>일하는 팀</h2>판정 12")
    new_html, new_sum, dropped = fh.drop_soft(page, summary)
    assert dropped == [] and new_html == page and new_sum == summary
    assert lint.problems(new_html, new_sum)


def test_r603_f_switch_off_is_byte_identical(switch_off, tmp_path, monkeypatch):
    """ⓕ 스위치 없음 → 모든 경우 지금 판과 바이트 같은 동작(회귀 0)."""
    page, summary = _html(["가", "나"]), "가\n나\n" + APPROVAL
    html_p, sum_p = tmp_path / "n.html", tmp_path / "n.txt"
    html_p.write_text(page, encoding="utf-8")
    sum_p.write_text(summary, encoding="utf-8")
    monkeypatch.setitem(sys.modules, "ft_news_publish", _stub_publish(0, {}))
    rc, got = fh.publish_files(html_p, sum_p, __import__("datetime").datetime(2026, 10, 21, 6, 0))
    assert rc == 3 and got is None  # 발행 0 = 지금 동작
    assert html_p.read_text(encoding="utf-8") == page and sum_p.read_text(encoding="utf-8") == summary
    # add_status_line 도 지금처럼 ERROR(자르기 0)
    c = {**fr.bucket({}, LIVE), "summary": ["가" * 95, "나" * 95]}
    with pytest.raises(fr.NewsHtmlError) as e:
        fr.add_status_line(dict(c))
    assert "자르지 않는다" in str(e.value)


def test_r603_g_tail_keeps_summary_under_600(switch_on):
    """ⓖ «(빠진 줄 N)» 꼬리를 붙여도 요약 600B 이하(린트 통과)."""
    page, summary = _html(["가", "나"], working=2), "가\n나\n" + APPROVAL
    new_html, new_sum, dropped = fh.drop_soft(page, summary)
    assert dropped and "(빠진 줄 1)" in new_sum
    assert len(new_sum.encode("utf-8")) <= lint.SUMMARY_BYTES
    assert lint.problems(new_html, new_sum) == []
