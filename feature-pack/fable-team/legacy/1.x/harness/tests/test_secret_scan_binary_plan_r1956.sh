#!/usr/bin/env bash
# test_secret_scan_binary_plan_r1956.sh — r1956: 기본 계획 목록(/tmp/h* 대용)의 이진 파일(jpg 등)은 계획 파일 아님 → 판정기에 안 넘김
#   · SCAN 줄 끝 « skipped_binary=N»(0 이면 생략) · --plans 명시 목록은 손 0 · 스캔 첫 줄 «RUN <ISO 시각> root=… seats=…»
#   격리: 임시 HOME·임시 /tmp 대용(FT_SECRET_SCAN_TMP)·임시 SCAN_HERE(대역 판정기)·가짜 mbox · 실 세션 기록·실 /tmp/h*·실 우편함 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1956_BIN:-$HERE/../bin}"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
t0=$(date +%s)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
B="$T/bin"; mkdir -p "$B" "$T/home" "$T/root/design" "$T/tmp" "$T/plans"
cp -p "$BIN/ft-secret-scan.sh" "$BIN"/ft_secret_*.py "$BIN/ft-harness-root.sh" "$B/" 2>/dev/null
cat > "$B/ft_secret_judge.py" <<'PY'
import sys   # 대역 판정기 — 진짜처럼 UTF-8 로 못 읽으면 rc2 · «RC2» 글자가 있어도 rc2 · 나머지 ok
try:
    t = open(sys.argv[2], "rb").read().decode("utf-8")
except UnicodeDecodeError:
    sys.exit(2)
if "RC2" in t:
    sys.exit(2)
print("ok")
PY
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/mail.log"\nexit 0\n' "$T" > "$T/mbox.sh"
printf '{"_hil_route":"fx-desk#0"}\n' > "$T/seats.json"
printf '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01' > "$T/jpg"   # JPEG 머리(NUL·UTF-8 아님)
scan() {  # scan [--plans <경로>…] — 한 회차
  rm -rf "$T/home/.fable-team" "$T/mail.log"
  out="$(HOME="$T/home" FT_SECRET_SCAN_ROOT="$T/root" FT_SECRET_SCAN_TMP="$T/tmp" FT_MBOX_SH="$T/mbox.sh" \
         FT_SEATS_JSON="$T/seats.json" timeout 60 bash "$B/ft-secret-scan.sh" "$@" 2>&1)"; rc=$?
}
# ① 기본 목록 = JPEG 1 + 깨끗한 텍스트 계획 1 → rc0 · skipped_binary=1 · judge_unknown=0
cp "$T/jpg" "$T/tmp/hotel_reply.jpg"; printf 'echo hello\n' > "$T/tmp/h-plan.sh"
scan
ck "① 기본 목록 JPEG 뺌 → rc=$rc · skipped_binary=1 · judge_unknown=0" \
  "$([ "$rc" = 0 ] && grep -q 'SCAN read=1 skipped=0 new=0 judge_unknown=0 skipped_binary=1$' <<<"$out" && ! grep -q '판정 불가' <<<"$out" && echo 0 || echo 1)"
# ④ 출력 첫 줄 = RUN <ISO 시각> root=<ROOT> seats=<SCAN_SEATS>
first="$(head -n1 <<<"$out")"
ck "④ 첫 줄 RUN ISO 시각·root·seats :: $first" \
  "$(grep -Eq "^RUN [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[^ ]* root=$T/root seats=$T/seats.json$" <<<"$first" && echo 0 || echo 1)"
# ①' 이진이 없으면 skipped_binary 칸 생략
rm -f "$T/tmp/hotel_reply.jpg"; scan
ck "①' 이진 0 → skipped_binary 칸 없음 · rc=$rc" \
  "$([ "$rc" = 0 ] && grep -q 'judge_unknown=0$' <<<"$out" && ! grep -q 'skipped_binary' <<<"$out" && echo 0 || echo 1)"
# ② 텍스트 계획인데 판정기 rc2 → 지금처럼 판정 불가 rc3(회귀)
printf 'RC2 plan\n' > "$T/tmp/h-bad.sh"; scan
ck "② 텍스트 계획 rc2 → rc=$rc · judge_unknown=1" \
  "$([ "$rc" = 3 ] && grep -q '판정 불가 .*h-bad.sh 판정기 rc=2' <<<"$out" && grep -q 'judge_unknown=1$' <<<"$out" && echo 0 || echo 1)"
rm -f "$T/tmp/h-bad.sh"
# ③ --plans 로 JPEG 를 직접 주면 지금처럼 판정기에 넘김 → rc3(명시 목록 손 0)
scan --plans "$T/jpg"
ck "③ --plans JPEG → 판정기로 · rc=$rc · skipped_binary 칸 없음" \
  "$([ "$rc" = 3 ] && grep -q "판정 불가 $T/jpg 판정기 rc=2" <<<"$out" && ! grep -q 'skipped_binary' <<<"$out" && echo 0 || echo 1)"
# ⑤ --report 는 1줄 그대로(RUN 줄 0)
scan; out="$(HOME="$T/home" FT_SECRET_SCAN_ROOT="$T/root" FT_SEATS_JSON="$T/seats.json" FT_MBOX_SH="$T/mbox.sh" bash "$B/ft-secret-scan.sh" --report 2>&1)"; rc=$?
ck "⑤ --report 1줄 · RUN 0 · rc=$rc" "$([ "$rc" = 0 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && ! grep -q '^RUN' <<<"$out" && echo 0 || echo 1)"
echo "합계 $(( $(date +%s) - t0 ))초 · FAIL=$fail"
exit $(( fail > 0 ))
