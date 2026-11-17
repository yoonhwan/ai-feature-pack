#!/usr/bin/env bash
# test_approval_equiv_card_md_r2216.sh — r2216: 승인 뒤 카드 .md 만 바꾼 커밋은 «일반 커밋» 셈에서만 빠진다(O2) · 규칙 3·4·rebased() 는 카드까지 엄격(O4).
#   ② 더함→되돌림→main 병합 EQUIV cards=2 ③ 더함만 NOT-EQUIV ③b 병합 0 EQUIV merges=0 cards=2 ④ 카드+코드 «일반 커밋 1 개» ⑤ 섞인 커밋 ⑥ 닮은 경로
#   ⑦ 대기→완성→대기 EQUIV cards=2 ⑧⑨ rebase 그대로 ⑩ 충돌 ⑪ overlap·names = 카드 커밋 없는 그래프(기준판) ⑫ 카드 경로 판정 대조
# 격리: 임시 git 리포(한글 폴더 카드 경로 · refs/remotes/origin/* 가짜 ref) — 실 PR·실 main·sleep 0. 변이 대조 = FT_TEST_EQUIV=<사본>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"
EQP="${FT_TEST_EQUIV:-$BIN/ft_approval_equiv.py}"; REF="$BIN/ft_approval_equiv.py"   # REF = 원본(⑪ 기준 계산 · ⑧ 문구 대조)
fail=0; rc=0; out=""; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/w"; g() { git -C "$W" -c user.email=t@t -c user.name=t "$@"; }
C="design/teams/x/indices/대기/C.md"; D="design/teams/x/indices/완성/C.md"
ci() { g add -A; g commit -qm "$1"; }
addl() { printf '%s\n' "$2" >> "$W/$1"; ci "add $1"; }
dropl() { sed -i.bak '$d' "$W/$1" && rm -f "$W/$1.bak"; ci "revert $1"; }
eqv() { out="$(python3 -I "${3:-$EQP}" "$W" "$1" "$2" origin "${4:-main}" 2>&1)"; rc=$?; }
git -c init.defaultBranch=main init -q "$W"; mkdir -p "$W/design/teams/x/indices/대기" "$W/design/harness"
printf 'L1\nL2\nL3\nL4\nL5\n' > "$W/code.txt"; echo o > "$W/other.txt"; echo '- 상태: 대기' > "$W/$C"; ci base; B="$(g rev-parse HEAD)"
g checkout -qb feat; sed -i.bak 's/^L1$/X1/' "$W/code.txt"; rm -f "$W/code.txt.bak"; echo '- 증거: a' >> "$W/$C"; ci A; A="$(g rev-parse HEAD)"   # 승인 A = 코드 1 + 카드 줄
g checkout -q main; sed -i.bak 's/^L5$/M5/' "$W/code.txt"; rm -f "$W/code.txt.bak"; ci M1; M1="$(g rev-parse HEAD)"; g update-ref refs/remotes/origin/main "$M1"
g checkout -q -B m2 "$B"; sed -i.bak 's/^L2$/Z2/' "$W/code.txt"; rm -f "$W/code.txt.bak"; ci M2; g update-ref refs/remotes/origin/main2 "$(g rev-parse HEAD)"   # ⑩ 충돌 main
mrg() { g merge -q --no-edit "${1:-refs/remotes/origin/main}" >/dev/null 2>&1; }
t1=$SECONDS

# ② 더함 → 되돌림 → main 병합 (기준판 Red = «일반 커밋 2 개»)
g checkout -q -B s2 "$A"; addl "$C" '- 증거: b'; dropl "$C"; mrg; S2="$(g rev-parse HEAD)"
eqv "$A" "$S2"; [ "$rc" = 0 ] && has "^EQUIV .* mode=merge .* cards=2$"; ck "② 카드 더함→되돌림→main 병합 → EQUIV mode=merge cards=2" $?
# ③ 더함만 · 병합 0 → 규칙 3
g checkout -q -B s3 "$A"; addl "$C" '- 증거: b'; S3="$(g rev-parse HEAD)"
eqv "$A" "$S3"; [ "$rc" = 1 ] && has "^NOT-EQUIV 자기 변경이 승인 때와 다름"; ck "③ 카드 줄 남음(병합 0) → NOT-EQUIV 자기 변경 다름" $?
# ③b 더함 → 되돌림 · 병합 0
dropl "$C"; S3b="$(g rev-parse HEAD)"
eqv "$A" "$S3b"; [ "$rc" = 0 ] && has "^EQUIV .* merges=0 .* cards=2$"; ck "③b 카드 더함→되돌림(병합 0) → EQUIV merges=0 cards=2" $?
# ④ 카드 커밋 1 + 코드 커밋 1 + 병합
g checkout -q -B s4 "$A"; addl "$C" '- 증거: b'; addl other.txt o2; mrg; S4="$(g rev-parse HEAD)"
eqv "$A" "$S4"; [ "$rc" = 1 ] && has "^NOT-EQUIV 승인 뒤 main 이 아닌 일반 커밋 1 개"; ck "④ 카드 1 + 코드 1 → NOT-EQUIV «일반 커밋 1 개»" $?
# ⑤ 한 커밋이 카드와 코드를 같이 바꿈(더함 → 되돌림 · 순변화 0)
g checkout -q -B s5 "$A"; echo '- 증거: b' >> "$W/$C"; echo o2 >> "$W/other.txt"; ci mix; g revert --no-edit HEAD >/dev/null; mrg; S5="$(g rev-parse HEAD)"
eqv "$A" "$S5"; [ "$rc" = 1 ] && has "^NOT-EQUIV 승인 뒤 main 이 아닌 일반 커밋 2 개"; ck "⑤ 카드+코드 섞인 커밋 → NOT-EQUIV(카드 커밋 아님)" $?
# ⑥ 카드처럼 보이는 경로(더함 → 되돌림)
for p in design/teams/x/indices-old/C.md design/teams/x/indices/C.txt design/harness/GOAL-harness.md; do
  g checkout -q -B s6 "$A"; mkdir -p "$W/$(dirname "$p")"; echo y > "$W/$p"; ci look; g rm -q "$p"; ci unlook; mrg; S6="$(g rev-parse HEAD)"
  eqv "$A" "$S6"; [ "$rc" = 1 ] && has "^NOT-EQUIV 승인 뒤 main 이 아닌 일반 커밋 2 개"; ck "⑥ 닮은 경로 $p → NOT-EQUIV" $?
done
# ⑦ 대기/ → 완성/ → 대기/ (삭제 + 추가 둘 다 O1)
g checkout -q -B s7 "$A"; mkdir -p "$W/$(dirname "$D")"; g mv "$C" "$D"; ci mv1; g mv "$D" "$C"; ci mv2; mrg; S7="$(g rev-parse HEAD)"
eqv "$A" "$S7"; [ "$rc" = 0 ] && has "^EQUIV .* cards=2$"; ck "⑦ 카드 옮김→되돌림 → EQUIV cards=2" $?
t2=$SECONDS

# ⑧ rebase 갈래: 새 main 위 A 변경 + 카드 줄 1 → 기준판과 같은 문구
g checkout -q -B s8 "$M1"; g cherry-pick "$A" >/dev/null 2>&1; addl "$C" '- 증거: b'; S8="$(g rev-parse HEAD)"
eqv "$A" "$S8" "$REF"; ref8="$out"; eqv "$A" "$S8"; [ "$rc" = 1 ] && has "^NOT-EQUIV rebase 한 자기 변경" && [ "$out" = "$ref8" ]; ck "⑧ rebase + 카드 줄 1 → NOT-EQUIV 기준판과 같은 문구" $?
# ⑨ rebase 인데 코드 1줄 다름
g checkout -q -B s9 "$M1"; g cherry-pick "$A" >/dev/null 2>&1; sed -i.bak 's/^X1$/Y1/' "$W/code.txt"; rm -f "$W/code.txt.bak"; ci y; S9="$(g rev-parse HEAD)"
eqv "$A" "$S9"; [ "$rc" = 1 ] && has "^NOT-EQUIV rebase 한 자기 변경"; ck "⑨ rebase 코드 1줄 다름 → NOT-EQUIV" $?
# ⑩ 카드 커밋 뒤 merge-tree(A, mx) 충돌(이웃 줄 · 손 해소)
g checkout -q -B s10 "$A"; addl "$C" '- 증거: b'; dropl "$C"; g merge -q --no-edit refs/remotes/origin/main2 >/dev/null 2>&1
printf 'X1\nZ2\nL3\nL4\nL5\n' > "$W/code.txt"; ci resolve; S10="$(g rev-parse HEAD)"
eqv "$A" "$S10" "" main2; [ "$rc" = 1 ] && has "충돌"; ck "⑩ 카드 커밋 뒤 코드 충돌 → NOT-EQUIV «충돌»" $?
# ⑪ ② 의 overlap·names = 카드 커밋 없는 같은 그래프(A + main 병합)를 원본으로 센 값
eqv "$A" "$S2"; o2="$(grep -oE 'overlap=[0-9]+ base=[0-9a-f]+( names=[^ ]+)?' <<<"$out")"
g checkout -q -B s11 "$A"; mrg; eqv "$A" "$(g rev-parse HEAD)" "$REF"; o11="$(grep -oE 'overlap=[0-9]+ base=[0-9a-f]+( names=[^ ]+)?' <<<"$out")"
[ -n "$o2" ] && [ "$o2" = "$o11" ] && grep -q "overlap=1 .*names=code.txt" <<<"$o2"; ck "⑪ overlap·names 같음($o2 = $o11)" $?
t3=$SECONDS

# ⑫ 카드 경로 판정 대조 — python 판정 = O1 기대표 · r2215 bash 판정(ft-merge-lib.sh)이 있으면 같은 답
P12=$'design/teams/x/indices-old/C.md\tn\ndesign/teams/x/indices/C.txt\tn\ndesign/harness/GOAL-harness.md\tn\ndesign/teams/x/indices/대기/C.md\ty\ndesign/harness/indices/완성/r9-x.md\ty\ndesign/teams/x/y/indices/C.md\tn'
got="$(cut -f1 <<<"$P12" | python3 -I -c 'import importlib.util as u,sys
s=u.spec_from_file_location("e",sys.argv[1]); m=u.module_from_spec(s); s.loader.exec_module(m)
for p in sys.stdin.read().splitlines(): print("%s\t%s" % (p, "y" if m.is_card(p) else "n"))' "$EQP" 2>&1)"
out="$got"; [ "$got" = "$P12" ]; ck "⑫a python 카드 경로 판정 = O1 기대표(한글 폴더)" $?
FN="${FT_TEST_R2215_FN:-}"
if [ -n "$FN" ]; then
  gb="$(cut -f1 <<<"$P12" | while IFS= read -r p; do (. "$BIN/ft-merge-lib.sh" >/dev/null 2>&1; "$FN" "$p" && echo "$p	y" || echo "$p	n"); done)"
  out="$gb"; [ "$gb" = "$got" ]; ck "⑫b r2215 bash 판정($FN) = python 판정" $?
else echo "SKIP ⑫b r2215 bash 판정 미착지(FT_TEST_R2215_FN 없음) — r2215 착지 뒤 그 함수 이름으로 다시 돈다"; fi
t4=$SECONDS
echo "단계별 초: 픽스처 $((t1 - t0)) · ②~⑦ $((t2 - t1)) · ⑧~⑪ $((t3 - t2)) · ⑫ $((t4 - t3)) · 전체 $((SECONDS - t0))"
echo "fail=$fail"; [ "$fail" = 0 ]
