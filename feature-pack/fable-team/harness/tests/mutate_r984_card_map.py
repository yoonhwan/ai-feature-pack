#!/usr/bin/env python3
"""r984 변이 시험 — ft_card_map_lint.py 사본을 2가지로 망가뜨려 새 시험이 «빨강» 이 되는지 본다.

완료 조건의 변이 2종: «시험 칸 빈 행 통과»(= ⓐ 검사 끔) · «옛 카드 REJECT»(= 날짜 스위치 무시).
증거 줄은 harness/evidence/r984/mutation.txt 에 남긴다(이 스크립트 stdout).
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]   # harness
MOD = "bin/ft_card_map_lint.py"
KIT = "kit/fable-team/bin/ft_card_map_lint.py"

MUT = [
    ("ⓐ 검사 끔(시험 칸 빈 행 통과)", [
        ("        if not pick(row, ti).strip():", "        if False:"),
    ]),
    ("날짜 스위치 무시(옛 카드도 REJECT)", [
        ("    strict = added >= sw", "    strict = True"),
    ]),
    ("이스케이프 보존 분할 되돌림(셀 안 | 가 열 경계)", [
        ('    return [c.strip().replace("\\\\|", "|") for c in re.split(r"(?<!\\\\)\\|", body)]',
         '    return [c.strip() for c in body.split("|")]'),
    ]),
]


def run(copy: Path):
    r = subprocess.run(["bash", str(copy / "tests/test_card_map_lint_r984.sh")],
                       capture_output=True, text=True, timeout=1800)
    return r.returncode, r.stdout + r.stderr


bad = 0
for name, pairs in MUT:
    tmp = Path(tempfile.mkdtemp()) / "h"
    shutil.copytree(H, tmp, symlinks=True, ignore=shutil.ignore_patterns(".git"))
    p = tmp / MOD
    s = p.read_text(encoding="utf-8")
    miss = [old for old, _ in pairs if old not in s]
    if miss:
        print(f"MUTATION-APPLY-FAIL {name} — 조각 없음: {miss[0][:60]}")
        bad += 1
        continue
    for old, new in pairs:
        s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    shutil.copy2(p, tmp / KIT)   # lint 는 키트 사본을 부른다
    rc, out = run(tmp)
    fails = [ln for ln in out.splitlines() if ln.startswith("FAIL ")]
    print(f"=== 변이: {name} → rc={rc} fail={len(fails)}")
    for ln in fails:
        print("   " + ln[:160])
    if rc == 0:
        bad += 1
        print("   !! 변이가 초록 = 시험이 안 잡는다")
print("MUTATION-ALL-RED" if bad == 0 else f"MUTATION-WEAK {bad}")
sys.exit(0 if bad == 0 else 1)
