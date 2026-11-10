"""R242 단계 3 — ③(오래된 스레드)로 늦게 찾은 오빠 답은 본문 첫 줄에 «[옛 글 MM-DD HH:MM · N시간 늦게]»(U1~U6)
+ C5 history 응답 끊김(IncompleteRead)은 재시도 1 뒤 MirrorError 1줄(U7·U8)."""
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import test_byz_slack_mbox_inbound as base
import test_inbound_old_threads_r242 as old
from _slack_fakes import FakeSlack

env, slack = base.env, base.slack  # 픽스처 재사용
DAY, KST = 86400, timezone(timedelta(hours=9))


def _rows(env: Path) -> list[dict]:
    return [r for r in base.queue(env) if r["from"] == "slack-oppa"]


def _head(ts: str, late: str) -> str:
    return f"[옛 글 {datetime.fromtimestamp(float(ts), KST).strftime('%m-%d %H:%M')} · {late} 늦게]"


def _old_reply(env: Path, slack: FakeSlack, age: float, text: str = "새 답") -> str:
    t = old._setup(env, slack, 2 * DAY)
    ts = old._reply(slack, t, age)
    slack.msgs[-1]["text"] = text
    old._at(env, slack, 0)
    return ts


def test_u1_late_old_thread_reply_gets_a_first_line_head_in_hours(env: Path, slack: FakeSlack):
    ts = _old_reply(env, slack, 11 * 3600)
    rows = _rows(env)
    assert rows and all(r["body"].split("\n")[0].endswith(" " + _head(ts, "11시간")) for r in rows)
    assert all(r["body"].split("\n")[1].startswith("오빠(Slack) 발화") for r in rows)  # 나머지 본문 그대로


def test_u2_old_thread_reply_within_ten_minutes_has_no_head(env: Path, slack: FakeSlack):
    _old_reply(env, slack, 120)
    rows = _rows(env)
    assert rows and not any("[옛 글" in r["body"] for r in rows)


def test_u3_late_reply_found_by_the_root_window_has_no_head(env: Path, slack: FakeSlack):
    t = base.start(env, slack)
    base._old_baseline(env)
    old._reply(slack, t, 3 * 3600)  # 루트 창(①) 안 스레드 — 늦게 읽혀도 ③ 가 아니다
    old._at(env, slack, 0)
    rows = _rows(env)
    assert rows and not any("[옛 글" in r["body"] for r in rows)


def test_u4_delivered_late_reply_is_not_sent_again(env: Path, slack: FakeSlack):
    _old_reply(env, slack, 11 * 3600)
    assert _rows(env)
    (env / "comm" / "mailbox.jsonl").unlink()  # 좌석이 읽음 — 마커가 사라져도
    old._at(env, slack, old.EVERY)
    assert _rows(env) == []


def test_u5_late_by_less_than_an_hour_is_said_in_minutes(env: Path, slack: FakeSlack):
    ts = _old_reply(env, slack, 40 * 60)
    rows = _rows(env)
    assert rows and all(_head(ts, "40분") in r["body"].split("\n")[0] for r in rows)


def test_u6_long_late_reply_keeps_the_spool_file_as_is_and_puts_the_head_on_the_summary(env: Path, slack: FakeSlack):
    ts = _old_reply(env, slack, 11 * 3600, "긴 답 " * 200)
    spools = list((env / "st" / "spool").glob("inbound-*.txt"))
    assert spools and not any("[옛 글" in p.read_text(encoding="utf-8") for p in spools)  # 보관 파일 = 머리 없는 본문
    rows = _rows(env)
    assert rows and all(r["body"].rsplit("\n", 1)[-1].startswith(_head(ts, "11시간")) for r in rows)  # 큐에 보이는 요약 줄에 머리


def test_u7_cut_history_body_once_is_retried_and_the_daemon_goes_on(env: Path, slack: FakeSlack):
    base.start(env, slack)
    new = slack.human("새 글")
    slack.cut_history = 1
    r = base.run(env, slack)
    assert r.returncode == 0 and "Traceback" not in r.stderr
    assert any(f"slack:{new}:" in x["body"] for x in _rows(env))


def test_u8_history_body_cut_every_time_is_one_error_line_not_a_traceback(env: Path, slack: FakeSlack):
    base.start(env, slack)
    slack.cut_history = 10
    r = base.run(env, slack)
    assert r.returncode == 1
    assert "호출 실패: IncompleteRead" in r.stderr and "Traceback" not in r.stderr
    assert json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))["ledger"] == {}
