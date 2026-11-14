#!/usr/bin/env bash
# test_team_has_card_ref_r1977.sh — r1977: harness 카드(카드 리포 ref 트리 design/harness/indices/…)를 ft_team_has 가 harness 로 판정한다
#   세계 = 임시 git 리포 1개(카드는 refs/remotes/origin/ops/main-base 에만) + 가짜 FT_HARNESS_ROOT 폴더(git 아님) + 리포 밖 폴더
#   실 리포·Slack·장부·우편함 0(FT_MBOX = 시험 대역) · fetch·sleep 0 · 변이는 bin 사본에서(R1977_BIN env 로 바꿔 끼움)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${R1977_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0
ck() { local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "PASS $l"; else echo "FAIL $l :: rc=$rc"; fail=$((fail + 1)); fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
R="$T/repo"; P="$T/pack"; CARD="design/harness/indices/대기/r99-x.md"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$T/mbox.log" > "$T/mbox.sh"; export FT_MBOX="$T/mbox.sh"
mkdir -p "$P/design/harness/indices/대기" "$T/outside/design/harness/indices" && export FT_HARNESS_ROOT="$P"
git init -q -b main "$R" || exit 1
mkdir -p "$R/design/teams/planner/indices/대기" "$R/.fable-team/state"
printf '| 팀 | 폴더 |\n|---|---|\n| harness | `$FT_HARNESS_ROOT/design/harness/` |\n| planner | `design/teams/planner/` |\n' > "$R/design/TEAMS.md"
printf 'harness\t.\torigin/ops/main-base\tdesign/harness/indices\n' > "$R/.fable-team/state/directive-roots.tsv"
printf '{"_master": "byz-harness-master-t#0"}\n' > "$R/.fable-team/seats-harness.json"
git -C "$R" add design && git -C "$R" commit -qm init && git -C "$R" update-ref refs/remotes/origin/main HEAD
git -C "$R" checkout -q -b cards && mkdir -p "$R/${CARD%/*}" && printf 'card\n' > "$R/$CARD" && git -C "$R" add -A design && git -C "$R" commit -qm cards
git -C "$R" update-ref refs/remotes/origin/ops/main-base HEAD && git -C "$R" checkout -q main
has() { ( . "$BIN/ft-team-lib.sh"; FT_REPO_ROOT="$R" ft_team_has "$@" ) >/dev/null 2>&1; rc=$?; }

echo "### 사전: 카드는 디스크에 없다(ref 트리에만)"
ck "사전 디스크 카드 없음" [ ! -e "$R/$CARD" ]

echo "### ① BYZ 꼴 리포 카드 + FT_HARNESS_ROOT = 다른 폴더 → rc 0"
has harness "$R/$CARD"; ck "① rc 0" [ "$rc" = 0 ]

echo "### ② 팩 legacy 꼴 경로(지금 통과 꼴) → rc 0 그대로"
has harness "$P/design/harness/indices/대기/r99-x.md"; ck "② rc 0" [ "$rc" = 0 ]

echo "### ③ 다른 팀 카드 → harness rc 1(가운데 design/harness/ 가 끼어도)"
has harness "$R/design/teams/planner/indices/대기/r98-p.md"; ck "③ planner rc 1" [ "$rc" = 1 ]
has harness "$R/design/teams/planner/indices/design/harness/r97.md"; ck "③ 가운데 design/harness rc 1" [ "$rc" = 1 ]
has planner "$R/design/teams/planner/indices/대기/r98-p.md"; ck "③ planner 팀은 rc 0(다른 갈래 그대로)" [ "$rc" = 0 ]

echo "### ④ 리포 밖 경로(git 최상위 못 읽음) → rc 2"
has harness "$T/outside/design/harness/indices/r96.md"; ck "④ rc 2" [ "$rc" = 2 ]

echo "### ⑤ fm_land_notify_land 끝 = NOTIFIED 착지 → harness master(가짜 mbox)"
out="$( cd "$R" && . "$BIN/ft-merge-lib.sh" && unset FT_REPO_ROOT FT_ROOT; Q="$(git -C "$R" rev-parse HEAD)"; M="$Q"; HEADSHA="$Q"; REPO="$R"; TARGET=main
  fm_land_notify_land "$R" 1 "${Q:0:10}" 'r99 고침' 0 'OK n=1' nano/r99-x 2>&1 )"
ck "⑤ NOTIFIED 착지 → byz-harness-master-t#0 1줄" [ "$(grep -c '^NOTIFIED 착지 → byz-harness-master-t#0$' <<<"$out")" = 1 ]
ck "⑤ «팀 못 정함» 0" [ "$(grep -c '팀 못 정함' <<<"$out")" = 0 ]
ck "⑤ 가짜 mbox 에 [착지] 1줄" grep -q '^send byz-harness-master-t#0 .*\[착지\] pr=1 .*카드 r99' "$T/mbox.log"

echo "### 짝 사본"
ck "bin·kit cmp0(ft-team-lib)" cmp -s "$HERE/../bin/ft-team-lib.sh" "$KIT/ft-team-lib.sh"
printf '### 결과: %s\n' "$([ "$fail" = 0 ] && echo PASS || echo "FAIL $fail")"
[ "$fail" = 0 ]
