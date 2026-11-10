"""r894 — 슬랙 뿌리 글 단순화(골 표·팀 표·절차 블록은 HTML 에만) · 쉬운 풀이 차단 낱말 «다시 쓰기 1회» · eli5 문체 지침 = 따를 규칙. 가짜 Slack·가짜 LLM · 외부 호출 0.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE python3 -m pytest tests/scripts/test_magazine_slack_root_eli5_retry_r894.py -q
"""
import json
import logging
import re
import shutil
import time

import pytest
from _magazine_fakes import FakeMagazineSlack
from _magazine_ledger import GOOD, argv, make_env
from magazine_summary import SummaryError
from test_magazine_goal import BIN, CANON, TITLE, arm, env  # noqa: F401 — 무장 골 표 fixture(정본 견본 · 임시 FT_ROOT)

import magazine_celebrate as mc
import magazine_celebrate_eli5 as mb
import magazine_doc as md
import magazine_eli5 as me
import magazine_eli5_batches as eb
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

OK = {"icon": "🌱", "title": "좋아졌어요", "analogy": "꽃이 피었어요", "lines": ["쉬워졌어요"]}
TABLE_CONCLUSION = "**결론**: | 골 | 팀 | |---|---| | 진행 | 하네스 |"  # DA⑥ r1 반례 1 입력 그대로
GOOD_CONCLUSION = "**결론**: 9팀 중 6팀이 일하고 있어요. 오빠 차례는 2건이에요."


def _refs(prompt: str) -> list[str]:
    return [u.get("ref") or u.get("path") for u in json.loads(prompt.rsplit("<자료>\n", 1)[1].split("\n</자료>", 1)[0])]


# ⓐ·ⓑ 슬랙 뿌리 글 ------------------------------------------------------------

def test_root_has_no_table_or_goal_block_but_the_html_does(env):  # noqa: F811
    mag, root = env
    arm(root)
    slack = FakeMagazineSlack()
    assert md.main(argv(mag, "--publish", slack)) == 0
    lines = slack.roots[0]["text"].splitlines()
    assert lines[0] == TITLE  # «첫 줄 정확 일치» 탐색 그대로
    assert len(lines) <= 5 and not any(x.lstrip().startswith("|") or "|---" in x or "★골 표" in x for x in lines)
    assert lines[1] == "9팀 중 6팀이 일하고 있어요. 오빠 차례는 2건이에요."  # 원장 결론 칸(굵게 표시 걷음)
    page = next((mag[0] / "out").glob("*.html")).read_text(encoding="utf-8")
    assert "<h2>자율 골 표</h2>" in page and "★골 표 A6 (" in page


def test_dry_run_root_is_the_same_short_text(env, capsys):  # noqa: F811
    mag, root = env
    arm(root)
    assert md.main(argv(mag, "--dry-run")) == 0
    shown = capsys.readouterr().out.split("--- 슬랙 뿌리 글 ---\n", 1)[1].split("\nSLACK 링크 없음", 1)[0]
    assert shown == md.root_text("2026-10-16", "**9팀 중** 6팀이 일하고 있어요. 오빠 차례는 2건이에요.") and "★골 표" not in shown


def test_root_without_conclusion_keeps_title_and_pointer_only():
    assert md.root_text("2026-10-16").splitlines() == [TITLE, md.ROOT_POINTER]


@pytest.fixture
def env_table_conclusion(tmp_path, monkeypatch):
    """DA⑥ r1 반례 1 그대로 — 원장 결론 한 줄이 표 꼴인 원장 · 임시 FT_ROOT(무장 골 게이트 견본)."""
    root = tmp_path / "ftroot"
    (root / ".fable-team" / "bin").mkdir(parents=True)
    for name in ("ft-goal-table.sh", "ft_goal_table.py", "ft_goal_ledger.py", "ft_goal_gate.py", "ft_goal_receipt.py", "ft_goal_readjust_state.py", "ft_team_lib.py"):
        shutil.copy(BIN / name, root / ".fable-team" / "bin" / name)
    monkeypatch.setenv("FT_ROOT", str(root))
    monkeypatch.setenv("FT_GOAL_A6_MD", str(CANON))
    monkeypatch.setenv("FT_GOAL_A6_LEDGER", str(tmp_path / "없는원장.md"))
    assert GOOD_CONCLUSION in GOOD
    return make_env(tmp_path, GOOD.replace(GOOD_CONCLUSION, TABLE_CONCLUSION)), root


def test_table_shaped_conclusion_stays_out_of_the_root_and_warns(env_table_conclusion, capsys):  # noqa: F811
    """F1 — 표 꼴 결론은 뿌리 글에 0(안내 1줄) · 결과 줄 warn ≥1 · HTML 첫 절 결론은 그대로 · 발행은 그대로 된다."""
    mag, root = env_table_conclusion
    arm(root)
    slack = FakeMagazineSlack()
    assert md.main(argv(mag, "--publish", slack)) == 0
    text = slack.roots[0]["text"]
    assert "|" not in text and md.TABLE_LINE in text.splitlines()[1] and len(slack.roots) == 1
    assert slack.roots[0]["text"].splitlines()[0] == TITLE
    assert int(re.search(r"warn=(\d+)", capsys.readouterr().out).group(1)) >= 1
    page = next((mag[0] / "out").glob("*.html")).read_text(encoding="utf-8")
    assert "| 골 | 팀 |" in page and "<h2>자율 골 표</h2>" in page  # HTML 결론·골 표는 그대로


# ⓒ 축하 칸(magazine_doc 경로) 차단 낱말 다시 쓰기 ---------------------------------

def _celebrate_runner(prompts: list[str], first: str, second: str | Exception):
    def runner(cmd, prompt, timeout):
        prompts.append(prompt)
        ids = _refs(prompt)
        if len(prompts) > 1:
            if isinstance(second, Exception):
                raise second
            return json.dumps({"units": [{**OK, "ref": r, "lines": [second]} for r in ids]}, ensure_ascii=False)
        return json.dumps({"units": [{**OK, "ref": r, "lines": [first if r == "u1" else "쉬워졌어요"]} for r in ids]}, ensure_ascii=False)
    return runner


def test_celebrate_blocked_word_is_rewritten_once_naming_the_word():
    prompts: list[str] = []
    out = mb.explain([{"ref": "a", "자료": "가"}, {"ref": "b", "자료": "나"}], "cmd", "쉬운 말", _celebrate_runner(prompts, "새 판을 배포했어요", "새 판이 나왔어요"))
    assert out["a"]["lines"] == ["새 판이 나왔어요"] and out["b"]["lines"] == ["쉬워졌어요"]
    assert len(prompts) == 2 and "«배포»" in prompts[1] and _refs(prompts[1]) == ["u1"]  # 걸린 칸만 · 걸린 낱말을 적는다
    assert "«배포»" not in prompts[0]


@pytest.mark.parametrize("second", ["또 배포했어요", SummaryError("요약 실행 실패: TimeoutExpired")])
def test_celebrate_second_failure_drops_only_that_unit(second):
    prompts: list[str] = []
    out = mb.explain([{"ref": "a", "자료": "가"}, {"ref": "b", "자료": "나"}], "cmd", "쉬운 말", _celebrate_runner(prompts, "모두 끝났어요", second))
    assert out["a"] == "차단 단어" and out["b"]["lines"] == ["쉬워졌어요"] and len(prompts) == 2


def test_celebrate_rewrite_is_skipped_when_the_total_deadline_cannot_fit(monkeypatch, caplog):
    monkeypatch.setattr(mb, "DEADLINE_S", 1.0)  # 다시 쓰기 한 번(7초 + 시간 초과 재시도 7초)이 총 마감 안에 못 들어간다
    prompts: list[str] = []
    with caplog.at_level(logging.WARNING):
        out = mb.explain([{"ref": "a", "자료": "가"}], "cmd", "쉬운 말", _celebrate_runner(prompts, "배포했어요", "나왔어요"))
    assert out["a"] == "차단 단어" and len(prompts) == 1 and "총 마감" in caplog.text


# ⓒ 구 매거진(쉬운 판) 경로 -------------------------------------------------------

def test_batches_blocked_word_is_rewritten_once():
    prompts: list[str] = []
    def runner(cmd, prompt, timeout):
        prompts.append(prompt)
        line = "결정이 났어요" if len(prompts) == 1 else "길이 정해졌어요"
        return json.dumps({"units": [{"ref": p, "icon": eb.ICONS[0], "analogy": "길을 찾았어요", "lines": [line if p == "p1" else "쉬워요"]} for p in _refs(prompt)]}, ensure_ascii=False)
    out = eb.explain([{"path": "p1", "title": "가"}, {"path": "p2", "title": "나"}], "cmd", "쉬운 말", runner)
    assert out["p1"]["lines"] == ["길이 정해졌어요"] and out["p2"]["lines"] == ["쉬워요"]
    assert len(prompts) == 2 and "«결정»" in prompts[1] and _refs(prompts[1]) == ["p1"]


def test_batches_total_deadline_stops_new_calls_and_marks_timeout(monkeypatch, caplog):
    """F2 — DA⑥ r1 반례 2 를 1/100 배율로: 25칸 · 호출당 0.13초 · TIMEOUT 0.07 · DEADLINE 0.7. 마감 뒤 새 호출 0 · 마감에 못 끝난 칸 = «시간 초과»."""
    monkeypatch.setattr(eb, "TIMEOUT", 0.07)
    monkeypatch.setattr(eb, "DEADLINE_S", 0.7)
    calls: list[float] = []
    started = time.monotonic()

    def runner(cmd, prompt, timeout):
        calls.append(time.monotonic() - started)
        time.sleep(0.13)
        line = "결정이 났어요" if "«결정»" not in prompt else "길이 정해졌어요"  # 모든 칸이 걸린다 → 묶음마다 다시 쓰기 1회 = 호출 2회
        return json.dumps({"units": [{"ref": p, "icon": eb.ICONS[0], "analogy": "길을 찾았어요", "lines": [line]} for p in _refs(prompt)]}, ensure_ascii=False)

    with caplog.at_level(logging.ERROR):
        out = eb.explain([{"path": f"p{i}", "title": "가"} for i in range(25)], "cmd", "쉬운 말", runner)
    elapsed = time.monotonic() - started
    assert elapsed <= 0.7 + 0.1  # 마감 뒤 작은 여유만(총 대기가 마감을 모르면 1/100 배율에서도 0.9초를 넘는다)
    assert calls and max(calls) <= 0.7 + 0.02  # 마감 뒤 시작한 호출 0
    assert list(out.values()).count("시간 초과") >= 2 and "시간 초과" in caplog.text  # 마감에 못 끝난 칸 = 생략 + 사유
    assert any(isinstance(v, dict) for v in out.values())  # 성공한 칸은 그대로 실린다


# ⓓ eli5 스킬 본문 = 따를 규칙 · 없으면 보이는 실패 ------------------------------------

def test_skill_body_is_a_rule_not_a_reference_in_both_prompts():
    for prompt in (mb._prompt([{"ref": "u1", "자료": "가"}], "SKILL-BODY"), eb._prompt([{"path": "p", "title": "가"}], "SKILL-BODY")):
        assert "SKILL-BODY" in prompt and "참고일 뿐" not in prompt and "꼭 따를 문체 규칙" in prompt


def test_missing_skill_is_a_visible_error_not_a_silent_skip(tmp_path, monkeypatch, caplog):
    monkeypatch.setattr(me, "SKILL_ROOT", tmp_path)
    with pytest.raises(me.Eli5Error, match="SKILL.md 없음"):
        me._skill()
    done = [mc.Done(key="k", title="제목", what="무엇", evidence="e", source="자료")]
    with caplog.at_level(logging.ERROR):
        mc.explain_done(done, "cmd")
    assert done[0].eli5 == "eli5 스킬 없음" and "SKILL.md 없음" in caplog.text
