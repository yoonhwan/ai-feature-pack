#!/usr/bin/env bash
# test_press_baseline_no_assoc_array_r2249.sh — r2249 O3: press 기준선 시험 2개에 연관 배열 문법 0(grep · 시험 실행 0).
#   왜: macOS /bin/bash 3.2 는 연관 배열이 없고, 그 줄에서 죽어도 rc 0 이 나와 시험이 녹색으로 보였다(arch-pi#460 ⓧ1 ⓧ2).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
fail=0; n=0
for f in test_press_baseline_check.sh test_press_baseline_card_from_ref_r1177.sh; do
  n=$((n+1))
  if [ ! -f "$HERE/$f" ]; then echo "FAIL $f: 파일 없음"; fail=$((fail+1)); continue; fi
  hits="$(grep -nE '(local|declare|typeset)[[:space:]]+-[a-zA-Z]*A|\$\{![A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}' "$HERE/$f")"
  if [ -z "$hits" ]; then echo "PASS $f: 연관 배열 문법 0"
  else echo "FAIL $f: 연관 배열 문법 $(printf '%s\n' "$hits" | grep -c .)줄"; printf '%s\n' "$hits" | sed 's/^/    /'; fail=$((fail+1)); fi
done
echo "cases=$n fail=$fail"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || exit 1
