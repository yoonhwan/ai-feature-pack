#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit_deadline.sh — r925 r5~r8 «마감·재전송 경계» 칸을 «주입 경로» 로 돈다(ⓘ ⓙ + ⓙ2~ⓙ6b).
#   경계 칸 본문은 _cases_tmuxc_inject_deadline.sh(공용 · boot 경로는 …_boot.sh 가 같은 파일을 돈다).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/_harness_tmuxc_inject.sh"
FT_WHOS=inject
. "$HERE/_cases_tmuxc_inject_deadline.sh"

# ⓘ 첫 Enter 가 먹혔지만 기록이 «마지막 조회 직후»(재전송 판정 순간)에 생김 → 재전송 직전 재조회로 재전송 0 · rc0
fresh; : > "$D/ready"; : > "$D/enter_deferred"; printf '3\n' > "$D/rec_at_cap"   # 판독 3번째 = 재전송 판정의 입력줄 읽기
TMUXC_SUBMIT_WAIT=2 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" = 0 ] && grep -q 'state=submitted' "$T/out" && [ "$(enters)" = 1 ] && [ "$(rec_count)" = 1 ]; } \
  && ok "ⓘ 마지막 조회 직후 기록 생김 → 재전송 0(Enter 1) · rc=0" \
  || bad "ⓘ rc=$RC enters=$(enters) rec=$(rec_count) out=$(outline)"

# ⓙ 조회마다 0.04초 지연 × 많음 + WAIT=7 · Enter 전부 유실 → 벽시계 마감으로 9초 전에 rc≠0
fresh; : > "$D/ready"; printf '999\n' > "$D/enters_lost"
LOOKUP_DELAY=0.04 TMUXC_SUBMIT_WAIT=7 call_limited inject_message sess "$MSG" agent "$SID"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q '제출 실패' "$T/out" && python3 -c "import sys; sys.exit(0 if ${SECS} < 9 else 1)"; } \
  && ok "ⓙ 조회 지연 0.04초 + WAIT=7 → ${SECS}s(<9) 에 rc=$RC · 벽시계 마감" \
  || bad "ⓙ rc=$RC secs=${SECS} out=$(outline)"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
