#!/usr/bin/env python3
"""r938 r3 변이 시험 — 고친 사본을 10가지(r2 6 + r3 4)로 망가뜨려 «빨강이어야 할 칸» 이 정말 빨강이 되는지 본다(증거 harness/evidence/r938/mutation.txt).

DA⑥ r1 지적 4(«변이 실행기는 전체 rc≠0 만 봄») 반영: 변이마다 그 축의 시험 카드 이름을 적고, 그 카드가 FAIL 인지 단언한다.
r1318(시험 나눔): 시험 1개가 70초를 넘어 4조각(test_nano_close_step_timing_r938_{a,b,c,d}.sh)으로 갈렸으므로
  변이마다 «그 축이 사는 조각» 만 돌린다(하드 룰 22 «변이는 그 칸만») — 조각별로 기대 칸을 적는다.
r1318 r2(arch#207 판단): 상한을 끈 변이는 «상한을 넘어 계속 도는 것» 자체가 잡힌 신호다 —
  변이 실행을 «그 조각 무변이 시간 × 2(최소 15초 · 최대 70초)» timeout 으로 감싸고, timeout(rc124)을 변이 탐지로 센다.
  timeout 을 탐지로 세는 것은 «상한을 끈» 3실행(ⓑ · ⓒ-c · ⓒ-d)뿐 — 나머지 7은 기대 칸 FAIL 이어야 탐지다(부하로 끊긴 rc124 를 탐지로 세지 않는다).
r1318 r3(arch#207 반송): 한 회차가 662초 > 7분(하드 룰 22) — 초록 4조각과 변이 실행을 «동시 4» 로 병렬로 돌린다.
  timeout 은 «조각 하나가 혼자 돌 때의 무변이 초» 로 잡는다(병렬 부하로 초록이 느려져도 상한이 흔들리지 않게 · 무변이 1회 실측값을 쓴다).
"""
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

H = Path(__file__).resolve().parents[1]   # harness
BIN = "bin/ft-nano-close.sh"
KIT = "kit/fable-team/bin/ft-nano-close.sh"
PARTS = ("a", "b", "c", "d")
CAP_MIN, CAP_MAX = 15, 70   # 하드 룰 22: 시험 1개 단독 70초
PARALLEL = 4                # 동시 실행 상한(arch#207: 4개씩 병렬)

STEP_OLD = """step() { printf 'STEP %s +%ss\\n' "$1" "$(( $(date +%s) - T0 ))" >&2; }"""
FETCH_OLD = """  local rc=0 i
  if command -v fm_fetch >/dev/null 2>&1; then fm_fetch "$@"; return $?; fi
  for i in 1 2; do nf_bound 7 git -c gc.auto=0 -C "$1" fetch --quiet "$2" "$3" && return 0; rc=$?; done
  return "$rc"
}"""
BOUND_OLD = """  command -v python3 >/dev/null 2>&1 || { echo "WARN python3 없음 — ${sec}초 상한을 걸 수 없어 호출 거절" >&2; return 127; }"""
MULT_OLD = '  _gate_mult="$(nf_mult_commits "$SEAT_REPO" "$_FEAT" "$_gate_br")"; _gate_cap="$(nf_cap "$(nf_fixed cherry)" "$_gate_mult")"' 
TRAP_OLD = """trap 'if [ -n "${_SK:-}" ]; then bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null; fi; rm -f "${_CR_TMP:-}" "${_CB_TMP:-}"' EXIT   # r888: 꺼낸 카드 임시 파일도 같이(r960: 가지 판도)
nf_bound "$_SHCAP" bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' nano-close "" "$SEAT" "$SEAT" "세트 ${RESULT:0:60}" nano-close)" >/dev/null || { _shr=$?; echo "REJECT $SEAT"; echo "  - 사건 원장 prepared 실패$([ "$_shr" -eq 124 ] && echo " — 시간 초과(${_SHCAP}s 상한)") — 닫기 거절(PLAN §3-1)"; exit 1; }"""
# r1318: TRAP_NEW = 위 두 줄의 «자리» 만 바꾼다(등록을 prepare 뒤로) — r960 이 두 줄에 "${_CB_TMP:-}"·REJECT 처리를 덧붙여 옛 문자열이 안 맞았다(적용 불가 1건).
TRAP_NEW = """nf_bound "$_SHCAP" bash "$HERE/ft-sheet-events.sh" prepare "$_SK" "$(python3 -c 'import json,sys;print(json.dumps(dict(zip(("ev","team","id","seat","ref","by"),sys.argv[1:]))))' nano-close "" "$SEAT" "$SEAT" "세트 ${RESULT:0:60}" nano-close)" >/dev/null || { _shr=$?; echo "REJECT $SEAT"; echo "  - 사건 원장 prepared 실패$([ "$_shr" -eq 124 ] && echo " — 시간 초과(${_SHCAP}s 상한)") — 닫기 거절(PLAN §3-1)"; exit 1; }
trap 'if [ -n "${_SK:-}" ]; then bash "$HERE/ft-sheet-events.sh" abort "$_SK" 2>/dev/null; fi; rm -f "${_CR_TMP:-}" "${_CB_TMP:-}"' EXIT   # r888: 꺼낸 카드 임시 파일도 같이(r960: 가지 판도)"""
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

# (변이 이름, (옛, 새) 짝들, {조각: [빨강이어야 할 칸]}, {«상한 끔» 이라 timeout 을 탐지로 세는 조각})
MUT = [
    ("ⓐ 시각 줄 끔(step 무출력)", [(STEP_OLD, "step() { :; }")], {"a": ["[ⓐ]"]}, set()),
    ("ⓐ 시각 줄을 stdout 으로(자리 바뀜)", [(STEP_OLD, STEP_OLD.replace(" >&2; }", "; }"))], {"a": ["[ⓐ]"]}, set()),
    ("ⓑ fetch 상한 끔(옛 판 무상한 git fetch)", [(FETCH_OLD, '  git -C "$1" fetch -q "$2" "$3"\n}')], {"b": ["[ⓑ]"]}, {"b"}),
    ("ⓒ 하위 상한 끔(nf_bound = 그대로 실행)", [(BOUND_OLD, '  "$@"; return $?')], {"c": ["[ⓒ]"], "d": ["[ⓕ]", "[ⓖ]", "[ⓗ]"]}, {"c", "d"}),
    ("ⓘ 배수 고정 1(작업량 무시)", [(MULT_OLD, '  _gate_mult=1; _gate_cap="$(nf_cap "$(nf_fixed cherry)" "$_gate_mult")"')], {"c": ["[ⓘ]"]}, set()),
    # 이 변이를 잡는 칸 = ⓕ2 «prepare 잘린 뒤 .prepared 0»(r960 이 «시간 초과» 표기를 prepare 실패 처리로 옮겨 [ⓕ] 표기 칸은 안 빨개진다 · 실측)
    ("ⓕ abort trap 을 prepare 뒤로", [(TRAP_OLD, TRAP_NEW)], {"d": ["ⓕ2"]}, set()),
    # r3(astra r2 N1~N4 · DECISION-r938-r3-final): 굵은 3자리 + nf_bound 자손 회수
    ("ⓕ bad 있을 때 override 빼기 끔", [(OVR_OLD, "  if :; then")], {"d": ["[ⓕ]"]}, set()),
    ("ⓖ 자손 모으기 끔(killpg 만)", [(TREE1_OLD, "    pids = {p.pid}"), (TREE2_OLD, "    pass")], {"d": ["[ⓖ]"]}, set()),
    ("ⓙ 리서치 fetch 실패를 WARN 로 복귀", [(RS_OLD, RS_NEW)], {"b": ["[ⓙ]"]}, set()),
    ("ⓛ 둘째 cherry rc124 분기 끔", [(OM_OLD, '      if false; then')], {"b": ["[ⓛ]"]}, set()),
]

PART = "tests/test_nano_close_step_timing_r938_%s.sh"


def run(copy: Path, part: str, cap: int):
    """조각 1개 실행 — cap 초를 넘으면 프로세스 묶음째 끝낸다(rc124)."""
    t0 = time.time()
    p = subprocess.Popen(["/bin/bash", str(copy / (PART % part))],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, start_new_session=True)
    timed_out = False
    try:
        out, _ = p.communicate(timeout=cap)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        timed_out = True
        out = ""
        for sig in (signal.SIGTERM, signal.SIGKILL):   # 묶음째(자식 sleep 90 포함)
            try:
                os.killpg(p.pid, sig)
            except ProcessLookupError:
                pass
            try:
                out, _ = p.communicate(timeout=5)
                break
            except subprocess.TimeoutExpired:
                out = out or ""
        rc = 124
    return rc, out or "", time.time() - t0, timed_out


def fresh():
    tmp = Path(tempfile.mkdtemp()) / "fable-team" / "harness"   # 시험이 $HERE/../../harness/kit 를 보므로 부모 폴더 이름을 지킨다
    shutil.copytree(H, tmp)
    return tmp


def drop(tmp: Path):
    shutil.rmtree(tmp.parents[1], ignore_errors=True)


bad = 0
round0 = time.time()

# ── 1) 초록 대조 — 4조각을 동시 4로 한 번에(무변이 · 하드 룰 22 상한 70초)
base = fresh()
green: dict = {}
with ThreadPoolExecutor(max_workers=PARALLEL) as ex:   # 동시 4 상한
    futs = {p: ex.submit(run, base, p, CAP_MAX) for p in PARTS}
    for part in PARTS:
        green[part] = futs[part].result()
drop(base)
print("== 초록 대조(무변이 · 4조각 병렬 · 같은 timeout 안 rc0 이어야 한다)")
for part in PARTS:
    rc, out, sec, to = green[part]
    if rc != 0:
        bad += 1
        print(f"=== 대조: 조각 {part} rc={rc}{'(timeout)' if to else ''} {sec:.0f}s — 무변이 조각이 초록이 아니다")
        for ln in out.splitlines():
            if ln.startswith("FAIL "):
                print("   " + ln[:170])
    else:
        print(f"=== 대조: 조각 {part} rc=0 {sec:.0f}s")
# timeout = «그 조각이 혼자 돌 때의 초 × 2»(arch#207 r3). 위 값은 4조각 병렬 측정이라 부하가 섞인다 —
#   혼자 돌린 실측값(SOLO_REF · 2026-11-02 r1318 측정 · a 10s b 41s c 50s d 52s)과 «작은 쪽» 을 쓴다. 상한은 그때보다 느슨해지지 않는다.
SOLO_REF = {"a": 10, "b": 41, "c": 50, "d": 52}
SOLO = {p: min(green[p][2], SOLO_REF[p]) if green[p][0] == 0 else SOLO_REF[p] for p in PARTS}
cap = {p: max(CAP_MIN, min(CAP_MAX, int(2 * SOLO[p] + 0.999))) for p in PARTS}

# ── 2) 변이 — 조각 단위 실행을 동시 4로
jobs = []   # (변이 index, 조각, want, cap_detect, copy)
for i, (name, pairs, parts, capd) in enumerate(MUT):
    tmp = fresh()
    p = tmp / BIN
    s = p.read_text(encoding="utf-8")
    miss = [old for old, _ in pairs if old not in s]
    if miss:
        print(f"MUTATION-APPLY-FAIL {name}")
        bad += 1
        drop(tmp)
        continue
    for old, new in pairs:
        s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    shutil.copy2(p, tmp / KIT)
    for part, want in parts.items():   # 하드 룰 22: 변이는 «그 칸이 사는 조각» 만 돈다
        jobs.append((i, part, want, part in capd, tmp))

res: dict = {}
with ThreadPoolExecutor(max_workers=PARALLEL) as ex:   # 동시 4 상한
    futs = {n: ex.submit(run, j[4], j[1], cap[j[1]]) for n, j in enumerate(jobs)}
    for n in range(len(jobs)):
        res[n] = futs[n].result()

for n, (i, part, want, capd, tmp) in enumerate(jobs):
    name = MUT[i][0]
    rc, out, sec, to = res[n]
    fails = [ln for ln in out.splitlines() if ln.startswith("FAIL ")]
    if to:
        if capd:   # «상한 끔» 실행만 timeout 을 탐지로 센다
            print(f"=== 변이: {name} → 조각 {part} rc=124 timeout={cap[part]}s — 변이 탐지(상한을 넘어 계속 돎 · 기대 칸: {' '.join(want)})")
        else:
            bad += 1
            print(f"=== 변이: {name} → 조각 {part} rc=124 timeout={cap[part]}s — !! 부하로 끊김(탐지로 안 셈 · 기대 칸: {' '.join(want)})")
        continue
    print(f"=== 변이: {name} → 조각 {part} rc={rc} fail={len(fails)} {sec:.0f}s (기대 칸: {' '.join(want)})")
    for ln in fails:
        print("   " + ln[:170])
    if rc == 0:
        bad += 1
        print(f"   !! 변이가 초록(조각 {part}) = 시험이 안 잡는다")
        continue
    hit = [w for w in want if any(ln.startswith("FAIL " + w) for ln in fails)]
    if len(hit) == len(want):
        print(f"   OK 기대 칸 전부 빨강: {' '.join(want)}")
    else:
        bad += 1
        print(f"   !! 기대 칸이 안 빨강: 없음 {' '.join(w for w in want if w not in hit)}")
for tmp in {j[4] for j in jobs}:
    drop(tmp)

total = time.time() - round0
print(f"단계별 초: 초록(4조각 병렬) {max(green[p][2] for p in PARTS):.0f}s · 변이({len(jobs)}실행 · 동시 {PARALLEL}) {sum(res[n][2] for n in range(len(jobs))):.0f}s(합) → 회차 {total:.0f}s (목표 ≤ 420s)")
print("MUTATION-ALL-RED" if bad == 0 else f"MUTATION-WEAK {bad}")
sys.exit(0 if bad == 0 else 1)
