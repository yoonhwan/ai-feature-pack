"""r2380 (앞 갈래 ⑥~⑬) — ft-stall-scan 이 6시간 넘은 «오빠 대기» 를 «사람 대기 점검» 으로 세고, 줄이 풀려 지워지면 «사람 대기 풀림» 을 desk 에 1통 보낸다.

c06 ⑦ 6시간 넘으면 팀 master 에 1통(thread ts 포함) · c07 6시간 안 = 0통 · c08 같은 사건 두 번째 실행 = 0통
c09 다른 선행이 진행 카드를 가리키면(blocked) 0통 · c10 «확인 <시각>» 줄이 이기면 0통 · c11 확인 줄이 앞날이면 0통
c12 점검 뒤 선행 줄이 지워지면 «사람 대기 풀림» 1통 · c13 그 1통은 desk 에 가고 thread ts + «결과 1줄» 을 담는다
나머지 갈래(c14~c20) = test_stall_human_wait_b_r2380.py
"""
from datetime import datetime
from pathlib import Path

import pytest

from _stall_world import NOW, World
from real_state_guard import guard_begin_module  # noqa: F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)
from _r2380_world import (BIN, HUMAN, PLAIN, TS, desk, human, make_repo, put, scan, shim_git)  # noqa: F401


@pytest.fixture
def w(tmp_path: Path) -> World:
    return World(tmp_path)


def test_c06_six_hours_over_alerts_master(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    r = scan(w)
    hits = human(w, "사람 대기 점검")
    assert len(hits) == 1 and hits[0].startswith("send|t1-master#1|"), (hits, r.stdout, r.stderr)
    assert TS in hits[0], hits[0]


def test_c07_under_six_hours_is_quiet(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 2})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c08_same_event_twice_is_one_message(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    _ = scan(w)
    _ = scan(w)
    assert len(human(w, "사람 대기 점검")) == 1, human(w, "사람 대기 점검")


def test_c09_blocked_prereq_beats_human_wait(w: World) -> None:
    body = f"# h\n- 선행: indices/진행/z.md\n- 선행: 오빠 승인 대기 (thread {TS})\n"
    make_repo(w, "t1", {"대기/h.md": body, "진행/z.md": "# z\n- 선행: 없음\n"}, {"대기/h.md": 7})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c10_confirm_line_wins(w: World) -> None:
    stamp = datetime.fromtimestamp(NOW - 3600).strftime("%Y-%m-%d %H:%M")  # 1시간 전에 «아직 대기» 확인
    make_repo(w, "t1", {"대기/h.md": f"# h\n- 확인: {stamp}\n" + HUMAN.split("\n", 1)[1]}, {"대기/h.md": 7})
    r = scan(w)  # 카드 커밋은 7시간 전이지만 확인 줄이 더 최근이면 나이 0(⑩)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c11_future_confirm_line_is_quiet(w: World) -> None:
    stamp = datetime.fromtimestamp(NOW + 7200).strftime("%Y-%m-%d %H:%M")  # 앞날 확인 줄 = 나이 음수(⑪)
    make_repo(w, "t1", {"대기/h.md": f"# h\n- 확인: {stamp}\n" + HUMAN.split("\n", 1)[1]}, {"대기/h.md": 7})
    r = scan(w)
    assert not human(w, "사람 대기"), (human(w, "사람 대기"), r.stdout)


def test_c12_resolved_line_sends_done_once(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, (human(w, "사람 대기 풀림"), r.stdout)
    _ = scan(w)
    assert len(human(w, "사람 대기 풀림")) == 1, human(w, "사람 대기 풀림")  # 기록을 지웠으니 다시 0통


def test_c13_done_message_goes_to_desk_with_thread_ts(w: World) -> None:
    make_repo(w, "t1", {"대기/h.md": HUMAN}, {"대기/h.md": 7})
    desk(w)
    _ = scan(w)
    put(w, "t1", "대기/h.md", PLAIN)
    r = scan(w)
    hits = human(w, "사람 대기 풀림")
    assert len(hits) == 1 and hits[0].startswith("send|t1-desk#9|"), (hits, r.stdout)
    assert TS in hits[0] and "결과 1줄" in hits[0], hits[0]


