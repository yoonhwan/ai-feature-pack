#!/usr/bin/env bash
# test_scratch_report_budget_mut_r2363.sh — r2363 변이 칸 M1~M6: 고침 한 곳만 되돌린 변이 판이 «그 칸만» 빨강이 되는지(원본 대조 = 같은 대역에서 원본은 초록).
#   M1 예산 시계 제거 · M2 예산 바닥에 표 줄 건너뜀 · M3 못 잰 수 안 셈 · M4 요약에 못 잰 수 없음 · M5 지우기 길 가드 제거 · M6 표 awk «?» → 0.00
# 짝 = test_scratch_report_budget_r2363.sh(사례 ①~⑦) · 대역 = tests/lib/report_budget_r2363_bed.sh
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${FT_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
. "$HERE/lib/report_budget_r2363_bed.sh"
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; done_line; }
bed_begin "$SUT"

if want 변이-M1; then
# M1 K1 «보고 길 예산 없음(ODL=0) = 지금 그대로» → ① 의 «du 부름 ≤ 6» 이 깨진다(사본 12 = 12회)
mut M1 's/ODL=$(( now + ${FT_SCRATCH_JUDGE_BUDGET:-20} ))   # r2363/ODL=0   # r2363-mut/' && {
  bed 16; FT_SUT="$MUT" BUDGET=3 sc --report; MC="$(calls)"
  [ "$MC" -gt 8 ] && ok "변이 M1(보고 길 예산 제거) → du ${MC}회 > 8 = ① 빨강(변이 잡힘)" || bad "변이 M1 을 못 잡음 — 예산을 없애도 du ${MC}회"
}
fi

if want 변이-M2; then
# M2 K2 «예산 바닥 = 지우기 길 꼴(continue)» → ③ 의 «표 줄 12개» 가 깨진다(못 잰 사본이 표에서 사라진다)
mut M2 's/\[ "\$oleft" != 0 \] || { ORPT_MARK=1; ODEF=\$((ODEF+1)); return 0; }/[ "$oleft" != 0 ] || { ORPT_MARK=1; ODEF=$((ODEF+1)); return 1; }/' && {
  bed 16; FT_SUT="$MUT" BUDGET=3 sc --report; MR="$(rows)"
  [ "$MR" -lt 16 ] && ok "변이 M2(표 줄 건너뜀) → 표 ${MR}줄 < 16 = ③ 빨강(변이 잡힘)" || bad "변이 M2 를 못 잡음 — 건너뛰어도 표 ${MR}줄"
}
fi

if want 변이-M3; then
# M3 K3 «못 잰 수를 안 센다(ODEF 증가 3곳 제거)» → ④ 의 경고 1줄·수 대조가 깨진다
mut M3 's/\[ "\$ORPT_MARK" = 0 \] || { ODEF=\$((ODEF+1)); return 0; }/[ "$ORPT_MARK" = 0 ] || { return 0; }/' \
  -e 's/{ ORPT_MARK=1; ODEF=\$((ODEF+1)); return 0; }/{ ORPT_MARK=1; return 0; }/' \
  -e 's/isnum "\$COPY_KB" || { ODEF=\$((ODEF+1)); COPY_KB='"'"'?'"'"'; }/isnum "$COPY_KB" || COPY_KB='"'"'?'"'"'/' && {
  bed 16; FT_SUT="$MUT" BUDGET=3 sc --report
  MW="$(printf '%s\n' "$OUT" | grep -c '보고 예산(3초) 초과 · 크기 못 잰 사본')"
  [ "$MW" = 0 ] && ok "변이 M3(못 잰 수 안 셈) → 경고 0줄 = ④ 빨강(변이 잡힘)" || bad "변이 M3 을 못 잡음 — 안 세도 경고 ${MW}줄 out=$OUT"
}
fi

if want 변이-M4; then
# M4 K3 «--summary 같은 줄에 못 잰 수 없음» → ⑤ 가 깨진다
mut M4 's/ · 크기 못 잼 %s개//' && {
  bed 16; FT_SUT="$MUT" BUDGET=3 sc --report --summary; MS="$(sumline)"
  ! printf '%s' "$MS" | grep -q '크기 못 잼' && ok "변이 M4(요약에 못 잰 수 없음) → ⑤ 빨강(변이 잡힘): [${MS}]" || bad "변이 M4 를 못 잡음 — 요약=[$MS]"
}
fi

if want 변이-M5; then
# M5 K4 «지우기 길 예산 가드 제거» → ⑦ 의 «du 부름 ≤ 5» 가 깨진다(사본 8 = 8회)
mut M5 's/if \[ "\$ODL" != 0 \] && \[ "\$oleft" = 0 \]; then ODEF=\$((ODEF+1)); return 1; fi/if [ 0 = 1 ]; then ODEF=$((ODEF+1)); return 1; fi/' && {
  bed 8; : > "$ARMED"; FT_SUT="$MUT" BUDGET=1 sc --sweep; MC="$(calls)"
  [ "$MC" -gt 5 ] && ok "변이 M5(지우기 길 가드 제거) → du ${MC}회 > 5 = ⑦ 빨강(변이 잡힘)" || bad "변이 M5 를 못 잡음 — 가드를 없애도 du ${MC}회"
}
fi

if want 변이-M6; then
# M6 K2 «표 awk 예산 밖 kb → 0(.00) 되돌림» → ③ 의 ««0.00» 0개» 가 깨진다
mut M6 's/{ printf "?\\t%s\\t%s\\n", \$2, \$4; next }/k=0;/' && {
  bed 16; FT_SUT="$MUT" BUDGET=3 sc --report; MZ="$(zero_rows)"
  [ "$MZ" -ge 1 ] && ok "변이 M6(«?» → 0.00) → «0.00» ${MZ}줄 = ③ 빨강(변이 잡힘)" || bad "변이 M6 를 못 잡음 — 되돌려도 «0.00» ${MZ}줄"
}
fi

done_line
