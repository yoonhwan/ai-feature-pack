#!/usr/bin/env python3
"""ft_hil_plan_syntax_judge — h 계획의 bash 문법 · 명령 경로 검사 (r2289 · r1101 재접수 · 실사건 h465 h466 «bash/Users…» · h335 상대 경로).
CLI: --plan <파일> → `ok` rc0 | `reject <이유> — 줄 <n>`(걸린 것마다 · rc1) | 못 읽음 · bash 실행 실패 rc2
C1 셔뱅 없음 · bash · sh = bash -n (다른 셔뱅은 검사 0) · C2 명령 자리 첫 낱말이 «bash/…» 꼴(해석기와 경로 사이 공백 빠짐)
C3 bash·sh·zsh·python3? 다음 낱말이 / 로 시작하면 그 파일이 있어야 함($ 든 경로는 검사 0)
C4 명령 자리 첫 낱말 · 해석기 뒤 첫 인자가 / 든 상대 경로 .sh·.py(대입 · 그 밖 인자는 검사 0)
명령 자리 = 줄 머리 · ; & | ( 뒤 · $( )·백틱 안 — 앞의 VAR=값 · env · nohup · exec · timeout <초> · if·then·do 같은 낱말은 건너뜀.
주석 · here-doc 본문은 C2~C4 검사 밖(데이터). ft-hil.sh lint 가 등록 전에 부른다(실행 0 · bash -n 만)."""
from __future__ import annotations

import os
import re
import subprocess
import sys

from ft_hil_gate_judge import DUR, PRE, streams
from ft_scope_plan_judge import ASSIGN, SEP, scan

SKIP = PRE | {"env", "nohup", "exec"}
INTERP = {"bash", "sh", "zsh", "python", "python3"}
GLUED = re.compile(r"^(bash|sh|zsh|python3?)/")
HEREDOC = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2")
ARRAY = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\+?=\(")  # 배열 대입 — 여러 줄이면 ) 까지 한 줄(원소 = 명령 자리 아님)


def code_lines(text: str):
    """(첫 줄 번호, 이어 쓰기 · 여러 줄 배열을 합친 줄) — 주석 줄 · here-doc 본문은 건너뛴다."""
    buf, start, ends, arr = "", 0, [], False  # type: str, int, list[tuple[bool, str]], bool
    for n, line in enumerate(text.splitlines(), 1):
        if ends:
            dash, word = ends[0]
            if (line.lstrip("\t") if dash else line) == word:
                ends.pop(0)
            continue
        if not buf:
            start = n
        if (not buf or arr) and line.lstrip().startswith("#"):
            continue
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        full, buf = buf + line, ""
        cut, _, q = scan(full)
        if q:  # r2294 따옴표가 열린 채 끝남 = 닫힐 때까지 같은 논리 줄(첫 줄 번호)
            buf, arr = full + "\n", False
            continue
        arr = bool(ARRAY.search(cut)) and cut.count("(") > cut.count(")")
        if arr:
            buf = full + " "
            continue
        ends = [(m.group(1) == "-", m.group(3)) for m in HEREDOC.finditer(cut)]
        yield start, full
    if buf:
        yield start, buf


def commands(toks: list[str]):
    """토큰 → 명령마다 (첫 낱말, 다음 낱말) — 앞의 대입 · 감싸는 낱말은 건너뜀."""
    i = 0
    while i < len(toks):
        while i < len(toks) and (ASSIGN.match(toks[i]) or toks[i] in SKIP or set(toks[i]) & SEP):
            if toks[i].endswith("=") and toks[i + 1:i + 2] == ["("]:  # 배열 원소는 건너뜀
                i = next((k for k in range(i + 2, len(toks)) if ")" in toks[k]), len(toks) - 1)
            i += 1
        if i < len(toks) and toks[i] == "timeout":
            i += 1
            while i < len(toks) and DUR.match(toks[i]):
                i += 1
            continue
        if i < len(toks):
            yield toks[i], (toks[i + 1] if i + 1 < len(toks) else "")
        while i < len(toks) and not set(toks[i]) & SEP:
            i += 1


def path_reasons(text: str) -> list[str]:
    out: list[str] = []
    for n, line in code_lines(text):
        for toks in streams(line):
            for cmd, arg in commands(toks):
                if GLUED.match(cmd):
                    out.append("해석기와 경로 사이 공백 빠짐: %s — 줄 %d" % (cmd, n))
                    continue
                for w in [cmd] + ([arg] if cmd in INTERP else []):  # C4 = 명령 자리 첫 낱말 · 해석기 뒤 첫 인자만
                    if "/" in w and w[0] not in "/$~" and w.endswith((".sh", ".py")):
                        out.append("상대 경로 — 절대 경로로: %s — 줄 %d" % (w, n))
                if cmd in INTERP and arg.startswith("/") and "$" not in arg and not os.path.exists(arg):
                    out.append("명령 경로 없음: %s — 줄 %d" % (arg, n))
    return list(dict.fromkeys(out))


def syntax_reason(path: str, text: str) -> str:
    """C1 — 셔뱅 없음 · bash · sh 면 bash -n 의 첫 줄(맞으면 '')."""
    first = text.split("\n", 1)[0]
    if first.startswith("#!"):
        words = [os.path.basename(w) for w in first[2:].split()]
        prog = words[1] if words[:1] == ["env"] and len(words) > 1 else (words or [""])[0]
        if prog not in ("bash", "sh"):
            return ""
    r = subprocess.run(["bash", "-n", path], capture_output=True, text=True, timeout=5)
    if r.returncode == 0:
        return ""
    msg = (r.stderr.strip().splitlines() or ["rc=%d" % r.returncode])[0].replace(path + ": ", "")
    return "계획 문법 오류 — " + msg


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "--plan":
        print("usage: ft_hil_plan_syntax_judge.py --plan <파일>", file=sys.stderr)
        return 2
    try:
        with open(argv[2], encoding="utf-8", errors="replace") as f:
            text = f.read()
        found = [r for r in [syntax_reason(argv[2], text)] if r] + path_reasons(text)
    except (OSError, subprocess.SubprocessError) as e:
        print("ft_hil_plan_syntax_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
        return 2
    for why in found:
        print("reject " + why)
    if not found:
        print("ok")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
