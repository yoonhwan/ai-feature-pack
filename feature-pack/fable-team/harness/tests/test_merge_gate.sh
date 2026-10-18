#!/usr/bin/env bash
# test_merge_gate.sh — ft-merge-gate.sh 게이트 시험 (R230 · 임시 origin+clone 픽스처만)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; GATE="$BIN/ft-merge-gate.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:260}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
gate() { out="$(bash "$GATE" "$@" --repo "$W" --base-head-file "${BHF:-$T/none}" 2>&1)"; rc=$?; }
allow() { gate "$1"; [ "$rc" = 0 ] && [[ "$out" == ALLOW* ]]; ck "$2" $?; }
deny() { gate "$1"; [ "$rc" = 1 ] && [[ "$out" == DENY* ]] && [[ "$out" == *"$3"* ]]; ck "$2" $?; }

bash -n "$GATE"; ck "bash -n gate" $?; python3 -I -c "import ast,sys;ast.parse(open('$BIN/ft_merge_lines.py').read())"; ck "py 구문 lines" $?

mkrepo "$T"
git -C "$W" checkout -q -b old; echo c > "$W/c.txt"; cm "$W" "old work"           # M0 에서 딴 옛 브랜치
for b in oldmerged oldours oldmoved; do git -C "$W" branch "$b" old; done
git -C "$W" checkout -q main
printf 'l1\nMAIN-LINE\nl2\nl3\n' > "$W/a.txt"; echo n > "$W/n.txt"; printf '\0\1\2' > "$W/img.bin"
cm "$W" "main adds"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
M1="$(sha "$W" HEAD)"
git -C "$W" checkout -q oldmerged; git -C "$W" merge -q --no-edit origin/main
git -C "$W" checkout -q oldours;   git -C "$W" merge -q -s ours --no-edit origin/main     # main 을 포함하지만 줄은 옛 트리 그대로
git -C "$W" checkout -q oldmoved;  git -C "$W" merge -q --no-edit origin/main
printf 'l1\nl2\nl3\nMAIN-LINE\n' > "$W/a.txt"; cm "$W" "move line to end"
git -C "$W" checkout -q oldmerged; git -C "$W" checkout -q -b oldbin; printf '\0\9' > "$W/img.bin"; cm "$W" "touch binary"
git -C "$W" checkout -q -b fresh origin/main; printf 'l1\nl2\nl3\n' > "$W/a.txt"; cm "$W" "fresh deletes MAIN-LINE (정당 — main 에서 새로 딴 브랜치)"

deny old "main 을 포함하지 않는 옛 세트 → deny" "포함하지 않음"
allow oldmerged "main 을 병합한 옛 브랜치(줄 보존) → allow"
deny oldours "main 포함하지만 main 이 더한 줄 되돌림(S10 꼴) → deny" "사라짐"
allow oldmoved "같은 줄을 위치만 옮김 → allow(위치·순서 무시 · 한계 명시)"
deny oldbin "main 이 바꾼 바이너리를 S 가 바꿈 → deny" "바이너리"
allow fresh "현재 main 에서 새로 딴 브랜치는 main 줄을 지워도 allow(F==M)"
git -C "$W" checkout -q -b oldgone oldmerged; git -C "$W" rm -q n.txt; cm "$W" "rm n"
deny oldgone "main 이 더한 파일을 옛 브랜치가 삭제 → deny" "삭제"

echo "$M1" > "$T/bh"; BHF="$T/bh"; allow oldmerged "기준 헤드=main(조상) → allow"
echo "$M0" > "$T/bh"; allow oldmerged "기준 헤드=옛 커밋(조상) → allow"
echo "$(sha "$W" old)" > "$T/bh"; deny fresh "기준 헤드가 후보의 조상이 아님 → deny" "조상이 아님"
echo zzzz > "$T/bh";               deny oldmerged "기준 헤드 40hex 아님 = 손상 deny(#0)" "손상"
printf '%s\n%s\n' "$M0" "$M1" > "$T/bh"; deny oldmerged "기준 헤드 2줄 = 손상 deny" "손상"
: > "$T/bh";                        deny oldmerged "기준 헤드 빈 파일 = 손상 deny" "손상"
echo 0000000000000000000000000000000000000000 > "$T/bh"; deny oldmerged "기준 헤드 객체 없음 deny" "commit 으로 없음"
echo "$(git -C "$W" rev-parse "$M0^{tree}")" > "$T/bh"; deny oldmerged "기준 헤드가 tree(commit 아님) deny" "commit 으로 없음"
BHF=""; allow oldmerged "기준 헤드 파일 없음 = 조상 검사만 생략 · main 포함·줄 검사는 유지 → allow"
deny old "기준 헤드 파일 없음이어도 옛 세트는 deny(교정 1)" "포함하지 않음"

out="$(bash "$GATE" oldmerged --repo "$W" --remote nope --base-head-file "$T/none" 2>&1)"; rc=$?; [ "$rc" = 1 ] && [[ "$out" == *"fetch nope main 실패"* ]]; ck "fetch 실패 = deny(조용한 통과 0)" $?
gate deadbeef; [ "$rc" = 1 ] && [[ "$out" == DENY* ]]; ck "sha 아님 → deny" $?
gate; [ "$rc" = 2 ]; ck "sha 없음 → usage rc=2" $?
git -C "$W" worktree list >/dev/null; [ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
! grep -vE '^\s*#' "$GATE" "$BIN/ft_merge_lines.py" "$BIN/ft-merge-lib.sh" | grep -qE 'git[^|]*(reset|rebase|--force|push)'; ck "정적: gate·lines·lib 에 reset·rebase·force·push 호출 0" $?
# R295: fm_fetch 는 fetch 끝의 자동 정리(gc --auto)를 끈다 — 느슨한 객체를 gc 임계 위로 세워 두고 받기만 성공·pack 0 · 대조군(일반 fetch)은 pack 생성
git -C "$W" checkout -q main; git -C "$W" config gc.auto 1; git -C "$W" config gc.autoDetach false
i=0; while [ "$(ls "$W/.git/objects/17" 2>/dev/null | wc -l)" -lt 3 ]; do i=$((i+1)); echo "gc$i" | git -C "$W" hash-object -w --stdin >/dev/null; done
npk() { ls "$W/.git/objects/pack" 2>/dev/null | grep -c '\.pack$'; }
P0="$(npk)"; (. "$BIN/ft-merge-lib.sh"; fm_fetch "$W" origin main); rc=$?; out="pack ${P0}->$(npk)"
[ "$rc" = 0 ] && [ "$(npk)" = "$P0" ]; ck "fm_fetch: 받기 성공 + gc --auto 흔적(pack) 0" $?
git -C "$W" fetch --quiet origin main 2>/dev/null; out="대조군 pack ${P0}->$(npk)"; [ "$(npk)" -gt "$P0" ]; ck "대조: 일반 fetch 는 같은 조건에서 gc 를 돌린다(시험이 gc 조건을 실제로 세웠다)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
