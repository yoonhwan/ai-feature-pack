#!/usr/bin/env bash
# ft-verdict-row.sh — source 전용. planner 판정 원장(VERDICTS-planner-*.md)의 «두 꼴»을 한 곳에서 읽는다 (R255 · R257).
#   글머리 `- **N** …`  ·  표 행 `| N | 시각 | 내용 |`   — 번호 경계 엄격(`| 16460 |`·`- **1646a**` 는 1646 이 아님).
#   fv_row_re <n>  → 그 번호의 줄 머리를 잡는 ERE 출력(grep -E · git grep -E 공용). n 이 숫자가 아니면 rc 2.
#   fv_max         → stdin 원장 줄에서 두 꼴 번호의 최대값 출력. 번호가 0개면 rc 1 + 빈 출력(번호 지어내기 0).
# 쓰는 곳: ft-proxy-decide.sh(다음 번호 발급 · card-start 판정 줄 조회) · ft-index-lint.sh(조건부 승인 예외 조회).

fv_row_re() {
  case "${1:-}" in ''|*[!0-9]*) return 2 ;; esac
  printf '%s' "^(- \\*\\*${1}\\*\\*|\\|[[:space:]]*${1}[[:space:]]*\\|)"
}

fv_max() {
  local m
  m="$(sed -nE -e 's/^- \*\*([0-9]+)\*\*.*/\1/p' -e 's/^\|[[:space:]]*([0-9]+)[[:space:]]*\|.*/\1/p' | sort -n | tail -1)"
  [ -n "$m" ] || return 1
  printf '%s\n' "$m"
}
