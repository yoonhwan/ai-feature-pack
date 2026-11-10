"""R259 매거진 지침(GUIDE-magazine-20261016) — 견본 틀 생성 · 발행 전 지침 검사 · 쉬운 말 호출 0 · 바뀐 것 비교. 임시 git 저장소 · 가짜 Slack · 실 원장 읽기 0.

실행: env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY python3 -m pytest tests/scripts/test_magazine_guide.py -q
"""
import logging
import re

import pytest
from _magazine_fakes import FakeMagazineSlack
from _magazine_ledger import GOOD, argv, commit, make_env, page_of

import magazine_brief as mb
import magazine_doc as md
import magazine_doc_md as dm
import magazine_guide_check as gc
import magazine_hermes as mh

H2 = ["끝낸 일", "오빠 할 일", "지난 판 뒤로 바뀐 것", "눈여겨볼 열린 일", "팀은 지금", "드러난 문제"]  # r867 — ① 끝낸 일 축하 · ② 남은 일(아래 다섯)


@pytest.fixture
def env(tmp_path):
    return make_env(tmp_path)


def body_of(page: str) -> str:
    return page.split("<footer>")[0]


def test_a_head_rule_paragraph_and_quote_blocks_are_not_in_the_page(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    assert "칸 규칙 원문" not in page and "마지막 갱신" not in page and "archive/" not in page and "planner#55" not in page
    assert "9팀 중 6팀이 일하고 있어요" in page  # 결론 줄은 맨 위 제목


def test_b_line_end_evidence_moves_to_footer_table(env):
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    main_part, footer = page.split("<footer>")
    for token in ("판정 1816", "#1612", "3e4578339b", "판정 1853", "판정 1854"):
        assert token not in main_part
    assert "판정 1816 · #1612" in footer and "3e4578339b" in footer and "판정 1854" in footer
    assert "시험 21개가 실패해요" in main_part  # 본문 문장은 그대로 남는다
    assert "원장 " in footer


def test_c_order_note_kind_and_serial_columns_are_not_on_the_page(env):
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    assert "97655" not in page and "97700" not in page and "발주 쪽지" not in page and "순번" not in page and ">종류<" not in page


def test_d_number_left_in_a_sentence_rejects_publish_with_zero_side_effects(env, capsys, caplog):
    commit(env[1], GOOD.replace("- 키 교체 첫 키 인터뷰 대기", "- 키 교체 첫 키 인터뷰 대기 판정 1804 에 따라"))
    slack = FakeMagazineSlack()
    with caplog.at_level(logging.ERROR, logger="magazine_doc"):
        assert md.main(argv(env, "--publish", slack)) == 1
    out = capsys.readouterr().out
    assert re.search(r"REJECT 지침 판정번호 오빠 할 일 판정 1804", out)
    assert slack.roots == [] and slack.upload_url_calls == 0 and not (env[0] / "state.json").exists() and not (env[0] / "out").exists()
    assert any("발행 거절" in r.getMessage() for r in caplog.records)


def test_e_same_input_dry_run_warns_and_still_builds_html(env, capsys):
    commit(env[1], GOOD.replace("- 키 교체 첫 키 인터뷰 대기", "- 키 교체 첫 키 인터뷰 대기 판정 1804 에 따라"))
    assert md.main(argv(env, "--dry-run")) == 0
    out = capsys.readouterr().out
    assert "WARN 지침 판정번호 오빠 할 일 판정 1804" in out and "REJECT" not in out
    assert "판정 1804" in page_of(env)  # 자동으로 지우지 않는다


def test_f_missing_conclusion_line_rejects_publish_and_warns_in_dry_run(env, capsys):
    commit(env[1], GOOD.replace("**결론**: 9팀 중 6팀이 일하고 있어요. 오빠 차례는 2건이에요.\n", ""))
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 1
    assert "REJECT 지침 결론 줄 없음" in capsys.readouterr().out and slack.roots == []
    assert md.main(argv(env, "--dry-run")) == 0
    assert "WARN 지침 결론 줄 없음" in capsys.readouterr().out and "결론 줄이 없어요" in page_of(env)


def edited(*pairs: tuple[str, str]) -> str:
    text = GOOD
    for old, new in pairs:
        assert old in text
        text = text.replace(old, new)
    return text


def test_g_changes_since_last_published_commit_and_unknown_when_none(env, capsys):
    assert md.main(argv(env, "--dry-run")) == 0
    first = page_of(env)
    assert "지난 판 커밋 모름" in first and 'class="ok">끝' not in first  # 지난 발행 없음 — 지어내지 않는다
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0
    commit(env[1], edited(
        ("| 2 | 실시간 통역 main 합치기 | 코드 | 진행 — 시험 실패 고치는 중 |", "| 2 | 실시간 통역 main 합치기 | 코드 | 진행 — 시험 통과 |"),
        ("| 3 | Supabase 메일 링크 | 오빠 확인 | 오빠 확인 대기 |", "| 3 | Supabase 메일 링크 | 오빠 확인 | 완료 — 오빠 확인 |"),
        ("| 6 | 운영 화면 | 코드 | 진행 — 두 번째 제안서 | |\n", "| 6 | 운영 화면 | 코드 | 진행 — 두 번째 제안서 | |\n| 7 | 새로 온 일 | 코드 | 진행 — 시작 | |\n"),
    ))
    capsys.readouterr()
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    assert 'class="ok">끝</span> Supabase 메일 링크' in page and 'class="wait">새</span> 새로 온 일' in page
    assert 'class="wait">바뀜</span> 실시간 통역 main 합치기 — 진행 — 시험 통과' in page
    assert "지난 판 커밋 모름" not in page and page.index(">끝<") < page.index(">새<") < page.index(">바뀜<")


def test_g_state_record_keeps_key_contract_and_adds_date(env):
    import json
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0
    (key, rec), = json.loads((env[0] / "state.json").read_text(encoding="utf-8")).items()
    assert re.fullmatch(r"[0-9a-f]{40}:doc\.md", key) and rec["uploaded"] is True and rec["date"] == "2026-10-16"


def test_h_no_easy_summary_call_is_made(env, monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(mh, "_fetch", lambda url, body, timeout: calls.append(url) or b"{}")
    assert md.main(argv(env, "--dry-run")) == 0
    assert calls == [] and not hasattr(md, "easy_all") and 'class="easy' not in page_of(env)


def test_h_seven_second_rule_stage_deadline_is_within_70_seconds():
    assert mh.STAGE_DEADLINE_S <= 70  # 판정 666 — magazine_hermes 는 뉴스 쪽이 계속 쓴다


def test_i_sections_follow_guide_order_and_empty_sections_are_dropped(env):
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    assert re.findall(r"<h2>([^<]+)</h2>", page) == H2
    assert page.index('class="date"') < page.index("<h1>") < page.index("<h2>") and page.rindex("</table>") > page.index("<footer>")
    no_team = edited(("## 3. 팀 작업 (10-16)", "## 3. 팀 이야기 (10-16)"))
    commit(env[1], no_team)
    assert md.main(argv(env, "--dry-run")) == 0
    assert "<h2>팀은 지금</h2>" not in page_of(env)


def test_i_open_rows_table_picks_confirm_blocked_and_watched_lines(env):
    assert md.main(argv(env, "--dry-run")) == 0
    page = page_of(env)
    block = re.search(r"<h2>눈여겨볼 열린 일</h2>(.*?)<h2>", page, re.S).group(1)
    for want in ("노출된 키 17개 교체", "실시간 통역 main 합치기", "Supabase 메일 링크", "전체 정리 절차"):
        assert want in block
    assert "운영 화면" not in block and "통역 툴바" not in block  # 그냥 진행·완료 줄은 안 올라온다
    assert "나머지 열린 일은 원장에" in block and 'class="mute">컨시어지' in page


def test_i_cap_is_eight_rows():
    rows = "\n".join(f"| {i} | 일{i} | 코드 | 막힘 — 사유 |" for i in range(12))
    text = GOOD.replace("| 6 | 운영 화면 | 코드 | 진행 — 두 번째 제안서 |", rows)
    brief = mb.build_brief(dm.parse_doc(text), "2026-10-16", "abc", None, "x")
    assert len(brief.open_rows) == mb.MAX_OPEN


def test_j_relative_date_guard_still_rejects_publish(env, capsys):
    commit(env[1], GOOD.replace("- 키 교체 첫 키 인터뷰 대기", "- 오늘 키 교체 첫 키 인터뷰 대기"))
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 1
    assert "REJECT 상대 날짜 오늘 오빠 할 일 5" in capsys.readouterr().out and slack.roots == []


def test_mutation_guide_check_removed_lets_dirty_ledger_publish(env, monkeypatch):
    monkeypatch.setattr(md, "guide_check", lambda brief, publish: 0)
    commit(env[1], GOOD.replace("- 키 교체 첫 키 인터뷰 대기", "- 키 교체 첫 키 인터뷰 대기 판정 1804 에 따라"))
    slack = FakeMagazineSlack()
    assert md.main(argv(env, "--publish", slack)) == 0 and len(slack.roots) == 1  # 검사를 빼면 ⓓ 의 rc=1 · 발행 0 이 깨진다


@pytest.mark.parametrize("text,item", [
    ("2026-10 판정 1816 참고", "판정번호"), ("이슈 #1612 가 닫혔어요", "이슈번호"), ("커밋 3e4578339b 가 들어갔어요", "커밋번호"),
    ("쪽지 97655 로 보냈어요", "쪽지번호"), ("R253 카드가 열렸어요", "약어좌표"), ("design/harness/x.md 를 봐요", "파일경로"),
    ("전반적으로 좋아요", "군말"), ("이 표는 팀을 보여줘요", "군말"), ("좋은 편이라고 할 수 있어요", "군말"), ("> 칸 규칙 인용", "칸규칙"),
])
def test_forbidden_shapes_each_flag(text, item, capsys):
    brief = mb.Brief("2026-10-16", "abc", conclusion="결론이에요", problems=[text])
    assert gc.check(brief, True) >= 1
    assert f"REJECT 지침 {item} 드러난 문제 " in capsys.readouterr().out


def test_allowed_shapes_pass(capsys):
    ok = ["명령 한 줄 실행 `! bash /tmp/h34`", "main 합치기 21개 중 17개", "날짜 10-16 08:00 에 끝나요", "13000원 결제", "Supabase 메일"]
    brief = mb.Brief("2026-10-16", "abc", conclusion="결론이에요", todo=[("할 일", ok)])
    assert gc.check(brief, True) == 0 and capsys.readouterr().out == ""


def test_bad_table_header_is_reported_not_dropped(capsys):
    brief = mb.build_brief(dm.parse_doc(GOOD.replace("| 팀 | 지금 하는 것 | 다음 |", "| 팀 | 지금 | 다음 |")), "2026-10-16", "abc", None, "x")
    assert any(i[0] == "표 형식" and i[1].startswith("팀 작업") for i in brief.issues)
    assert gc.check(brief, False) >= 1 and "WARN 지침 표 형식" in capsys.readouterr().out
