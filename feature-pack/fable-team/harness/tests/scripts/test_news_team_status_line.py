"""r588 — 뉴스 요약의 «팀 상태» 문장 때문에 발행 0: ①코드가 팀 상태 줄을 만들어 요약 첫 줄로 넣고 모델에는 쓰지 말라고 한다
②린트는 확인 불가 팀 이름이 든 «절» 안에서만 쉼 단정을 본다(같은 문장 다른 절 = 위반 아님).
가짜 opencode(FT_OPENCODE · 인자 기록) · 실 모델·실 슬랙·실 좌석 0.
실행: python3 -m pytest tests/scripts/test_news_team_status_line.py -q
"""
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import CONTENT, DATA, FAKE_OC, NOW  # noqa: E402

import ft_news_html as fh  # noqa: E402
import ft_news_html_lint as lint  # noqa: E402
import ft_news_html_render as fr  # noqa: E402

# 00:57 실제 로그 문장(arch 112 실측) — 확인 불가 팀이 «쉬며» 절과 «다른 절» 에 있다
REAL = ("지금은 다섯 팀(chatbot·loom·planner·ops·v65)이 일하고, 다섯 팀(cfo·issues·kk·lecture·room)이 쉬며, "
        "세 팀(feature·graphics·harness)은 상태 확인 불가다")
UNK = ["feature", "graphics", "harness"]
from _news_live import with_state  # noqa: E402  r850: live 팀 상태(state·label) = ft_team_state.judge 값

LIVE_UNK = with_state([{"team": t, "live": 2, "working": 0, "unknown": 2, "unknown_reason": "jsonl 없음 2석"} for t in UNK] + [
    {"team": "chatbot", "live": 3, "working": 2, "unknown": 0, "unknown_reason": ""}])
NEW = {**CONTENT, "summary": ["통역 고침 시험 중", "하네스 설치 끝"]}  # 모델 줄은 1~2줄(첫 줄은 코드가 넣는다)


@pytest.fixture
def oc(tmp_path, monkeypatch):
    """가짜 opencode — 답 글 파일(요약 2줄 판) · 인자 기록 파일."""
    exe, reply, log = tmp_path / "opencode", tmp_path / "reply.txt", tmp_path / "oc.log"
    exe.write_text(FAKE_OC, encoding="utf-8")
    exe.chmod(0o755)
    reply.write_text("```json\n" + json.dumps(NEW, ensure_ascii=False) + "\n```", encoding="utf-8")
    for k, v in {"FT_OPENCODE": str(exe), "FAKE_OC_REPLY": str(reply), "FAKE_OC_LOG": str(log),
                 "FT_NEWS_VIA": "opencode", "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv")}.items():
        monkeypatch.setenv(k, v)
    for k in ("FT_NEWS_EFFORT", "FT_NEWS_MODEL", "FT_NEWS_DEPTH", "FT_NEWS_FIXED_S"):
        monkeypatch.delenv(k, raising=False)
    return reply


@pytest.fixture
def unknown_page(tmp_path, oc):
    """확인 불가 팀 3(feature·graphics·harness) + 일하는 팀 1(chatbot) 인 지도."""
    return fh.run_files({**DATA, "live": LIVE_UNK}, tmp_path / "u", NOW)[0].read_text(encoding="utf-8")


# ⓐ 00:57 문장 그대로(확인 불가 팀은 «확인 불가» 절에만) → 위반 0 (지금 판 = 위반 3)
def test_r588_a_unknown_team_in_its_own_clause_is_not_a_rest_claim(unknown_page):
    assert [p for p in lint.problems(unknown_page, "가\n" + REAL) if "확인 불가 팀" in p] == []


# ⓑ 진짜 단정은 그대로 잡는다(«확인 불가 팀은 쉬는 팀이 아니다» 는 판정 불변)
@pytest.mark.parametrize("line", ["feature 는 쉬고 있다", "graphics 는 멈춘 상태다", "harness 는 대기 중이다"])
def test_r588_b_real_rest_claim_on_unknown_team_still_rejected(unknown_page, line):
    assert [p for p in lint.problems(unknown_page, "가\n" + line) if "확인 불가 팀" in p] == [f"확인 불가 팀 {line.split()[0]} 에 쉼 단정 «{line}»"]


# ⓒ 코드가 만든 상태 줄 = 요약 첫 줄 · 0개 칸 생략 · 린트 0 · 넘치면 «자르지 않고» ERROR
def test_r588_c_status_line_is_the_first_summary_line_and_lints_clean(tmp_path, oc):
    html_p, sum_p = fh.run_files({**DATA, "live": LIVE_UNK}, tmp_path / "o", NOW)
    page, summary = html_p.read_text(encoding="utf-8"), sum_p.read_text(encoding="utf-8")
    lines = summary.splitlines()
    assert lines[0] == "진행 팀 1개: chatbot. 상태 확인 불가 3개: feature, graphics, harness"  # r850 «진행 팀»
    assert lines[1:] == NEW["summary"]  # 모델 줄은 상태 줄 «뒤» 그대로
    assert lint.problems(page, summary) == []
    assert "0개" not in lines[0]  # 0개 칸은 생략


def test_r588_c2_summary_over_limit_is_an_error_not_a_silent_cut(tmp_path, oc):
    oc.write_text(json.dumps({**CONTENT, "summary": ["가" * 300, "나" * 300, "다"]}, ensure_ascii=False), encoding="utf-8")
    with pytest.raises(fr.NewsHtmlError, match="자르지 않는다"):
        fh.run_files({**DATA, "live": LIVE_UNK}, tmp_path / "big", NOW)
    assert not list((tmp_path / "big").glob("*.html"))  # 발행 0


# ⓓ 모델이 «모든 팀 정지» 를 지어내면 지금처럼 위반(발행 0)
def test_r588_d_model_all_stop_still_rejected(tmp_path, oc):
    oc.write_text(json.dumps({**CONTENT, "summary": ["모든 팀이 멈췄다", "하네스 설치 끝"]}, ensure_ascii=False), encoding="utf-8")
    html_p, sum_p = fh.run_files({**DATA, "live": LIVE_UNK}, tmp_path / "d", NOW)
    found = lint.problems(html_p.read_text(encoding="utf-8"), sum_p.read_text(encoding="utf-8"))
    assert any("일하는 팀 1개인데" in p for p in found)
    from ft_news_html import publish_files
    assert publish_files(html_p, sum_p, NOW)[0] == 3  # 발행 0


# ⓔ facts 의 팀 수 = 상태 줄의 수(일하는 6 = 줄의 6) 와 이름 그대로
def test_r588_e_status_line_counts_match_facts(tmp_path, oc):
    live = with_state([{"team": f"t{i}", "live": 1, "working": 1, "unknown": 0, "unknown_reason": ""} for i in range(6)]
                      + [{"team": "rest", "live": 1, "working": 0, "unknown": 0, "unknown_reason": ""}])
    sum_p = fh.run_files({**DATA, "live": live}, tmp_path / "e", NOW)[1]
    first = sum_p.read_text(encoding="utf-8").splitlines()[0]
    facts = fh.facts(live, "모름")  # r850: facts 칸 = 진행·대기·쉼·확인 불가
    assert first.startswith(f"진행 팀 {len(facts['진행'])}개: {', '.join(facts['진행'])}.") and "진행 팀 6개" in first
    assert first.endswith(f"쉬는 팀 {len(facts['쉼'])}개: {', '.join(facts['쉼'])}") and "확인 불가" not in first
