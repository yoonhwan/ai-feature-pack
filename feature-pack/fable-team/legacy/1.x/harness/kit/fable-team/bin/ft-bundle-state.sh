#!/usr/bin/env bash
# ft-bundle-state.sh — 시험 묶음 test_bundle.state 를 허용 전이로만 바꾼다 (C10-라이트).
#
# 사용: ft-bundle-state.sh <seats-x.json> <카드#> <open|reported|classified|closed|reopen> [--result PASS|FAIL|UNMEASURED] [--event <seq>]
#   OK <파일> #<카드> <from>-><to>            exit 0
#   REJECT <사유> (금지 전이·결과 불일치)      exit 1
#   usage·파일·카드 불일치·JSON 오류           exit 2
#
# 허용 전이 (SPEC-team-essentials §1-B · MERGED C10):
#   open→reported · reopen→reported · reported→classified(--result 필수) ·
#   classified→closed(result=PASS 만 · --event 는 close_event) ·
#   classified→reopen(result=FAIL|UNMEASURED · 묶음당 1회 — test_bundle.reopen_count)
# 그 외 전부 exit 1. JSON 은 mktemp 후 mv 로 원자 갱신한다 — 실패 시 원본 불변.
set -uo pipefail

usage() { echo "usage: ft-bundle-state.sh <seats-x.json> <카드#> <open|reported|classified|closed|reopen> [--result PASS|FAIL|UNMEASURED] [--event <seq>]" >&2; exit 2; }
[ $# -ge 3 ] || usage
F="$1"; CARD="$2"; TO="$3"; shift 3
RESULT=""; EVENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --result) [ $# -ge 2 ] || usage; RESULT="$2"; shift 2 ;;
    --event)  [ $# -ge 2 ] || usage; EVENT="$2"; shift 2 ;;
    *) usage ;;
  esac
done
[ -f "$F" ] || { echo "REJECT $F: 파일 없음" >&2; exit 2; }

TMP="$(mktemp "$(dirname -- "$F")/.bundle-state.XXXXXX")" || { echo "REJECT mktemp 실패" >&2; exit 2; }
trap 'rm -f "$TMP"' EXIT

python3 - "$F" "$TMP" "$CARD" "$TO" "$RESULT" "$EVENT" <<'PY'
import json, sys

path, tmp, card, to, result, event = sys.argv[1:7]
STATES = ("open", "reported", "classified", "closed", "reopen")
RESULTS = ("PASS", "FAIL", "UNMEASURED")
ALLOWED = {
    ("open", "reported"), ("reopen", "reported"),
    ("reported", "classified"),
    ("classified", "closed"), ("classified", "reopen"),
}

def die(code, msg):
    print(msg, file=sys.stderr if code == 2 else sys.stdout)
    sys.exit(code)

if to not in STATES:
    die(2, f"REJECT 목표 상태 '{to}' 는 {'|'.join(STATES)} 가 아니다")
if result and result not in RESULTS:
    die(2, f"REJECT --result '{result}' 는 {'|'.join(RESULTS)} 가 아니다")
try:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
except ValueError as e:
    die(2, f"REJECT {path}: JSON 파싱 실패 ({e})")

tb = doc.get("test_bundle") if isinstance(doc, dict) else None
if not isinstance(tb, dict):
    die(2, f"REJECT {path}: test_bundle 객체 없음")
if str(tb.get("card")) != card:
    die(2, f"REJECT 카드 불일치: 명부 card={tb.get('card')} 인자={card}")

frm = tb.get("state")
if (frm, to) not in ALLOWED:
    die(1, f"REJECT 금지 전이 {frm}->{to}")

if to == "classified":
    if not result:
        die(1, "REJECT classified 는 --result PASS|FAIL|UNMEASURED 필수")
    tb["result"] = result
elif to == "closed" and tb.get("result") != "PASS":
    die(1, f"REJECT closed 는 result=PASS 만 (현재 result={tb.get('result')})")
elif to == "reopen":
    if tb.get("result") not in ("FAIL", "UNMEASURED"):
        die(1, f"REJECT reopen 은 result=FAIL|UNMEASURED 만 (현재 result={tb.get('result')})")
    if int(tb.get("reopen_count", 0)) >= 1:
        die(1, "REJECT reopen 은 묶음당 1회 (reopen_count 이미 1)")
    tb["reopen_count"] = int(tb.get("reopen_count", 0)) + 1
    tb.pop("result", None)
if to == "closed" and event:
    tb["close_event"] = event
tb["state"] = to

with open(tmp, "w", encoding="utf-8") as out:
    json.dump(doc, out, ensure_ascii=False, indent=2)
    out.write("\n")
print(f"OK {path} #{card} {frm}->{to}")
PY
rc=$?
[ $rc -eq 0 ] || exit $rc
mv "$TMP" "$F" || { echo "REJECT mv 실패" >&2; exit 2; }
trap - EXIT
