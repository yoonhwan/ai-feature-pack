#!/usr/bin/env python3
"""ft 2.0 legacy guard — ft2/ 가 1.x 도구를 실행·import·source 하는 줄을 찾는다.

검사 대상 = ft2/ 아래 .py .sh .ts .js .json.
허용 = *.md(산문) · 이 검사기 자신(규칙 표가 자기 규칙에 걸리지 않게) · 아래 ALLOW 표(카드에 적힌 다리만).
코드 파일 주석도 검사한다 — 주석 처리된 1.x 경로는 다음 사람이 되살린다.
ALLOW 는 파일·패턴·상한 줄 수로 센다. 넘치면 ALLOW-OVER, 다리를 걷어 0줄이면 ALLOW-STALE 로 찍는다.
종료 코드: 0 = 위반 0 · 1 = 위반 있음 · 2 = 사용법·경로 오류.
"""
import os
import sys

PATTERNS = (
    "legacy/1.x",
    "harness/bin",
    "harness/kit",
    "LIVE_BIN",
    ".fable-team/bin",
)
SUFFIXES = (".py", ".sh", ".ts", ".js", ".json")
SELF = os.path.abspath(__file__)
GUARD_REL = "tools/legacy_guard.py"   # 자기 자신 — 사본으로 풀린 트리에서도 검사에서 뻗다
# r2383 K1 — 다리로 남긴 1.x 호출만 보이게 허용한다.
# (ft2 기준 relpath, 패턴, 상한 줄 수, 카드, 이유) · relpath 는 정확 일치(이름만 같은 다른 폴더 = 허용 아님).
ALLOW = (
    ("adapters/pi/keeper_land.py", "LIVE_BIN", 1, "r2307", ":60 lib_mark 의 설치본 폴더 파일 읽기"),
    ("adapters/pi/keeper_next.py", ".fable-team/bin", 1, "r2182", ":488 FIX 안내 문구"),
)


def scan_targets(root):
    """검사할 파일 경로를 이름 순서로 돌려준다."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(SUFFIXES):
                continue
            path = os.path.join(dirpath, name)
            if os.path.relpath(path, root) == GUARD_REL:
                continue
            yield path


def scan_file(path, root):
    """파일 한 개에서 패턴이 걸린 줄을 (relpath, 줄, 패턴) 으로 돌려준다."""
    hits = []
    rel = os.path.relpath(path, root)
    with open(path, encoding="utf-8", errors="replace") as handle:
        for lineno, line in enumerate(handle, 1):
            for pattern in PATTERNS:
                if pattern in line:
                    hits.append((rel, lineno, pattern))
    return hits


def judge(hits, root):
    """ALLOW 상한 안의 줄은 빼고, 넘침·남음을 덧붙여 찍을 줄을 만든다.
    남음(STALE)은 표가 이 트리에 대한 것일 때(ALLOW 줄 하나라도 살아 있을 때)만 본다 — 표와 상관없는 가짜 트리에서 헛줄을 내지 않는다."""
    caps = {(rel, pattern): cap for rel, pattern, cap, _card, _why in ALLOW}
    counted = {}
    for rel, _lineno, pattern in hits:
        counted[(rel, pattern)] = counted.get((rel, pattern), 0) + 1
    alive = any(counted.get((rel, pattern), 0) for rel, pattern, _cap, _card, _why in ALLOW)
    lines = []
    for rel, lineno, pattern in hits:
        cap = caps.get((rel, pattern))
        if cap is not None and counted[(rel, pattern)] <= cap:
            continue
        lines.append(f"{rel}:{lineno}: {pattern}")
    for rel, pattern, cap, _card, _why in ALLOW:
        got = counted.get((rel, pattern), 0)
        if got > cap:
            lines.append(f"ALLOW-OVER {rel} {pattern} {got}/{cap}")
        elif got == 0 and alive:
            lines.append(f"ALLOW-STALE {rel} {pattern}")
    return lines


def main(argv):
    if len(argv) > 2:
        print("usage: legacy_guard.py [ft2 dir]", file=sys.stderr)
        return 2
    root = argv[1] if len(argv) == 2 else os.path.dirname(os.path.dirname(SELF))
    if not os.path.isdir(root):
        print(f"legacy_guard: not a directory: {root}", file=sys.stderr)
        return 2
    hits = []
    for path in scan_targets(root):
        hits.extend(scan_file(path, root))
    lines = judge(hits, root)
    for finding in lines:
        print(finding)
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
