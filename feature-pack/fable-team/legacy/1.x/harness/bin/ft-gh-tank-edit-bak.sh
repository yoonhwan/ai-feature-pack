#!/usr/bin/env bash
# ft-gh-tank-edit-bak.sh <kind issue|pr> <번호> <접두> — Issue·PR 수정 «전» 현재 제목·본문을 보관 폴더에 저장한다(ft-gh-as-tank.sh edit·pr-edit 의 보관 단계 본체)
#
# 왜 있나: 래퍼가 200줄 한도를 넘어 «수정 전 원문 보관» 블록을 떼어 냈다(원장 R236 · 동작 변경 0). 보관이 안 되면 수정 시도 0 — 조용히 건너뛰지 않는다(#0 RULE).
# 토큰 = env FT_TANK_TOK 로만 받는다(인자·출력 0). env: REPO(없으면 FT_ISSUE_REPO) · FT_ISSUE_EDIT_BAK_DIR 는 래퍼와 같은 이름·기본값.
# 출력(stdout) = 성공 시 1줄 `BAK_BODY=<본문 보관 파일>` (제목 파일은 같은 이름의 .title.txt) · 실패 사유는 stderr `REJECT …`
# exit 0 = 보관 완료 · 1 = 보관 실패(사유 stderr · 수정 시도 0) · 2 = usage/토큰 없음
set -uo pipefail
unset GH_TOKEN
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${REPO:-${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}}"

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }

[ $# -eq 3 ] || die "usage: $0 <issue|pr> <번호> <접두>" 2
EKIND="$1"; NUM="$2"; BAKPFX="$3"
case "$EKIND" in issue|pr) ;; *) die "kind 는 issue|pr: $EKIND" 2;; esac
[[ "$NUM" =~ ^[0-9]+$ ]] || die "번호(정수) 필요: $NUM" 2
TOK="${FT_TANK_TOK:-}"
[ -n "$TOK" ] || die "FT_TANK_TOK 없음 — 오빠 계정으로 폴백하지 않는다" 2

BAKDIR="${FT_ISSUE_EDIT_BAK_DIR:-}"
if [ -z "$BAKDIR" ]; then
  COMMON="$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE")"   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
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
echo "BAK_BODY=$BAK_BODY"
