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
import time

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
    _wait_group_gone(p.pid)


def _wait_group_gone(pgid: int) -> None:
    """SIGKILL 직후 그룹의 프로세스가 사라질 때까지 최대 1초 확인 — 반환 순간 자식 생존 0 을 보장한다."""
    for _ in range(100):
        try:
            os.killpg(pgid, 0)
        except (ProcessLookupError, PermissionError):
            return
        time.sleep(0.01)


_CUR: "subprocess.Popen[bytes] | None" = None   # 지금 도는 자식 — 바깥이 SIGTERM 으로 끊으면 핸들러가 이 그룹까지 정리한다


def _once(cmd: list[str], lim: float) -> tuple[int, bytes, bool]:
    """(rc, stdout, 실제 시간 초과 여부) — 시간 초과 표시는 세 번째 값뿐이다(git 자신이 낸 rc124 와 섞이지 않는다)."""
    global _CUR
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return 128, b"", False
    _CUR = p
    try:
        out, _e = p.communicate(timeout=lim)
        return p.returncode, out or b"", False
    except subprocess.TimeoutExpired:
        _kill_group(p)
        return 124, b"", True
    finally:
        _CUR = None


def run(repo: str, args: list[str] | tuple[str, ...], lim: float = 7.0) -> tuple[int, bytes]:
    """git 1회 = lim 초 상한 · 실제 시간 초과만 재시도 RETRIES 회(총 ≤ 2회) · 그 밖 rc·stdout 은 git 그대로(git 의 rc124 도)."""
    rc = 128
    for _ in range(RETRIES + 1):
        rc, out, timed_out = _once(["git", "-C", repo, *args], lim)
        if not timed_out:   # git 자신의 종료 코드(124 포함)는 그대로 · 출력도 보존 — 재시도는 «실제 시간 초과» 만
            return rc, out
    return rc, b""


def run_cmd(cmd: list[str], lim: float) -> tuple[int, bytes]:
    """아무 명령 1회 = lim 초 상한(재시도 없음) · 초과면 그 명령의 프로세스 그룹까지 정리하고 rc124 (r937 astra r1 · 바깥 상한용)."""
    rc, out, _to = _once(cmd, lim)
    return rc, out


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
