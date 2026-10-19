#!/usr/bin/env bash
# test_scratch_repo.sh — ft-scratch-repo.sh (R246): 등록형 저장소 사본(git worktree --detach) · --done 정리 · --report 주인 없는 사본.
# 임시 git 저장소·가짜 tmux·임시 TMPDIR 만 쓴다 — 실 저장소·실 세션·실 TMPDIR 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
SUT="$REPO/harness/bin/ft-scratch-repo.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$SUT" ] || { bad "ft-scratch-repo.sh 없음"; echo "(1 failed)"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G="$T/src"; R="$T/R"; SCR="$T/scratch"; TMPD="$T/tmpdir"; mkdir -p "$G" "$R/.fable-team/state" "$SCR" "$TMPD" "$T/bin"
git -C "$G" init -q && echo a > "$G/a.txt" && git -C "$G" add a.txt && git -C "$G" -c user.name=t -c user.email=t@t commit -q -m c1
SHA="$(git -C "$G" rev-parse HEAD)"
printf '#!/bin/sh\n[ -f "%s/tmuxfail" ] && { echo "no server running" >&2; exit 1; }\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"
printf 'live-owner\n' > "$T/sessions"
sc() { OUT="$(env PATH="$T/bin:$PATH" FT_RES_ROOT="$R" FT_SCRATCH_DIR="$SCR" TMPDIR="$TMPD" FT_SCRATCH_OWNER="${OWN:-live-owner}" bash "$SUT" "$@" 2>&1)"; RC=$?; }
TSV="$R/.fable-team/state/scratch-repos.tsv"
age_reg() { awk -F'\t' -v p="$1" -v t="$(( $(date +%s) - $2 ))" 'BEGIN{OFS="\t"} $1==p{$3=t} {print}' "$TSV" > "$TSV.n" && mv "$TSV.n" "$TSV"; }   # 등록 시각을 <초> 전으로

sc "$SHA" --repo "$G"; P="$OUT"
{ [ $RC = 0 ] && [ -f "$P/a.txt" ] && [ "$(dirname "$P")" = "$SCR" ] && grep -q "^$P	live-owner	" "$TSV"; } \
  && ok "ⓐ 사본 생성(detach worktree) · 경로 출력 · 등록 줄(경로·주인·시각)" || bad "ⓐ rc=$RC out=$OUT tsv=$(cat "$TSV" 2>/dev/null)"
[ "$(git -C "$P" rev-parse HEAD)" = "$SHA" ] && ok "ⓐ 요청한 sha 그대로" || bad "ⓐ sha 불일치"
sc --report;            { [ $RC = 0 ] && ! echo "$OUT" | grep -q "$P"; } && ok "ⓑ 주인 세션 살아 있으면 보고 대상 아님" || bad "ⓑ $OUT"
OWN=gone-owner sc "$SHA" --repo "$G"; P2="$OUT"; age_reg "$P2" 90000
sc --report;            { echo "$OUT" | grep -q "$P2" && ! echo "$OUT" | grep -q "$P	"; } && ok "ⓒ 주인 세션 없는 사본만 보고" || bad "ⓒ $OUT"
sc --report --summary;  echo "$OUT" | grep -q '^주인 없는 임시 사본 1개 ' && ok "ⓓ --summary 한 줄" || bad "ⓓ [$OUT]"
mkdir -p "$TMPD/tmp.old1" "$TMPD/tmp.new1"; echo x > "$TMPD/tmp.old1/f"; touch -t 202001010000 "$TMPD/tmp.old1"
sc --report;            { echo "$OUT" | grep -q 'tmp.old1' && ! echo "$OUT" | grep -q 'tmp.new1'; } && ok "ⓔ TMPDIR tmp.* 는 24h 지난 것만" || bad "ⓔ $OUT"
sc --report --summary;  echo "$OUT" | grep -q '^주인 없는 임시 사본 2개 ' && ok "ⓔ 요약에 합산(2개)" || bad "ⓔ [$OUT]"
[ -d "$TMPD/tmp.old1" ] && [ -d "$P2" ] && ok "ⓕ --report 는 삭제 0" || bad "ⓕ 삭제됨"
sc --done "$P";         { [ $RC = 0 ] && [ ! -d "$P" ] && ! grep -q "^$P	" "$TSV"; } && ok "ⓖ --done = worktree 제거 + 등록 줄 삭제" || bad "ⓖ rc=$RC $OUT"
git -C "$G" worktree list | grep -q "$P" && bad "ⓖ git worktree 목록에 남음" || ok "ⓖ git worktree 목록에서도 제거"
sc --done "$G";         { [ $RC != 0 ] && [ -d "$G" ]; } && ok "ⓗ 등록 안 된 경로는 --done 거부" || bad "ⓗ rc=$RC"
rm -f "$TSV"; sc --report; echo "$OUT" | grep -q 'No such file' && bad "ⓙ 등록 파일 없을 때 --report 에러" || ok "ⓙ 등록 파일 없어도 --report 정상"
# --sweep (판정 1920): 첫 1회 = 목록 보고만(실삭제 0) · 그 뒤부터 자동 삭제 · 주인 있는 사본·24h 안 tmp.* 는 건드리지 않는다
sc "$SHA" --repo "$G"; L="$OUT"; OWN=gone-owner sc "$SHA" --repo "$G"; D1="$OUT"; age_reg "$D1" 90000
mkdir -p "$TMPD/tmp.old2"; echo y > "$TMPD/tmp.old2/f"; touch -t 202001010000 "$TMPD/tmp.old2"
sc --sweep
{ [ $RC = 0 ] && echo "$OUT" | grep -q '목록 보고' && echo "$OUT" | grep -q '실삭제 0' && [ -d "$D1" ] && [ -d "$TMPD/tmp.old1" ] && [ -d "$TMPD/tmp.old2" ]; } \
  && ok "ⓚ 첫 --sweep = 목록 보고만 · 실삭제 0" || bad "ⓚ rc=$RC out=$OUT"
sc --sweep
{ [ $RC = 0 ] && echo "$OUT" | grep -q '자동 삭제' && [ ! -d "$D1" ] && [ ! -d "$TMPD/tmp.old1" ] && [ ! -d "$TMPD/tmp.old2" ]; } \
  && ok "ⓛ 둘째 --sweep = 주인 없는 사본·24h 지난 tmp.* 삭제" || bad "ⓛ rc=$RC out=$OUT"
{ [ -d "$L" ] && [ -d "$TMPD/tmp.new1" ]; } && ok "ⓜ 주인 살아 있는 사본·새 tmp.* 는 남음" || bad "ⓜ 지워짐"
git -C "$G" worktree list | grep -q "$D1" && bad "ⓛ worktree 목록에 남음" || ok "ⓛ git worktree 목록에서도 제거"
sc --sweep; [ -z "$OUT" ] && ok "ⓝ 지울 것 없으면 출력 0" || bad "ⓝ [$OUT]"
# DA⑥ HOLD3: ①tmux 목록 실패 ≠ 세션 0 ②주인 '-' 등록 거부 · ③(r444) 등록 사본은 나이 문턱 0 — 주인이 죽으면 즉시 후보
OWN=gone-owner sc "$SHA" --repo "$G"; Y="$OUT"; age_reg "$Y" 60
sc --report; echo "$OUT" | grep -q "$Y" && ok "ⓞ 주인 없음+생성 1분 → 즉시 후보(r444)" || bad "ⓞ 주인 없음 1분 후보 아님 $OUT"
touch "$T/tmuxfail"; sc --report
{ ! echo "$OUT" | grep -q "$Y" && echo "$OUT" | grep -q 'ERROR tmux 목록 실패 — 등록 사본 판정 생략'; } && ok "ⓟ tmux 목록 실패 → 등록 사본 후보 0 + ERROR" || bad "ⓟ $OUT"
mkdir -p "$TMPD/tmp.old3"; touch -t 202001010000 "$TMPD/tmp.old3"; sc --report; echo "$OUT" | grep -q 'tmp.old3' && ok "ⓟ tmux 실패여도 tmp.* 판정은 계속" || bad "ⓟ tmp.* 판정 중단 $OUT"
sc --sweep; { [ -d "$Y" ] && [ -d "$TMPD/tmp.old3" ] && echo "$OUT" | grep -q '^ERROR tmux unreadable'; } && ok "ⓟ tmux 실패 중 --sweep = ERROR 1줄(stdout) + 삭제 0(tmp.* 포함 · r444)" || bad "ⓟ sweep tmux 실패 [$OUT]"
rm -f "$T/tmuxfail"
before="$(git -C "$G" worktree list | wc -l)"; OWN=- sc "$SHA" --repo "$G"
{ [ $RC != 0 ] && [ "$(git -C "$G" worktree list | wc -l)" = "$before" ] && echo "$OUT" | grep -q '주인'; } && ok "ⓠ 주인 '-' → 등록 거부 rc≠0 · worktree 0" || bad "ⓠ rc=$RC out=$OUT"
sc "nosuchref" --repo "$G"; [ $RC != 0 ] && ok "ⓘ 없는 ref → 실패 rc≠0(조용한 성공 0)" || bad "ⓘ rc=$RC"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
