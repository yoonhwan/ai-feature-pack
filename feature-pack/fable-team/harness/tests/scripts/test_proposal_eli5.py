"""설계 §r2-4 3 — proposal_eli5: 결정 박스 = 원문 · 절 카드 수 = 절 수 · 차단 단어는 그 카드만 · 각주표 원문. 가짜 LLM 만, 네트워크 0.

실행: python3 -m pytest tests/scripts/test_proposal_eli5.py -q
"""
import html
import json
import shlex
import sys

import pytest
from _magazine_fakes import KIT  # noqa: F401 — sys.path 에 키트 경로를 넣는다

import magazine_eli5 as me
import magazine_eli5_batches as eb
import proposal_eli5 as pe
from magazine_eli5_batches import Eli5Error

KEY = "feature/ko-line-break"
MD = """# 제안서 — 한국어 줄바꿈 CSS
- 상태: 컨펌 대기

## 결론
word-break 한 줄이면 된다.

## 오빠가 결정할 것
<적용할까요> 승인 / 수정 / 폐기? (추천: 승인)

## 제안
- 한 줄 CSS

## 영향 범위
채팅 말풍선 한 곳. 다른 화면은 그대로.

## 되돌림
CSS 한 줄 revert.

## 검증
화면에서 줄이 단어 중간에서 안 끊긴다.

## 실험·예측 시뮬
실측 — 헤드리스 렌더 1회 · 결과 줄바꿈 정상 · design/feature/evidence/proposal-ko/render.png

## 각주표
| 번호 | 종류 | 제목 | 상태 |
| #887 | Issue | 줄바꿈 | 열림 |
"""
CARDS = ["결론", "제안", "영향 범위", "검증", "실험·예측 시뮬"]


FAKE_LLM = """import json, sys
cfg = json.loads(sys.argv[1])
prompt = sys.stdin.read()
units = json.loads(prompt.rsplit("<자료>", 1)[1].rsplit("</자료>", 1)[0])
refs = {u["path"] for u in units}
items = [{"ref": f"{cfg['key']}#{n}", "icon": "🪟", "analogy": "책상 위 작은 창 같아요",
          "lines": [cfg["lines"].get(n, "읽을 내용을 한눈에 찾아봐요")]}
         for n in cfg["names"] if f"{cfg['key']}#{n}" in refs]
print(json.dumps({"units": items}, ensure_ascii=False))
"""


def fake_llm(tmp_path, lines_by_name=None, names=CARDS):
    """cmd — stdin 프롬프트의 <자료> 에 든 ref 만(그 배치 몫) 한 항목씩 답한다. lines_by_name[이름] 으로 그 절의 풀이 문장을 바꾼다."""
    p = tmp_path / "fake_llm.py"
    p.write_text(FAKE_LLM, encoding="utf-8")
    cfg = json.dumps({"key": KEY, "names": list(names), "lines": lines_by_name or {}}, ensure_ascii=False)
    return f"{sys.executable} \"{p}\" {shlex.quote(cfg)}"


@pytest.fixture(autouse=True)
def skill(tmp_path, monkeypatch):
    p = tmp_path / "eli5" / "1.0.0" / "skills/eli5/SKILL.md"
    p.parent.mkdir(parents=True)
    p.write_text("---\nname: eli5\n---\n큰 그림과 적은 말 $ARGUMENTS", encoding="utf-8")
    monkeypatch.setattr(me, "SKILL_ROOT", tmp_path / "eli5")


def test_decision_box_is_source_text_not_ai(tmp_path):
    page = pe.build(MD, KEY, fake_llm(tmp_path))
    box = page.split('id="decisions"')[1].split('id="units"')[0]
    print(f"[결정 박스] {html.unescape(box)[box.index('<h3>결정 박스'):][:140]}")
    assert f"<p>{html.escape('<적용할까요> 승인 / 수정 / 폐기? (추천: 승인)')}</p>" in box
    assert f"<p>{html.escape('CSS 한 줄 revert.')}</p>" in box and "AI 풀이" not in box


def test_one_card_per_section_with_source_and_ai(tmp_path):
    page = pe.build(MD, KEY, fake_llm(tmp_path))
    assert page.count('class="unit-card"') == len(CARDS) == page.count('class="ai-explanation"')
    assert page.stats == {"success": 5, "total": 5, "omitted": 0, "reasons": {}}
    assert "AI 풀이 5/5 · 생략 0(없음)" in page and "<title>제안서 feature/ko-line-break — 쉬운 판</title>" in page
    no_exp = pe.build(MD.replace("## 실험·예측 시뮬\n", "## 근거\n"), KEY, fake_llm(tmp_path, names=CARDS[:4]))
    assert no_exp.count('class="unit-card"') == 4 and no_exp.stats["total"] == 4  # 실험 절은 «있을 때만» 카드


def test_every_card_is_explained_when_batches_are_smaller_than_the_page(tmp_path):
    assert eb.BATCH_SIZE < len(CARDS)  # 카드 5장이 배치 여러 개로 나뉘는 설정에서
    page = pe.build(MD, KEY, fake_llm(tmp_path))  # 가짜 LLM 은 배치에 든 ref 만 답한다
    assert page.count('class="ai-explanation"') == len(CARDS) and page.stats["omitted"] == 0


def test_blocked_word_hits_only_that_card(tmp_path):
    page = pe.build(MD, KEY, fake_llm(tmp_path, {"영향 범위": "전부 안전해요"}))
    assert page.count("AI 풀이 없음 — 차단 단어") == 1 and page.count('class="ai-explanation"') == 4
    assert "AI 풀이 4/5 · 생략 1(차단 단어 1건)" in page
    card = page.split('<h3>영향 범위</h3>')[1].split("</article>")[0]
    assert "AI 풀이 없음 — 차단 단어" in card and "채팅 말풍선 한 곳" in card
    print("[차단 단어 1건] 그 카드만 「AI 풀이 없음 — 차단 단어」 · 나머지 4장 풀이 유지")


def test_footnote_table_is_source_text(tmp_path):
    page = pe.build(MD, KEY, fake_llm(tmp_path))
    raw = page.split('<pre class="raw">')[1].split("</pre>")[0]
    assert html.unescape(raw) == "| 번호 | 종류 | 제목 | 상태 |\n| #887 | Issue | 줄바꿈 | 열림 |"


def test_zero_ai_is_eli5error_and_missing_fact_section_raises(tmp_path):
    with pytest.raises(Eli5Error, match="AI 풀이 0건"):
        pe.build(MD, KEY, fake_llm(tmp_path, {n: "완료예요" for n in CARDS}))
    with pytest.raises(ValueError, match="되돌림"):
        pe.build(MD.replace("## 되돌림\nCSS 한 줄 revert.\n", ""), KEY, fake_llm(tmp_path))
    with pytest.raises(ValueError, match="둘 이상"):
        pe.build(MD + "\n## 검증\n또\n", KEY, fake_llm(tmp_path))
