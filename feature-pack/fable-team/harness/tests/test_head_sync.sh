#!/usr/bin/env bash
# test_head_sync.sh — ft-head-sync.sh 최신화 도구 시험 (R230 · 임시 origin+clone+워크트리 픽스처만)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../scripts/fable-team-bin"; SYNC="$BIN/ft-head-sync.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
row() { printf '%s\n' "$out" | awk -v b="$1" '$1==b'; }          # 표에서 브랜치 줄
head_of() { sha "$T/wt-$1" HEAD; }
wt() { git -C "$W" worktree add -q -b "$1" "$T/wt-$1" "${2:-$M0}"; git -C "$T/wt-$1" config user.name t; git -C "$T/wt-$1" config user.email t@t; }

bash -n "$SYNC"; ck "bash -n head-sync" $?
mkrepo "$T"
# 브랜치들 — 전부 M0 에서 딴다
wt clean;  echo c > "$T/wt-clean/c.txt";  cm "$T/wt-clean" "clean work"
wt dirty;  echo d > "$T/wt-dirty/d.txt";  cm "$T/wt-dirty" "dirty work"
wt conf;   printf 'l1\nCONF-BRANCH\nl3\n' > "$T/wt-conf/a.txt"; cm "$T/wt-conf" "conf work"
wt squash; printf 'b1\nSQUASHED\n' > "$T/wt-squash/b.txt"; cm "$T/wt-squash" "squash lineage work"
wt landed; echo LANDED > "$T/wt-landed/lnd.txt"; cm "$T/wt-landed" "landed work"
# main 전진 — a.txt 2행 변경(conf 와 충돌) · squash 와 같은 내용을 다른 커밋으로 · landed 와 같은 패치(새 파일 → patch-id 동일) · 새 파일
printf 'l1\nCONF-MAIN\nl3\n' > "$W/a.txt"; cm "$W" "main edits a.txt line 2"
printf 'b1\nSQUASHED\n' > "$W/b.txt"; cm "$W" "squash of same content"
echo LANDED > "$W/lnd.txt"; cm "$W" "landed same patch"
echo m > "$W/m.txt"; cm "$W" "main new file"; git -C "$W" push -q origin main
M1="$(sha "$W" HEAD)"
wt fresh "$M1"; echo f > "$T/wt-fresh/f.txt"; cm "$T/wt-fresh" "fresh work"
# 미커밋(수정+미추적)
echo "dirty-edit" >> "$T/wt-dirty/b.txt"; echo untracked > "$T/wt-dirty/new.txt"

# ① 표만(--apply 없음): 어떤 워크트리도 안 움직인다
for b in clean dirty conf squash landed fresh; do eval "H0_$b=$(head_of $b)"; done
out="$(bash "$SYNC" --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ]; ck "표만 rc=0" $?
[[ "$out" == *"base=$M1 "* ]]; ck "표 머리에 base 40hex 고정 기록" $?
for b in clean dirty conf squash landed fresh; do [ "$(head_of $b)" = "$(eval echo \$H0_$b)" ]; done; ck "표만 = 모든 HEAD 불변" $?
row clean | grep -q '최신화 필요'; ck "뒤처진 clean → «최신화 필요»" $?
row fresh | grep -qE '최신$'; ck "main 포함 fresh → «최신»" $?
row landed | grep -q '랜딩됨'; ck "LANDED 도 최신화 대상 + 닫기 후보 표기(H3 · rc3 를 신선으로 안 봄)" $?
out="$(bash "$SYNC" --repo "$W" 2>&1)"; printf '%s\n' "$out" | grep -qE '^main '; [ $? -ne 0 ]; ck "main 브랜치 제외" $?

# ② --apply
DIRTY_SNAP="$(cd "$T/wt-dirty" && { git diff --binary; cat new.txt; git rev-parse HEAD; } | shasum)"
out="$(bash "$SYNC" --apply --repo "$W" 2>&1)"; rc=$?
[ "$rc" = 0 ]; ck "--apply rc=0 (비파괴 위반 0)" $?
row clean | grep -q '최신화함'; ck "깨끗한 STALE → 최신화함" $?
[ "$(git -C "$T/wt-clean" rev-list --first-parent --count "$H0_clean..HEAD")" = 1 ] && git -C "$T/wt-clean" merge-base --is-ancestor "$M1" HEAD && [ "$(git -C "$T/wt-clean" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" = 3 ]; ck "clean: merge 1커밋(부모 2) · main 이 조상" $?
row squash | grep -q '최신화함'; ck "squash 계보(같은 내용 다른 커밋) → 자동 해소 → 최신화함" $?
row landed | grep -q '최신화함·랜딩됨'; ck "LANDED 도 merge · 닫기 후보 칸" $?
row dirty | grep -q '보류(미커밋'; ck "미커밋 있는 워크트리 → 보류" $?
[ "$(head_of dirty)" = "$H0_dirty" ] && [ "$(cd "$T/wt-dirty" && { git diff --binary; cat new.txt; git rev-parse HEAD; } | shasum)" = "$DIRTY_SNAP" ]; ck "보류 워크트리 손대지 않음(HEAD·수정·미추적 내용 동일)" $?
row conf | grep -q '충돌·사람'; ck "충돌 → «충돌·사람»" $?
[ "$(head_of conf)" = "$H0_conf" ] && [ -z "$(git -C "$T/wt-conf" status --porcelain)" ] && [ ! -e "$(git -C "$T/wt-conf" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; ck "충돌 워크트리: abort 뒤 HEAD 그대로·깨끗·MERGE_HEAD 0" $?
row fresh | grep -qE '최신$'; ck "이미 포함 fresh 는 그대로" $?
[ "$(head_of fresh)" = "$H0_fresh" ]; ck "fresh HEAD 불변" $?
[[ "$out" == *"비파괴 증거"* ]]; ck "비파괴 증거 줄 출력" $?
git -C "$W" worktree add -q -b opx "$T/wt-opx" "$M0"; git -C "$T/wt-opx" config user.name t; git -C "$T/wt-opx" config user.email t@t
printf 'x\n' > "$T/wt-opx/a.txt"; cm "$T/wt-opx" "opx"; git -C "$T/wt-opx" merge --no-edit "$M1" >/dev/null 2>&1
[ -e "$(git -C "$T/wt-opx" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; ck "픽스처: opx 는 충돌로 병합 진행 중" $?
H0x="$(head_of opx)"; out="$(bash "$SYNC" --apply --repo "$W" 2>&1)"
row opx | grep -q '보류(진행 중 연산'; ck "진행 중 연산(MERGE_HEAD) → 보류" $?
[ "$(head_of opx)" = "$H0x" ] && [ -e "$(git -C "$T/wt-opx" rev-parse --absolute-git-dir)/MERGE_HEAD" ]; ck "진행 중 연산 워크트리 손대지 않음(abort 도 안 함)" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
! grep -vE '^\s*#' "$SYNC" | grep -qE 'git[^|]*(reset|rebase|--force|push)|\+refs'; ck "정적: head-sync 에 reset·rebase·force·push 호출 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
