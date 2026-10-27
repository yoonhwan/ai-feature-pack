#!/usr/bin/env bash
# test_stall_scan_lead_heartbeat_r1001.sh — r1001 팀장 멈춤 = 팀 단위 심박 디바운스.
#   본문 = tests/scripts/test_stall_scan_lead_heartbeat_r1001.py (ⓐ~ⓗ + 반례) · 기존 stall 시험 회귀(ⓕ)
#   + 변이 2종(«심박 무시(항상 경보)» · «팀당 1통 → 좌석마다» → 그 시험 FAIL) + kit 짝 cmp0.
# 격리: 합성 jsonl · 가짜 명부·tmux·mbox·seat-status(임시 폴더) — 실 좌석 깨우기·ring·쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
run_py() { (cd "$SC" && R1001_BIN="$1" pytest -q -p no:cacheprovider "$2" ${3:+-k "$3"} >"$T/py.log" 2>&1); }

run_py "$KIT" test_stall_scan_lead_heartbeat_r1001.py; ck "ⓐ~ⓝ $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?

# ⓕ — 기존 stall 시험은 기대 변경 0 (C3)
for t in test_ft_stall_scan.py test_ft_stall_scan_off_roster.py test_ft_stall_scan_wake_r638.py test_ft_penalty.py; do
  run_py "$KIT" "$t"; ck "ⓕ 회귀 $t $(grep -Eo '[0-9]+ passed' "$T/py.log")" $?
done

# 변이 — 사본 bin 의 한 곳을 무력화하면 그 시험이 FAIL 해야 한다
cp -Rp "$KIT" "$T/bin"
mutate() {  # $1 이름 $2 파일 $3 원문(고정 문자열) $4 바꿀 글 $5 -k 시험
  cp -p "$KIT/$2" "$T/bin/$2"
  python3 - "$T/bin/$2" "$3" "$4" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  run_py "$T/bin" test_stall_scan_lead_heartbeat_r1001.py "$5"; [ $? -ne 0 ]; ck "변이 $1 → $5 FAIL" $?
  cp -p "$KIT/$2" "$T/bin/$2"
}
mutate "심박 무시(항상 경보)" ft_stall_detect.py '    return age > lead_heartbeat_min(), age, False' '    return True, age, False' test_c1a
mutate "env 무시" ft_stall_detect.py '    return age > lead_heartbeat_min(), age, False' '    return age > 15.0, age, False' test_i_env_threshold_is_read
mutate "수신자 미검증" ft_stall_detect.py '            if r.get("from") not in masters or r.get("to") not in recipients:' '            if r.get("from") not in masters:' test_j_heartbeat_to_nano_is_not_a_heartbeat
mutate "팀당 1통 → 좌석마다" ft_stall_scan.py '                    out.append(dict(kind="f",' '                    out.extend(cands)
                    out.append(dict(kind="f",' test_c2e2

# C6 — 심박 판정은 detect 쪽(scan 이 mailbox 를 직접 파싱하지 않는다) · 200줄 상한 가드
grep -q '^def lead_heartbeat(' "$KIT/ft_stall_detect.py"; ck "C6 심박 판정 함수 = ft_stall_detect" $?
! grep -q 'mailbox.jsonl' "$KIT/ft_stall_scan.py"; ck "C6 scan 은 mailbox 직접 파싱 0" $?
nc="$(wc -l <"$KIT/ft_stall_scan.py")"; [ "$nc" -le 352 ]; ck "C6 ft_stall_scan.py ${nc}줄 ≤ 352(기준판)" $?

# 짝 사본(harness/bin ↔ kit) 바이트·실행 비트 동일
for n in ft_stall_scan.py ft_stall_detect.py ft_stall_seats.py ft_stall_state.py ft-stall-scan.sh ft_penalty.py; do
  cmp -s "$TRK/$n" "$KIT/$n" && [ "$(stat -f %Lp "$TRK/$n")" = "$(stat -f %Lp "$KIT/$n")" ]; ck "짝 사본 $n" $?
done
echo "FAIL=$fail"; [ "$fail" = 0 ]
