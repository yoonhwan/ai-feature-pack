#!/usr/bin/env bash
# test_autonomy_standing_r947_old.sh — 얇은 묶음: r947 ⓗ «기존 시험 11개»를 차례로 부른다 (r1664 · test_autonomy_standing_r947.sh 가 70초를 넘겨 하드 룰 22 «넘으면 쪼갠다»).
# 검사 본문 = test_autonomy_core · test_autonomy_scope(그 자체가 4파일 묶음) · test_autonomy_scope_pack · test_autonomy_kinds_1675 · test_autonomy_hooks ·
#            test_merge_land · test_merge_land_pack_repo · test_merge_land_equiv · test_merge_land_off_approval · test_da_codex_wrapper · test_doc_exempt_r725
# 이 묶음 단독 실행은 시험 1개 70초 상한 대상 밖(상한은 위 11파일 각각에 건다 · 하드 룰 22 · r1197 test_autonomy_scope.sh 와 같은 꼴).
# 실 상태 지문(real_state_guard)은 11파일이 각자 건다 — 여기서 다시 걸지 않는다(자기 재호출 0).
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
rc=0
for t in test_autonomy_core test_autonomy_scope test_autonomy_scope_pack test_autonomy_kinds_1675 test_autonomy_hooks \
         test_merge_land test_merge_land_pack_repo test_merge_land_equiv test_merge_land_off_approval test_da_codex_wrapper test_doc_exempt_r725; do
  "$BASH" "$HERE/$t.sh" "$@" || rc=1
done
exit "$rc"
