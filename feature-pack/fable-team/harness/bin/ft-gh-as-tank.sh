#!/usr/bin/env bash
# ft-gh-as-tank.sh <create|comment|label|close|reopen|edit> … [--apply] — Issue 쓰기를 Tank 봇(byz-tank) 이름으로 실행하는 gh 래퍼
#
# 왜 있나: 좌석이 gh 기본 로그인으로 Issue 를 쓰면 등록자·코멘트·라벨·close 가 전부 오빠 계정(yoonhwan)으로 올라간다(10-07 #839 등).
#   모든 Issue 쓰기는 이 래퍼 → Tank 토큰으로만 나간다. 직접 호출은 gh-issue-author-guard.sh 훅이 막는다. 읽기(view·list)는 래퍼 불필요.
# 기본 = dry-run: 실행할 gh 명령만 출력. --apply 때만 실제 실행.
# 토큰 = FT_ISSUE_BOT_TOKEN 또는 ~/.config/byz-harness/issue-bot.token (ft-issue-create-pair.sh 와 같은 위치) — 값은 출력하지 않는다.
#   --apply 에 토큰이 없으면 exit 2(오빠 로그인으로 폴백하지 않는다 — #0 RULE). 실행 전 `gh api user` 로 토큰 주인이 byz-tank 인지 확인, 아니면 REJECT.
# 동작:
#   create  <제목> <본문파일>                              → ft-issue-create-pair.sh 재사용(마커·매니저 알림 규약 그대로)
#   comment <번호> <본문파일>
#   label   <번호> [--add a,b] [--remove c,d]
#   close   <번호> [--comment <본문파일>] [--reason completed|not-planned]
#   reopen  <번호> [--comment <본문파일>]
#   edit    <번호> [--title <제목>] [--body-file <파일>]   (둘 중 하나 이상)
#       --apply 는 수정 «전» 현재 제목·본문을 `gh issue view` 로 읽어 보관 폴더(FT_ISSUE_EDIT_BAK_DIR 또는
#       git common dir 루트의 .fable-team/state/issue-edit-bak/)에 <번호>-<UTC시각>.body.md · .title.txt 로 저장한 «뒤에만» 수정한다.
#       보관 실패(조회 실패·빈 응답·쓰기 실패)면 수정 시도 0 · exit 1. 성공 출력 끝에 bak=<본문 파일> + 되돌림 명령 1줄.
#   pr-comment <번호> <본문파일>
#   pr-create  <제목> <본문파일> [--base B] [--head H]
#       dry-run 은 --base/--head 생략 가능. --apply 는 --base main 고정(아니면 exit 2) · --head 필수(없으면 exit 2) ·
#       생성 전 `gh api repos/$REPO/branches/<head>` 로 원격 실재 확인(없으면 exit 1 · PR 생성 시도 0) · 생성 뒤 PR 작성자가 Tank 인지 확인(아니면 exit 1 · URL 출력)
#   pr-edit  <번호> [--title <제목>] [--body-file <파일>]   (둘 중 하나 이상 · Issue edit 와 같은 보관 규약 — 파일명 pr<번호>-<UTC시각>.body.md · .title.txt)
#   pr-close <번호> [--comment <본문파일>]                  (gh pr close 에는 파일 인자가 없어 래퍼가 파일 내용을 --comment 문자열로 넘긴다)
#   (PR merge 는 래퍼·가드 대상이 아니다 · PR 리뷰 approve/request-changes 는 대체 동작 없음 — 사람만)
# exit 0 = 완료/dry-run · 1 = 실행 실패 또는 작성자 불일치(사유 stderr) · 2 = usage/토큰 없음
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}"
TANK="${FT_TANK_LOGIN:-byz-tank}"

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }
usage() { die "usage: $0 <create|comment|label|close|reopen|edit|pr-comment|pr-create|pr-edit|pr-close> … [--apply]" 2; }
need_num() { [[ "${1:-}" =~ ^[0-9]+$ ]] || die "Issue 번호(정수) 필요: ${1:-없음}" 2; }
need_file() { [ -f "${1:-}" ] || die "본문 파일이 없다: ${1:-없음}" 2; }

[ $# -ge 1 ] || usage
ACTION="$1"; shift
APPLY=0; ARGS=()
for a in "$@"; do [ "$a" = "--apply" ] && APPLY=1 || ARGS+=("$a"); done
set -- ${ARGS[@]+"${ARGS[@]}"}

# 동작별로 실행할 gh 인자를 CMD 배열에 만든다(dry-run 출력과 실행이 같은 배열 — 어긋날 일 없음).
CMD=(); COMMENT_FILE=""
case "$ACTION" in
  create)
    [ $# -eq 2 ] || die "usage: $0 create <제목> <본문파일> [--apply]" 2
    need_file "$2";;
  comment)
    [ $# -eq 2 ] || die "usage: $0 comment <번호> <본문파일> [--apply]" 2
    need_num "$1"; need_file "$2"
    CMD=(issue comment "$1" -R "$REPO" --body-file "$2");;
  pr-comment)
    [ $# -eq 2 ] || die "usage: $0 pr-comment <번호> <본문파일> [--apply]" 2
    need_num "$1"; need_file "$2"
    CMD=(pr comment "$1" -R "$REPO" --body-file "$2");;
  pr-create)
    [ $# -ge 2 ] || die "usage: $0 pr-create <제목> <본문파일> [--base B] [--head H]" 2
    T="$1"; need_file "$2"; CMD=(pr create -R "$REPO" --title "$T" --body-file "$2"); shift 2
    PR_BASE=""; PR_HEAD=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) PR_BASE="${2:?--base 값 필요}"; CMD+=(--base "$PR_BASE"); shift 2;;
        --head) PR_HEAD="${2:?--head 값 필요}"; CMD+=(--head "$PR_HEAD"); shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done
    if [ $APPLY -eq 1 ]; then
      [ "$PR_BASE" = main ] || die "pr-create --apply 는 --base main 고정(받은 값: ${PR_BASE:-없음})" 2
      [ -n "$PR_HEAD" ] || die "pr-create --apply 는 --head 필수" 2
    fi;;
  label)
    need_num "${1:-}"; NUM="$1"; shift; ADD=""; REM=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --add) ADD="${2:?--add 값 필요}"; shift 2;;
        --remove) REM="${2:?--remove 값 필요}"; shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done
    [ -n "$ADD$REM" ] || die "label 은 --add 또는 --remove 필요" 2
    CMD=(issue edit "$NUM" -R "$REPO")
    [ -n "$ADD" ] && CMD+=(--add-label "$ADD")
    [ -n "$REM" ] && CMD+=(--remove-label "$REM");;
  edit|pr-edit)
    need_num "${1:-}"; NUM="$1"; shift; ETITLE=""; EBODY=""; HAS_TITLE=0
    EKIND=issue; BAKPFX=""; [ "$ACTION" = pr-edit ] && { EKIND=pr; BAKPFX=pr; }
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) [ $# -ge 2 ] && [ -n "$2" ] || die "--title 값은 빈 문자열일 수 없다" 2; ETITLE="$2"; HAS_TITLE=1; shift 2;;
        --body-file) [ $# -ge 2 ] || die "--body-file 값 필요" 2; EBODY="$2"; need_file "$EBODY"; shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done
    [ $HAS_TITLE -eq 1 ] || [ -n "$EBODY" ] || die "edit 는 --title 또는 --body-file 필요" 2
    CMD=("$EKIND" edit "$NUM" -R "$REPO")
    [ $HAS_TITLE -eq 1 ] && CMD+=(--title "$ETITLE")
    [ -n "$EBODY" ] && CMD+=(--body-file "$EBODY");;
  pr-close)
    need_num "${1:-}"; NUM="$1"; shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --comment) COMMENT_FILE="${2:?--comment 값 필요}"; need_file "$COMMENT_FILE"; shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done
    CMD=(pr close "$NUM" -R "$REPO");;
  close|reopen)
    need_num "${1:-}"; NUM="$1"; shift; REASON=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --comment) COMMENT_FILE="${2:?--comment 값 필요}"; need_file "$COMMENT_FILE"; shift 2;;
        --reason) [ "$ACTION" = close ] || die "--reason 은 close 전용" 2
                  case "${2:-}" in completed) REASON="completed";; not-planned) REASON="not planned";; *) die "--reason 은 completed|not-planned" 2;; esac; shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done
    CMD=(issue "$ACTION" "$NUM" -R "$REPO")
    [ -n "$REASON" ] && CMD+=(--reason "$REASON");;
  *) usage;;
esac

if [ $APPLY -eq 0 ]; then
  if [ "$ACTION" = create ]; then
    echo "DRY as=$TANK (토큰 값은 출력하지 않는다)"
    bash "$HERE/ft-issue-create-pair.sh" "$@"; exit $?
  fi
  SHOW="${CMD[*]}"; [ -n "$COMMENT_FILE" ] && SHOW="$SHOW --comment <$COMMENT_FILE>"
  echo "DRY as=$TANK gh $SHOW"
  exit 0
fi

# ── 실행 경로: 토큰 → 작성자 확인 → gh ──
TOK="${FT_ISSUE_BOT_TOKEN:-}"
[ -n "$TOK" ] || { TFILE="${FT_ISSUE_BOT_TOKEN_FILE:-$HOME/.config/byz-harness/issue-bot.token}"; [ -r "$TFILE" ] && TOK="$(tr -d '[:space:]' < "$TFILE")"; }
[ -n "$TOK" ] || die "봇 토큰 없음 — FT_ISSUE_BOT_TOKEN 또는 ${FT_ISSUE_BOT_TOKEN_FILE:-$HOME/.config/byz-harness/issue-bot.token} (오빠 계정으로 폴백하지 않는다)" 2
WHO="$(GH_TOKEN="$TOK" gh api user --jq .login 2>/dev/null || true)"
[ "$WHO" = "$TANK" ] || die "토큰 주인이 $TANK 가 아니다(주인=${WHO:-확인 불가}) — 오빠 계정 토큰이면 즉시 폐기" 1

if [ "$ACTION" = create ]; then
  FT_ISSUE_BOT_TOKEN="$TOK" bash "$HERE/ft-issue-create-pair.sh" "$@" --apply; exit $?
fi
if [ "$ACTION" = edit ] || [ "$ACTION" = pr-edit ]; then
  # 수정 «전» 원문 보관 — 보관이 안 되면 수정 시도 0(#0 RULE: 조용히 건너뛰지 않는다)
  BAKDIR="${FT_ISSUE_EDIT_BAK_DIR:-}"
  if [ -z "$BAKDIR" ]; then
    COMMON="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
    [ -n "$COMMON" ] || die "보관 폴더를 정할 수 없다(git common dir 없음 · FT_ISSUE_EDIT_BAK_DIR 미지정) — 수정 시도 0" 1
    BAKDIR="$COMMON/.fable-team/state/issue-edit-bak"
  fi
  mkdir -p "$BAKDIR" || die "보관 폴더 생성 실패: $BAKDIR — 수정 시도 0" 1
  VIEW="$(GH_TOKEN="$TOK" gh "$EKIND" view "$NUM" -R "$REPO" --json title,body 2>&1)" || die "수정 전 원문 조회 실패 — 수정 시도 0: $VIEW" 1
  [ -n "$VIEW" ] || die "수정 전 원문 조회 응답이 비었다 — 수정 시도 0" 1
  BAK_BODY="$BAKDIR/$BAKPFX$NUM-$(date -u +%Y%m%dT%H%M%SZ).body.md"; BAK_TITLE="${BAK_BODY%.body.md}.title.txt"
  printf '%s' "$VIEW" | python3 -c 'import json,sys
d=json.load(sys.stdin); t=d["title"]; b=d["body"]
assert isinstance(t,str) and t and isinstance(b,str)
open(sys.argv[1],"w",encoding="utf-8",newline="").write(b)
open(sys.argv[2],"w",encoding="utf-8",newline="").write(t)' "$BAK_BODY" "$BAK_TITLE" 2>&1 \
    || die "수정 전 원문 보관 실패(응답 해석·쓰기) — 수정 시도 0: $VIEW" 1
  [ -s "$BAK_TITLE" ] && [ -f "$BAK_BODY" ] || die "보관 파일 확인 실패: $BAK_BODY — 수정 시도 0" 1
fi
if [ -n "$COMMENT_FILE" ]; then CMD+=(--comment "$(cat "$COMMENT_FILE")"); fi
if [ "$ACTION" = pr-create ]; then
  GH_TOKEN="$TOK" gh api "repos/$REPO/branches/$PR_HEAD" >/dev/null 2>&1 \
    || die "원격에 head 브랜치가 없다: $PR_HEAD — push 먼저(PR 생성 시도 0)" 1
fi
OUT="$(GH_TOKEN="$TOK" gh "${CMD[@]}" 2>&1)" || die "gh ${CMD[0]} ${CMD[1]} 실패: $OUT" 1
if [ "$ACTION" = pr-create ]; then
  PR_URL="$(grep -Eo 'https://[^ ]+/pull/[0-9]+' <<<"$OUT" | tail -1)"; NUM="${PR_URL##*/}"
  [[ "$NUM" =~ ^[0-9]+$ ]] || die "PR URL 해석 실패 — 출력: $OUT" 1
  AUTHOR="$(GH_TOKEN="$TOK" gh api "repos/$REPO/pulls/$NUM" --jq .user.login 2>/dev/null || true)"
  [ "$AUTHOR" = "$TANK" ] || die "PR 작성자가 $TANK 가 아니다(작성자=${AUTHOR:-확인 불가}) — $PR_URL" 1
  OUT="$PR_URL"
fi
if [ "$ACTION" = edit ] || [ "$ACTION" = pr-edit ]; then
  echo "OK as=$TANK $ACTION $NUM ${OUT:+— $OUT }bak=$BAK_BODY"
  echo "되돌림: bash $HERE/ft-gh-as-tank.sh $ACTION $NUM --body-file $BAK_BODY --title \"\$(cat $BAK_TITLE)\" --apply"
  exit 0
fi
echo "OK as=$TANK $ACTION ${NUM:-${1:-}} ${OUT:+— $OUT}"
