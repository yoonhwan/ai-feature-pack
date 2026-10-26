#!/usr/bin/env python3
"""r938 r3 변이 시험 — 고친 사본을 10가지(r2 6 + r3 4)로 망가뜨려 «빨강이어야 할 칸» 이 정말 빨강이 되는지 본다(증거 harness/evidence/r938/mutation.txt).

DA⑥ r1 지적 4(«변이 실행기는 전체 rc≠0 만 봄») 반영: 변이마다 그 축의 시험 카드 이름을 적고, 그 카드가 FAIL 인지 단언한다.
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
FETCH_OLD = """  local rc=0 i
  if command -v fm_fetch >/dev/null 2>&1; then fm_fetch "$@"; return $?; fi
  for i in 1 2; do nf_bound 7 git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3" && return 0; rc=$?; done
  return "$rc"
}"""
BOUND_OLD = """  command -v python3 >/dev/null 2>&1 || { echo "WARN python3 없음 — ${sec}초 상한을 걸 수 없어 호출 거절" >&2; return 127; }"""
MULT_OLD = '  _gate_mult="$(nf_mult_commits "$SEAT_REPO" "$_FEAT" "$_gate_br")"; _gate_cap="$(nf_cap "$(nf_fixed cherry)" "$_gate_mult")"' 
TRAP_OLD = """trap 'if [ -n "${_SK:-}" ]; then bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null; fi; rm -f "${_CR_TMP:-}"' EXIT   # r888: 꺼낸 카드 임시 파일도 같이
nf_bound "$_SHCAP" bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' nano-close "" "$SEAT" "$SEAT" "세트 ${RESULT:0:60}" nano-close)" >/dev/null"""
TRAP_NEW = """nf_bound "$_SHCAP" bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' nano-close "" "$SEAT" "$SEAT" "세트 ${RESULT:0:60}" nano-close)" >/dev/null
trap 'if [ -n "${_SK:-}" ]; then bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null; fi; rm -f "${_CR_TMP:-}"' EXIT   # r888: 꺼낸 카드 임시 파일도 같이"""
OVR_OLD = '  if [ "${#bad[@]}" -eq 0 ]; then'
TREE1_OLD = "    pids = tree(p.pid) | {p.pid}"
TREE2_OLD = "    pids |= tree(p.pid)"
RS_OLD = """        bad+=("⑥리서치 origin/main fetch 실패 — 옛 ref 대조 0(R22) · 7초+재시도 1 상한 · 다시: 같은 명령(일시 장애면)")
      else
"""
RS_NEW = """        echo "WARN 리서치 — origin main fetch 실패(로컬 origin/main 로 대조)"
      fi
      if :; then
"""
OM_OLD = '      if [ "$_om_rc" -eq 124 ]; then'

MUT = [
    ("ⓐ 시각 줄 끔(step 무출력)", [(STEP_OLD, "step() { :; }")], ["[ⓐ]"]),
    ("ⓐ 시각 줄을 stdout 으로(자리 바뀜)", [(STEP_OLD, STEP_OLD.replace(" >&2; }", "; }"))], ["[ⓐ]"]),
    ("ⓑ fetch 상한 끔(옛 판 무상한 git fetch)", [(FETCH_OLD, '  git -C "$1" fetch -q "$2" "$3"\n}')], ["[ⓑ]"]),
    ("ⓒ 하위 상한 끔(nf_bound = 그대로 실행)", [(BOUND_OLD, '  "$@"; return $?')], ["[ⓒ]", "[ⓕ]", "[ⓖ]", "[ⓗ]"]),
    ("ⓘ 배수 고정 1(작업량 무시)", [(MULT_OLD, '  _gate_mult=1; _gate_cap="$(nf_cap "$(nf_fixed cherry)" "$_gate_mult")"')], ["[ⓘ]"]),
    ("ⓕ abort trap 을 prepare 뒤로", [(TRAP_OLD, TRAP_NEW)], ["[ⓕ]"]),
    # r3(astra r2 N1~N4 · DECISION-r938-r3-final): 굵은 3자리 + nf_bound 자손 회수
    ("ⓕ bad 있을 때 override 빼기 끔", [(OVR_OLD, "  if :; then")], ["[ⓕ]"]),
    ("ⓖ 자손 모으기 끔(killpg 만)", [(TREE1_OLD, "    pids = {p.pid}"), (TREE2_OLD, "    pass")], ["[ⓖ]"]),
    ("ⓙ 리서치 fetch 실패를 WARN 로 복귀", [(RS_OLD, RS_NEW)], ["[ⓙ]"]),
    ("ⓛ 둘째 cherry rc124 분기 끔", [(OM_OLD, '      if false; then')], ["[ⓛ]"]),
]


def run(copy: Path):
    r = subprocess.run(["/bin/bash", str(copy / "tests/test_nano_close_step_timing_r938.sh")],
                       capture_output=True, text=True, timeout=2400)
    return r.returncode, r.stdout + r.stderr


bad = 0
for name, pairs, want in MUT:
    tmp = Path(tempfile.mkdtemp()) / "fable-team" / "harness"   # 시험이 $HERE/../../harness/kit 를 보므로 부모 폴더 이름을 지킨다
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
    print(f"=== 변이: {name} → rc={rc} fail={len(fails)} (기대 칸: {' '.join(want)})")
    for ln in fails:
        print("   " + ln[:170])
    if rc == 0:
        bad += 1
        print("   !! 변이가 초록 = 시험이 안 잡는다")
        continue
    hit = [w for w in want if any(ln.startswith("FAIL " + w) for ln in fails)]
    if len(hit) == len(want):
        print(f"   OK 기대 칸 전부 빨강: {' '.join(want)}")
    else:
        bad += 1
        print(f"   !! 기대 칸이 안 빨강: 없음 {' '.join(w for w in want if w not in hit)}")
print("MUTATION-ALL-RED" if bad == 0 else f"MUTATION-WEAK {bad}")
sys.exit(0 if bad == 0 else 1)
