#!/usr/bin/env bash
# ft-hil-answer.sh — 질문 원장의 한 행에 사람의 답을 넣고 질문한 좌석에 돌려보낸다 (C3).
#
# 사용: ft-hil-answer.sh <행#> <값> [--from <최상위 오케 좌석>]
#   open → answered:<값>(원장 기록) → 질문 좌석에 mbox 회신 → applied:<값>
#   mbox 가 실패하면 answered 에서 멈추고 exit 1 — 같은 명령을 다시 치면 «전달만» 재시도한다.
#   이미 applied 인 행 · 없는 행은 REJECT. 선택지 밖 값은 받되 NOTE 를 찍는다(Other).
#   FT_SEND_DRY=1 이면 mbox 를 보내지 않는다(시험용). 원장 = HIL_LEDGER (기본 <harness 팀 폴더>/HIL-LEDGER.md · TEAMS.md 폴더 칸)
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
COMMON="$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
if [ -n "${HIL_LEDGER:-}" ]; then LEDGER="$HIL_LEDGER"
else . "$HERE/ft-team-lib.sh"; _HT="$(ft_team_in "$ROOT" harness)" || exit 1; LEDGER="$_HT/HIL-LEDGER.md"; fi   # R382b: 팀 폴더는 TEAMS.md 칸으로
MBOX="${FT_MBOX_CMD:-}"
[ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 ../comm 없음 — 데이터 루트의 comm

die() { echo "REJECT $*" >&2; exit "${2:-1}"; }
clean() { printf '%s' "$1" | tr '\n\r' '  ' | sed 's/|/¦/g; s/^ *//; s/ *$//'; }
trim() { printf '%s' "$1" | sed 's/^ *//; s/ *$//'; }

ROW=""; VALUE=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:-}"; shift 2;;
    --*)    die "알 수 없는 옵션: $1" 2;;
    *)      if [ -z "$ROW" ]; then ROW="$1"; elif [ -z "$VALUE" ]; then VALUE="$1"; else die "값은 1개 문자열로 — 따옴표로 묶어라" 2; fi; shift;;
  esac
done
case "$ROW" in ''|*[!0-9]*) die "usage: $0 <행#> <값> [--from 좌석]" 2;; esac
[ -n "$VALUE" ] || die "usage: $0 <행#> <값> [--from 좌석]" 2
[ -z "$FROM" ] && FROM="${FT_ME:-}"
[ -z "$FROM" ] && [ -n "${TMUX:-}" ] && FROM="$(tmux display -p '#S' 2>/dev/null)"
[ -n "$FROM" ] || FROM="ft-hil-answer"
[ -f "$LEDGER" ] || die "원장 없음: $LEDGER"

send_mbox() {  # <to> <from> <body>
  if [ "${FT_SEND_DRY:-0}" = 1 ]; then echo "DRY send to=$1 from=$2 body=$3" >&2; return 0; fi
  local out
  out="$(bash "$MBOX" send "$1" "$2" "$3" 2>&1)" || { echo "REJECT mbox send 실패: $out" >&2; return 1; }
  case "$out" in *doorbell=absent*) echo "WARN 질문 좌석 세션 없음(doorbell=absent): $1" >&2;; esac
  return 0
}

set_status() {  # <행#> <상태> — 원장 한 칸만 바꿔 temp+mv 로 교체
  local tmp="$LEDGER.tmp.$$"
  awk -F'|' -v OFS='|' -v n="$1" -v st="$2" '/^\|/ && $2+0==n && $2 ~ /[0-9]/ {$9=" " st " "} {print}' "$LEDGER" > "$tmp" && mv -f "$tmp" "$LEDGER" || { rm -f "$tmp"; die "원장 갱신 실패"; }
}

LOCK="$LEDGER.lock"; i=0
until mkdir "$LOCK" 2>/dev/null; do
  i=$((i+1)); [ "$i" -gt 100 ] && die "원장 잠금 10초 초과 — $LOCK (남은 잠금이면 사람 확인)"
  sleep 0.1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

LINE="$(awk -F'|' -v n="$ROW" '/^\|/ && $2 ~ /[0-9]/ && $2+0==n {print; exit}' "$LEDGER")"
[ -n "$LINE" ] || die "원장에 행 #$ROW 없음"
IFS='|' read -r _ _ _ SEAT SEQ Q OPTS _ STATUS _ <<<"$LINE"
SEAT="$(trim "$SEAT")"; SEQ="$(trim "$SEQ")"; Q="$(trim "$Q")"; OPTS="$(trim "$OPTS")"; STATUS="$(trim "$STATUS")"
case "$STATUS" in
  open|answered:*) ;;
  applied:*)       die "행 #$ROW 는 이미 applied — $STATUS";;
  *)               die "행 #$ROW 상태를 모른다: $STATUS";;
esac
V="$(clean "$VALUE")"
[ -n "$OPTS" ] && case "¦${OPTS}¦" in *"¦${V}¦"*) ;; *) echo "NOTE 선택지 밖 값(Other): $V" >&2;; esac

set_status "$ROW" "answered:$V"
send_mbox "$SEAT" "$FROM" "[HIL-답] 행#$ROW (질문 seq #$SEQ) 값: $V — 질문: ${Q:0:200}" \
  || { echo "answered 에서 멈춤 — 같은 명령을 다시 치면 전달만 재시도" >&2; exit 1; }
set_status "$ROW" "applied:$V"
echo "APPLIED row=$ROW seat=$SEAT seq=$SEQ value=$V"
