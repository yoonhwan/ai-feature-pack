"""R242 단계 2 — 루트가 7일 넘은 스레드에 온 새 답글을 원장 «seen»(마지막 답 시각)으로 찾아 읽는다.
반례 T1·T2·T4·T5·T6(T3 = 단계 1 시험) + 보탬 T7~T11(③ 는 60초에 1회 · 5개 · «마지막 확인 오래된 순» 순환)."""
import json
import time
from pathlib import Path

import test_byz_slack_mbox_inbound as base
from _slack_fakes import FakeSlack

env, slack = base.env, base.slack  # 픽스처 재사용
HUMAN, run, start, _old_baseline = base.HUMAN, base.run, base.start, base._old_baseline
DAY = 86400
EVERY = 61  # ③ 주기(60초)를 넘긴 다음 회 — 자식 프로세스 시계만 앞당긴다


def _state(env: Path) -> dict:
    return json.loads((env / "st" / "byz_slack_mbox_inbound.C1.json").read_text(encoding="utf-8"))


def _set(env: Path, key: str, rows: dict[str, str]) -> None:
    p = env / "st" / "byz_slack_mbox_inbound.C1.json"
    st = _state(env)
    p.write_text(json.dumps({**st, key: {**st.get(key, {}), **rows}}), encoding="utf-8")


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
    _set(env, "seen", {t: f"{time.time() - seen_age:.6f}"})
    return t


def _many(env: Path, slack: FakeSlack, n: int) -> list[str]:
    """③ 대상 n 개 — 앞쪽일수록 최근 답(1시간 간격)."""
    start(env, slack)
    _old_baseline(env)
    threads = [_old_root(slack) for _ in range(n)]
    _set(env, "seen", {t: f"{time.time() - (i + 1) * 3600:.6f}" for i, t in enumerate(threads)})
    return threads


def _at(env: Path, slack: FakeSlack, offset: float):
    r = run(env, slack, **base._clocked(env, offset))
    assert r.returncode == 0, r.stderr
    return r


def _bodies(env: Path) -> str:
    p = env / "comm" / "mailbox.jsonl"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def _calls(slack: FakeSlack) -> list[str]:
    """③ 의 replies 조회 순서(o="0" = 전달 경로의 루트 조회라 뺀다)."""
    return [ts for ts, o in slack.replies_oldest if o != "0"]


def test_t1_new_reply_in_thread_whose_root_is_older_than_window_is_delivered_once(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    before = _state(env)["seen"][t]
    new = _reply(slack, t)
    _at(env, slack, 0)
    assert f"slack:{new}:" in _bodies(env)  # 루트가 7일 넘어도 «마지막 답 2일 전» 스레드의 새 답은 간다
    assert _state(env)["seen"][t] == new
    (env / "comm" / "mailbox.jsonl").unlink()  # 좌석이 읽음
    _at(env, slack, EVERY)
    assert _bodies(env) == ""  # 다음 회 0
    assert [o for ts, o in slack.replies_oldest if ts == t and o != "0"] == [before, new]  # S2 — 회마다 «마지막 답 뒤» 만 읽는다


def test_t2_thread_whose_last_reply_is_older_than_keep_is_skipped_and_said_so(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 20 * DAY)
    new = _reply(slack, t)
    r = _at(env, slack, 0)
    assert f"slack:{new}:" not in _bodies(env)  # 알려진 한계 — 14일 넘게 조용한 스레드는 더 읽지 않는다
    assert "오래된 스레드 건너뜀 1" in r.stdout  # 조용한 0 이 아니라 .out 에 1줄
    assert t not in _state(env)["seen"]  # 닫는 사건 — 건너뛴 스레드는 원장에서도 내린다


def test_t4_only_five_threads_per_round_most_recent_first_and_the_round_is_reported(env: Path, slack: FakeSlack):
    threads = _many(env, slack, 25)
    news = [_reply(slack, t) for t in threads]
    r = _at(env, slack, 0)
    ledger = _state(env)["ledger"]
    assert [n in ledger for n in news] == [True] * 5 + [False] * 20  # 첫 회 = 최근 답 순 5개
    assert "③ 스레드 순환 확인 5/대상 25 · 한 바퀴 약 5분" in r.stdout


def test_t5_failed_thread_read_is_retried_next_round_without_moving_seen(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    before = _state(env)["seen"][t]
    new = _reply(slack, t)
    slack.drop_replies.add(t)
    r = _at(env, slack, 0)  # 그 스레드만 다음 회로 — 데몬 전체를 멈추지 않는다
    assert "스레드 미확인 1" in r.stdout
    assert _state(env)["seen"][t] == before and _bodies(env) == ""  # 놓침 0 의 조건 — seen 을 옮기지 않는다
    slack.drop_replies.clear()
    _at(env, slack, EVERY)
    assert f"slack:{new}:" in _bodies(env)


def test_t6_bot_or_other_users_reply_is_not_delivered_but_moves_seen(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 2 * DAY)
    bot = _reply(slack, t, bot_id="B1")
    _at(env, slack, 0)
    assert _bodies(env) == "" and _state(env)["seen"][t] == bot  # 같은 답을 회마다 다시 조회하지 않는다
    other = _reply(slack, t, 30, user="U-OTHER")
    _at(env, slack, EVERY)
    assert _bodies(env) == "" and _state(env)["seen"][t] == other


def test_t7_round_runs_once_per_sixty_seconds_not_every_ten_second_pass(env: Path, slack: FakeSlack):
    _many(env, slack, 148)
    got = []
    for off in (0, 10, 20, 30, 40, 50):
        n = len(_calls(slack))
        r = _at(env, slack, off)
        got.append(len(_calls(slack)) - n)
        assert ("③ 스레드 순환" in r.stdout) == (off == 0)  # .out 1줄은 ③ 회마다 1번
    assert got == [5, 0, 0, 0, 0, 0]


def test_t8_rotation_visits_every_thread_before_any_second_visit(env: Path, slack: FakeSlack):
    threads = _many(env, slack, 12)
    for off in (0, EVERY, 2 * EVERY):
        _at(env, slack, off)
    calls = _calls(slack)
    assert len(calls) == 15 and sorted(calls[:12]) == sorted(threads)  # 12개 전부 1회 · 2번째는 그 뒤


def test_t9_failed_thread_keeps_checked_and_comes_first_next_round(env: Path, slack: FakeSlack):
    threads = _many(env, slack, 6)
    slack.drop_replies.add(threads[0])
    _at(env, slack, 0)
    assert threads[0] not in _state(env).get("checked", {})  # 실패 = 확인 시각 그대로(없음)
    slack.drop_replies.clear()
    n = len(_calls(slack))
    _at(env, slack, EVERY)
    assert _calls(slack)[n] == threads[0]  # 다음 회 첫 자리


def test_t10_thread_dropped_from_seen_is_dropped_from_checked_too(env: Path, slack: FakeSlack):
    t = _setup(env, slack, 20 * DAY)
    _set(env, "checked", {t: f"{time.time() - 3 * DAY:.6f}"})
    _at(env, slack, 0)
    st = _state(env)
    assert t not in st["seen"] and t not in st["checked"]


def test_t11_old_ledger_without_checked_starts_with_the_five_most_recent(env: Path, slack: FakeSlack):
    threads = _many(env, slack, 7)
    assert "checked" not in _state(env)
    _at(env, slack, 0)
    assert _calls(slack) == threads[:5]
