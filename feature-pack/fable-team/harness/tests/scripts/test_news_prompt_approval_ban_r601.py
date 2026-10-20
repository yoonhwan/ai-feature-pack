"""r601 — 뉴스 프롬프트 금지 문구(«사장님 승인을 기다린다» 1개)가 린트 APPROVAL_WAIT(«승인 … 기다|대기»)보다 좁아
자율 ON 인데 «승인 대기» 문장이 3회 발행 0(arch 113 · r594 실사건). 프롬프트 금지 범위를 린트와 같게 넓히고 쓸 수 있는 말을 준다. 린트 변경 0.
ⓐ (실패 시험 먼저) 자율 ON 금지 글에 «승인 대기»·«승인을 기다» 두 꼴이 없으면 FAIL
ⓑ 대안 꼴 «<무엇> 승인 단계 남음» 을 함께 준다
ⓒ 그 대안 문장 «1번 골은 착지 승인 단계 남음» 은 린트 판정 0(대안이 린트와 안 부딪힘) · «승인 대기다» 는 위반 그대로
ⓓ OFF·모름 경로 글은 base 와 바이트 같음(바뀐 곳 = ON 문장 하나 · FACT_RULES 앞 2줄·«모름» 꼬리 불변)
실행: python3 -m pytest tests/scripts/test_news_prompt_approval_ban_r601.py -q
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BIN = ROOT / "harness" / "bin"
sys.path[:0] = [str(BIN)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(ROOT / "harness" / "kit" / "slack-mirror"))

import ft_news_html_lint as lint  # noqa: E402
import ft_news_html_render as fr  # noqa: E402
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

BASE_HEAD = ('- 입력 facts = 코드가 tmux 좌석·jsonl 로 잰 «사실» — 원장 문장과 어긋나면 facts 가 이긴다. «일하는 팀» 이 1개 이상이면 '
             '«모든 팀이 멈춤·대기·쉼» 같은 문장 금지 · 일하는/쉬는 팀 수·이름은 facts 그대로.\n'
             '- facts.확인 불가 팀은 쉬는 팀이 아니다 — 그 팀이 쉰다·멈췄다·대기 중이라고 상태를 단정하지 말 것(쓰려면 «상태 확인 불가»).\n')
BASE_AUTO = ('- facts.자율 이 "ON" 이면 병합 승인은 desk 가 실행한다 — «사장님 승인을 기다린다» 금지 · '
             '"모름" 이면 승인·자율 이야기를 쓰지 않는다.')
MOKRUM_TAIL = '"모름" 이면 승인·자율 이야기를 쓰지 않는다.'
ALT = "1번 골은 착지 승인 단계 남음"
BAD = "1번 골 마감 승인 대기다."
FOOT_ON = ('<p class="foot">근거: 원장 · 카드 · 자율 ON · 정리 x</p>'
           '<section class="prio"><li>%s</li></section>')
DATA = {"goals": [{"n": i, "goal": f"골 {i}", "state": "지금"} for i in range(1, 7)],
        "live": [{"team": "harness", "live": 1, "working": 1, "unknown": 0}]}


def rules_head(part: str) -> str:
    return fr.build_prompt(DATA, part).split("출력 스키마:")[0]


def test_r601_a_prompt_bans_both_forms_for_summary_and_important():
    """ⓐ 자율 ON 금지 글에 «승인 대기» 와 «승인을 기다» 두 꼴이 적혀 있지 않으면 FAIL(지금 판 = «사장님 승인을 기다린다» 1개)."""
    for part in ("summary", "important"):
        head = rules_head(part)
        assert "«승인 대기»" in head, f"{part}: «승인 대기» 꼴 금지 없음"
        assert "«승인을 기다»" in head, f"{part}: «승인을 기다» 꼴 금지 없음"
        assert "«사장님 승인을 기다린다» 금지" not in head, f"{part}: 옛 1개짜리 금지 문장 그대로"


def test_r601_b_prompt_gives_usable_alternative():
    """ⓑ 금지 문장 대신 «<무엇> 승인 단계 남음» 으로 쓰라는 대안 꼴을 함께 준다."""
    for part in ("summary", "important"):
        assert "승인 단계 남음" in rules_head(part), f"{part}: 대안 꼴 없음"


def test_r601_c_alternative_passes_lint_and_bad_form_still_flagged():
    """ⓒ 대안 «… 승인 단계 남음» = 린트 판정 0 · «승인 대기다» = 위반 그대로(린트 변경 0 확인)."""
    assert lint.fact_problems(FOOT_ON % ALT, ALT, FOOT_ON % ALT) == []
    assert not lint.APPROVAL_WAIT.search(ALT)
    assert lint.APPROVAL_WAIT.search(BAD)
    bad = lint.fact_problems(FOOT_ON % BAD, BAD, FOOT_ON % BAD)
    assert len(bad) == 1 and "자율 ON 인데 승인 대기 문장" in bad[0]


def test_r601_d_off_and_unknown_path_bytes_unchanged():
    """ⓓ 바뀐 곳 = ON 문장 하나 · FACT_RULES 앞 2줄·«모름» 꼬리는 base 와 바이트 같음(OFF·모름 회귀 0)."""
    assert fr.FACT_RULES.startswith(BASE_HEAD)
    assert fr.FACT_RULES.endswith(MOKRUM_TAIL)
    assert BASE_AUTO not in fr.FACT_RULES
    assert fr.FACT_RULES[len(BASE_HEAD):].count("\n") == 0
