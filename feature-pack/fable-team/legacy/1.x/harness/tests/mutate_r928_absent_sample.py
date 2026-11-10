#!/usr/bin/env python3
"""r928 r3 변이 시험 — 고친 판을 망가뜨려 test_r928_watch_rearm_grace.sh 가 «그 시험» 에서 빨강이 되는지 본다.
사본(harness + skill)을 임시 폴더에 떠서 변이마다 따로(병렬) 돌린다 · 원본 파일 쓰기 0. 빨강 시험 칸(ⓐ~ⓚ)을 표로 낸다."""
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

FT = Path(__file__).resolve().parents[2]   # feature-pack/fable-team
COMM = "harness/comm/mbox.sh"
KIT = "harness/kit/fable-team/bin/ft-mbox.sh"
SKILL = "skill/scripts/ft-mbox.sh"
GRACE = [COMM, KIT, SKILL]   # _absent_grace 본문은 세 곳 같다(시험 ① 이 본다) — 같이 망가뜨린다
SAMPLE = [KIT, SKILL]        # watch_sample 은 kit·skill 짝

MUT = [
    ("정수 검사 끔", "ⓔ", GRACE, [
        ('    case "$s" in \'\'|*[!0-9]*) why="본문 깨짐" ;; esac\n    case "$a" in \'\'|*[!0-9]*) why="본문 깨짐" ;; esac\n', ''),
    ]),
    ("쓰기 실패 무시", "ⓕ", SAMPLE, [
        ('_sample_put "$f" "$a" "$now" || { _sample_fail "$f" "쓰기 실패"; return 1; }',
         '_sample_put "$f" "$a" "$now" || true'),
    ]),
    ("지우기 실패 무시", "ⓖ", SAMPLE, [
        ('_sample_put "$f" 0 "$now" || { _sample_fail "$f" "지우기 실패"; return 1; }',
         '_sample_put "$f" 0 "$now" || true'),
    ]),
    ("실패 뒤 옛 표본 안 지움(r4 고침 1)", "ⓕ", SAMPLE, [
        ('  echo "WATCH-ABSENT 이상($2) $1" >&2\n  rm -f "$1" 2>/dev/null\n', '  echo "WATCH-ABSENT 이상($2) $1" >&2\n'),
    ]),
    (".broken 검사 끔(r4 고침 1)", "ⓖ", GRACE, [
        ('  if [ -e "$f.broken" ] || [ -L "$f.broken" ]; then why="표본기 실패 표식"\n  elif [ -L "$f" ]; then why="심링크"',
         '  if [ -L "$f" ]; then why="심링크"'),
    ]),
    ("깨진·미래 첫 칸 되살림(r4 고침 2)", "ⓛ", SAMPLE, [
        ('    case "$s" in \'\'|*[!0-9]*) _sample_fail "$f" "본문 깨짐"; return 1 ;; esac\n', ''),
        ('    s=$((10#$s)); a=$((10#$a))\n    if [ "$s" -gt "$now" ] || [ "$a" -gt "$s" ]; then _sample_fail "$f" "미래 값"; return 1; fi\n',
         '    a=$((10#$a))\n'),
    ]),
    ("300초 검사 끔(언제나 유예)", "ⓒ", GRACE, [
        ('  if [ $((now - a)) -lt "$grace" ]; then', '  if true; then'),
    ]),
    ("300초 검사 끔(유예 0)", "ⓑ", GRACE, [
        ('  if [ $((now - a)) -lt "$grace" ]; then', '  if false; then'),
    ]),
    ("감시 있음 표본이 처음 없음을 안 지움(H2)", "ⓙ", SAMPLE, [
        ('    _sample_put "$f" 0 "$now" || { _sample_fail "$f" "지우기 실패"; return 1; }', '    :'),
    ]),
    ("표본 멈춤 검사 끔", "ⓚ", GRACE, [
        ('      elif [ $((now - s)) -gt "$stale" ]; then why="표본 멈춤 $((now - s))초 전"\n', ''),
    ]),
]


def one(m):
    name, want, files, pairs = m
    tmp = Path(tempfile.mkdtemp()) / "ft"
    shutil.copytree(FT / "harness", tmp / "harness", ignore=shutil.ignore_patterns("evidence"))
    shutil.copytree(FT / "skill", tmp / "skill")
    for rel in files:
        p = tmp / rel
        s = p.read_text(encoding="utf-8")
        for old, new in pairs:
            if old not in s:
                return name, want, -1, [f"MUTATION-APPLY-FAIL {rel}: {old[:60]}"]
            s = s.replace(old, new)
        p.write_text(s, encoding="utf-8")
    r = subprocess.run(["bash", str(tmp / "harness/tests/test_r928_watch_rearm_grace.sh")],
                       capture_output=True, text=True, timeout=3000)
    shutil.rmtree(tmp.parent, ignore_errors=True)
    fails = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith("FAIL ")]
    return name, want, r.returncode, fails


def cells(fails):
    return sorted({m.group(1) for ln in fails if (m := re.match(r"FAIL ([①-⑨ⓐ-ⓩ③]'?)", ln))} |
                  {"유예폭" for ln in fails if ln.startswith("FAIL 유예")})


bad = 0
with ThreadPoolExecutor(max_workers=len(MUT)) as ex:
    results = list(ex.map(one, MUT))
print("| 변이 | 기대 빨강 | rc | FAIL 수 | 빨강 칸 |")
print("|---|---|---|---|---|")
for name, want, rc, fails in results:
    got = cells(fails)
    print(f"| {name} | {want} | {rc} | {len(fails)} | {' '.join(got)} |")
    if rc != 1 or not any(c.startswith(want) for c in got):
        bad += 1
for name, _, _, fails in results:
    print(f"=== {name}")
    for ln in fails[:12]:
        print("   " + ln[:180])
print("MUTATION-ALL-RED" if bad == 0 else f"MUTATION-WEAK {bad}")
sys.exit(0 if bad == 0 else 1)
