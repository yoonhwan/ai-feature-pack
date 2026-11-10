"""r590 — 뉴스 요약 줄 수 지시가 한 프롬프트 안에서 어긋남(견본 «3줄 이하» ↔ 규칙 «1~2줄») → 둘 다 상한 상수(SUMMARY_LINES - 1)에서 만든다.
가짜 opencode(FT_OPENCODE · 답 글 파일) · 실 모델·실 슬랙·실 좌석 0.
실행: python3 -m pytest tests/scripts/test_news_summary_schema_lines.py -q
"""
import importlib.util
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ft_news_html import CONTENT, DATA, FAKE_OC, NOW  # noqa: E402

import ft_news_html as fh  # noqa: E402
import ft_news_html_lint as lint  # noqa: E402
import ft_news_html_render as fr  # noqa: E402

KIT = Path(__file__).resolve().parents[2] / "kit" / "fable-team" / "bin" / "ft_news_html_render.py"


def summary_prompt() -> str:
    return fr.build_prompt(DATA, "summary")


def rule_line(prompt: str) -> str:
    return next(x for x in prompt.splitlines() if x.startswith('- "summary" = '))


def schema_line(prompt: str) -> str:
    return prompt.split("출력 스키마:")[1].splitlines()[0]


@pytest.fixture
def oc(tmp_path, monkeypatch):
    """가짜 opencode — 답 글 파일 · 인자 기록 파일."""
    exe, reply, log = tmp_path / "opencode", tmp_path / "reply.txt", tmp_path / "oc.log"
    exe.write_text(FAKE_OC, encoding="utf-8")
    exe.chmod(0o755)
    reply.write_text("```json\n" + json.dumps(CONTENT, ensure_ascii=False) + "\n```", encoding="utf-8")
    for k, v in {"FT_OPENCODE": str(exe), "FAKE_OC_REPLY": str(reply), "FAKE_OC_LOG": str(log),
                 "FT_NEWS_VIA": "opencode", "FT_NEWS_STARTUP_LOG": str(tmp_path / "startup.tsv")}.items():
        monkeypatch.setenv(k, v)
    for k in ("FT_NEWS_EFFORT", "FT_NEWS_MODEL", "FT_NEWS_DEPTH", "FT_NEWS_FIXED_S"):
        monkeypatch.delenv(k, raising=False)
    return reply


# ⓐ 한 프롬프트 안 줄 수 지시가 한 값 — 견본·규칙 줄 둘 다 SUMMARY_LINES - 1 (지금 판 = «3줄 이하» 와 «1~2줄» 공존 FAIL)
def test_r590_a_summary_prompt_speaks_one_line_number():
    model_lines = fr.SUMMARY_LINES - 1
    prompt = summary_prompt()
    assert f"{model_lines}줄 이하" in schema_line(prompt)
    assert f"1~{model_lines}줄" in rule_line(prompt)
    assert len({n for n in (1, 2, 3, 4, 5) if f"{n}줄" in rule_line(prompt) + schema_line(prompt)}) == 1
    assert "3줄 이하" not in prompt or model_lines == 3


# ⓑ 숫자 출처 = 상수 한 곳 — 상한을 4로 바꾼 사본은 견본·규칙 줄이 «3» 으로 따라간다(하드코딩 0)
def test_r590_b_both_numbers_follow_the_constant(tmp_path):
    src = KIT.read_text(encoding="utf-8")
    line = "SUMMARY_LINES, SUMMARY_BYTES = 3, 600"
    assert line in src
    copy = tmp_path / "ft_news_html_render.py"
    copy.write_text(src.replace(line, "SUMMARY_LINES, SUMMARY_BYTES = 4, 900", 1), encoding="utf-8")
    spec = importlib.util.spec_from_file_location("ft_news_html_render_r590_probe", copy)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    prompt = mod.build_prompt(DATA, "summary")
    assert f"{mod.SUMMARY_LINES - 1}줄 이하" in schema_line(prompt) and "2줄 이하" not in schema_line(prompt)
    assert f"1~{mod.SUMMARY_LINES - 1}줄" in rule_line(prompt)


# ⓒ 모델이 그래도 3줄을 내면 상태 줄까지 4줄 = 지금처럼 ERROR(발행 0 · 자르기 0)
def test_r590_c_model_three_lines_is_an_error_not_a_cut(tmp_path, oc):
    oc.write_text(json.dumps({**CONTENT, "summary": ["가", "나", "다"]}, ensure_ascii=False), encoding="utf-8")
    with pytest.raises(fr.NewsHtmlError, match="자르지 않는다"):
        fh.run_files(DATA, tmp_path / "c", NOW)
    assert not list((tmp_path / "c").glob("*.html"))


# ⓓ 모델 2줄 + 상태 줄 = 3줄 = 통과(린트 0 · 상태 줄이 첫 줄)
def test_r590_d_model_two_lines_plus_status_line_publishes(tmp_path, oc):
    html_p, sum_p = fh.run_files(DATA, tmp_path / "d", NOW)
    lines = sum_p.read_text(encoding="utf-8").splitlines()
    assert len(lines) == fr.SUMMARY_LINES and lines[0].startswith("진행 팀")  # r850 «진행 팀»
    assert lint.problems(html_p.read_text(encoding="utf-8"), "\n".join(lines)) == []
