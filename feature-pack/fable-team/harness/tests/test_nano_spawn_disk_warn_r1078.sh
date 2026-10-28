#!/usr/bin/env bash
# test_nano_spawn_disk_warn_r1078.sh — r1078: ft-nano-spawn 의 r444 ⑤ 디스크 여유 검사(40Gi 하드 REJECT)를 r921 꼴 «WARN 1줄 + 진행» 으로 맞춘 카드의 시험.
#   계약(카드 계약↔시험 대응표 그대로):
#   ① 40Gi 아래 = WARN + 진행 · R1        ⓐ 25Gi → rc0 · WARN «25Gi < 40Gi» 1줄 · PASSED · REJECT 0
#   ② 측정 실패 = REJECT · R2             ⓑ1 FT_DISK_FREE_GIB=fail → rc1 + «측정 실패» + PASSED 0
#                                         ⓑ2 FT_DISK_FREE_GIB 없음 + PATH 앞 가짜 df(출력 0 · rc0) → rc1 + «측정 실패» + PASSED 0
#   ③ 1GiB 하한 = 문지기 REJECT · R3      ⓒ ft-resource-gate.sh check rc3(하한 아래) — 이 카드 손 0 · 값만 확인
#   ④ 워크트리 있음 = 검사 0 · R4         ⓓ WTDIR 실재 + 여유 0 → WARN 0 · REJECT 0 · PASSED
#   ⑤ 문턱 위 · 한시 값 · R5·R6           ⓔ 50Gi → WARN 0 · PASSED / FT_NANO_MIN_FREE_GI=10 · 25Gi → WARN 0 · PASSED
#   ⑥ bin·kit 같은 줄                    ⓕ 두 파일 블록 diff 0
#   변이 3(ⓜ1 WARN → 옛 REJECT exit 1 · ⓜ2 측정 실패도 WARN 진행 → ⓑ1·ⓑ2 FAIL · ⓜ3 빈 값을 0 으로 채움 → ⓑ2 FAIL)
# 블록 추출 실행 꼴(test_finished_cleanup_auto ⓗ 와 같다) — 실 워크트리·실 tmux·실 spawn 0 · 자기 재호출 0 · 임시 폴더만 쓴다.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }

BLK="$(awk '/^# r1078: r444 ⑤ 디스크 여유 검사/{f=1} f{print} f&&/^fi$/{exit}' "$BIN/ft-nano-spawn.sh")"
[ -n "$BLK" ] || { echo "FAIL 블록 추출 0 — ft-nano-spawn.sh 의 r1078 머리 주석을 찾지 못했다"; exit 1; }
# run_blk <WTDIR> <여유값(빈 = env 없음)> [PATH 앞 폴더] → OUT(2>&1)·RC
run_blk() {
  local wt="$1" free="$2" pre="${3:-}"
  if [ -n "$pre" ]; then OUT="$( WTDIR="$wt" ROOT="$T/root" PATH="$pre:$PATH" FT_DISK_FREE_GIB="$free" bash -c "$BLK"$'\n''echo PASSED' 2>&1 )"
  elif [ -n "$free" ]; then OUT="$( WTDIR="$wt" ROOT="$T/root" FT_DISK_FREE_GIB="$free" bash -c "$BLK"$'\n''echo PASSED' 2>&1 )"
  else OUT="$( env -u FT_DISK_FREE_GIB WTDIR="$wt" ROOT="$T/root" bash -c "$BLK"$'\n''echo PASSED' 2>&1 )"; fi
  RC=$?
}
mkdir -p "$T/root" "$T/wt" "$T/fakedf"

echo "== ⓐ 40Gi 아래 = WARN 1줄 + 진행 (R1)"
run_blk "$T/absent" 25
[ "$RC" = 0 ] && ok "ⓐ 여유 25Gi → rc0(진행)" || bad "ⓐ 25 rc=$RC [$OUT]"
has "$OUT" "WARN 디스크 여유 25Gi < 40Gi" "ⓐ WARN 1줄에 «25Gi < 40Gi»"
has "$OUT" "진행" "ⓐ WARN 줄에 «진행»(정지 아님)"
has "$OUT" "ft-resource-reclaim.sh" "ⓐ WARN 줄에 회수 권장(ft-resource-reclaim.sh)"
has "$OUT" "PASSED" "ⓐ 다음 줄 진행(PASSED)"
hasnt "$OUT" "REJECT" "ⓐ REJECT 0"
[ "$(printf '%s\n' "$OUT" | grep -c 'WARN 디스크 여유')" = 1 ] && ok "ⓐ WARN 은 정확히 1줄" || bad "ⓐ WARN 줄 수 $(printf '%s\n' "$OUT" | grep -c 'WARN 디스크 여유')"

echo "== ⓑ 측정 실패 = REJECT (R2)"
run_blk "$T/absent" fail
[ "$RC" = 1 ] && has "$OUT" "REJECT [HIL] 디스크 여유 측정 실패" "ⓑ1 FT_DISK_FREE_GIB=fail → rc1 + «측정 실패»" || bad "ⓑ1 rc=$RC [$OUT]"
hasnt "$OUT" "PASSED" "ⓑ1 PASSED 0(진행 안 함)"
hasnt "$OUT" "WARN" "ⓑ1 WARN 0(측정 실패는 WARN 아니라 REJECT)"
# ⓑ2 가짜 df — 출력 0 · rc0(«빈 값» 을 숫자로 채우면 통과해 버린다)
printf '#!/bin/sh\nexit 0\n' > "$T/fakedf/df"; chmod 755 "$T/fakedf/df"
run_blk "$T/absent" "" "$T/fakedf"
[ "$RC" = 1 ] && has "$OUT" "REJECT [HIL] 디스크 여유 측정 실패" "ⓑ2 가짜 df 빈 출력(rc0) → rc1 + «측정 실패»" || bad "ⓑ2 rc=$RC [$OUT]"
hasnt "$OUT" "PASSED" "ⓑ2 PASSED 0"

echo "== ⓒ 1GiB 하한 = 문지기 REJECT (R3 · 이 카드 손 0)"
mkdir -p "$T/df1024"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 500000 1%% /System/Volumes/Data"\n' > "$T/df1024/df"
chmod 755 "$T/df1024/df"
for s in sysctl memory_pressure vm_stat pgrep; do printf '#!/bin/sh\nexit 1\n' > "$T/df1024/$s"; chmod 755 "$T/df1024/$s"; done
printf '#!/bin/sh\ncase "$2" in vm.swapusage) echo "total = 14336.00M  used = 6133.00M  free = 1000.00M";; kern.memorystatus_vm_pressure_level) echo 1;; *) exit 1;; esac\n' > "$T/df1024/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 51%%"\n' > "$T/df1024/memory_pressure"
printf '#!/bin/sh\necho "Swapouts:                          1."\n' > "$T/df1024/vm_stat"
chmod 755 "$T/df1024"/*
mkdir -p "$T/resroot/.fable-team/state"; now="$(date +%s)"
printf '%s\t6133\t51\t1\t2303978\n%s\t6133\t51\t1\t2303978\n' "$((now-60))" "$now" > "$T/resroot/.fable-team/state/pressure.tsv"
OUT="$( env -u FT_DISK_MIN_GIB -u FT_DISK_HARD_MIN_MIB -u FT_SWAP_HARD_MIB -u FT_MEM_FREE_MIN_PCT -u FT_PRESSURE_MAX -u FT_AGENT_MAX \
  FT_RES_ROOT="$T/resroot" PATH="$T/df1024:$PATH" bash "$BIN/ft-resource-gate.sh" check 2>&1 )"; RC=$?
[ "$RC" = 3 ] && ok "ⓒ 여유 488MiB < 1GiB 하한 → 문지기 rc3(REJECT 유지)" || bad "ⓒ gate rc=$RC [$OUT]"
has "$OUT" "disk" "ⓒ 문지기 REJECT 사유가 disk"

echo "== ⓓ 워크트리 이미 있음 = 검사 0 (R4)"
run_blk "$T/wt" 0
[ "$RC" = 0 ] && ok "ⓓ WTDIR 실재 → rc0" || bad "ⓓ rc=$RC [$OUT]"
hasnt "$OUT" "WARN" "ⓓ WARN 0"
hasnt "$OUT" "REJECT" "ⓓ REJECT 0"
has "$OUT" "PASSED" "ⓓ PASSED(검사 없이 다음 줄)"

echo "== ⓔ 문턱 위 · 한시 값 (R5·R6)"
run_blk "$T/absent" 50
[ "$RC" = 0 ] && hasnt "$OUT" "WARN" "ⓔ 여유 50Gi → WARN 0 · 진행" || bad "ⓔ 50 rc=$RC [$OUT]"
has "$OUT" "PASSED" "ⓔ 50Gi PASSED"
OUT="$( WTDIR="$T/absent" ROOT="$T/root" FT_DISK_FREE_GIB=25 FT_NANO_MIN_FREE_GI=10 bash -c "$BLK"$'\n''echo PASSED' 2>&1 )"; RC=$?
[ "$RC" = 0 ] && hasnt "$OUT" "WARN" "ⓔ FT_NANO_MIN_FREE_GI=10 · 25Gi → WARN 0(한시 값 팀 그대로)" || bad "ⓔ min10 rc=$RC [$OUT]"
has "$OUT" "PASSED" "ⓔ min10 PASSED"

echo "== ⓕ bin·kit 같은 줄"
KBLK="$(awk '/^# r1078: r444 ⑤ 디스크 여유 검사/{f=1} f{print} f&&/^fi$/{exit}' "$KIT/ft-nano-spawn.sh")"
[ -n "$KBLK" ] && [ "$BLK" = "$KBLK" ] && ok "ⓕ bin·kit 블록 글자 그대로 같음" || bad "ⓕ kit 블록 다름 ← ${KBLK:0:200}"
cmp -s "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh" && ok "ⓕ 두 파일 통째 cmp0" || bad "ⓕ 두 파일 다름"

echo "== 변이 3 — 「깨진 판에서 이 시험이 FAIL 하는가」"
M="$T/mut"; mkdir -p "$M"
# ⓜ1 WARN → 옛 REJECT exit 1
printf '%s\n' "$BLK" | sed 's#^  \[ "$_free" -ge .*#  [ "$_free" -ge "${FT_NANO_MIN_FREE_GI:-40}" ] || { echo "REJECT [HIL] 디스크 여유 ${_free}Gi < ${FT_NANO_MIN_FREE_GI:-40}Gi — spawn 0"; exit 1; }#' > "$M/m1.blk"
M1="$(cat "$M/m1.blk")"
[ "$M1" != "$BLK" ] || bad "ⓜ1 변이가 안 걸림(sed 무효)"
OUT="$( WTDIR="$T/absent" ROOT="$T/root" FT_DISK_FREE_GIB=25 bash -c "$M1"$'\n''echo PASSED' 2>&1 )"; RC=$?
{ [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q 'REJECT'; } && ok "ⓜ1(WARN→옛 REJECT) → 25Gi 에 rc1 = ⓐ 단언 FAIL 로 잡힌다" || bad "ⓜ1 rc=$RC [$OUT]"
# ⓜ2 측정 실패도 WARN 으로 진행
printf '%s\n' "$BLK" | sed 's#^  case "$_free" in .*#  case "$_free" in \x27\x27|*[!0-9]*) _free=0;; esac#' > "$M/m2.blk"
M2="$(cat "$M/m2.blk")"
[ "$M2" != "$BLK" ] || bad "ⓜ2 변이가 안 걸림(sed 무효)"
OUT="$( WTDIR="$T/absent" ROOT="$T/root" FT_DISK_FREE_GIB=fail bash -c "$M2"$'\n''echo PASSED' 2>&1 )"; RC=$?
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q PASSED; } && ok "ⓜ2(측정 실패도 진행) → fail 값에 rc0 = ⓑ1 단언 FAIL 로 잡힌다" || bad "ⓜ2 rc=$RC [$OUT]"
OUT="$( WTDIR="$T/absent" ROOT="$T/root" PATH="$T/fakedf:$PATH" env -u FT_DISK_FREE_GIB bash -c "$M2"$'\n''echo PASSED' 2>&1 )"; RC=$?
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q PASSED; } && ok "ⓜ2(빈 값을 0 으로 채움) → 가짜 df 에 rc0 = ⓑ2 단언 FAIL 로 잡힌다" || bad "ⓜ2b rc=$RC [$OUT]"

echo "== bash -n"
for f in "$BIN/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh"; do bash -n "$f" && ok "bash -n $f" || bad "bash -n $f"; done

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED ($fail)"; exit "$fail"
