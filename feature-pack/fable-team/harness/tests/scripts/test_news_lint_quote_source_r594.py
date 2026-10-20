"""r594 — 린트 위반 문구에 «문장 전문 + 갈래(summary N / important N)» 를 남긴다 (지어냄 판정용 원문).
시험 입력 = HTML 문자열만(기존 린트 시험 꼴) · 실 모델·슬랙·좌석·press 0.
실행: python3 -m pytest tests/scripts/test_news_lint_quote_source_r594.py -q
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(ROOT / "harness" / "bin"), str(KIT)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(KIT))

import ft_news_html_lint as lint  # noqa: E402

APPROVAL = "사장님 승인을 기다리는 중"


def _html(important: list[str], auto: str = "ON", working: int = 2) -> str:
    lis = "\n".join(f'      <li><div class="what"><strong>일 {i}</strong><span>{d}</span></div>'
                    f'<span class="who">t</span></li>' for i, d in enumerate(important, 1))
    work = '  <section class="goal work">\n    <p class="say">팀</p>\n  </section>\n' * working
    goals = '  <section class="goal">\n    골\n  </section>\n' * lint.GOALS
    h2 = "".join(f"<h2>{h}</h2>" for h in lint.H2)
    return (f"<h1>{lint.H1}</h1>{h2}<section class=\"prio\">\n    <ol>\n{lis}\n    </ol>\n  </section>\n"
            f"{goals}{work}<p class=\"foot\">근거: 원장 · 자율 {auto}</p>")


def test_r594_a_important_item_keeps_full_sentence_and_branch_number():
    """ⓐ 중요한 일 3번째 detail 의 승인 대기 — 옛 판 = 조각만 · 고친 판 = [important 3] + 문장 전문."""
    page, summary = _html(["가", "나", APPROVAL]), "가\n나"
    bad = lint.problems(page, summary)
    assert len(bad) == 1, bad
    assert "[important 3]" in bad[0] and APPROVAL in bad[0] and "자율 ON 인데" in bad[0]


def test_r594_b_summary_line_keeps_full_sentence_and_line_number():
    """ⓑ 요약 2번째 줄 — [summary 2] + 그 줄 전문."""
    page, summary = _html(["가", "나"]), "가\n" + APPROVAL
    bad = lint.problems(page, summary)
    assert len(bad) == 1 and "[summary 2]" in bad[0] and APPROVAL in bad[0]
    assert len(lint.problems(page, "가\n나\n다")) == 0


def test_r594_c_autonomy_off_is_still_no_violation():
    """ⓒ 자율 OFF → 승인 대기 문장은 사실 (위반 0 불변)."""
    assert lint.problems(_html(["가", "나", APPROVAL], auto="OFF"), "가\n나") == []


def test_r594_d_all_stop_quote_has_branch_and_verdict_is_unchanged(tmp_path):
    """ⓓ ALL_STOP 도 같은 꼴 · 위반 1건 = rc3 발행 0 (판정 불변)."""
    page = _html(["가", "나"], working=2)
    bad = lint.problems(page, "가\n모든 팀은 작업을 멈추고 대기 중입니다")
    assert len(bad) == 1 and "[summary 2]" in bad[0] and "모든 팀은 작업을 멈추고 대기 중입니다" in bad[0]
    (tmp_path / "x.html").write_text(page, encoding="utf-8")
    (tmp_path / "x.txt").write_text("가\n모든 팀은 작업을 멈추고 대기 중입니다", encoding="utf-8")
    assert lint.main([str(tmp_path / "x.html"), str(tmp_path / "x.txt")]) == 3
