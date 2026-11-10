#!/usr/bin/env bash
# test_merge_land_part2_r1336.sh — test_merge_land.sh 의 2/3(R354 ⓔ3~ⓖ2) — 사전 DA ① R5: 기준판 단독 147 s > 시험 1개 70 s → 같은 단언을 3파일로(1/3 = test_merge_land.sh)
exec bash "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/test_merge_land.sh" 2
