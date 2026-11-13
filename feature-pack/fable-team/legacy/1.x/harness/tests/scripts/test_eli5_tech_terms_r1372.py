"""r1372 — 상태판·쉬운 말 lint·뉴스 프롬프트가 기술 용어(PR·sha·branch·worktree…)를 한글로 바꾸거나 풀이를 요구하지 않는다.

팀 내부어(나노·오케…)는 지금 규칙 그대로 · 번호·sha 값 기준 ③ 회귀 0 · 외부 호출 0 · 실 상태판 발행 0.
변이 시험: R1372_BIN=<bin 사본 폴더> 로 사본을 가리킨다(작업 트리 원본은 건드리지 않는다).
실행: python3 -m pytest tests/scripts/test_eli5_tech_terms_r1372.py -q
"""
import importlib.util
import os
import sys
from pathlib import Path

import pytest

BIN = Path(os.environ.get("R1372_BIN") or Path(__file__).resolve().parents[2] / "bin")
TECH_KO = ("합치기 요청", "작업 가지", "버전 번호", "작업 폴더", "임시 저장", "실시간 전송", "조각", "목차 다시 만들기")


def _load(name: str, file: str):
    sys.path.insert(0, str(BIN))
    try:
        spec = importlib.util.spec_from_file_location(name, BIN / file)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        sys.path.remove(str(BIN))


@pytest.fixture(scope="module")
def cards():
    return _load("r1372_cards", "ft_board_sheet_cards.py")


@pytest.fixture(scope="module")
def lint():
    return _load("r1372_lint", "ft-eli5-lint.py")


@pytest.fixture(scope="module")
def terms(cards):
    return cards.table("eli5_terms.json")


def test_c1_board_keeps_tech_terms(cards):
    out = cards.plain("PR 7262 착지 · branch park · 브랜치 정리 · sha 확인 · 워크트리 · 캐시 · SSE · 청크 · 재색인")
    for word in ("PR", "branch", "브랜치", "sha", "워크트리", "캐시", "SSE", "청크", "재색인"):
        assert word in out, out
    for ko in TECH_KO:
        assert ko not in out, out


def test_c2_lint_no_gloss_for_tech_terms(lint, terms):
    summary = "sha 를 맞췄어요\n워크트리 하나에서 일해요\n인덱스 를 다시 만들었어요\nPR 을 열었어요\n"
    no_gloss = [b.rsplit(": ", 1)[1] for b in lint.c2(summary, terms) if "풀이 없음" in b]
    first_hit = [b.split(": ", 1)[1].split() for b in lint.c1(summary, terms) if b.startswith("첫 화면에 전문어")]
    flagged = set(no_gloss) | {w for ws in first_hit for w in ws}
    assert not flagged & {"sha", "워크트리", "인덱스", "PR", "브랜치", "캐시", "SSE", "청크", "재색인"}, flagged


def test_c3_lint_keeps_team_terms(lint, terms):
    bad = lint.c2("나노 가 일해요\n오케 가 정해요\n", terms)
    assert "전문어 첫 등장에 풀이 없음: 나노" in bad
    assert "전문어 첫 등장에 풀이 없음: 오케" in bad


def test_c4_news_prompt_keeps_tech_terms():
    prompt = _load("r1372_news", "ft_news_html_render.py").PROMPT
    assert "기술 용어(PR·sha·branch·table 등)는 영문 그대로" in prompt
    assert "내부어·약어·파일 경로 0" not in prompt


def test_c5_number_rule_unchanged(lint):
    assert lint.c3("수정 " + "a" * 40 + " 완료\n", "", False)
    assert lint.c3("카드 #1372 착지\n", "", False)
    assert not lint.c3("PR 착지 · sha 확인\n", "", False)
