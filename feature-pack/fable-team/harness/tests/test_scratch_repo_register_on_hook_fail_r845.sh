#!/usr/bin/env bash
# test_scratch_repo_register_on_hook_fail_r845.sh — r845 (재설계 r6 · 오빠 결정 10-27 «tmp 에 임시를 쌓으면 재부팅에 정리된다») ft-scratch-repo.sh
#   ⓐ post-checkout 훅 exit 4 (--full) → 사본은 그 sha 그대로 생겼다 = stderr WARN 1줄 + 경로 stdout rc0 + 장부 1줄
#   ⓑ 훅 SIGSEGV(kill -SEGV) → ⓐ 와 같음
#   ⓒ 장부 쓰기 불가(장부 파일 권한 0) → WARN 1줄 · rc0 · 사본 그대로 (장부는 «있으면 참고» — die 0)
#   ⓓ --done/--sweep 은 출구 게이트(r897: 등록 정확히 1줄 ∧ 사본 자리 아래 ∧ 이름꼴 ∧ 분리 워크트리)를 통과할 때만 지운다 — 깨진 줄(칸 5개) · 이름꼴 아닌 사본 = 삭제 0
#   ⓕ FT_SCRATCH_DIR 없으면 기본 생성 자리 = $TMPDIR/ft-scratch/<주인>/ (재부팅이 지우는 임시 자리)
#   ⓗ (r7 반송서 ⓕ) 등록 사본이 «그 줄 주인의 사본 자리(베이스) 아래» 가 아니면 --done/--sweep 모두 삭제 0 · 거절 1줄 · 장부 유지 (r897 게이트 G1 이 그 자리를 지킨다 · 옛 3칸 줄은 TMPDIR·FT_SCRATCH_DIR 만 베이스로 인정)
#   ⓘ (r7 반송서 ⓖ) 훅 rc0 이어도 완전성 확인은 항상 — 생성 중 파일 이동·HEAD 바꿈(--full·sparse 둘 다) = rc4 · 등록 0
#   ⓚ (r8 반송서) 같은 sha 재사용도 «온전한 사본» 일 때만 — 더러운 기존 사본은 돌려주지 않고 WARN 1줄 + 새 사본(그 사본은 status 깨끗) · 더러운 사본은 삭제 0 · 장부 유지 · --full·sparse 둘 다
#   ⓖ 기존 scratch 시험 4종 ALL PASS(동작 변화 0) · kit 짝 cmp0 · /bin/bash(bash 3.2) 로 같은 시험 1회
#   변이 5: «장부 실패 = die» → ⓒ FAIL · «게이트 검사 끔» → ⓓ/ⓗ FAIL · «완전성 확인 건너뜀» → ⓘ/ⓚ FAIL
#           «owner 경계 제거» → ⓗ FAIL · «rc0 훅 완전성 건너뜀» → ⓘ FAIL · «재사용 완전성 확인 끔» → ⓚ FAIL
# 임시 git 저장소·임시 훅 폴더·가짜 tmux·가짜 lsof·임시 TMPDIR 만 쓴다 — 실 저장소·실 장부·실 사본·실 TMPDIR 0.
# SCR_SUT=<경로> 로 시험 대상을 바꿀 수 있다(기준판 before-red · 변이). R845_FAST=1 = 변이·기존 4종·bash32 생략(변이 재귀용).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="${SCR_SUT:-$REPO/harness/bin/ft-scratch-repo.sh}"
SH="${BASH:-bash}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음 ($SUT)"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; BIN="$T/bin"; HOOKS="$T/hooks"
mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$BIN" "$HOOKS"
cm() { git -C "$1" -c user.name=t -c user.email=t@t commit -q -m "$2"; }
git init -q -b main "$G"; printf '.fable-team/\n' > "$G/.gitignore"; echo a > "$G/a.txt"
git -C "$G" add -A; cm "$G" c1; SHA="$(git -C "$G" rev-parse HEAD)"
STATE="$R/.fable-team/state"; TSV="$STATE/scratch-repos.tsv"; ARMED="$STATE/scratch-sweep.armed"
printf 'live-owner\n' > "$T/sessions"   # tmux 세션 목록(가짜) = 이 한 줄 — 다른 주인은 «주인 없음»
printf '#!/bin/sh\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" > "$BIN/tmux"
printf '#!/bin/sh\nprintf "p1\\ncinit\\nn/\\n"\n' > "$BIN/lsof"   # cwd 를 쓰는 프로세스 0(기준 pid 1 = 루트)
chmod 755 "$BIN/tmux" "$BIN/lsof"
git -C "$G" config core.hooksPath "$HOOKS"
hook() { # <exit4|segv|ok> — worktree add 안에서 도는 post-checkout 훅
  case "$1" in
    exit4) printf '#!/bin/sh\nexit 4\n' > "$HOOKS/post-checkout";;
    segv)  printf '#!/bin/sh\nkill -SEGV $$\n' > "$HOOKS/post-checkout";;
    ok)    printf '#!/bin/sh\nexit 0\n' > "$HOOKS/post-checkout";;
  esac
  chmod 755 "$HOOKS/post-checkout"
}
SCRDIR="$SCR"   # 기본 = FT_SCRATCH_DIR 를 명시(ⓕ 에서만 비운다)
sc() { # 접두 env 는 «따옴표 그대로» 넘긴다 — 단어 분리로 탭·줄바꿈 경로가 갈라지면 ⓔ 가 거짓 통과한다
  OUT="$(FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCRDIR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" FT_SCRATCH_MAIN=main \
    PATH="$BIN:$PATH" "$SH" "$SUT" "$@" 2>"$T/err")"; RC=$?; ERR="$(cat "$T/err")"; }
nreg()  { awk 'END{print NR+0}' "$TSV" 2>/dev/null; }
regline() { awk -F'\t' -v p="$1" '$1==p' "$TSV" 2>/dev/null | wc -l | tr -d ' '; }   # r897 정본 장부 = 4칸 · 옛 3칸도 같은 줄로 센다

# ── ⓐ 훅 exit 4 (--full: post-checkout 훅이 실제로 도는 경로) ──────────────────────────────
hook exit4
sc "$SHA" --repo "$G" --full; A="$OUT"
{ [ $RC = 0 ] && [ -n "$A" ] && [ -d "$A" ] && [ -f "$A/a.txt" ] && [ "$(git -C "$A" rev-parse HEAD 2>/dev/null)" = "$SHA" ] \
  && printf '%s' "$ERR" | grep -q '사본 생성됨' && [ "$(regline "$A")" = 1 ] && git -C "$G" worktree list | grep -q "$A"; } \
  && ok "ⓐ 훅 exit 4 → 사본은 그 sha 로 생김 · WARN 1줄 · 경로 rc0 · 장부 1줄" || bad "ⓐ rc=$RC out=[$A] err=[$ERR] reg=$(regline "$A")"

# ── ⓑ 훅 SIGSEGV ─────────────────────────────────────────────────────────────────────
hook segv
OWN=segv-owner sc "$SHA" --repo "$G" --full; B="$OUT"
{ [ $RC = 0 ] && [ -n "$B" ] && [ -d "$B" ] && [ -f "$B/a.txt" ] && [ "$(git -C "$B" rev-parse HEAD 2>/dev/null)" = "$SHA" ] \
  && printf '%s' "$ERR" | grep -q '사본 생성됨' && [ "$(regline "$B")" = 1 ]; } \
  && ok "ⓑ 훅 SIGSEGV(rc139) → ⓐ 와 같음(사본 쓸 수 있음 · WARN · rc0)" || bad "ⓑ rc=$RC out=[$B] err=[$ERR]"

# ── ⓒ 장부 쓰기 불가 = WARN 만 (die 0) ────────────────────────────────────────────────
hook ok
echo b > "$G/b.txt"; git -C "$G" add -A; cm "$G" c2; SHA2="$(git -C "$G" rev-parse HEAD)"
chmod 400 "$TSV"   # 폴더 권한이 아니라 «장부 파일» 쓰기를 막는다(이미 있는 파일은 폴더 권한과 무관하게 쓸 수 있다)
OWN=no-ledger sc "$SHA2" --repo "$G" --full; C="$OUT"
{ [ $RC = 0 ] && [ -n "$C" ] && [ -d "$C" ] && [ -f "$C/b.txt" ] && printf '%s' "$ERR" | grep -q '장부 등록 실패' && [ "$(regline "$C")" = 0 ]; } \
  && ok "ⓒ 장부 쓰기 불가 → WARN 1줄 · rc0 · 사본 그대로(장부 0줄)" || bad "ⓒ rc=$RC out=[$C] err=[$ERR] reg=$(regline "$C")"
chmod 600 "$TSV"; [ -w "$TSV" ] && ok "ⓒ 장부 파일 권한 복구" || bad "ⓒ 권한 복구 실패 $TSV"

# ── ⓓ 지우기 = 출구 게이트(등록 1줄 ∧ 사본 자리 아래 ∧ 사본 증명) — 깨진 줄·이름꼴 아닌 사본 = 삭제 0 ──────
D1="$A"   # ⓐ 의 진짜 detached 워크트리 · 장부 줄을 «칸 5개 깨진 줄» 로 바꾼다
awk -F'\t' -v OFS='\t' -v p="$D1" -v t="$(( $(date +%s) - 90000 ))" 'BEGIN{OFS="\t"} $1==p{print p,"live-owner",t,"/tmp","extra"; next} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
date +%s > "$ARMED"   # 목록 보고 단계를 건너뛰고 «지우기» 단계로
sc --done "$D1"; { [ $RC = 2 ] && [ -d "$D1" ] && printf '%s' "$ERR" | grep -q '칸 깨짐'; } \
  && ok "ⓓ 깨진 장부 줄(칸 5개) = --done 거부 rc2 · 사본 그대로" || bad "ⓓ --done rc=$RC err=[$ERR] D1=$([ -d "$D1" ] && echo 있음 || echo 없음)"
# --sweep 후보가 되려면 주인이 tmux 에 없어야 한다(가짜 tmux = live-owner 한 줄) — 주인 칸만 dead-owner 로 바꾼다
awk -F'\t' -v OFS='\t' -v p="$D1" 'BEGIN{OFS="\t"} $1==p{$2="dead-owner"; print; next} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
sc --sweep; { [ -d "$D1" ] && printf '%s' "$ERR" | grep -q '칸 깨짐'; } \
  && ok "ⓓ --sweep 도 깨진 줄은 지우지 않는다(경고 1줄 · 삭제 0)" || bad "ⓓ sweep err=[$ERR] D1=$([ -d "$D1" ] && echo 있음 || echo 없음)"
D2="$SCR/notrepo-1-2"; git -C "$G" worktree add -q --detach "$D2" "$SHA" >/dev/null 2>&1   # 사본이긴 한데 이름꼴이 다르다
printf '%s\t%s\t%s\t%s\n' "$D2" "live-owner" "$(date +%s)" "$SCR" >> "$TSV"
sc --done "$D2"; { [ $RC = 2 ] && [ -d "$D2" ] && printf '%s' "$ERR" | grep -q '이름꼴'; } \
  && ok "ⓓ 이름꼴 다른 사본 = --done 거부 rc2 · 폴더 그대로" || bad "ⓓ 이름꼴 rc=$RC err=[$ERR]"
sc --sweep; [ -d "$D2" ] && ok "ⓓ --sweep 도 이름꼴 아닌 줄은 삭제 0" || bad "ⓓ sweep 이 이름꼴 아닌 폴더 삭제"
awk -F'\t' -v p="$D2" '$1!=p' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
git -C "$G" worktree remove --force "$D2" >/dev/null 2>&1

# ── ⓕ 기본 생성 자리 = $TMPDIR/ft-scratch/<주인>/ ───────────────────────────────────
SCRDIR= OWN=f-owner sc "$SHA" --repo "$G" --full; F="$OUT"
{ [ $RC = 0 ] && [ -n "$F" ] && [ -d "$F" ] && [ "$(dirname "$F")" = "$TMPD/ft-scratch/f-owner" ]; } \
  && ok "ⓕ FT_SCRATCH_DIR 없으면 \$TMPDIR/ft-scratch/<주인>/ 아래에 만든다(재부팅 정리 자리)" || bad "ⓕ rc=$RC out=[$F] (기대 $TMPD/ft-scratch/f-owner)"
SCRDIR="$SCR"

# ── ⓗ (r7) 지우기 경계 = 그 줄 주인의 사본 자리 아래 (남의 owner 폴더·자리 밖 = 삭제 0 · WARN · 장부 유지) ──────
OLD=$(( $(date +%s) - 90000 ))
wtadd() { git -C "$G" worktree add -q --detach "$1" "$2" >/dev/null 2>&1; }   # <경로> <sha> — 진짜 detached 워크트리
OTHER="$TMPD/ft-scratch/other-owner/repo-11111111-1-2"; mkdir -p "$(dirname "$OTHER")"; wtadd "$OTHER" "$SHA"
printf '%s\t%s\t%s\n' "$OTHER" "live-owner" "$OLD" >> "$TSV"   # 장부 주인 = 내 이름 · 폴더 = 남의 owner
OUTSIDE="$TMPD/elsewhere/repo-22222222-1-2"; mkdir -p "$TMPD/elsewhere"; wtadd "$OUTSIDE" "$SHA"
printf '%s\t%s\t%s\n' "$OUTSIDE" "live-owner" "$OLD" >> "$TSV"   # 사본 자리 밖
MINE="$TMPD/ft-scratch/dead-owner/repo-33333333-1-2"; mkdir -p "$(dirname "$MINE")"; wtadd "$MINE" "$SHA"
printf '%s\t%s\t%s\t%s\n' "$MINE" "dead-owner" "$OLD" "$TMPD/ft-scratch/dead-owner" >> "$TSV"        # 정상(경계 안 · 주인 없는 세션) = 지워져야 한다(«항상 거절» 이면 이 칸이 FAIL)
DEAD="$TMPD/ft-scratch/live-owner/repo-44444444-1-2"; wtadd "$DEAD" "$SHA"
printf '%s\t%s\t%s\n' "$DEAD" "dead-owner" "$OLD" >> "$TSV"       # 장부 주인(없는 세션) ≠ 폴더 주인 → --sweep 도 건너뜀
SCRDIR=   # 사본 자리 = $TMPDIR/ft-scratch/<주인>/ 규칙으로 본다
sc --done "$OTHER"; { [ $RC = 2 ] && [ -d "$OTHER" ] && [ "$(regline "$OTHER")" = 1 ] && printf '%s' "$ERR" | grep -q '베이스 바로 아래'; } \
  && ok "ⓗ 남의 owner 폴더 등록 사본(옛 3칸 줄) --done → rc2 · 거절 · 삭제 0 · 장부 유지" || bad "ⓗ 남의 owner rc=$RC err=[$ERR] 있음=$([ -d "$OTHER" ] && echo Y || echo N) reg=$(regline "$OTHER")"
sc --done "$OUTSIDE"; { [ $RC = 2 ] && [ -d "$OUTSIDE" ] && [ "$(regline "$OUTSIDE")" = 1 ] && printf '%s' "$ERR" | grep -q '베이스 바로 아래'; } \
  && ok "ⓗ 사본 자리 밖 등록 사본 --done → rc2 · 거절 · 삭제 0 · 장부 유지" || bad "ⓗ 자리 밖 rc=$RC err=[$ERR]"
sc --sweep; { [ -d "$OTHER" ] && [ -d "$OUTSIDE" ] && [ -d "$DEAD" ] && [ "$(regline "$OTHER")" = 1 ] && [ "$(regline "$DEAD")" = 1 ] && printf '%s' "$ERR" | grep -q '베이스 바로 아래'; } \
  && ok "ⓗ --sweep 은 자리 밖·주인 다른 줄을 지우지 않는다(삭제 0 · 장부 유지 · WARN)" || bad "ⓗ sweep err=[$ERR] 경계밖=$([ -d "$OTHER" ] && echo Y || echo N)/$([ -d "$DEAD" ] && echo Y || echo N)"
{ [ ! -d "$MINE" ] || [ "$(regline "$MINE")" = 0 ]; } \
  && ok "ⓗ 자리 안 정상 사본(4칸)은 --sweep 이 지운다(검사가 «항상 거절» 이 아님)" || bad "ⓗ 정상 사본 미삭제 MINE=$([ -d "$MINE" ] && echo 있음 || echo 없음)"
awk -F'\t' -v p1="$OTHER" -v p2="$OUTSIDE" -v p3="$DEAD" -v p4="$MINE" '$1!=p1 && $1!=p2 && $1!=p3 && $1!=p4' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"
git -C "$G" worktree remove --force "$OTHER" >/dev/null 2>&1; git -C "$G" worktree remove --force "$OUTSIDE" >/dev/null 2>&1; git -C "$G" worktree remove --force "$DEAD" >/dev/null 2>&1
SCRDIR="$SCR"

# ── ⓘ (r7) 훅 rc0 이어도 완전성 확인은 항상 (파일 이동 · HEAD 바꿈 = rc4 · 등록 0) ────────────
hookmove() { printf '#!/bin/sh\nmv a.txt moved.txt 2>/dev/null\nexit 0\n' > "$HOOKS/post-checkout"; chmod 755 "$HOOKS/post-checkout"; }
hookhead() { printf '#!/bin/sh\ngit update-ref HEAD %s 2>/dev/null\nexit 0\n' "$SHA2" > "$HOOKS/post-checkout"; chmod 755 "$HOOKS/post-checkout"; }
for mode in --full --sparse; do
  for kind in move head; do
    if [ "$kind" = move ]; then hookmove; else hookhead; fi
    N1="$(nreg)"
    OWN="i-$kind-$mode"   # r444 재사용을 피한다(같은 sha·같은 주인 = 기존 사본을 돌려줘 훅이 안 돈다)
    if [ "$mode" = --full ]; then sc "$SHA" --repo "$G" --full; else sc "$SHA" --repo "$G"; fi
    { [ $RC = 4 ] && printf '%s' "$ERR" | grep -q '온전하지 않음' && [ "$(nreg)" = "$N1" ] && { [ -z "$OUT" ] || [ "$(regline "$OUT")" = 0 ]; }; } \
      && ok "ⓘ 훅 rc0 + $kind ($mode) → rc4 · 등록 0" || bad "ⓘ $kind $mode rc=$RC out=[$OUT] err=[$ERR] reg=$(nreg)/$N1"
  done
done
hook ok

# ── ⓚ (r8) 같은 sha 재사용도 온전한 사본만 (더러운 기존 사본은 돌려주지 않는다) ──────────────
reuse_case() { # <mode: --full|--sparse> <owner> — 재사용은 «같은 주인·같은 sha·같은 체크아웃 규칙» 일 때만 타진다
  local mode="$1" own="$2" p1 p2 n1
  if [ "$mode" = --full ]; then OWN="$own" sc "$SHA" --repo "$G" --full; else OWN="$own" sc "$SHA" --repo "$G"; fi
  p1="$OUT"; [ -d "$p1" ] || { bad "ⓚ($mode) 첫 사본을 안 만들었다 rc=$RC err=[$ERR]"; return; }
  mv "$p1/a.txt" "$p1/moved.txt"   # DA 반례 그대로: 첫 사본의 a.txt 가 moved.txt 로 옴겨졌다(rc0 · 끝은 정상)
  n1="$(nreg)"
  if [ "$mode" = --full ]; then OWN="$own" sc "$SHA" --repo "$G" --full; else OWN="$own" sc "$SHA" --repo "$G"; fi
  p2="$OUT"
  { [ $RC = 0 ] && [ -n "$p2" ] && [ "$p2" != "$p1" ] && [ -d "$p2" ] && [ -z "$(git -C "$p2" status --porcelain 2>/dev/null)" ] \
    && printf '%s' "$ERR" | grep -q '불완전 사본 건너뜀' && [ -d "$p1" ] && [ "$(regline "$p1")" = 1 ] && [ "$(nreg)" = "$((n1+1))" ]; } \
    && ok "ⓚ ($mode) 더러운 사본 재사용 0 → 새 사본(깨끗) · WARN 1줄 · 더러운 사본 삭제 0 · 장부 유지" \
    || bad "ⓚ ($mode) rc=$RC p1=[$p1] p2=[$p2] err=[$ERR] p1있음=$([ -d "$p1" ] && echo Y || echo N) reg=$(regline "$p1") nreg=$(nreg)/$((n1+1))"
}
reuse_case --full k-full
reuse_case --sparse k-sparse
reuse_case --sparse k-sparse2   # 같은 주인의 sparse 사본이 이미 더러운 상태에서 한 번 더(반복 요청)

if [ -z "${R845_FAST:-}" ]; then
  # ── ⓖ 기존 scratch 시험 4종(동작 변화 0) · kit 짝 cmp0 · bash 3.2 ─────────────────
  for t in test_scratch_repo.sh test_scratch_judged_r645.sh test_scratch_sweep_live_cwd_r548.sh test_scratch_repo_sparse_auto_done_r891.sh; do
    bash "$HERE/$t" > "$T/e.txt" 2>&1; e=$?
    { [ "$e" = 0 ] && grep -q '^ALL PASS' "$T/e.txt"; } && ok "ⓖ 기존 $t ALL PASS" || bad "ⓖ 기존 $t rc=$e $(grep '^FAIL' "$T/e.txt" | head -2 | tr '\n' ' ')"
  done
  cmp -s "$REPO/harness/bin/ft-scratch-repo.sh" "$REPO/harness/kit/fable-team/bin/ft-scratch-repo.sh" \
    && ok "ⓖ kit 짝 cmp0" || bad "ⓖ kit 짝 다름"
  env R845_FAST=1 /bin/bash "$HERE/$(basename "$0")" > "$T/b32.txt" 2>&1; b=$?
  { [ "$b" = 0 ] && grep -q '^ALL PASS' "$T/b32.txt"; } && ok "ⓖ /bin/bash(bash 3.2) 로 같은 시험 ALL PASS" || bad "ⓖ bash3.2 rc=$b $(grep '^FAIL' "$T/b32.txt" | head -2 | tr '\n' ' ')"

  # ── 변이 3: 계약을 되돌리면 그 칸이 FAIL ─────────────────────────────────────────
  grep -v -F 'WARN ft-scratch-repo — 장부 등록 실패 · 사본은 그대로 만들고 쓴다' "$SUT" > "$T/mut1.sh"   # 장부 실패 경고 삭제(r996: reg_write 실패 WARN 1줄)
  grep -v -F '[[ ${P##*/} =~ $re ]] || { gfail G2 3' "$SUT" > "$T/mut2.sh"
  grep -v -F 'gate_base "$P"' "$SUT" > "$T/mut4.sh"   # 출구 게이트의 «베이스 바로 아래»(G1) 검사 제거
  grep -v -F 'verify_complete || { gen_rollback "$DEST" "온전성 확인"' "$SUT" > "$T/mut5.sh"   # 훅 rc0 일 때 완전성 확인 건너뜀(r996: 실패 = 되돌림 + die)
  awk 'index($0, "if verify_complete \"$p\"; then echo") > 0 { sub(/if verify_complete "\$p"; then echo/, "if true; then echo"); print; next } { print }' "$SUT" > "$T/mut6.sh"   # 재사용 완전성 확인 끔
  for m in 1 2 4 5 6; do
    cmp -s "$SUT" "$T/mut$m.sh" && bad "변이$m 이 안 바뀜"
    "$SH" -n "$T/mut$m.sh" 2>/dev/null || bad "변이$m 문법 깨짐(가짜 변이)"
  done
  mut() { env R845_FAST=1 SCR_SUT="$T/mut$1.sh" "$SH" "$HERE/$(basename "$0")" > "$T/m$1.txt" 2>&1; }
  mut 1; grep -q '^FAIL ⓒ' "$T/m1.txt" && ok "변이1(장부 실패 경고 삭제) → ⓒ FAIL" || bad "변이1 이 살아남음 $(grep '^FAIL' "$T/m1.txt" | head -2 | tr '\n' ' ')"
  mut 2; grep -q '^FAIL ⓓ' "$T/m2.txt" && ok "변이2(출구 게이트 이름꼴 검사 끔) → ⓓ FAIL" || bad "변이2 가 살아남음 $(grep '^FAIL' "$T/m2.txt" | head -2 | tr '\n' ' ')"
  mut 4; grep -q '^FAIL ⓗ' "$T/m4.txt" && ok "변이4(게이트 G1 베이스 검사 제거) → ⓗ FAIL" || bad "변이4 가 살아남음 $(grep '^FAIL' "$T/m4.txt" | head -2 | tr '\n' ' ')"
  mut 5; grep -q '^FAIL ⓘ' "$T/m5.txt" && ok "변이5(rc0 훅 완전성 건너뜀) → ⓘ FAIL" || bad "변이5 가 살아남음 $(grep '^FAIL' "$T/m5.txt" | head -2 | tr '\n' ' ')"
  mut 6; grep -q '^FAIL ⓚ' "$T/m6.txt" && ok "변이6(재사용 완전성 확인 끔) → ⓚ FAIL" || bad "변이6 이 살아남음 $(grep '^FAIL' "$T/m6.txt" | head -2 | tr '\n' ' ')"
fi

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
