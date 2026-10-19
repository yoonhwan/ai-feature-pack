#!/usr/bin/env bash
# test_merge_lines_moved.sh — r461: 줄 대조(ft_merge_lines.py)가 «다른 폴더로 옮긴 파일» 을 소실로 읽지 않는가 (임시 리포만 · 외부 호출 0)
# ⓐ 작은 카드 이동(유사도 밑 → D+A) 3장·48장 = PASS · ⓑ 진짜 삭제 · ⓒ 이동+줄 소실 · ⓓ 같은 이름 2개 = DENY · ⓔ 바이너리 이동 = 기존 DENY · ⓕ 큰 카드 R = PASS
# RED 재현: FT_MERGE_LINES=<옛 ft_merge_lines.py> bash test_merge_lines_moved.sh
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LINES="${FT_MERGE_LINES:-$BIN/ft_merge_lines.py}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run() { out="$(python3 -I "$LINES" "$W" "$M1" "$(sha "$W" "$1")" 2>&1)"; rc=$?; }
pass() { run "$1"; [ "$rc" = 0 ] && [[ "$out" == PASS* ]] && [[ "$out" == *"$3"* ]]; ck "$2" $?; }
deny() { run "$1"; [ "$rc" = 1 ] && [[ "$out" == DENY* ]] && [[ "$out" == *"$3"* ]]; ck "$2" $?; }
card() { mkdir -p "$W/$(dirname "$1")"; printf '# 인덱스: %s\n- 위치: %s\n- 본문 %s\n' "$1" "$1" "$2" > "$W/$1"; }   # 3줄 중 2줄이 경로 글자
mv_card() { git -C "$W" rm -q "$1"; card "$2" "$3"; }        # 옮기며 경로 글자 치환 → 유사도 50% 밑(git 이 D+A 로 가름)
br() { git -C "$W" checkout -q -b "$1" old; git -C "$W" merge -q --no-edit main; }

python3 -I -c "import ast;ast.parse(open('$LINES').read())"; ck "py 구문" $?
mkrepo "$T"
git -C "$W" checkout -q -b old; echo c > "$W/c.txt"; cm "$W" "old work"; git -C "$W" checkout -q main
for i in 1 2 3; do card "t/대기/a$i.md" "a$i"; done
for i in $(seq 1 48); do card "t/대기/m$i.md" "m$i"; done
card t/대기/b.md b; card t/대기/d.md d
card t/대기/c.md c; printf 'c-line1\nc-line2\nc-line3\n' >> "$W/t/대기/c.md"
mkdir -p "$W/e" "$W/big"; printf '\0\1\2\3' > "$W/e/img.bin"
{ echo "# 인덱스: big/f.md"; for i in $(seq 1 19); do echo "f-line$i"; done; } > "$W/big/f.md"; cp "$W/big/f.md" "$W/big/g.md"; sed -i.x 's#big/f.md#big/g.md#' "$W/big/g.md"; rm -f "$W/big/g.md.x"
cm "$W" "main adds cards"; M1="$(sha "$W" HEAD)"

br sa;  for i in 1 2 3; do mv_card "t/대기/a$i.md" "t/진행/a$i.md" "a$i"; done; cm "$W" "move 3"
br s48; for i in $(seq 1 48); do mv_card "t/대기/m$i.md" "t/완성/m$i.md" "m$i"; done; cm "$W" "move 48"
br sb;  git -C "$W" rm -q t/대기/b.md; cm "$W" "rm b"
br sc;  git -C "$W" rm -q t/대기/c.md; card t/진행/c.md c; echo c-line3 >> "$W/t/진행/c.md"; cm "$W" "move c, drop 2 lines"
br sd;  mv_card t/대기/d.md t/진행/d.md d; mkdir -p "$W/u/완성"; echo other > "$W/u/완성/d.md"; cm "$W" "move d + same-name other"
br se;  mkdir -p "$W/e2"; git -C "$W" mv e/img.bin e2/img.bin; cm "$W" "move binary"
br sf;  mkdir -p "$W/big2"; git -C "$W" mv big/f.md big2/f.md; cm "$W" "move big same"
br sf2; mkdir -p "$W/big2"; git -C "$W" mv big/g.md big2/g.md; sed -i.x 's#big/g.md#big2/g.md#' "$W/big2/g.md"; rm -f "$W/big2/g.md.x"; cm "$W" "move big + path line"

n="$(git -C "$W" -c core.quotepath=off diff -M --name-status "$M1" sa | grep -c '^D')"; out="D=$n"; [ "$n" = 3 ]; ck "전제: ⓐ 작은 카드 이동은 git 이 D+A 로 가른다(시험이 그 꼴을 실제로 만든다)" $?
n="$(git -C "$W" diff -M --name-status "$M1" sf2 | grep -c '^R')"; out="R=$n"; [ "$n" = 1 ]; ck "전제: ⓕ2 큰 카드는 R 로 잡힌다" $?

pass sa  "ⓐ 작은 카드 3장 다른 폴더로 이동(경로 글자만 치환) → PASS 이동 인정 3" "이동 인정 3"
pass s48 "ⓐ 48장 이동(loom 1959 꼴) → PASS 이동 인정 48" "이동 인정 48"
deny sb  "ⓑ 진짜 삭제(같은 이름 후보 0) → DENY 그대로" "t/대기/b.md: main 이 바꾼 파일을 S 가 삭제"
deny sc  "ⓒ 이동 + main 이 더한 줄 2개 지움 → DENY" "t/진행/c.md 로 이동했으나 main 이 더한 줄 2 개 없음"
deny sd  "ⓓ 같은 이름 후보 2개 = 추측 0 → DENY" "같은 이름 후보 2개(추측 0)"
deny se  "ⓔ 바이너리 이동 = 기존 거절 그대로" "바이너리"
pass sf  "ⓕ 큰 카드 같은 내용 이동(R) → PASS 그대로" "이동 인정 1"
pass sf2 "ⓕ2 큰 카드 R + 경로 줄 치환 → PASS" "MOVED big/g.md -> big2/g.md"
br same; printf 'x\n' > "$W/t/대기/a1.md"; cm "$W" "same path drop"
deny same "같은 경로에서 줄 지움 = 기존 «사라짐» 그대로(이동 규칙이 안 덮음)" "사라짐"
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
