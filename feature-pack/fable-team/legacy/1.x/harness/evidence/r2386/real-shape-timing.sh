#!/usr/bin/env bash
# real-shape-timing.sh — r2386 증거: «실사건 꼴»(키트 bin 전체 = 이 판 실측 파일 수)에서 새 판·기준판 각 1회 초를 잰다.
#   세계 = mktemp 리포(키트 bin 사본 · 커밋 방금 → DIFF 0) + 라이브 설치 꼴 사본 · 실 라이브·네트워크 0
set -uo pipefail
H="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"; SRC="$H/kit/fable-team/bin"; KP=kit/bin
SUT="${1:-$SRC/ft-live-bin-drift-check.sh}"; OLD="$H/tests/fixtures/drift_check_pre_r2386.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/$KP" "$T/live"; cp -p "$SRC"/* "$T/repo/$KP/"; cp -p "$SRC"/* "$T/live/"
git init -q -b main "$T/repo"; git -C "$T/repo" add -A
GIT_COMMITTER_DATE="$(($(date +%s) - 7200)) +0000" git -c user.email=t@t -c user.name=t -C "$T/repo" commit -q -m kit
n="$(git -C "$T/repo" ls-tree main "$KP/" | wc -l | tr -d ' ')"; m="$(ls "$T/live" | wc -l | tr -d ' ')"
echo "판 크기 = ls-tree ${n}행 · 라이브 ${m}파일 · load $(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')"
for s in "$SUT" "$OLD"; do
  t0="$(python3 -c 'import time;print("%.3f"%time.time())')"
  o="$(bash "$s" --bin "$T/live" --repo "$T/repo" --ref main --path "$KP" 2>&1)"; rc=$?
  t1="$(python3 -c 'import time;print("%.3f"%time.time())')"
  printf '%s → %s초 rc=%s · %s\n' "$(basename "$s" .sh)/$( [ "$s" = "$SUT" ] && echo '새 판' || echo '기준판')" \
    "$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f", b-a}')" "$rc" "$(printf '%s' "$o" | head -1)"
done
