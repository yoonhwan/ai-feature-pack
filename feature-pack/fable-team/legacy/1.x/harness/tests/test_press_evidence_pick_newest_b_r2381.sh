#!/usr/bin/env bash
# test_press_evidence_pick_newest_b_r2381.sh — r2381 ④~⑧: 끝까지 도는 갈래(통과 0)의 거절 사유·unpaid 자리(r2381 동결 반례 뒤 절반)
#   ④ 통과 묶음 0(전부 음성 경로 트리 다름) → «묶음 없음(… 검사 40개)» = 지금 판과 바이트 같음 · unpaid 0회
#   ⑤ 통과 0 · 이름순 첫 거절 = 목록 판정 불가 → 거절 사유 = 지금 판과 같음(이름순 첫 사유)
#   ⑥ 빚 1 · 통과 3 · 아무도 안 덮음 → debt_line 거절 = 지금 판과 바이트 같음 · unpaid 1회
#   ⑦ 빚 1 · 통과 0 · 빚 조회 git 고장(가짜 git rc 128) → «묶음 없음» · unpaid 0회
#   ⑧ run_id 꼴 아닌 묶음 섞임 → 그 묶음은 맨 뒤(r1263 열쇠 그대로) · 결과 = 지금 판과 같음
#   변이 M4(못 찾은 갈래 사유를 «마지막» 것으로)·M5(덮음 0 을 «묶음 없음» 사유로)·M6(unpaid 를 pick 앞으로) → 계약 깨짐 재현 · 변이마다 원본 1회 더
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_pick_newest_r2381_lib.sh"

# ===== ④: 통과 묶음 0(부모 40 전부 음성 경로 트리 다름) → «묶음 없음(… 검사 40개)» · unpaid 0회 =====
reset_press
S4="$(wset s4r1 "clients/web/r4.ts=x")"
for i in $(seq 1 40); do jb "$(git -C "$REPO" commit-tree "$(mt)" -p "$(sha "$REPO" origin/main)" -m "p4-$i")" "20261004-0$(printf %05d "$i")"; done
both "$S4"
[ "$rc" = 1 ] && [[ "$out" == "press 증거 없음/틀림: 묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0 · 검사 40개) — 판정 2946" ]]; ck "④ 통과 0 → «묶음 없음(… 검사 40개)»" $?
nm="$(cnt "$T/fixed.log" 'merge-base --is-ancestor')"; [ "$nm" = 0 ]; ck "④ unpaid 0회(빚 조회 merge-base ${nm}회)" $?
samebytes; ck "④ 거절 사유 = 기준판(바이트 같음)" $?
echo "단계 초: ④ $((SECONDS - T_START))s"

# ===== ⑤: 통과 0 · 이름순 첫 거절 = 목록 판정 불가 → 사유 = 지금 판과 같음(이름순 첫 사유) =====
reset_press
S5="$(wset s5r5 "clients/web/r5.ts=x")"; bt "$S5" 20261005-010000                        # 통과 0 · 칸 틀림 사유
BROKEN=$'# 음성 경로 목록\n## 목록\n- `worker/**`\n깨진줄'                                     # 목록 꼴 틀림(판정 불가)
XB=""; for i in 1 2 3 4 5 6; do c="$(wset "s5x$i" "docs/rules/press_voice_paths.md=$BROKEN")"; if [ -z "$XB" ] || [[ "$c" < "$XB" ]]; then XB="$c"; fi; done
jb "$XB" 20261005-020000                                                                   # 이름순 맨 앞 = 목록 판정 불가 쪽
both "$S5"
[ "$rc" = 1 ] && [[ "$out" == *"판정 불가: 음성 경로 목록 꼴 틀림"* ]]; ck "⑤ 거절 사유 = 이름순 첫 거절(목록 판정 불가)" $?
samebytes; ck "⑤ 사유 = 기준판(이름순 첫 사유 · 바이트 같음)" $?
mut M4 verify '(bad[min(bad)] if bad else "")' '(list(bad.values())[-1] if bad else "")'
mutbad "ⓜM4 사유를 «마지막» 것으로 → ⑤ 사유 달라짐" "$MBIN" "$S5" "판정 불가: 음성 경로 목록 꼴 틀림"
landat "$BIN" "$S5"; [[ "$out" == *"판정 불가: 음성 경로 목록 꼴 틀림"* ]]; ck "ⓜM4 원본 재확인 → ⑤ 통과" $?
echo "단계 초: ⑤ $((SECONDS - T_START))s"

# ===== ⑥: 빚 1 · 통과 묶음 3 · 아무도 안 덮음 → debt_line 거절 = 지금 판과 바이트 같음 · unpaid 1회 =====
reset_press
adv "worker/r6d.py=debtsrc"; D6="$(sha "$REPO" origin/main)"; debt "$D6" 61
S6="$(wset s6r1 "clients/web/r6.ts=x")"; DP6="$(sha "$REPO" "$D6^")"
A6="$(asrev a6 "$DP6" "$S6")"; B6="$(asrev b6 "$DP6" "$S6")"; C6="$(asrev c6 "$DP6" "$S6")"
vb "$A6" 20261006-030000; vb "$B6" 20261006-020000; vb "$C6" 20261006-010000
both "$S6"
[ "$rc" = 1 ] && [[ "$out" == "press 빚 PR #61(착지 ${D6:0:10}) — 담당 o · 복구 뒤 press 1회 — 판정 2946" ]]; ck "⑥ 덮는 묶음 0 → debt_line 거절(빚 착지 10자)" $?
nd="$(cnt "$T/fixed.log" 'for-each-ref .*refs/press-debt')"; [ "$nd" = 2 ]; ck "⑥ unpaid 1회(빚·상환 ref 읽기 ${nd}회 = 2)" $?
samebytes; ck "⑥ 거절 = 기준판(바이트 같음)" $?
mut M5 land 'raise Reject(debt_line(a.repo, debts[0]) + " — 판정 2946")' 'raise Reject("press 증거 없음/틀림: 묶음 없음 — 판정 2946")'
mutbad "ⓜM5 덮음 0 을 «묶음 없음» 사유로 → ⑥ 사유 달라짐" "$MBIN" "$S6" "press 빚 PR #61"
landat "$BIN" "$S6"; [[ "$out" == *"press 빚 PR #61"* ]]; ck "ⓜM5 원본 재확인 → ⑥ 통과" $?
echo "단계 초: ⑥ $((SECONDS - T_START))s"

# ===== ⑦: 빚 1 · 통과 0 · 빚 조회 git 고장(rc 128) → «묶음 없음» 사유 · unpaid 0회 =====
reset_press
S7="$(wset s7r1 "clients/web/r7.ts=x")"; jb "$(git -C "$REPO" commit-tree "$(mt)" -p "$(sha "$REPO" origin/main)" -m p7)" 20261007-010000
debt "$(sha "$REPO" origin/main)" 61
export STUB_BREAK_DEBT=1
both "$S7"
unset STUB_BREAK_DEBT
[ "$rc" = 1 ] && [[ "$out" == *"묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0 · 검사 1개)"* ]] && [[ "$out" != *"판정 불가"* ]]; ck "⑦ 통과 0 이면 빚 조회를 안 부른다 → «묶음 없음»(고장난 git 안 탄다)" $?
nq="$(cnt "$T/fixed.log" 'for-each-ref .*refs/press-debt')"; [ "$nq" = 0 ]; ck "⑦ 빚 조회 호출 ${nq}회(unpaid 0회)" $?
samebytes; ck "⑦ 사유 = 기준판(바이트 같음)" $?
mut M6 verify '    good, bad, debts, n = [], {}, None, 0' '    good, bad, debts, n = [], {}, unpaid(repo, upto), 0'
export STUB_BREAK_DEBT=1
mutbad "ⓜM6 unpaid 를 pick 앞으로 → 통과 0 에도 불러 ⑦ 판정 불가" "$MBIN" "$S7" "묶음 없음(음성 경로 트리가 같은 세트의 refs/press/* 0"
landat "$BIN" "$S7"; [[ "$out" == *"묶음 없음"* ]]; ck "ⓜM6 원본 재확인 → ⑦ 통과" $?
unset STUB_BREAK_DEBT
echo "단계 초: ⑦ $((SECONDS - T_START))s"

# ===== ⑧: run_id 꼴 아닌 묶음 섞임 → 그 묶음은 맨 뒤(r1263 열쇠 그대로) · 결과 = 지금 판과 같음 =====
reset_press
S8="$(wset s8r1 "clients/web/r8.ts=x")"
vb "$S8" nostamp; vb "$S8" "z-20261008-010000"; vb "$S8" 20261108-000000
both "$S8"
[ "$rc" = 0 ] && [[ "$out" == *"run 20261108-000000 ·"* ]]; ck "⑧ run_id 꼴 아닌 묶음은 맨 뒤 · 늦은 run = 20261108-000000" $?
samebytes; ck "⑧ 결과 = 기준판(바이트 같음)" $?
echo "단계 초: ⑧ $((SECONDS - T_START))s"

echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
