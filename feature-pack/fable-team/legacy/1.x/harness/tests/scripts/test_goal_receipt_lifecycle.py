"""R362 DA⑥ r2 HOLD 2 — H3 검증 영수증 수명(묶음별 키 · pending/partial/complete/failed 닫는 사건 · 본문 해시 결속 · 기록 뒤 mark_done) + H4 모듈 누락 통지 · 억제 지문.

표본 7: H3 ①첫 판 실패→failed·후속 번호 소비 불가 ②부분 성공 뒤 기록 실패→재시도 중복 게시 0+기록 복구 ③완료 후 재시도→이미 완료 거절+영수증 닫힘 ④다른 묶음 시작→이전 묶음 보존 ⑤같은 번호 다른 본문→거절 / H4 ⑥모듈 누락+무장→통지 1회 ⑦같은 80자 접두 다른 사유→통지 2회.
실행: .venv/bin/python -m pytest tests/scripts/test_goal_receipt_lifecycle.py -q -p no:cacheprovider
"""
import json
from datetime import datetime
from pathlib import Path

import pytest
from test_ft_news_goal_block import LEAD, NOW, REL, _bundle_env, _new, arm, block, canon, gate, lt, np, post, sdir, stub_mbox  # noqa: F401 — 픽스처·도구 재사용
from test_ft_news_publish import draft, env, polished, records, slack  # noqa: F401

NEXT_RUN = datetime(2026, 10, 18, 10, 31)


def _parts(block: str, at: datetime = NOW) -> list[str]:
    parts = lt.render_parts(at, _new(120), [], REL, lead=LEAD, goal=block)
    assert len(parts) >= 3
    return parts


def _receipts(tmp: Path) -> list[dict]:
    return [json.loads(f.read_text(encoding="utf-8")) for f in sorted((sdir(tmp) / "goal-bundle").glob("*.json"))]


def test_h3_first_part_failure_marks_failed_and_followup_numbers_cannot_be_consumed(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    fail = tmp_path / "fail.sh"
    fail.write_text("#!/usr/bin/env bash\nexit 1\n", encoding="utf-8")
    monkeypatch.setenv("FT_NEWS_PUBLISH", f"bash {fail}")
    arm(tmp_path)
    parts = _parts(block)
    assert post.publish(news, state, parts, NOW, "cur1")[0] == 1
    (rec,) = _receipts(tmp_path)
    assert rec["status"] == "failed" and "1/" in rec["reason"]
    assert gate.problem(parts[1], sdir(tmp_path)) != ""  # 후속 번호 소비 불가
    assert (state / "last.sha").read_text().strip() == "base"


def test_h3_partial_success_then_record_failure_retries_without_duplicate_post_and_recovers_record(env, slack, monkeypatch, block):  # noqa: F811
    tmp, news = env
    arm(tmp)
    draft(news, "20261013-0900")
    parts = _parts(block)
    assert gate.write_receipt(sdir(tmp), parts) == ""
    first = polished(news, "20261013-0911", parts[1])
    calls = {"n": 0}
    real = np._record

    def flaky(*a, **k):
        calls["n"] += 1
        if calls["n"] == 1:
            raise OSError("기록 저장 실패")
        return real(*a, **k)

    monkeypatch.setattr(np, "_record", flaky)
    with pytest.raises(OSError):
        np.main(["publish", str(first)])
    assert len(slack.posts) == 1 and _receipts(tmp)[0]["done"] == []  # mark_done 은 기록 저장 «뒤» — 아직 안 찍힘
    assert np.main(["publish", str(first)]) == 0  # 재시도
    assert len(slack.posts) == 1  # 중복 게시 0
    assert records(tmp) != [] and _receipts(tmp)[0]["done"] == [2]  # 기록 복구 + 영수증 완료 표기


def test_h3_retry_after_complete_is_refused_and_receipt_stays_closed(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    arm(tmp_path)
    parts = _parts(block)
    assert post.publish(news, state, parts, NOW, "cur1")[0] == 0
    assert _receipts(tmp_path)[0]["status"] == "complete"
    lines = (tmp_path / "stub.log").read_text().splitlines()
    assert post.publish(news, state, parts, NOW, "cur1")[0] == 3  # 이미 완료
    assert (tmp_path / "stub.log").read_text().splitlines() == lines  # 발행 0
    assert _receipts(tmp_path)[0]["status"] == "complete"


def test_h3_starting_another_bundle_keeps_the_previous_bundle_state(tmp_path, block):
    a, b = _parts(block), _parts(block, NEXT_RUN)
    assert gate.write_receipt(sdir(tmp_path), a) == ""
    before = _receipts(tmp_path)
    assert gate.write_receipt(sdir(tmp_path), b) == ""
    after = _receipts(tmp_path)
    assert len(after) == 2 and before[0] in after  # 이전 묶음 내용 그대로


def test_h3_same_part_number_with_a_different_body_is_rejected(tmp_path, block):
    parts = _parts(block)
    gate.write_receipt(sdir(tmp_path), parts)
    assert gate.problem(parts[1], sdir(tmp_path)) == ""
    assert gate.problem(parts[1] + "\n검증하지 않은 다른 본문\n", sdir(tmp_path)) != ""


def test_h3_draft_mode_leaves_a_closing_mark_not_a_dangling_pending(tmp_path, monkeypatch, block):
    news, state = _bundle_env(tmp_path, monkeypatch)
    monkeypatch.setenv("FT_NEWS_MODE", "draft")
    arm(tmp_path)
    assert post.publish(news, state, _parts(block), NOW, "cur1")[0] == 0
    assert _receipts(tmp_path)[0]["status"] == "drafted"


def test_h4_missing_gate_module_notifies_planner_once_when_armed(tmp_path, monkeypatch):
    log = stub_mbox(tmp_path, monkeypatch)
    stand_in = post._MissingGate(ImportError("x"))
    assert stand_in.refuse(sdir(tmp_path), "bundle abc", stand_in.why) is False  # 비무장 = 통지 0
    assert not log.exists()
    arm(tmp_path)
    assert stand_in.refuse(sdir(tmp_path), "bundle abc", stand_in.why) is True
    assert stand_in.refuse(sdir(tmp_path), "bundle abc", stand_in.why) is True
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 1  # 같은 거절 1회


def test_h4_same_80_char_prefix_with_different_reasons_notifies_twice(tmp_path, monkeypatch):
    log = stub_mbox(tmp_path, monkeypatch)
    head = "가" * 80
    assert gate.notify_planner(tmp_path, "render", head + "A") is True
    assert gate.notify_planner(tmp_path, "render", head + "B") is True
    assert gate.notify_planner(tmp_path, "render", head + "A") is False  # 같은 사유는 억제
    assert log.read_text(encoding="utf-8").count("[긴급] 뉴스 발행 거절") == 2
