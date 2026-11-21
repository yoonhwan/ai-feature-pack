#!/usr/bin/env bash
# test_press_evidence_pick_newest_r2381.sh — r2381 ①~③: press 묶음 고르기가 refs/press/* 를 최신 run 순으로 보다가 «첫 통과 + 빚 덮음» 묶음에서 멈춘다(끝까지 안 본다) · 고르는 묶음과 출력 줄은 지금 판과 바이트 같음
#   동결 반례 ①(묶음 40·부모 30·최신 통과·빚 0 → bundle 판정 1회·목록 1회 · 기준판 Red) ②(최신 묶음 칸 틀림 → 둘째 · 판정 2회 · 이름순 첫 통과에서 멈추면 답이 달라진다) ③(빚 1 · 셋째만 덮음 → 셋째 + 빚 상환 1)
#   변이 M1(멈춤 지움)·M2(정렬 지움)·M3(빚 덮음 확인 없이 멈춤) → 계약이 깨짐을 재현 · 변이마다 원본으로 같은 사례 1회 더
#   틀 = _press_evidence_pick_newest_r2381_lib.sh(r1230 픽스처 · 기준판 = e33c6e4a 파일 · 가짜 git 호출 기록) · 실 원격·실 gh 0 · dry(빚 ref push 0)
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_pick_newest_r2381_lib.sh"

# ===== 사전: 문법 · 기준판 =====
python3 -m py_compile "$BIN/press_evidence_verify.py" "$BIN/press_evidence_land.py" "$BASEBIN/press_evidence_verify.py"; ck "사전 python3 -m py_compile(고친 판·기준판)" $?
[ -s "$BASEBIN/press_evidence_verify.py" ] && ! cmp -s "$BASEBIN/press_evidence_verify.py" "$BIN/press_evidence_verify.py"; ck "사전 기준판 파일 ≠ 고친 판 파일" $?

# ===== ①: 묶음 40(부모 30) · 최신 run 묶음 통과 · 빚 0 → OK 줄 = 최신 · bundle 판정 1회 · 목록 읽기 1회 =====
reset_press
S1="$(wset s1r1 "clients/web/r1.ts=x")"
for i in $(seq 1 29); do jb "$(git -C "$REPO" commit-tree "$(mt)" -p "$(sha "$REPO" origin/main)" -m "p1-$i")" "20261001-0$(printf %05d "$i")"; done   # 부모 29 × 묶음 1
for i in $(seq 1 11); do vb "$S1" "20261101-1200$(printf %02d "$i")"; done                                                                                  # 세트 × 묶음 11 = 40
both "$S1"
W1="press 증거 OK 세트 ${S1:0:10} run 20261101-120011 · ref refs/press/$S1-20261101-120011 · turbopack build 0 runtime 1 config 0"
[ "$rc" = 0 ] && [[ "$out" == "$W1"* ]] && [ "$brc" = 0 ] && [[ "$bout" == "$W1"* ]]; ck "① OK 줄 = 최신 run 묶음 · 기준판과 바이트 같음" $?
nf_rv="$(cnt "$T/fixed.log" 'rev-list --parents')"; nf_list="$(cnt "$T/fixed.log" ':docs/rules/press_voice_paths.md')"
[ "$nf_rv" = 1 ] && [ "$nf_list" -le 4 ]; ck "① 고친 판: bundle 판정 ${nf_rv}회 · 목록 ${nf_list}회(specs_of 3 + pick 1 이하)" $?
nb_rv="$(cnt "$T/base.log" 'rev-list --parents')"; nb_list="$(cnt "$T/base.log" ':docs/rules/press_voice_paths.md')"
[ "$nb_rv" -ge 11 ] && [ "$nb_list" -ge 41 ]; ck "① 기준판 Red: bundle 판정 ${nb_rv}회(11 이상) · 목록 ${nb_list}회(41 이상)" $?
echo "단계 초: ① $((SECONDS - T_START))s"

# ===== ②: 최신 묶음이 틀림(표 빈 칸) · 둘째가 통과 → OK = 둘째 · 판정 2회 · 이름순 첫 통과(이른 run)에서 멈추면 답이 달라진다 =====
reset_press
S2="$(wset s2r1 "clients/web/r2.ts=x")"; M2A="$(asrev s2a "$(sha "$REPO" origin/main)" "$S2")"; M2B="$(asrev s2b "$(sha "$REPO" origin/main)" "$S2")"
LO="$(printf '%s\n%s\n' "$M2A" "$M2B" | sort | head -1)"; HI="$(printf '%s\n%s\n' "$M2A" "$M2B" | sort | tail -1)"   # 이름순 = LO 먼저 · run 은 HI 쪽이 늦다
bt "$HI" 20261102-030000; vb "$HI" 20261102-020000; vb "$LO" 20261102-010000
both "$S2"
[ "$rc" = 0 ] && [[ "$out" == *"세트 ${HI:0:10} run 20261102-020000 ·"* ]]; ck "② 최신 묶음 칸 틀림 → 둘째(늦은 run) 통과" $?
nf_rv="$(cnt "$T/fixed.log" 'rev-list --parents')"; [ "$nf_rv" = 2 ]; ck "② 고친 판 판정 ${nf_rv}회(틀린 최신 + 통과 둘째)" $?
samebytes; ck "② 출력 = 기준판(이름순 첫 통과가 아니라 늦은 run 이 답)" $?
mut M1 verify '        if all(anc(repo, d, b["set"]) for d in debts):
            break' '        if all(anc(repo, d, b["set"]) for d in debts):
            continue'
landat "$MBIN" "$S2"; n="$(cnt "$GITLOG" 'rev-list --parents')"; [ "$n" != 2 ]; ck "ⓜM1 멈춤 지움 → ② 판정 ${n}회(끝까지 봄) = 계약 깨짐 재현" $?
landat "$BIN" "$S2"; [ "$rc" = 0 ] && [[ "$out" == *"run 20261102-020000 ·"* ]]; ck "ⓜM1 원본 재확인 → ② 통과(같은 사례 1회 더)" $?
mut M2 verify 'for ref, c in newest_refs(refs(repo, "refs/press").items()):' 'for ref, c in sorted(refs(repo, "refs/press").items()):'
mutbad "ⓜM2 정렬 지움 → 이름순 첫 통과(이른 run)에서 멈춤 = ② 답 달라짐" "$MBIN" "$S2" "run 20261102-020000 ·"
landat "$BIN" "$S2"; [ "$rc" = 0 ] && [[ "$out" == *"run 20261102-020000 ·"* ]]; ck "ⓜM2 원본 재확인 → ② 통과" $?
echo "단계 초: ② $((SECONDS - T_START))s"

# ===== ③: 빚 1(착지 D) · 최신 통과 묶음 세트가 D 조상을 안 가짐 · 셋째가 가짐 → 셋째 묶음 OK + 빚 상환 1 =====
reset_press
adv "worker/r3d.py=debtsrc"; D="$(sha "$REPO" origin/main)"; debt "$D" 61
S3="$(wset s3r1 "clients/web/r3.ts=x")"
DP="$(sha "$REPO" "$D^")"   # 빚 착지 직전 main = A3·B3 의 부모(빚을 조상으로 안 가짐) · C3 만 D 를 조상으로
A3="$(asrev a3 "$DP" "$S3")"; B3="$(asrev b3 "$DP" "$S3")"; C3="$(asrev c3 "$D" "$S3")"
vb "$A3" 20261103-030000; vb "$B3" 20261103-020000; vb "$C3" 20261103-010000
both "$S3"
[ "$rc" = 0 ] && [[ "$out" == *"세트 ${C3:0:10} run 20261103-010000"* ]] && [[ "$out" == *"빚 상환 1 · dry · push 0"* ]]; ck "③ 빚을 덮는 셋째 묶음으로 OK + 빚 상환 1(최신·둘째는 건너뜀)" $?
samebytes; ck "③ 출력 = 기준판(빚 규칙이 순서보다 먼저 · 바이트 같음)" $?
mut M3 verify '        if all(anc(repo, d, b["set"]) for d in debts):' '        if True:'
mutbad "ⓜM3 빚 덮음 확인 없이 멈춤 → ③ 답(셋째 묶음) 안 나옴" "$MBIN" "$S3" "run 20261103-010000"
landat "$BIN" "$S3"; [ "$rc" = 0 ] && [[ "$out" == *"run 20261103-010000"* ]]; ck "ⓜM3 원본 재확인 → ③ 통과" $?
echo "단계 초: ③ $((SECONDS - T_START))s"

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
