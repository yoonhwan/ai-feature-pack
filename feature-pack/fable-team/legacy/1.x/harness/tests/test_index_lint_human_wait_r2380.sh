#!/usr/bin/env bash
# test_index_lint_human_wait_r2380.sh — r2380 K1·K1b: 카드의 «오빠 대기» 선행 줄은 오빠 질문 thread ts 를 꼭 단다(신판 green).
#   ① ts 없음 + FT_LINT_HUMAN_WAIT=reject = REJECT · ② ts 있으면 OK · ③ 스위치 없음 = WARN 1줄 + rc 0(정체 감시 판정 0)
#   ④ «오빠» 없는 선행 = 대상 아님 · ⑤-a «없음» 머리 줄 · ⑤-b 취소선 안 글자 = 대상 아님
#   ⑥ 카드를 쓰는 길(ft-card-commit)이 lint 를 FT_LINT_HUMAN_WAIT=reject 로 부른다 · 짝 사본(harness/bin ↔ kit)
# 형제 시험(하드 룰 22 = 파일마다 70초): _base(기준판 Red) · _mut(변이 M1~M4) · _regress(기존 시험)
# 임시 리포에서만 돈다 · 네트워크 0 · 실 카드 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"; TRK="$HERE/../bin"; SC="$HERE/scripts"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; R2380_T0=$SECONDS
. "$SC/_r2380_lint_world.sh"
r2380_lint_world "$T" || { echo "FAIL 세계"; exit 1; }

echo "== 신판 =="
run_cases "$KIT" 신판; lap 신판

echo "== 카드를 쓰는 길(ft-card-commit) =="
D="$T/cc"; mkdir -p "$D"
export GIT_CONFIG_NOSYSTEM=1 HOME="$D/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mkdir -p "$HOME"
put() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }
git init -q -b ops/main-base "$D/W" && git init -q --bare -b main "$D/O" || { echo "FAIL 카드커밋 세계"; exit 1; }
( cd "$D/W" && put design/harness/GOAL-harness.md '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' \
  && put design/TEAMS.md '| 팀 | 폴더 | x | y |
|---|---|---|---|
| harness | `design/harness/` | h | 현역 |
' && git add -A && git commit -qm base && git push -q "$D/O" ops/main-base ops/main-base:main )
git clone -q -b ops/main-base "$D/O" "$D/R" 2>/dev/null
STUB="$D/stub-lint.sh"; printf '#!/bin/sh\necho "$FT_LINT_HUMAN_WAIT" >> "%s/envs"\necho "OK $1"\nexit 0\n' "$D" > "$STUB"; chmod +x "$STUB"
printf '<!-- ledger: design/harness/GOAL-harness.md -->\n# 인덱스: r9001\n- 제안서: 없음 — 시험\n- 선행: 오빠 승인 (master#66 #340166)\n' > "$D/card.md"
OUT="$( cd "$D/R" && FT_CARD_LINT="$STUB" bash "$KIT/ft-card-commit.sh" ops/main-base "카드 추가" "design/harness/indices/대기/r9001-x.md=$D/card.md" 2>&1 )"; RC=$?
# 새 카드는 «고치기 전 판» 이 없어 lint 1회(빈 사유 목록과 diff = 모든 사유가 새 사유) · 고친 카드는 2회 — 어느 쪽이든 늘 reject
[ $RC -eq 0 ] && [ -s "$D/envs" ] && [ "$(sort -u "$D/envs")" = reject ]
ck "⑥ ft-card-commit 이 lint 를 FT_LINT_HUMAN_WAIT=reject 로 부른다($(wc -l < "$D/envs" | tr -d ' ')회)" $?
lap 카드커밋

echo "== 짝·모드 =="
for f in "$KIT/ft-index-lint.sh" "$KIT/ft-card-commit.sh" "$TRK/ft-card-commit.sh"; do
  bash -n "$f"; ck "bash -n $(basename "$f")" $?
done
cmp -s "$TRK/ft-card-commit.sh" "$KIT/ft-card-commit.sh" && [ "$(stat -f %Lp "$TRK/ft-card-commit.sh")" = "$(stat -f %Lp "$KIT/ft-card-commit.sh")" ]
ck "짝 사본 ft-card-commit.sh" $?
for f in "$HERE/test_index_lint_human_wait_r2380.sh" "$HERE/test_index_lint_human_wait_base_r2380.sh" "$HERE/test_index_lint_human_wait_mut_r2380.sh" "$HERE/test_index_lint_human_wait_regress_r2380.sh" "$SC/_r2380_lint_world.sh"; do
  m="$(stat -f %Lp "$f" 2>/dev/null)"; [ "$m" = 644 ]; ck "새 시험 모드 644 $(basename "$f") ($m)" $?
done
lap 짝

echo "fail=$fail"; [ "$fail" -eq 0 ]
