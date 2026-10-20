"""r596 — 뉴스 요약 바이트 예산: 모델 몫 = 600 − 이번 틱 «팀 상태 줄» 바이트 − 줄바꿈(2).
ⓐ 팀 13개(이름 실제 꼴) 프롬프트 숫자 + 상태 줄 + 줄바꿈 > 600 이면 FAIL(고치기 전 = 500 고정이라 FAIL)
ⓑ 팀 0개(상태 줄 «팀 상태 원천 없음») → 숫자 = 600 − 그 줄 바이트 − 2
ⓒ 모델이 받은 숫자를 넘겨 쓰면 ERROR(발행 0 · 자르기 0) — 판정 불변
ⓓ 모델이 받은 숫자 안으로 쓰면 통과
실행: python3 -m pytest tests/scripts/test_news_summary_byte_budget_r596.py -q
"""
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
LIVE13 = [{"team": t, "live": 2, "working": 1 if i % 2 == 0 else 0, "unknown": 0} for i, t in enumerate(TEAMS)]
DATA13 = {"goals": [{"n": i, "goal": f"골 글 {i}", "team": f"t{i}", "state": "지금"} for i in range(1, 7)], "live": LIVE13}


def status_bytes(data: dict) -> int:
    return len(fr.status_line(fr.bucket({}, data["live"])).encode("utf-8"))


def prompt_number(prompt: str) -> int:
    head = prompt.split("출력 스키마:")[0]
    mark = "합쳐 "
    i = head.index(mark) + len(mark)
    return int(head[i:head.index("바이트", i)])


def test_r596_a_summary_budget_subtracts_this_ticks_status_line():
    """ⓐ 팀 13개 — 모델 몫 + 상태 줄 + 줄바꿈 2 = 600 이내(고치기 전 = 500 고정이라 600 초과)."""
    line = fr.status_line(fr.bucket({}, LIVE13))
    assert 500 + status_bytes(DATA13) + 2 > fr.SUMMARY_BYTES, "이 픽스처가 600 초과를 재현하지 못한다"
    prompt = fr.build_prompt(DATA13, "summary")
    got = prompt_number(prompt)
    assert got == fr.SUMMARY_BYTES - status_bytes(DATA13) - 2
    assert got + len(line.encode("utf-8")) + 2 <= fr.SUMMARY_BYTES


def test_r596_b_no_teams_budget_is_upper_bound_minus_status_only():
    """ⓑ 팀 0개 — 상태 줄 «팀 상태 원천 없음» 바이트만 뺀다."""
    assert fr.status_line({"working": [], "resting": [], "unknown": []}) == "팀 상태 원천 없음"
    line = fr.status_line({"working": [], "resting": [], "unknown": []})
    assert fr.summary_budget(line) == fr.SUMMARY_BYTES - len(line.encode("utf-8")) - 2


def test_r596_c_model_over_budget_is_error_publish_zero():
    """ⓒ 받은 숫자를 넘긴 답 = ERROR(자르지 않는다 · 판정 불변)."""
    live = [{"team": "kk", "live": 1, "working": 0, "unknown": 0}]
    budget = fr.summary_budget(fr.status_line(fr.bucket({}, live)))
    c = {**fr.bucket({}, live), "summary": ["a" * budget, "b"]}  # 두 줄 = 예산 초과(줄바꿈 1 추가)
    with pytest.raises(fr.NewsHtmlError) as e:
        fr.add_status_line(c)
    assert "이내여야 한다" in str(e.value) and fr.status_line(fr.bucket({}, live)) in c["summary"][0]


def test_r596_d_model_within_budget_passes():
    """ⓓ 받은 숫자 안 = 통과(상태 줄 + 모델 2줄 그대로)."""
    live = [{"team": "kk", "live": 1, "working": 0, "unknown": 0}]
    budget = fr.summary_budget(fr.status_line(fr.bucket({}, live)))
    c = {**fr.bucket({}, live), "summary": ["a" * (budget - 3), "b"]}  # 두 줄 = 줄바꿈 1 · 합 ≤ 예산
    out = fr.add_status_line(c)
    assert len(out["summary"]) == 3 and out["summary"][0] == fr.status_line(fr.bucket({}, live))
