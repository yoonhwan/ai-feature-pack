#!/bin/bash
# ft-launchd-check.sh — 기대 예약이 launchd 에서 꺼져(disabled) 있나 (R184 · 내림에 «닫는 사건»을 붙인다)
#   기대 예약표 .fable-team/state/launchd-expected.txt(한 줄 한 Label · # 주석) 의 각 Label 이 `launchctl print-disabled` 에서 disabled 면
#     · 내림 기록 .fable-team/state/launchd-disabled/<Label>.md 에 `사유:` `판정:` `다시 올릴 조건:` `누가:` 네 줄이 모두 «콜론 뒤 비공백 값» 이면 stdout «내림 중(<사유>)» 1줄 — 알림 0
#     · 기록이 없거나 한 줄이라도 비면 stdout «꺼짐 — 내림 기록 없음» / «내림 기록 불완전(<빠진 항목>)» 1줄 + 현역 master 앞 [급] 1통(Label·날짜당 1회 · 표식 파일)
#   R612: 켜져 있는데(launchctl list 에 PID «-») 마지막 종료가 실패(≠0)인 예약은 «죽은 예약» 이다 — print 의 실행 스크립트 경로를 읽어
#     대상 파일이 없으면 stdout «죽은 예약 <Label> exit=<N> — 대상 없음: <경로>» 1줄 + 현역 master 앞 [급] 1통(Label·날짜당 1회 · 표식 파일)
#     대상 파일이 있으면 stdout «죽은 예약 <Label> exit=<N>(대상 있음)» 1줄 + 같은 알림. 접두 밖 Label 은 안 본다. 켜기·끄기·plist 쓰기 0.
#   로컬 파일·launchctl 만 읽는다(외부 호출 0). 켜지도 끄지도 않는다. 기록 작성 규칙 = install-magazine.sh 머리 주석.
#   env: FT_LDC_EXPECTED · FT_LDC_RECORDS · FT_LDC_STATE · FT_LDC_NOW(YYYY-MM-DD · 시험) · FT_LDC_MBOX · FT_LDC_SEATS · FT_LDC_LAUNCHCTL
#        FT_LDC_NOTIFY(수신 좌석 덮기) → 없으면 FT_LDC_OWNER_SEATS(기본 <ROOT>/.fable-team/seats-harness.json · 장치 주인 명부)의 _master
#        → 주인 명부 «파일이 없을» 때만 FT_LDC_SEATS 의 _master (r1158 · 주인 명부가 있는데 _master 가 비면 rc3)
#        FT_LDC_DEAD_PREFIX(기본 «com.byz. com.airag. com.hermes.») · FT_LDC_DEAD=0 이면 죽은 예약 점검 끔
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

# r1158: 경보 수신 = 예약 장치 주인(harness 팀) 명부의 _master — 틱을 돈 팀의 명부(FT_LDC_SEATS)가 아니다
OWNER_SEATS="${FT_LDC_OWNER_SEATS:-$ROOT/.fable-team/seats-harness.json}"
_master_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_master") or "")' "$1" 2>/dev/null; }
if [ -n "${FT_LDC_NOTIFY:-}" ]; then to="$FT_LDC_NOTIFY"; to_src="FT_LDC_NOTIFY"
elif [ -f "$OWNER_SEATS" ]; then to="$(_master_of "$OWNER_SEATS")"; to_src="$OWNER_SEATS"   # _master 가 비면 수신 좌석 없음(rc3) — 틱 명부로 후퇴하지 않는다(#0 RULE)
else to="$(_master_of "$SEATS")"; to_src="$SEATS"; fi   # 주인 명부 파일이 없는 설치(팀 1개)만 틱 명부
rc=0
# ── 죽은 예약(켜진 채 실패 · 대상 스크립트 없음) — r612 ──
DEAD_PREFIX="${FT_LDC_DEAD_PREFIX:-com.byz. com.airag. com.hermes.}"
case "${FT_LDC_DEAD:-1}" in 0|no|false|off) DEAD_PREFIX="" ;; esac
# arguments 블록(또는 program)에서 «인터프리터 다음» 의 첫 절대경로 = 실행 스크립트
_dead_script() {
  local detail paths p
  detail="$("$LCTL" print "gui/$(id -u)/$1" 2>/dev/null)" || return 1
  paths="$(printf '%s\n' "$detail" | awk '/^[[:space:]]*arguments = \{/{f=1;next} f&&/^[[:space:]]*\}/{f=0} f{print}' | sed 's/^[[:space:]]*//' | grep '^/')"
  [ -n "$paths" ] || paths="$(printf '%s\n' "$detail" | sed -n 's/^[[:space:]]*program = \(\/.*\)$/\1/p')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "${p##*/}" in bash|sh|zsh|dash|ksh|fish|python*|node|perl|ruby) continue ;; esac
    printf '%s\n' "$p"; return 0
  done <<< "$paths"
  return 1
}
if [ -n "$DEAD_PREFIX" ] && listing="$("$LCTL" list 2>/dev/null)"; then
  while IFS=$'\t' read -r pid st label; do
    label="${label%$'\r'}"; [ -n "$label" ] || continue
    [ "$pid" = "-" ] || continue
    case "$st" in ''|*[!0-9-]*) continue ;; esac
    [ "$st" != "0" ] || continue
    hit=0; for pfx in $DEAD_PREFIX; do case "$label" in "$pfx"*) hit=1; break ;; esac; done
    [ "$hit" = 1 ] || continue
    script="$(_dead_script "$label" || true)"
    if [ -n "$script" ] && [ ! -e "$script" ]; then note="대상 없음: $script"; echo "죽은 예약 $label exit=$st — $note"
    else note="대상 있음${script:+: $script}"; echo "죽은 예약 $label exit=$st($note)"; fi
    [ -f "$STATE/dead-$label.$TODAY" ] && continue
    [ -n "$to" ] || { echo "ERROR ft-launchd-check: 수신 좌석 없음(_master) $to_src" >&2; rc=3; continue; }
    if bash "$MBOX" send "$to" ft-launchd-check "[급] 예약 $label 이 죽어 있음(launchctl PID 없음 · 마지막 종료 exit=$st) — $note · plist 실행 경로/인자를 그 팀이 확인할 것" --urgent >/dev/null 2>&1; then
      mkdir -p "$STATE" && : > "$STATE/dead-$label.$TODAY"
    else echo "ERROR ft-launchd-check: mbox 실패 to=$to($to_src)" >&2; rc=5; fi
  done <<< "$(printf '%s\n' "$listing" | tail -n +2)"
fi
[ -f "$EXPECTED" ] || exit $rc   # 기대 예약표가 없으면 꺼짐 점검 대상 0 (죽은 예약 점검은 표와 무관하게 이미 돌았다)
disabled="$("$LCTL" print-disabled "gui/$(id -u)" 2>&1)" || { echo "ERROR ft-launchd-check: print-disabled 실패 — $disabled" >&2; exit 4; }
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
  [ -n "$to" ] || { echo "ERROR ft-launchd-check: 수신 좌석 없음(_master) $to_src" >&2; rc=3; continue; }
  if bash "$MBOX" send "$to" ft-launchd-check "[급] 예약 $label 이 launchd 에서 꺼져 있음(disabled) — $note · 내림 기록을 쓰거나 다시 올릴 것(install-magazine.sh 머리 주석 참조)" --urgent >/dev/null 2>&1; then
    mkdir -p "$STATE" && : > "$STATE/$label.$TODAY"
  else echo "ERROR ft-launchd-check: mbox 실패 to=$to($to_src)" >&2; rc=5; fi
done < "$EXPECTED"

exit $rc
