#!/usr/bin/env python3
"""ft_hil_mix_judge — 자율 ON 중 h 계획에 «desk 가 직접 돌릴 줄»과 «오빠 손 줄»이 섞였는지 알리는 경고 판정기 (r1384 · 오빠 11-05 «잘 만들고 제대로 못쓰냐고»)
CLI: ft_hil_mix_judge.py --plan <파일> → `ok`(rc0) | `warn h 계획 섞임 — …`(rc0 · 등록은 그대로) | 자율 모드 조회 실패·내부 오류 rc2(reject 글 없음 = 조용한 통과 0)
- desk 줄 = scope-stop · approve-merge · ft-seat-close.sh · ft-nano-close.sh / 오빠 줄 = approve-scope · approve-standing · forget-kind · ft-autonomy.sh on|off · ft-queue-digest.sh issue · ft-resume-attempt.sh allow
  (라이브 쓰기·과금 줄을 가르는 표식은 계획 머리·낱말에 없다 — 실측 11-05 · 이 칸은 훅 DENY_EXEC 에서 approve-merge 를 뺀 것만)
- 주석·echo/printf/:/grep/rg 인자 글자 = 줄이 아니다(범위 판정기 scan 꼴 · $( )·백틱 본문은 재귀) · desk 줄이 0 이면 자율 모드 조회 0
- 자율 모드 = FT_AUTONOMY_MODE_CMD 또는 같은 폴더 ft-autonomy.sh mode (7초) · on 이 아니면 ok"""
from __future__ import annotations

import os
import re
import shlex
import subprocess
import sys

from ft_scope_plan_judge import ASSIGN, PUNCT, SEP, TEXT, scan
from ft_traffic_plan_judge import logical_lines

DESK = re.compile(r"(?<![\w-])(scope-stop|approve-merge)(?![\w-])|ft-(seat|nano)-close\.sh")
OPPA = re.compile(r"(?<![\w-])(approve-scope|approve-standing|forget-kind)(?![\w-])|ft-autonomy\.sh\s+(on|off)(?![\w-])")
VAR = re.compile(r"^\$\{?\w+\}?$")


def pairs(line: str):
    """(앞 낱말, 낱말) — 글자뿐인 명령(echo 따위)의 인자는 뺀다 · $( )·백틱 본문은 재귀."""
    cut, subs, q = scan(line)
    for s in subs:
        yield from pairs(s)
    lex = shlex.shlex(cut, posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    try:
        toks = list(lex)
    except ValueError:
        toks = cut.split()  # 따옴표 짝 안 맞음 = 낱말대로 본다(경고만이라 통과 쪽 위험 0)
    cmd, prev = "", ""
    for t in toks:
        if t and set(t) <= PUNCT:
            cmd = "" if set(t) & SEP else cmd
            continue
        if cmd not in TEXT:
            yield prev, t
        cmd = t if not cmd and not ASSIGN.match(t) else cmd
        prev = t


def kinds(line: str) -> tuple[bool, bool]:
    desk = oppa = False
    for prev, t in pairs(line):
        desk = desk or bool(DESK.search(t))
        oppa = oppa or bool(OPPA.search(t))
        sub = {"on": "ft-autonomy.sh", "off": "ft-autonomy.sh", "issue": "ft-queue-digest.sh", "allow": "ft-resume-attempt.sh"}.get(t)
        oppa = oppa or bool(sub and (prev.endswith(sub) or (sub == "ft-autonomy.sh" and VAR.match(prev))))
    return desk, oppa


def mode_on() -> bool:
    cmd = os.environ.get("FT_AUTONOMY_MODE_CMD")
    argv = shlex.split(cmd) if cmd else ["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)), "ft-autonomy.sh"), "mode"]
    r = subprocess.run(argv, capture_output=True, text=True, timeout=7)
    if r.returncode != 0:
        raise RuntimeError("자율 모드 조회 rc=%d" % r.returncode)
    return (r.stdout.strip().splitlines() or [""])[-1] == "on"


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_hil_mix_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            ks = [(n, *kinds(line)) for n, line in logical_lines(f.read())]
        desk, oppa = [n for n, d, _ in ks if d], [n for n, _, o in ks if o]
        on = mode_on() if desk else False
    except (OSError, RuntimeError, subprocess.SubprocessError) as e:
        print("ft_hil_mix_judge 모드 조회·읽기 실패: %s" % e, file=sys.stderr)
        return 2
    if not (desk and on):
        print("ok")
        return 0
    tail = "desk 줄은 desk 가 직접(자율 ON) · h 는 오빠 손 줄만" if oppa else "h 불필요 — desk 가 직접(자율 ON)"
    print("warn h 계획 섞임 — desk 줄 %d(%d) · 오빠 줄 %d — %s" % (len(desk), desk[0], len(oppa), tail))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
