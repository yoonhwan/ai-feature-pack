#!/usr/bin/env bash
# test_scratch_repo_sparse_auto_done_r891.sh — r891(범위 축소 r7): ft-scratch-repo.sh = sparse 기본 + --report --orphans 만
#   ⓑ 기본 sparse(design/teams/*·evidence 미디어 제외) · --full · --with · 재사용은 규칙 같을 때만
#   ⓖ' 등록부 = ROOT + 원 저장소 둘(r996 ①: 같은 줄을 양쪽에 · --done 이 양쪽 줄을 치움)   ⓩ 생성은 아무것도 안 지움(판정 끝난 같은 주인 사본 그대로)
#   ⓩ' worktree add 실패 · sparse 체크아웃 실패 = rc 4 · 이번 실행이 만든 폴더만 되돌림 · 등록 줄 0   ⓡ 선등록(r996 ⓗ): sparse set 직후 끊겨도 등록 1줄이 남고 완성 표식은 없다
#   ⓘ --report --orphans = 미등록 사본 표(주인 추정) · 삭제 0 · 못 읽은 등록부 = «부분 읽기» 줄
#   ⓔ 기존 scratch 시험 ALL PASS   ⓕ 변이 2종 FAIL   ⓙ kit 짝 cmp0
#   옮긴 칸: 지우는 쪽(AUTO-DONE·신원 비교·합친 등록부 sweep·--done 가드 · r5) → r897 · ⓗ 선등록·되돌림은 r996 이 되가져옴(ⓩ'·ⓡ 칸이 그 계약)
# 임시 git 저장소·가짜 lsof·임시 TMPDIR 만 쓴다 — 실 저장소·실 사본·실 TMPDIR 0.
# SCR_SUT=<경로> 로 시험 대상을 바꿀 수 있다(고치기 전 판 = before-red 증거용 · 변이). R891_NO_MUT=1 = ⓔⓕⓙ 생략(변이 재귀용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${SCR_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
G="$T/src"; R2="$T/other"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G/.fable-team/state" "$R2/.fable-team/state" "$SCR" "$TMPD" "$T/bin"
cm() { git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
git init -q -b main "$G"; printf '.fable-team/\n' > "$G/.gitignore"
for f in design/teams/a/big.md design/teams/a/evidence/x/s.wav design/teams/b/c.md design/harness/h.md design/harness/evidence/r1/a.wav \
  design/harness/evidence/r1/a.txt bin/x.sh tests/t.sh feature-pack/p.md; do mkdir -p "$G/$(dirname "$f")"; echo 1 > "$G/$f"; done
git -C "$G" add -A; cm "$G" m1; M1="$(git -C "$G" rev-parse HEAD)"
echo 2 > "$G/bin/y.sh"; git -C "$G" add -A; cm "$G" m2; M2="$(git -C "$G" rev-parse HEAD)"
for b in u1 u2 u3; do git -C "$G" checkout -q -b "$b" "$M2"; echo "$b" > "$G/$b.txt"; git -C "$G" add -A; cm "$G" "$b"; done
git -C "$G" checkout -q main
U() { git -C "$G" rev-parse "$1"; }
git init -q -b main "$R2"; echo r > "$R2/r.txt"; git -C "$R2" add r.txt; cm "$R2" r
REG="$G/.fable-team/state/scratch-repos.tsv"; REG2="$R2/.fable-team/state/scratch-repos.tsv"
printf '#!/bin/sh\nprintf "p1\\ncinit\\nn/\\n"\n' > "$T/bin/lsof"; chmod 755 "$T/bin/lsof"
sc() { OUT="$(cd "$G" && env PATH="${PBIN:+$PBIN:}$T/bin:$PATH" FT_RES_ROOT="${ROOTX:-$G}" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-o1}" \
  FT_SCRATCH_MAIN=main FT_SCRATCH_MBOX="$T/mailbox.jsonl" ${FG_MODE:+FG_MODE=$FG_MODE} bash "$SUT" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
nrepo() { ls -d "$SCR"/repo-* 2>/dev/null | wc -l | tr -d ' '; }
snap() { ls -d "$SCR"/repo-* 2>/dev/null | sort > "$T/snap"; }                       # 사본 폴더 목록 찍기
newdir() { ls -d "$SCR"/repo-* 2>/dev/null | sort | comm -13 "$T/snap" - | head -1; }  # 찍은 뒤 새로 생긴 폴더
nreg() { awk 'END{print NR}' "$REG" 2>/dev/null; }

# ⓑ 기본 sparse
sc "$(U u1)" --repo "$G"; A="$OUT"
{ [ $RC = 0 ] && [ -f "$A/bin/x.sh" ] && [ -f "$A/tests/t.sh" ] && [ -f "$A/feature-pack/p.md" ] && [ -f "$A/design/harness/h.md" ] \
  && [ -f "$A/design/harness/evidence/r1/a.txt" ]; } && ok "ⓑ 기본 사본에 bin·tests·feature-pack·design/harness(증거 txt) 있음" || bad "ⓑ IN 경로 빠짐 rc=$RC [$OUT][$ERR]"
{ [ ! -e "$A/design/teams/a" ] && [ ! -e "$A/design/teams/b" ] && [ ! -e "$A/design/harness/evidence/r1/a.wav" ]; } \
  && ok "ⓑ 기본 사본에 design/teams/*·evidence 미디어 없음" || bad "ⓑ sparse 아님: $(cd "$A" 2>/dev/null && find design -type f | tr '\n' ' ')"
[ -z "$(git -C "$A" status --porcelain 2>/dev/null)" ] && ok "ⓑ sparse 사본 git status 깨끗" || bad "ⓑ status [$(git -C "$A" status --porcelain | head -3)]"
sc "$(U u1)" --repo "$G"; [ "$OUT" = "$A" ] && ok "ⓑ 같은 sha·주인·규칙 = 재사용" || bad "ⓑ 재사용 아님 [$OUT]"
sc "$(U u1)" --repo "$G" --full; F="$OUT"
{ [ $RC = 0 ] && [ "$F" != "$A" ] && [ -f "$F/design/teams/a/big.md" ] && [ -f "$F/design/teams/b/c.md" ] && [ -f "$F/design/harness/evidence/r1/a.wav" ]; } \
  && ok "ⓑ --full = 통째(sparse 사본을 재사용하지 않음)" || bad "ⓑ --full rc=$RC [$F][$ERR]"
sc "$(U u2)" --repo "$G" --with design/teams/a; W="$OUT"
{ [ $RC = 0 ] && [ -f "$W/design/teams/a/big.md" ] && [ ! -e "$W/design/teams/b" ] && [ -f "$W/bin/x.sh" ]; } \
  && ok "ⓑ --with design/teams/a = 그 경로만 추가" || bad "ⓑ --with rc=$RC [$W][$ERR]"
# ⓑ r8: core.sparseCheckout 이 1·yes(git 은 참)인 sparse 사본을 --full 요청에 재사용하지 않는다
for v in 1 yes; do
  OWN="ob$v" sc "$(U u3)" --repo "$G"; SP="$OUT"; git -C "$SP" config --worktree core.sparseCheckout "$v"
  OWN="ob$v" sc "$(U u3)" --repo "$G" --full
  { [ $RC = 0 ] && [ -n "$OUT" ] && [ "$OUT" != "$SP" ] && [ -d "$SP" ] && [ -f "$OUT/design/teams/a/big.md" ]; } \
    && ok "ⓑ core.sparseCheckout=$v sparse 사본 → --full 재사용 0(새 사본 · 원 사본 그대로)" || bad "ⓑ sparseCheckout=$v 재사용됨 [$SP][$OUT][$ERR]"
done

# ⓩ 생성은 아무것도 안 지움 — 판정 끝난(main 조상) 같은 주인 사본이 있어도 그대로 · AUTO-DONE 줄 0
sc "$M1" --repo "$G"; J1="$OUT"; sc --judged "$J1"; JR=$RC
sc "$(U u3)" --repo "$G"; N3="$OUT"
{ [ "$JR" = 0 ] && [ -d "$J1" ] && grep -q "^$J1	o1	" "$REG" && [ -d "$N3" ] && ! echo "$ERR" | grep -q 'AUTO-DONE'; } \
  && ok "ⓩ 판정 끝난 같은 주인 사본(--judged rc0) = 새 사본 생성 때 지우기 0 · AUTO-DONE 줄 0" || bad "ⓩ judged=$JR J1=$([ -d "$J1" ] && echo 있음 || echo 지워짐) [$ERR]"

# ⓖ' 등록부 = ROOT 등록부 하나(r6) — --repo 가 .fable-team 있는 다른 저장소여도 ROOT 에 1줄 · ROOT --done 이 치움
PK="$T/pack"; mkdir -p "$PK/.fable-team/state"; git init -q -b main "$PK"; printf '.fable-team/\n' > "$PK/.gitignore"; echo p > "$PK/p.txt"
git -C "$PK" add -A; cm "$PK" p; PREG="$PK/.fable-team/state/scratch-repos.tsv"
OWN=o9 sc HEAD --repo "$PK"; K9="$OUT"
{ [ $RC = 0 ] && grep -q "^$K9	o9	" "$REG" && grep -q "^$K9	o9	" "$PREG" 2>/dev/null; } && ok "ⓖ' 다른 저장소(.fable-team 있음) 사본 = ROOT·원 저장소 등록부에 같은 줄(r996 ①)" || bad "ⓖ' 등록부 위치 rc=$RC [$(cat "$PREG" 2>/dev/null)]"
OWN=o9 sc --done "$K9"; { [ $RC = 0 ] && [ ! -d "$K9" ] && ! grep -q "$K9" "$REG" && ! grep -q "$K9" "$PREG"; } && ok "ⓖ' ROOT --done = rc0 · 사본 0 · 두 등록부 줄 0" || bad "ⓖ' --done rc=$RC [$OUT][$ERR]"   # r897 r10: --done 은 «주인 자신» 만(등록 주인 o9 = 실행 주인 o9)

# 대역 git·rm(r7): 호출을 적어 두고 FG_MODE 대로 실패시킨다 — addfail = worktree add 가 그 자리에 폴더(premade)만 남기고 rc128 ·
#   cofail = sparse 뒤 «checkout -q» rc1 · killset = sparse-checkout set 를 마친 직후 부모(ft-scratch-repo)를 TERM 으로 끊음
REALGIT="$(command -v git)"; mkdir -p "$T/fg"
cat > "$T/fg/git" <<EOF
#!/bin/sh
echo "\$*" >> "$T/gitlog"
case "\${FG_MODE:-}:\$*" in
  addfail:*"worktree add"*) p1=""; p2=""; for a in "\$@"; do p2="\$p1"; p1="\$a"; done; mkdir -p "\$p2"; echo keep > "\$p2/premade"; exit 128;;
  cofail:*" checkout -q"*) exit 1;;
  killset:*"sparse-checkout set"*) "$REALGIT" "\$@"; kill -TERM \$PPID; exit 0;;
esac
exec "$REALGIT" "\$@"
EOF
printf '#!/bin/sh\necho "$*" >> "%s/rmlog"\nexec /bin/rm "$@"\n' "$T" > "$T/fg/rm"; chmod 755 "$T/fg/git" "$T/fg/rm"

# ⓩ' worktree add 실패 · sparse 체크아웃 실패 = rc 4 · 지운 것 0(대역 rm·worktree remove 호출 0) · 등록 줄 0 · 그 자리 폴더 그대로
for mode in addfail cofail; do
  : > "$T/gitlog"; : > "$T/rmlog"; snap; NL="$(nreg)"
  PBIN="$T/fg" FG_MODE=$mode OWN=o5 sc "$(U u3)" --repo "$G"; D="$(newdir)"
  { [ $RC = 4 ] && [ "$(nreg)" = "$NL" ] && [ -z "$D" ]; } \
    && ok "ⓩ' $mode = rc4 · 이번 실행이 만든 폴더 = 되돌림(폴더 0) · 등록 줄 0" || bad "ⓩ' $mode rc=$RC 등록 ${NL}→$(nreg) D=[$D] rm=[$(cat "$T/rmlog")] [$ERR]"
done

# ⓡ 등록은 체크아웃 «뒤» 마지막 단계 — sparse set 직후 스크립트가 끊기면 등록 0(등록 줄이 있는 사본 = 체크아웃 끝난 사본)
snap; NL="$(nreg)"
PBIN="$T/fg" FG_MODE=killset OWN=o6 sc "$(U u2)" --repo "$G"; D="$(newdir)"
{ [ -n "$D" ] && [ -d "$D" ] && [ "$(nreg)" = "$((NL+1))" ] && grep -q "^$D	" "$REG" \
  && [ ! -f "$G/.fable-team/state/scratch-ready/${D##*/}" ]; } \
  && ok "ⓡ sparse set 직후 끊김 = 선등록 1줄 남음 · 완성 표식 없음(r996 ⓗ)" || bad "ⓡ rc=$RC D=[$D] 등록 ${NL}→$(nreg)"

# ⓘ --report --orphans = 미등록 사본 표 · 삭제 0 · 못 읽은 등록부 = «부분 읽기»
S8="$(U u3 | cut -c1-8)"; O1="$SCR/repo-$S8-1792860000-111"; git -C "$G" worktree add -q --detach "$O1" "$(U u3)"
O2="$SCR/repo-deadbeef-1792860001-222"; mkdir -p "$O2"
printf '{"seq": 777, "ts": "2026-10-25T01:00:00", "to": "byz-x-arch#1", "from": "byz-x-nano#0", "body": "새 HEAD %s"}\n' "$(U u3)" > "$T/mailbox.jsonl"
PO="$SCR/repo-oldloc-1792860002-333"; git -C "$PK" worktree add -q --detach "$PO" HEAD; printf '%s\to8\t%s\n' "$PO" "$(date +%s)" >> "$PREG"   # 옛 판(원 저장소 등록부)에 적힌 사본
sc --report --orphans
{ [ $RC = 0 ] && printf '%s\n' "$OUT" | grep "^$O1	" | grep -q "	$(U u3)	.*mbox #777 byz-x-nano#0->byz-x-arch#1"; } && ok "ⓘ 미등록 사본 = 경로·HEAD·주인 추정(mbox) 줄" || bad "ⓘ [$OUT][$ERR]"
printf '%s\n' "$OUT" | grep "^$O2	" | grep -q '못 읽음	-	.*	모름$' && ok "ⓘ 못 읽는 사본 = 원 저장소 «못 읽음» · 주인 «모름»" || bad "ⓘ 못 읽음 줄 [$OUT]"
{ ! printf '%s\n' "$OUT" | grep -q "^$A	" && ! printf '%s\n' "$OUT" | grep -q "^$PO	"; } && ok "ⓘ 등록된 사본(ROOT · 옛 판이 적은 원 저장소 등록부)은 표에 없음" || bad "ⓘ 등록 사본이 섞임"
{ [ -d "$O1" ] && [ -d "$O2" ]; } && ok "ⓘ --orphans 는 삭제 0" || bad "ⓘ 삭제됨"
{ [ -n "$D" ] && grep -q "^$D	" "$REG" && ! printf '%s\n' "$OUT" | grep -q "^$D	"; } && ok "ⓘ 끊긴 사본 = 등록부에 보임(선등록) · «미등록» 표에는 안 나옴(r996 ⓗ)" || bad "ⓘ 끊긴 사본 안 보임 [$D]"
OWN=o1 sc HEAD --repo "$PK"; PC="$OUT"; chmod 000 "$PREG"
sc --report --orphans
{ [ $RC = 0 ] && printf '%s\n' "$OUT" | grep -q "^부분 읽기	.*$PREG" && [ -d "$PC" ]; } && ok "ⓘ 못 읽은 등록부 = «부분 읽기» 줄(보고만 · 삭제 0)" || bad "ⓘ 부분 읽기 [$OUT][$ERR]"
chmod 644 "$PREG"

if [ -z "${R891_NO_MUT:-}" ]; then
  # ⓕ 변이: sparse 기본 끔 → ⓑ FAIL · 등록을 체크아웃 전으로(worktree add 앞에 등록 1줄) → ⓡ FAIL
  sed "s#'!/design/teams/\*/'##" "$SUT" > "$T/mut1.sh"
  cat > "$T/r7line" <<'MUT'
    printf '%s\t%s\t%s\n' "$DEST" "$OWNER" "$(date +%s)" >> "$TSV"
MUT
  awk 'NR==FNR{r=$0; next} /^    if \[ "\$FULL" = 1 \]; then git -C/{print r} {print}' "$T/r7line" "$SUT" > "$T/mut2.sh"
  sed 's#config --bool --get core.sparseCheckout#config --get core.sparseCheckout#' "$SUT" > "$T/mut3.sh"   # r8: 불리언 읽기 빼기
  for m in 1 2 3; do cmp -s "$SUT" "$T/mut$m.sh" && bad "ⓕ 변이$m 이 안 바뀜"; bash -n "$T/mut$m.sh" 2>/dev/null || bad "ⓕ 변이$m 문법 깨짐(가짜 변이)"; done
  mut() { R891_NO_MUT=1 SCR_SUT="$T/mut$1.sh" bash "$HERE/$(basename "$0")" > "$T/m$1.txt" 2>&1; }
  mut 1; grep -q '^FAIL ⓑ' "$T/m1.txt" && ok "ⓕ 변이1(sparse 기본 끔) → ⓑ FAIL" || bad "ⓕ 변이1 이 살아남음"
  mut 2; grep -q '^FAIL ⓡ' "$T/m2.txt" && ok "ⓕ 변이2(등록 줄 하나 더 — 선등록 중복) → ⓡ FAIL" || bad "ⓕ 변이2 가 살아남음"
  mut 3; grep -q '^FAIL ⓑ sparseCheckout=' "$T/m3.txt" && ok "ⓕ 변이3(--bool 빼기) → ⓑ sparseCheckout 칸 FAIL" || bad "ⓕ 변이3 이 살아남음"
  # ⓔ 기존 scratch 시험 (r548 시험이 test_scratch_repo.sh·census pytest 도 돌린다)
  for t in test_scratch_repo.sh test_scratch_judged_r645.sh test_scratch_sweep_live_cwd_r548.sh; do
    bash "$HERE/$t" > "$T/e.txt" 2>&1; e=$?; [ "$e" = 0 ] && grep -q 'ALL PASS' "$T/e.txt" && ok "ⓔ 기존 $t ALL PASS" || bad "ⓔ $t rc=$e $(grep FAIL "$T/e.txt" | head -2 | tr '\n' ' ')"
  done
  # ⓙ kit 짝 cmp0
  cmp -s "$REPO/harness/bin/ft-scratch-repo.sh" "$REPO/harness/kit/fable-team/bin/ft-scratch-repo.sh" && ok "ⓙ kit 짝 cmp0" || bad "ⓙ kit 짝 다름"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
