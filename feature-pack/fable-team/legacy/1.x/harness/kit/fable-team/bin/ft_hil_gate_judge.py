#!/usr/bin/env python3
"""ft_hil_gate_judge — h 계획 공통 규칙 4개 (r2078 · 실사건 #309281 70초 넘김 · #309234 시간초과를 «변경 0» 으로 셈 · DA#11 #310488 고정 반례)
CLI: --plan <파일> → `ok` rc0 | `warn h 공통 규칙 — <위반들>` rc0(지우는 줄 없음 = 등록 그대로) | `reject <규칙> <n>줄 <사유> (지우는 줄 <m>줄)` rc1(등록 0) | 못 읽음 rc2
J1 파이프 앞에 set -o pipefail 없음 · J3 반복인데 `# ft-hil-budget: <1~70>` 줄이 정확히 1개가 아님 · J4 실행 글자에 BASH_SOURCE(잠금 실행 = bash -c 에서 빈 값 · 늘 reject)
J2 $( )·백틱 안 timeout 이 «rc 를 보는 꼴» 아님: ⓐ 맨 대입 오른쪽 전부 ⓑ 치환 안 timeout 뒤 ||·; 없음 ⓒ 뒤 = `|| <exit류 | { echo·printf 1개; exit류; }>` · `; …$?` · if/while/until/! 바로 뒤 · 면제 `# rc-ok: <사유>`
실행 글자 = scan 꼴(주석·작은따옴표·큰따옴표 글자 아님 · 그 안 $( )·백틱은 실행) · 지우는 줄 = 명령 자리(줄 머리 ; && || { ( do then else timeout <초>)의 rm -r…·git worktree remove|branch -D|reset --hard|clean -f…·tmux kill-*·kill·pkill
알려진 한계: J2 는 같은 줄만 · here-doc 본문도 실행 줄로 읽음 · 다른 도구 안의 지우는 명령은 안 셈(경고 길)."""
from __future__ import annotations

import re
import shlex
import sys

from ft_scope_plan_judge import ASSIGN, PUNCT, SEP, close_paren, scan
from ft_traffic_plan_judge import logical_lines

LOOP, DPOS = {"for", "while", "until"}, {"{", "do", "then", "else"}  # DPOS = 지우는 명령을 세는 명령 자리 낱말(카드 G2)
PRE = {"while", "until", "!", "{", "}", "do", "then", "else", "elif", "if", "time"}
DUR = re.compile(r"^-|^[0-9.]+[smhd]?$")  # timeout 의 옵션 · 시간 값
BUDGET = re.compile(r"^\s*#\s*ft-hil-budget:\s*(\S*)\s*$")
RC_OK = re.compile(r"^#\s*rc-ok:\s*\S")
TIMEOUT = re.compile(r"(?<![\w-])timeout(?![\w-])")
HEAD = re.compile(r'(^|;|&&|\|\||\bthen\b|\bdo\b|\belse\b|\{|\()\s*(?P<cond>(if|while|until|!)\s+(!\s+)?)?[A-Za-z_][A-Za-z0-9_]*="?$')
LEAVE = r"(exit|return|continue|break)\b"
CLOSED = re.compile(r"\s*(" + LEAVE + r"|\{\s*(echo|printf)\b(?:[^;|&]|>&\d)*;\s*" + LEAVE + r"[^;|&]*;?\s*\})")


def streams(line: str) -> list[list[str]]:
    """토큰 묶음들 — 줄 자체 + $( )·백틱 본문(재귀 · 큰따옴표 안 포함) · 따옴표 짝 안 맞음 = 낱말대로."""
    cut, subs, _ = scan(line)
    lex = shlex.shlex(cut, posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    try:
        toks = list(lex)
    except ValueError:
        toks = cut.split()
    return [toks] + [t for s in subs for t in streams(s)]


def bare(cut: str) -> str:
    """scan 이 자른 줄 → 실행 글자: 작은따옴표 = '' · 큰따옴표 = 안의 $( )·백틱·$? 만 남김 · 치환 본문은 다시 벗김."""
    out, i, stack = [], 0, []  # type: list[str], int, list[str]  # ')' = $( )·( ) · '`' = 백틱 · '"' = 큰따옴표
    while i < len(cut):
        c, top, k = cut[i], (stack[-1] if stack else ""), cut[i:i + 2]
        if c == "\\" or (top == '"' and c not in '"`' and k not in ("$(", "$?")):
            out.append(k if c == "\\" and top != '"' else "")
            i += 2 if c == "\\" else 1
            continue
        if c == "'" and top != '"':
            out.append("''")
            i = cut.find("'", i + 1) % (len(cut) + 1) + 1  # 짝 없음 = 줄 끝까지
            continue
        if k == "$(" or (c == "(" and top != '"'):
            stack.append(")")
        elif c in '"`' and top != c:
            stack.append(c)
        elif c == top or (c == ")" and top == ")"):
            stack.pop()
        out.append(cut[i:i + (2 if k in ("$(", "$?") else 1)])
        i += 2 if k in ("$(", "$?") else 1
    return "".join(out)


def subs_of(s: str):
    """벗긴 글자의 가장 바깥 치환 (시작, 끝, 본문) — $( ) 짝은 범위 판정기 close_paren."""
    i = 0
    while i < len(s):
        j = close_paren(s, i + 2) if s.startswith("$(", i) else (s.find("`", i + 1) % (len(s) + 1) if s[i] == "`" else -1)
        if j >= 0:
            yield i, j + 1, s[i + (2 if s[i] == "$" else 1):j]
        i = j + 1 if j >= 0 else i + 1


def j2(s: str) -> str:
    """한 줄(벗긴 글자)의 J2 사유 · 없으면 ''."""
    for a, b, inner in subs_of(s):
        m, h = TIMEOUT.search(inner), HEAD.search(s[:a])
        rest = s[b + 1:] if s[b:b + 1] == '"' else s[b:]
        o, semi = re.match(r"\s*\|\|(.*)$", rest), re.match(r"\s*;(.*)$", rest)
        if m and re.search(r"\|\||;", inner[m.end():]):
            return "삼킴(치환 안에서 timeout 뒤 || · ;)"
        if m and not h:
            return "안 봄(치환이 맨 대입의 오른쪽 전부가 아님 — rc 사라짐)"
        if m and o and not h.group("cond") and not CLOSED.match(o.group(1)):
            return "삼킴(|| 뒤 갈래가 닫힌 꼴 4개가 아님)"
        if m and not (h.group("cond") or o or (semi and "$?" in re.split(r";|&&|\|\|", semi.group(1))[0])):
            return "안 봄(대입 바로 뒤에 $? 도 || 갈래도 없음)"
    return ""


def commands(toks: list[str]):
    """토큰 → (반복인가, 지우는 명령 자리인가, 낱말들) — SEP 에서 끊고 앞 낱말(대입 · if/do/while · timeout <초>)을 벗긴다."""
    seg: list[str] = []
    for t in toks + [";"]:
        seg += [] if t and set(t) <= PUNCT else [t]
        if t and set(t) & SEP and set(t) <= PUNCT and seg:
            loop, pos, i = False, True, 0
            while i < len(seg) and (ASSIGN.match(seg[i]) or seg[i] in PRE or seg[i] == "timeout"):
                loop, pos = loop or seg[i] in LOOP, pos and (seg[i] in DPOS or seg[i] == "timeout")
                while seg[i] == "timeout" and i + 1 < len(seg) and DUR.match(seg[i + 1]):
                    i += 1
                i += 1
            yield loop or seg[i:i + 1] == ["for"], pos, seg[i:]
            seg = []


def destroys(w: list[str]) -> bool:
    c, a = (w[0].rsplit("/", 1)[-1], w[1:]) if w else ("", [])
    git = (("worktree", "remove") in list(zip(a, a[1:])) or ("branch" in a and "-D" in a) or ("reset" in a and "--hard" in a)
           or ("clean" in a and any(re.match(r"^-[a-zA-Z]*f", x) for x in a)))
    return {"rm": any(re.match(r"^-[a-zA-Z]*[rR]", x) or x == "--recursive" for x in a), "tmux": bool({"kill-session", "kill-server"} & set(a)),
            "git": git, "kill": True, "pkill": True}.get(c, False)


def judge(text: str) -> tuple[list[str], list[str], list[int]]:
    v, j4, dest = [], [], []  # type: list[str], list[str], list[int]
    pipefail, j1, loop_at = False, False, 0  # J1 은 계획마다 1번
    for n, line in logical_lines(text):
        cut, st = scan(line)[0], streams(line)
        cmds = [c for toks in st for c in commands(toks)]
        pipefail |= any(w[:1] == ["set"] and any(re.match(r"^-[a-zA-Z]*o$", x) and y == "pipefail" for x, y in zip(w[1:], w[2:])) for _, _, w in cmds)
        if not (pipefail or j1) and any("|" in t.replace("||", "") for toks in st for t in toks if t and set(t) <= PUNCT):
            v, j1 = v + ["J1 %d줄 파이프가 있는데 그 앞에 set -o pipefail 없음" % n], True
        loop_at = loop_at or (n if any(lp for lp, _, _ in cmds) else 0)
        dest += [n] if any(pos and destroys(w) for _, pos, w in cmds) else []
        j4 += ["J4 %d줄 BASH_SOURCE 는 잠금 실행에서 빈 값 — $0 로 바꿔 다시 등록" % n] if re.search(r"(?<!\w)BASH_SOURCE(?!\w)", re.sub(r"'[^']*'", "''", cut)) else []
        why = "" if RC_OK.match(line[len(cut):]) else j2(bare(cut))
        v += ["J2 %d줄 시간 상한 건 명령의 rc 를 %s" % (n, why)] if why else []
    b = [m.group(1) for m in map(BUDGET.match, text.splitlines()) if m]
    j3 = "" if not loop_at else "줄이 %d개" % len(b) if len(b) != 1 else "" if b[0].isdigit() and 1 <= int(b[0]) <= 70 else "선언 %s초 — 1~70 밖" % b[0]
    return v + (["J3 %d줄 반복이 있는데 «# ft-hil-budget: <초>» %s" % (loop_at, j3)] if j3 else []), j4, dest


def main(argv: list[str]) -> int:
    try:
        if len(argv) != 3 or argv[1] != "--plan":
            raise OSError("usage: ft_hil_gate_judge.py --plan <파일>")
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            v, j4, dest = judge(f.read())
    except OSError as e:
        print("ft_hil_gate_judge 읽기 실패: %s" % e, file=sys.stderr)
        return 2
    rej = ["reject " + x + (" (지우는 줄 %d줄)" % dest[0] if dest else "") for x in (j4 + v if dest else j4)]
    print("\n".join(rej) if rej else ("warn h 공통 규칙 — " + " · ".join(v) if v else "ok"))
    return 1 if rej else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
