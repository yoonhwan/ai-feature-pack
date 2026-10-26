#!/usr/bin/env python3
"""r938 변이 시험 — 고친 사본을 3가지로 망가뜨려 새 시험이 «빨강» 이 되는지 본다(증거 harness/evidence/r938/mutation.txt).

ⓐ 시각 줄 끔 · ⓑ fetch 상한 끔(옛 판 무상한 git fetch) · ⓒ 하위 검사 상한 끔 — 각각 그 축의 PASS 줄이 FAIL 로 바뀌어야 한다.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]   # harness
BIN = "bin/ft-nano-close.sh"
KIT = "kit/fable-team/bin/ft-nano-close.sh"

STEP_OLD = """step() { printf 'STEP %s +%ss\\n' "$1" "$(( $(date +%s) - T0 ))" >&2; }"""
FETCH_OLD = """  local tb rc=0 i\n  if command -v fm_fetch >/dev/null 2>&1; then fm_fetch "$@"; return $?; fi\n  tb="$(nf_tb)" || { echo "WARN timeout/gtimeout 없음 — fetch 거절(옛 ref 로 대조하지 않는다)" >&2; return 127; }\n  for i in 1 2; do "$tb" 7 git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3" && return 0; rc=$?; done\n  return "$rc"\n}"""
BOUND_OLD = """  "$tb" "$sec" "$@"\n}"""

MUT = [
    ("ⓐ 시각 줄 끔(step 무출력)", [
        (STEP_OLD, "step() { :; }"),
    ]),
    ("ⓑ fetch 상한 끔(옛 판 무상한 git fetch)", [
        (FETCH_OLD, """  git -C "$1" fetch -q "$2" "$3"\n}"""),
    ]),
    ("ⓒ 하위 검사 상한 끔(nf_bound = 그대로 실행)", [
        (BOUND_OLD, """  "$@"\n}"""),
    ]),
]


def run(copy: Path):
    r = subprocess.run(["/bin/bash", str(copy / "tests/test_nano_close_step_timing_r938.sh")],
                       capture_output=True, text=True, timeout=1800)
    return r.returncode, r.stdout + r.stderr


bad = 0
for name, pairs in MUT:
    tmp = Path(tempfile.mkdtemp()) / "fable-team" / "harness"   # 시험이 $HERE/../../harness/kit 를 보므로 부모 폴더 이름(fable-team/harness)을 지킨다
    shutil.copytree(H, tmp)
    p = tmp / BIN
    s = p.read_text(encoding="utf-8")
    miss = [old for old, _ in pairs if old not in s]
    if miss:
        print(f"MUTATION-APPLY-FAIL {name}")
        bad += 1
        continue
    for old, new in pairs:
        s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    shutil.copy2(p, tmp / KIT)
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
