#!/usr/bin/env bash
# ft-resource-swap-lib.sh — r672: «swap 축» 판정은 이 파일 하나다. 문지기(ft-resource-gate.sh)와 감시자(ft-resource-watch.sh)가
#   같은 함수·같은 env(FT_SWAP_MEMFREE_MAX)를 쓰게 해서, 두 곳이 다른 문턱으로 어긋나 동결/해제가 플래핑하던 길(DA⑥ r1 H2)을 닫는다.
#   판정식 = swap > SWAP_HARD(12288) ∧ level ≥ LEVEL_MIN(2) ∧ memfree < FT_SWAP_MEMFREE_MAX(30).
#   FT_SWAP_MEMFREE_MAX = 양의 정수만 · 그 밖(0·음수·비숫자·빈 값)은 기본 30 + FT_SWAP_MEMFREE_WARN 1줄(조용한 후퇴 금지 · 감시자는 죽지 않는다 — 옛 판에서 `${FT_SWAP_MEMFREE_MAX}` 직접 확장이 set -u unbound 로 감시자를 죽였다).
#   되돌림 = FT_SWAP_MEMFREE_MAX=100(옛 동작: swap·level 만).
#   쓰는 법: . ft-resource-swap-lib.sh
#     ft_swap_memfree_max; MAX="$FT_SWAP_MEMFREE_MAX_VAL"   # 한계 = FT_SWAP_MEMFREE_MAX_VAL · 경고문 = FT_SWAP_MEMFREE_WARN(전역)
#     ft_swap_axis_hit <swap> <level> <memfree> <SWAP_HARD> <LEVEL_MIN> <MAX>   # rc0 = swap 축 트리거

ft_swap_memfree_max() {
  local v="${FT_SWAP_MEMFREE_MAX:-30}" bad=0
  FT_SWAP_MEMFREE_WARN=""
  case "$v" in ''|*[!0-9]*) bad=1;; *) [ "$((10#$v))" -ge 1 ] || bad=1;; esac
  [ "$bad" = 0 ] || { FT_SWAP_MEMFREE_WARN="FT_SWAP_MEMFREE_MAX=${v} 무효(양의 정수 아님) — 기본 30 사용"; v=30; }
  FT_SWAP_MEMFREE_MAX_VAL="$v"   # 전역에 남긴다 — $(...) 안에서 부르면 경고문이 subshell 에 갇힌다(DA⑥ r1 H2). 출력 0.
}

ft_swap_axis_hit() { # swap level memfree SWAP_HARD LEVEL_MIN MEMFREE_MAX
  [ "${1:-0}" -gt "${4:-0}" ] && [ "${2:-0}" -ge "${5:-0}" ] && [ "${3:-100}" -lt "${6:-0}" ]
}
