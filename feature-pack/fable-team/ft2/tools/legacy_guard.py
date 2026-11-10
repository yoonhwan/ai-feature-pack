#!/usr/bin/env python3
"""ft 2.0 legacy guard — ft2/ 가 1.x 도구를 실행·import·source 하는 줄을 찾는다.

검사 대상 = ft2/ 아래 .py .sh .ts .js .json.
허용 = *.md(산문) 와 이 검사기 자신(규칙 표가 자기 규칙에 걸리지 않게).
코드 파일 주석도 검사한다 — 주석 처리된 1.x 경로는 다음 사람이 되살린다.
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


def scan_targets(root):
    """검사할 파일 경로를 이름 순서로 돌려준다."""
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith(SUFFIXES):
                continue
            path = os.path.join(dirpath, name)
            if os.path.abspath(path) == SELF:
                continue
            yield path


def scan_file(path, root):
    """파일 한 개에서 패턴이 걸린 줄을 `<파일>:<줄>: <패턴>` 꼴로 돌려준다."""
    findings = []
    rel = os.path.relpath(path, root)
    with open(path, encoding="utf-8", errors="replace") as handle:
        for lineno, line in enumerate(handle, 1):
            for pattern in PATTERNS:
                if pattern in line:
                    findings.append(f"{rel}:{lineno}: {pattern}")
    return findings


def main(argv):
    if len(argv) > 2:
        print("usage: legacy_guard.py [ft2 dir]", file=sys.stderr)
        return 2
    root = argv[1] if len(argv) == 2 else os.path.dirname(os.path.dirname(SELF))
    if not os.path.isdir(root):
        print(f"legacy_guard: not a directory: {root}", file=sys.stderr)
        return 2
    findings = []
    for path in scan_targets(root):
        findings.extend(scan_file(path, root))
    for finding in findings:
        print(finding)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
