#!/usr/bin/env bash
# ft-issues-daily-check.sh [--dry-run]   (r1115 · 00시 이슈 표 «안 돌면 경보» 1통 · 읽기 전용 · 하루 1회)
#   부르는 자 = ft-stall-scan.sh (120초 틱 · 한 줄). 하는 일 = 오늘 표 파일이 00:40 뒤에도 없거나 «판정 불가» 면
#   harness master 에 `[경보] 00시 이슈 표 없음 <날짜> · launchd <상태>` 1통. 같은 날 두 번째 틱은 0(장부 키 = state/issues-daily/<날짜>.alarm).
#   00:40 전에는 아무것도 하지 않는다(00:10 잡이 아직 돌 수 있다) · 표가 있고 «판정 불가» 가 아니면 0.
#   launchd 상태 = `launchctl print gui/<uid>/com.byz.ft-issues-daily` 한 번(없으면 «미등록»). FT_LAUNCHCTL 로 시험 주입.
#   exit 0 = 경보 없음/보냄 · 1 = 경보 발신 실패 · 2 = usage. 시험 = tests/test_issues_daily_r1115.sh
set -uo pipefail
DRY=0
case "${1:-}" in --dry-run) DRY=1;; '') ;; *) echo "usage: $0 [--dry-run]" >&2; exit 2;; esac
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
: "${FT_ROOT:=$(git -C . rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "${FT_ROOT:-}" ] || { echo "ERROR FT_ROOT 없음 — 리포 공용 루트를 못 풂" >&2; exit 2; }
NOW="${FT_NOW:-$(date +%s)}"
DAY="$(date -r "$NOW" +%Y%m%d 2>/dev/null || date -d "@$NOW" +%Y%m%d)"
HM="$(date -r "$NOW" +%H%M 2>/dev/null || date -d "@$NOW" +%H%M)"
[ "$HM" -ge 40 ] || exit 0                     # 00:10 잡이 아직 돌 수 있다 — 00:40 뒤에만 본다
DIR="${FT_ISSUES_DAILY_DIR:-$FT_ROOT/design/teams/issues/daily}"
TABLE="$DIR/TABLE-daily-$DAY.md"
STATE="${FT_ISSUES_DAILY_STATE:-$FT_ROOT/.fable-team/state/issues-daily}"
WHY=""
if [ ! -f "$TABLE" ]; then WHY="표 파일 없음"
elif grep -q '^## 판정 불가' "$TABLE"; then WHY="표가 판정 불가"
fi
[ -n "$WHY" ] || exit 0
[ -f "$STATE/$DAY.alarm" ] && exit 0           # 하루 1통
LC="${FT_LAUNCHCTL:-launchctl}"
LSTATE="$(timeout 7 "$LC" print "gui/$(id -u)/com.byz.ft-issues-daily" 2>&1 | grep -m1 -E 'state = |Could not find service' || true)"
[ -n "$LSTATE" ] || LSTATE="print 실패(launchctl rc≠0)"
if [ "$DRY" = 1 ]; then echo "PLAN [경보] 00시 이슈 표 없음 $DAY · $WHY · launchd $LSTATE"; exit 0; fi
MBOX="${FT_MBOX_SH:-$FT_ROOT/.fable-team/comm/mbox.sh}"
TO="${FT_ISSUES_DAILY_ALARM_TO:-}"
if [ -z "$TO" ]; then
  TO="$(python3 - "$FT_ROOT/.fable-team/seats-harness.json" <<'PY' 2>/dev/null || true
import json,sys
try: doc=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: sys.exit(0)
m=doc.get("_master")
if isinstance(m,str) and m.strip(): print(m.strip()); sys.exit(0)
best,bn="",-1
for k,v in doc.items():
    if k.startswith("_") or not isinstance(v,dict) or v.get("role")!="master" or v.get("_replaced_by"): continue
    t=k.rsplit("#",1)[-1]; n=int(t) if t.isdigit() else 0
    if n>bn: best,bn=k,n
print(best)
PY
)"
fi
[ -n "$TO" ] || { echo "ERROR 경보 받을 harness master 를 못 찾음 (seats-harness.json _master)" >&2; exit 1; }
BODY="[경보] 00시 이슈 표 없음 $DAY · $WHY · launchd $LSTATE
표: $TABLE
다음: launchd 재등록(install.sh --launchd-new com.byz.ft-issues-daily) 또는 손 1회 ft-issues-daily.sh --date $DAY"
OUT="$(timeout 30 bash "$MBOX" send "$TO" ft-issues-daily-check "$BODY" --urgent 2>&1)"; RC=$?
if [ "$RC" != 0 ]; then echo "ERROR 경보 발신 실패 to=$TO rc=$RC — $(printf '%s' "$OUT" | head -1)" >&2; exit 1; fi
mkdir -p "$STATE" && printf '%s\n' "$(printf '%s' "$OUT" | head -1)" > "$STATE/$DAY.alarm"
echo "ALARM $DAY → $TO ($WHY · launchd $LSTATE)"
