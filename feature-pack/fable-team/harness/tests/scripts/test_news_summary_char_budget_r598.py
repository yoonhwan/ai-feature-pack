"""r598 — 뉴스 요약 상한을 «바이트» 대신 «글자 수 + 여유 20%» 로 준다(모델은 한글 3B 를 세지 못한다 · r596 설치 뒤 605B 발행 0).
프롬프트 숫자 = floor(모델 몫 바이트 × 0.8 ÷ 3) · 한글만 꽉 채워도 600B 이내(산술 보장) · 넘치면 지금처럼 ERROR(자르기 0)+그 숫자를 문구에 남긴다.
ⓐ 지금 판(«N바이트») = FAIL — 고친 판 = «N글자(띄어쓰기 포함)» 이고 N = floor(모델 몫 × 0.8 ÷ 3)
ⓑ 그 글자 수를 꽉 채운 한글(3B/자) + 상태 줄 → 600B 이하
ⓒ 그 글자 수를 꽉 채운 ASCII 섞인 글 → 600B 이하
ⓓ 그래도 넘기면 ERROR(발행 0 · 자르기 0) · 문구에 «모델 몫 N글자 = MB»
ⓔ 글자 수가 0 이하 = 같은 ERROR(모델 호출 전)
실행: python3 -m pytest tests/scripts/test_news_summary_char_budget_r598.py -q
"""
import math
import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
sys.path[:0] = [str(BIN)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(ROOT / "harness" / "kit" / "slack-mirror"))

import ft_news_html_render as fr  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

TEAMS = ["chatbot", "graphics", "harness", "ops", "room", "v65", "kk", "lecture", "loom", "issues", "planner", "feature", "daily-trend"]
from _news_live import with_state  # noqa: E402  r850: live 팀 상태(state·label) = ft_team_state.judge 값

LIVE13 = with_state([{"team": t, "live": 2, "working": 1 if i % 2 == 0 else 0, "unknown": 0} for i, t in enumerate(TEAMS)])
DATA13 = {"goals": [{"n": i, "goal": f"골 글 {i}", "team": f"t{i}", "state": "지금"} for i in range(1, 7)], "live": LIVE13}
STATUS13 = fr.status_line(fr.bucket({}, LIVE13))


def model_bytes(status: str) -> int:
    return fr.SUMMARY_BYTES - len(status.encode("utf-8")) - (fr.SUMMARY_LINES - 1)


def want_chars(status: str) -> int:
    return math.floor(model_bytes(status) * 0.8 / 3)


def prompt_number(prompt: str) -> tuple[int, str]:
    """summary 프롬프트의 «합쳐 N<단위>» — (N, 단위)."""
    head = prompt.split("출력 스키마:")[0]
    mark = "합쳐 "
    i = head.index(mark) + len(mark)
    j = i
    while j < len(head) and head[j].isdigit():
        j += 1
    return int(head[i:j]), head[j:j + 8]


def test_r598_a_prompt_gives_chars_with_margin_not_bytes():
    """ⓐ 지금 판 = «455바이트» → FAIL · 고친 판 = «N글자(띄어쓰기 포함)» 이고 N = floor(모델 몫 × 0.8 ÷ 3)."""
    n, unit = prompt_number(fr.build_prompt(DATA13, "summary"))
    assert unit.startswith("글자(띄어"), f"단위가 글자가 아니다: {unit!r}"
    assert n == want_chars(STATUS13)
    assert "바이트" not in fr.build_prompt(DATA13, "summary").split("출력 스키마:")[0].split("합쳐 ")[1][:40]


def test_r598_b_korean_fill_keeps_total_under_600():
    """ⓑ 글자 수를 꽉 채운 한글(3B/자) + 상태 줄 → 600B 이하(산술 보장 · 자르기 0)."""
    chars = want_chars(STATUS13)
    body = "가" * chars
    c = {**fr.bucket({}, LIVE13), "summary": [body[:chars // 2], body[chars // 2:]]}
    out = fr.add_status_line(c)
    text = "\n".join(out["summary"])
    assert len(text.encode("utf-8")) <= fr.SUMMARY_BYTES
    assert len(out["summary"]) == fr.SUMMARY_LINES


def test_r598_c_ascii_fill_keeps_total_under_600():
    """ⓒ 글자 수를 꽉 채운 ASCII 섞인 글 → 600B 이하."""
    chars = want_chars(STATUS13)
    body = ("ab 12" * (chars // 6 + 1))[:chars]
    c = {**fr.bucket({}, LIVE13), "summary": [body[:chars // 2], body[chars // 2:]]}
    out = fr.add_status_line(c)
    assert len("\n".join(out["summary"]).encode("utf-8")) <= fr.SUMMARY_BYTES


def test_r598_d_overflow_is_error_naming_chars_and_bytes():
    """ⓓ 그래도 넘기면 ERROR(발행 0 · 자르기 0) · 문구에 «모델 몫 N글자 = MB»."""
    chars = want_chars(STATUS13)
    c = {**fr.bucket({}, LIVE13), "summary": ["가" * 200, "나" * 200]}
    with pytest.raises(fr.NewsHtmlError) as e:
        fr.add_status_line(c)
    msg = str(e.value)
    assert "이내여야 한다" in msg and "자르지 않는다" in msg
    assert f"모델 몫 {chars}글자 = {model_bytes(STATUS13)}B" in msg
    assert "가" * 200 in c["summary"] and c["summary"][-1] == "나" * 200  # 자르기 0(모델 줄 그대로)


def test_r598_e_zero_chars_raises_before_model_call():
    """ⓔ 상태 줄이 길어 모델 몫 글자 수가 0 이하 = 모델 호출 전 ERROR(«글자» 를 말한다)."""
    live = with_state([{"team": "t" * 580, "live": 1, "working": 1, "unknown": 0}])
    assert want_chars(fr.status_line(fr.bucket({}, live))) <= 0
    with pytest.raises(fr.NewsHtmlError) as e:
        fr.build_prompt({"live": live}, "summary")
    assert "글자" in str(e.value)
