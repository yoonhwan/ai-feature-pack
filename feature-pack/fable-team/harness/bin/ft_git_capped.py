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


_CUR: "subprocess.Popen[bytes] | None" = None   # 지금 도는 자식 — 바깥이 SIGTERM 으로 끊으면 핸들러가 이 그룹까지 정리한다


def _once(cmd: list[str], lim: float) -> tuple[int, bytes]:
    global _CUR
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return 128, b""
    _CUR = p
    try:
        out, _e = p.communicate(timeout=lim)
        return p.returncode, out or b""
    except subprocess.TimeoutExpired:
        _kill_group(p)
        return 124, b""
    finally:
        _CUR = None


def run(repo: str, args: list[str] | tuple[str, ...], lim: float = 7.0) -> tuple[int, bytes]:
    """git 1회 = lim 초 상한 · 시간 초과(rc124)만 재시도 RETRIES 회 · 그 밖 rc·stdout 은 git 그대로."""
    rc = 128
    for _ in range(RETRIES + 1):
        rc, out = _once(["git", "-C", repo, *args], lim)
        if rc != 124:
            return rc, out
    return rc, b""


def run_cmd(cmd: list[str], lim: float) -> tuple[int, bytes]:
    """아무 명령 1회 = lim 초 상한(재시도 없음) · 초과면 그 명령의 프로세스 그룹까지 정리하고 rc124 (r937 astra r1 · 바깥 상한용)."""
    return _once(cmd, lim)


def _on_term(signum: int, _frame: object) -> None:
    if _CUR is not None:   # 이미 끊기는 중 — 유예 없이 바로 SIGKILL(바깥의 0.5초 유예 안에 끝낸다)
        try:
            os.killpg(_CUR.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    sys.exit(128 + signum)


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        print("usage: ft_git_capped.py <초> <리포> <git 인자…>", file=sys.stderr)
        return 128
    try:
        lim = float(argv[1])
    except ValueError:
        print("ft_git_capped.py: 초가 숫자가 아니다: " + argv[1], file=sys.stderr)
        return 128
    signal.signal(signal.SIGTERM, _on_term)
    rc, out = run(argv[2], argv[3:], lim)
    sys.stdout.buffer.write(out)
    sys.stdout.buffer.flush()
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
