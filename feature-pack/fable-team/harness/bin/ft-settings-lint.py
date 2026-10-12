#!/usr/bin/env python3
"""ft-settings-lint.py <settings.json> [--root <프로젝트 루트>] — 중복 키 · 훅 command 경로 실재 검사.

JSON 표준 파서는 같은 키가 두 번 나오면 «마지막 값만» 남긴다 — settings.json 의 "PreToolUse" 가
2번 쓰이면 앞 블록의 훅이 소리 없이 사라진다(판정 1097b · 09-22 이후 3주).
출력: REJECT <파일> 중복 키 <이름> <행,행> | REJECT <파일> 훅 경로 실재 0 <경로> | OK <파일> …
rc: 0 OK · 1 REJECT · 2 usage(파일 없음·인자)
"""
import json
import os
import re
import sys

WRAPPERS = {"bash", "sh", "zsh", "python3", "python"}
ENV_ROOT = re.compile(r"^\$\{?CLAUDE_PROJECT_DIR\}?")


def dup_keys(text):
    """중복된 키 이름 목록(원문 순서). object_pairs_hook 으로 같은 객체 안 반복만 잡는다."""
    found = []

    def hook(pairs):
        seen = set()
        for key, _ in pairs:
            if key in seen and key not in found:
                found.append(key)
            seen.add(key)
        return dict(pairs)

    json.loads(text, object_pairs_hook=hook)
    return found


def key_lines(text, key):
    pat = re.compile(r'^\s*"%s"\s*:' % re.escape(key))
    return [str(i) for i, line in enumerate(text.splitlines(), 1) if pat.match(line)]


def hook_commands(data):
    for blocks in (data.get("hooks") or {}).values():
        for block in blocks or []:
            for hook in block.get("hooks") or []:
                if hook.get("type") == "command" and hook.get("command"):
                    yield hook["command"]


def command_path(command, root):
    """command 의 첫 «경로 토큰»을 절대 경로로. 셸 한 줄·외부 실행기(node 등)는 None(검사 제외)."""
    tokens = command.split()
    if tokens and tokens[0] in WRAPPERS:
        tokens = tokens[1:]
    if not tokens:
        return None
    tok = tokens[0]
    if ENV_ROOT.match(tok):
        return ENV_ROOT.sub(root, tok)
    if tok.startswith(("$HOME", "~")):
        return os.path.expandvars(os.path.expanduser(tok.replace("$HOME", "~", 1)))
    if tok.startswith("/"):
        return tok
    if tok.startswith(".claude/"):
        return os.path.join(root, tok)
    return None


def lint(path, root):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    try:
        dups = dup_keys(text)
        data = json.loads(text)
    except ValueError as exc:
        return ["REJECT %s JSON 파싱 실패 %s" % (path, exc)]
    out = ["REJECT %s 중복 키 %s %s" % (path, k, ",".join(key_lines(text, k))) for k in dups]
    for command in hook_commands(data):
        target = command_path(command, root)
        if target and not os.path.exists(target):
            out.append("REJECT %s 훅 경로 실재 0 %s" % (path, target))
    return out


def main(argv):
    root = None
    if "--root" in argv:
        i = argv.index("--root")
        root, argv = (argv[i + 1] if i + 1 < len(argv) else None), argv[:i] + argv[i + 2:]
    if len(argv) != 1 or not os.path.isfile(argv[0]) or ("--root" in sys.argv and root is None):
        print("usage: ft-settings-lint.py <settings.json> [--root <dir>]", file=sys.stderr)
        return 2
    path = argv[0]
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(path)))
    problems = lint(path, root)
    print("\n".join(problems) if problems else "OK %s 중복 키 0 · 훅 경로 전부 실재" % path)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
