#!/usr/bin/env bash
# test_merge_lines_deny_total_r2098.sh — r2098 · «main 이 더한 줄을 지움» DENY 에 전체 규모(외 N 파일 · 합계)와 다음 수 1줄 · --lost-rows 줄 뽑기 (반례 ①~⑨ · 임시 리포 · 실 PR·실 gh 0 · sleep 0)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; GATE="$BIN/ft-merge-gate.sh"; PY="$BIN/ft_merge_lines.py"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; err=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:400} err=${err:0:200}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
CARD="$T/card"; DAP="design/harness/DA-r2098.md"
export FT_ROOT="$CARD" FT_AUTONOMY_STATE_DIR="$T/state" FT_AUTONOMY_LEVEL=each
mkdir -p "$CARD/design/harness" "$T/state"
git init -q -b main "$CARD"; git -C "$CARD" config user.name t; git -C "$CARD" config user.email t@t; git -C "$CARD" config commit.gpgsign false

# 기준 B: 파일 10개 + t · tab · fen · del · bin → main M 이 줄을 더한다 · 후보는 B 에서 자기 파일 → main 병합 → 줄 지움(F = B)
mkrepo "$T"; ghremote "$W" "$ORIGIN" fake/w
for i in 0 1 2 3 4 5 6 7 8 9; do printf 'base\n' > "$W/f0$i.txt"; done
printf 't0\n' > "$W/t.txt"; printf 'x\n' > "$W/tab.txt"; printf 'y\n' > "$W/fen.txt"; printf 'd0\n' > "$W/del.txt"; printf '\0a' > "$W/bin.dat"
cm "$W" "B"; B="$(sha "$W" HEAD)"
for i in 0 1 2 3 4 5 6 7 8 9; do printf 'base\nADD %s\n' "$i" > "$W/f0$i.txt"; done
printf 't0\nT1\nT1\nT1\n' > "$W/t.txt"; printf 'x\nT\tAB\n' > "$W/tab.txt"; printf 'y\nx ``` y\n' > "$W/fen.txt"; printf 'd0\nD1\n' > "$W/del.txt"; printf '\0b' > "$W/bin.dat"
cm "$W" "M: main 이 줄을 더함"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; M="$(sha "$W" HEAD)"
cand() {  # cand <이름> <셸 명령> → 후보 sha
  git -C "$W" checkout -q -b "$1" "$B"; echo "$1" > "$W/own-$1.txt"; cm "$W" "own $1"
  git -C "$W" merge -q --no-edit origin/main; (cd "$W" && eval "$2"); cm "$W" "cand $1"; sha "$W" HEAD
}
drop() { git checkout -q "$B" -- "$@"; }   # 후보 파일을 B 꼴로 = main 이 더한 줄 지움
ALL="f00.txt f01.txt f02.txt f03.txt f04.txt f05.txt f06.txt f07.txt f08.txt f09.txt"
S1="$(cand c1 "drop $ALL")"
S2="$(cand c2 "drop f00.txt f01.txt; printf 't0\nT1\n' > t.txt")"
S6="$(cand c6 "echo z > z.txt")"
SA="$(cand c7a "drop f00.txt; git rm -q del.txt")"
SB="$(cand c7b "drop f00.txt; printf '\0c' > bin.dat")"
SC="$(cand c7c "drop f00.txt tab.txt")"
SD="$(cand c7d "drop f00.txt fen.txt")"
git -C "$W" checkout -q -b c6m "$M"; echo z > "$W/z.txt"; cm "$W" "F==M"; SM="$(sha "$W" HEAD)"
L() { out="$(python3 -I "$PY" "$W" "$M" "$@" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"; }
l1() { printf '%s\n' "$out" | sed -n "${1}p"; }
mkdoc() {  # mkdoc <block 파일> → 카드 리포 판정문 커밋 sha
  { printf '# DA r2098 시험\n\n## §2 수용\n\n판정: **APPROVE — 시험**\n\n```gate-replace\n'; cat "$1"; printf '```\n'; } > "$CARD/$DAP"
  git -C "$CARD" add -A && git -C "$CARD" commit -q -m doc && sha "$CARD" HEAD
}

# ① 10 파일 소실 → 8 항목 + 외 2 파일 + 합계
L "$S1"; first="$(l1 1)"
[ "$rc" = 1 ] && [[ "$first" == "DENY main 이 더한 줄을 지움(옛 브랜치 F=${B:0:10})"* ]] && [ "$(printf '%s' "$first" | grep -o '사라짐' | wc -l | tr -d ' ')" = 8 ] \
  && [[ "$first" == *"외 2 파일"* ]] && [[ "$first" == *"합계 10 파일 · 10 줄"* ]]
ck "① 10 파일 → 8 항목 · 외 2 파일 · 합계 10 파일 · 10 줄 · rc 1" $?
# ② 8 이하
L "$S2"; first="$(l1 1)"
[ "$rc" = 1 ] && [[ "$first" != *"외 "* ]] && [[ "$first" == *"합계 3 파일 · 4 줄"* ]]; ck "② 3 파일 4줄 → 외 0 · 합계 3 파일 · 4 줄" $?
# ③ 다음 수: 둘째 줄 · 게이트 출력 · head 불일치 판정문이면 0
L "$S1"; second="$(l1 2)"
[[ "$second" == "다음: "*"--replace-ok"*"--lost-rows"* ]] && [ "$(printf '%s\n' "$out" | grep -c '^다음:')" = 1 ]; ck "③a stdout 둘째 줄 = 다음: … --replace-ok … --lost-rows" $?
out="$(bash "$GATE" "$S1" --repo "$W" --base-head-file "$T/none" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *$'\n다음: '*"--replace-ok"*"--lost-rows"* ]]; ck "③b ft-merge-gate.sh 거절 출력에 다음: 줄" $?
printf 'head %s\nf00.txt\tADD 0\t1\n' "$B" > "$T/bad.blk"; CB="$(mkdoc "$T/bad.blk")"
L "$S1" --replace-ok "$DAP@$CB#§2"
[ "$rc" = 1 ] && [[ "$out" == "DENY "*"replace-ok "* ]] && [[ "$out" != *"더한 줄을 지움"* ]] && ! [[ "$out" == *"다음:"* ]]; ck "③c --replace-ok head 불일치 DENY → 다음: 줄 0" $?
# ④ 왕복: --lost-rows → 판정문 블록 → PASS · REPLACE-OK 10줄
L "$S1" --lost-rows; printf '%s\n' "$out" > "$T/s1.blk"
[ "$rc" = 0 ] && [ "$(l1 1)" = "head $S1" ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 11 ] && [ "$(l1 2)" = "$(printf 'f00.txt\tADD 0\t1')" ]; ck "④a --lost-rows = head + 10행 · rc 0" $?
C1="$(mkdoc "$T/s1.blk")"; L "$S1" --replace-ok "$DAP@$C1#§2"
[ "$rc" = 0 ] && [[ "$out" == PASS* ]] && [[ "$out" == *"REPLACE-OK 10줄"* ]]; ck "④b 블록 그대로 → --replace-ok PASS · REPLACE-OK 10줄 · rc 0" $?
# ⑤ 개수: T1 3개 중 1개 남음 → 1행 개수 2 · 왕복 PASS
L "$S2" --lost-rows; printf '%s\n' "$out" > "$T/s2.blk"
[ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^t.txt')" = 1 ] && printf '%s\n' "$out" | grep -qx "$(printf 't.txt\tT1\t2')"; ck "⑤a 같은 줄 3→1 = 1행 · 개수 2" $?
C2="$(mkdoc "$T/s2.blk")"; L "$S2" --replace-ok "$DAP@$C2#§2"
[ "$rc" = 0 ] && [[ "$out" == *"REPLACE-OK 4줄"* ]]; ck "⑤b 왕복 PASS · REPLACE-OK 4줄(개수 합)" $?
# ⑥ 소실 0 · F==M
L "$S6" --lost-rows; [ "$rc" = 0 ] && [ "$out" = "head $S6" ]; ck "⑥a 소실 0 → head 줄만 · rc 0" $?
L "$SM" --lost-rows; [ "$rc" = 0 ] && [ "$out" = "head $SM" ]; ck "⑥b F==M → head 줄만 · rc 0" $?
# ⑦ 줄로 못 적음 → stderr 1줄 · stdout 그 항목 0 · 함께 있는 f00 1행은 stdout · rc 1
c7() {  # c7 <표시> <sha> <경로>
  L "$2" --lost-rows
  [ "$rc" = 1 ] && [ "$(printf '%s\n' "$err" | grep -c '^줄로 못 적음: ')" = 1 ] && [[ "$err" == *"줄로 못 적음: $3: "* ]] \
    && ! printf '%s\n' "$out" | grep -q "^$3" && printf '%s\n' "$out" | grep -qx "$(printf 'f00.txt\tADD 0\t1')" && [ "$(l1 1)" = "head $2" ]
  ck "⑦$1 $3 → 줄로 못 적음 1줄 · stdout 0 · f00 1행 있음 · rc 1" $?
}
c7 ⓐ "$SA" del.txt; c7 ⓑ "$SB" bin.dat; c7 ⓒ "$SC" tab.txt; c7 ⓓ "$SD" fen.txt
# ⑧ 실패: 없는 sha · 무관 이력 → ERROR 1줄 · rc 2 · head 0
L 0123456789012345678901234567890123456789 --lost-rows; [ "$rc" = 2 ] && [[ "$out" == ERROR* ]] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ]; ck "⑧a 없는 sha → ERROR · rc 2 · head 0" $?
git -C "$W" checkout -q --orphan orph; git -C "$W" rm -rqf . ; echo o > "$W/o.txt"; cm "$W" orphan; SO="$(sha "$W" HEAD)"
L "$SO" --lost-rows; [ "$rc" = 2 ] && [[ "$out" == ERROR* ]] && ! [[ "$out" == *head* ]]; ck "⑧b 무관 이력 → ERROR · rc 2 · head 0" $?
# ⑨ 8067 꼴: 가지가 main 병합 → main 줄 1개 바꿈 → main 한 번 더 병합 → F = 처음 갈래점 · DENY 유지
T9="$T/n9"; mkdir -p "$T9"; mkrepo "$T9"; F9="$M0"
git -C "$W" checkout -q main; printf 'l1\nl2\nl3\nSTAMP 23d4c\n' > "$W/a.txt"; cm "$W" "main 스탬프"; git -C "$W" push -q origin main
git -C "$W" checkout -q -b p9 "$F9"; echo own > "$W/own.txt"; cm "$W" own; git -C "$W" merge -q --no-edit main
printf 'l1\nl2\nl3\nSTAMP c037d\n' > "$W/a.txt"; cm "$W" "재스탬프"
git -C "$W" checkout -q main; echo d > "$W/d.txt"; cm "$W" "main 다음"; M9="$(sha "$W" HEAD)"
git -C "$W" checkout -q p9; git -C "$W" merge -q --no-edit main; S9="$(sha "$W" HEAD)"
out="$(python3 -I "$PY" "$W" "$M9" "$S9" 2>/dev/null)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == "DENY main 이 더한 줄을 지움(옛 브랜치 F=${F9:0:10})"* ]]; ck "⑨a 두 번 병합한 가지 → F = 처음 갈래점 · DENY 유지" $?
cmp -s "$PY" "$BIN/../kit/fable-team/bin/ft_merge_lines.py"; ck "⑨b bin = kit 같은 글자" $?

echo "합계 FAIL=$fail"
[ "$fail" = 0 ]
