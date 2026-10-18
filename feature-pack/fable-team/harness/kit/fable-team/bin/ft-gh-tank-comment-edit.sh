#!/usr/bin/env bash
# ft-gh-tank-comment-edit.sh <comment_id> <본문파일> — byz-tank 이 쓴 Issue 코멘트 1개의 본문을 교체한다(ft-gh-as-tank.sh comment-edit 의 본체)
#
# 왜 있나: 래퍼에 Issue 코멘트 수정이 없어 issues 팀이 자기(byz-tank) 코멘트의 정본 줄을 못 고쳤다(원장 R59 · 쪽지 65989).
#   직접 `gh api …/issues/comments` 쓰기는 gh-issue-author-guard.sh 가 막으므로 래퍼 → 이 스크립트 경로로만 나간다.
# 토큰 = env FT_TANK_TOK 로만 받는다(인자·출력 0 · 없으면 exit 2). 토큰 주인 확인은 래퍼가 이미 했다.
# env: FT_ISSUE_REPO · FT_TANK_LOGIN · FT_ISSUE_EDIT_BAK_DIR 는 래퍼와 같은 이름·기본값.
# 순서(앞 단계가 실패하면 수정 시도 0 · exit 1): ⓐ코멘트 조회 → ⓑ작성자가 Tank 인지 → ⓒ원문 보관 → ⓓPATCH → ⓔ응답 본문 = 파일 확인
# exit 0 = 완료 · 1 = 실행 실패/작성자 불일치(사유 stderr) · 2 = usage/토큰 없음
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}"
TANK="${FT_TANK_LOGIN:-byz-tank}"

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }

[ $# -eq 2 ] || die "usage: $0 <comment_id> <본문파일>" 2
ID="$1"; FILE="$2"
[[ "$ID" =~ ^[0-9]+$ ]] || die "코멘트 id(정수) 필요: $ID" 2
[ -f "$FILE" ] || die "본문 파일이 없다: $FILE" 2
TOK="${FT_TANK_TOK:-}"
[ -n "$TOK" ] || die "FT_TANK_TOK 없음 — 오빠 계정으로 폴백하지 않는다" 2

# ⓐ 조회 — 실패·빈 응답·해석 실패 = 수정 시도 0
RAW="$(GH_TOKEN="$TOK" gh api "repos/$REPO/issues/comments/$ID" 2>&1)" || die "코멘트 조회 실패 — 수정 시도 0: $RAW" 1
META="$(printf '%s' "$RAW" | python3 -c 'import json,sys
d=json.load(sys.stdin); u=d["user"]["login"]; h=d["html_url"]; b=d["body"]
assert isinstance(u,str) and u and isinstance(h,str) and h and isinstance(b,str)
print(u); print(h)' 2>&1)" || die "코멘트 응답 해석 실패 — 수정 시도 0: $META" 1
LOGIN="${META%%$'\n'*}"; URL="${META#*$'\n'}"

# ⓑ 작성자 확인
[ "$LOGIN" = "$TANK" ] || die "코멘트 작성자가 $TANK 가 아니다(작성자=$LOGIN) — 수정 시도 0" 1

# ⓒ 수정 «전» 원문 보관 — 보관이 안 되면 수정 시도 0(래퍼 edit 와 같은 폴더 규칙)
BAKDIR="${FT_ISSUE_EDIT_BAK_DIR:-}"
if [ -z "$BAKDIR" ]; then
  COMMON="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
  [ -n "$COMMON" ] || die "보관 폴더를 정할 수 없다(git common dir 없음 · FT_ISSUE_EDIT_BAK_DIR 미지정) — 수정 시도 0" 1
  BAKDIR="$COMMON/.fable-team/state/issue-edit-bak"
fi
mkdir -p "$BAKDIR" || die "보관 폴더 생성 실패: $BAKDIR — 수정 시도 0" 1
BAK="$BAKDIR/comment$ID-$(date -u +%Y%m%dT%H%M%SZ).body.md"
printf '%s' "$RAW" | python3 -c 'import json,sys
open(sys.argv[1],"w",encoding="utf-8",newline="").write(json.load(sys.stdin)["body"])' "$BAK" 2>&1 \
  || die "수정 전 원문 보관 실패(쓰기) — 수정 시도 0: $BAK" 1
[ -f "$BAK" ] || die "보관 파일 확인 실패: $BAK — 수정 시도 0" 1

# ⓓ 수정 — 본문은 -f/-F 인자가 아니라 JSON stdin 으로(형 변환·길이 문제 회피)
RESP="$(python3 -c 'import json,sys
print(json.dumps({"body":open(sys.argv[1],encoding="utf-8",newline="").read()}))' "$FILE" \
  | GH_TOKEN="$TOK" gh api -X PATCH "repos/$REPO/issues/comments/$ID" --input - 2>&1)" || die "코멘트 PATCH 실패: $RESP (원문 bak=$BAK)" 1

# ⓔ 응답 본문 = 파일 확인
printf '%s' "$RESP" | python3 -c 'import json,sys
want=open(sys.argv[1],encoding="utf-8",newline="").read()
sys.exit(0 if json.load(sys.stdin).get("body")==want else 1)' "$FILE" 2>/dev/null \
  || die "PATCH 응답 본문이 파일과 다르다 — 확인 필요 (원문 bak=$BAK)" 1

echo "OK as=$TANK comment-edit $ID — $URL bak=$BAK"
echo "되돌림: bash $HERE/ft-gh-as-tank.sh comment-edit $ID $BAK --apply"
