#!/usr/bin/env python3
"""ft_traffic_plan_judge — h 계획 파일의 Cloud Run 트래픽 전환 줄 검사 (r1133 · 사건 h244 10-29 RT STT 11분 정지).
CLI: ft_traffic_plan_judge.py --plan <파일> → `ok`(rc0) | `reject <이유> — 줄 <n>`(줄마다 · rc1) | 내부 오류 rc2
- 주석 아닌 줄의 날 `gcloud … run services update-traffic` = reject (전환은 ft-traffic-switch.sh — 전환 뒤 health·자동 원복)
- `ft-traffic-switch.sh` 호출에 `--health-url` 이 없다 = reject
줄 끝 `\\` 이어 쓰기는 한 줄로 합쳐 본다(번호 = 첫 줄). 문자열만 본다(실행 0). ft-hil.sh lint 가 등록 전에 부른다."""
from __future__ import annotations

import re
import sys

RAW = re.compile(r"\bgcloud\b.*\brun\b\s+services\s+update-traffic\b")
TOOL = re.compile(r"ft-traffic-switch\.sh\b")
WHY_RAW = "트래픽 전환은 ft-traffic-switch.sh 로(전환 뒤 health·자동 원복) — 날 update-traffic 줄 %d"
WHY_URL = "ft-traffic-switch.sh 호출에 --health-url 이 없다(전환 뒤 health 확인 0) — 줄 %d"


def logical_lines(text: str):
    """(첫 줄 번호, 이어 쓰기를 합친 줄) — 주석 줄은 건너뛴다."""
    buf, start = "", 0
    for n, line in enumerate(text.splitlines(), 1):
        if not buf:
            start = n
            if line.lstrip().startswith("#"):
                continue
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        yield start, buf + line
        buf = ""
    if buf:
        yield start, buf


def plan(text: str) -> list[str]:
    out: list[str] = []
    for n, line in logical_lines(text):
        if RAW.search(line):
            out.append(WHY_RAW % n)
        elif TOOL.search(line) and "--health-url" not in line:
            out.append(WHY_URL % n)
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_traffic_plan_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError as e:
        print("ft_traffic_plan_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
        return 2
    found = plan(text)
    for why in found:
        print("reject " + why)
    if not found:
        print("ok")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
