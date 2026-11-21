#!/usr/bin/env bash
# _r2380_stall_lib.sh — r2380 정체 감시 칸 시험들이 같이 쓰는 도우미(하드 룰 22: 파일마다 70초).
#   부르는 쪽이 HERE·KIT·SC·PACK·T·fail·R2380_T0 을 정하고 source 한다.
set -uo pipefail
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-R2380_T0))초"; R2380_T0=$SECONDS; }
run_py() {  # $1=bin $2=시험 파일 [$3=-k] → rc · 출력은 $T/py.log
  (ulimit -u 2000; cd "$SC" && R2380_BIN="$1" R2380_BASE_BIN="${BASE:-}" timeout 70 python3.11 -m pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1)
}
r2380_base() {  # 기준판(팩 origin/main) bin 폴더 → $BASE (없으면 빈 문자열)
  mkdir -p "$T/base"
  git -C "$PACK" archive origin/main feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin 2>/dev/null | tar -x -C "$T/base" 2>/dev/null
  BASE="$T/base/feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin"
  [ -f "$BASE/ft_stall_scan.py" ] || BASE=""
}
