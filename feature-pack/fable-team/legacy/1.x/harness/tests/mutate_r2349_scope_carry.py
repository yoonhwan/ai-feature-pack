#!/usr/bin/env python3
"""r2349 변이 시험 — 고친 사본을 12가지로 망가뜨려 새 시험(test_autonomy_scope_carry_r2349.sh)이 그 사례에서 «빨강» 이 되는지 본다.
변이마다 원본으로 같은 시험을 1회 더 돌려(ORIG) 초록임을 확인한다. 사본은 mktemp 아래에서만 · 실 bin/kit 손 0."""
import concurrent.futures as cf
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

H = Path(__file__).resolve().parents[1]          # harness
TEST = "tests/test_autonomy_scope_carry_r2349.sh"
SCOPE = "bin/ft-autonomy-scope.sh"
LEVEL = "bin/ft-autonomy-level.sh"
MAIN = "bin/ft-autonomy.sh"

# (이름, [(파일, 옛 글자, 새 글자)…], 이 변이가 빨강으로 만들어야 하는 FAIL 사례 머리말)
MUT = [
    ("M1 C2 기본값을 기본표로 되돌림", [(LEVEL,
        'if [ "$ON_LEVEL" = full ] && scope_prev; then', 'if false; then')], ["① off → on"]),
    ("M2 C4 비교 지움", [(SCOPE,
        '  LOWER_CELL=""\n  [ -z "$lw" ]', '  LOWER_CELL=""; if :; then return 0; fi\n  [ -z "$lw" ]')], ["② on --max 30", "⑥b ⑥ + --classes"]),
    ("M3 SCOPE_GRANT_RE 에 lower 칸 안 넣음", [(MAIN,
        '( lower=[0-9]{10}\\.[0-9]{6})?$', '$')], ["③ lower 칸 줄 = 위변조 아님"]),
    ("M4 C1 이 마지막 줄 대신 첫 줄", [(SCOPE,
        '{last = $0} END {if (last != "") printf "%s", last}', '{if (first == "") first = $0} END {if (first != "") printf "%s", first}')], ["① off → on"]),
    ("M5 repos 비교 지움", [(SCOPE,
        '  [ "$P_REPOS" = byz,pack ] && [ "$rp" = byz ] && low=1\n', '')], ["⑦ byz,pack → byz"]),
    ("M6 --lower 꼴 검사 지움", [(SCOPE,
        '  [ -z "$lw" ] || [[ "$lw" =~ ^[0-9]{10}\\.[0-9]{6}$ ]] || scope_err', '  : || scope_err')], ["⑩ --lower abc"]),
    ("M7 C1 이 위변조 뒤 줄도 읽음", [(SCOPE,
        'then log_mode >/dev/null 2>&1 || return 1; fi', 'then :; fi')], ["⑨ 위변조 뒤 on-check", "⑨ 위변조 scope-status"]),
    ("M8 C1 의 level 거름 지움", [(SCOPE,
        "awk '$0 ~ /(^| )level=mid( |$)/ {next} {last = $0} END {if (last != \"\") printf \"%s\", last}'", "tail -1")], ["⑭ mid 줄"]),
    ("M9 --lower 시각 검사(ⓑ ⓒ) 지움", [(SCOPE,
        '    [ "$s" -gt "$((10#$P_AT))" ] || scope_err', '    : || scope_err'),
        (SCOPE, '    [ "$s" -le "$(now_epoch)" ] || scope_err', '    : || scope_err')],
        ["⑯ --lower 초 = 직전 at", "⑯ --lower 가 지금보다 뒤"]),
    ("M10 classes 비교(C1 ⊄ 새) 지움", [(SCOPE,
        '  for c in ${P_CLASSES//,/ }; do case ",$cl," in *",$c,"*) ;; *) low=1 ;; esac; done', '  :')],
        ["⑮ code 빼기", "⑮b 엇갈린 집합"]),
    ("M11 --lower 재사용 검사(ⓓ) 지움", [(SCOPE,
        '    awk -v t="$lw" \'$1=="approve-scope" && $NF=="lower="t {f=1} END{exit !f}\' "$LOG" 2>/dev/null && scope_err', '    false && scope_err')],
        ["⑰ 이미 쓴 --lower"]),
    ("M12 codemax·classes 이어받기 조건 지움", [(LEVEL,
        'mx="$P_MAX"; dl="$P_DAILY"; cl="$P_CLASSES"; cm=""; rp="$P_REPOS"', 'mx="$P_MAX"; dl="$P_DAILY"; cm="10"')], ["⑲ 직전 classes=docs"]),
]


def run(copy: Path):
    r = subprocess.run(["bash", str(copy / TEST)], capture_output=True, text=True, timeout=70)   # 하드 룰 22: 시험 1개 70초
    return r.returncode, r.stdout + r.stderr


def fails(out: str):
    return [ln for ln in out.splitlines() if ln.startswith("FAIL ")]


def one(item):
    name, pairs = item
    tmp = Path(tempfile.mkdtemp()) / "h"
    shutil.copytree(H, tmp)
    for rel, old, new in pairs:
        p = tmp / rel
        s = p.read_text(encoding="utf-8")
        if old not in s:
            return name, "APPLY-FAIL", [], []
        p.write_text(s.replace(old, new, 1), encoding="utf-8")
        shutil.copy2(p, tmp / "kit/fable-team" / rel)
    rc, out = run(tmp)
    return name, rc, fails(out), []


want = {name: expect for name, _, expect in MUT}
with cf.ThreadPoolExecutor(max_workers=2) as ex:   # 동시 2개 — 런 1개 상한 70초(하드 룰 22) 안에 끝나게
    results = list(ex.map(one, [(n, p) for n, p, _ in MUT]))
    org = list(ex.map(lambda _: run(Path(H)), range(1)))

bad = 0
org_ok = all(rc == 0 for rc, _ in org)
print(f"ORIG 원본 {TEST} → {'초록 fail=0' if org_ok else '빨강(원본이 이미 실패)'}")
if not org_ok:
    bad += 1
for name, rc, fl, _ in results:
    hit = [e for e in want[name] if any(e in ln for ln in fl)]
    ok = rc != 0 and len(hit) == len(want[name])
    print(f"=== 변이: {name} → rc={rc} fail={len(fl)} 기대사례적중={len(hit)}/{len(want[name])} {'OK' if ok else '!! 안 잡힘'}")
    for ln in fl[:6]:
        print("   " + ln[:120])
    if not ok:
        bad += 1
print("MUTATION-ALL-RED" if bad == 0 else f"MUTATION-WEAK {bad}")
sys.exit(0 if bad == 0 else 1)
