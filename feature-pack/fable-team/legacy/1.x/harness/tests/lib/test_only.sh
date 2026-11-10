#!/usr/bin/env bash
# test_only.sh — 시험 «그 칸만» 돌리기 공용 함수 (r1026 · 하드 룰 22 «변이는 그 칸만»).
#   쓰는 법: . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/test_only.sh"
#            ft_only ⓐ && { <ⓐ 절> }   …   ft_only_report   (맨 끝에 1번)
#   ft_only <칸>   : FT_TEST_ONLY 가 비었으면 rc0(전부 돈다 = 기존 동작 그대로) · 값의 쉼표 목록에 <칸> 이 있으면 rc0 · 아니면 rc1
#   ft_only_report : FT_TEST_ONLY 가 있는데 실제로 돈 칸이 0 이면 `BAD FT_TEST_ONLY=<값> 에 맞는 칸 0` 1줄 + rc1(오타로 «0 FAIL = 통과» 가 되는 길 차단)
#   /bin/bash 3.2 · 외부 명령 0(내장 확장만) · 실행 파일 아님(source 전용).
ft_only_ran=0
ft_only() {
  local want rest item
  want="${1-}"
  if [ -z "${FT_TEST_ONLY-}" ]; then ft_only_ran=$((ft_only_ran + 1)); return 0; fi
  [ -n "$want" ] || return 1
  rest="${FT_TEST_ONLY},"
  while [ -n "$rest" ]; do
    item="${rest%%,*}"
    rest="${rest#*,}"
    item="${item#"${item%%[![:space:]]*}"}"   # 앞 공백 제거
    item="${item%"${item##*[![:space:]]}"}"   # 뒤 공백 제거
    if [ "$item" = "$want" ]; then ft_only_ran=$((ft_only_ran + 1)); return 0; fi
  done
  return 1   # 목록에 없음
}
ft_only_report() {
  [ -n "${FT_TEST_ONLY-}" ] || return 0
  [ "${ft_only_ran:-0}" -gt 0 ] && return 0
  echo "BAD FT_TEST_ONLY=$FT_TEST_ONLY 에 맞는 칸 0"
  return 1
}
