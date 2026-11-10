#!/bin/bash
# ft-distill-audit.sh — r1554 감사(읽기 전용): 증류 게이트 «판정 불가» 를 갈래별·좌석별로 센다.
#   갈래 = subsession(하위 세션 면제 · 로그 0) · seat(좌석 = 기록 → 연속 N회 막음) · other(그 밖 경고 통과) · other-legacy(옛 줄 · branch 없음)
#   usage: bash ft-distill-audit.sh [--log F] [--hours 24]   — 쓰기 0 · 실좌석 입력 0 · 출력 = 표 1장
set -uo pipefail
LOG="${FT_DISTILL_LOG:-$HOME/.claude/logs/context-distill-gate.log}"; HOURS=24
while [ $# -gt 0 ]; do case "$1" in
  --log) LOG="${2:?}"; shift 2;; --hours) HOURS="${2:?}"; shift 2;;
  -h|--help) echo "usage: bash $0 [--log F] [--hours 24]"; exit 0;;
  *) echo "usage: bash $0 [--log F] [--hours 24]" >&2; exit 2;; esac; done
case "$HOURS" in ''|*[!0-9]*) echo "REJECT --hours 정수 아님: $HOURS" >&2; exit 2;; esac
[ -f "$LOG" ] || { echo "로그 없음: $LOG" >&2; exit 2; }
python3 - "$LOG" "$HOURS" <<'PYEOF'
import re, sys, time, collections
path, hours = sys.argv[1], int(sys.argv[2])
now = time.time(); cut = now - hours * 3600
TS = re.compile(r"^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)")
SEAT = re.compile(r"\bseat=(\S+)")
REASON = re.compile(r"\breason=(\S+)")
kinds = collections.Counter(); seats = collections.Counter(); why = collections.Counter()
bad_ts = 0
with open(path, "r", encoding="utf-8", errors="replace") as f:
    for line in f:
        m = TS.match(line)
        if not m:
            continue
        try:
            t = time.mktime(tuple(int(x) for x in m.groups()) + (0, 0, -1))
        except Exception:
            bad_ts += 1; continue
        if t < cut:
            continue
        if "undecidable-block" in line and "branch=seat" in line:
            kinds["seat-block"] += 1
        elif "undecidable" in line and "branch=seat" in line:
            kinds["seat-record"] += 1
        elif "branch=subsession" in line:
            kinds["subsession"] += 1
        elif "branch=other" in line:
            kinds["other"] += 1
        elif " error " in line:
            kinds["other-legacy"] += 1
        else:
            continue
        s = SEAT.search(line)
        if s:
            seats[s.group(1)] += 1
        r = REASON.search(line)
        if r:
            why[r.group(1)] += 1
print("== 증류 게이트 판정 불가 감사 (최근 %dh · %s) ==" % (hours, path))
print("%-14s %8s   %s" % ("GALAE", "LINES", "MEANING"))
print("%-14s %8d   %s" % ("subsession", kinds["subsession"], "하위 세션 면제 — 0 이어야 정상(로그 줄 자체가 없음)"))
print("%-14s %8d   %s" % ("seat-record", kinds["seat-record"], "좌석 판정 불가 기록(연속 상한 미만 = 통과)"))
print("%-14s %8d   %s" % ("seat-block", kinds["seat-block"], "좌석 판정 불가 연속 상한 도달 = 막음 + 팀장 1줄"))
print("%-14s %8d   %s" % ("other", kinds["other"], "명부 밖 세션 = 경고 통과(여전히 조용한 통과 아님)"))
print("%-14s %8d   %s" % ("other-legacy", kinds["other-legacy"], "옛 줄(branch 태그 없음) — r1554 이전 기록"))
print("TOTAL %d" % sum(kinds.values()))
if seats:
    print("\n%-40s %8s" % ("SEAT", "UNDECIDABLE"))
    for s, n in seats.most_common(30):
        print("%-40s %8d" % (s, n))
if why:
    print("\n%-24s %8s" % ("REASON", "LINES"))
    for s, n in why.most_common(10):
        print("%-24s %8d" % (s, n))
sys.exit(0)
PYEOF
