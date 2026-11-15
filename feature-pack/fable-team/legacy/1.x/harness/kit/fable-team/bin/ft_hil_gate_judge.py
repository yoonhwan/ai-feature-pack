#!/usr/bin/env python3
"""ft_hil_gate_judge — h 계획 공통 규칙 3개 (r2078 · 실사건 #309281 70초 넘김 · #309234 시간초과를 «변경 0» 으로 셈)
CLI: --plan <파일> → `ok` rc0 | `warn h 공통 규칙 — <위반들>` rc0(지우는 줄 없음 = 등록 그대로) | `reject <규칙> <n>줄 <사유> (지우는 줄 <m>줄)` 위반마다 rc1(등록 0) | 못 읽음 rc2
- J1 파이프(`|` · `||` 아님) 실행 줄 앞(같은 줄 포함)에 set -o pipefail(-euo pipefail 꼴) 없음 · J3 반복(for·while·until)인데 `# ft-hil-budget: <초>` 줄이 1개가 아니거나 1~70 밖
- J2 $( )·백틱 안 timeout 값 줄이 rc 를 안 봄($? · || 없음 · if/while/until/! 시작 아님) 또는 삼킴(|| true · || : · || echo) · 면제 = 줄 끝 `# rc-ok: <사유>`
- 실행 줄 = 범위 판정기 scan 꼴(주석·따옴표 안·echo/printf 인자 글자는 줄 아님 · $( )·백틱 본문 재귀) · 지우는 줄 = rm -r… · git worktree remove|branch -D|reset --hard|clean -f… · tmux kill-session|kill-server · kill · pkill
알려진 한계: J2 는 같은 줄만 본다 · 다른 도구 안에 숨은 지우는 명령은 안 센다(경고 길)."""
from __future__ import annotations

import re
import shlex
import sys

from ft_scope_plan_judge import ASSIGN, PUNCT, SEP, scan
from ft_traffic_plan_judge import logical_lines

LOOP = {"for", "while", "until"}
PRE = {"while", "until", "!", "{", "}", "do", "then", "else", "elif", "if", "time", "sudo", "command", "exec", "nohup", "env"}
DUR = re.compile(r"^-|^[0-9.]+[smhd]?$")  # timeout 의 옵션 · 시간 값
BUDGET = re.compile(r"^\s*#\s*ft-hil-budget:\s*(\S*)\s*$")
RC_OK = re.compile(r"^#\s*rc-ok:\s*\S")
LEAD = re.compile(r"^\s*(if|while|until|!)\s")
SWALLOW = {"true", ":", "echo"}


def tokens(cut: str) -> list[str]:
    lex = shlex.shlex(cut, posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    try:
        return list(lex)
    except ValueError:  # 따옴표 짝 안 맞음 = 낱말대로
        return cut.split()


def streams(line: str) -> list[tuple[list[str], bool]]:
    """[(토큰들, 치환 안인가)] — 줄 자체 + $( )·백틱 본문(재귀)."""
    cut, subs, _ = scan(line)
    return [(tokens(cut), False)] + [(t, True) for s in subs for t, _ in streams(s)]


def strip(seg: list[str]) -> tuple[bool, bool, list[str]]:
    """명령 앞 낱말(대입 · if/do/while · sudo · timeout <초>) 벗김 → (반복인가, timeout 인가, 낱말들)."""
    loop, timed, i = False, False, 0
    while i < len(seg) and (ASSIGN.match(seg[i]) or seg[i] in PRE or seg[i] == "timeout"):
        loop |= seg[i] in LOOP
        if seg[i] == "timeout":
            timed = True
            while i + 1 < len(seg) and DUR.match(seg[i + 1]):
                i += 1
        i += 1
    return loop or seg[i:i + 1] == ["for"], timed, seg[i:]


def commands(toks: list[str]):
    seg: list[str] = []
    for t in toks + [";"]:
        if t and set(t) <= PUNCT:  # 명령 구분(SEP) 에서 끊는다 · 리다이렉트는 건너뜀
            if set(t) & SEP and seg:
                yield strip(seg)
                seg = []
        else:
            seg.append(t)


def destroys(w: list[str]) -> bool:
    c, a = (w[0].rsplit("/", 1)[-1], w[1:]) if w else ("", [])
    if c == "rm":
        return any(re.match(r"^-[a-zA-Z]*[rR]", x) or x == "--recursive" for x in a)
    if c == "tmux":
        return any(x in ("kill-session", "kill-server") for x in a)
    if c != "git":
        return c in ("kill", "pkill")
    return (("worktree", "remove") in list(zip(a, a[1:])) or ("branch" in a and "-D" in a) or ("reset" in a and "--hard" in a)
            or ("clean" in a and any(re.match(r"^-[a-zA-Z]*f", x) for x in a)))


def judge(text: str) -> tuple[list[str], list[int]]:
    v, dest = [], []  # type: list[str], list[int]
    pipefail, j1, loop_at = False, False, 0  # J1 은 계획마다 1번
    for n, line in logical_lines(text):
        st = streams(line)
        cmds = [(sub, c) for toks, sub in st for c in commands(toks)]
        puncts = [t for toks, _ in st for t in toks if t and set(t) <= PUNCT]
        pipefail |= any(w[:1] == ["set"] and any(re.match(r"^-[a-zA-Z]*o$", x) and y == "pipefail" for x, y in zip(w[1:], w[2:])) for _, (_, _, w) in cmds)
        if not (pipefail or j1) and any("|" in t.replace("||", "") for t in puncts):
            v.append("J1 %d줄 파이프가 있는데 그 앞에 set -o pipefail 없음" % n)
            j1 = True
        loop_at = loop_at or (n if any(lp for _, (lp, _, _) in cmds) else 0)
        dest += [n] if any(destroys(w) for _, (_, _, w) in cmds) else []
        cut = scan(line)[0]
        if not any(sub and t for sub, (_, t, _) in cmds) or RC_OK.match(line[len(cut):]):
            continue
        swallow = any("||" in a and set(a) <= PUNCT and b in SWALLOW for toks, _ in st for a, b in zip(toks, toks[1:]))
        if swallow or not ("$?" in cut or any("||" in t for t in puncts) or LEAD.match(cut)):
            v.append("J2 %d줄 시간 상한 건 명령의 rc 를 %s" % (n, "삼킴" if swallow else "안 봄"))
    b = [m.group(1) for m in map(BUDGET.match, text.splitlines()) if m]
    if loop_at and len(b) != 1:
        v.append("J3 %d줄 반복이 있는데 «# ft-hil-budget: <초>» 줄이 %d개" % (loop_at, len(b)))
    elif loop_at and not (b[0].isdigit() and 1 <= int(b[0]) <= 70):
        v.append("J3 %d줄 선언 %s초 — 1~70 밖" % (loop_at, b[0]))
    return v, dest


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_hil_gate_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            v, dest = judge(f.read())
    except OSError as e:
        print("ft_hil_gate_judge 읽기 실패: %s" % e, file=sys.stderr)
        return 2
    rej = "\n".join("reject %s (지우는 줄 %d줄)" % (x, dest[0]) for x in v) if dest else ""
    print("ok" if not v else rej or "warn h 공통 규칙 — " + " · ".join(v))
    return 1 if v and dest else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
