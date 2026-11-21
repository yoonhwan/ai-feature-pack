#!/usr/bin/env bash
# test_press_evidence_pick_newest_c_r2381.sh — r2381 ⑨·⑩: 부모 세트 목록을 묶음마다 다시 읽지 않는다(부모당 1번) · 묶음 256개에서도 press 검사가 착지 70초 예산을 먹지 않는다
#   ⑨ 같은 부모 묶음 10개 → 목록·diff 판정 각 1회(기준판 = 10회 → Red)
#   ⑩ 묶음 256개(부모 199) · 최신 통과 → pick·unpaid·cover 몫 7초 안 · git 호출 수 · 기준판 초를 같은 기계에서 함께 적음(기준판 = 묶음 수에 비례 → Red)
#   변이 M7(목록 기억 지움) → ⑨ FAIL(목록 읽기 10회 이상) · 변이마다 원본 1회 더
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_pick_newest_r2381_lib.sh"

# ===== ⑨: 같은 부모 묶음 10개 → 목록·diff 판정 각 1회(기준판 = 10회 → Red) =====
#   ⑨ 는 «10개를 다 판정하는 갈래»(빚 1 · 어느 묶음도 안 덮음)로 둔다 — 멈춤 갈래(빚 0)는 ①·② 가 본다 · 그래야 목록 기억(M7)이 실제로 걸린다
reset_press
adv "worker/r9d.py=debtsrc"; D9="$(sha "$REPO" origin/main)"; debt "$D9" 61
S9="$(wset s9r1 "clients/web/r9.ts=x")"; S9B="$(asrev s9b "$(sha "$REPO" "$D9^")" "$S9")"   # 빚을 조상으로 안 가진 세트 1개
for i in $(seq 1 10); do vb "$S9B" "20261109-0000$(printf %02d "$i")"; done
both "$S9"
[ "$rc" = 1 ] && [[ "$out" == "press 빚 PR #61(착지 ${D9:0:10}) — 담당 o · 복구 뒤 press 1회 — 판정 2946" ]]; ck "⑨ 같은 부모 10묶음 전부 판정(덮는 묶음 0 → debt_line)" $?
df9="$(cnt "$T/fixed.log" ' diff --quiet ')"; ls9="$(cnt "$T/fixed.log" ':docs/rules/press_voice_paths.md')"; rv9="$(cnt "$T/fixed.log" 'rev-list --parents')"
[ "$ls9" = 4 ] && [ "$df9" = 2 ] && [ "$rv9" = 10 ]; ck "⑨ 고친 판: 묶음 판정 ${rv9}회 · 목록 ${ls9}회 · diff ${df9}회(부모당 1번)" $?
db9="$(cnt "$T/base.log" ' diff --quiet ')"; lb9="$(cnt "$T/base.log" ':docs/rules/press_voice_paths.md')"
[ "$db9" -ge 11 ] && [ "$lb9" -ge 13 ]; ck "⑨ 기준판 Red: 목록 ${lb9}회(13 이상) · diff ${db9}회(11 이상)" $?
samebytes; ck "⑨ 출력 = 기준판" $?
mut M7 verify '        if e not in seen:' '        if True:'
landat "$MBIN" "$S9"; n="$(cnt "$GITLOG" ':docs/rules/press_voice_paths.md')"; [ "$n" -ge 7 ]; ck "ⓜM7 목록 기억 지움 → ⑨ 목록 ${n}회(10묶음 다시 읽음) = 계약 깨짐 재현" $?
landat "$BIN" "$S9"; [ "$rc" = 1 ]; ck "ⓜM7 원본 재확인 → ⑨ 통과" $?
echo "단계 초: ⑨ $((SECONDS - T_START))s"

# ===== ⑩: 묶음 256개(부모 199) · 최신 통과 → pick·unpaid·cover 몫 7초 안 · git 호출 수 비교 =====
reset_press
S10="$(wset s10r1 "clients/web/r10.ts=x")"
PB=(); for i in $(seq 1 198); do PB+=("$(git -C "$REPO" commit-tree "$(mt)" -p "$(sha "$REPO" origin/main)" -m "p10-$i")"); done   # 부모 198 + 세트 = 199
for i in $(seq 1 198); do jbl "${PB[$((i - 1))]}" "20261010-0$(printf %05d "$i")"; done
for i in $(seq 1 58); do vbl "$S10" "20261110-$(printf %06d "$i")"; done                                                       # 198 + 58 = 256
git -C "$REPO" push -q origin 'refs/press/*:refs/press/*'
git -C "$REPO" fetch -q --prune origin '+refs/press/*:refs/press/*'
NREF="$(git -C "$REPO" for-each-ref refs/press/ | wc -l | tr -d ' ')"; [ "$NREF" = 256 ]; ck "⑩ 묶음 ref 256개 준비(부모 199)" $?
python3 - "$REPO" "$S10" "$(sha "$REPO" origin/main)" "$BIN" "$BASEBIN" > "$T/scale.txt" 2>&1 <<'PY'
import importlib.util, sys, time
repo, target, main, fixed, base = sys.argv[1:6]
def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
def measure(m, tag, three):
    n, rl = [0], [0]
    orig = m.run
    def run(r, *a, inp=None):
        n[0] += 1
        if a[:2] == ("rev-list", "--parents"):
            rl[0] += 1
        return orig(r, *a, inp=inp)
    m.run = run
    specs = m.specs_of(repo, target, main)
    n[0], rl[0] = 0, 0
    t = time.time()
    if three:   # 고친 판 — pick 이 빚까지 읽고 first 통과 뒤 멈춘다
        good, why, debts = m.pick(repo, target, specs, main)
    else:       # 기준판 — pick 전부 판정 → unpaid → cover
        good, why = m.pick(repo, target, specs)
        debts = m.unpaid(repo, main)
    b = m.cover(repo, good, debts) if good else None
    dt = time.time() - t
    print("%s pick+unpaid+cover %.2fs git=%d rev-list=%d good=%d chosen=%s" % (tag, dt, n[0], rl[0], len(good), (b or {}).get("run", "없음")))
measure(load(base + "/press_evidence_verify.py", "b"), "기준판", False)
measure(load(fixed + "/press_evidence_verify.py", "f"), "고친판", True)
PY
sed -n '1,4p' "$T/scale.txt" | sed 's/^/    /'
FS="$(awk '/^고친판/ {print $3}' "$T/scale.txt" | tr -d 's')"; FG="$(awk '/^고친판/ {print $4}' "$T/scale.txt" | sed 's/git=//')"
BS="$(awk '/^기준판/ {print $3}' "$T/scale.txt" | tr -d 's')"; BG="$(awk '/^기준판/ {print $4}' "$T/scale.txt" | sed 's/git=//')"
FB="$(awk '/^기준판/ {print $5}' "$T/scale.txt" | sed 's/rev-list=//')"; FR="$(awk '/^고친판/ {print $5}' "$T/scale.txt" | sed 's/rev-list=//')"
awk -v s="$FS" 'BEGIN {exit !(s <= 7)}' && [ -n "$FS" ]; ck "⑩ 고친 판 pick·unpaid·cover = ${FS}s(fetch 뺌 · 7초 안)" $?
[ "$FR" = 1 ] && [ "$FB" = 58 ]; ck "⑩ bundle 판정 = 고친 판 ${FR}회 / 기준판 ${FB}회(통과 묶음 전부)" $?
[ -n "$BG" ] && [ "$BG" -ge 500 ] && [ "$BG" -ge $((FG * 20)) ]; ck "⑩ 기준판 Red: git 호출 ${BG}회 = 고친 판 ${FG}회의 20배 이상" $?
awk -v s="$BS" 'BEGIN {exit !(s > 0)}' && [ -n "$BS" ]; ck "⑩ 같은 기계 기준판 초 = ${BS}s(고친 판 ${FS}s) · 기록" $?
ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
t0="$(ms)"; landat "$BASEBIN" "$S10"; bms=$(( $(ms) - t0 )); brc2="$rc"; bout2="$out"
t0="$(ms)"; landat "$BIN" "$S10"; fms=$(( $(ms) - t0 ))
[ "$rc" = "$brc2" ] && [ "$out" = "$bout2" ] && [ "$rc" = 0 ]; ck "⑩ press 단계 전체(land)도 같은 답 · 기준판 ${bms}ms / 고친 판 ${fms}ms(주석 = fetch 포함)" $?
echo "단계 초: ⑩ $((SECONDS - T_START))s"

echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
