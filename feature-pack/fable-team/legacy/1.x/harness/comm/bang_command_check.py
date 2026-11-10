#!/usr/bin/env python3
"""R106 오빠 `!` 명령 줄 판정기 — 쪽지 가드(mbox_guard.sh)·인터뷰 훅(bang-command-gate.sh)이 함께 쓴다.

«오빠 명령 줄» = 앞 공백·백틱·`>` 인용·목록 기호를 벗기고 `! ` 로 시작하는 줄. 그 줄이 `! bash /tmp/h<숫자>` 면 통과,
아니면 60자 초과 · /tmp/h<N> 밖 절대경로(`/`·`~/` 토큰) · 따옴표 밖 `&&`·`;`·`|` 중 하나라도 있을 때 위반.
`!` 로 시작하지 않는 줄(①막힌 명령 원문 등)은 검사 밖이다. CLI: 본문을 stdin 으로 받아 위반이 있으면 안내+위반 줄(앞 40자)을 stdout, rc 1.
"""
import re
import sys

MAX_LEN = 60
STANDARD = re.compile(r"^! bash /tmp/h[0-9]+$")
TMP_H = re.compile(r"^/tmp/h[0-9]+$")
WRAPPER = re.compile(r"^(?:`+|>+|[-*]\s|[0-9]+\.\s)\s*")
QUOTED = re.compile(r"\"[^\"]*\"|'[^']*'")
GUIDE = "오빠 명령 줄이 길거나 절대경로·체인 — `ft-hil.sh --add <계획 파일>` 로 /tmp/h<N> 을 받아 `! bash /tmp/h<N>` 한 줄만 (R83·R106)"


def _bang_line(line):
    s = line.strip()
    while True:
        t = WRAPPER.sub("", s)
        if t == s:
            break
        s = t
    s = s.rstrip("`").rstrip()
    return s if s.startswith("! ") else ""


def _bad(cmd):
    if STANDARD.match(cmd):
        return False
    if len(cmd) > MAX_LEN or re.search(r"&&|;|\|", QUOTED.sub('""', cmd)):
        return True
    toks = (t.strip("\"'") for t in cmd.split())
    return any((t.startswith("/") or t.startswith("~/")) and not TMP_H.match(t) for t in toks)


def violations(body):
    cmds = (_bang_line(line) for line in body.splitlines())
    return [c for c in cmds if c and _bad(c)]


if __name__ == "__main__":
    found = violations(sys.stdin.read())
    if found:
        print(GUIDE)
        for c in found:
            print("  위반 줄: " + c[:40])
    sys.exit(1 if found else 0)
