"""ft_team_status_line.py --hil <N|?> [--root R] [--now EPOCH]  (r2255 → r2390 · desk 틱이 매 틱 1회 부름)

TEAM-STATUS.md 1행 = 칸 8개(r2390 K1) «자율 <ON A<N> <레벨>|OFF|?> · 오빠 답 기다림 <N>(가장 오래 <N>시간) · 스크립트 <N> ·
막힌 팀 <N> · planner [정리] <HH:MM>(<N>분 전) · 원장 낡음 <N>시간 · 오빠 지시 멈춤 <N> · 담당 없음 <N>»
  · 2행 = 칸마다 출처·잰 시각 1구 · 3행부터 바이트 그대로(r2255)
  · 칸 셈 = ft_desk_head_cells(K3) 한 곳 · 오빠 답 기다림 = r2389 ft_board_news_wait 같은 함수(K2)
  · 못 잰 칸은 0 대신 «?»(조용한 0 금지) · «인터뷰» 이름은 «오빠 답 기다림» 으로 바뀌었다(kind=question 만 세던 셈 0)
쓰기 = 같은 폴더 임시 파일 → os.replace · 권한 기존 그대로.
출력 = 1행 1줄 · rc0. 폴더 없음 · 쓰기 실패 = rc1 «판정 불가 …» 1줄(하드 룰 20) · 인자 오류 = rc2.
"""
from __future__ import annotations  # mini python 3.9.6

import os
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ft_desk_head_cells import UNKNOWN, cells  # noqa: E402

REL = Path(".fable-team") / "state"


def hhmm(t: float) -> str:
    return time.strftime("%H:%M", time.localtime(t))


def head(root: Path, hil: str, now: float) -> tuple:
    """(1행, 2행) — 1행 = K1 꼴 8칸 · 2행 = «설명: desk 틱 HH:MM · <칸마다 출처·잰 시각>»."""
    got = cells(root, hil, now)
    first = " · ".join(f"{name} {value}" for name, value, _ in got)
    second = "설명: desk 틱 " + hhmm(now) + " · " + " · ".join(f"{name} {where}" for name, _, where in got)
    return first, second


def write(f: Path, first: str, second: str) -> None:
    try:
        rest = f.read_bytes().split(b"\n", 2)
        tail = rest[2] if len(rest) > 2 else b""
        mode = f.stat().st_mode & 0o7777
    except FileNotFoundError:
        tail, mode = b"", 0o644
    data = (first + "\n" + second + "\n").encode("utf-8") + tail
    fd, tmp = tempfile.mkstemp(prefix=".TEAM-STATUS.", dir=str(f.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, f)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def parse(argv: list) -> tuple:
    opts = {"--hil": None, "--root": os.environ.get("FT_ROOT") or os.getcwd(), "--now": None}
    it = iter(argv)
    for a in it:
        if a not in opts:
            raise ValueError(a)
        opts[a] = next(it)
    hil = opts["--hil"]
    if hil is None or not (hil == UNKNOWN or hil.isdigit()):
        raise ValueError("--hil")
    now = float(opts["--now"]) if opts["--now"] is not None else time.time()
    return hil, Path(opts["--root"]), now


def main(argv: list) -> int:
    try:
        hil, root, now = parse(argv)
    except (ValueError, StopIteration):
        print("usage: ft_team_status_line.py --hil <N|?> [--root R] [--now EPOCH]", file=sys.stderr)
        return 2
    folder = root / REL / "planner-tick"
    if not folder.is_dir():
        print(f"판정 불가 — 폴더 없음 {folder}")
        return 1
    first, second = head(root, hil, now)
    try:
        write(folder / "TEAM-STATUS.md", first, second)
    except OSError as e:
        print(f"판정 불가 — 쓰기 실패 {e}")
        return 1
    print(first)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
