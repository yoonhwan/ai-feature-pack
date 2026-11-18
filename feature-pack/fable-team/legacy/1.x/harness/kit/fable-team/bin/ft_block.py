"""r2070 A1 — 막힘 장부(block.sh) 올리는 한 길 · 주기 점검 도구(ft_stall_scan · ft_teamset)가 줄을 만드는 자리에서 부른다.

block(<데이터 루트>, "raise"|"clear", …) — 장부 도구 = env FT_BLOCK_BIN › <데이터 루트>/.fable-team/state/ft20-r1483-watch/block.sh
  · 그 파일이 없거나 데이터 루트가 없으면 호출 0 · FT_CRITICAL_OFF=1 = 호출 0 · env FT20_SCAN_ROOT=<데이터 루트>
  · 상한 7초(하드 룰 12) · 출력은 버림 · 예외 0 · 반환값 없음 · --cause 글 = 첫 줄 · 160자 안
  · 한 실행에서 상한을 한 번 넘기면 그 실행의 남은 호출 0(점검 도구의 총 시간 예산 보호)
"""
from __future__ import annotations

import os
import signal
import subprocess
from pathlib import Path

LIMIT_S = 7
_stopped = False   # 이 실행에서 상한을 넘긴 적 있음 = 남은 호출 0


def block(root, op: str, *args: str) -> None:
    global _stopped
    try:
        if _stopped or os.environ.get("FT_CRITICAL_OFF") == "1" or not root or not Path(root).is_dir():
            return
        tool = os.environ.get("FT_BLOCK_BIN") or str(Path(root) / ".fable-team/state/ft20-r1483-watch/block.sh")
        if not os.path.isfile(tool):
            return
        a = [str(x) for x in args]
        for i in range(len(a) - 1):
            if a[i] == "--cause":
                a[i + 1] = (a[i + 1].splitlines() or [""])[0][:160]
        p = subprocess.Popen(["bash", tool, op, *a], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             env={**os.environ, "FT20_SCAN_ROOT": str(root)}, start_new_session=True)
        try:
            _ = p.wait(timeout=LIMIT_S)
        except subprocess.TimeoutExpired:
            _stopped = True
            try:
                os.killpg(p.pid, signal.SIGKILL)
            except OSError:
                pass
            try:
                _ = p.wait(timeout=1)
            except subprocess.TimeoutExpired:
                pass
    except Exception:   # 장부는 곁가지 — 부른 쪽 판정·출력·rc 를 바꾸지 않는다(A5)
        return
