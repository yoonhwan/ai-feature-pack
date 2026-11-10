"""쉬운 판 시험 공용 — 모델 픽스처 · 요청 종류별 가짜 LLM (네트워크 0)."""
import copy
import json
import re

import pytest
from _magazine_fakes import fake_model

import magazine_eli5 as me

UNIT = {"team": "harness", "path": "design/harness/indices/완성/창.md", "title": "아침 매거진의 요약 창",
        "why": "읽을 내용을 한눈에 보여줘요. 자세한 내용은 원문에 있어요.", "coord": "C", "evidence": ["시험 통과"],
        "da": "DA.md#§1", "moved_sha": "a" * 40, "ref": "ops/main-base"}
DETAIL = {"refs": [], "units": [UNIT], "malformed": [], "verdict_sections": [], "decisions": [], "merge_bodies": {}, "issue_evidence": {},
          "open": {"cards": [], "requests": [], "malformed_requests": [], "holds": [], "breaches": []}, "seats_closed": [], "appendix": []}
NOTES = {883: ("PR", "요약 창", "병합됨"), 885: ("Issue", "매거진", "열림")}
LINES = ["main 에 두 건이 들어갔어요", "오빠가 할 일은 하나예요"]
EASY = "쉬운 말로 다시 쓴 결정 한 줄이에요"


def model(hil=("이 매거진의 발행 시간을 정해 주세요 #885",), verdicts=()):
    m = fake_model()
    m["mbox"]["hil"] = list(hil)
    m["verdicts"] = [{"n": n, "line": line} for n, line in verdicts]
    m["detail"] = copy.deepcopy(DETAIL)
    return m


def unit_answer():
    return {"units": [{"ref": UNIT["path"], "icon": "🪟", "analogy": "책상 위 작은 창 같아요", "lines": ["읽을 내용을 한눈에 찾아봐요"]}]}


def llm(prompts=None, decide=lambda ref, text: EASY, fail_decisions=False):
    """run_cmd 대용 — 결정 줄 요청(<원문>)과 단위 요청(<자료>)을 가른다. decide(ref, 원문) → 쉬운 말."""
    from magazine_summary import SummaryError

    def run(cmd, prompt, timeout):  # noqa: ANN001, ANN202
        if "<원문>" not in prompt:
            return json.dumps(unit_answer(), ensure_ascii=False)
        if prompts is not None:
            prompts.append(prompt)
        if fail_decisions:
            raise SummaryError("실행 실패: Timeout")
        items = json.loads(prompt.split("<원문>\n", 1)[1].split("\n</원문>")[0])
        return json.dumps({"lines": [{"ref": i["ref"], "text": decide(i["ref"], i["원문"])} for i in items]}, ensure_ascii=False)
    return run


def render(monkeypatch, m=None, runner=None, lines=LINES):
    monkeypatch.setattr(me, "run_cmd", runner or llm())
    return me.build(m or model(), NOTES, "fake", lines)


def box(page: str, marker: str) -> str:
    return re.search(rf'<article class="decision{marker}">.*?</article>', page, re.S).group(0)


@pytest.fixture
def skill(tmp_path, monkeypatch):
    p = tmp_path / "eli5/2.10.0/skills/eli5/SKILL.md"
    p.parent.mkdir(parents=True)
    p.write_text("---\nname: eli5\n---\nTopic: $ARGUMENTS\n큰 그림과 적은 말", encoding="utf-8")
    monkeypatch.setattr(me, "SKILL_ROOT", tmp_path / "eli5")
