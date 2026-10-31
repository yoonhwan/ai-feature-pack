#!/usr/bin/env bash
# test_press_gate_step1_cache_r1260_b.sh — r1260 press 게이트 ① 판정 캐시(2/4): 입력이 바뀌면 키가 달라져 다시 돈다
#   R2 나노 작업 트리에 커밋 1 · R3 FEAT 원격 끝 이동 · R4a 러너 HEAD · R4b 러너 경로만(같은 HEAD) · R5a 현역 나노 목록 · R5a2 .worktree-info.json 내용
#   R5b 선언 base ref 끝만 이동(작업 트리·info 파일 그대로) · R5b2 base ref 해석 실패 = 캐시 0
#   R5c press 카드를 «제외 선언 있음 → 없음» 으로 바꿈 · R5c2 같은 카드에서 선언 줄만 삭제
set -uo pipefail
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
run_cases "$P" r2 r3 r4a r4b r5a r5a2 r5b r5b2 r5c r5c2
[ -z "$BAD" ] && ok "R2·R3·R4a·R4b·R5a·R5a2·R5b·R5b2·R5c·R5c2 통과" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -12 | sed 's/^/    /'; }
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
