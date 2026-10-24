"""r867 r2 — DA⑥ r1 반례 3건(완성/ 안 이름 바꾸기 재축하 · 한 장 eli5 입력 상한 · 남은 일 약어만 줄) 시험.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE python3 -m pytest tests/scripts/test_magazine_celebrate_r2.py -q
"""
import json
import re

import _magazine_fakes  # noqa: F401 — slack-mirror 경로를 sys.path 에 올린다
from test_magazine_celebrate import commit, env  # noqa: F401 — 같은 임시 원장·git 이력

import magazine_celebrate as mc
import magazine_celebrate_eli5 as mb
import magazine_guide_check as mg
from magazine_brief import Brief

OLD = "design/harness/indices/완성/r900-easy-news.md"


def test_rename_inside_done_folder_is_not_a_new_completion(env):  # noqa: F811 — 위에서 가져온 fixture
    _, repo, _ = env
    text = (repo / OLD).read_text(encoding="utf-8")
    commit(repo, "2026-10-17T10:00:00+09:00", {OLD: None, "design/harness/indices/완성/r900-renamed.md": text})
    span, done = mc.collect(str(repo), "HEAD", "doc.md", "2026-10-18")
    assert span == "10-17 00:00 ~ 10-18 08:00" and done == []  # 창 전에 이미 완성/ 이던 카드 — 이름만 바뀜
    _, done16 = mc.collect(str(repo), "HEAD", "doc.md", "2026-10-16")
    assert "뉴스 창이 빨라졌어요" in [d.title for d in done16]  # 진행/ → 완성/ 이동은 그대로 축하


def test_one_long_unit_is_cut_to_the_base_amount_with_a_visible_mark():
    prompts: list[str] = []

    def runner(cmd, prompt, timeout):
        prompts.append(prompt)
        units = json.loads(re.search(r"<자료>\n(.*)\n</자료>", prompt, re.S).group(1))
        return json.dumps({"units": [{"ref": u["ref"], "icon": "🌱", "title": "좋아졌어요", "analogy": "꽃이 피었어요", "lines": ["쉬워졌어요"]} for u in units]}, ensure_ascii=False)

    result = mb.explain([{"ref": "a", "자료": "가" * 50000}, {"ref": "b", "자료": "나" * 10}], "cmd", "쉬운 말", runner)
    assert len(prompts) == 1 and isinstance(result["a"], dict) and isinstance(result["b"], dict)
    sent = json.loads(re.search(r"<자료>\n(.*)\n</자료>", prompts[0], re.S).group(1))
    assert sum(len(u["자료"]) for u in sent) <= mb.BASE_CHARS  # 호출 한 번의 자료 합 ≤ 기준량(하드 룰 12)
    assert sent[0]["자료"].endswith(mb.CUT_MARK) and sent[1]["자료"] == "나" * 10


def test_remaining_line_with_only_abbreviations_warns_without_blocking(capsys):
    brief = Brief("2026-10-16", "x", conclusion="일하는 팀이 셋이에요.", todo=[("지금", ["DA · STT · E2E", "DA 판정 받고 착지하기"])])
    assert mg.check(brief, publish=True) == 0  # 발행 막기 0
    out = capsys.readouterr().out
    assert "WARN 지침 약어만 오빠 할 일 DA · STT · E2E" in out and "착지하기" not in out
