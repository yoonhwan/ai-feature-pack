#!/usr/bin/env python3
"""ft_scope_plan_judge — 범위 승인(S) 중 h 계획의 `approve-merge` 줄 검사 (r1192 · 오빠 판정 2904 · S3 뒤 approve-merge 159 · scope-use 2).
CLI: ft_scope_plan_judge.py --plan <파일> → `ok`(rc0) | `reject <이유> — 줄 <n>`(줄마다 · rc1) | 범위 조회 실패·내부 오류 rc2
- 주석 아닌 줄에서 낱말 `approve-merge` 가 명령 인자(명령 첫 낱말 아님 · echo/printf/grep 인자 아님)로 있으면 후보 — 후보 0 이면 범위 조회 0
- 후보가 있으면 scope-status 1회(FT_SCOPE_STATUS_CMD 또는 같은 폴더 ft-autonomy.sh · 7초): «[범위 승인 S<n> · …» = 살아 있음 → reject
  «[범위 승인 없음…» · «[범위 승인 S<n> 정지: …» = ok(오빠 손 승인 h 그대로) · 그 밖(도구 없음·rc≠0·시간 초과·꼴 모름) = rc2
줄 끝 `\\` 이어 쓰기는 한 줄로 합쳐 본다(번호 = 첫 줄). ft-hil.sh lint 가 등록 전에 부른다."""
from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys

from ft_traffic_plan_judge import logical_lines

OPS = {";", "&&", "||", "|", "&", "(", ")", "$(", "`"}
TEXT = {"echo", "printf", ":", "grep", "rg"}  # 인자가 글자일 뿐인 명령
ALIVE = re.compile(r"^\[범위 승인 (S[0-9]+) · ")
IDLE = re.compile(r"^\[범위 승인 (없음|S[0-9]+ 정지: )")
WHY = "범위 승인 %s 중 approve-merge — scope-approve <sha> --pr <N> [--card <카드>] [--repo byz|pack] 로 (판정 2904) — 줄 %d"


def is_candidate(line: str) -> bool:
    if "approve-merge" not in line:
        return False
    lex = shlex.shlex(line, posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    try:
        toks = list(lex)
    except ValueError:  # 따옴표 짝이 안 맞음 — 글자에 있으면 후보로 본다(통과 쪽으로 기울지 않는다)
        return True
    cmd = ""  # 지금 명령의 첫 낱말(빈 값 = 다음 낱말이 명령)
    for t in toks:
        if t.startswith("#"):
            break  # 줄 안 주석
        if t in OPS or t.endswith("$"):
            cmd = ""
        elif not cmd:
            cmd = t
        elif t == "approve-merge" and cmd not in TEXT:
            return True
    return False


def scope_state() -> str:
    cmd = os.environ.get("FT_SCOPE_STATUS_CMD")
    argv = shlex.split(cmd) if cmd else ["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft-autonomy.sh"), "scope-status"]
    r = subprocess.run(argv, capture_output=True, text=True, timeout=7)
    if r.returncode != 0:
        raise RuntimeError("scope-status rc=%d" % r.returncode)
    out = r.stdout.strip().splitlines()[-1:] or [""]
    m = ALIVE.match(out[0])
    if m:
        return m.group(1)
    if IDLE.match(out[0]):
        return ""
    raise RuntimeError("scope-status 꼴 모름: %s" % out[0][:80])


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_scope_plan_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            hits = [n for n, line in logical_lines(f.read()) if is_candidate(line)]
        s = scope_state() if hits else ""
    except (OSError, RuntimeError, subprocess.SubprocessError) as e:
        print("ft_scope_plan_judge 범위 조회·읽기 실패: %s" % e, file=sys.stderr)
        return 2
    for n in hits if s else []:
        print("reject " + WHY % (s, n))
    if not (hits and s):
        print("ok")
    return 1 if hits and s else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
