#!/usr/bin/env bash
# test_branch_candidates.sh — C18 브랜치 정리 후보 목록 시험: mktemp 저장소 SAFE/KEEP/REVIEW 각 1 + 불변 증거 + 실제 리포 전후 브랜치 수.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TOOL="$HERE/../../harness/bin/ft-branch-candidates.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$TOOL" && ok "bash -n" || bad "bash -n"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OLD="2020-01-01T00:00:00"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
c() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$T/r" commit -q --allow-empty -m "$1" "${@:3}"; }
f() { echo "$1" > "$T/r/$1"; git -C "$T/r" add "$1"; GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$T/r" commit -q -m "add $1"; }

git init -q -b main "$T/r"; f base "$OLD"
git -C "$T/r" branch safe-old                                      # SAFE: main 조상 · 옛 활동
f recent "$(date +%FT%T)"; git -C "$T/r" branch recent-landed   # KEEP: main 조상이나 최근 활동
git -C "$T/r" checkout -q -b keep-unlanded; f u1 "$(date +%FT%T)"
git -C "$T/r" checkout -q -b review-rebased main; f same "$OLD"      # REVIEW: main 에 같은 패치를 cherry-pick → 조상 아님 · cherry 동일
git -C "$T/r" checkout -q main; f pre "$OLD"; GIT_COMMITTER_DATE="$OLD" git -C "$T/r" cherry-pick review-rebased >/dev/null
f later "$OLD"
git -C "$T/r" worktree add -q "$T/wt" -b keep-worktree main        # KEEP: 워크트리 사용 중(옛 활동 · 조상)

before="$(git -C "$T/r" for-each-ref | cksum)"; nb="$(git -C "$T/r" branch -a | wc -l)"
out="$(bash "$TOOL" --repo "$T/r" --out "$T/out.md" 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "실행 exit 0" || bad "exit $rc: $out"
row() { grep -F "| \`$1\` |" "$T/out.md"; }
row safe-old        | grep -q '| SAFE |'   && ok "SAFE safe-old"          || bad "SAFE safe-old: $(row safe-old)"
row review-rebased  | grep -q '| REVIEW |' && ok "REVIEW review-rebased"  || bad "REVIEW review-rebased: $(row review-rebased)"
row keep-unlanded   | grep -q '| KEEP |'   && ok "KEEP keep-unlanded"     || bad "KEEP keep-unlanded: $(row keep-unlanded)"
row keep-worktree   | grep -q '| KEEP |'   && ok "KEEP keep-worktree"     || bad "KEEP keep-worktree: $(row keep-worktree)"
row recent-landed   | grep -q '| KEEP |'   && ok "KEEP recent-landed(최근 활동)" || bad "KEEP recent-landed: $(row recent-landed)"
row main            && bad "기준 브랜치 main 이 목록에 있음" || ok "main 제외"
grep -q '^- \*\*SAFE\*\*' "$T/out.md" && grep -q '^- \*\*KEEP\*\*' "$T/out.md" && grep -q '^- \*\*REVIEW\*\*' "$T/out.md" && ok "분류 기준 3줄" || bad "분류 기준 3줄"
grep -q "git branch -d 'safe-old'" "$T/out.md" && ok "명령은 문서에만(SAFE)" || bad "명령 문구"
grep -q "git branch -d 'keep-" "$T/out.md" && bad "KEEP 이 삭제 명령에 들어감" || ok "KEEP 은 명령에 없음"
[ "$before" = "$(git -C "$T/r" for-each-ref | cksum)" ] && [ "$nb" = "$(git -C "$T/r" branch -a | wc -l)" ] && ok "mktemp 저장소 refs·브랜치 수 불변" || bad "refs 변경됨"

# --remote: 복제본에서 origin/* 를 분류
git clone -q "$T/r" "$T/c" 2>/dev/null
rout="$(bash "$TOOL" --remote --repo "$T/c" --out "$T/rout.md" 2>&1)"
grep -F '| `safe-old` |' "$T/rout.md" | grep -q '| SAFE |' && grep -q "git push origin --delete 'safe-old'" "$T/rout.md" && ok "--remote SAFE + push --delete 문구" || bad "--remote: $rout"

bash "$TOOL" --bogus >/dev/null 2>&1; [ $? -eq 2 ] && ok "잘못된 인자 exit 2" || bad "잘못된 인자 exit"
bash "$TOOL" --repo "$T" --out "$T/x.md" >/dev/null 2>&1; [ $? -eq 2 ] && ok "저장소 아님 exit 2" || bad "저장소 아님 exit"

# 실제 리포 실행 전후 브랜치 수 불변 (읽기 전용 증거)
REAL="$(cd "$HERE/../.." && pwd)"
n1="$(git -C "$REAL" branch -a | wc -l)"
bash "$TOOL" --repo "$REAL" --remote --out "$T/real-remote.md" >"$T/real.log" 2>&1; rr=$?
bash "$TOOL" --repo "$REAL" --out "$T/real-local.md" >>"$T/real.log" 2>&1; rl=$?
n2="$(git -C "$REAL" branch -a | wc -l)"
[ $rr -eq 0 ] && [ $rl -eq 0 ] && ok "실제 리포 실행 exit 0" || bad "실제 리포 exit $rr/$rl"
[ "$n1" = "$n2" ] && ok "실제 리포 전후 브랜치 수 불변(${n1}=${n2})" || bad "브랜치 수 변함 ${n1} -> ${n2}"
sed 's/^/  real: /' "$T/real.log"

echo "fail=$fail"; [ $fail -eq 0 ]
