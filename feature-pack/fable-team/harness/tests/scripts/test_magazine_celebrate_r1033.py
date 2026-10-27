"""r1033 — «끝낸 일» 칸 원문 줄(Done.what → fact())도 제목과 같은 걸러내기(_plain)를 지난다 (판정 2724 · Issue byz-agents#3930).

카드 닫힘 줄에는 커밋 번호·파일 경로가 원래 들어 있다. 제목은 _plain 으로 거르는데 원문 줄은 그대로 실려
08:20 발행이 «지침 위반 144건» 으로 거절됐다. 걸러 낸 번호는 근거 표에 남는다(숨김 0).
실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE /opt/homebrew/bin/python3.11 -m pytest tests/scripts/test_magazine_celebrate_r1033.py -q
"""
import os
import subprocess
from pathlib import Path

import pytest
import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다

import magazine_celebrate as mc
import magazine_guide_check as mg
from magazine_brief import Brief

DAY = "2026-10-20"  # 축하 창 = 10-19 00:00 ~ 10-20 08:00 KST(끝 제외)
MARK = "(설명 문장은 근거 표에)"  # 걸러도 지침 꼴이 남았을 때의 표시
FAKE_SHA = "ab12cd34ef"  # 닫힘 줄에만 있는 번호 — 근거 표로 옮겨졌는지 이 값으로 본다
CARD = "# 인덱스: {stem} — 끝: {note}\n\n## 골 원문 (항상 이 3줄)\n골\n\n## 상태\n{close}\n"
ELI5 = {"icon": "🌱", "title": "새로 좋아진 일이 생겼어요", "analogy": "작은 정원에 새 꽃이 피었어요", "lines": ["이제 더 쉽게 읽을 수 있어요"]}


def commit(repo: Path, when: str, files: dict[str, str]) -> str:
    for rel, text in files.items():
        path = repo / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when}
    subprocess.run(["git", "-C", str(repo), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", when], check=True, env=env)
    return subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], check=True, capture_output=True, text=True).stdout.strip()


def card(stem: str, close: str, note: str = "한 줄") -> str:
    return CARD.format(stem=stem, note=note, close=close)


@pytest.fixture
def repo(tmp_path):
    """창 안 완성 카드 4벌 — ⓐ 커밋 번호+경로 줄 · ⓑ 같은 sha 한 쌍(합침) · ⓒ 절대 경로만 남는 줄 · ⓓ 닫힘 줄 없음."""
    path = tmp_path / "repo"
    path.mkdir()
    for args in (("init", "-q", "-b", "main"), ("config", "user.email", "t@t"), ("config", "user.name", "t")):
        subprocess.run(["git", "-C", str(path), *args], check=True)
    done = "design/harness/indices/완성/"
    commit(path, "2026-10-19T09:00:00+09:00",
           {f"{done}r1033-a.md": card("r1033-a", f"- 닫힘 판정문: {FAKE_SHA} 착지 · 카드 {done}r1033-a.md")})
    commit(path, "2026-10-19T10:00:00+09:00",  # 같은 커밋 = 같은 닫는 증거 sha → 1건으로 합친다
           {f"{done}r1033-b.md": card("r1033-b", f"- 닫힘 판정문: 판정 2724 · {done}r1033-b.md"),
            f"{done}r1033-c.md": card("r1033-c", f"- 닫힘 판정문: 판정 2724 · {done}r1033-c.md")})
    commit(path, "2026-10-19T11:00:00+09:00",
           {f"{done}r1033-d.md": card("r1033-d", "- 닫힘 판정문: 고침 완료 · /Users/yoonhwan/.hermes/scripts/magazine_celebrate.py 바꿈")})
    commit(path, "2026-10-19T12:00:00+09:00", {f"{done}r1033-e.md": card("r1033-e", "- 검토 대기")})  # 닫힘 줄 없음
    return path


def brief_of(repo: Path) -> Brief:
    """collect + 쉬운 풀이 dict 주입(외부 호출 0) — 판에 실리는 «끝낸 일» 칸 줄을 그대로 만든다."""
    brief = Brief(DAY, "x", conclusion="일하는 팀이 셋이에요.")
    brief.span, brief.done = mc.collect(str(repo), "HEAD", DAY)
    brief.evidence += [(d.evidence, d.title[:40]) for d in brief.done]
    for d in brief.done:
        d.eli5 = dict(ELI5)
    return brief


def done_lines(brief: Brief) -> list[str]:
    cell = next(c for c in brief.cells() if c.title == "끝낸 일")
    return cell.body.splitlines()


def test_a_done_fact_line_carries_no_guide_violation(repo):
    brief = brief_of(repo)
    assert len(brief.done) == 4  # a · (b+c 합침) · d · e
    lines = done_lines(brief)
    assert mg.violations(brief.done_head()) == [] and len(lines) > 1
    bad = [(ln, mg.violations(ln)) for ln in lines if mg.violations(ln)]
    assert bad == []  # 원문 줄(fact)의 커밋 번호·경로가 판으로 새지 않는다


def test_b_stripped_numbers_stay_in_the_evidence_table(repo):
    brief = brief_of(repo)
    text = " ".join(f"{why} {what}" for why, what in brief.evidence)
    assert FAKE_SHA in text  # 닫힘 줄에서 걷어 낸 번호는 근거 표에 남는다(숨김 0)
    assert "design/harness/indices/완성/r1033-a.md" in text


def test_c_leftover_guide_shape_marked_and_missing_close_keeps_plain_title(repo):
    brief = brief_of(repo)
    what = {d.title: d.fact() for d in brief.done}
    assert what["r1033-d"] == MARK  # 절대 경로는 걷어도 남는다 → 표시만
    assert what["r1033-e"] == "원문 — r1033-e"  # 닫힘 줄 없음 → «원문 — <제목>»(제목은 이미 걸러짐)
    assert what["r1033-a"] and mg.violations(what["r1033-a"]) == []  # 남은글도 위반 0
