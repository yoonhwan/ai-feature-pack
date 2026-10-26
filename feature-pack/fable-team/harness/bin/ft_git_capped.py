#!/usr/bin/env python3
"""ft_git_capped.py <초> <리포> <git 인자…> — git 조회 1회를 «초» 상한으로 돌린다 (r937 r3 · 외부 호출 7초 룰).
  git 은 새 세션(프로세스 그룹)에서 돈다. 시간 초과면 그룹에 SIGTERM → 0.5초 뒤 SIGKILL(자식 git·sleep 까지 정리) → 1회 재시도 → 또 초과면 rc 124.
  rc·stdout 은 git 그대로 · 실행 실패(git 없음 등) = rc 128 · stderr 는 버린다. bash 3.2·timeout/gtimeout 유무와 무관(python3 는 하네스 필수 의존).
  모듈로도 쓴다: run(repo, args, lim) -> (rc, stdout 바이트)."""
from __future__ import annotations

import os
import signal
import subprocess
import sys

RETRIES = 1
GRACE = 0.5


def _kill_group(p: "subprocess.Popen[bytes]") -> None:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(p.pid, sig)
        except (ProcessLookupError, PermissionError):
            pass
        if sig == signal.SIGTERM:
            try:
                p.wait(GRACE)
            except subprocess.TimeoutExpired:
                pass
    try:
        p.communicate(timeout=2)
    except (subprocess.TimeoutExpired, ValueError):
        pass


def run(repo: str, args: list[str] | tuple[str, ...], lim: float = 7.0) -> tuple[int, bytes]:
    rc = 128
    for _ in range(RETRIES + 1):
        try:
            p = subprocess.Popen(["git", "-C", repo, *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 stdin=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            return 128, b""
        try:
            out, _e = p.communicate(timeout=lim)
            return p.returncode, out or b""
        except subprocess.TimeoutExpired:
            _kill_group(p)
            rc = 124
    return rc, b""


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("usage: ft_git_capped.py <초> <리포> <git 인자…>", file=sys.stderr)
        return 128
    try:
        lim = float(argv[1])
    except ValueError:
        print("ft_git_capped.py: 초가 숫자가 아니다: " + argv[1], file=sys.stderr)
        return 128
    rc, out = run(argv[2], argv[3:], lim)
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
