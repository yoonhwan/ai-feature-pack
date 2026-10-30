#!/usr/bin/env python3
"""ft_scope_plan_judge — 범위 승인(S) 중 h 계획의 `approve-merge` 줄 검사 (r1192 · 오빠 판정 2904 · S3 뒤 approve-merge 159 · scope-use 2).
CLI: ft_scope_plan_judge.py --plan <파일> → `ok`(rc0) | `reject <이유> — 줄 <n>`(줄마다 · rc1) | 범위 조회 실패·내부 오류 rc2
- 주석 아닌 줄에서 낱말 `approve-merge` 가 echo/printf/:/grep/rg 인자가 «아닌» 토큰(명령 자리·대입·배열·eval·bash -c 문자열 안 포함)에 있으면 후보 — 후보 0 이면 범위 조회 0
  글자 훑기(r1192 반송 1): 따옴표 밖 낱말 머리 `#` 뒤 = 주석 · 작은따옴표 밖 `$( )`·백틱 본문 = 실행되므로 재귀 판정
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

PUNCT, SEP = set("();<>|&"), set(";&|()")  # shlex 구두점 토큰(«;(»·«&&(»·«>(» 처럼 붙어 나온다) — SEP 글자가 있으면 명령 구분 · <>만 = 리다이렉트
TEXT = {"echo", "printf", ":", "grep", "rg"}  # 인자가 글자일 뿐인 명령(단 그 안의 $( )·백틱은 재귀로 본다)
WORD = re.compile(r"(?<![\w-])approve-merge(?![\w-])")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
ALIVE = re.compile(r"^\[범위 승인 (S[0-9]+) · ")
IDLE = re.compile(r"^\[범위 승인 (없음|S[0-9]+ 정지: )")
WHY = "범위 승인 %s 중 approve-merge — scope-approve <sha> --pr <N> [--card <카드>] [--repo byz|pack] 로 (판정 2904) — 줄 %d"


def close_paren(s: str, i: int) -> int:
    """s[i:] 에서 `$(` 짝 `)` 위치(괄호 깊이 셈) — 없으면 len(s)."""
    depth = 1
    for j in range(i, len(s)):
        depth += {"(": 1, ")": -1}.get(s[j], 0)
        if depth == 0:
            return j
    return len(s)


def scan(line: str) -> tuple[str, list[str], str]:
    """글자 훑기 → (주석 자른 줄, 실행되는 $( )·백틱 본문들, 끝난 따옴표 상태) — 작은따옴표 안은 글자뿐."""
    out: list[str] = []
    subs: list[str] = []
    q, i = "", 0
    while i < len(line):
        ch, j = line[i], i + 1
        if q != "'" and ch == "\\":
            j = i + 2
        elif q == "'":
            q = "" if ch == "'" else q
        elif ch in "'\"" and q in ("", ch):
            q = "" if q else ch
        elif ch == "#" and not q and (i == 0 or line[i - 1] in " \t;&|("):
            break  # 진짜 주석
        elif line.startswith("$(", i):
            j = close_paren(line, i + 2)
            subs.append(line[i + 2:j])
            j += 1
        elif ch == "`":
            k = line.find("`", i + 1)
            j = k if k > 0 else len(line)
            subs.append(line[i + 1:j])
            j += 1
        out.append(line[i:j])
        i = j
    return "".join(out), subs, q


def is_candidate(line: str) -> bool:
    if "approve-merge" not in line:
        return False
    cut, subs, q = scan(line)
    if q or any(is_candidate(s) for s in subs):  # 따옴표 짝 안 맞음 = 후보(통과 쪽으로 기울지 않는다) · $( )·백틱은 실행된다
        return True
    lex = shlex.shlex(cut, posix=True, punctuation_chars=True)
    lex.whitespace_split, lex.commenters = True, ""
    try:
        toks = list(lex)
    except ValueError:
        return True
    cmd = ""  # 지금 명령의 첫 낱말(빈 값 = 다음 낱말이 명령 · 대입은 명령이 아니다)
    for t in toks:
        if t and set(t) <= PUNCT:
            cmd = "" if set(t) & SEP else cmd  # 리다이렉트(>·>>·<)는 명령을 바꾸지 않는다
            continue
        if t.endswith("$"):  # «x=$» 다음 «(» — $( ) 본문은 scan 이 재귀로 본다
            cmd = ""
            continue
        text_arg = cmd in TEXT  # TEXT 명령의 인자만 글자로 본다
        if not cmd and not ASSIGN.match(t):
            cmd = t
        if not text_arg and WORD.search(t):  # 명령 자리·대입·배열·eval·bash -c 문자열 안 낱말 전부
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
