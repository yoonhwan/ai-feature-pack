#!/usr/bin/env bash
# test_nano_close_step_timing_r938_a.sh — r938 단계 시각 줄 시험의 «시각 줄(ⓐ) · 실측 재현(ⓔ)» 조각(r1318 나눔 · 원본 = test_nano_close_step_timing_r938.sh 1개).
#   왜 나눴나: r1316 뒤 이 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22) — 단언·변이 집합은 나누기 전과 같다(빼지 않고 옮기기만).
#   공통 준비(임시 리포·가짜 tmux·대역·도우미) = lib/r938_step_timing_fixture.sh · 끝에 finish 로 ALL PASS/FAILED.
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r938_step_timing_fixture.sh"

echo "== ⓐ 정상 대역 → CLOSED · STEP 줄은 stderr 에만 · stdout 은 기준판과 cmp0"
setup; runout="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$runout" "CLOSED $SEAT" "$(card ⓐ 'rc=0 · CLOSED(새 판)')" || bad "ⓐ rc=$rc ← ${runout:0:900}"
evi a-new "$runout"
ST="$(steps_of "$(cat "$T/err")")"
for nm in ⑥증거검사 ⑤cherry sheet ledger slots; do
  case "$ST" in *"$nm"*) ok "$(card ⓐ "  └ STEP $nm 줄이 stderr 에 있음")";; *) bad "$(card ⓐ "  └ STEP $nm 줄 없음 ← $ST")";; esac
done
hasnt "$(cat "$T/out")" "STEP" "$(card ⓐ '  └ stdout 에 STEP 0줄')"
setup; FB=feat/x; runbase="$(FEAT=feat/x closebase)"; rcb=$?   # 기준판 = r938 시각 줄만 뺀 사본
setup; FEAT=feat/x out="$(close)"; rc2=$?
[ "$rcb" -eq 0 ] && [ "$rc2" -eq 0 ] || bad "$(card ⓐ "기준판/새 판 rc=$rcb/$rc2")"
cmp -s "$T/base-out" "$T/out" && ok "$(card ⓐ '  └ stdout 기준판 cmp0(사람 출력 회귀 0)')" || bad "stdout 이 기준판과 다름: $(diff "$T/base-out" "$T/out" | head -4)"
hasnt "$(cat "$T/base-err")" "STEP ⑥증거검사" "$(card ⓐ '  └ 기준판 stderr 에는 STEP 0줄(대조군 확인)')"


echo "== ⓔ 실측 재현 — 카드 인자 꼴(--result · --recv · role=nano · press 산출 0)에서 STEP 줄이 끝까지"
setup; instant cherry-gate 0
n_press="$(git -C "$NW" diff --name-only "$BASE" HEAD | grep -c 'poller_dom\.jsonl')"
[ "$n_press" = "0" ] && ok "$(card ⓔ '  └ press 산출 0(나노 좌석)')" || bad "press 산출이 있다"
out="$(FEAT=feat/x close)"; rc=$?
has "$out" "WARN ④checkpoint 면제 — 나노 브랜치에 press 산출 0" "$(card ⓔ '④ 면제 자리(실측 마지막 줄) 재현')"
ST="$(steps_of "$(cat "$T/err")")"
[ "$(printf '%s\n' "$ST" | grep -c .)" = "5" ] && ok "$(card ⓔ '  └ STEP 5줄 끝까지(slots 포함)')" || bad "STEP 줄 $(printf '%s\n' "$ST" | grep -c .)개 ← $ST"


finish
