#!/usr/bin/env bash
# test_press_queue_r2387.sh — r2387 ①~⑩: `ft-press-evidence.sh queue` 가 음성 경로 PR 을 승인 순으로 세우고 «지금 press 해도 안 깨질 PR 1개»(NEXT)를 고른다 (K1 대상 고르기 · K2 차례)
#   ① 줄 3개·gh 1회(기준판 Red) ② 승인 전은 NEXT 후보 아님 ②b 승인 표식 둘째 길(«판정: APPROVE» 코멘트) ③ 음성 경로 0 은 줄에 안 섬 ④ PR 쪽 목록 글롭도 합집합
#   ⑤ 묶음 0 = 셋 다 NONE · NEXT 첫 PR ⑥ VALID 하나면 NEXT = 대기 ⑦ 앞 착지로 STALE(다르게 만든 착지 sha) ⑧ 음성 경로 아닌 착지는 VALID 그대로 ⑨ 승인 시각 같으면 번호 오름차순
#   ⑩ VALID 가 뒤에 있어도 NEXT 는 대기(DA#53 H1) — ⑮⑯⑰⑭ = test_press_queue_edge_r2387.sh · ⑪⑫⑬ = test_press_queue_tail_r2387.sh · M1~M8 = test_press_queue_mut*_r2387.sh
#   틀 = _press_queue_r2387_lib.sh(r1230 픽스처 + gh pr list 대역 + 세트/묶음 도우미) · 실 gh·실 원격 0 · queue 는 읽기 전용
# 사용: timeout 70 bash <이 파일> → 마지막 줄 «== OK ==» · rc 0/1
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_press_queue_r2387_lib.sh"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:700}"; fail=$((fail+1)); fi; }
S0=$SECONDS

# ===== 사전: 문법 · bin·kit 같은 글자 · 기준판에 queue 갈래 0 =====
python3 -m py_compile "$BIN/press_evidence_verify.py" "$QBB/press_evidence_verify.py"; ck "사전 python3 -m py_compile(고친 판·기준판)" $?
for f in ft-press-evidence.sh press_evidence_verify.py ft-merge-land.sh; do cmp -s "$BIN/$f" "$BIN/../kit/fable-team/bin/$f" || { echo "  짝 다름 $f"; false; }; done; ck "사전 bin·kit 사본 같은 글자(3파일)" $?
grep -q '^  queue)' "$QBB/ft-press-evidence.sh" && ck "사전 기준판에 queue 갈래가 있다(고치기 전 판 아님)" 1 || ck "사전 기준판(origin/main)에 queue 갈래 0" 0

# ===== ①: 열린 PR 4개(음성 경로 3 · 승인 3 · 음성 경로 0 1) → PR 줄 3개 · gh 1회 =====
qreset; A1="$(tmn 30)"
qm 31 pr31 "$A1" worker/p31.py=p31
qm 32 pr32 "$A1" clients/web/p32.ts=p32
qm 33 pr33 "$A1" pyproject.toml=#p33
qm 34 pr34 "" docs/notes.md=n34
qrun
[ "$rc" = 0 ] && [ "$(grep -c '^PR #' <<<"$out")" = 3 ] && [ "$(qgl)" = 1 ] && [ "$(grep -c '^NEXT ' <<<"$out")" = 1 ] \
  && [ -z "$(grep '^PR #34 ' <<<"$out")" ] && [ "$(grep -c ' NONE' <<<"$out")" = 3 ]; ck "① PR 줄 3개(#34 안 섬) · gh 1회 · 셋 다 NONE · 끝 NEXT 1줄" $?
qbase
[ "$rc" = 2 ] && [ "$(grep -c '^PR #' <<<"$out")" = 0 ] && [ "$(qgl)" = 0 ]; ck "① 기준판 Red — queue 갈래 0(usage rc 2 · 줄 0 · gh 0)" $?
echo "단계 초: 사전·① $((SECONDS - S0))s"

# ===== ②: 승인 표식 없는 음성 경로 PR → «승인 전» 줄 · NEXT 후보 아님 =====
qreset
qm 41 pr41 "" worker/p41.py=p41
qm 42 pr42 "$(tmn 20)" worker/p42.py=p42
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #41 승인 전"* ]] && [ "$(qnext)" = 42 ] && [ "$(qline 42)" -lt "$(qline 41)" ]; ck "② «승인 전» 줄(승인 있는 줄 아래) · NEXT 42(41 은 후보 아님)" $?
qreset
qm 43 pr43 "C:$(tmn 15)" worker/p43.py=p43
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #43 NONE"* ]]; ck "②b 승인 표식 = «판정: APPROVE» 코멘트도 센다" $?

# ===== ③·④: 음성 경로 0 은 줄에 안 섬 · PR 쪽 목록 글롭도 합집합 =====
qreset
qm 51 pr51 "$(tmn 10)" docs/x51.md=x51
qrun
[ "$rc" = 0 ] && [ "$(grep -c '^PR #' <<<"$out")" = 0 ] && [ "$(qnext)" = 없음 ]; ck "③ 음성 경로 0 = 줄 0 · NEXT 없음" $?
qreset
qlst 61 pr61 "$(tmn 10)" tools/cli/** tools/cli/run.sh=x61
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #61 NONE"* ]]; ck "④ PR 쪽 목록에만 있는 글롭(tools/cli/**)도 대상 — 합집합" $?
echo "단계 초: ②~④ $((SECONDS - S0))s"

# ===== ⑤: 음성 경로 PR 3개(승인 순 A·B·C · 겹침 없음) · 묶음 0 → 셋 다 NONE · NEXT A =====
qreset
qm 71 pr71 "$(tmn 30)" worker/p71.py=p71
qm 72 pr72 "$(tmn 20)" worker/p72.py=p72
qm 73 pr73 "$(tmn 10)" worker/p73.py=p73
qrun
[ "$rc" = 0 ] && [ "$(grep -c '^PR #7[123] NONE' <<<"$out")" = 3 ] && [ "$(qnext)" = 71 ] && [ "$(qline 71)" = 1 ]; ck "⑤ 셋 다 NONE · NEXT 71(승인 순 첫) · 줄 순서 71·72·73" $?

# ===== ⑥: ⑤ 에서 A 묶음 VALID → A VALID · NEXT 대기(VALID PR A 착지 뒤 · <분>분째) =====
vbs "$(setof "$(sha "$REPO" pr71)")" 20261117-101500
qrun
M6="$(sed -n 's/^NEXT 대기(VALID PR 71 착지 뒤 · \([0-9]*\)분째)$/\1/p' <<<"$out")"
[ "$rc" = 0 ] && [[ "$out" == *"PR #71 VALID"* ]] && [[ "$out" == *"PR #72 NONE"* ]] && [ -n "$M6" ] && [ "$M6" -ge 29 ] && [ "$M6" -le 31 ]
ck "⑥ A VALID · NEXT 대기(VALID PR 71 · ${M6:-?}분째 = 승인 30분 전)" $?

# ===== ⑦: 앞 음성 경로 착지 뒤 B 묶음(옛 main 세트) → B STALE · 다르게 만든 착지 = 그 착지 sha · NEXT B =====
qreset
qm 74 pr74 "$(tmn 20)" worker/p74.py=p74
vbs "$(setof "$(sha "$REPO" pr74)")" 20261117-103000    # B 묶음 = 지금(옛) main 세트
adv worker/aa74.py=landed74                              # A 착지 = main 음성 경로가 바뀐다
qrun
LAND7="$(sha "$REPO" origin/main)"
[ "$rc" = 0 ] && [[ "$out" == *"PR #74 STALE · 다르게 만든 착지 ${LAND7:0:10}"* ]] && [ "$(qnext)" = 74 ]; ck "⑦ 앞 음성 경로 착지(${LAND7:0:10}) 뒤 B = STALE · 그 착지 sha 1개 · NEXT 74" $?

# ===== ⑧: 음성 경로가 아닌 PR 착지 뒤 B 묶음 → B VALID 그대로 =====
qreset
qm 81 pr81 "$(tmn 20)" worker/p81.py=p81
vbs "$(setof "$(sha "$REPO" pr81)")" 20261117-104000
adv docs/nonvoice.md=nnn                                 # 음성 경로 아닌 착지
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #81 VALID"* ]]; ck "⑧ 음성 경로 아닌 착지 뒤에도 B = VALID 그대로" $?

# ===== ⑨: 승인 시각 같음 → PR 번호 오름차순 =====
qreset; T9="$(tmn 12)"
qm 91 pr91 "$T9" worker/p91.py=p91
qm 90 pr90 "$T9" worker/p90.py=p90
qrun
[ "$rc" = 0 ] && [ "$(qline 90)" = 1 ] && [ "$(qline 91)" = 2 ]; ck "⑨ 승인 시각 같음 → PR #90 이 #91 보다 위" $?

# ===== ⑩: 승인 순 A(NONE) · B(VALID) → NEXT 대기(VALID PR B …) · A 는 NEXT 아님 (DA#53 H1) =====
qreset
qm 101 pr101 "$(tmn 30)" worker/p101.py=p101
qm 102 pr102 "$(tmn 10)" worker/p102.py=p102
vbs "$(setof "$(sha "$REPO" pr102)")" 20261117-105000
qrun
[ "$rc" = 0 ] && [[ "$out" == *"PR #101 NONE"* ]] && [[ "$out" == *"PR #102 VALID"* ]] && [[ "$(qnext)" == "대기(VALID PR 102 착지 뒤 · "* ]] && [ "$(qline 101)" = 1 ]
ck "⑩ 줄 어디든 VALID 면 NEXT = 대기(102) — 앞의 NONE(101) 을 고르지 않는다" $?

# ===== 격리 =====
[ "$(git -C "$ORIGIN" rev-parse --is-bare-repository)" = true ] && [[ "$ORIGIN" == "$T/"* ]]; ck "격리: 원격 = 임시 bare 1개(실 원격·실 gh 0)" $?
echo "단계 초: ⑤~⑦ $((SECONDS - S0))s · 전체 $((SECONDS - S0))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
