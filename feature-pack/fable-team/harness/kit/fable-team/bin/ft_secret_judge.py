#!/usr/bin/env python3
"""ft_secret_judge — 비밀을 stdout 으로 내는 명령이 화면·파이프로 가면 reject (R135a · 판정 1585 · loom 사고 2026-10-13).
judge(명령) → ("ok","") | ("reject","<이유>")   CLI: ft_secret_judge.py '<명령>' | -(stdin) → `ok`(rc0) | `reject <이유>`(rc1)
plan(계획 파일 글) → [(줄, 이유)]               CLI: ft_secret_judge.py --plan <파일>      → `ok` | `reject <줄> <이유>`(줄마다 · rc1)
훅 모드: ft_secret_judge.py --hook (stdin = PreToolUse JSON) → reject 면 deny JSON 한 줄, ok 면 출력 없음 · rc 0 ok / 1 reject / 2 내부 오류(호출자 fail-open)
알려진 모양의 가드레일이다(전부 못 잡는다 — 출력 가림·사후 스캔이 뒤에 있다). 이유는 고정 글자뿐 — 명령 속 값·이름을 다시 쓰지 않는다. 문자열만 본다(실행 0)."""
from __future__ import annotations

import json
import os
import re
import sys
from typing import NamedTuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:  # 동봉 모듈이 빠진 설치 — reject(rc1)와 섞이지 않게 내부 오류 rc2 (호출자 fail-open)
    from ft_secret_lex import W, scan, strip_heredocs
    from ft_secret_sinks import nested, sinks
    from ft_secret_targets import secret_path, target
except ImportError as e:
    print("ft_secret_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
    sys.exit(2)

HINT = ' · 값은 변수에만: X="$(… 2>"$ERR")" · 확인은 ${#X}/[ -n "$X" ] · BOOT 22'
SKIP = {"if", "then", "elif", "else", "while", "until", "do", "fi", "done", "!", "{", "}", "time", "sudo", "command", "builtin", "exec", "nohup"}
DECL = {"export", "local", "declare", "readonly", "typeset"}
EXEMPT = {"unset", "[", "[[", "test", "export", "read", "exit", "return", "set", "true", "false", ":"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")
REDIR = re.compile(r"^(\d*)(&>>?|>&|>>?|<<?<?)(.*)$", re.S)


class Seg(NamedTuple):
    start: int
    args: list[W]
    assigns: list[W]
    redirs: list[tuple[str, str, str]]
    decl: bool
    arg_subs: list[str]  # 인자 단어 속 치환(대입·export 값 속 치환은 변수에 갇히므로 뺀다)


def parse(t: str) -> list[Seg]:
    out = []
    for start, words, _sep in scan(strip_heredocs(t)):
        args: list[W] = []
        redirs: list[tuple[str, str, str]] = []
        ws = list(words)
        while ws:
            w = ws.pop(0)
            m = REDIR.match(w)
            if not m:
                args.append(w)
                continue
            fd, op, tgt = m.groups()
            redirs.append((fd, op, tgt if tgt or op == ">&" or not ws else ws.pop(0)))
        assigns: list[W] = []
        while args and (ASSIGN.match(args[0]) or args[0] in SKIP or (args[0] == "env" and any(not x.startswith("-") for x in args[1:]))):
            w = args.pop(0)
            if ASSIGN.match(w):
                assigns.append(w)
        decl = bool(args) and args[0] in DECL
        out.append(Seg(start, args, assigns, redirs, decl, [x for w in args for x in w.subs]))
    return out


def out_state(redirs: list[tuple[str, str, str]]) -> tuple[bool, bool]:  # → (stdout 이 파일·/dev/null 로만 가나, 2>&1 이 stdout 파일 지정보다 앞섰나)
    to_file = merged = early = False
    for fd, op, tgt in redirs:
        if (op in (">", ">>") and fd in ("", "1")) or op in ("&>", "&>>") or (op == ">&" and fd in ("", "1") and not tgt.isdigit()):
            if tgt in ("/dev/stdout", "/dev/stderr", "/dev/tty") or tgt.startswith("/dev/fd/"):
                to_file = False
            else:
                early, to_file = early or merged, True
        elif op == ">&" and fd == "2" and tgt == "1" and not to_file:
            merged = True
        elif op == ">&" and fd in ("", "1") and tgt.isdigit():
            to_file = False
    return to_file, early


def leak(s: Seg) -> str | None:  # 비밀을 stdout 으로 내는 모양이면 고정 이름 — `< 비밀경로` 는 파일 인자와 같이 본다
    stdin = [x for fd, op, x in s.redirs if op == "<" and fd in ("", "0") and secret_path(x)]
    return target(s.args + [W(x) for x in stdin]) or sinks(s.args, stdin)


def has_target(t: str) -> bool:
    return any(leak(s) or any(has_target(x) for x in s.arg_subs) for s in parse(t))


def check(t: str, depth: int = 0) -> list[tuple[int, str]]:  # → [(시작 위치, 이유)] · depth = bash -c·eval 본문 재판정 단계(상한 2)
    found = []
    for s in parse(t):
        why, (to_file, early) = leak(s), out_state(s.redirs)
        inner = nested(s.args) if depth < 2 and not why and not to_file else ""
        sub = check(inner, depth + 1) if inner else []
        if sub:
            found.append((s.start, s.args[0] + " 본문 안에서 " + sub[0][1]))
        elif why and early:
            found.append((s.start, why + " — 2>&1 이 > 보다 앞섬"))
        elif why and not to_file:
            found.append((s.start, why + " 출력이 화면·파이프로 감"))
        elif not s.decl and not to_file and any(has_target(x) for x in s.arg_subs):
            found.append((s.start, "비밀 조회 치환이 인자로 넘어감(변수 대입 밖)"))
    return found


def judge(cmd: str) -> tuple[str, str]:
    found = check(cmd)
    return ("reject", found[0][1]) if found else ("ok", "")


def func_lines(t: str) -> set[int]:  # `name() {` … `}` 본문 줄 — 옛 계획이 자기 secret() 를 정의하는 꼴
    inside, lines = False, set()
    for k, line in enumerate(t.split("\n"), 1):
        inside = inside or bool(re.match(r"\s*(function\s+)?[A-Za-z_][\w-]*\s*\(\)", line))
        if inside:
            lines.add(k)
            inside = not (line.strip() == "}" or re.search(r"\{.*\}\s*$", line))
    return lines


def plan(text: str) -> list[tuple[int, str]]:  # 계획 파일: judge 와 같은 검사 + set -x + 비밀 변수를 인자로 받은 명령의 출력이 화면으로
    t = strip_heredocs(text)
    found = [(t.count("\n", 0, o) + 1, why) for o, why in check(t)]
    if re.match(r"#!.*\s-[a-z]*x", t):
        found.append((1, "셔뱅 -x 로 값이 추적 출력됨"))
    fn, tracked = func_lines(t), set()
    for s in parse(t):
        line, to_file = t.count("\n", 0, s.start) + 1, out_state(s.redirs)[0]
        if s.args[:1] == ["set"] and any(re.fullmatch(r"-[a-zA-Z]*x[a-zA-Z]*", a) or a == "xtrace" for a in s.args[1:]):
            found.append((line, "set -x 로 값이 추적 출력됨"))
        elif tracked and s.args and not s.decl and s.args[0] not in EXEMPT and not to_file and line not in fn and not any(a.startswith("--format") for a in s.args):
            use = re.compile(r"\$\{?(?:%s)(?![A-Za-z0-9_#])" % "|".join(map(re.escape, tracked)))
            if any(use.search(a) for a in s.args[1:]):
                found.append((line, "비밀 변수를 인자로 넘긴 명령의 출력이 화면으로 감(>/dev/null 또는 --format 필요)"))
        if line not in fn:
            tracked |= {w.split("=")[0] for w in s.assigns + (s.args[1:] if s.decl else []) if "=" in w and any(has_target(x) for x in w.subs)}
    return sorted(set(found))


def main(argv: list[str]) -> int:
    if argv[:1] == ["--hook"]:
        verdict, why = judge(json.load(sys.stdin)["tool_input"]["command"])
        if verdict == "reject":
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                                     "permissionDecisionReason": "REJECT 비밀 출력 경로 — " + why + HINT}}, ensure_ascii=False))
        return 0
    if argv[:1] == ["--plan"] and len(argv) == 2:
        with open(argv[1], encoding="utf-8") as f:
            found = plan(f.read())
        print("\n".join("reject %d %s" % x for x in found) if found else "ok")
        return 1 if found else 0
    if len(argv) != 1:
        print("usage: ft_secret_judge.py '<명령>' | - | --plan <파일> | --hook", file=sys.stderr)
        return 2
    verdict, why = judge(sys.stdin.read() if argv[0] == "-" else argv[0])
    print("ok" if verdict == "ok" else "reject " + why)
    return 0 if verdict == "ok" else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # 내부 오류는 reject(rc1)와 섞이지 않게 rc2
        print("ft_secret_judge 내부 오류: %s" % type(e).__name__, file=sys.stderr)
        sys.exit(2)
