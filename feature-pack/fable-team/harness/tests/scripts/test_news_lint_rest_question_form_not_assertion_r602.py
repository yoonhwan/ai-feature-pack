"""r602 — «쉬는지 일하는지 확인 불가다»(물음꼴 · 모른다는 말)를 «확인 불가 팀에 쉼 단정» 으로 거절하던 오탐.
쉼 글자 바로 뒤 같은 절 앞 6자 안에 물음꼴 어미(는지·ㄴ지·은지·던지·었는지·았는지·했는지·인지)가 오면 단정 아님 · 단정(«쉬고 있다»·«대기 중이다»·«멈췄다»)은 그대로 거절.
시험 입력 = HTML 문자열 + 요약 문자열만(기존 린트 시험 꼴) · 실 모델·슬랙·좌석·press 0.
실행: python3 -m pytest tests/scripts/test_news_lint_rest_question_form_not_assertion_r602.py -q
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(ROOT / "harness" / "bin"), str(KIT)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(KIT))

import ft_news_html_lint as lint  # noqa: E402


def _html(unknown: list[str], working: int = 2) -> str:
    """확인 불가 블록(team unk) + 일하는 팀 카드 + 절 6 뼈대 — 다른 규칙에 안 걸리는 최소 HTML."""
    lis = "\n".join(f'      <li><div class="what"><strong>일 {i}</strong><span>가</span></div>'
                    f'<span class="who">t</span></li>' for i in (1, 2))
    work = '  <section class="goal work">\n    <p class="say">팀</p>\n  </section>\n' * working
    goals = '  <section class="goal">\n    골\n  </section>\n' * lint.GOALS
    unk = "".join(f'<div class="team unk"><strong>{t}</strong></div>' for t in unknown)
    h2 = "".join(f"<h2>{h}</h2>" for h in lint.H2)
    return (f"<h1>{lint.H1}</h1>{h2}<section class=\"prio\">\n    <ol>\n{lis}\n    </ol>\n  </section>\n"
            f"{goals}{work}{unk}<p class=\"foot\">근거: 원장 · 자율 ON</p>")


def test_r602_a_question_form_saying_unknown_is_not_a_rest_assertion():
    """ⓐ(실패 시험 먼저) «feature·graphics는 좌석 상태를 잴 수 없어 쉬는지 일하는지 확인 불가다» — 옛 판 위반 1 · 고친 판 0."""
    said = "feature·graphics는 좌석 상태를 잴 수 없어 쉬는지 일하는지 확인 불가다"
    assert len(lint.problems(_html(["feature", "graphics"]), said)) == 0


def test_r602_b_other_question_forms_are_not_assertions():
    """ⓑ «멈췄는지 모른다» · «대기 중인지 알 수 없다» — 위반 0."""
    page = _html(["feature"])
    for said in ("feature 는 멈췄는지 모른다", "feature 가 대기 중인지 알 수 없다",
                 "feature 가 쉬었는지 알 수 없다", "feature 가 정지했는지 확인 불가다"):
        assert lint.problems(page, said) == [], said


def test_r602_c_plain_assertions_are_still_rejected():
    """ⓒ «쉬고 있다» · «대기 중이다» · «멈췄다» — 위반 1씩(옛 판과 같다)."""
    page = _html(["feature"])
    for said in ("feature 는 쉬고 있다", "feature 는 대기 중이다", "feature 는 멈췄다"):
        bad = lint.problems(page, said)
        assert len(bad) == 1 and bad[0].startswith("확인 불가 팀 feature"), (said, bad)


def test_r602_d_existing_negation_and_clause_rules_unchanged():
    """ⓓ r498 부정 꼬리 · r588 절 단위 회귀 0 — 다른 규칙은 그대로."""
    page = _html(["feature", "graphics"])
    assert lint.problems(page, "feature 는 쉰다거나 멈췄다고 단정하지 않습니다") == []      # r498
    assert lint.problems(page, "지금은 세 팀이 일하며, feature 는 상태 확인 불가다") == []   # r588
    bad = lint.problems(page, "feature 는 쉬고 있다")
    assert bad == ["확인 불가 팀 feature 에 쉼 단정 «feature 는 쉬고 있다»"]
