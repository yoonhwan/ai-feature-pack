#!/usr/bin/env bash
# test_stall_human_wait_base_r2380.sh — r2380 기준판(팩 origin/main) 대조: 새 갈래가 없던 판은 점검·풀림 시험이 FAIL(Red), «지금 그대로» 시험은 PASS.
#   앞 갈래 Red = c06 c08 c12 c13 · 뒷 갈래 Red = c15 c16 c17 c18 c20 · 그대로 = c07 c09 c10 c11 c14 c19 (6 passed)
# 형제 시험: test_stall_human_wait_r2380.sh(신판 ⑥~⑬) · _b(⑭~⑳) · _mut(변이) · _regress(기존)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; SC="$HERE/scripts"; PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_stall_lib.sh"
r2380_base
gone() {  # $1=py 파일 $2=기대 Red 목록 — 기준판 한 번 돌려 실패 목록만 본다
  local f="$1" want got
  (ulimit -u 2000; cd "$SC" && R2380_BIN="$BASE" R2380_BASE_BIN= timeout 140 python3.11 -m pytest -q -p no:cacheprovider --tb=no -rf "$f" >"$T/base.log" 2>&1)
  got="$(grep -E '^FAILED' "$T/base.log" | sed -E 's/^FAILED [^ ]*::test_([a-z0-9]+)_.*/\1/' | sort | tr '\n' ' ')"
  want="$(printf '%s\n' $2 | sort | tr '\n' ' ')"
  [ "$got" = "$want" ]; ck "기준판 $f Red = $2 (실측: $got)" $?
  grep -qE '[0-9]+ passed' "$T/base.log"; ck "기준판 $f «그대로» 시험 PASS $(grep -Eo '[0-9]+ passed' "$T/base.log")" $?
}
if [ -n "$BASE" ]; then
  gone test_stall_human_wait_r2380.py "c06 c08 c12 c13"
  gone test_stall_human_wait_b_r2380.py "c15 c16 c17 c18 c20"
else echo "WARN 기준판 없음(origin/main 에 팩 없음) — 대조 건너뜀"; fi
lap 기준판
echo "FAIL=$fail"; [ "$fail" -eq 0 ]
