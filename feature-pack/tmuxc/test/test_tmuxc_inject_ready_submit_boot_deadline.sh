#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit_boot_deadline.sh — «마감·재전송 경계» 칸을 «이어가기(boot-enter)» 경로로만 돈다.
#   본문은 _cases_tmuxc_inject_deadline.sh(공용) — 같은 파일을 …_deadline.sh 는 FT_WHOS=inject 로 돈다.
#   r1075 에서 넷으로 쪼갠 이유: 부하 43 에 한 파일이 79초를 넘었다(하드 룰 22 · 각 파일 70초 안).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_harness_tmuxc_inject.sh"
FT_WHOS=boot
. "$HERE/_cases_tmuxc_inject_deadline.sh"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
