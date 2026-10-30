#!/bin/bash
# test_launchd_alarm_owner_r1158.sh — r1158: [급] 경보 수신 = 장치 주인(harness 팀) 명부의 _master · 틱을 돈 팀 명부가 아니다
# R1 FT_LDC_SEATS=seats.json(_master V) · seats-harness.json(_master H) · 꺼진 예약 1 → [급] to=H 1통(옛 판 V)
# R2 FT_LDC_SEATS=seats-ops.json(_master O) · 죽은 예약 1 → [급] to=H 1통(옛 판 O)
# R3 FT_LDC_NOTIFY=X → to=X
# R4 seats-harness.json 파일 없음 → to=FT_LDC_SEATS 의 _master
# R5 seats-harness.json 있음 · _master 빔 → rc3 · ERROR 1줄(주인 명부 경로) · 쪽지 0 · 표식 0
# ⓓ bin·kit 같은 내용(cmp0)
# 변이 = FT_LDC_TEST_BIN=<옛 판> 으로 같은 시험 → R1 FAIL 이어야 한다. 실 launchctl·mbox·HOME 0 — 전부 가짜. 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
KIT="$HERE/../../harness/kit/fable-team/bin"
SCRIPT="${FT_LDC_TEST_BIN:-$BIN/ft-launchd-check.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

R="$T/root"; FT="$R/.fable-team"
mkdir -p "$T/bin" "$T/rec" "$FT"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.calls"\n' "$T" > "$T/mbox.sh"
cat > "$T/bin/launchctl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  print-disabled) cat "$T/disabled.txt";;
  list) cat "$T/list.txt";;
  print) cat "$T/print.\${2##*/}" 2>/dev/null;;
esac
exit 0
EOF
chmod +x "$T/mbox.sh" "$T/bin/launchctl"
printf '{"_master": "V#1"}\n' > "$FT/seats.json"
printf '{"_master": "O#1"}\n' > "$FT/seats-ops.json"
owner_ok() { printf '{"_master": "H#1"}\n' > "$FT/seats-harness.json"; }
printf 'com.byz.ft-x\n' > "$T/expected.txt"
printf 'gui/501/com.airag.x = {\n\targuments = {\n\t\t/bin/bash\n\t\t%s\n\t}\n}\n' "$T/absent.sh" > "$T/print.com.airag.x"
off_one()  { printf 'disabled services = {\n\t"com.byz.ft-x" => disabled\n}\n' > "$T/disabled.txt"; : > "$T/list.txt"; }
dead_one() { : > "$T/disabled.txt"; printf 'PID\tStatus\tLabel\n-\t127\tcom.airag.x\n' > "$T/list.txt"; }
calls() { [ -f "$T/mbox.calls" ] && wc -l < "$T/mbox.calls" | tr -d ' ' || echo 0; }
reset() { rm -f "$T/mbox.calls"; rm -rf "$T/state"; }
# 임시 ROOT 에서 돈다(git 밖 → ROOT=cwd) · FT_LDC_OWNER_SEATS 는 안 준다(기본 <ROOT>/.fable-team/seats-harness.json 을 본다)
ldc() {
  ( cd "$R" && GIT_CEILING_DIRECTORIES="$T" FT_LDC_EXPECTED="$T/expected.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state" \
      FT_LDC_NOW=2026-10-30 FT_LDC_MBOX="$T/mbox.sh" FT_LDC_LAUNCHCTL="$T/bin/launchctl" bash "$SCRIPT" 2>&1 )
}
to_is() { [ "$(calls)" = 1 ] && grep -q "^send $1 ft-launchd-check \[급\] " "$T/mbox.calls"; }

# R1 메인 틱 명부(V) · 꺼진 예약 → H
owner_ok; off_one; reset; OUT="$(FT_LDC_SEATS="$FT/seats.json" ldc)"; rc=$?
[ $rc -eq 0 ] && to_is 'H#1' && ok "R1 틱 명부 seats.json(V) · 꺼진 예약 → [급] to=H 1통" || bad "R1 rc=$rc calls=$(calls) $(cat "$T/mbox.calls" 2>/dev/null): $OUT"

# R2 팀 틱 명부(O) · 죽은 예약 → H
owner_ok; dead_one; reset; OUT="$(FT_LDC_SEATS="$FT/seats-ops.json" ldc)"; rc=$?
[ $rc -eq 0 ] && to_is 'H#1' && ok "R2 틱 명부 seats-ops.json(O) · 죽은 예약 → [급] to=H 1통" || bad "R2 rc=$rc calls=$(calls) $(cat "$T/mbox.calls" 2>/dev/null): $OUT"

# R3 덮기 그대로
owner_ok; off_one; reset; OUT="$(FT_LDC_NOTIFY='X#9' FT_LDC_SEATS="$FT/seats.json" ldc)"; rc=$?
[ $rc -eq 0 ] && to_is 'X#9' && ok "R3 FT_LDC_NOTIFY=X → to=X" || bad "R3 rc=$rc calls=$(calls) $(cat "$T/mbox.calls" 2>/dev/null): $OUT"

# R4 주인 명부 파일 없음(팀 1개 설치) → 틱 명부 _master
rm -f "$FT/seats-harness.json"; dead_one; reset; OUT="$(FT_LDC_SEATS="$FT/seats-ops.json" ldc)"; rc=$?
[ $rc -eq 0 ] && to_is 'O#1' && ok "R4 seats-harness.json 없음 → to=틱 명부 _master(O)" || bad "R4 rc=$rc calls=$(calls) $(cat "$T/mbox.calls" 2>/dev/null): $OUT"

# R5 주인 명부 있음 · _master 빔 → rc3 · ERROR 1줄 · 쪽지 0 · 표식 0 (틱 명부로 후퇴 0)
printf '{"_master": ""}\n' > "$FT/seats-harness.json"; off_one; reset; OUT="$(FT_LDC_SEATS="$FT/seats.json" ldc)"; rc=$?
errs="$(printf '%s\n' "$OUT" | grep -c '^ERROR ft-launchd-check: 수신 좌석 없음')"
marks="$(find "$T/state" -type f 2>/dev/null | wc -l | tr -d ' ')"
[ $rc -eq 3 ] && [ "$(calls)" = 0 ] && [ "$errs" = 1 ] && [ "$marks" = 0 ] && printf '%s\n' "$OUT" | grep -q "seats-harness.json" \
  && ok "R5 _master 빔 → rc3 · ERROR 1줄(주인 명부 경로) · 쪽지 0 · 표식 0" || bad "R5 rc=$rc calls=$(calls) errs=$errs marks=$marks: $OUT"

# ⓓ bin·kit 같은 내용
cmp -s "$BIN/ft-launchd-check.sh" "$KIT/ft-launchd-check.sh" && ok "ⓓ bin·kit cmp0" || bad "ⓓ bin·kit 내용 다름"

echo "FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS"
exit $((fail > 0))
