#!/usr/bin/env python3
"""r922a 변이 시험 — 고친 사본을 2가지로 망가뜨려 새 시험이 «빨강» 이 되는지 본다(증거 harness/evidence/r922a/mutation.txt)."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]   # harness
REL = "bin/ft_news_post.py"
COPY = "kit/fable-team/bin/ft_news_post.py"
GUARD = "    if not is_draft() or not goal_gate.armed(state_dir):\n"

MUT = [
    ("초안 분기 끔(옛 판 복귀 = 초안도 [긴급] 통지)", "    if True:\n"),
    ("모든 모드 WARN(발행 모드 통지 끔)", "    if not goal_gate.armed(state_dir):\n"),
]


def run(copy: Path):
    r = subprocess.run(["bash", str(copy / "tests/test_r922a_news_draft_gate_warn.sh")],
                       capture_output=True, text=True, timeout=900)
    return r.returncode, r.stdout + r.stderr


bad = 0
for name, repl in MUT:
    tmp = Path(tempfile.mkdtemp()) / "h"
    shutil.copytree(H, tmp)
    p = tmp / REL
    s = p.read_text(encoding="utf-8")
    if GUARD not in s:
        print(f"MUTATION-APPLY-FAIL {name}")
        bad += 1
        continue
    p.write_text(s.replace(GUARD, repl), encoding="utf-8")
    shutil.copy2(p, tmp / COPY)
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
