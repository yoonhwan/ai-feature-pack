#!/bin/bash
# test_launchd_exit_allow_r1184.sh — r1184: 죽은 예약 판정 앞 «Label → 허용 exit 범위» 예외 표
# R1 표 «com.byz.gce-guard-check 90-99» · exit 91 → INFO «예외 표 허용(90-99)» · [급] 0 · 표식 0 · rc0
# R2 같은 표 · exit 1 → 죽은 예약 + [급] 1통 + 표식(범위 밖)
# R3 같은 표 · com.byz.other exit 91 → 죽은 예약 + [급](표 밖 Label)
# R4 표 파일 없음 · exit 91 → 죽은 예약 + [급]
# R5 표 줄 뒤집힘(99-90) · 글자(abc) → stderr «예외 표 줄 형식 틀림» 1줄 · exit 91 은 죽은 예약 + [급]
# R6 표 «com.byz.gce-guard-check 91» · exit 91 → 허용 · exit 92 → 죽은 예약
# ⓓ bin·kit 같은 내용(cmp0)
# FT_LDC_BASE_BIN=<기준판> 이면 R2~R4 stdout 이 기준판과 같은지도 본다.
# 변이 = FT_LDC_TEST_BIN=<허용 분기 지운 판> 으로 같은 시험 → R1 FAIL 이어야 한다. 실 launchctl·mbox·state 0 — 전부 가짜. 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team/bin"
SCRIPT="${FT_LDC_TEST_BIN:-$BIN/ft-launchd-check.sh}"
BASE="${FT_LDC_BASE_BIN:-}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

R="$T/root"; G=com.byz.gce-guard-check
mkdir -p "$T/bin" "$T/rec" "$R"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.calls"\n' "$T" > "$T/mbox.sh"
cat > "$T/bin/launchctl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  print-disabled) : ;;
  list) cat "$T/list.txt";;
  print) cat "$T/print.\${2##*/}" 2>/dev/null;;
esac
exit 0
EOF
chmod +x "$T/mbox.sh" "$T/bin/launchctl"
: > "$T/g.sh"
for l in "$G" com.byz.other; do printf 'gui/501/%s = {\n\targuments = {\n\t\t/bin/bash\n\t\t%s\n\t}\n}\n' "$l" "$T/g.sh" > "$T/print.$l"; done
dead() { printf 'PID\tStatus\tLabel\n-\t%s\t%s\n' "$2" "$1" > "$T/list.txt"; }
table() { printf '%s\n' "$@" > "$T/exit-ok.txt"; }
calls() { [ -f "$T/mbox.calls" ] && wc -l < "$T/mbox.calls" | tr -d ' ' || echo 0; }
marks() { find "$T/state" -type f 2>/dev/null | wc -l | tr -d ' '; }
reset() { rm -f "$T/mbox.calls"; rm -rf "$T/state"; }
# $1 = 돌릴 판 · stdout → $T/out · stderr → $T/err
ldc() {
  ( cd "$R" && GIT_CEILING_DIRECTORIES="$T" FT_LDC_EXPECTED="$T/none.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state" \
      FT_LDC_NOW=2026-10-30 FT_LDC_MBOX="$T/mbox.sh" FT_LDC_LAUNCHCTL="$T/bin/launchctl" FT_LDC_NOTIFY='H#1' \
      FT_LDC_EXIT_OK="$T/exit-ok.txt" bash "$1" >"$T/out" 2>"$T/err" )
}
# 경보 쪽: 죽은 예약 줄 + [급] 1통 + 표식 1 (+ 기준판과 stdout 같음)
alarmed() {
  local want="죽은 예약 $1 exit=$2(대상 있음: $T/g.sh)"
  [ "$rc" -eq 0 ] && [ "$(cat "$T/out")" = "$want" ] && [ "$(calls)" = 1 ] && [ "$(marks)" = 1 ] || return 1
  [ -z "$BASE" ] && return 0
  cp "$T/out" "$T/out.new"; reset; ldc "$BASE"; cmp -s "$T/out" "$T/out.new"
}

# R1 범위 안 → INFO 1줄 · [급] 0 · 표식 0
table "$G 90-99"; dead "$G" 91; reset; ldc "$SCRIPT"; rc=$?
[ $rc -eq 0 ] && [ "$(cat "$T/out")" = "예약 $G exit=91 — 예외 표 허용(90-99)" ] && [ "$(calls)" = 0 ] && [ "$(marks)" = 0 ] \
  && ok "R1 표 90-99 · exit 91 → INFO 1줄 · [급] 0 · 표식 0" || bad "R1 rc=$rc calls=$(calls) marks=$(marks): $(cat "$T/out" "$T/err")"

# R2 범위 밖 exit 1
table "$G 90-99"; dead "$G" 1; reset; ldc "$SCRIPT"; rc=$?
alarmed "$G" 1 && ok "R2 exit 1(범위 밖) → 죽은 예약 + [급] 1통 + 표식" || bad "R2 rc=$rc calls=$(calls) marks=$(marks): $(cat "$T/out" "$T/err")"

# R3 표 밖 Label
table "$G 90-99"; dead com.byz.other 91; reset; ldc "$SCRIPT"; rc=$?
alarmed com.byz.other 91 && ok "R3 표 밖 Label exit 91 → 죽은 예약 + [급]" || bad "R3 rc=$rc calls=$(calls) marks=$(marks): $(cat "$T/out" "$T/err")"

# R4 표 파일 없음
rm -f "$T/exit-ok.txt"; dead "$G" 91; reset; ldc "$SCRIPT"; rc=$?
alarmed "$G" 91 && ok "R4 표 없음 · exit 91 → 죽은 예약 + [급]" || bad "R4 rc=$rc calls=$(calls) marks=$(marks): $(cat "$T/out" "$T/err")"

# R5 형식 틀림(뒤집힘 · 글자) → ERROR 1줄 · 경보 쪽
for bad_row in "$G 99-90" "$G abc"; do
  table "$bad_row"; dead "$G" 91; reset; ldc "$SCRIPT"; rc=$?
  errs="$(grep -c '^ERROR ft-launchd-check: 예외 표 줄 형식 틀림 1: ' "$T/err")"
  [ "$errs" = 1 ] && [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] && alarmed "$G" 91 \
    && ok "R5 «${bad_row}» → ERROR 1줄 · 죽은 예약 + [급]" || bad "R5 «${bad_row}» rc=$rc errs=$errs calls=$(calls): $(cat "$T/out" "$T/err")"
done

# R6 단일 값 91 → exit 91 허용 · exit 92 죽은 예약
table "$G 91  # 단일 값"; dead "$G" 91; reset; ldc "$SCRIPT"; rc=$?
[ $rc -eq 0 ] && [ "$(cat "$T/out")" = "예약 $G exit=91 — 예외 표 허용(91)" ] && [ "$(calls)" = 0 ] \
  && ok "R6a 표 91 · exit 91 → 허용" || bad "R6a rc=$rc calls=$(calls): $(cat "$T/out" "$T/err")"
table "$G 91"; dead "$G" 92; reset; ldc "$SCRIPT"; rc=$?
alarmed "$G" 92 && ok "R6b 표 91 · exit 92 → 죽은 예약" || bad "R6b rc=$rc calls=$(calls): $(cat "$T/out" "$T/err")"

# ⓓ bin·kit 같은 내용
cmp -s "$BIN/ft-launchd-check.sh" "$KIT/ft-launchd-check.sh" && ok "ⓓ bin·kit cmp0" || bad "ⓓ bin·kit 내용 다름"

echo "FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS"
exit $((fail > 0))
