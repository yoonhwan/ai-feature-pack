"""r638 — `Scan.wake()` 는 깨우기 직전 IDLE 나이를 «한 번만» 새로 읽어 판정한다.

옛 판: `idle_age(seat, fresh=True) is None or idle_age(seat) < IDLE_MIN` — 새로 읽기(IDLE)와 캐시 읽기(WORKING)가 어긋나면
둘째가 None → `None < float` TypeError 로 감시 전체가 죽었다(launchd com.byz.ft-stall-scan 12:48~ 연속 exit 1).
가짜 seats.info(force 에 따라 다른 값) · 가짜 tmux·mbox 스크립트(로그만) — 실 좌석·ring 0.
"""
import stat
import sys
from pathlib import Path

import pytest

from _stall_world import BIN
from real_state_guard import guard_begin_module  # noqa: E402,F401  r541: 실 상태 지문 + git 밖 cwd(모듈 autouse)

sys.path.insert(0, str(BIN))
import ft_stall_scan  # noqa: E402
from ft_stall_detect import IDLE_MIN  # noqa: E402

NOW = 1_800_000_000.0
SEAT = "t1-nano#0"


class FakeSeats:
    """force=True(새로 읽기)와 force=False(캐시)가 서로 다른 값을 돌려주는 가짜 — 그 사이 좌석이 IDLE↔WORKING 된 경우."""

    def __init__(self, fresh: tuple[str, float], cached: tuple[str, float]):
        self.fresh, self.cached = fresh, cached
        self.calls: list[bool] = []

    def info(self, seat: str, force: bool = False) -> dict:
        self.calls.append(force)
        state, mins = self.fresh if force else self.cached
        return {"state": state, "end": NOW - mins * 60, "rest": False, "future": False}


def _exe(path: Path, body: str) -> str:
    _ = path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return str(path)


def make_scan(tmp_path: Path, fresh: tuple[str, float], cached: tuple[str, float], attached: int = 0) -> ft_stall_scan.Scan:
    log = tmp_path / "act.log"
    tmux = _exe(tmp_path / "tmux.sh", f'#!/bin/sh\ncase "$1" in\n  list-panes) echo "{SEAT}|%1";;\n  send-keys) echo "tmux $*" >> "{log}";;\nesac\n')
    mbox = _exe(tmp_path / "mbox.sh", f'#!/bin/sh\necho "mbox $*" >> "{log}"\n')
    s = object.__new__(ft_stall_scan.Scan)
    s.now, s.tmux, s.mbox = NOW, ["bash", tmux], mbox
    s.seats = FakeSeats(fresh, cached)
    s.sessions = lambda: {SEAT: attached}  # type: ignore[method-assign]
    s.live = s.sessions()
    return s


def acts(tmp_path: Path) -> list[str]:
    p = tmp_path / "act.log"
    return p.read_text().splitlines() if p.exists() else []


def test_a_fresh_idle_old_cache_working_wakes_without_typeerror(tmp_path: Path) -> None:  # ⓐ 옛 판 = TypeError
    s = make_scan(tmp_path, fresh=("IDLE", IDLE_MIN + 7), cached=("WORKING", 0))
    assert s.wake(SEAT, None) is True
    assert s.seats.calls == [True]  # 새로 읽기 1번 · 캐시 다시 읽기 0
    assert acts(tmp_path) == ["tmux send-keys -t %1 Escape", f"mbox ring {SEAT}"]


def test_b_fresh_working_does_not_wake(tmp_path: Path) -> None:  # ⓑ
    s = make_scan(tmp_path, fresh=("WORKING", 0), cached=("IDLE", IDLE_MIN + 7))
    assert s.wake(SEAT, 5) is False
    assert acts(tmp_path) == []


def test_c_fresh_idle_young_does_not_wake_even_if_cache_old(tmp_path: Path) -> None:  # ⓒ 옛 판 = 캐시(오래됨)로 깨움
    s = make_scan(tmp_path, fresh=("IDLE", IDLE_MIN / 3), cached=("IDLE", IDLE_MIN + 7))
    assert s.wake(SEAT, 5) is False
    assert acts(tmp_path) == []


def test_d_fresh_and_cache_idle_old_wakes_once_with_seq(tmp_path: Path) -> None:  # ⓓ 지금처럼 Escape·ring 1회
    s = make_scan(tmp_path, fresh=("IDLE", IDLE_MIN + 7), cached=("IDLE", IDLE_MIN + 7))
    assert s.wake(SEAT, 7) is True
    assert acts(tmp_path) == ["tmux send-keys -t %1 Escape", f"mbox ring {SEAT} 7"]


@pytest.mark.parametrize("fresh", [("IDLE", IDLE_MIN + 7), ("WORKING", 0)])
def test_attached_seat_never_woken(tmp_path: Path, fresh: tuple[str, float]) -> None:
    s = make_scan(tmp_path, fresh=fresh, cached=("IDLE", IDLE_MIN + 7), attached=1)
    assert s.wake(SEAT, None) is False
    assert acts(tmp_path) == []
