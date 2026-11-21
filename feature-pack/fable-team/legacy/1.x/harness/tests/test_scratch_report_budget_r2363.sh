#!/usr/bin/env bash
# test_scratch_report_budget_r2363.sh — r2363 사례 칸 ①~⑦: ft-scratch-repo.sh --report(·--summary) 도 지우기 길과 «같은 판정 예산(FT_SCRATCH_JUDGE_BUDGET · 기본 20초)» 안에서만 사본 크기(du)를 잰다.
#   예산을 넘은 사본은 표에 남기고 크기만 «?»(0.00 아님) 로 두며, 못 잰 수를 1줄로 알린다(--summary 는 같은 줄에 « · 크기 못 잼 N개») · 지우기 길·다른 길은 그대로.
# 짝 = test_scratch_report_budget_mut_r2363.sh(변이 M1~M6) · 대역 = tests/lib/report_budget_r2363_bed.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${FT_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
. "$HERE/lib/report_budget_r2363_bed.sh"
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; done_line; }
bed_begin "$SUT"

if want ①; then
# ① K1 보고 예산 — 사본 16 · 가짜 du 0.5초/회 · 예산 3초 → du 부름 1~8회(16 아님) · rc0 · 회차 ≤ 10초
bed 16
t0=$SECONDS; BUDGET=3 sc --report; t1=$SECONDS; C="$(calls)"
{ [ "$RC" = 0 ] && [ "$C" -ge 1 ] && [ "$C" -le 8 ] && [ "$(( t1 - t0 ))" -le 10 ]; } \
  && ok "① --report du 부름 ${C}회(사본 16 · 예산 3초) · 회차 $(( t1 - t0 ))초 ≤ 10초" || bad "① rc=$RC du호출=$C 시간=$(( t1 - t0 ))초 out=$(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
fi

if want ②; then
# ② K1 --summary 도 같은 예산 — 사본 16 · 예산 3초 → du 부름 1~8회 · 요약 1줄 · rc0 · 회차 ≤ 10초
bed 16
t0=$SECONDS; BUDGET=3 sc --report --summary; t1=$SECONDS; C="$(calls)"
{ [ "$RC" = 0 ] && [ "$C" -ge 1 ] && [ "$C" -le 8 ] && [ "$(( t1 - t0 ))" -le 10 ] \
  && [ "$(printf '%s\n' "$OUT" | grep -c '^주인 없는 임시 사본')" = 1 ]; } \
  && ok "② --report --summary du 부름 ${C}회 · 회차 $(( t1 - t0 ))초 ≤ 10초 · 요약 1줄" || bad "② rc=$RC du호출=$C 시간=$(( t1 - t0 ))초 out=$OUT"
fi

if want ③; then
# ③ K2 못 잰 사본도 보임 — 예산을 넘어도 표 줄은 사본 16개 그대로 · 못 잰 줄은 «?»(0.00 아님) · 숫자 줄과 «?» 줄의 합 = 16
bed 16
BUDGET=3 sc --report; NROWS="$(rows)"; QUES="$(raws)"; ZERO="$(zero_rows)"
{ [ "$RC" = 0 ] && [ "$NROWS" = 16 ] && [ "$QUES" -ge 1 ] && [ "$ZERO" = 0 ] && [ $(( NROWS - QUES )) -ge 1 ]; } \
  && ok "③ 표 줄 16개 그대로 · «?» ${QUES}개 · 숫자 $(( NROWS - QUES ))개 · «0.00» 0개" || bad "③ rc=$RC 줄=$NROWS «?»=$QUES «0.00»=$ZERO"
fi

if want ④; then
# ④ K3 못 잰 수 1줄 — 경고 1줄 · 그 수 = «?» 줄 수(같은 눈금)
bed 16
BUDGET=3 sc --report; QUES="$(raws)"
WLINE="$(printf '%s\n' "$OUT" | grep -c '보고 예산(3초) 초과 · 크기 못 잰 사본')"
WN="$(printf '%s\n' "$OUT" | sed -n 's/.*크기 못 잰 사본 \([0-9]*\)개.*/\1/p' | head -1)"
{ [ "$WLINE" = 1 ] && [ -n "$WN" ] && [ "$WN" = "$QUES" ]; } \
  && ok "④ 못 잰 수 경고 1줄 · «${WN}개» = «?» 줄 ${QUES}개" || bad "④ 경고=$WLINE 수=$WN «?»=$QUES out=$OUT"
fi

if want ⑤; then
# ⑤ K3 --summary 같은 줄 — «· 크기 못 잼 N개» · GiB 는 예산 안에서 잰 사본만(사본 1개 = 1.00 GiB) → 잰 수 + 못 잼 수 = 16
bed 16
BUDGET=3 sc --report --summary; SL="$(sumline)"
GIB="$(printf '%s' "$SL" | sed -n 's/^주인 없는 임시 사본 16개 \([0-9]*\)\.00 GiB.*/\1/p')"
MISS="$(printf '%s' "$SL" | sed -n 's/.* · 크기 못 잼 \([0-9]*\)개.*/\1/p')"
{ [ "$RC" = 0 ] && [ -n "$GIB" ] && [ -n "$MISS" ] && [ "$MISS" -ge 1 ] && [ $(( GIB + MISS )) = 16 ]; } \
  && ok "⑤ 요약 같은 줄 — ${GIB}.00 GiB(잰 ${GIB}개) · 크기 못 잼 ${MISS}개 = 16" || bad "⑤ rc=$RC 요약=[$SL]"
fi

if want ⑥; then
# ⑥ K4 다른 길 그대로 — 예산이 넉넉하면(기본 20초 · 사본 3) 표는 «지금 그대로»: du 부름 = 사본 수 · «?» 0 · 못 잰 경고 0
bed 3
sc --report; C="$(calls)"; NROWS="$(rows)"; QUES="$(raws)"
{ [ "$RC" = 0 ] && [ "$C" = 3 ] && [ "$NROWS" = 3 ] && [ "$QUES" = 0 ] && ! printf '%s' "$OUT" | grep -q '크기 못 잰'; } \
  && ok "⑥ 예산 넉넉 — du 3회(사본 3) · «?» 0 · 경고 0(보고 표 그대로)" || bad "⑥ rc=$RC du호출=$C 줄=$NROWS «?»=$QUES out=$OUT"
fi

if want ⑦; then
# ⑦ (r2398a K2 정정) 지우기 길은 크기를 안 잰다 — --sweep 사본 8 · 예산 1초 → du 부름 0 · 끝 줄 judged=8 · rc0
#    (r2363 때는 «du 가 예산을 먹어 다음 틱» 이 계약이었다 — K2 가 du 를 지우기 길에서 빼서 그 자리는 «du 0 + judged 수» 가 계약이 된다)
bed 8
: > "$ARMED"
BUDGET=1 sc --sweep; C="$(calls)"
J="$(printf '%s\n' "$OUT" | sed -n 's/.*judged=\([0-9][0-9]*\).*/\1/p' | tail -1)"
{ [ "$RC" = 0 ] && [ "$C" = 0 ] && [ "${J:-0}" = 8 ]; } \
  && ok "⑦ --sweep du 부름 0회(지우기 길 = 크기 «?» · K2) · judged=$J · rc0" || bad "⑦ rc=$RC du호출=$C judged=${J:-?} out=$(printf '%s' "$OUT" | tail -3 | tr '\n' ' ')"
fi

if want cmp; then
# bin·kit 같은 글자(설치는 h 몫 · 여기서는 사본만 맞춘다)
cmp -s "$REPO/harness/bin/ft-scratch-repo.sh" "$REPO/harness/kit/fable-team/bin/ft-scratch-repo.sh" \
  && ok "bin·kit 같은 글자(cmp 0)" || bad "bin·kit 다름"
fi

done_line
