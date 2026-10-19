#!/usr/bin/env bash
# test_merge_lines_pathsubst.sh — r477: 줄 대조(ft_merge_lines.py)가 «팀 폴더 옛 꼴 글자만 바꾼 줄» 을 소실로 읽지 않는가 (임시 리포만 · 외부 호출 0)
# ⓐ 옛 꼴 3줄 → 새 꼴 = PASS PATHSUBST 3 · ⓑ 같은 줄 다른 글자 변경 = DENY · ⓒ 명단 밖 팀 = DENY · ⓓ 역방향(새→옛) = DENY
# ⓔ r461 이동 + 본문 다른 팀 경로 치환 = PASS(두 규칙 동시) · ⓕ 명단 ref 못 읽음 = WARN + 옛 동작(DENY)
# RED 재현: FT_MERGE_LINES=<옛 ft_merge_lines.py> bash test_merge_lines_pathsubst.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LINES="${FT_MERGE_LINES:-$BIN/ft_merge_lines.py}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() { out="$(python3 -I "$LINES" "$W" "$M1" "$(sha "$W" "$1")" 2>&1)"; rc=$?; }
pass() { run "$1"; [ "$rc" = 0 ] && [[ "$out" == PASS* ]] && [[ "$out" == *"$3"* ]]; ck "$2" $?; }
both() { run "$1"; [ "$rc" = 0 ] && [[ "$out" == PASS* ]] && [[ "$out" == *"$3"* ]] && [[ "$out" == *"$4"* ]]; ck "$2" $?; }
deny() { run "$1"; [ "$rc" = 1 ] && [[ "$out" == DENY* ]] && [[ "$out" == *"$3"* ]]; ck "$2" $?; }
br() { git -C "$W" checkout -q -b "$1" old; git -C "$W" merge -q --no-edit main; }
sub() { sed -i.x "$2" "$W/$1"; rm -f "$W/$1.x"; }   # sub <경로> <sed 식>

python3 -I -c "import ast;ast.parse(open('$LINES').read())"; ck "py 구문" $?
mkrepo "$T"
mkdir -p "$W/design"
cat > "$W/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 | 오케 좌석 계열 | 상태 |
|---|---|---|---|
| harness | `$FT_HARNESS_ROOT/design/harness/` | h | 현역 |
| a | `design/teams/a/` | a | 현역 |
| b | `design/teams/b/` | b | 현역 |
EOF
cm "$W" "teams roster"; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
git -C "$W" checkout -q -b old; echo c > "$W/c.txt"; cm "$W" "old work"; git -C "$W" checkout -q main
mkdir -p "$W/t"
printf 'alpha design/a/x.md tail\nbeta design/a/x.md tail\ngamma design/a/x.md tail\n' > "$W/t/path.md"
printf 'one design/a/y.md keep\ntwo design/a/y.md stay\n' > "$W/t/word.md"
printf 'zz design/zzz/x.md tail\n' > "$W/t/unknown.md"
printf 'rev design/teams/b/x.md tail\n' > "$W/t/reverse.md"
printf 'see design/a/z.md tail\n' > "$W/t/move.md"
cm "$W" "main adds lines"; M1="$(sha "$W" HEAD)"

br sa; sub t/path.md 's#design/a/#design/teams/a/#g'; cm "$W" "ⓐ path form only"
br sb; sub t/word.md 's#design/a/y.md#design/teams/a/y.md#; s/keep/KEEP/'; cm "$W" "ⓑ path + word"
br sc; sub t/unknown.md 's#design/zzz/#design/teams/zzz/#'; cm "$W" "ⓒ roster 밖 팀"
br sd; sub t/reverse.md 's#design/teams/b/#design/b/#'; cm "$W" "ⓓ 역방향"
br se; git -C "$W" rm -q t/move.md; mkdir -p "$W/t/new"; printf 'see design/teams/a/z.md tail\n' > "$W/t/new/move.md"; cm "$W" "ⓔ 이동 + 본문 치환"

pass sa "ⓐ 옛 꼴 3줄 → 새 꼴 = PASS PATHSUBST 3" "PATHSUBST 3"
deny sb "ⓑ 같은 줄 다른 글자 변경 = DENY(정규화가 내용 변경을 안 덮는다)" "main 이 더한 줄 1 개가 S 에서 사라짐"
deny sc "ⓒ 명단 밖 팀(zzz) = DENY(치환 0 · 추측 0)" "main 이 더한 줄 1 개가 S 에서 사라짐"
deny sd "ⓓ 역방향(새 꼴 → 옛 꼴) = DENY" "main 이 더한 줄 1 개가 S 에서 사라짐"
both se "ⓔ r461 이동 + 본문 다른 팀 경로 치환 = PASS(두 규칙 동시)" "MOVED t/move.md -> t/new/move.md" "PATHSUBST 1"

out="$(FT_TEAMS_REF=no-such-ref python3 -I "$LINES" "$W" "$M1" "$(sha "$W" sa)" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"WARN 명단 ref 못 읽음 — PATHSUBST 0"* ]] && [[ "$out" == *"main 이 더한 줄 3 개가 S 에서 사라짐"* ]]; ck "ⓕ 명단 ref 못 읽음 = WARN + 옛 동작(DENY)" $?
out="$(python3 -I "$LINES" "$W" "$M1" "$(sha "$W" sa)" 2>&1)"; rc=$?
[[ "$out" != *"WARN"* ]]; ck "ⓕ2 명단 읽힘 = WARN 0" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
