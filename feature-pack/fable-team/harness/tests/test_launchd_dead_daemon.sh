#!/bin/bash
# test_launchd_dead_daemon.sh — R612: 켜져 있는데 마지막 종료가 실패(PID «-» · exit≠0)인 예약 = «죽은 예약»
# ⓐ(실패 시험 먼저) exit 127 · 대상 스크립트 없음 → stdout «죽은 예약 … — 대상 없음: <경로>» + master 앞 [급] 1통
# ⓑ 같은 날 두 번째 틱 → 0통(표식)
# ⓒ PID 있음(exit 0·255) → 0줄 · 0통
# ⓓ PID «-» · exit 1 · 대상 파일 있음 → «죽은 예약 … exit=1(대상 있음…)» 1줄 + [급] 1통 · 같은 날 1통
# ⓔ 접두 밖 Label(com.apple.x) → 0줄 · 0통 · 기존 disabled 판정(내림 중·기록 없음) 그대로
# 실 launchctl·mbox·HOME 0 — 전부 가짜. 시험 입력은 GIT_* 없이.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541
set -uo pipefail
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY; do unset "$v"; done
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
SCRIPT="${FT_LDC_TEST_BIN:-$BIN/ft-launchd-check.sh}"   # 전(base) 대조 = 옛 판 경로를 넣어 같은 시험을 돌린다
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

mkdir -p "$T/bin" "$T/state" "$T/rec" "$T/scripts"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/mbox.calls"\n' "$T" > "$T/mbox.sh"
# 가짜 launchctl — print-disabled/list/print 모두 파일에서 읽는다(라벨별 print.<Label>)
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
: > "$T/disabled.txt"; : > "$T/list.txt"
printf 'com.byz.ft-x\n' > "$T/expected.txt"
calls() { [ -f "$T/mbox.calls" ] && wc -l < "$T/mbox.calls" | tr -d ' ' || echo 0; }
reset() { rm -f "$T/mbox.calls"; rm -rf "$T/state/lc"; }
ldc() {
  FT_LDC_EXPECTED="$T/expected.txt" FT_LDC_RECORDS="$T/rec" FT_LDC_STATE="$T/state/lc" FT_LDC_NOW=2026-10-21 \
    FT_LDC_MBOX="$T/mbox.sh" FT_LDC_NOTIFY="hmaster#t" FT_LDC_LAUNCHCTL="$T/bin/launchctl" \
    bash "$SCRIPT" 2>&1
}
# 라벨 print 출력 = arguments 블록(인터프리터 + 스크립트 경로)
mkprint() { printf 'gui/501/%s = {\n\tprogram = /bin/bash\n\targuments = {\n\t\t/bin/bash\n\t\t%s\n\t}\n}\n' "$1" "$2" > "$T/print.$1"; }
missing="$T/scripts/absent-ft-goal-tick.sh"
present="$T/scripts/present.sh"; printf '#!/bin/bash\necho hi\n' > "$present"; chmod +x "$present"

# ⓐ 실패 시험 먼저 — 지금 판이면 알림 0 (전 = FAIL 이어야 한다)
printf 'PID\tStatus\tLabel\n-\t127\tcom.airag.x\n' > "$T/list.txt"; mkprint com.airag.x "$missing"
reset; OUT="$(ldc)"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 1 ] && echo "$OUT" | grep -q "죽은 예약 com.airag.x exit=127 — 대상 없음: $missing" \
  && grep -q '^send hmaster#t ft-launchd-check \[급\] 예약 com.airag.x' "$T/mbox.calls" \
  && ok "ⓐ exit 127 · 대상 없음 → «죽은 예약 … — 대상 없음: <경로>» 1줄 + [급] 1통 · rc 0" \
  || bad "ⓐ rc=$rc calls=$(calls): $OUT"

# ⓑ 같은 날 두 번째 → 1통 유지
ldc >/dev/null; [ "$(calls)" = 1 ] && ok "ⓑ 같은 날 두 번째 틱 → 1통 유지(표식)" || bad "ⓑ 중복 calls=$(calls)"

# ⓒ PID 있음 = 지금 도는 중 → 0줄 · 0통 (exit 0 · 255 · 음수)
printf 'PID\tStatus\tLabel\n510\t0\tcom.byz.ft-x\n777\t255\tcom.airag.y\n888\t-9\tcom.hermes.z\n' > "$T/list.txt"
reset; OUT="$(ldc)"; [ "$(calls)" = 0 ] && [ -z "$OUT" ] && ok "ⓒ PID 있음(0·255·-9) → 0줄 · 0통" || bad "ⓒ calls=$(calls): $OUT"

# ⓓ PID «-» · exit 1 · 대상 파일 있음 → 1줄 + [급] 1통 · 같은 날 1통
printf 'PID\tStatus\tLabel\n-\t1\tcom.hermes.y\n' > "$T/list.txt"; mkprint com.hermes.y "$present"
reset; OUT="$(ldc)"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 1 ] && echo "$OUT" | grep -q "죽은 예약 com.hermes.y exit=1(대상 있음: $present)" \
  && ok "ⓓ exit 1 · 대상 있음 → «죽은 예약 … exit=1(대상 있음…)» 1줄 + [급] 1통" || bad "ⓓ rc=$rc calls=$(calls): $OUT"
ldc >/dev/null; [ "$(calls)" = 1 ] && ok "ⓓ 같은 날 두 번째 → 1통 유지" || bad "ⓓ 중복 calls=$(calls)"

# ⓔ 접두 밖 → 0 · 같은 list 안의 접두 안 행만 본다
printf 'PID\tStatus\tLabel\n-\t78\tcom.apple.x\n-\t127\tcom.airag.x\n' > "$T/list.txt"; mkprint com.apple.x "$missing"
reset; OUT="$(ldc)"
[ "$(calls)" = 1 ] && ! echo "$OUT" | grep -q 'com.apple.x' && echo "$OUT" | grep -q 'com.airag.x' \
  && ok "ⓔ 접두 밖 com.apple.x → 0 · 접두 안 1줄" || bad "ⓔ calls=$(calls): $OUT"

# ⓔ2 기존 disabled 판정 무변경 — 기록 없음 → [급] · 네 줄 기록 → «내림 중» 0통
: > "$T/list.txt"
printf 'com.byz.ft-x\n' > "$T/expected.txt"
printf 'disabled services = {\n\t"com.byz.ft-x" => disabled\n}\n' > "$T/disabled.txt"
reset; OUT="$(ldc)"; [ "$(calls)" = 1 ] && echo "$OUT" | grep -q '꺼짐 — com.byz.ft-x disabled · 내림 기록 없음' \
  && ok "ⓔ2 disabled + 기록 없음 → [급] 1통(기존 규칙 그대로)" || bad "ⓔ2 calls=$(calls): $OUT"
printf '사유: 판정 1\n판정: 판정 1\n다시 올릴 조건: 조건\n누가: master\n' > "$T/rec/com.byz.ft-x.md"
reset; OUT="$(ldc)"; [ "$(calls)" = 0 ] && echo "$OUT" | grep -q '내림 중(판정 1)' && ok "ⓔ2 기록 있음 → 0통 + «내림 중»" || bad "ⓔ2 기록 calls=$(calls): $OUT"
: > "$T/disabled.txt"

# ⓔ3 FT_LDC_DEAD=0 → 죽은 예약 점검 끔
printf 'PID\tStatus\tLabel\n-\t127\tcom.airag.x\n' > "$T/list.txt"
reset; OUT="$(FT_LDC_DEAD=0 ldc)"; [ "$(calls)" = 0 ] && [ -z "$OUT" ] && ok "ⓔ3 FT_LDC_DEAD=0 → 0줄 · 0통" || bad "ⓔ3 calls=$(calls): $OUT"

# ⓔ4 기대 예약표(EXPECTED)가 없어도 죽은 예약은 본다 — 실사건(airag 팀 표에 airag 줄 0) 경로
printf 'PID\tStatus\tLabel\n-\t127\tcom.airag.x\n' > "$T/list.txt"
reset; OUT="$(FT_LDC_EXPECTED="$T/no-such-expected.txt" ldc)"; rc=$?
[ $rc -eq 0 ] && [ "$(calls)" = 1 ] && echo "$OUT" | grep -q '죽은 예약 com.airag.x exit=127' \
  && ok "ⓔ4 EXPECTED 없음 → 죽은 예약은 그대로 1통 · rc 0" || bad "ⓔ4 rc=$rc calls=$(calls): $OUT"

echo "FAIL=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS"
exit $((fail > 0))
