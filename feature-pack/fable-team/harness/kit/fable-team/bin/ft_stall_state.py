# pyright: basic
"""R320b — ft_stall_scan 상태 파일·중복 실행 잠금·자기 로그 10분 가드.

stall-scan.json = {handled: {좌석: 처리 시각}, prev: [지난 실행 감지 키], seats: {좌석 캐시 — ft_stall_seats}}.
launchd 가 120초마다 1회 실행하므로 앞 실행이 아직 돌면(첫 실행·압력 시 느림) 새 실행은 조용히 건너뛴다(rc 0 · 한 줄).
"""
import fcntl
import json
import time
from contextlib import contextmanager
from pathlib import Path

REPEAT_S = 600


def load(state_dir: Path) -> dict:
    try:
        return json.loads((state_dir / "stall-scan.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save(state_dir: Path, handled: dict, prev: list[str], seats: dict) -> None:
    state_dir.mkdir(parents=True, exist_ok=True)
    _ = (state_dir / "stall-scan.json").write_text(json.dumps({"handled": handled, "prev": prev, "seats": seats}), encoding="utf-8")


def recent_in_log(state_dir: Path, seat: str, now: float) -> bool:
    """ft-mbox ring 의 outstanding 억제를 우회하므로 자기 로그(act=… to=<좌석>)도 본다 — 10분 안에 처리했으면 True."""
    try:
        tail = (state_dir / "stall-scan.log").read_text(encoding="utf-8").splitlines()[-400:]
    except OSError:
        return False
    for line in tail:
        if f" to={seat} " in line + " ":
            try:
                if now - time.mktime(time.strptime(line[:19], "%Y-%m-%dT%H:%M:%S")) < REPEAT_S:
                    return True
            except ValueError:
                continue
    return False


@contextmanager
def single_run(state_dir: Path):
    """한 번에 한 실행 — 잠금이 잡혀 있으면 None."""
    state_dir.mkdir(parents=True, exist_ok=True)
    with open(state_dir / "stall-scan.lock", "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            yield False
            return
        yield True
