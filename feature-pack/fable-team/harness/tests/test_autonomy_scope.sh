#!/usr/bin/env bash
# test_autonomy_scope.sh — 얇은 묶음: 범위 승인 시험 3파일을 차례로 부른다 (r1197 · 옛 144 검사 1파일 단독 98~103초 → 하드 룰 22 «넘으면 쪼갠다»).
# 검사 본문 = test_autonomy_scope_grant.sh · test_autonomy_scope_stop_tamper.sh · test_autonomy_scope_code_hook.sh(공용 준비 lib/autonomy_scope_setup.sh).
# 이 묶음은 옛 이름을 부르는 회귀(test_autonomy_standing_r947.sh ⓗ 등)용이다 — 묶음 단독 실행은 시험 1개 70초 상한 대상 밖(상한은 3파일 각각에 건다).
# 실 상태 지문(real_state_guard)은 3파일이 각자 건다 — 여기서 다시 걸지 않는다(자기 재호출 0).
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
rc=0
for t in test_autonomy_scope_grant test_autonomy_scope_stop_tamper test_autonomy_scope_code_hook; do
  "$BASH" "$HERE/$t.sh" "$@" || rc=1
done
exit "$rc"
