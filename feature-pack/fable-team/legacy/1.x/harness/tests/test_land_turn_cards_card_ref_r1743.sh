#!/usr/bin/env bash
# test_land_turn_cards_card_ref_r1743.sh — r1743: 착지 장부(land-record-turn.jsonl)와 [착지] 알림의 «카드» 칸을 루트 체크아웃 index 가 아니라 «카드 ref 트리» 에서 찾는다(계약 A1~A5 · 반례 ①~⑤)
#   세계 = 임시 git 리포 1개(루트 체크아웃 = main · 카드는 refs/remotes/origin/ops/main-base 에만 · 카드 루트 표 2행) · 실 PR·gh·tmux·fetch·sleep 0
#   [착지] 알림 = 발신 대역(fm_land_notify 를 시험에서 바꿔 «카드 인자» 만 본다 — mbox 실제 발신 0) · 변이 M1~M3 은 사본에서 따로 돈다
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; LIB="$BIN/ft-merge-lib.sh"; REC="$BIN/ft-nano-record.sh"
fail=0; rc=0; out=""; err=""
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: rc=$rc out=${out:0:220} err=${err:0:220}"; fail=$((fail + 1)); fi; }
run() { "$@" >"$T/o" 2>"$T/e"; rc=$?; out="$(cat "$T/o")"; err="$(cat "$T/e")"; }
n() { printf '%s\n' "$out" | grep -cE "$1"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; CARD="design/harness/indices/진행/r9001-x.md"; S2="design/harness/indices/완성/r9001-y.md"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q -b main "$R" || exit 1
mkdir -p "$R/.fable-team/state" "$R/design/harness/indices/진행" "$R/design/harness/indices/완성"
tbl() { printf '%s\n' "*	.	${2:-origin/main}	design/teams/*/indices" "harness	.	${1:-origin/ops/main-base}	design/harness/indices" > "$R/.fable-team/state/directive-roots.tsv"; }
tbl
printf 'seed\n' > "$R/design/harness/indices/진행/r0001-seed.md"
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" checkout -q -b cards
printf 'card\n' > "$R/$CARD"
printf 'boundary\n' > "$R/design/harness/indices/진행/ar9001-y.md"
printf 'boundary\n' > "$R/design/harness/indices/진행/r90011-z.md"
git -C "$R" add -A && git -C "$R" commit -qm cards
git -C "$R" update-ref refs/remotes/origin/ops/main-base HEAD
git -C "$R" checkout -q main && git -C "$R" update-ref refs/remotes/origin/main main
. "$LIB"

echo "### 사전: 카드 ref 에만 카드 · 루트(main)에는 0"
run git -C "$R" ls-files -- 'design/*/indices/*/*.md'
ck "사전 루트 index 에 r9001 카드 0" [ "$(n r9001)" = 0 ]

echo "### ① 카드 ref 출처(A1)"
run fm_cards_by_tokens "$R" r9001
ck "① 카드 ref 에서 1줄" [ "$out" = "$R/$CARD" ]

echo "### ⑤ 토큰 경계(규칙 그대로 · ls-tree 0회)"
ck "⑤ ar9001·r90011 안 잡힘" [ "$(n r9001-x)" = 1 ] && ck "⑤ 경계 카드 0줄" [ "$(n 'ar9001\|r90011')" = 0 ]
SHIM="$T/shim"; mkdir -p "$SHIM"; printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexec %s "$@"\n' "$T/git.log" "$(command -v git)" > "$SHIM/git"; chmod +x "$SHIM/git"
run env PATH="$SHIM:$PATH" bash -c '. "$1" >/dev/null; fm_cards_by_tokens "$2"' _ "$LIB" "$R"
ck "⑤ 토큰 0 = 출력 0" [ -z "$out" ]
ck "⑤ 토큰 0 = ls-tree 호출 0" [ ! -s "$T/git.log" ]

echo "### ④ 루트 체크아웃 index·디스크는 안 본다(A5)"
printf 'disk\n' > "$R/design/harness/indices/진행/r9002-disk.md"; git -C "$R" add -A
run fm_cards_by_tokens "$R" r9002
ck "④ index 에만 있는 카드 = 0줄" [ -z "$out" ]
git -C "$R" rm -q --cached "$R/design/harness/indices/진행/r9002-disk.md"; rm -f "$R/design/harness/indices/진행/r9002-disk.md"

echo "### ② 중복 제거(A2)"
git -C "$R" checkout -q cards && printf 'card\n' > "$R/$S2" && git -C "$R" add -A && git -C "$R" commit -qm stage2 && git -C "$R" update-ref refs/remotes/origin/ops/main-base HEAD
git -C "$R" checkout -q main && printf 'card\n' > "$R/$CARD" && git -C "$R" add -A && git -C "$R" commit -qm dup && git -C "$R" update-ref refs/remotes/origin/main HEAD
run fm_cards_by_tokens "$R" r9001
ck "② 같은 파일 두 ref = 1줄" [ "$(n '진행/r9001-x.md')" = 1 ] && ck "② 다른 단계 = 2줄" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ]
ck "② 다른 단계 줄 = <루트>/<경로>" [ "$(n "$R/$S2")" = 1 ]

echo "### ③ 판정 불가(A3)"
tbl origin/ops/main-base origin/ops/nonexist
run fm_cards_by_tokens "$R" r9001
ck "③ 일부 ref 실패 = 나머지 ref 결과 그대로(2줄)" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && ck "③ 일부 실패 = FM_CARDS_ERR 빈 값" [ -z "${FM_CARDS_ERR:-}" ]
ck "③ 일부 ref 실패 = stderr WARN 1줄" [ "$(printf '%s\n' "$err" | grep -c '^WARN 카드 ref 일부')" = 1 ]
tbl origin/ops/nonexist1 origin/ops/nonexist2
run fm_cards_by_tokens "$R" r9001
ck "③ ref 전부 못 읽음 = stdout 0" [ -z "$out" ] && ck "③ FM_CARDS_ERR 채움 + WARN" [ -n "${FM_CARDS_ERR:-}" ]
ck "③ stderr WARN cards_err 1줄" [ "$(printf '%s\n' "$err" | grep -c '^WARN cards_err: ')" = 1 ]
( Q="$(git -C "$R" rev-parse HEAD)"; HEADSHA="$Q"; REPO="$R"; TARGET=main; FT_SEAT=byz-harness-nano-x#0
  fm_land_turn "$R" 9001 0 r9001 ) >/dev/null 2>&1
L="$R/.fable-team/state/land-record-turn.jsonl"
ck "③ 장부 줄에 cards_err" grep -q '"cards_err": "카드 ref 를 하나도 못 읽음' "$L"
run env FT_ROOT="$R" bash "$REC" due --pr 9001 --no-fetch
ck "③ due = «판정 불가 카드 ref»" [ "$(n '^판정 불가 카드 ref ')" = 1 ] && ck "③ due rc=3" [ "$rc" = 3 ]
ck "③ due 에 «카드 없음» 글자 0" [ "$(n '카드 없음')" = 0 ]

echo "### A4 [착지] 알림도 같은 함수 결과"
tbl
run env REC="$REC" FM_NOTIFY_REPO="$R" FT_SEAT=byz-harness-nano-x#0 bash -c '. "$1" >/dev/null; eval "$2"' _ "$LIB" \
  "fm_land_notify() { printf 'NOTIFY road=%s cards=%s\n' \"\$1\" \"\$(shift 2; printf '%s ' \"\$@\")\"; }; fm_land_notify_land \"$R\" 9001 deadbeef 'PR r9001 제목' 0 'OK n=1'"
ck "A4 알림 카드 = 카드 ref 결과 그대로" [ "$(n 'cards=.*진행/r9001-x.md')" = 1 ] && ck "A4 알림 꼴 그대로" [ "$(n 'NOTIFY road=착지')" = 1 ]

echo "### 회귀: 같은 ref 를 두 행에 적어도 1줄"
tbl origin/main origin/main
run fm_cards_by_tokens "$R" r9001
ck "회귀 같은 ref 2행 = 1줄" [ "$(n '진행/r9001-x.md')" = 1 ]
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
