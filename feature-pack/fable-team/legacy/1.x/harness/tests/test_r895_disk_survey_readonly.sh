#!/usr/bin/env bash
# test_r895_disk_survey_readonly.sh — 카드 r895: 디스크 조사 스크립트 2종(evidence/r895/measure.sh · scratch.sh)이 «읽기만» 하고 표 칸을 맞게 채우는가.
#   ⓐ실행 뒤 픽스처 리포·워크트리·임시 사본 안에 바뀐 파일 0(find -newer) · refs·worktree 목록 그대로 ⓑ착지(조상/아님) · 주인 tmux · 미커밋 칸
#   ⓒ같은 HEAD 사본 묶음(dup) ⓓtmp_pack 잔재 행 ⓔ등록 사본 실재·주인 칸 · 등록 안 된 repo-* 행
#   ⓕlanded.sh: squash 착지 = 내용착지 · 미착지(다른/바꾼) · 경로만 넣으면 사본 HEAD 를 읽음
#   ⓖsparse.sh: core.sparseCheckout 칸 · info/sparse-checkout 실재 ⓗcandidates.py: classified+sparse 를 «한 줄=한 후보» 로 합친다 (r2 신규 2종)
#   ⓘ정적 검사: 스크립트 8개에 지우기·되쓰기 호출(rm · mv · git gc/repack · --prune · worktree remove/prune · branch -d|-D)이 원문에 없다 — 옵션 없는 `rm x` · 줄 머리 공백이 든 `  mv x y` 까지 잡는다
#     알려진 한계 1줄: 이 검사는 원문 문자열만 본다 — 별칭·변수(`$RM`)·`find -delete`·`git clean`·`sh -c "…"` 안에 숨긴 호출은 못 잡는다(그 꼴은 픽스처의 «바뀐 파일 0» 이 잡는다).
#   ⓙclassify.py --replay: 등록 사본이라도 detached 아님 → 밖:나노 밖 워크트리 · 미커밋 >0 → 밖:미커밋 · 조건충족(주인 없음 ∧ 24h) 수를 따로 센다 (DA r1 #1·#2)
#   ⓚlanded.sh --branches: 끝난 가지 후보 = 착지 ∧ 워크트리 없음 ∧ 카드가 완성/·아카이브/ 에 있음 · 카드 진행 중·없음은 확정하지 않는다 (DA r1 #3)
#   변이 1: GIT_OPTIONAL_LOCKS=0 제거 → git status 가 index 를 다시 써 ⓐ 실패. 변이 2: orphans.sh 에 `git gc --prune=now` 한 줄을 넣으면 ⓘ 가 잡는다.
# 임시 git 리포 + 가짜 tmux 만 쓴다 — 실 리포·tmux·mbox 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${R895_SRC:-$HERE/../evidence/r895}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }

bash -n "$SRC/measure.sh" && bash -n "$SRC/scratch.sh" && bash -n "$SRC/sparse.sh" && ok "bash -n 3종" || bad "bash -n"
python3 -m py_compile "$SRC/candidates.py" "$SRC/classify.py" && ok "py_compile 2종" || bad "py_compile"

# 픽스처: main 2커밋 · nano/landed(main 조상) · nano/open(미착지 + 미커밋) · dup(landed 와 같은 HEAD · detached) · tmp_pack 잔재
R="$T/repo"; git init -q -b main "$R"; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo a > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm c1; echo b >> "$R/a"; git -C "$R" commit -qam c2
git -C "$R" branch nano/landed HEAD~1
git -C "$R" worktree add -q "$R/.worktrees/v65-landed" nano/landed
git -C "$R" worktree add -q -b nano/open "$R/.worktrees/harness-open" main
echo c > "$R/.worktrees/harness-open/c"; git -C "$R/.worktrees/harness-open" add c; git -C "$R/.worktrees/harness-open" commit -qm c3
echo dirty >> "$R/.worktrees/harness-open/a"
git -C "$R" worktree add -q --detach "$R/.worktrees/dupcopy" nano/landed
head -c 4096 /dev/zero > "$R/.git/objects/pack/tmp_pack_TEST"
# 임시 사본: 등록 1(주인 살아 있음) · 등록 1(사라짐) · 미등록 repo-* 1
export TMPDIR="$T/tmpd/"; mkdir -p "$T/tmpd/repo-reg" "$T/tmpd/repo-unreg"
printf '%s\t%s\t%s\n' "$T/tmpd/repo-reg" "byz-x-nano-open#0" "$(( $(date +%s) - 7200 ))" "$T/tmpd/repo-gone" "byz-dead#1" 1 > "$T/reg.tsv"
mkdir -p "$T/fake"; printf '#!/bin/sh\necho "byz-harness-nano-open#0"\necho "byz-x-nano-open#0"\n' > "$T/fake/tmux"; chmod +x "$T/fake/tmux"
export PATH="$T/fake:$PATH"

run_case() {  # $1 = 스크립트 폴더 → 바뀐 파일 수
  local src="$1" out="$2"
  touch -t "$(date -v-2S +%Y%m%d%H%M.%S)" "$R/.worktrees/v65-landed/a"   # stat 만 바뀜 → 잠금 없는 status 는 index 재작성 유혹
  sleep 1; touch "$T/marker"; sleep 1
  refs0="$(git -C "$R" for-each-ref; git -C "$R" worktree list --porcelain)"
  bash "$src/measure.sh" "$R" "$out" >/dev/null 2>&1; bash "$src/scratch.sh" "$T/reg.tsv" "$out" >/dev/null 2>&1
  refs1="$(git -C "$R" for-each-ref; git -C "$R" worktree list --porcelain)"
  [ "$refs0" = "$refs1" ] && r=same || r=changed
  echo "$(find "$R" "$T/tmpd" -newer "$T/marker" -type f | wc -l | tr -d ' ') $r"
}

read -r n r <<<"$(run_case "$SRC" "$T/out" | tail -1)"
[ "$n" = 0 ] && ok "ⓐ 리포·사본 안 바뀐 파일 0" || bad "ⓐ 바뀐 파일 $n"
[ "$r" = same ] && ok "ⓐ refs·worktree 목록 그대로" || bad "ⓐ refs·worktree 목록 바뀜"
W="$(cat "$T/out/repo-worktrees.tsv")"
has "$W" "$R/.worktrees/v65-landed	nano/landed" "ⓑ 착지 가지 행"
has "$(grep v65-landed <<<"$W")" "	조상	" "ⓑ landed = 조상"
has "$(grep harness-open <<<"$W")" "	아님	" "ⓑ open = 아님"
has "$(grep harness-open <<<"$W")" "byz-harness-nano-open#0" "ⓑ 주인 tmux 칸"
has "$(grep harness-open <<<"$W" | cut -f7)" "1" "ⓑ 미커밋 1"
has "$(grep dupcopy <<<"$W")" "(detached)" "ⓑ detached 칸"
has "$(cat "$T/out/repo-dup.tsv")" "	2	" "ⓒ 같은 HEAD 묶음 2"
has "$(cat "$T/out/repo-git.txt")" "tmp_pack_TEST	4	" "ⓓ tmp_pack 잔재 행(4KiB)"
has "$(cat "$T/out/repo-branches.txt")" "nano=2" "가지 수 nano=2"
S="$(cat "$T/out/scratch-registered.tsv")"
has "$(grep repo-reg <<<"$S")" "	2	있음	" "ⓔ 등록 사본 나이 2h · 실재"
has "$(grep repo-reg <<<"$S")" "	있음	없음" "ⓔ 주인 살아 있음 · cwd 0"
has "$(grep repo-gone <<<"$S")" "	없음	0	없음" "ⓔ 사라진 사본 · 주인 없음"
has "$(cat "$T/out/scratch-unregistered.tsv")" "repo-unreg" "ⓔ 미등록 repo-* 행"

# landed.sh: squash 착지(같은 내용을 main 에 따로 커밋) = 내용착지 · 미착지 = 미착지(다른/바꾼) · 사본 경로만 넣어도 HEAD 를 읽음
git -C "$R" branch nano/sq main; git -C "$R" worktree add -q "$T/sqwt" nano/sq
echo s > "$T/sqwt/s"; git -C "$T/sqwt" add s; git -C "$T/sqwt" commit -qm sq
echo s > "$R/s"; git -C "$R" add s; git -C "$R" commit -qm "squash of sq"
printf 'path\tbranch\thead\n%s\tnano/sq\t%s\n%s\tnano/open\t%s\n' "$T/sqwt" "$(git -C "$R" rev-parse --short nano/sq)" "$R/.worktrees/harness-open" "$(git -C "$R" rev-parse --short nano/open)" > "$T/l.in"
printf '%s\n' "$R/.worktrees/dupcopy" >> "$T/l.in"
bash "$SRC/landed.sh" "$R" "$T/l.in" "$T/l.out" >/dev/null 2>&1
L="$(cat "$T/l.out")"
has "$(grep sqwt <<<"$L")" "	내용착지" "landed: squash = 내용착지"
has "$(grep harness-open <<<"$L")" "	미착지(1/1)" "landed: 미착지(다른 1/바꾼 1)"
has "$(grep dupcopy <<<"$L")" "	조상" "landed: 경로만 → HEAD 읽어 조상"

# sparse.sh: 워크트리별 core.sparseCheckout · info/sparse-checkout 실재 (r2 신규 스크립트)
bash "$SRC/sparse.sh" "$T/out/repo-worktrees.tsv" "$T/sp.tsv" >/dev/null 2>&1
has "$(cat "$T/sp.tsv")" "	false	없음	" "sparse: 기본 false · info 없음"
git -C "$R/.worktrees/v65-landed" config core.sparseCheckout true
mkdir -p "$(git -C "$R/.worktrees/v65-landed" rev-parse --git-dir)/info"
printf 'a\n' > "$(git -C "$R/.worktrees/v65-landed" rev-parse --git-dir)/info/sparse-checkout"
bash "$SRC/sparse.sh" "$T/out/repo-worktrees.tsv" "$T/sp2.tsv" >/dev/null 2>&1
has "$(cat "$T/sp2.tsv")" "	true	있음	" "sparse: 켜면 true · info 있음"

# candidates.py: 표를 손으로 만들지 않는다 — classified.tsv + sparse.tsv 를 «한 줄 = 한 후보» 로 합친다 (r2 신규)
mkdir -p "$T/mini"
printf 'path\tbranch\thead\tkib\tdirty\tland\tclass\n%s\tnano/landed\tabc\t2048\t0\t조상\t밖:미커밋\n%s\tnano/open\tdef\t1024\t1\t미착지\t안:nano-close\n' "$R/.worktrees/v65-landed" "$R/.worktrees/harness-open" > "$T/mini/repo-classified.tsv"
printf 'path\tsparse\tinfo_file\tkib\n%s\ttrue\t있음\t2048\n%s\tfalse\t없음\t1024\n' "$R/.worktrees/v65-landed" "$R/.worktrees/harness-open" > "$T/mini/repo-sparse.tsv"
printf 'path\tbranch\thead\tkib\tseat_live\tlanded\tdirty\n%s\tnano/landed\tabc\t2048\t없음\t조상\t0\n' "$R/.worktrees/v65-landed" > "$T/mini/repo-worktrees.tsv"
python3 "$SRC/candidates.py" "$T/mini" >/dev/null 2>&1
C="$(cat "$T/mini/repo-candidates.tsv")"
has "$C" "path	GiB	branch	head	land	real_dirty	class	sparse	owner_hint" "candidates: 칸 9개"
has "$(grep v65-landed <<<"$C")" "	0.00	" "candidates: KiB → GiB"
has "$(grep v65-landed <<<"$C")" "	true	" "candidates: sparse 칸 옮김"
has "$(grep harness-open <<<"$C")" "안:nano-close" "candidates: 분류 옮김"
[ "$(sed -n 2p "$T/mini/repo-candidates.tsv" | cut -f7)" = "안:nano-close" ] && ok "candidates: 안 분류가 먼저" || bad "candidates: 정렬(안 먼저)"

# ⓘ정적 검사: 스크립트 8개 원문에 지우기·되쓰기 호출 0 (주석 제외 · DA r1 #4)
scan_ro() {  # $1 = 폴더 → 0 = 깨끗 · 1 = 금지 호출 있음
  local f hits rc=0
  for f in "$1"/*.sh "$1"/*.py; do
    [ -f "$f" ] || continue
    hits="$(sed -e 's/[[:space:]]*#.*$//' "$f" | grep -nE '(^|[;&|(])[[:space:]]*(rm([[:space:]]|$)|mv([[:space:]]|$))|git[^|;]*[[:space:]](gc|repack)([[:space:]]|$)|--prune|worktree[[:space:]]+(remove|prune)|branch[[:space:]]+-[dD]([[:space:]]|$)')" || true
    [ -z "$hits" ] || { echo "  $f: $hits"; rc=1; }
  done
  return $rc
}
n8="$(ls "$SRC"/*.sh "$SRC"/*.py | wc -l | tr -d ' ')"
[ "$n8" = 8 ] && ok "ⓘ 정적 검사 대상 8개" || bad "ⓘ 스크립트 $n8개(8 이어야)"
if scan_ro "$SRC"; then ok "ⓘ 스크립트 8개에 지우기·되쓰기 호출 0"; else bad "ⓘ 지우기·되쓰기 호출이 있다"; fi
mkdir -p "$T/mut2"; cp "$SRC"/orphans.sh "$T/mut2/"; printf 'git -C "$1" gc --prune=now\n' >> "$T/mut2/orphans.sh"
if scan_ro "$T/mut2"; then bad "변이 2(git gc --prune=now) 를 못 잡음"; else ok "변이 2(git gc --prune=now) 정적 검사가 잡음"; fi
mkdir -p "$T/mut3" "$T/mut4"; cp "$SRC"/orphans.sh "$T/mut3/"; printf '  mv "$1" x\n' >> "$T/mut3/orphans.sh"
cp "$SRC"/orphans.sh "$T/mut4/"; printf 'rm x\n' >> "$T/mut4/orphans.sh"
if scan_ro "$T/mut3"; then bad "변이 3(줄 머리 공백 든 mv) 를 못 잡음"; else ok "변이 3(줄 머리 공백 든 mv) 정적 검사가 잡음"; fi
if scan_ro "$T/mut4"; then bad "변이 4(옵션 없는 rm 단독) 를 못 잡음"; else ok "변이 4(옵션 없는 rm 단독) 정적 검사가 잡음"; fi

# ⓙclassify.py --replay: 등록 사본의 ①detached ∧ 미커밋 0 만 «안» ②가지 붙음 → 밖 ③미커밋 >0 → 밖 ④조건충족(주인 없음 ∧ 24h) 수
M="$T/mini2"; mkdir -p "$M" "$T/T/repo-a" "$T/T/repo-b" "$T/T/repo-c" "$T/T/repo-d"
printf 'path\towner\tage_h\texists\tkib\towner_live\tcwd_held\n%s\tbyz-a#0\t30\t있음\t2\t없음\t없음\n%s\tbyz-b#0\t30\t있음\t2\t없음\t없음\n%s\tbyz-c#0\t5\t있음\t2\t없음\t없음\n' \
  "$T/T/repo-a" "$T/T/repo-b" "$T/T/repo-c" > "$M/scratch-registered.tsv"
printf 'path\tbranch\thead\tkib\tdirty\tland\tclass\n%s\t(detached)\taa\t2048\t0\t조상\t밖:미커밋\n%s\tnano/foo\tbb\t2048\t0\t조상\t밖:미커밋\n%s\t(detached)\tcc\t2048\t3\t조상\t밖:미커밋\n%s\t(detached)\tdd\t2048\t0\t조상\t밖:미커밋\n' \
  "$T/T/repo-a" "$T/T/repo-b" "$T/T/repo-c" "$T/T/repo-d" > "$M/x-classified.tsv"
CL="$(python3 "$SRC/classify.py" "$M" x --replay 2>&1)"; rc=$?
cls_of() { awk -F'\t' -v p="$1" 'FNR>1 && $1==p {print $7}' "$M/x-classified.tsv"; }
[ "$(cls_of "$T/T/repo-a")" = "안:scratch-sweep" ] && ok "ⓙ 등록 ∧ detached ∧ 미커밋 0 = 안:scratch-sweep" \
  || bad "ⓙ repo-a = $(cls_of "$T/T/repo-a")"
[ "$(cls_of "$T/T/repo-b")" = "밖:나노 밖 워크트리" ] && ok "ⓙ 가지에 붙은 사본은 안이 아니다(밖:나노 밖 워크트리)" \
  || bad "ⓙ repo-b = $(cls_of "$T/T/repo-b")"
[ "$(cls_of "$T/T/repo-c")" = "밖:미커밋" ] && ok "ⓙ 미커밋 3 이면 안이 아니다(밖:미커밋)" \
  || bad "ⓙ repo-c = $(cls_of "$T/T/repo-c")"
[ "$(cls_of "$T/T/repo-d")" = "밖:등록 밖 사본" ] && ok "ⓙ 등록부에 줄이 없으면 밖:등록 밖 사본" \
  || bad "ⓙ repo-d = $(cls_of "$T/T/repo-d")"
has "$CL" "조건충족(주인 없음 ∧ 24h)	1	" "ⓙ 조건충족 = detached·미커밋 0 이면서 주인 없음·24h 인 것만 1개"
[ "$rc" = 0 ] && ok "ⓙ replay rc=0" || bad "ⓙ replay rc=$rc"

# ⓚlanded.sh --branches: 착지 ∧ 워크트리 없음 ∧ 카드가 완성/·아카이브/ 에 있음 — 진행 중·없는 카드는 확정하지 않는다
RB="$T/br"; git init -q -b main "$RB"; git -C "$RB" config user.email t@t; git -C "$RB" config user.name t
echo a > "$RB/a"; git -C "$RB" add a; git -C "$RB" commit -qm c1
for b in nano/aaaa-done-branch-name-aaaaaaaa-mainish nano/bbbb-live-branch-name-bbbbbbbbbbbb \
         nano/cccc-nocard-branch-name-cccccccccccc nano/dddd-worktree-branch-name-dddddddddd; do
  git -C "$RB" branch "$b" main
done
git -C "$RB" worktree add -q "$T/brwt" nano/dddd-worktree-branch-name-dddddddddd
C="$T/cards"; mkdir -p "$C/harness/indices/완성" "$C/harness/indices/진행"
: > "$C/harness/indices/완성/aaaa-done-branch-name-aaaaaaaa-mainish-and-more.md"
: > "$C/harness/indices/진행/bbbb-live-branch-name-bbbbbbbbbbbb-still-going.md"
bash "$SRC/landed.sh" --branches "$RB" "$T/br.tsv" "$C" >/dev/null 2>&1
card_of() { awk -F'\t' -v b="$1" '$1==b {print $3}' "$T/br.tsv"; }
has "$(cat "$T/br.tsv")" "branch	head	card	card_path" "ⓚ 칸 4개(branch·head·card·card_path)"
[ "$(card_of nano/aaaa-done-branch-name-aaaaaaaa-mainish)" = "완성카드" ] && ok "ⓚ 카드가 완성/ 에 있으면 완성카드" \
  || bad "ⓚ aaaa = $(card_of nano/aaaa-done-branch-name-aaaaaaaa-mainish)"
[ "$(card_of nano/bbbb-live-branch-name-bbbbbbbbbbbb)" = "진행카드" ] && ok "ⓚ 카드가 진행/ 이면 확정 0(진행카드)" \
  || bad "ⓚ bbbb = $(card_of nano/bbbb-live-branch-name-bbbbbbbbbbbb)"
[ "$(card_of nano/cccc-nocard-branch-name-cccccccccccc)" = "확인불가" ] && ok "ⓚ 카드를 못 찾으면 확인불가" \
  || bad "ⓚ cccc = $(card_of nano/cccc-nocard-branch-name-cccccccccccc)"
[ -z "$(card_of nano/dddd-worktree-branch-name-dddddddddd)" ] && ok "ⓚ 워크트리가 쓰는 가지는 목록에서 뺀다" \
  || bad "ⓚ 워크트리 있는 가지가 들어감"
[ "$(grep -c . "$T/br.tsv")" = 4 ] && ok "ⓚ 후보 3줄 + 머리 1줄" || bad "ⓚ 줄 수 = $(grep -c . "$T/br.tsv")"


# 변이: 잠금 끄기 제거 → status 가 index 를 다시 쓴다
mkdir -p "$T/mut"; cp "$SRC/scratch.sh" "$T/mut/"; grep -v 'GIT_OPTIONAL_LOCKS=0' "$SRC/measure.sh" > "$T/mut/measure.sh"
read -r n r <<<"$(run_case "$T/mut" "$T/out2" | tail -1)"
[ "$n" != 0 ] && ok "변이(GIT_OPTIONAL_LOCKS 제거) → 바뀐 파일 $n 로 잡힘" || bad "변이를 못 잡음"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
