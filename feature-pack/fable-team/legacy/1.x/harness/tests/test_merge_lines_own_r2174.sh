#!/usr/bin/env bash
# test_merge_lines_own_r2174.sh — r2174: 줄 대조(ft_merge_lines.py)가 «가지가 같은 경로에 스스로 더한 줄» 을 main 줄 소실로 세지 않는가 (임시 리포만 · 외부 호출 0 · sleep 0)
# 반례 ①~⑪ (⑫ = 기존 시험 재실행은 따로) · RED 재현: FT_MERGE_LINES=<기준판 ft_merge_lines.py> bash test_merge_lines_own_r2174.sh (① ② ④ FAIL)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; LINES="${FT_MERGE_LINES:-$BIN/ft_merge_lines.py}"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""; calls=0
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc calls=$calls out=${out:0:400}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
REALGIT="$(command -v git)"; mkdir -p "$T/gw"   # 둘레 git 래퍼 — ft_merge_lines.py 가 부르는 git 호출 수만 센다(⑨ · M5)
printf '#!/bin/bash\necho x >> "$GITLOG"\nexec "%s" "$@"\n' "$REALGIT" > "$T/gw/git"; chmod +x "$T/gw/git"
run() {  # run <M> <S> [인자…] → out(stdout) · rc · calls(git 호출 수)
  local m="$1" s="$2"; shift 2; : > "$T/glog"
  out="$(PATH="$T/gw:$PATH" GITLOG="$T/glog" python3 -I "$LINES" "$W" "$m" "$s" "$@" 2>"$T/err")"; rc=$?
  calls="$(wc -l < "$T/glog" | tr -d ' ')"
}
deny_txt() {  # deny_txt <M> <S> <본문> <파일 수> <줄 수> — 기준판 DENY 2줄(바이트 그대로)
  printf 'DENY main 이 더한 줄을 지움(옛 브랜치 F=%s) — main 에서 새 브랜치로 따라: %s · 합계 %s 파일 · %s 줄\n다음: 의도된 교체면 DA 판정문 gate-replace 블록 → 착지 명령에 --replace-ok <경로>@<sha>#§<절> · 블록 줄 = ft_merge_lines.py %s %s %s --lost-rows' \
    "${M0:0:10}" "$3" "$4" "$5" "$W" "$1" "$2"
}
co() { git -C "$W" checkout -q -B "$1" "$2"; }                       # co <가지> <시작>
put() { printf "$2" > "$W/$1"; }                                   # put <경로> <printf 본문>
ours() { git -C "$W" merge -q -s ours --no-edit "$1"; }            # 가지 트리 그대로 main 을 들임(부모 2개)
mrg() { git -C "$W" merge -q --no-ff --no-edit "$1"; }

python3 -I -c "import ast;ast.parse(open('$LINES').read())"; ck "py 구문" $?
mkrepo "$T"; X8='x1\nx2\nx3\nx4\nx5\nx6\nx7\nx8\n'; X7='x1\nx2\nx3\nx4\nx5\nx6\nx7\n'

# ① PR 8999 꼴: c1 이 P 에 8줄 · main 이 같은 8줄 · c2 가 1줄을 Q 로 옮김 · main merge
co m1 "$M0"; put p.txt "$X8"; cm "$W" "main 8"; MA="$(sha "$W" HEAD)"
co s1 "$M0"; put p.txt "$X8"; cm "$W" "c1 8"; put p.txt "$X7"; put q.txt 'x8\n'; cm "$W" "c2 move"; ours m1; S1="$(sha "$W" HEAD)"
run "$MA" "$S1"; [ "$rc" = 0 ] && [[ "$out" == "PASS "*" · OWN 1줄" ]]; ck "① 겹쳐 착지 뒤 다른 파일로 옮김 → PASS · OWN 1줄(기준판 DENY 1 파일 · 1 줄 = Red)" $?

# ② PR 9005 꼴: c1 과 main 이 P 에 같은 L · merge 커밋 안에서 L → L2
co m2 "$M0"; put p.txt 'L\n'; cm "$W" "main L"; MB="$(sha "$W" HEAD)"
co s2 "$M0"; put p.txt 'L\n'; cm "$W" "c1 L"; git -C "$W" merge -q --no-commit --no-ff m2 >/dev/null 2>&1; put p.txt 'L2\n'; cm "$W" "merge main + L2"; S2="$(sha "$W" HEAD)"
n="$(git -C "$W" rev-list --parents -n1 "$S2" | wc -w | tr -d ' ')"; out="words=$n"; [ "$n" = 3 ]; ck "전제: ② 의 바꿈은 merge 커밋(부모 2개) 안에 있다" $?
run "$MB" "$S2"; [ "$rc" = 0 ] && [[ "$out" == "PASS "*" · OWN 1줄" ]]; ck "② 같은 줄을 두 곳에 적고 merge 안에서 바꿈 → PASS · OWN 1줄(기준판 DENY = Red)" $?

# ③ main 만 더한 줄(가지 줄 0) → DENY 기준판 바이트
co m3 "$M0"; put a.txt 'l1\nl2\nl3\nL\n'; cm "$W" "main L"; MC="$(sha "$W" HEAD)"
co s3 "$M0"; put b.txt 'b1\nb2\n'; cm "$W" "c1 b"; ours m3; S3="$(sha "$W" HEAD)"
run "$MC" "$S3"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MC" "$S3" "a.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "③ main 만 더한 줄 → DENY · stdout 기준판과 같음" $?

# ④ 개수: main L×2 · c1 L×1 · S 에 L 0
co m4 "$M0"; put p.txt 'L\nL\n'; cm "$W" "main L L"; MD="$(sha "$W" HEAD)"
co s4 "$M0"; put p.txt 'keep\nL\n'; cm "$W" "c1 L"; ours m4; put p.txt 'keep\n'; cm "$W" "c2 drop L"; S4="$(sha "$W" HEAD)"
run "$MD" "$S4"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MD" "$S4" "p.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "④ main 2 · 가지 1 · S 0 → DENY «1 줄»(기준판 «2 줄» = Red · M4)" $?

# ⑤ merge 가 들여온 줄을 뒤 커밋이 지움 → DENY 기준판 바이트
co s5 "$M0"; put b.txt 'b1\nb2\n'; cm "$W" "c1 b"; mrg m3; put a.txt 'l1\nl2\nl3\n'; cm "$W" "c2 drop L"; S5="$(sha "$W" HEAD)"
run "$MC" "$S5"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MC" "$S5" "a.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "⑤ merge 가 들여온 줄 → 가지 줄 아님 · DENY 기준판과 같음(M1)" $?

# ⑥ 둘째 부모 쪽 가지 X 가 L 을 더함 → DENY 그대로
co x6 "$M0"; put p.txt 'xk\nL\n'; cm "$W" "X L"
co s6 "$M0"; put b.txt 'b1\nb2\n'; cm "$W" "c1 b"; mrg x6; ours m2; put p.txt 'xk\n'; cm "$W" "c2 drop L"; S6="$(sha "$W" HEAD)"
run "$MB" "$S6"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MB" "$S6" "p.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "⑥ 사슬 밖(둘째 부모 쪽) 커밋 줄 → 가지 줄 아님 · DENY 그대로(M2)" $?

# ⑦ 다른 경로: c1 이 L 을 Q 에 · main 이 L 을 P(a.txt) 에
co s7 "$M0"; put q.txt 'L\n'; cm "$W" "c1 Q L"; ours m3; S7="$(sha "$W" HEAD)"
run "$MC" "$S7"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MC" "$S7" "a.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "⑦ 다른 경로의 같은 글자 → DENY 그대로(M3)" $?

# ⑧ 줄 아닌 소실(가지가 같은 줄을 먼저 더했어도) → DENY 기준판 바이트
co s8a "$M0"; put p.txt 'L\n'; cm "$W" "c1 L"; mrg m2; git -C "$W" rm -q p.txt; cm "$W" "c2 rm"; S8A="$(sha "$W" HEAD)"
run "$MB" "$S8A"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MB" "$S8A" "p.txt: main 이 바꾼 파일을 S 가 삭제" 1 0)" ]; ck "⑧-a S 가 P 를 삭제 → DENY 기준판과 같음" $?
co m8 "$M0"; put e.bin '\0\1'; cm "$W" "main bin"; ME="$(sha "$W" HEAD)"
co s8b "$M0"; put e.bin '\0\1'; cm "$W" "c1 bin"; mrg m8; put e.bin '\0\2'; cm "$W" "c2 bin"; S8B="$(sha "$W" HEAD)"
run "$ME" "$S8B"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$ME" "$S8B" "e.bin: 바이너리가 main 의 것과 다름" 1 0)" ]; ck "⑧-b 바이너리 다름 → DENY 기준판과 같음" $?

# ⑨ 통과 길 불변: stdout · rc · git 호출 수(기준판 실측값 고정)
co s9a "$M0"; put b.txt 'b1\nb2\n'; cm "$W" "c1 b"; S9A="$(sha "$W" HEAD)"
run "$M0" "$S9A"; [ "$rc" = 0 ] && [ "$out" = "PASS 처음부터 main 위(F==M) — 보호 집합 빈 집합" ] && [ "$calls" = 3 ]; ck "⑨-a F==M → PASS · git 3회(기준판과 같음)" $?
co s9b "$M0"; put b.txt 'b1\nb2\n'; cm "$W" "c1 b"; mrg m3; S9B="$(sha "$W" HEAD)"
run "$MC" "$S9B"; [ "$rc" = 0 ] && [ "$out" = "PASS 보호 집합 1 파일 · F=${M0:0:10} · 이동 인정 0" ] && [ "$calls" = 7 ]; ck "⑨-b 보호 집합 있고 소실 0 → PASS · git 7회(기준판과 같음 · M5)" $?
co m9 "$M0"; mkdir -p "$W/t/대기"; put "t/대기/c.md" '# 인덱스: t/대기/c.md\n- 위치: t/대기/c.md\n- 본문 c\n'; cm "$W" "main card"; MF="$(sha "$W" HEAD)"
co s9c "$M0"; mrg m9; git -C "$W" rm -q "t/대기/c.md"; mkdir -p "$W/t/진행"; put "t/진행/c.md" '# 인덱스: t/진행/c.md\n- 위치: t/진행/c.md\n- 본문 c\n'; cm "$W" "move card"; S9C="$(sha "$W" HEAD)"
run "$MF" "$S9C"; [ "$rc" = 0 ] && [ "$out" = "PASS 보호 집합 1 파일 · F=${M0:0:10} · 이동 인정 1; MOVED t/대기/c.md -> t/진행/c.md" ] && [ "$calls" = 9 ]; ck "⑨-c r461 이동 인정 → PASS · git 9회(기준판과 같음 · M5)" $?

# ⑩ --replace-ok 블록과 함께(가지 줄 먼저 · 남은 소실에만 블록)
CARD="$T/card"; DAP="da.md"; git init -q -b main "$CARD"; git -C "$CARD" config user.name t; git -C "$CARD" config user.email t@t
dac() {  # dac <head> <"경로|줄|개수"…> → 판정문 커밋 sha
  local head="$1" r p l n; shift
  { printf '# DA r2174 시험\n\n## §2 수용 판정\n\n판정: **APPROVE — 시험**\n\n```gate-replace\nhead %s\n' "$head"
    for r in "$@"; do IFS='|' read -r p l n <<<"$r"; printf '%s\t%s\t%s\n' "$p" "$l" "$n"; done; printf '```\n'; } > "$CARD/$DAP"
  git -C "$CARD" add -A && git -C "$CARD" commit -q -m v && sha "$CARD" HEAD
}
co m10 "$M0"; put a.txt 'l1\nl2\nl3\nL1\nL2\n'; cm "$W" "main L1 L2"; MG="$(sha "$W" HEAD)"
co s10 "$M0"; put a.txt 'l1\nl2\nl3\nL1\n'; cm "$W" "c1 L1"; ours m10; put a.txt 'l1\nl2\nl3\n'; cm "$W" "c2 drop"; S10="$(sha "$W" HEAD)"
C10="$(dac "$S10" "a.txt|L2|1")"
out="$(FT_ROOT="$CARD" python3 -I "$LINES" "$W" "$MG" "$S10" --replace-ok "$DAP@$C10#§2" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "PASS "*" · OWN 1줄 · REPLACE-OK 1줄 ($DAP@${C10:0:10}#§2)" ]]; ck "⑩-a L1 가지 줄 · L2 블록 → PASS · OWN 1줄 · REPLACE-OK 1줄" $?
co m10b "$M0"; put a.txt 'l1\nl2\nl3\nL\nL\n'; cm "$W" "main L L"; MH="$(sha "$W" HEAD)"
co s10b "$M0"; put a.txt 'l1\nl2\nl3\nL\n'; cm "$W" "c1 L"; ours m10b; put a.txt 'l1\nl2\nl3\n'; cm "$W" "c2 drop"; S10B="$(sha "$W" HEAD)"
C10B="$(dac "$S10B" "a.txt|L|2")"
out="$(FT_ROOT="$CARD" python3 -I "$LINES" "$W" "$MH" "$S10B" --replace-ok "$DAP@$C10B#§2" 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] && [[ "$out" == "PASS "*" · OWN 1줄 · REPLACE-OK 1줄 ($DAP@${C10B:0:10}#§2)" ]]; ck "⑩-b 같은 L 소실 2 · 가지 1 · 블록 2 → OWN 1줄 · REPLACE-OK 1줄(M6)" $?
run "$MG" "$S10" --lost-rows; [ "$rc" = 0 ] && [ "$out" = "$(printf 'head %s\na.txt\tL2\t1' "$S10")" ]; ck "⑩-c --lost-rows → 블록 줄 = L2 1줄뿐" $?

# ⑪ 상한: ① 꼴 + 부모 1개 커밋 50개 → PASS OWN · 51개 → DENY 기준판 바이트
co s11 "$M0"; put p.txt "$X8"; cm "$W" "c1 8"; put p.txt "$X7"; put q.txt 'x8\n'; cm "$W" "c2 move"
for i in $(seq 1 48); do git -C "$W" commit -q --allow-empty -m "fill $i"; done; ours m1; S11="$(sha "$W" HEAD)"
git -C "$W" commit -q --allow-empty -m "fill 49"; S11B="$(sha "$W" HEAD)"
run "$MA" "$S11"; [ "$rc" = 0 ] && [[ "$out" == "PASS "*" · OWN 1줄" ]]; ck "⑪ 부모 1개 커밋 50개 → PASS · OWN 1줄" $?
run "$MA" "$S11B"; [ "$rc" = 1 ] && [ "$out" = "$(deny_txt "$MA" "$S11B" "p.txt: main 이 더한 줄 1 개가 S 에서 사라짐" 1 1)" ]; ck "⑪ 51개 → 가지 줄 0 · DENY 기준판과 같음" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
