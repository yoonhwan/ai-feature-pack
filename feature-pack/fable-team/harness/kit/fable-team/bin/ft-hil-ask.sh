#!/usr/bin/env bash
# ft-hil-ask.sh — 하위 좌석의 사람 질문을 «질문 원장 1곳»에 올린다 (C3).
#
# 왜 있나: 하위 좌석(워커·나노·tester·architect)은 AskUserQuestion 을 못 쓴다 — 사용자가 그 pane 을 못 본다.
#   질문은 원장 1행 + mbox [HIL] 1통(seats-harness.json 의 _hil_route 좌석)으로 모이고, 답은 ft-hil-answer.sh 가 같은 좌석 seq 로 돌려보낸다.
#
# 사용: ft-hil-ask.sh <질문> [--options "a|b|c"] [--recommend a] [--seat <좌석>]
#   원장 = <harness 팀 폴더>/HIL-LEDGER.md (TEAMS.md 폴더 칸 · HIL_LEDGER 로 교체) · 행 8칸: # | 일시 | 좌석 | 좌석seq | 질문 | 선택지 | 추천 | 상태(open)
#   보내는 좌석 = --seat > FT_ME > tmux 세션명 (셋 다 없으면 REJECT)
#   수신 = FT_HIL_ROUTE > seats-harness.json(FT_SEATS)의 _hil_route
#   FT_SEND_DRY=1 이면 mbox 를 보내지 않고 DRY 줄만 찍는다(시험용 · seq 칸 = dry)
# 실패는 전부 raise(exit≠0) — 원장에 행이 «없으면» 질문도 안 나간 것이다(mbox 실패 시 행 추가 0).
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
COMMON="$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
if [ -n "${HIL_LEDGER:-}" ]; then LEDGER="$HIL_LEDGER"
else . "$HERE/ft-team-lib.sh"; _HT="$(ft_team_in "$ROOT" harness)" || exit 1; LEDGER="$_HT/HIL-LEDGER.md"; fi   # R382b: 팀 폴더는 TEAMS.md 칸으로
SEATS="${FT_SEATS:-$COMMON/.fable-team/seats-harness.json}"
MBOX="${FT_MBOX_CMD:-}"
[ -n "$MBOX" ] || { [ -f "$HERE/../comm/mbox.sh" ] && MBOX="$HERE/../comm/mbox.sh" || MBOX="$COMMON/.fable-team/comm/mbox.sh"; }

die() { echo "REJECT $*" >&2; exit "${2:-1}"; }
clean() { printf '%s' "$1" | tr '\n\r' '  ' | sed 's/|/¦/g; s/^ *//; s/ *$//'; }

QUESTION=""; OPTIONS=""; RECOMMEND=""; SEAT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --options)   OPTIONS="${2:-}"; shift 2;;
    --recommend) RECOMMEND="${2:-}"; shift 2;;
    --seat)      SEAT="${2:-}"; shift 2;;
    --*)         die "알 수 없는 옵션: $1" 2;;
    *)           [ -z "$QUESTION" ] && QUESTION="$1" || die "질문은 1개 문자열로 — 따옴표로 묶어라" 2; shift;;
  esac
done
[ -n "$QUESTION" ] || die "usage: $0 <질문> [--options a|b|c] [--recommend a] [--seat 좌석]" 2
[ -z "$SEAT" ] && SEAT="${FT_ME:-}"
[ -z "$SEAT" ] && [ -n "${TMUX:-}" ] && SEAT="$(tmux display -p '#S' 2>/dev/null)"
[ -n "$SEAT" ] || die "보내는 좌석을 알 수 없다 — --seat 또는 FT_ME" 2
if [ -n "$RECOMMEND" ]; then
  [ -n "$OPTIONS" ] || die "--recommend 는 --options 와 함께" 2
  case "|$OPTIONS|" in *"|$RECOMMEND|"*) ;; *) die "--recommend 값이 선택지에 없다: $RECOMMEND" 2;; esac
fi
ROUTE="${FT_HIL_ROUTE:-$(jq -r '._hil_route // empty' "$SEATS" 2>/dev/null)}"
[ -n "$ROUTE" ] || die "_hil_route 없음 — $SEATS 의 _hil_route 또는 FT_HIL_ROUTE" 2

send_mbox() {  # <to> <from> <body> → seq 를 stdout
  if [ "${FT_SEND_DRY:-0}" = 1 ]; then echo "DRY send to=$1 from=$2 body=$3" >&2; echo dry; return 0; fi
  local out seq
  out="$(bash "$MBOX" send "$1" "$2" "$3" 2>&1)" || { echo "REJECT mbox send 실패: $out" >&2; return 1; }
  seq="$(printf '%s' "$out" | sed -n 's/.*seq=\([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$seq" ] || { echo "REJECT mbox 응답에 seq 없음: $out" >&2; return 1; }
  case "$out" in *doorbell=absent*) echo "WARN 수신 좌석 세션 없음(doorbell=absent): $1" >&2;; esac
  echo "$seq"
}

mkdir -p "$(dirname "$LEDGER")" || die "원장 폴더 생성 실패"
LOCK="$LEDGER.lock"; i=0
until mkdir "$LOCK" 2>/dev/null; do
  i=$((i+1)); [ "$i" -gt 100 ] && die "원장 잠금 10초 초과 — $LOCK (남은 잠금이면 사람 확인)"
  sleep 0.1
done
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ ! -s "$LEDGER" ]; then
  cat > "$LEDGER" <<'EOF'
# HIL 질문 원장

> 질문 1건 = 1행. 상태: open → answered:<값> → applied:<값>. 쓰는 도구 = ft-hil-ask.sh · ft-hil-answer.sh (손으로 고치지 않는다).
> 칸 안의 `|` 는 `¦` 로 바뀐다.

| # | 일시 | 좌석 | 좌석seq | 질문 | 선택지 | 추천 | 상태 |
|---|---|---|---|---|---|---|---|
EOF
fi

N="$(awk -F'|' '/^\|/ && $2+0>m {m=$2+0} END{print m+1}' "$LEDGER")"
Q="$(clean "$QUESTION")"; O="$(clean "$OPTIONS")"; R="$(clean "$RECOMMEND")"
BODY="[HIL] 행#$N 좌석=$SEAT 질문: ${Q:0:300} / 선택지: ${O:-없음} / 추천: ${R:-없음} / 답: ft-hil-answer.sh $N <값> (원장 HIL-LEDGER.md)"
SEQ="$(send_mbox "$ROUTE" "$SEAT" "$BODY")" || exit 1
printf '| %s | %s | %s | %s | %s | %s | %s | open |\n' "$N" "$(date +%Y-%m-%dT%H:%M:%S)" "$SEAT" "$SEQ" "$Q" "$O" "$R" >> "$LEDGER"
echo "ASKED row=$N seat=$SEAT seq=$SEQ route=$ROUTE ledger=$LEDGER"
