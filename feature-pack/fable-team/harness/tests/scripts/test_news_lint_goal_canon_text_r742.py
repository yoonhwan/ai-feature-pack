"""r742 — 골 카드 «원문 문단»(<p class="say">)은 번호 검사에서 뺀다 (오빠 승인 정본 글 · 모델 글 아님).
실측 사고: 골 정본 행 이름에 «샵 2598~2601» 이 들어 있어 매 틱 «각주 밖 번호 1건» → 발행 0.
시험 입력 = HTML 문자열 + 임시 파일만(실 게시·좌석·press 0).
실행: python3 -m pytest tests/scripts/test_news_lint_goal_canon_text_r742.py -q
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
KIT = ROOT / "harness" / "kit" / "slack-mirror"
sys.path[:0] = [str(ROOT / "harness" / "bin"), str(KIT)]
os.environ.setdefault("FT_HERMES_SCRIPTS", str(KIT))

import ft_news_html_lint as lint  # noqa: E402

GOAL_N = 6  # 시험 견본의 골 수(린트는 상수 6 을 안 쓴다 · h2_titles(GOAL_N) 과 짝)
CANON = "내부 하네스 MR 수정 #2598~2601 승인 반영"  # 골 정본 행 원문 꼴(고칠 수 없는 글)


def _goal_card(n: int, say: str, gnum: str = "", track: str = "가") -> str:
    """렌더러 _goal_card 와 같은 꼴(ft_news_html_render.py:518–523) — gnum·say·track 세 글 자리."""
    return (f'  <section class="goal">\n    <div class="body">\n      <span class="gnum">{gnum or f"골 {n} · 하네스"}</span>\n'
            f'      <p class="say">{say}</p>\n      <div class="track">\n        <div class="step s-done"><b>끝남</b>{track}</div>\n'
            f'      </div>\n    </div>\n  </section>')


def _html(important: list[str] = ("가", "나"), auto: str = "ON", working: int = 1,
          gnum: str = "", track: str = "가", say: str = "골 원문") -> str:
    lis = "\n".join(f'      <li><div class="what"><strong>일 {i}</strong><span>{d}</span></div>'
                    f'<span class="who">t</span></li>' for i, d in enumerate(important, 1))
    work = '  <section class="goal work">\n    <div class="body">\n      <p class="say">팀</p>\n    </div>\n  </section>\n' * working
    goals = "\n".join(_goal_card(n, say if n == 1 else "골 원문", gnum if n == 1 else "", track if n == 1 else "가")
                      for n in range(1, GOAL_N + 1))
    h2 = "".join(f"<h2>{h}</h2>" for h in lint.h2_titles(GOAL_N))
    return (f"<h1>{lint.H1}</h1>{h2}<section class=\"prio\">\n    <ol>\n{lis}\n    </ol>\n  </section>\n"
            f"{goals}{work}<p class=\"foot\">근거: 원장 · 자율 {auto}</p>")


def test_r742_a_goal_canon_say_number_is_not_a_violation():
    """ⓐ 골 카드 원문 문단의 «샵 번호» — 옛 판 = «각주 밖 번호 1건» 발행 0 · 고친 판 = 위반 0."""
    page = _html(say=CANON)
    assert lint.problems(page, "가\n나") == []
    assert lint.problem_records(page, "가\n나") == []


def test_r742_b_mutation_dropping_the_exclusion_brings_the_violation_back():
    """ⓕ 변이: 제외 구역(GOAL_SAY)을 죽이면 ⓐ 가 다시 위반 — 시험이 «고침»을 잡는다(빨강 확인)."""
    page = _html(say=CANON)
    saved = lint.GOAL_SAY
    try:
        lint.GOAL_SAY = re.compile(r"(?!)")  # 아무것도 안 지우는 정규식
        bad = lint.problems(page, "가\n나")
    finally:
        lint.GOAL_SAY = saved
    assert len(bad) == 1 and "각주 밖 번호 1건" in bad[0]


def test_r742_c_numbers_outside_the_goal_say_still_violate():
    """ⓒ 회귀 0 — 골 카드 밖(중요한 일·일하는 팀 카드)과 같은 카드의 gnum·track 번호는 지금처럼 위반."""
    cases = {
        "important": _html(important=("가", "판정 12 확정")),
        "gnum": _html(gnum="골 1 · harness #4242"),
        "track": _html(track="끝남 #7788"),
        "work": _html(working=1).replace('<p class="say">팀</p>', '<p class="say">팀 #9999</p>', 1),
    }
    for name, page in cases.items():
        bad = lint.problems(page, "가\n나")
        assert len(bad) == 1 and "각주 밖 번호 1건" in bad[0], (name, bad)


def test_r742_d_foot_numbers_still_pass():
    """ⓓ 각주 안 번호 = 지금처럼 통과(골 원문 문단과 함께 있어도 위반 0)."""
    page = _html(say=CANON).replace("자율 ON", "자율 ON · 근거 #1234 판정 7", 1)
    assert lint.problems(page, "가\n나") == []


def test_r742_e_cli_isolated_temp_files_rc0(tmp_path):
    """ⓖ 격리 = 임시 HTML·요약 파일만(실 게시 0) — ⓐ 페이지는 rc0, ⓕ 변이 판은 rc3."""
    (tmp_path / "x.html").write_text(_html(say=CANON), encoding="utf-8")
    (tmp_path / "x.txt").write_text("가\n나", encoding="utf-8")
    assert lint.main([str(tmp_path / "x.html"), str(tmp_path / "x.txt")]) == 0
    (tmp_path / "y.html").write_text(_html(important=("가", "판정 12 확정")), encoding="utf-8")
    assert lint.main([str(tmp_path / "y.html"), str(tmp_path / "x.txt")]) == 3
