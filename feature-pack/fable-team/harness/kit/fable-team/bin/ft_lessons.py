#!/usr/bin/env python3
"""ft_lessons.py — 3계층 LESSONS(좌석 → 팀 → 전역 다이제스트) + 파일 락. r1433.

설계 근거: hermes 는 MEMORY.md / USER.md + <파일>.lock 로 기억을 다룬다. fable-team 은 계층이 3개다.
  좌석 LESSONS  ≤ 2,048 B   <FT_ROOT>/state/lessons/seat/<좌석이름>.md
  팀 LESSONS    ≤ 4,096 B   <FT_ROOT>/state/lessons/team/<팀>.md
  전역 다이제스트 ≤ 2,048 B   ~/.claude/rules/dumb-time-digest.md   (읽기 전용 — 갱신 규칙은 guides/dumb-time.md)
계층 규칙: 좌석에서 3번 되풀이된 교훈만 팀으로 올리고, 팀에서 팀을 넘어 되풀이된 것만 전역으로 올린다.
  올리는 판단은 사람·팀장이 한다(자동 승격 없음 — 잘못된 일반화가 전 좌석에 퍼지는 것을 막는다).
락: <파일>.lock 을 fcntl.flock 으로 7초 대기. 못 잡으면 rc3 «판정 불가» 1줄(하드 룰 20).
종료코드: 0 정상 · 3 락/판정 불가 · 2 usage · 1 상한 위반(check)
"""
from __future__ import annotations

import datetime as dt
import fcntl
import os
import re
import sys
from pathlib import Path

LIMITS = {"seat": 2048, "team": 4096, "global": 2048}
LOCK_WAIT = 7.0
GLOBAL_DIGEST = Path.home() / ".claude" / "rules" / "dumb-time-digest.md"


def die(msg: str, rc: int = 2) -> None:
    print(msg)
    sys.exit(rc)


def ft_root() -> Path:
    env = os.environ.get("FT_ROOT")
    if env:
        return Path(env)
    cwd = Path.cwd()
    for p in [cwd, *cwd.parents]:
        if (p / ".fable-team").is_dir():
            return p / ".fable-team"
    die("REJECT .fable-team 없음 — FT_ROOT 를 지정하라")


def safe(name: str) -> str:
    n = re.sub(r"[^A-Za-z0-9._#-]+", "-", name.strip())
    if not n:
        die("REJECT 이름이 비었다")
    return n


def global_lock() -> Path:
    return ft_root() / "state" / "lessons" / "global.md.lock"


def path_of(layer: str, name: str | None) -> Path:
    if layer == "global":
        return GLOBAL_DIGEST
    if not name:
        die("REJECT %s 계층은 이름이 필요하다" % layer)
    base = ft_root() / "state" / "lessons" / layer
    return base / (safe(name) + ".md")


class Lock:
    def __init__(self, target: Path):
        self.lock = target.with_suffix(target.suffix + ".lock")

    def __enter__(self):
        self.lock.parent.mkdir(parents=True, exist_ok=True)
        self.fh = open(self.lock, "a+", encoding="utf-8")
        end = dt.datetime.now().timestamp() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(self.fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if dt.datetime.now().timestamp() > end:
                    self.fh.close()
                    die("판정 불가 락 못 잡음(%.0fs): %s" % (LOCK_WAIT, self.lock), 3)
                import time

                time.sleep(0.1)

    def __exit__(self, *exc):
        try:
            fcntl.flock(self.fh, fcntl.LOCK_UN)
        finally:
            self.fh.close()


def read_lines(p: Path) -> list[str]:
    if not p.is_file():
        return []
    return p.read_text(encoding="utf-8").splitlines()


def size_of(p: Path) -> int:
    return p.stat().st_size if p.is_file() else 0


def compact(p: Path, limit: int) -> tuple[int, Path | None]:
    """상한을 넘으면 오래된 줄을 archive 로 옮긴다(절반 유지). (옮긴 줄 수, 아카이브 경로)"""
    if size_of(p) <= limit:
        return 0, None
    lines = read_lines(p)
    keep_n = max(1, len(lines) // 2)
    moved, keep = lines[:-keep_n], lines[-keep_n:]
    arc = p.with_suffix(".archive-%s.md" % dt.date.today().strftime("%Y%m%d"))
    with open(arc, "a", encoding="utf-8") as f:
        f.write("\n".join(moved) + "\n")
    p.write_text("\n".join(keep) + "\n", encoding="utf-8")
    return len(moved), arc


def cmd_init(argv: list[str]) -> int:
    root = ft_root()
    n = 0
    lk = global_lock()
    lk.parent.mkdir(parents=True, exist_ok=True)
    if not lk.exists():
        lk.touch()
        n += 1
    for layer, lim in LIMITS.items():
        if layer == "global":
            continue
        d = root / "state" / "lessons" / layer
        d.mkdir(parents=True, exist_ok=True)
        for f in d.glob("*.md"):
            lk = f.with_suffix(f.suffix + ".lock")
            if not lk.exists():
                lk.touch()
                n += 1
    print("INIT lessons seat≤2048 team≤4096 global≤2048 합계상한=8192 new-lock=%d root=%s" % (n, root / "state" / "lessons"))
    return 0


def cmd_check(argv: list[str]) -> int:
    root = ft_root()
    bad = 0
    rows = []
    for layer, lim in LIMITS.items():
        d = root / "state" / "lessons" / layer
        if layer == "global":
            files = [GLOBAL_DIGEST]
        else:
            files = [f for f in sorted(d.glob("*.md")) if ".archive-" not in f.name] if d.is_dir() else []
            if not d.is_dir():
                rows.append("MISSING %-6s 폴더 없음 %s (ft-lessons.sh init)" % (layer, d))
                bad += 1
        if layer != "global" and d.is_dir() and not files:
            continue
        for f in files:
            sz = size_of(f)
            lk = global_lock() if layer == "global" else f.with_suffix(f.suffix + ".lock")
            state = "OK" if sz <= lim else "OVER"
            lock = "lock" if lk.is_file() else "NO-LOCK"
            if state != "OK" or lock != "lock":
                bad += 1
            rows.append("%-5s %-6s %5d/%-5d %s %s" % (state, layer, sz, lim, lock, f))
    for r in rows:
        print(r)
    total = sum(size_of(f) for layer in LIMITS for f in ([GLOBAL_DIGEST] if layer == "global" else [x for x in sorted((root / "state" / "lessons" / layer).glob("*.md")) if ".archive-" not in x.name])) if root else 0
    print("CHECK lessons 계층파일=%d 위반=%d 상한(seat 2048 · team 4096 · global 2048) 합계=%d" % (len(rows), bad, total))
    return 0 if bad == 0 else 1


def cmd_path(argv: list[str]) -> int:
    if not argv:
        die("usage: path <seat|team|global> [이름]")
    layer = argv[0]
    if layer not in LIMITS:
        die("REJECT 계층은 seat|team|global")
    print(path_of(layer, argv[1] if len(argv) > 1 else None))
    return 0


def cmd_add(argv: list[str]) -> int:
    if len(argv) < 3:
        die('usage: add <seat|team> <이름> "1줄"')
    layer, name, text = argv[0], argv[1], " ".join(argv[2:])
    if layer not in ("seat", "team"):
        die("REJECT add 는 seat|team 만 — 전역 다이제스트는 guides/dumb-time.md 규칙으로 사람이 갱신한다")
    p = path_of(layer, name)
    lim = LIMITS[layer]
    with Lock(p):
        p.parent.mkdir(parents=True, exist_ok=True)
        line = "- [%s] %s" % (dt.date.today().strftime("%m-%d"), text.replace("\n", " ").strip())
        with open(p, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        sz = size_of(p)
        moved, arc = (0, None)
        if sz > lim:
            moved, arc = compact(p, lim)
    print("ADD %s %s %d/%d %s" % (layer, p.name, size_of(p), lim, "OK" if size_of(p) <= lim else "OVER"))
    if arc:
        print("SPLIT %s 상한 초과 → 오래된 %d줄 자동 분리(a) %s" % (layer, moved, arc))
    return 0


def cmd_read(argv: list[str]) -> int:
    if len(argv) < 2:
        die("usage: read <seat|team> <이름> [--all]")
    p = path_of(argv[0], argv[1])
    lines = read_lines(p)
    if not lines:
        print("EMPTY %s" % p)
        return 0
    show = lines if "--all" in argv else lines[-20:]
    print("READ %s (%d줄 · %dB)" % (p, len(lines), size_of(p)))
    for l in show:
        print(l)
    return 0


def cmd_compact(argv: list[str]) -> int:
    if len(argv) < 2:
        die("usage: compact <seat|team> <이름>")
    layer, name = argv[0], argv[1]
    p = path_of(layer, name)
    with Lock(p):
        moved, arc = compact(p, LIMITS[layer])
    if not arc:
        print("COMPACT %s %d/%d 이미 상한 안" % (p, size_of(p), LIMITS[layer]))
        return 0
    print("COMPACT %s %d/%d 오래된 %d줄 → %s" % (p, size_of(p), LIMITS[layer], moved, arc))
    return 0


CMDS = {"init": cmd_init, "check": cmd_check, "path": cmd_path, "add": cmd_add, "read": cmd_read, "compact": cmd_compact}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip().splitlines()[0])
        print("usage: ft-lessons.sh {init|check|path|add|read|compact} …")
        return 0 if len(sys.argv) > 1 else 2
    fn = CMDS.get(sys.argv[1])
    if not fn:
        die("REJECT 모르는 명령: %s (init|check|path|add|read|compact)" % sys.argv[1])
    return fn(sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
