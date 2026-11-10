"""R202 매거진 상대 날짜 가드 — 원장 본문에 어제·오늘·내일… 이 있으면 --publish 는 발행 0 + rc≠0 + 줄 출력, --dry-run 은 WARN 후 계속. 가짜 Slack · 가짜 프록시.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY python3 -m pytest tests/scripts/test_magazine_date_guard.py -q
"""
import logging

import pytest
from _magazine_fakes import FakeMagazineSlack
from _magazine_ledger import GOOD, argv, commit, make_env, page_of
from test_magazine_doc_three import DATE, LEDGER

import magazine_date_guard as guard
import magazine_doc as md
import magazine_doc_md as dm
import magazine_doc_three as three


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


DIRTY = GOOD.replace("- 키 교체 첫 키 인터뷰 대기", "- 오늘 키 교체 첫 키 인터뷰 대기").replace("- 진행 카드의 상태", "- 내일 진행 카드의 상태")


def hits_of(md_text: str) -> list[tuple[str, str, int]]:
    return guard.find_relative_dates(dm.parse_doc(md_text))


def test_a_publish_rejects_body_cell_and_team_words_with_zero_publish(env, capsys, caplog):
    commit(env[1], DIRTY)
    slack = FakeMagazineSlack()
    with caplog.at_level(logging.ERROR, logger="magazine_doc"):
        assert md.main(argv(env, "--publish", slack)) == 1
    out = capsys.readouterr().out
    assert "REJECT 상대 날짜 오늘 오빠 할 일 5" in out and "REJECT 상대 날짜 내일 드러난 문제 1" in out
    assert slack.roots == [] and slack.upload_url_calls == 0 and not (env[0] / "state.json").exists()
    assert not (env[0] / "out").exists()  # HTML 도 안 만든다 — 게시 전에 거절
    assert any("발행 거절" in r.getMessage() for r in caplog.records)  # ⓔ 로그 경로(stderr)에도 남는다


def test_a_three_cells_and_sections_3_4_are_scanned():
    ledger = LEDGER.replace("- 하네스: 일함", "- 하네스: 내일 일함").replace("- 카드 상태 줄이 다름", "- 모레 고침")
    got = {(w, s) for w, s, _ in guard.find_relative_dates(three.with_three(dm.parse_doc(ledger), DATE))}
    assert ("어제", "요청한 일") in got and ("어제", "완료한 일") in got  # 3칸(소제목·완료 보관 행)
    assert ("내일", "팀 작업 (팀 차례)") in got and ("모레", "드러난 문제") in got


def test_b_dry_run_warns_and_continues_without_publish_side_effects(env, capsys):
    commit(env[1], DIRTY)
    assert md.main(argv(env, "--dry-run")) == 0
    out = capsys.readouterr().out
    assert "WARN 상대 날짜 오늘 오빠 할 일 5" in out and "WARN 상대 날짜 내일 드러난 문제 1" in out and "REJECT" not in out
    assert "오늘 키 교체" in page_of(env) and not (env[0] / "state.json").exists()


def test_c_quotes_and_code_are_skipped_and_compounds_are_not_words():
    body = "\n".join([
        "# 샘플 (2026-10-13)", "", "## 1. 칸",
        "- 「오늘 할 일」 은 인용", "- «내일» 도 인용", '- "어제" 와 “모레” 도 인용', "- `오늘` 코드 안",
        "- 오늘날 · 내일모레 · 어제오늘 · 그제서야 는 합성어",
        "- 오늘은 진짜", "- 마감은 내일의 일", "- 오늘(10-13) 이 그대로",
    ])
    assert [(w, n) for w, _, n in hits_of(body)] == [("오늘", 6), ("내일", 7), ("오늘", 8)]  # 줄 번호 = 칸 본문 안(1부터)


def test_c_word_list_covers_all_six():
    text = "# 샘플 (2026-10-13)\n\n## 1. 칸\n" + "\n".join(f"- {w} 일" for w in ("어제", "오늘", "내일", "모레", "그제", "그저께"))
    assert [w for w, _, _ in hits_of(text)] == ["어제", "오늘", "내일", "모레", "그제", "그저께"]


def test_d_clean_doc_has_no_hits_and_still_publishes(env, capsys):
    assert hits_of(GOOD) == []
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0 and len(slack.roots) == 1
    seen = capsys.readouterr()
    assert "REJECT" not in seen.out and "WARN" not in seen.out


def test_mutation_guard_call_removed_lets_dirty_doc_publish(env, monkeypatch):
    monkeypatch.setattr(md, "date_guard", lambda doc, publish: False)
    commit(env[1], DIRTY)
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0  # 가드를 빼면 ⓐ 의 rc=1 · 발행 0 이 깨진다
    assert len(slack.roots) == 1
