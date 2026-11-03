"""R242 단계 2 — 루트가 7일 넘은 스레드에 온 새 답글을 원장 «seen»(마지막 답 시각)으로 찾아 읽는다(반례 T1·T2·T4·T5·T6 · T3 = 단계 1 시험)."""
import json
import time
from pathlib import Path

import test_byz_slack_mbox_inbound as base
from _slack_fakes import FakeSlack

env, slack = base.env, base.slack  # 픽스처 재사용
HUMAN, run, start, _old_baseline = base.HUMAN, base.run, base.start, base._old_baseline
DAY = 86400


def _state(env: Path) -> dict:
    return json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))


def _set_seen(env: Path, seen: dict[str, str]) -> None:
    p = env / "st" / "byz_slack_mbox_inbound.C1.json"
    st = _state(env)
    p.write_text(json.dumps({**st, "seen": {**st.get("seen", {}), **seen}}), encoding="utf-8")


def _old_root(slack: FakeSlack, age: float = 10 * DAY) -> str:
    t = f"{time.time() - age + len(slack.msgs) * 0.001:.6f}"
    slack.msgs.append({"ts": t, "text": "#820 옛 스레드 — x", "thread_ts": "", "bot_id": "B1"})
    return t


def _reply(slack: FakeSlack, thread: str, age: float = 60, **who: str) -> str:
    ts = f"{time.time() - age + len(slack.msgs) * 0.001:.6f}"
    slack.msgs.append({"ts": ts, "text": "새 답", "thread_ts": thread, **(who or {"user": HUMAN})})
    return ts


def _setup(env: Path, slack: FakeSlack, seen_age: float) -> str:
    """루트 10일 전 스레드 · 원장 seen[t] = 지금 − seen_age · 데몬 baseline 은 아주 옛날(실제 desk 사례)."""
    start(env, slack)
    t = _old_root(slack)
    _old_baseline(env)
    _set_seen(env, {t: f"{time.time() - seen_age:.6f}"})
    return t


def _bodies(env: Path) -> str:
    p = env / "comm" / "mailbox.jsonl"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def _replies_calls(slack: FakeSlack) -> int:
    return len([r for r in slack.requests if r[1].endswith("conversations.replies")])


def test_t1_new_reply_in_thread_whose_root_is_older_than_window_is_delivered_once(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    new = _reply(slack, t)
    assert run(env, slack).returncode == 0
    assert f"slack:{new}:" in _bodies(env)  # 루트가 7일 넘어도 «마지막 답 2일 전» 스레드의 새 답은 간다
    assert _state(env)["seen"][t] == new  # 다음 패스는 그 뒤 답만 읽는다
    (env / "comm" / "mailbox.jsonl").unlink()  # 좌석이 읽음
    assert run(env, slack).returncode == 0
    assert _bodies(env) == ""  # 다음 패스 0


def test_t2_thread_whose_last_reply_is_older_than_keep_is_skipped_and_said_so(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 20 * DAY)
    new = _reply(slack, t)
    r = run(env, slack)
    assert r.returncode == 0
    assert f"slack:{new}:" not in _bodies(env)  # 알려진 한계 — 14일 넘게 조용한 스레드는 더 읽지 않는다
    assert "오래된 스레드 건너뜀 1" in r.stdout  # 조용한 0 이 아니라 .out 에 1줄
    assert t not in _state(env)["seen"]  # 닫는 사건 — 건너뛴 스레드는 원장에서도 내린다(줄이 패스마다 반복되지 않게)


def test_t4_only_the_twenty_most_recent_old_threads_are_read_and_the_rest_are_counted(env: Path, slack: FakeSlack):
    start(env, slack)
    _old_baseline(env)
    threads = [_old_root(slack) for _ in range(25)]
    _set_seen(env, {t: f"{time.time() - (i + 1) * 3600:.6f}" for i, t in enumerate(threads)})  # 앞쪽일수록 최근 답
    news = [_reply(slack, t) for t in threads]
    r = run(env, slack)
    assert r.returncode == 0
    ledger = _state(env)["ledger"]
    assert [n in ledger for n in news] == [True] * 20 + [False] * 5  # 최근 답 순 20개만
    assert _replies_calls(slack) == 20
    assert "스레드 미확인 5" in r.stdout


def test_t5_failed_thread_read_is_retried_next_pass_without_moving_seen(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    before = _state(env)["seen"][t]
    new = _reply(slack, t)
    slack.drop_replies.add(t)
    r = run(env, slack)
    assert r.returncode == 0  # 그 스레드만 다음 패스로 — 데몬 전체를 멈추지 않는다
    assert "스레드 미확인 1" in r.stdout
    assert _state(env)["seen"][t] == before and _bodies(env) == ""  # 놓침 0 의 조건 — seen 을 옮기지 않는다
    slack.drop_replies.clear()
    assert run(env, slack).returncode == 0
    assert f"slack:{new}:" in _bodies(env)


def test_t6_bot_or_other_users_reply_is_not_delivered_but_moves_seen(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    bot = _reply(slack, t, bot_id="B1")
    assert run(env, slack).returncode == 0
    assert _bodies(env) == "" and _state(env)["seen"][t] == bot  # 같은 답을 패스마다 다시 조회하지 않는다
    other = _reply(slack, t, 30, user="U-OTHER")
    assert run(env, slack).returncode == 0
    assert _bodies(env) == "" and _state(env)["seen"][t] == other
