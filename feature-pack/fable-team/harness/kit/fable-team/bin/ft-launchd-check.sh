#!/bin/bash
# ft-launchd-check.sh — 기대 예약이 launchd 에서 꺼져(disabled) 있나 (R184 · 내림에 «닫는 사건»을 붙인다)
#   기대 예약표 .fable-team/state/launchd-expected.txt(한 줄 한 Label · # 주석) 의 각 Label 이 `launchctl print-disabled` 에서 disabled 면
#     · 내림 기록 .fable-team/state/launchd-disabled/<Label>.md 에 `사유:` `판정:` `다시 올릴 조건:` `누가:` 네 줄이 모두 «콜론 뒤 비공백 값» 이면 stdout «내림 중(<사유>)» 1줄 — 알림 0
#     · 기록이 없거나 한 줄이라도 비면 stdout «꺼짐 — 내림 기록 없음» / «내림 기록 불완전(<빠진 항목>)» 1줄 + 현역 master 앞 [급] 1통(Label·날짜당 1회 · 표식 파일)
#   로컬 파일·launchctl 만 읽는다(외부 호출 0). 켜지도 끄지도 않는다. 기록 작성 규칙 = install-magazine.sh 머리 주석.
#   env: FT_LDC_EXPECTED · FT_LDC_RECORDS · FT_LDC_STATE · FT_LDC_NOW(YYYY-MM-DD · 시험) · FT_LDC_MBOX · FT_LDC_NOTIFY(기본 SEATS 의 _master) · FT_LDC_SEATS · FT_LDC_LAUNCHCTL
#   rc: 0 · 3 수신 좌석 없음 · 4 print-disabled 못 읽음 · 5 mbox 실패(표식 안 씀 → 다음 루프 재시도)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"; ROOT="${ROOT:-$WT}"
EXPECTED="${FT_LDC_EXPECTED:-$ROOT/.fable-team/state/launchd-expected.txt}"
RECORDS="${FT_LDC_RECORDS:-$ROOT/.fable-team/state/launchd-disabled}"
STATE="${FT_LDC_STATE:-$ROOT/.fable-team/state/launchd-check}"
MBOX="${FT_LDC_MBOX:-}"; [ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
SEATS="${FT_LDC_SEATS:-$ROOT/.fable-team/seats.json}"
LCTL="${FT_LDC_LAUNCHCTL:-launchctl}"
TODAY="${FT_LDC_NOW:-$(date +%F)}"

[ -f "$EXPECTED" ] || exit 0   # 기대 예약표가 없으면 점검 대상 0 (master 가 표를 쓰면 시작)
disabled="$("$LCTL" print-disabled "gui/$(id -u)" 2>&1)" || { echo "ERROR ft-launchd-check: print-disabled 실패 — $disabled" >&2; exit 4; }
to="${FT_LDC_NOTIFY:-$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_master") or "")' "$SEATS" 2>/dev/null)}"
rc=0
while IFS= read -r label; do
  label="${label%%#*}"; label="${label//[[:space:]]/}"; [ -n "$label" ] || continue
  printf '%s\n' "$disabled" | grep -Eq "\"$label\"[[:space:]]*=>[[:space:]]*(disabled|true)" || continue
  rec="$RECORDS/$label.md"
  missing=""
  for key in 사유 판정 "다시 올릴 조건" 누가; do   # 네 줄 모두 콜론 뒤 «비공백 값» 이 있어야 기록이다
    [ -n "$(grep -m1 "^$key:" "$rec" 2>/dev/null | sed "s/^$key:[[:space:]]*//")" ] || missing+="${missing:+·}$key"
  done
  if [ -z "$missing" ]; then
    why="$(grep -m1 '^사유:' "$rec" | sed 's/^사유:[[:space:]]*//')"
    echo "내림 중($why) $label — 내림 기록 $rec"; continue
  fi
  note="내림 기록 없음"; [ -f "$rec" ] && note="내림 기록 불완전($missing)"
  echo "꺼짐 — $label disabled · $note"
  [ -f "$STATE/$label.$TODAY" ] && continue
  [ -n "$to" ] || { echo "ERROR ft-launchd-check: 수신 좌석 없음(_master) $SEATS" >&2; rc=3; continue; }
  if bash "$MBOX" send "$to" ft-launchd-check "[급] 예약 $label 이 launchd 에서 꺼져 있음(disabled) — $note · 내림 기록을 쓰거나 다시 올릴 것(install-magazine.sh 머리 주석 참조)" --urgent >/dev/null 2>&1; then
    mkdir -p "$STATE" && : > "$STATE/$label.$TODAY"
  else echo "ERROR ft-launchd-check: mbox 실패 to=$to" >&2; rc=5; fi
done < "$EXPECTED"
exit $rc
