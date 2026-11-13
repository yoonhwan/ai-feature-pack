#!/usr/bin/env bash
# test_land_card_root_r1821.sh — r1821: 착지 장부 카드 찾기가 FT_ROOT=라이브 worktree 여도 git common root 의 카드 위치 표를 읽는다(C1)
#   · 토큰이 있는데 카드 0장이면 cards_err(C2) · 착지 결과 «카드 root=… 표=… refs=… cards=…» 1줄(C3) · 담당 경로 그대로(C4)
#   세계 = 임시 git 리포 1개 + worktree 1개(표 = 공용 root 작업 폴더에만 · 커밋 0) · 카드 = refs/remotes/origin/ops/main-base 대역에만
#   실 Slack·launchd·장부·우편함 0(FT_MBOX = 시험 대역) · fetch·sleep 0 · 변이 M1~M4 는 사본에서 따로 돈다(R1821_LIB env 로 바꿔 끼움)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; LIB="${R1821_LIB:-$BIN/ft-merge-lib.sh}"; REC="$BIN/ft-nano-record.sh"
fail=0; rc=0; out=""; err=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: rc=$rc out=${out:0:220} err=${err:0:220}"; fail=$((fail + 1)); fi; }
run() { "$@" >"$T/o" 2>"$T/e"; rc=$?; out="$(cat "$T/o")"; err="$(cat "$T/e")"; }
n() { printf '%s\n' "$out" | grep -cE -- "$1"; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; W="$T/live-wt"; CARD="design/harness/indices/진행/r1801-x.md"; ALT="design/harness/indices/진행/r1802-alt.md"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$T/mbox.log" > "$T/mbox.sh"; export FT_MBOX="$T/mbox.sh"
git init -q -b main "$R" || exit 1
mkdir -p "$R/design/harness/indices/진행"; printf 'seed\n' > "$R/design/harness/indices/진행/r0001-seed.md"
git -C "$R" add -A && git -C "$R" commit -qm init && git -C "$R" update-ref refs/remotes/origin/main main
git -C "$R" checkout -q -b cards && printf 'card\n' > "$R/$CARD" && git -C "$R" add -A && git -C "$R" commit -qm cards
git -C "$R" update-ref refs/remotes/origin/ops/main-base HEAD
git -C "$R" checkout -q -b alt main && printf 'alt\n' > "$R/$ALT" && git -C "$R" add -A && git -C "$R" commit -qm alt
git -C "$R" update-ref refs/remotes/origin/ops/alt HEAD && git -C "$R" checkout -q main
git -C "$R" worktree add -q --detach "$W" main || exit 1
TB="$R/.fable-team/state/directive-roots.tsv"; WT="$W/.fable-team/state/directive-roots.tsv"
tbl() { mkdir -p "${1%/*}"; printf '%s\n' "*	.	${3:-origin/main}	design/teams/*/indices" "harness	.	$2	design/harness/indices" > "$1"; }
tbl "$TB" origin/ops/main-base
. "$LIB"
turn() { ( Q="$(git -C "$R" rev-parse HEAD)"; HEADSHA="$Q"; REPO="$R"; TARGET=main; FT_SEAT=byz-harness-nano-x#0; fm_land_turn "$W" "$1" 0 "${@:2}" ); }
L="$R/.fable-team/state/land-record-turn.jsonl"

echo "### 사전: worktree 에는 표·카드 파일 0"
ck "사전 worktree 표 없음" [ ! -e "$WT" ] && ck "사전 worktree 디스크에 r1801 카드 없음" [ ! -e "$W/$CARD" ]

echo "### ① worktree root + 공용 표 + 카드는 ops/main-base 에만 → 1장(C1)"
run fm_cards_by_tokens "$W" r1801
ck "① 카드 1줄" [ "$(n 'indices/진행/r1801-x.md$')" = 1 ] && ck "① stdout 은 카드 경로만" [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ]
ck "① cards_err 빈 값" [ -z "${FM_CARDS_ERR:-}" ]

echo "### ①′ root 자신의 표가 먼저(C1 · 공용 표와 다른 ref)"
tbl "$WT" origin/ops/alt
run fm_cards_by_tokens "$W" r1802
ck "①′ root 표 ref(origin/ops/alt)의 카드 1줄" [ "$(n 'indices/진행/r1802-alt.md$')" = 1 ]
rm -rf "$W/.fable-team"

echo "### ② 토큰 r9999 · 어느 ref 에도 카드 없음 → cards_err(C2)"
run fm_cards_by_tokens "$W" r9999
ck "② stdout 0" [ -z "$out" ]
ck "② FM_CARDS_ERR «토큰 r9999 카드 0장 · 읽은 ref … · 표 …»" eval '[[ "${FM_CARDS_ERR:-}" == "토큰 r9999 카드 0장 · 읽은 ref "*origin/ops/main-base*" · 표 $TB" ]]'
turn 9999 r9999 >/dev/null 2>&1
ck "② 장부 줄 cards_err «카드 0장»" grep -q '"pr": 9999, .*"cards": \[\], .*"cards_err": "토큰 r9999 카드 0장' "$L"
run env FT_ROOT="$R" bash "$REC" due --pr 9999 --no-fetch
ck "② due = «판정 불가 카드 ref»" [ "$(n '^판정 불가 카드 ref ')" = 1 ] && ck "② due 에 «카드 없음» 행 0" [ "$(n '카드 없음')" = 0 ]

echo "### ②′ 토큰 0 → 출력 0 · cards_err 0"
run fm_cards_by_tokens "$W"
ck "②′ stdout 0" [ -z "$out" ] && ck "②′ FM_CARDS_ERR 빈 값" [ -z "${FM_CARDS_ERR:-}" ]

echo "### ③ 착지 결과 줄 네 칸(C3 · 카드 stdout 과 섞지 않음)"
run turn 1801 r1801
ck "③ «카드 root=<W> 표=<공용 표> refs=<목록> cards=1» 1줄" [ "$(n "^카드 root=$W 표=$TB refs=origin/main,origin/ops/main-base cards=1\$")" = 1 ]
run fm_cards_by_tokens "$W" r1801
ck "③ fm_cards_by_tokens stdout 에 진단 줄 0" [ "$(n '^카드 root=')" = 0 ]

echo "### ④ 카드 찾음 = 카드 경로(C4) · ref 전부 못 읽음 = 지금 cards_err(회귀)"
ck "④ 장부 줄에 카드 경로 · cards_err 없음" grep -q '"pr": 1801, .*진행/r1801-x.md"\]' "$L" && ! grep -q '"pr": 1801, .*cards_err' "$L"
tbl "$TB" origin/ops/nonexist1 origin/ops/nonexist2
for rt in "$R" "$W"; do
  run fm_cards_by_tokens "$rt" r1801
  ck "④ ${rt##*/} stdout 0" [ -z "$out" ] && ck "④ ${rt##*/} FM_CARDS_ERR «카드 ref 를 하나도 못 읽음»" eval '[[ "${FM_CARDS_ERR:-}" == "카드 ref 를 하나도 못 읽음"* ]]'
done
ck "④ 우편함 대역만 씀(실 발신 0)" [ ! -e "$R/.fable-team/comm/.mbox-seq" ]

printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
