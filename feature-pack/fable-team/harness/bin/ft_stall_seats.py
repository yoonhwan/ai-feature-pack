# pyright: basic
"""R320b — 좌석 상태 캐시 (ft_stall_scan 용). 실측: 64좌석 전수 `ft-seat-status.sh turn` = 130초·CPU 86초(좌석마다 jsonl 후보 1MB 머리 전수 읽기).

경로(jsonl 해석)는 좌석마다 30분(+좌석별 0~10분 분산)에 1번만 풀고, 그 사이는 파일 mtime 이 같으면 지난 판정을 그대로 쓴다
(턴 끝은 turn_duration 기록 = mtime 이 바뀐다 → mtime 불변 = 상태 불변). 후보(b·d·a)로 걸린 좌석은 `force` 로 경로까지 다시 푼다(새 jsonl 로 이어진 좌석 오탐 방지).
캐시 한계: 새 jsonl 로 옮겨 간 좌석은 후보가 되기 전까지 옛 파일을 본다 — 최대 40분 늦게 보인다(오탐이 아니라 미탐 방향).
"""
import os
import zlib
from pathlib import Path
from typing import Any

from ft_stall_detect import last_turn, run, turn_info

TTL_S = 1800


class Seats:
    def __init__(self, status_cmd: str, now: float, cache: dict[str, Any]):
        self.status, self.now, self.cache = status_cmd, now, cache

    def _resolve(self, seat: str) -> str:
        rc, out = run(["bash", self.status, "jsonl", seat])
        return out.strip() if rc == 0 else ""

    def info(self, seat: str, force: bool = False) -> dict[str, Any]:
        c = self.cache.get(seat)
        ttl = TTL_S + zlib.crc32(seat.encode()) % 600
        if c is None or force or self.now - c["resolved"] > ttl:
            path, resolved = self._resolve(seat), self.now
        else:
            path, resolved = c["path"], c["resolved"]
        mtime = os.stat(path).st_mtime if path and Path(path).exists() else None
        if c and not force and path and c["path"] == path and c["mtime"] == mtime and c.get("state"):
            return c
        if path and mtime is not None:
            state, end = turn_info(self.status, seat, path)
            flags = last_turn(path)
        else:
            state, end = turn_info(self.status, seat)  # jsonl 없는 좌석(codex·cmd 등) — ft-seat-status 가 pane 으로 판정
            flags, path = {"rest": False, "future": False}, ""
        c = dict(path=path, mtime=mtime, resolved=resolved, state=state, end=end, **flags)
        self.cache[seat] = c
        return c
