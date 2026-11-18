#!/usr/bin/env bash
# test_merge_land_card_md_overlap_mut_r2215.sh — r2215 짝 시험(r2253 쪼갬): 변이 M1~M5(사본) + 원본 대조(같은 사례 새 PR)
#   세계·도우미 = test_merge_land_card_md_overlap_r2215.sh 를 R2215_WORLD_ONLY=1 로 source(사례 ②~⑪ 은 안 돎) · 본 시험과 나눈 까닭 = 시험 1개 70초 상한(하드 룰 22)
#   실 PR·실 main·실 gh·실 push 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
R2215_WORLD_ONLY=1 . "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_merge_land_card_md_overlap_r2215.sh"
F11="$(mkbin eq-two)"; fakeeq "$F11" 2   # M5 원본 대조용(본 시험 ⑪ 과 같은 가짜 equiv)
# ===== 변이 M1~M5(사본) + 원본 대조(같은 사례 새 PR) =====
M1D="$(mkbin m1)"; medit "$M1D" ft-merge-land.sh 'x="$(fm_not_card_md <<<"$x" | head -n1)"' "x=\"\$(grep -v '\\.md\$' <<<\"\$x\" | head -n1)\""
sc6b 101; land "$M1D/ft-merge-land.sh" 101 --approve-sha "$A"; landed 101; ck "M1(50행 «아무 .md») → ⑥b FAIL 재현(LANDED)" $?
sc6b 102; land "$LAND" 102 --approve-sha "$A"; rejected "$MB"; ck "M1 원본 대조 ⑥b → REJECT" $?
M2D="$(mkbin m2)"; medit "$M2D" ft-merge-land.sh '[ -z "$(fm_not_card_md <<<"$OVF")" ]; }' 'true; }'
sc5b 103; land "$M2D/ft-merge-land.sh" 103 --approve-sha "$A"; landed 103; ck "M2(58행 코드 섞여도 통과) → ⑤b FAIL 재현(LANDED)" $?
sc5b 104; land "$LAND" 104 --approve-sha "$A"; rejected "$MB"; ck "M2 원본 대조 ⑤b → REJECT" $?
M3D="$(mkbin m3)"; medit "$M3D" ft-merge-land.sh 'OVF="$(fm_card_overlap "$REPO" "$AP" "$S" "refs/remotes/$REMOTE/$TARGET")"' "OVF=\"\$(printf '%s' \"\$EQ\" | sed -n 's/.* names=\\([^ ]*\\).*/\\1/p' | tail -n1 | tr ',' '\\n')\""
sc 105 "$(card 105a)" "$(card 105b)" "$(card 105c)" "$(card 105d)"; land "$M3D/ft-merge-land.sh" 105 --approve-sha "$A"; rejected "$MB" && [[ "$out" == *"겹침 수 다름(셈 3 · equiv 4)"* ]]; ck "M3(equiv names= 로 셈) → ⑨ FAIL 재현(REJECT)" $?
sc 106 "$(card 106a)" "$(card 106b)" "$(card 106c)" "$(card 106d)"; land "$LAND" 106 --approve-sha "$A"; landed 106; ck "M3 원본 대조 ⑨ → LANDED" $?
M4D="$(mkbin m4)"; medit "$M4D" ft-merge-lib.sh "'^design/teams/[^/]+/indices/.+" "'^design/teams/[^/]+/indices.+"
sc8 107; land "$M4D/ft-merge-land.sh" 107 --approve-sha "$A"; landed 107; ck "M4(indices 뒤 / 빼기) → ⑧ FAIL 재현(LANDED)" $?
sc8 108; land "$LAND" 108 --approve-sha "$A"; rejected "$MB"; ck "M4 원본 대조 ⑧ → REJECT" $?
M5D="$(mkbin m5)"; medit "$M5D" ft-merge-land.sh '[ "$(grep -c . <<<"$OVF")" = "$OV" ] ||' 'true ||'; fakeeq "$M5D" 2
sc 109 "$(card 109)"; land "$M5D/ft-merge-land.sh" 109 --approve-sha "$A"; landed 109; ck "M5(겹침 수 대조 빼기) → ⑪ FAIL 재현(LANDED)" $?
sc 110 "$(card 110)"; land "$F11/ft-merge-land.sh" 110 --approve-sha "$A"; rejected "$MB"; ck "M5 원본 대조 ⑪ → REJECT" $?

echo "단계 초: 전체 $((SECONDS - T_START))s"
echo "== $([ "$fail" = 0 ] && echo OK || echo "FAIL $fail") =="
[ "$fail" = 0 ]
