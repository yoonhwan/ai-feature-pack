#!/usr/bin/env bash
# ft-plan-handoff.sh — 임시 기획 세션의 «정리본»을 issue-manager 로 넘기는 한 명령 (C17).
#
# 왜 있나: 오빠가 임의로 연 기획 세션(byz-planner-master-claude#N)의 정리본이 Issue 로 들어가는 길이 없었다(SPEC-github-issue-driven §2 ①).
#   정리본 머리줄 3개를 검증하고 mbox 2통을 보낸다 — ①issue-manager: 단위 1 = Issue 1건 잠정 생성 요청 · ②planner: 분류 요청 예고.
#   Issue 생성 자체는 하지 않는다(매니저 몫).
#
# 사용: ft-plan-handoff.sh <정리본 경로> [--dry-run]
#   머리줄(줄 맨 앞, 3개 모두 필요): 「주제: …」 · 「골좌표: …」 · 「쪼갠 단위 N」(N = 1 이상 정수 · 「쪼갠 단위: N」도 허용)
#   수신자 = seats-issues.json(FT_ISSUES_SEATS)의 _master(매니저) · seats-planner.json(FT_PLANNER_SEATS)의 _master(planner) — 없으면 REJECT(폴백 0)
#   보내는 좌석 = FT_ME > tmux 세션명 (둘 다 없으면 REJECT)
#   --dry-run 또는 FT_SEND_DRY=1 이면 mbox 를 보내지 않고 본문 2통만 stdout 에 찍는다(시험용)
# 실패는 전부 raise(exit≠0).
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
COMMON="$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
ISSUES_SEATS="${FT_ISSUES_SEATS:-$COMMON/.fable-team/seats-issues.json}"
PLANNER_SEATS="${FT_PLANNER_SEATS:-$COMMON/.fable-team/seats-planner.json}"
MBOX="${FT_MBOX_CMD:-}"
[ -n "$MBOX" ] || { [ -f "$HERE/../comm/mbox.sh" ] && MBOX="$HERE/../comm/mbox.sh" || MBOX="$COMMON/.fable-team/comm/mbox.sh"; }

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }
clean() { printf '%s' "$1" | tr '\n\r' '  ' | tr -d '`' | sed 's/^ *//; s/ *$//'; }

FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) FT_SEND_DRY=1; shift;;
    --*)       die "알 수 없는 옵션: $1" 2;;
    *)         [ -z "$FILE" ] && FILE="$1" || die "정리본 경로는 1개만" 2; shift;;
  esac
done
[ -n "$FILE" ] || die "usage: $0 <정리본 경로> [--dry-run]" 2
[ -f "$FILE" ] || die "정리본 파일이 없다: $FILE"

TOPIC="$(clean "$(sed -n 's/^주제:[[:space:]]*//p' "$FILE" | head -1)")"
GOALCOORD="$(clean "$(sed -n 's/^골좌표:[[:space:]]*//p' "$FILE" | head -1)")"
UNITS="$(sed -n 's/^쪼갠 단위[: ]*\([0-9][0-9]*\)[[:space:]]*$/\1/p' "$FILE" | head -1)"
[ -n "$TOPIC" ]     || die "머리줄 「주제: …」 없음(또는 값 비었음) — $FILE"
[ -n "$GOALCOORD" ] || die "머리줄 「골좌표: …」 없음(또는 값 비었음) — $FILE"
[ -n "$UNITS" ]     || die "머리줄 「쪼갠 단위 N」 없음(N = 정수) — $FILE"
[ "$UNITS" -ge 1 ]  || die "쪼갠 단위는 1 이상이어야 한다: $UNITS — $FILE"

FROM="${FT_ME:-}"
[ -z "$FROM" ] && [ -n "${TMUX:-}" ] && FROM="$(tmux display -p '#S' 2>/dev/null)"
[ -n "$FROM" ] || die "보내는 좌석을 알 수 없다 — FT_ME 또는 tmux 안에서 실행" 2
MANAGER="$(jq -r '._master // empty' "$ISSUES_SEATS" 2>/dev/null)"
[ -n "$MANAGER" ] || die "issue-manager 좌석 없음 — $ISSUES_SEATS 의 _master" 2
PLANNER="$(jq -r '._master // empty' "$PLANNER_SEATS" 2>/dev/null)"
[ -n "$PLANNER" ] || die "planner 좌석 없음 — $PLANNER_SEATS 의 _master" 2

ABS="$(cd -- "$(dirname -- "$FILE")" && pwd)/$(basename -- "$FILE")"
REL="$ABS"; [ -n "$ROOT" ] && REL="${ABS#"$ROOT"/}"
BODY_MGR="[계획 인계] 정리본 $REL / 주제: ${TOPIC:0:150} / 골좌표: ${GOALCOORD:0:150} / 쪼갠 단위 $UNITS — 단위 1 = Issue 1건, 잠정 Issue ${UNITS}건 생성 요청(type: + status:needs-triage + 마일스톤만 · team·priority·완성 전/후는 planner 값 뒤). 만든 뒤 planner $PLANNER 에 새 Issue # 별 분류 요청 1통씩."
BODY_PLN="[분류 요청 예고] 정리본 $REL / 주제: ${TOPIC:0:150} / 골좌표: ${GOALCOORD:0:150} / 쪼갠 단위 $UNITS — issue-manager $MANAGER 가 잠정 Issue ${UNITS}건을 만들면 Issue # 별로 분류 요청이 온다. 팀·골 축·완성 전/후 값을 1통씩 회신."

send_mbox() {  # <to> <body> → 전역 SEQ_OUT (명령 치환을 쓰지 않아 DRY 줄이 stdout 에 그대로 나간다)
  SEQ_OUT=""
  if [ "${FT_SEND_DRY:-0}" = 1 ]; then echo "DRY send to=$1 from=$FROM body=$2"; SEQ_OUT=dry; return 0; fi
  local out
  out="$(bash "$MBOX" send "$1" "$FROM" "$2" 2>&1)" || { echo "REJECT mbox send 실패($1): $out" >&2; return 1; }
  SEQ_OUT="$(printf '%s' "$out" | sed -n 's/.*seq=\([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$SEQ_OUT" ] || { echo "REJECT mbox 응답에 seq 없음($1): $out" >&2; return 1; }
  case "$out" in *doorbell=absent*) echo "WARN 수신 좌석 세션 없음(doorbell=absent): $1" >&2;; esac
}

send_mbox "$MANAGER" "$BODY_MGR" || exit 1
SEQ_M="$SEQ_OUT"
send_mbox "$PLANNER" "$BODY_PLN" || die "매니저 발신은 끝남(seq=$SEQ_M) · planner 발신 실패 — planner 만 다시 보낼 것" 1
SEQ_P="$SEQ_OUT"
echo "HANDOFF units=$UNITS manager=$MANAGER seq=$SEQ_M planner=$PLANNER seq=$SEQ_P file=$REL"
