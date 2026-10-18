#!/usr/bin/env python3
"""r384 — harness/tests/** 경로 치환 (표 5행 · 리포 루트 앵커가 붙은 참조만 · 픽스처 경로는 그대로).

앵커 = 옛 BYZ 루트를 가리키던 식. 팩에서 그 식이 가리키는 곳:
  셸 $HERE/../.. · $(dirname "$0")/../.. · 그 값을 받은 변수  → feature-pack/fable-team  → 접두사 harness/
  셸 git rev-parse --show-toplevel 을 받은 변수               → 팩 리포 루트             → 접두사 feature-pack/fable-team/harness/
  파이썬 tests/*.py parents[2]                                → feature-pack/fable-team  → "harness"
  파이썬 tests/scripts/*.py parents[2] → parents[3]           → feature-pack/fable-team  → "harness"
사용: rewrite_tests.py <harness 폴더> [--apply]   출력 = 파일별 치환 수 + 남은 옛 경로(앵커 없음) 목록
"""
import re
import sys
from pathlib import Path

TABLE = [  # 옛 → 새 (harness/ 기준) · 긴 것 먼저
    ("scripts/fable-team-bin", "bin"),
    ("scripts/harness-install", "kit"),
    ("tools/comm-canonical", "comm"),
    ("design/teams/harness", "design/harness"),
    ("design/harness", "design/harness"),
    ("tests/harness", "tests"),
    ("tests/scripts/test_mbox", "tests/scripts/test_mbox"),
    ("tests/scripts/test_magazine", "tests/scripts/test_magazine"),
    (".fable-team/state/v6-", "evidence/state-v6/v6-"),
]
OLD_ALT = "|".join(re.escape(o) for o, _ in TABLE)
NEW_OF = dict(TABLE)
OLD_RE = re.compile(r"(?<![\w.-])(" + OLD_ALT + r")(?![\w-])")

DIRECT_ANCHOR = r'(?:\$HERE|\$\{HERE\}|\$\(dirname (?:-- )?"\$(?:0|\{BASH_SOURCE\[0\]\}|\{BASH_SOURCE\[0\]:-\$0\})"\))/\.\./\.\./'
ROOT_DEF = re.compile(
    r'(?:^|[;\s(])(?:export\s+|local\s+)?([A-Z_][A-Z0-9_]*)="?'
    r'(?:\$HERE/\.\./\.\.|\$\(cd (?:-- )?"\$HERE/\.\./\.\." && pwd\)|\$\(cd (?:-- )?"\$\(dirname (?:-- )?"\$0"\)/\.\./\.\." && pwd\))"?(?=[;\s]|$)'
)
TOP_DEF = re.compile(r'(?:^|[;\s])([A-Z_][A-Z0-9_]*)="\$\(git -C "\$\(dirname -- "\$\{BASH_SOURCE\[0\]\}"\)" rev-parse --show-toplevel\)"')
ANY_DEF = re.compile(r"(?:^|[;\s(])(?:export\s+|local\s+)?([A-Z_][A-Z0-9_]*)=")


def anchor_vars(text):
    roots = {m.group(1) for m in ROOT_DEF.finditer(text)}
    tops = {m.group(1) for m in TOP_DEF.finditer(text)}
    defs = {}
    for line in text.splitlines():
        for m in ANY_DEF.finditer(line):
            defs.setdefault(m.group(1), []).append(line.strip())
    conflict = {}
    for v in roots | tops:
        other = [d for d in defs.get(v, []) if not (ROOT_DEF.search(d) or TOP_DEF.search(d))]
        if other:
            conflict[v] = other
    return roots - conflict.keys(), tops - conflict.keys(), conflict


def sub_shell(text):
    roots, tops, conflict = anchor_vars(text)
    n = 0

    def rep(prefix):
        def f(m):
            nonlocal n
            n += 1
            return m.group(1) + prefix + NEW_OF[m.group(2)]
        return f

    text = re.sub("(" + DIRECT_ANCHOR + ")(" + OLD_ALT + r")(?![\w-])", rep("harness/"), text)
    for v in sorted(roots):
        text = re.sub(r'("?\$\{?' + v + r'\}?"?/)(' + OLD_ALT + r")(?![\w-])", rep("harness/"), text)
        # git -C "$ROOT" … HEAD:<경로> — 객체 경로는 리포 최상위 기준
        if re.search(r'git -C "?\$\{?' + v + r'\}?"?', text):
            text = re.sub(r"(HEAD:)(" + OLD_ALT + r")(?![\w-])", rep("feature-pack/fable-team/harness/"), text)
    for v in sorted(tops):
        text = re.sub(r'("?\$\{?' + v + r'\}?"?/)(' + OLD_ALT + r")(?![\w-])", rep("feature-pack/fable-team/harness/"), text)
    # bin 의 형제 키트: <bin>/../harness-install → <bin>/../kit
    text, k = re.subn(r"(?<![\w.-])\.\./harness-install/", "../kit/", text)
    n += k
    return text, n, conflict


def sub_py(text, in_scripts):
    n = 0
    pairs = [('"scripts" / "fable-team-bin"', '"harness" / "bin"'),
             ('"scripts" / "harness-install"', '"harness" / "kit"'),
             ('"tools" / "comm-canonical"', '"harness" / "comm"'),
             ('"scripts/harness-install', '"harness/kit'),
             ('"scripts/fable-team-bin', '"harness/bin'),
             ('"tools/comm-canonical', '"harness/comm'),
             ('ROOT / "design/harness', 'ROOT / "harness/design/harness')]
    for a, b in pairs:
        k = text.count(a)
        if k:
            text = text.replace(a, b)
            n += k
    if in_scripts and n:
        # tests/scripts → harness/tests/scripts: 리포 루트가 한 칸 더 위 (parents[2] → parents[3])
        text, k = re.subn(r"parents\[2\]", "parents[3]", text)
        n += k
    return text, n, {}


def main():
    harness = Path(sys.argv[1]).resolve()
    apply = "--apply" in sys.argv
    tests = harness / "tests"
    total = 0
    for p in sorted(tests.rglob("*")):
        if not p.is_file() or p.suffix not in (".sh", ".py", ""):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if p.suffix == ".py":
            new, n, conflict = sub_py(text, p.parent.name == "scripts")
        else:
            new, n, conflict = sub_shell(text)
        rel = p.relative_to(harness)
        for v, lines in conflict.items():
            print(f"CONFLICT {rel} {v}: {lines[:2]}")
        if n:
            total += n
            print(f"SUB {n:4d} {rel}")
            if apply:
                p.write_text(new, encoding="utf-8")
        for i, line in enumerate(new.splitlines(), 1):
            if OLD_RE.search(line):
                print(f"LEFT {rel}:{i}: {line.strip()[:160]}")
    print(f"TOTAL {total} apply={int(apply)}")


if __name__ == "__main__":
    main()
