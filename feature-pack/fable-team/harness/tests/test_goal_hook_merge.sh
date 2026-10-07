#!/usr/bin/env bash
# test_goal_hook_merge.sh — #835: v65 골좌표 commit-msg 훅이 «main 조상 병합 커밋»은 통과시키고
# 일반 커밋·비-main 병합은 그대로 거부하는지. 임시 리포만 쓴다(실 리포·훅 설치 미접촉).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../../scripts/git-hooks/v65-goal-commit-msg.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$HOOK" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
mkdir -p design/v65 worker
echo "닫는 증거 정본 문장 스무자 이상 들어간 줄입니다" > design/v65/GOAL-LEDGER-v65.md
echo base > worker/a.py
git add -A && git commit -q -m "base"
git update-ref refs/remotes/origin/main HEAD
git switch -q -c feat/v6-realtime-live
echo feat > design/v65/feat.md; git add -A && git commit -q -m "feat 쪽 문서"
git switch -q main
echo m1 > worker/main_new.py; git add -A && git commit -q -m "main 새 코드"
git update-ref refs/remotes/origin/main HEAD
git switch -q -c topic/other main~1
echo t > worker/topic.py; git add -A && git commit -q -m "topic 코드"
git switch -q feat/v6-realtime-live

msg="$T/msg"
run_hook() { printf '%s\n' "$1" > "$msg"; sh "$HOOK" "$msg" >/dev/null 2>&1; }

# 1) main 조상 병합(제품 경로 staged · [chore]) → 통과해야 한다
git merge -q --no-ff --no-commit origin/main >/dev/null 2>&1
run_hook "[chore] main 병합" && ok "main 병합 커밋 통과" || bad "main 병합 커밋이 거부됨"
git merge --abort

# 2) 같은 제품 경로를 일반 커밋으로 staged → 거부 유지(통제 시험)
echo x > worker/plain.py; git add worker/plain.py
run_hook "[chore] 일반 커밋" && bad "일반 커밋이 통과됨" || ok "일반 커밋 거부 유지"
git reset -q --hard HEAD

# 3) main 조상이 아닌 topic 병합(제품 경로 staged) → 거부
git merge -q --no-ff --no-commit topic/other >/dev/null 2>&1
run_hook "[chore] topic 병합" && bad "비-main 병합이 통과됨" || ok "비-main 병합 거부"
git merge --abort

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "fail=$fail"
exit "$fail"
