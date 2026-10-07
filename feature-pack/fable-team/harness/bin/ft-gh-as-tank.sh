#!/usr/bin/env bash
# ft-gh-as-tank.sh <create|comment|label|close|reopen> … [--apply] — Issue 쓰기를 Tank 봇(byz-tank) 이름으로 실행하는 gh 래퍼
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
#   pr-comment <번호> <본문파일>
#   pr-create  <제목> <본문파일> [--base B] [--head H] — ★dry-run 전용★: Tank(triage) 권한으로 PR 생성이 되는지 «권한 미확인». --apply 는 exit 2(시험 금지)
#   (PR merge 는 래퍼·가드 대상이 아니다)
# exit 0 = 완료/dry-run · 1 = 실행 실패 또는 작성자 불일치(사유 stderr) · 2 = usage/토큰 없음
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}"
TANK="${FT_TANK_LOGIN:-byz-tank}"

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }
usage() { die "usage: $0 <create|comment|label|close|reopen|pr-comment|pr-create> … [--apply]" 2; }
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
    # 권한 미확인: byz-tank 은 triage 권한 — PR 생성 가능 여부를 실행으로 확인한 적 없다. 명령 출력만 지원.
    [ $APPLY -eq 0 ] || die "pr-create 는 dry-run 전용 — Tank(triage) 의 PR 생성 권한 미확인(실행 시험 금지)" 2
    [ $# -ge 2 ] || die "usage: $0 pr-create <제목> <본문파일> [--base B] [--head H]" 2
    T="$1"; need_file "$2"; CMD=(pr create -R "$REPO" --title "$T" --body-file "$2"); shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --base|--head) CMD+=("$1" "${2:?$1 값 필요}"); shift 2;;
        *) die "알 수 없는 인자: $1" 2;;
      esac
    done;;
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
if [ -n "$COMMENT_FILE" ]; then CMD+=(--comment "$(cat "$COMMENT_FILE")"); fi
OUT="$(GH_TOKEN="$TOK" gh "${CMD[@]}" 2>&1)" || die "gh ${CMD[0]} ${CMD[1]} 실패: $OUT" 1
echo "OK as=$TANK $ACTION ${NUM:-${1:-}} ${OUT:+— $OUT}"
