#!/usr/bin/env bash
# test_nano_close_step_timing_r938_b2.sh (r1363: ⓑ 둘째 칸 = 카드 ref fetch 상한) — r938 단계 시각 줄 시험의 «fetch 상한·실패 경로(ⓑ · ⓙ · ⓛ)» 조각(r1318 나눔 · 원본 = test_nano_close_step_timing_r938.sh 1개).
#   왜 나눴나: r1316 뒤 이 시험이 끝까지 돌며 rc124(70초 초과 · 하드 룰 22) — 단언·변이 집합은 나누기 전과 같다(빼지 않고 옮기기만).
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/lib/r938_step_timing_fixture.sh"

echo "== ⓑ2 카드 ref(origin/main) fetch 대역 30초 → 상한 8초(지정) + 재시도 1 뒤 «WARN 카드 ref fetch 실패/시간 초과» · 총 ≤ 70초"
setup; _now="$(date +%s)"; out2="$(SLEEP_FETCH=30 FT_FETCH_TIMEOUT_SEC=8 close)"; took2="$(elapsed "$_now")"   # 카드 ref(origin/main) fetch 도 같은 상한
has "$out2" "WARN 카드 ref fetch 실패/시간 초과(origin/main" "$(card ⓑ '  └ 카드 ref fetch 도 25초+재시도 1(r1363)')"
[ "$took2" -le 24 ] && ok "$(card ⓑ '  └ 카드 ref fetch 총 소요 ≤ 24초(상한 8초 × 2 + 여유 · 기본 25초 값은 r1363 시험 D4 가 잰다)')" || bad "카드 ref fetch ${took2}s > 24초"

echo

finish
