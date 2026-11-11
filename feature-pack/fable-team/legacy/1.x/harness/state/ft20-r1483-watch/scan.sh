#!/usr/bin/env bash
# ft20 5분 점검 (오빠 11-11 «5분에 한번 전체 프로그래스와 각 팀 죽은 좌석 tmuxc 체크 · 이 세션·이 역할만 · 증류되면 연계»)
# launchd com.byz.ft20-r1483-scan (StartInterval 300 · 유휴 디바운스 0 · 모델 호출 0)
# 받는 좌석 = 명부 seats-harness.json 에서 role=qa · _replaced_by 없음 · 도달 파일(state/successor) 후계 · tmux 생존 (r1666 승계 자동 연계)
# 출력 = scan-latest.txt + QA 좌석 우편함 1통 (QA 우편함이 이미 5통 이상 밀려 있으면 파일만)
set -uo pipefail
cd "$(dirname "$0")" || exit 2
ROOT=/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents
FT="$ROOT/.fable-team"
IDLE_MIN=${FT20_SCAN_IDLE_MIN:-10}
mkdir scan.lock 2>/dev/null || exit 0
trap 'rmdir scan.lock' EXIT

SEAT=$(python3 - "$FT" <<'PY'
import json, os, subprocess, sys
ft = sys.argv[1]
d = json.load(open(ft + "/seats-harness.json"))

def later(seat):  # r1666 ⓔ: 도달 파일 → 후계 (연쇄 추적 · 순환 0)
    seen = {seat}
    while True:
        path = os.path.join(ft, "state", "successor", seat + ".json")
        try:
            nxt = json.load(open(path)).get("successor") or seat
        except (OSError, ValueError):
            return seat
        if nxt == seat or nxt in seen:
            return seat
        seen.add(nxt)
        seat = nxt

for k, v in d.items():
    if k.startswith("byz-harness-qa-ft20-") and isinstance(v, dict) and v.get("role") == "qa" and not v.get("_replaced_by"):
        seat = later(k)
        if subprocess.run(["tmux", "has-session", "-t", "=" + seat], capture_output=True).returncode == 0:
            print(seat); break
PY
)
[ -n "$SEAT" ] || { echo "$(date '+%F %T') NO_QA_SEAT" > scan-latest.txt; printf '%s\n' "{\"at\": $(date +%s), \"status\": \"NO_TARGET_SEAT\", \"error\": \"명부 role=qa 현역 0 또는 tmux 없음\"}" > error.json; exit 0; }

LIST=$(cd "$ROOT" && FT_SEATS_JSON="$FT/seats-harness.json" timeout 20 bash "$FT/bin/ft-seat-status.sh" list '^byz-(harness|planner|issues)' 2>/dev/null)
[ -n "$LIST" ] || { echo "$(date '+%F %T') 판정 불가 ft-seat-status 실패" > scan-latest.txt; exit 1; }

SUMMARY=$(SCAN_LIST="$LIST" python3 - "$SEAT" "$IDLE_MIN" <<'PY'
import os, sys
me, lim = sys.argv[1], int(sys.argv[2]) * 60
busy, idle, unknown = 0, [], []
for ln in os.environ["SCAN_LIST"].splitlines():
    p = ln.split()
    if len(p) < 3 or p[0] == me:
        continue
    if p[1] == "BUSY":
        busy += 1
    elif p[1] == "IDLE":
        if p[2].isdigit() and int(p[2]) >= lim:
            idle.append("%s %d분" % (p[0].replace("byz-", ""), int(p[2]) // 60))
        elif not p[2].isdigit():
            unknown.append(p[0].replace("byz-", ""))
print("작업 %d · %d분↑ 유휴 %d" % (busy, lim // 60, len(idle)))
print("유휴: " + (" · ".join(idle) or "0"))
print("유휴(시간 모름): " + (" · ".join(unknown) or "0"))
PY
)
NOW=$(date '+%H:%M')
{ echo "$(date '+%F %T') seat=$SEAT"; echo "$SUMMARY"; echo "---"; echo "$LIST"; } > scan-latest.txt

PENDING=$(timeout 7 bash "$FT/comm/mbox.sh" peek "$SEAT" 2>/dev/null | sed -n 's/.*pending=\([0-9]*\).*/\1/p' | head -1)
[ "${PENDING:-0}" -ge 5 ] && exit 0
timeout 20 bash "$FT/comm/mbox.sh" send "$SEAT" ft20-scan "[5분 점검 $NOW] $(printf '%s' "$SUMMARY" | head -1)
$(printf '%s' "$SUMMARY" | sed -n 2,3p)
할 일: 유휴 좌석마다 사유 확인 → 현역 팀장 경유 처리 요청 · 전체 N/20·착지 N/14 회차 갱신(CHECK-BRIEF 형식) · 전문 $PWD/scan-latest.txt" >/dev/null 2>&1
exit 0
