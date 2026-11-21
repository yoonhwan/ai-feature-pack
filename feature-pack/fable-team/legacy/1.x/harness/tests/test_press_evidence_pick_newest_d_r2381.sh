#!/usr/bin/env bash
# test_press_evidence_pick_newest_d_r2381.sh — r2381 ⑪~⑮: 판정 불가·본 묶음만(K4) 과 다른 길 그대로(K5)
#   ⑪ 가짜 fetch 7초 넘김 2회 → 판정 불가 1줄 = 지금 판과 같음(외부 호출 7초 룰 그대로)
#   ⑫ 최신 통과 묶음보다 옛 쪽의 깨진 묶음(rev-parse 실패) → OK 줄 = 최신 통과(기준판 = 판정 불가 거절 · 의도한 차이 1줄 · 기준판 Red)
#   ⑬ 최신 통과 묶음보다 새 쪽의 같은 깨진 묶음 → 판정 불가 거절 = 지금 판과 같은 꼴
#   ⑭ 음성 경로 변경 0 PR → «대상 밖» 줄 그대로 · fetch 0  ⑮ 정확 역변경 PR → 면제·빚 줄 그대로
#   변이 M8(깨진 묶음을 조용히 건너뜀) → ⑬ 판정 불가가 안 나옴 · 변이마다 원본 1회 더
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_evidence_pick_newest_r2381_lib.sh"

# ===== ⑪: 가짜 fetch 7초 넘김 2회 → 판정 불가 1줄(재시도 1 · 7 s) = 지금 판과 같음 =====
reset_press
S11="$(wset s11r1 "clients/web/r11.ts=x")"; vb "$S11" 20261111-010000
export STUB_FETCH_SLEEP=8
both "$S11"
unset STUB_FETCH_SLEEP
[ "$rc" = 1 ] && [[ "$out" == *"판정 불가: git fetch 실패(7 s + 재시도 1)"* ]] && [ "$brc" = 1 ]; ck "⑪ fetch 7초 초과 2회 → 판정 불가 1줄" $?
samebytes; ck "⑪ 판정 불가 줄 = 기준판(바이트 같음)" $?
echo "단계 초: ⑪ $((SECONDS - T_START))s"

# ===== ⑫: 최신 통과 묶음보다 옛 쪽에 깨진 묶음 → OK 줄 = 최신 통과(기준판 = 판정 불가) =====
reset_press
S12="$(wset s12r1 "clients/web/r12.ts=x")"
vb "$S12" 20261112-020000; bk "$(printf 'b%.0s' $(seq 1 40))" 20261112-010000
both "$S12"
[ "$rc" = 0 ] && [[ "$out" == *"run 20261112-020000 ·"* ]]; ck "⑫ 옛 쪽 깨진 묶음은 안 본다 → OK 줄 = 최신 통과 묶음" $?
[ "$brc" = 1 ] && [[ "$bout" == *"판정 불가: git rev-parse"* ]]; ck "⑫ 기준판 Red: 깨진 묶음 하나에 판정 불가 거절(의도한 차이)" $?
[[ "$out" != "$bout" ]]; ck "⑫ 의도한 차이 1줄: 고친 판 OK ≠ 기준판 판정 불가" $?
echo "단계 초: ⑫ $((SECONDS - T_START))s"

# ===== ⑬: 최신 통과 묶음보다 새 쪽에 같은 깨진 묶음 → 판정 불가 거절 = 지금 판과 같은 꼴 =====
reset_press
S13="$(wset s13r1 "clients/web/r13.ts=x")"
vb "$S13" 20261113-020000; bk "$(printf 'c%.0s' $(seq 1 40))" 20261113-030000
both "$S13"
[ "$rc" = 1 ] && [[ "$out" == *"판정 불가: git rev-parse"* ]]; ck "⑬ 새 쪽 깨진 묶음(본 묶음) → 판정 불가 거절" $?
samebytes; ck "⑬ 거절 = 기준판(바이트 같음)" $?
mut M8 verify '        e = git(repo, "rev-parse", c + "^").strip()   # 깨진 묶음 = 지금처럼 판정 불가(본 묶음일 때만)' '        try:
            e = git(repo, "rev-parse", c + "^").strip()
        except Reject:
            continue'
mutbad "ⓜM8 깨진 묶음을 조용히 건너뜀 → ⑬ 판정 불가가 안 나옴" "$MBIN" "$S13" "판정 불가: git rev-parse"
landat "$BIN" "$S13"; [[ "$out" == *"판정 불가: git rev-parse"* ]]; ck "ⓜM8 원본 재확인 → ⑬ 통과" $?
echo "단계 초: ⑬ $((SECONDS - T_START))s"

# ===== ⑭: 음성 경로 변경 0 PR → «대상 밖» 줄 그대로 · fetch 0 =====
reset_press
S14="$(wset s14r1 "docs/r14.md=문서만")"
both "$S14"
[ "$rc" = 0 ] && [[ "$out" == "press 증거 대상 밖(음성 경로 변경 0)"$'\n'"press=out" ]]; ck "⑭ 음성 경로 변경 0 → «대상 밖» 줄" $?
nf="$(cnt "$T/fixed.log" ' fetch ')"; [ "$nf" = 0 ]; ck "⑭ fetch ${nf}회(대상 밖이면 원격 안 본다)" $?
samebytes; ck "⑭ 출력 = 기준판" $?
echo "단계 초: ⑭ $((SECONDS - T_START))s"

# ===== ⑮: 정확 역변경 PR → 면제·빚 줄 그대로 =====
reset_press
adv "clients/web/v15.ts=1"; L15="$(sha "$REPO" origin/main)"
brn b15r; git -C "$REPO" revert --no-edit "$L15" >/dev/null; RV15="$(sha "$REPO" HEAD)"
both "$RV15"
[ "$rc" = 0 ] && [[ "$out" == *"press 증거 면제 — 정확 역변경(되돌린 ${L15:0:10}) · 빚 refs/press-debt/${RV15:0:10}"* ]] && [[ "$out" == *"press=revert:${L15:0:10}" ]]; ck "⑮ 정확 역변경 → 면제 줄 + 빚 ref 이름" $?
[[ "$out" == *"· 담당 byz-harness-master-claude#9 · 복구 뒤 press 1회"* ]]; ck "⑮ 담당 = PR 팀 명부 _master(빚 담당 그대로)" $?
samebytes; ck "⑮ 출력 = 기준판(바이트 같음)" $?
echo "단계 초: ⑮ $((SECONDS - T_START))s"

echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
