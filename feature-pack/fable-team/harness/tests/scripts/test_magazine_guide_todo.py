"""R259 매거진 §2 «오빠 할 일» — 원장 HEAD 꼴 묶음(굵은 제목 + 하위 글머리)을 이름으로 거르지 않고 그대로 옮긴다 (지침 §1 2행 · §4 2-1 · arch 재작업).

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY python3 -m pytest tests/scripts/test_magazine_guide_todo.py -q
"""
import re

import pytest
from _magazine_ledger import GOOD, argv, commit, make_env, page_of

import magazine_brief as mb
import magazine_doc as md
import magazine_doc_md as dm
import magazine_guide_check as gc


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


HEAD_S2 = """## 2. 오빠 할 일 (10-16 08:5x)
- **막는 것 (먼저)**
  - GitHub 자동 시험을 껐어요.
  - GPU 서버 2대가 켜져 있어요.
- **결정 (추천 먼저)**
  - 노트 요약 환경값 — 추천: 승인
- **실행 한 줄 (전부 미리 점검함)**
  - `! bash /tmp/h67` — 팝업 원인 점검
- **합치기 묶음** — 풀리면 한 줄로 드려요.
- **위험 — 지켜볼 것**
  - 시험 21개가 실패해요.

"""


def with_head_s2() -> str:
    return re.sub(r"## 2\. 오빠 할 일.*?(?=## 2-1\.)", lambda _: HEAD_S2, GOOD, flags=re.S)


def test_head_shaped_section2_groups_are_kept_by_title_without_name_filter(env, capsys):
    brief = mb.build_brief(dm.parse_doc(with_head_s2()), "2026-10-16", "abc", None, "x")
    assert [(t, len(i)) for t, i in brief.todo] == [("막는 것 (먼저)", 2), ("결정 (추천 먼저)", 1), ("실행 한 줄 (전부 미리 점검함)", 1), ("합치기 묶음", 1)]
    assert brief.risk == "시험 21개가 실패해요." and not [i for i in brief.issues if i[0].startswith("할 일")]
    assert gc.check(brief, True) == 0 and capsys.readouterr().out == ""
    commit(env[1], with_head_s2())
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    assert '<p class="grp">막는 것 (먼저)</p>' in page and '<span class="cmd">! bash /tmp/h67</span>' in page
    assert "지켜보는 위험</b> — 시험 21개가 실패해요." in page and "<h2>오빠 할 일</h2>" in page
