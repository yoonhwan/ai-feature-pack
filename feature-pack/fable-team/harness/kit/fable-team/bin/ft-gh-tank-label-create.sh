#!/usr/bin/env bash
# ft-gh-tank-label-create.sh <이름> <6hex색> [<설명>] — 저장소 라벨 1건을 byz-tank 이름으로 만든다(ft-gh-as-tank.sh label-create 의 본체)
#
# 왜 있나: 래퍼에 Issue 에 라벨을 «붙이는» 동사만 있고 저장소 라벨을 «만드는» 동사가 없어, 새 라벨(team:graphics·security 등)이 좌석의
#   직접 `gh label create` → 오빠 계정으로 만들어졌다(10-09 R68). 인자 검증·토큰 주인 확인은 래퍼가 이미 했다.
# 토큰 = env FT_TANK_TOK 로만(인자·출력 0 · 없으면 exit 2). env FT_ISSUE_REPO · FT_TANK_LOGIN 은 래퍼와 같은 이름·기본값.
# ★이미 있는 라벨은 «바꾸지 않고» EXISTS 로만 알린다(멱등 · exit 0) — 색·설명 덮어쓰기·삭제 동작은 없다.
# 순서: ⓐ이름 1건 조회(GET labels/<이름>) 200=EXISTS · 404=ⓑ · 401/403=REJECT 권한 없음 · 그 밖=REJECT
#       ⓑPOST labels — 성공=OK · 422(그새 남이 만듦)=ⓐ 한 번 더 → EXISTS · 401/403=REJECT
#       ⓒ외부 호출은 각 1회 7초(timeout 7) · 재시도 1(시간 초과 rc 124·5xx 만) — 7초 룰(판정 666)
# exit 0 = OK/EXISTS · 1 = 실행 실패/권한 없음(사유 stderr) · 2 = usage/토큰 없음
set -uo pipefail
unset GH_TOKEN
REPO="${FT_ISSUE_REPO:-SecondWindStudio/byz-agents}"
TANK="${FT_TANK_LOGIN:-byz-tank}"

die() { echo "REJECT $1" >&2; exit "${2:-1}"; }

[ $# -ge 2 ] && [ $# -le 3 ] || die "usage: $0 <이름> <6hex색> [<설명>]" 2
NAME="$1"; COLOR="$2"; DESC="${3:-}"
TOK="${FT_TANK_TOK:-}"
[ -n "$TOK" ] || die "FT_TANK_TOK 없음 — 오빠 계정으로 폴백하지 않는다" 2
ENC="$(python3 -c 'import sys,urllib.parse
print(urllib.parse.quote(sys.argv[1],safe=""))' "$NAME")" || die "이름 URL 인코딩 실패: $NAME" 1

# gh_call <gh api 인자…> → RAW(stdout+stderr) · RC. 시간 초과(124)·5xx 만 1회 재시도.
gh_call() {
  local n=0
  while :; do
    RAW="$(GH_TOKEN="$TOK" timeout 7 gh api "$@" 2>&1)"; RC=$?
    if [ $RC -ne 0 ] && { [ $RC -eq 124 ] || grep -qE 'HTTP 5[0-9][0-9]' <<<"$RAW"; } && [ $n -lt 1 ]; then n=1; continue; fi
    return 0
  done
}
# denied: 401/403 이면 REJECT 권한 없음(HTTP N) · exit 1
denied() {
  local code; code="$(grep -oE 'HTTP 40[13]' <<<"$RAW" | head -1)"
  [ -z "$code" ] || die "권한 없음(${code}) — Tank 토큰 Issues 쓰기 권한 확인" 1
}
fail() { die "$1 실패(rc=$RC): ${RAW:0:200}" 1; }
# lookup: 0 = 있음(EXISTS 줄 출력 · exit 0) · 1 = 없음(404) · 그 밖 = REJECT
lookup() {
  gh_call "repos/$REPO/labels/$ENC"
  if [ $RC -eq 0 ]; then
    CUR="$(printf '%s' "$RAW" | python3 -c 'import json,sys
c=json.load(sys.stdin)["color"]; assert isinstance(c,str) and c
print(c)' 2>&1)" || die "조회 응답 해석 실패: ${CUR:0:200}" 1
    echo "EXISTS as=$TANK label $NAME color=$CUR"; return 0
  fi
  denied
  grep -q 'HTTP 404' <<<"$RAW" && return 1
  fail "라벨 조회"
}

lookup && exit 0

ARGS=(-X POST "repos/$REPO/labels" -f "name=$NAME" -f "color=$COLOR")
[ -n "$DESC" ] && ARGS+=(-f "description=$DESC")
gh_call "${ARGS[@]}"
if [ $RC -eq 0 ]; then
  URL="$(printf '%s' "$RAW" | python3 -c 'import json,sys
d=json.load(sys.stdin); print(d.get("html_url") or d.get("url") or "")' 2>/dev/null || true)"
  echo "OK as=$TANK label-create $NAME${URL:+ — $URL}"; exit 0
fi
denied
if grep -q 'HTTP 422' <<<"$RAW"; then
  lookup && exit 0
  die "라벨 생성 422 인데 재조회에도 없다: ${RAW:0:200}" 1
fi
fail "라벨 생성"
