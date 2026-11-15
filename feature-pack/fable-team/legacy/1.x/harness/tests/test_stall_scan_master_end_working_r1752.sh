#!/usr/bin/env bash
# test_stall_scan_master_end_working_r1752.sh — r1752 stall-scan 은 WORKING 팀장의 «마지막으로 끝낸 턴»(master_end)도 남긴다.
#   본문 = tests/scripts/test_stall_scan_master_end_working_r1752.py (반례 ①~④) + ⑤ 회귀(기존 stall·penalty 시험)
#   + 변이 2종(사본 bin 치환 → 그 시험 FAIL · 원본으로 같은 사례 PASS 대조) + bin·kit 짝 cmp0.
# 격리: 가짜 명부·tmux·mbox·seat-status(임시 폴더) · FT_NOW 고정 · 임시 PENALTY_STOP — 실 좌석·실 페널티 0 · sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_py() { (cd "$SC" && R1752_BIN="$1" pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1); }
PY=test_stall_scan_master_end_working_r1752.py

run_py "$KIT" "$PY"; rc=$?; ck "①~④ $(grep -Eo '[0-9]+ (passed|failed)' "$T/py.log" | tr '\n' ' ')" $rc
echo "단계 반례 $((SECONDS - t0))초"

# ⑤ — 기존 stall·penalty 시험은 기대 변경 0 (A3)
for t in test_ft_stall_scan.py test_ft_penalty.py; do
  run_py "$KIT" "$t"; rc=$?; ck "⑤ 회귀 $t $(grep -Eo '[0-9]+ (passed|failed)' "$T/py.log" | tr '\n' ' ')" $rc
done
echo "단계 회귀 $((SECONDS - t0))초"

# 변이 — 사본 bin 한 곳을 바꾸면 그 시험 FAIL · 원본으로 같은 사례는 PASS(반대 결과 대조)
cp -Rp "$KIT" "$T/bin"
ORIG='per_team[t["team"]]["master_end"] = end_m if st_m in ("IDLE", "WORKING") else None'
mutate() {  # $1 이름 $2 바꿀 글 $3 -k 시험
  cp -p "$KIT/ft_stall_scan.py" "$T/bin/ft_stall_scan.py"
  python3 - "$T/bin/ft_stall_scan.py" "$ORIG" "$2" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" "$PY" "$3"; [ $? -ne 0 ]; ck "변이 $1 → $3 FAIL" $?
  run_py "$KIT" "$PY" "$3"; ck "대조 원본 → $3 PASS" $?
  cp -p "$KIT/ft_stall_scan.py" "$T/bin/ft_stall_scan.py"
}
mutate "M1 WORKING 칸 지움(기준판 꼴)" 'per_team[t["team"]]["master_end"] = end_m if st_m == "IDLE" else None' test_1
mutate "M2 UNKNOWN 도 end 남김" 'per_team[t["team"]]["master_end"] = end_m if st_m in ("IDLE", "WORKING", "UNKNOWN") else None' "test_4b and UNKNOWN"
echo "단계 변이 $((SECONDS - t0))초"

# A3 — resume 판정 코드는 손 0(조건 줄 그대로)
grep -qF 'if end is None or float(end) <= float(d.get("since", 0)):' "$KIT/ft_penalty.py"; ck "A3 ft_penalty resume 조건 그대로" $?

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일
for n in ft_stall_scan.py ft_penalty.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
echo "단계 합계 $((SECONDS - t0))초"
echo "FAIL=$fail"; [ "$fail" = 0 ]
