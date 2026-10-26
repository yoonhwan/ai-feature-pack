#!/usr/bin/env python3
"""r926 변이 시험 — 고친 사본을 4가지로 망가뜨려 새 시험이 «빨강» 이 되는지 본다(증거 harness/evidence/r926/mutation.txt)."""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]   # harness
LEVEL = "bin/ft-autonomy-level.sh"
LIB = "bin/ft-team-lib.sh"

MUT = [
    ("명부 후보 = cwd 리포 공용 루트 먼저(옛 판) 복귀", LEVEL, [
        ('rr="$(_roster_common_root "$ROOT")" || rr=""',
         'rr="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)" || rr=""'),
        ('for p in "$ROOT/.fable-team/seats-planner.json" "${rr:+$rr/.fable-team/seats-planner.json}"; do',
         'for p in "${rr:+$rr/.fable-team/seats-planner.json}" "$ROOT/.fable-team/seats-planner.json"; do'),
    ]),
    ("못 찾음 rc1 → rc0(조용한 통과)", LEVEL, [
        ('못 찾음(찾은 자리 2곳: $ROOT/.fable-team/seats-planner.json · ${rr:-<공용 루트 못 풂>}/.fable-team/seats-planner.json)" >&2; return 1',
         '못 찾음(찾은 자리 2곳: $ROOT/.fable-team/seats-planner.json · ${rr:-<공용 루트 못 풂>}/.fable-team/seats-planner.json)" >&2; return 0'),
    ]),
    ("timeout 없으면 git 직접(옛 판) 복귀", LIB, [
        ('  [ -n "$to" ] || { echo unknown; return 0; }\n  n="$("$to" 7 git -C "$r" rev-list --count HEAD..origin/main 2>/dev/null)"',
         '  if [ -n "$to" ]; then n="$("$to" 7 git -C "$r" rev-list --count HEAD..origin/main 2>/dev/null)"; else n="$(git -C "$r" rev-list --count HEAD..origin/main 2>/dev/null)"; fi'),
    ]),
    ("가지 검사 끔(언제나 contains)", LIB, [
        ('st=unknown; [ -n "$root" ] && st="$(_ft_team_branch_state "$root")"', 'st=contains'),
    ]),
]


def run(copy: Path):
    r = subprocess.run(["bash", str(copy / "tests/test_r926_root_roster_twin_warn.sh")],
                       capture_output=True, text=True, timeout=900)
    return r.returncode, r.stdout + r.stderr


bad = 0
for name, rel, pairs in MUT:
    tmp = Path(tempfile.mkdtemp()) / "h"
    shutil.copytree(H, tmp)
    p = tmp / rel
    s = p.read_text(encoding="utf-8")
    miss = [old for old, _ in pairs if old not in s]
    if miss:
        print(f"MUTATION-APPLY-FAIL {name}");
        bad += 1
        continue
    for old, new in pairs:
        s = s.replace(old, new)
    p.write_text(s, encoding="utf-8")
    if rel in (LEVEL, LIB):
        shutil.copy2(p, tmp / "kit/fable-team" / rel)
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
