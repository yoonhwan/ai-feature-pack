#!/usr/bin/env bash
# test_land_card_tokens_r1848.sh — r1848: 착지 카드 토큰 = ⓐ head `nano/r<N>-` 의 r<N> 하나 ⓑ 아니면 PR 제목 r 토큰 · 본문 토큰 0
#   세계 = 임시 git 리포(카드는 refs/remotes/origin/ops/main-base 에만) · ft-merge-land.sh 의 실제 fm_land_notify_land 호출 줄을 떼어 eval
#   pf = 대역(PR JSON 대신) · fm_land_notify = 대역(쪽지 «카드» 칸만 기록 · mbox 0) · 실 PR·gh·장부·fetch·sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_R1848_BIN:-$HERE/../bin}"; LIB="$BIN/ft-merge-lib.sh"; LAND="$BIN/ft-merge-land.sh"; KIT="$HERE/../kit/fable-team/bin"
fail=0
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: ${ROW:-}"; fail=$((fail + 1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; IX="design/harness/indices/진행"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main "$R" || exit 1
mkdir -p "$R/.fable-team/state" "$R/$IX"
printf '%s\n' "harness	.	origin/ops/main-base	design/harness/indices" > "$R/.fable-team/state/directive-roots.tsv"
printf 'seed\n' > "$R/README" && git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" update-ref refs/remotes/origin/main HEAD
for c in r1840-x r1812-a r1813-b r1844-c r1845-d; do printf 'card\n' > "$R/$IX/$c.md"; done
git -C "$R" add -A && git -C "$R" commit -qm cards && git -C "$R" update-ref refs/remotes/origin/ops/main-base HEAD
CALL="$(grep -m1 '^fm_land_notify_land ' "$LAND" | sed 's/; HLTO=.*//')"
ck "사전 착지 호출 줄 1개" [ -n "$CALL" ]
L="$R/.fable-team/state/land-record-turn.jsonl"
case_run() {  # case_run <PR> <head> <제목> <본문> → ROW = 장부 cards 토큰 · NOTE = 쪽지 줄
  ( . "$LIB" >/dev/null 2>&1; FM_HERE="$T/no-bin"
    fm_land_notify() { printf '%s | %s\n' "$2" "$(shift 2; printf '%s ' "$@")" >>"$T/note"; }
    PH="$2" PT="$3" PB="$4"; pf() { case "$1" in headRefName) printf '%s' "$PH";; title) printf '%s' "$PT";; body) printf '%s' "$PB";; esac; }
    ROOT="$R" PR="$1" Q="$(git -C "$R" rev-parse HEAD)" M="$Q" HEADSHA="$Q" REPO="$R" TARGET=main irc=0 IOUT='OK n=1'
    eval "$CALL" ) >/dev/null 2>&1
  ROW="$(python3 -c 'import json,sys,re
for l in open(sys.argv[1]):
  d=json.loads(l)
  if d["pr"]==int(sys.argv[2]): print(" ".join(sorted(re.search(r"/(r\d+)-",c).group(1) for c in d["cards"])), "ERR" if d.get("cards_err") else "")' "$L" "$1")"
  ROW="${ROW% }"; NOTE="$(grep "pr=$1 " "$T/note" 2>/dev/null)"
}

echo "### ① 나노 가지 = 가지 토큰 1장(본문 r1812·r1813 무시)"
case_run 1 nano/r1840-x 'r1840 착지 고침' '겹침 대조 r1812 · r1813 · 근거 r1840'
ck "① 장부 cards = r1840" [ "$ROW" = r1840 ]
ck "① 쪽지 카드 칸 = r1840 만" grep -qF "카드 r1840 · 설치" <<<"$NOTE"
ck "① 쪽지 카드 경로 = r1840 1장" [ "$(grep -o 'r18[0-9][0-9]-' <<<"${NOTE#*|}" | sort -u)" = r1840- ]

echo "### ② 나노 가지 아님 = 제목 토큰(본문 r1812 무시)"
case_run 2 ops/foo 'r1844·r1845 묶음' '참고 r1812'
ck "② 장부 cards = r1844 r1845" [ "$ROW" = "r1844 r1845" ]
ck "② 쪽지 카드 칸 = r1844 r1845" grep -qF "카드 r1844 r1845 · 설치" <<<"$NOTE"

echo "### ③ 가지·제목 토큰 0 = cards [] · «카드 없음» 1통(지금 규칙)"
case_run 3 chore/x '코드만' '본문 r1812'
ck "③ 장부 cards = [] · cards_err 없음" [ "$ROW" = "" ]
ck "③ 장부 줄 1개" [ "$(grep -c '"pr": 3,' "$L")" = 1 ]
ck "③ 쪽지 «카드 없음» 1통" [ "$(grep -c 'pr=3 .*카드 없음 · 설치' "$T/note")" = 1 ]

echo "### 경계: 가지 nano/r1840 뒤에 '-' 없음 = 나노 꼴 아님 → 제목"
case_run 4 nano/r1840 'r1844 제목' '본문 r1812'
ck "경계 장부 cards = r1844" [ "$ROW" = r1844 ]

echo "### 짝 사본"
ck "bin·kit cmp0(ft-merge-land)" cmp -s "$HERE/../bin/ft-merge-land.sh" "$KIT/ft-merge-land.sh"
ck "bin·kit cmp0(ft-merge-lib)" cmp -s "$HERE/../bin/ft-merge-lib.sh" "$KIT/ft-merge-lib.sh"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
