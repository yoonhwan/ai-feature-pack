#!/usr/bin/env bash
# ft-tank-verify.sh [--login byz-tank] [--repo ORG/REPO] [--invite] [--issue-test] — Tank 봇 계정 끝까지 점검
#   가입 → 리포 초대 → 토큰 → 토큰 주인 → 시험 Issue 작성자 5단계를 순서대로 «값으로» 확인한다. 앞 단계가 막히면 거기서 멈춘다(폴백 0).
#   기본 = 읽기 전용 점검. --invite 는 collaborator(triage) 초대 1건을 보낸다 · --issue-test 는 시험 Issue 를 만들고 작성자를 읽은 뒤 바로 닫는다.
#   토큰 = FT_ISSUE_BOT_TOKEN 또는 ~/.config/byz-harness/issue-bot.token (ft-issue-create-pair.sh 와 같은 위치) · 값은 출력하지 않는다.
#   exit 0 = 요청한 단계까지 전부 통과 · 1 = 어느 단계 FAIL(사유 stdout) · 2 = usage
set -uo pipefail
unset GH_TOKEN
LOGIN="byz-tank"; REPO="SecondWindStudio/byz-agents"; INVITE=0; ISSUE_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --login) LOGIN="${2:?--login 값 필요}"; shift 2;;
    --repo) REPO="${2:?--repo 값 필요}"; shift 2;;
    --invite) INVITE=1; shift;;
    --issue-test) ISSUE_TEST=1; shift;;
    *) echo "usage: $0 [--login L] [--repo O/R] [--invite] [--issue-test]" >&2; exit 2;;
  esac
done
step() { echo "[$1] $2"; }
fail() { echo "FAIL [$1] $2"; exit 1; }

step 1 "계정 존재: $LOGIN"
gh api "users/$LOGIN" --jq .login >/dev/null 2>&1 || fail 1 "계정 없음 — 오빠가 GitHub 에서 가입해야 한다"
echo "PASS [1]"

step 2 "리포 권한: $REPO"
PERM="$(gh api "repos/$REPO/collaborators/$LOGIN/permission" --jq .role_name 2>/dev/null || true)"
case "$PERM" in triage|write|maintain|admin) PERM_OK=1;; *) PERM_OK=0;; esac   # read 는 Issue 를 못 만든다
if [ "$PERM_OK" -ne 1 ]; then
  if [ $INVITE -eq 1 ]; then
    gh api -X PUT "repos/$REPO/collaborators/$LOGIN" -f permission=triage >/dev/null 2>&1 || fail 2 "초대 실패(권한 확인)"
    echo "[2] triage 권한 부여 요청 보냄 — 다시 점검해 반영 확인"
    PERM="$(gh api "repos/$REPO/collaborators/$LOGIN/permission" --jq .role_name 2>/dev/null || true)"
    case "$PERM" in triage|write|maintain|admin) ;; *) fail 2 "아직 권한 ${PERM:-없음} — $LOGIN 이 초대를 수락해야 한다";; esac
  else
    fail 2 "권한 부족(permission=${PERM:-없음}, triage 이상 필요) — --invite 로 올리거나 수락 대기"
  fi
fi
echo "PASS [2] permission=$PERM"

step 3 "토큰 파일"
TOK="${FT_ISSUE_BOT_TOKEN:-}"; TFILE="${FT_ISSUE_BOT_TOKEN_FILE:-$HOME/.config/byz-harness/issue-bot.token}"
if [ -z "$TOK" ]; then
  [ -r "$TFILE" ] || fail 3 "토큰 없음 — $TFILE (chmod 600) 또는 FT_ISSUE_BOT_TOKEN"
  MODE="$(stat -f '%Lp' "$TFILE" 2>/dev/null || stat -c '%a' "$TFILE" 2>/dev/null)"
  [ "$MODE" = "600" ] || fail 3 "토큰 파일 권한 $MODE — chmod 600 필요"
  TOK="$(tr -d '[:space:]' < "$TFILE")"
fi
[ -n "$TOK" ] || fail 3 "토큰이 비어 있다"
echo "PASS [3]"

step 4 "토큰 주인 = $LOGIN"
WHO="$(GH_TOKEN="$TOK" gh api user --jq .login 2>/dev/null || true)"
[ "$WHO" = "$LOGIN" ] || fail 4 "토큰 주인이 다르다(주인=${WHO:-확인 불가}) — 오빠 계정 토큰이면 즉시 폐기"
echo "PASS [4]"

if [ $ISSUE_TEST -eq 1 ]; then
  step 5 "시험 Issue 작성자"
  URL="$(GH_TOKEN="$TOK" gh issue create -R "$REPO" --title "[tank-verify] 작성자 점검 — 바로 닫음" --body "ft-tank-verify.sh 시험 Issue. 작성자가 $LOGIN 인지 확인한 뒤 닫는다." 2>&1)" || fail 5 "Issue 생성 실패: $URL"
  NUM="$(printf '%s' "$URL" | sed -n 's#.*/issues/\([0-9][0-9]*\).*#\1#p' | tail -1)"
  AUTH="$(gh api "repos/$REPO/issues/$NUM" --jq .user.login 2>/dev/null || true)"
  GH_TOKEN="$TOK" gh issue close "$NUM" -R "$REPO" -c "시험 완료" >/dev/null 2>&1 || echo "WARN 시험 Issue #$NUM 닫기 실패 — 손으로 닫을 것"
  [ "$AUTH" = "$LOGIN" ] || fail 5 "작성자=${AUTH:-확인 불가} (기대 $LOGIN) · Issue #$NUM"
  echo "PASS [5] issue=#$NUM author=$AUTH"
fi
echo "ALL PASS (login=$LOGIN)"
