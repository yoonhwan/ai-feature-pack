#!/usr/bin/env bash
# test_scratch_sweep_cursor_mut_r2372.sh — r2372 변이 M1~M4: 사본에서만 한 곳을 고쳐 «그 반례가 FAIL» 인지 본다
#   M1 cursor 읽기 지움 → ① / M2 번갈아 대신 등록 사본 다 보고 tmp → ② / M3 cursor 를 «이름 같음» 만으로 → ③ / M4 «처음부터 돌림(회전)» 지움 → ③
#   변이마다 «원본으로 같은 사례 1회 더» — 변이 = FAIL ∧ 원본 = PASS 일 때만 잡힌 것으로 센다(다른 FAIL 섞이면 못 잡음)
# 사례 파일(test_scratch_sweep_cursor_r2372.sh)을 FT_SUT·FT_TEST_ONLY 로 다시 부른다 — 실 상태 0 · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
SUT="${FT_SUT:-$REPO/bin/ft-scratch-repo.sh}"
CASES="$HERE/test_scratch_sweep_cursor_r2372.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }
[ -f "$CASES" ] || { bad "사례 파일 없음 ($CASES)"; echo "(1 failed)"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mut() { # <번호> <sed 식> <사례> <설명>
  local n="$1" ex="$2" cs="$3" desc="$4" o m r
  sed "$ex" "$SUT" > "$T/m-$n.sh" 2>/dev/null
  if cmp -s "$SUT" "$T/m-$n.sh"; then bad "M$n 주입 실패(바꾼 줄 없음) — $desc"; return; fi
  o="$(FT_SUT="$T/m-$n.sh" FT_TEST_ONLY="$cs" bash "$CASES" 2>&1)"
  case "$o" in *FAIL*) m=잡힘;; *) m=못잡음;; esac
  o="$(FT_SUT="$SUT" FT_TEST_ONLY="$cs" bash "$CASES" 2>&1)"
  case "$o" in *FAIL*) r=원본도FAIL;; *) r=원본PASS;; esac
  { [ "$m" = 잡힘 ] && [ "$r" = 원본PASS ]; } && ok "M$n $desc — 변이 FAIL($cs) · 원본 PASS" \
    || bad "M$n $desc — 변이=$m 원본=$r $(printf '%s\n' "$o" | grep -m1 '^FAIL' | cut -c1-120)"
}

mut 1 's/^    cur_read$/    :/'                                                                    ① "cursor 읽기를 지움(늘 처음부터)"
mut 2 's/^    ALT_ON=1$/    ALT_ON=0/'                                                             ② "번갈아 대신 등록 사본 다 보고 tmp"
mut 3 's/if cge "${A\[\$mid\]%%"\$TAB"\*}" "\$c"; then/if [ "${A[$mid]%%"$TAB"*}" = "$c" ]; then/' ③ "cursor 를 «이름 같음» 만으로"
mut 4 's/^  while \[ "\$k" -lt "\$S" \]; do printf .*$/  while [ 0 = 1 ]; do printf "%s\\n" "${A[$k]}"; k=$((k+1)); done/' ③ "«처음부터 돌림(회전)» 지움"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
