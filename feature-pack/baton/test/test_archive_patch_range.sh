#!/usr/bin/env bash
# baton v1.2.17 — wt-clean 보관본 패치 범위·상한·독립 prune 시험 (ⓐ~ⓖ)
# 픽스처 = 임시 리포 (실제 리포 0 · 외부 호출 0)
# 사용: bash feature-pack/baton/test/test_archive_patch_range.sh

set -euo pipefail

PKG_CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../core" && pwd)"
export BATON_HOME="$PKG_CORE"
BATON="$PKG_CORE/bin/baton"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_NOSYSTEM=1

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok()   { echo "  ✓ $1"; pass=$((pass + 1)); }
bad()  { echo "  ✗ $1"; fail=$((fail + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- 픽스처: origin(src) 이 로컬 main 보다 1,000 커밋 앞섬 ---
git init -q -b main "$T/src"
echo base > "$T/src/a.txt"; git -C "$T/src" add a.txt; git -C "$T/src" commit -qm c0
git clone -q "$T/src" "$T/proj"
{
  parent=$(git -C "$T/src" rev-parse HEAD)
  blob=$(head -c 2048 /dev/urandom | base64)
  for i in $(seq 1 1000); do
    echo "commit refs/heads/main"
    echo "committer t <t@t> $((1700000000 + i)) +0000"
    echo "data $(( ${#i} + 2 ))"; echo "c$i"
    [[ $i -eq 1 ]] && echo "from $parent"
    echo "M 100644 inline big.txt"
    echo "data $(( ${#blob} + ${#i} + 1 ))"; echo "$i$blob"
  done
} | git -C "$T/src" fast-import --quiet
git -C "$T/proj" fetch -q origin
cd "$T/proj"
MAIN_BEFORE=$(git rev-parse main)
mkdir -p .worktrees

# args: $1=이름 $2=브랜치(빈 값이면 detached)
mk_wt() {
  if [[ -n "$2" ]]; then git worktree add -q -b "$2" ".worktrees/$1" origin/main
  else git worktree add -q --detach ".worktrees/$1" origin/main; fi
}
commit_in() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
archive() { ( . "$PKG_CORE/lib/core.sh"; baton_archive_create "$PWD/.worktrees/$1" "" ); }
row() { jq -c "select(.id | startswith(\"$1\"))" .baton/archive/INDEX.jsonl | tail -1; }
tar_has() { tar tzf "$1" | grep -qx "$2"; }

echo "ⓐ 가지 3커밋 · origin/main 1,000 앞섬 → 패치 = 3커밋만"
mk_wt a ""
for i in 1 2 3; do echo "a$i" > ".worktrees/a/f$i.txt"; commit_in .worktrees/a "a$i"; done
check "로컬 main..HEAD = 1003 (옛 범위)" '[[ $(git -C .worktrees/a rev-list --count main..HEAD) -eq 1003 ]]'
f=$(archive a)
r=$(tail -1 .baton/archive/INDEX.jsonl)
check "patch=included" '[[ $(jq -r .patch <<< "$r") == included ]]'
check "commits 3" '[[ $(jq ".commits|length" <<< "$r") -eq 3 ]]'
check "tar < 1MB" '[[ $(stat -f%z "$f" 2>/dev/null || stat -c%s "$f") -lt 1048576 ]]'
check "패치 안 커밋 3개" '[[ $(tar xzf "$f" -O .unmerged-changes.patch | grep -c "^commit ") -eq 3 ]]'
check "끝 커밋 메타 파일" 'tar_has "$f" .archive-meta.txt'

echo "ⓑ squash 랜딩 + --landed <sha> → merged · 패치 0 (wt-clean CLI 경유)"
mk_wt b nano/b
echo b1 > .worktrees/b/b.txt; commit_in .worktrees/b b1
echo b2 >> .worktrees/b/b.txt; commit_in .worktrees/b b2
git -C "$T/src" checkout -q main; cp .worktrees/b/b.txt "$T/src/b.txt"; commit_in "$T/src" "squash b"
git fetch -q origin
SQ=$(git rev-parse origin/main)
check "가지 tip 은 origin/main 조상 아님" '! git merge-base --is-ancestor nano/b origin/main'
( . "$PKG_CORE/lib/core.sh"; BATON_ARCHIVE_LANDED=0000000000000000000000000000000000000000 baton_archive_create "$PWD/.worktrees/b" "" >/dev/null 2>"$T/b.err" )
check "가짜 착지 sha → merged 아님 + 경고" '[[ $(row nano_b | jq -r .merged_to_main) == false ]] && grep -q "조상 아님" "$T/b.err"'
"$BATON" wt-clean "$PWD/.worktrees/b" --landed "$SQ" --skip-save > "$T/b.out" 2>&1 < /dev/null
r=$(row nano_b)
check "merged_to_main=true" '[[ $(jq -r .merged_to_main <<< "$r") == true ]]'
check "patch=merged · 파일에 패치 없음" '[[ $(jq -r .patch <<< "$r") == merged ]] && ! jq -e ".files|index(\".unmerged-changes.patch\")" <<< "$r" >/dev/null'
check "워크트리 정리됨 · 브랜치 보존" '[[ ! -d .worktrees/b ]] && git show-ref -q --verify refs/heads/nano/b'

echo "ⓒ 브랜치가 리포에 있음 → 패치 0 · patch=skipped branch= tip="
mk_wt c nano/c
echo c > .worktrees/c/c.txt; commit_in .worktrees/c c1
TIP_C=$(git -C .worktrees/c rev-parse HEAD)
f=$(archive c); r=$(row nano_c)
check "patch_meta 1줄" '[[ $(jq -r .patch_meta <<< "$r") == "patch=skipped branch=nano/c tip=$TIP_C" ]]'
check "tar 에 패치 없음" '! tar_has "$f" .unmerged-changes.patch'
check "tar 안 메타에 tip" 'tar xzf "$f" -O .archive-meta.txt | grep -q "tip=$TIP_C"'

echo "ⓓ 60MB 바이너리 → 바이너리 제외 뒤 상한 검사 · 텍스트 상한 초과 → oversize"
mk_wt d ""
head -c 62914560 /dev/zero > .worktrees/d/blob.bin; echo keep > .worktrees/d/d.txt; commit_in .worktrees/d d1
f=$(archive d); r=$(tail -1 .baton/archive/INDEX.jsonl)
check "바이너리 포함 가지 → included" '[[ $(jq -r .patch <<< "$r") == included ]]'
check "패치에 바이너리 본문 없음 (< 1MB)" '[[ $(tar xzf "$f" -O .unmerged-changes.patch | wc -c) -lt 1048576 ]]'
mk_wt d2 ""
head -c 1500000 /dev/urandom | base64 > .worktrees/d2/big.txt; commit_in .worktrees/d2 d2
TIP_D2=$(git -C .worktrees/d2 rev-parse HEAD)
f=$( ( . "$PKG_CORE/lib/core.sh"; BATON_ARCHIVE_PATCH_MAX_BYTES=1048576 baton_archive_create "$PWD/.worktrees/d2" "" ) )
r=$(tail -1 .baton/archive/INDEX.jsonl)
check "상한 초과 → patch=oversize tip=" '[[ $(jq -r .patch_meta <<< "$r") == "patch=oversize branch= tip=$TIP_D2" ]]'
check "oversize tar 에 패치 없음 · 워크트리에 잔여 0" '! tar_has "$f" .unmerged-changes.patch && [[ ! -e .worktrees/d2/.unmerged-changes.patch && ! -e .worktrees/d2/.archive-meta.txt ]]'
check "기본 상한 50MB" '( . "$PKG_CORE/lib/core.sh"; [[ $BATON_ARCHIVE_PATCH_MAX_BYTES -eq 52428800 ]] )'

echo "ⓔ .log · evidence/ · .wav 경로 제외"
mk_wt e ""
mkdir -p .worktrees/e/evidence .worktrees/e/sub/evidence
echo l > .worktrees/e/run.log; echo e > .worktrees/e/evidence/a.txt; echo e > .worktrees/e/sub/evidence/b.txt
echo w > .worktrees/e/s.wav; echo j > .worktrees/e/x.jsonl; echo k > .worktrees/e/keep.txt
commit_in .worktrees/e e1
f=$(archive e); p=$(tar xzf "$f" -O .unmerged-changes.patch)
check "keep.txt 는 패치에 있음" 'grep -q "^diff --git a/keep.txt" <<< "$p"'
check "제외 경로 0" '! grep -qE "^diff --git a/(run\.log|evidence/|sub/evidence/|s\.wav|x\.jsonl)" <<< "$p"'

echo "ⓕ archive:prune --standalone — wt-clean 0 · 30일 지난 tar + 0B tar + 고아 행 정리"
A=.baton/archive
old=$(date -v-40d +%Y-%m-%dT00:00:00+0000 2>/dev/null || date -d '-40 days' +%Y-%m-%dT00:00:00+0000)
now=$(date +%Y-%m-%dT%H:%M:%S%z)
mkrow() { jq -nc --arg id "$1" --arg at "$2" '{id:$id, archived_at:$at, size_bytes:1}' >> "$A/INDEX.jsonl"; }
echo x | gzip > "$A/p_old.tar.gz"; mkrow p_old "$old"
echo x | gzip > "$A/p_new.tar.gz"; mkrow p_new "$now"
: > "$A/p_empty.tar.gz"; mkrow p_empty "$now"
mkrow p_ghost "$now"
echo x | gzip > "$A/p_noindex.tar.gz"; : > "$A/p_zero.tar"
WT_BEFORE=$(git worktree list | wc -l)
ROWS_BEFORE=$(wc -l < "$A/INDEX.jsonl")
"$BATON" archive:prune --standalone --dry-run --project "$T/proj" > "$T/f.dry" 2>&1
check "dry-run 은 변경 0" '[[ $(wc -l < "$A/INDEX.jsonl") -eq $ROWS_BEFORE && -e "$A/p_empty.tar.gz" ]]'
( cd / && "$BATON" archive:prune --standalone --project "$T/proj" > "$T/f.out" 2>&1 ) || { bad "standalone prune rc=$?"; cat "$T/f.out"; }
check "30일 지난 tar 삭제" '[[ ! -e "$A/p_old.tar.gz" ]]'
check "0B tar 둘 삭제" '[[ ! -e "$A/p_empty.tar.gz" && ! -e "$A/p_zero.tar" ]]'
check "고아 행(p_ghost·p_empty·p_old) 0" '! grep -qE "\"(p_ghost|p_empty|p_old)\"" "$A/INDEX.jsonl"'
check "최근 행·tar 보존" 'grep -q "\"p_new\"" "$A/INDEX.jsonl" && [[ -e "$A/p_new.tar.gz" ]]'
check "INDEX 없는 tar 보존" '[[ -e "$A/p_noindex.tar.gz" ]]'
check "wt-clean 호출 0 (워크트리 수 불변)" '[[ $(git worktree list | wc -l) -eq $WT_BEFORE ]]'
check "기존 prune 형식(baton archive prune) 유지" '"$BATON" archive prune --dry-run >/dev/null'

echo "ⓖ 600/300 0 · 외부 호출 0 · 로컬 main 불변"
SRC=("$PKG_CORE/lib/archive.sh" "$PKG_CORE/bin/baton")
check "600·300 상한 0 (chmod 제외)" '! grep -nwE "600|300" "${SRC[@]}" | grep -v chmod'
check "외부 호출 0" '! grep -nE "curl|wget|ssh |https?://" "${SRC[@]}"'
check "로컬 main 불변 · branch -f 0" '[[ $(git rev-parse main) == "$MAIN_BEFORE" ]] && ! grep -n "branch -f" "${SRC[@]}"'

echo
echo "결과: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
