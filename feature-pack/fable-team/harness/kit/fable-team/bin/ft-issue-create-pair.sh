#!/usr/bin/env bash
# ft-issue-create-pair.sh <제목> <본문파일> [--apply] — 좌석 등록 쌍: Issue 생성 + 매니저 알림 1통 (C16)
#
# 왜 있나: 세션 에이전트가 gh issue create 만 하면 로컬 사건이 생기지 않아 매니저가 모른다(SPEC-github-issue-driven §2 ②).
#   생성 명령과 매니저 알림 mbox 1통을 한 묶음으로 만든다. 본문 끝에 마커 「ft-origin: seat」를 찍어 분류기(ft-issue-classify.sh)가 ②로 읽게 한다.
# 작성자 = 봇 계정 토큰(FT_ISSUE_BOT_TOKEN 또는 ~/.config/byz-harness/issue-bot.token) — --apply 에 토큰이 없으면 exit 2.
# 기본 = dry-run: 실행할 gh 명령과 알림 본문(Issue 번호는 자리표시)만 출력. --apply 때만 실제 실행.
# 수신자 = seats-issues.json(FT_ISSUES_SEATS)의 _master — 없으면 raise(폴백 0). 보내는 좌석 = FT_ME > tmux 세션명.
# exit 0 = 완료 · 1 = 실행 실패(사유 stderr) · 2 = usage/입력 오류
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
COMMON="$(git -C "${ROOT:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
ISSUES_SEATS="${FT_ISSUES_SEATS:-$COMMON/.fable-team/seats-issues.json}"
MBOX="${FT_MBOX_CMD:-}"
[ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r385 r3: 설치본엔 형제 comm 폴더가 없다 — 데이터 루트의 comm
MARKER='<!-- ft-origin: seat -->'

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }
clean() { printf '%s' "$1" | tr '\n\r' '  ' | tr -d '`' | sed 's/^ *//; s/ *$//'; }

TITLE=""; BODYFILE=""; APPLY=0; POS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift;;
    --*)     die "알 수 없는 옵션: $1" 2;;
    *)       POS=$((POS+1)); [ $POS -eq 1 ] && TITLE="$1" || { [ $POS -eq 2 ] && BODYFILE="$1" || die "인자 초과: $1" 2; }; shift;;
  esac
done
[ -n "$TITLE" ] && [ -n "$BODYFILE" ] || die "usage: $0 <제목> <본문파일> [--apply]" 2
[ -f "$BODYFILE" ] || die "본문 파일이 없다: $BODYFILE" 2

FROM="${FT_ME:-}"
[ -z "$FROM" ] && [ -n "${TMUX:-}" ] && FROM="$(tmux display -p '#S' 2>/dev/null)"
[ -n "$FROM" ] || die "보내는 좌석을 알 수 없다 — FT_ME 또는 tmux 안에서 실행" 2
MANAGER="$(jq -r '._master // empty' "$ISSUES_SEATS" 2>/dev/null)"
[ -n "$MANAGER" ] || die "issue-manager 좌석 없음 — $ISSUES_SEATS 의 _master" 2

SHORT="$(clean "$TITLE")"
notify_body() { echo "[Issue 등록] Issue #$1 등록 — 제목: ${SHORT:0:120} / 경로: 세션 에이전트(ft-origin: seat) / 등록 좌석: $FROM — 접수 검사(라벨 6) 요청."; }

# r1174: team 라벨 1개 — 이슈팀 확정 순서(PLAN-issue-autonomy-system §5-2). 명단은 10-30 실측 고정 — 새 team 라벨이 생기면 이 줄을 같이 고친다. 라벨 신설 0.
TEAMS=" planner v65 ccu cfo kk shared-harness harness-ops feature ops loom graphics concierge room chatbot knowledge lecture "
norm_team() {  # 대괄호·공백 떼고 소문자 → 별칭 → 명단에 있을 때만 출력(rc0)
  local t; t="$(printf '%s' "$1" | tr -d '[] \t' | tr '[:upper:]' '[:lower:]')"
  case "$t" in harness) t=harness-ops;; mobile) t=room;; esac
  [ -n "$t" ] && [[ "$TEAMS" == *" $t "* ]] && echo "$t"
}
seat_team() {  # 순 3: byz-<팀>-<역할>-… 의 팀(가장 긴 이름 일치) · 접수자(planner·issues·desk) = 보류
  local seat="${1#byz-}" c best="" role
  [[ "$1" == byz-* ]] || { echo "HOLD 좌석 이름이 byz- 꼴 아님: $1"; return; }
  for c in $TEAMS harness mobile issues; do [[ "$seat" == "$c"-* ]] && [ ${#c} -gt ${#best} ] && best="$c"; done
  [ -n "$best" ] || { echo "HOLD 좌석 팀이 명단 밖: $1"; return; }
  role="${seat#"$best"-}"; role="${role%%-*}"
  case "$best:$role" in planner:*|issues:*|*:desk) echo "HOLD 접수자 좌석: $1"; return;; esac
  norm_team "$best"
}
team_of() {  # <제목> <본문파일> <등록 좌석> → 팀 | «HOLD <이유>»
  local t rest="$1" n=0 first="" re='^[[:space:]]*\[([^]]*)\](.*)$'
  t="$(sed -n 's/^[[:space:]]*담당 팀[[:space:]]*:[[:space:]]*//p' "$2" | head -1)"
  t="$(norm_team "${t%%[[:space:]]*}")" && { echo "$t"; return; }
  while [[ "$rest" =~ $re ]]; do n=$((n+1)); [ $n -eq 1 ] && first="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"; done
  [ $n -ge 2 ] && { echo "HOLD 제목 접두 ${n}개"; return; }
  [ $n -eq 0 ] && { seat_team "$3"; return; }
  norm_team "$first" || echo "HOLD 명단 밖 접두: [$first]"
}
TEAM="$(team_of "$TITLE" "$BODYFILE" "$FROM")"
LABEL=()
case "$TEAM" in HOLD\ *) echo "TEAM-HOLD ${TEAM#HOLD }"; TEAM=보류;; *) LABEL=(--label "team:$TEAM");; esac

if [ $APPLY -eq 0 ]; then
  echo "DRY gh issue create --title '$TITLE'${LABEL[*]:+ ${LABEL[*]}} --body-file <$BODYFILE + 마지막 줄 $MARKER>"
  echo "DRY send to=$MANAGER from=$FROM body=$(notify_body '<번호>')"
  exit 0
fi

# 작성자 = 봇 계정(오빠 이름으로 올라가지 않게). 토큰 없으면 raise — 오빠 계정으로 폴백하지 않는다(#0 RULE).
BOT_TOKEN="${FT_ISSUE_BOT_TOKEN:-}"
[ -n "$BOT_TOKEN" ] || { BOT_FILE="${FT_ISSUE_BOT_TOKEN_FILE:-$HOME/.config/byz-harness/issue-bot.token}"; [ -r "$BOT_FILE" ] && BOT_TOKEN="$(tr -d '[:space:]' < "$BOT_FILE")"; }
[ -n "$BOT_TOKEN" ] || die "봇 토큰 없음 — FT_ISSUE_BOT_TOKEN 또는 ${FT_ISSUE_BOT_TOKEN_FILE:-$HOME/.config/byz-harness/issue-bot.token} (오빠 계정으로 폴백하지 않는다)" 2
STAMPED="$(mktemp)"; trap 'rm -f "$STAMPED"' EXIT
{ cat "$BODYFILE"; printf '\n%s\n' "$MARKER"; } > "$STAMPED"
URL="$(GH_TOKEN="$BOT_TOKEN" gh issue create --title "$TITLE" ${LABEL[@]+"${LABEL[@]}"} --body-file "$STAMPED" 2>&1)" || die "gh issue create 실패: $URL"
NUM="$(printf '%s' "$URL" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -1)"
[ -n "$NUM" ] || die "Issue 는 만들어졌을 수 있다 — 번호를 못 읽음: $URL"
OUT="$(bash "$MBOX" send "$MANAGER" "$FROM" "$(notify_body "$NUM")" 2>&1)" \
  || die "Issue #$NUM 은 만들어졌다 · 매니저 알림 실패 — 알림만 다시 보낼 것: $OUT"
echo "PAIR issue=#$NUM team=$TEAM manager=$MANAGER $(printf '%s' "$OUT" | sed -n 's/.*\(seq=[0-9]*\).*/\1/p' | head -1)"
