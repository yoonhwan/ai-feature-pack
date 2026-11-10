#!/bin/bash
# ft-magazine-check.sh — 08:15 아침 매거진 미발행 경보 (R184 · 판정 1424·1425 «자동화는 그 뒤»)
#   오늘(KST) 날짜의 `published date=<오늘>` 줄이 매거진 로그에 없으면 planner 앞 [긴급] 1통 — 같은 날 1회(표식 파일).
#   08:15 전이면 아무 것도 안 한다. 틱(ft-tick.sh)이 매 루프 부른다 — 로컬 파일·launchctl 만 읽는다(외부 호출 0).
#   env: FT_MAG_LOG(기본 ~/.hermes/logs/byz_morning_magazine.out) · FT_MAG_NOW("YYYY-MM-DD HH:MM" · 시험) · FT_MAG_MBOX · FT_MAG_STATE(표식 폴더)
#        FT_MAG_NOTIFY(수신 좌석 · 기본 SEATS 의 _hil_route → _master) · FT_MAG_SEATS · FT_MAG_LAUNCHCTL(기본 launchctl) · FT_MAG_LABEL(기본 com.byz.ft-magazine)
#   로그 파일이 없어도 «미발행» — 같은 [긴급] 1통(본문에 `로그 없음`) · 같은 날 1회 표식 · mbox 실패면 재시도 계약 그대로.
#   rc: 0 정상(경보 보냄·게시 있음·아직 이른 시각 포함) · 3 수신 좌석 없음 · 5 mbox 실패(표식 안 씀 → 다음 루프 재시도)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
LOG="${FT_MAG_LOG:-$HOME/.hermes/logs/byz_morning_magazine.out}"
NOW="${FT_MAG_NOW:-$(date '+%Y-%m-%d %H:%M')}"
MBOX="${FT_MAG_MBOX:-}"; [ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
STATE="${FT_MAG_STATE:-${ROOT:-$WT}/.fable-team/state/magazine-check}"
SEATS="${FT_MAG_SEATS:-${ROOT:-$WT}/.fable-team/seats.json}"
LCTL="${FT_MAG_LAUNCHCTL:-launchctl}"
LABEL="${FT_MAG_LABEL:-com.byz.ft-magazine}"
TODAY="${NOW:0:10}"; HM="${NOW:11:5}"

[[ "$HM" < "08:15" ]] && exit 0
nolog=""; last=""
if [ -f "$LOG" ]; then   # 로그 파일이 없으면 «미발행» 이다(예약이 한 번도 안 돈 것) — 조용히 끝내지 않고 같은 [긴급] 경로로 간다
  last="$(grep -o 'published date=[0-9-]*' "$LOG" | tail -1 | sed 's/published date=//')"
  grep -q "published date=$TODAY" "$LOG" && { echo "OK ft-magazine-check: 게시 있음 $TODAY"; exit 0; }
else nolog=" · 로그 없음($LOG)"; fi
[ -f "$STATE/$TODAY" ] && { echo "SKIP ft-magazine-check: $TODAY 경보 이미 보냄"; exit 0; }

to="${FT_MAG_NOTIFY:-$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("_hil_route") or d.get("_master") or "")' "$SEATS" 2>/dev/null)}"
[ -n "$to" ] || { echo "ERROR ft-magazine-check: 수신 좌석 없음(_hil_route/_master) $SEATS" >&2; exit 3; }
if ! "$LCTL" print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then st="없음"
elif "$LCTL" print-disabled "gui/$(id -u)" 2>/dev/null | grep -Eq "\"$LABEL\"[[:space:]]*=>[[:space:]]*(disabled|true)"; then st="disabled"
else st="enabled"; fi
bash "$MBOX" send "$to" ft-magazine-check "[긴급] 아침 매거진 미발행 $TODAY — 예약 상태 $st · 마지막 게시 ${last:-없음}$nolog" --urgent >/dev/null 2>&1 \
  || { echo "ERROR ft-magazine-check: mbox 실패 to=$to" >&2; exit 5; }
mkdir -p "$STATE" && : > "$STATE/$TODAY"
echo "ALERT ft-magazine-check: [긴급] 미발행 $TODAY → $to (예약 $st · 마지막 게시 ${last:-없음}$nolog)"
