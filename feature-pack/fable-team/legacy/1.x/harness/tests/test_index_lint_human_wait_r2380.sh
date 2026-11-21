#!/usr/bin/env bash
# test_index_lint_human_wait_r2380.sh — r2380 K1·K1b: 카드의 «오빠 대기» 선행 줄은 오빠 질문 thread ts 를 꼭 단다.
#   ① ts 없음 + FT_LINT_HUMAN_WAIT=reject = REJECT · ② ts 있으면 OK · ③ 스위치 없음 = WARN 1줄 + rc 0(정체 감시 판정 0)
#   ④ «오빠» 없는 선행 줄 = 대상 아님(모든 선행에 ts 요구 0) · ⑤ «없음» 머리 줄·취소선 안 글자 = 대상 아님
#   + 기준판(팩 origin/main) 대조: ① FAIL(옛 판은 통과)·③ FAIL(WARN 없음) · ②④⑤ PASS
#   + 변이 M1~M4(사본 bin 만 치환 → 그 시험 FAIL → 복구) + 회귀 = ft-index-lint 기존 시험
# 임시 리포에서만 돈다 · 네트워크 0 · 실 카드 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/bin"
PACK="$(git -C "$HERE" rev-parse --show-toplevel)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0; t0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-t0))초"; t0=$SECONDS; }

W="$T/world"; mkdir -p "$W/design" "$W/src"
git -C "$W" init -q . || { echo "FAIL git init"; exit 1; }
printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$W/design/TEAMS.md"
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$W/goal.txt"
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$W/design/LEDGER.md"
printf 'l1\nl2\nl3\n' > "$W/src/target.sh"
export FT_GOAL_LINES_FILE="$W/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md"

MK=0
mk() {  # $1=선행 줄(그대로) → 카드 경로
  MK=$((MK+1)); local f="$W/card$MK.md"
  { echo "# 인덱스: card$MK"; echo '- 제안서: 없음 — 시험 카드'; printf '%s\n' "$1"; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '시험 통과.'
    echo "## 계약↔시험 대응표"; echo '| 계약 | 입력 | 기대 | 시험 |'; echo '|---|---|---|---|'
    echo '| C1 오빠 대기 꼴 | 선행 줄 | ts 필수 | ① |'; echo '| C2 대상 줄 | 없음·취소선 | 대상 밖 | ⑤ |'
    echo "## 상태"; echo '- 시험'; } > "$f"
  printf '%s' "$f"
}
lint_at() {  # $1=bin 폴더 $2=카드 $3=스위치 값 — rc 를 돌려주고 출력은 $OUT
  OUT="$( cd "$W" && FT_LINT_HUMAN_WAIT="$3" bash "$1/ft-index-lint.sh" "$2" 2>&1 )"; return $?
}

run_cases() {  # $1=bin 폴더 $2=접두(신판/기준판/변이 이름) → 그 판으로 ①~⑤
  local b="$1" p="$2" rc c
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$b" "$c" reject; rc=$?
  { [ $rc -eq 1 ] && echo "$OUT" | grep -q 'thread'; }; ck "$p ① ts 없는 오빠 줄 + reject = REJECT" $?
  c="$(mk '- 선행: 오빠 승인 (thread 1795016460.792199)')"; lint_at "$b" "$c" reject; rc=$?
  { [ $rc -eq 0 ] && echo "$OUT" | grep -q '^OK '; }; ck "$p ② thread ts 있으면 OK" $?
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$b" "$c" ""; rc=$?
  { [ $rc -eq 0 ] && echo "$OUT" | grep -q '^WARN .*thread'; }; ck "$p ③ 스위치 없음 = WARN 1줄 + rc0" $?
  c="$(mk '- 선행: master 판정 3 결과 (desk 손)')"; lint_at "$b" "$c" reject; rc=$?
  { [ $rc -eq 0 ] && ! echo "$OUT" | grep -q 'thread'; }; ck "$p ④ «오빠» 없는 선행 = 대상 아님" $?
  c="$(mk '- 선행: 없음 — 오빠 승인 뒤 착수 0')"; lint_at "$b" "$c" reject; rc=$?
  { [ $rc -eq 0 ] && ! echo "$OUT" | grep -q 'thread'; }; ck "$p ⑤-a «없음» 머리 줄 = 대상 아님" $?
  c="$(mk '- 선행: ~~오빠 컨펌~~ 풀림 (11-20)')"; lint_at "$b" "$c" reject; rc=$?
  { [ $rc -eq 0 ] && ! echo "$OUT" | grep -q 'thread'; }; ck "$p ⑤-b 취소선 안 «오빠» = 대상 아님" $?
}

echo "== 신판 =="; run_cases "$KIT" 신판; lap 신판

echo "== 기준판(팩 origin/main) =="
mkdir -p "$T/base"; git -C "$PACK" archive origin/main feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin | tar -x -C "$T/base" 2>/dev/null
BASE="$T/base/feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft-index-lint.sh"
if [ -f "$BASE" ]; then
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$(dirname "$BASE")" "$c" reject; rc=$?; [ $rc -eq 0 ]; ck "기준판 ① FAIL(옛 판 = ts 검사 없음)" $?
  c="$(mk '- 선행: 오빠 승인 (master#66 #340166)')"; lint_at "$(dirname "$BASE")" "$c" ""; rc=$?; { [ $rc -eq 0 ] && ! echo "$OUT" | grep -q 'thread'; }; ck "기준판 ③ FAIL(WARN 줄 없음)" $?
  c="$(mk '- 선행: 오빠 승인 (thread 1795016460.792199)')"; lint_at "$(dirname "$BASE")" "$c" reject; rc=$?; { [ $rc -eq 0 ] && echo "$OUT" | grep -q '^OK '; }; ck "기준판 ② PASS(회귀 대조)" $?
else echo "WARN 기준판 없음(origin/main 에 팩 없음) — 대조 건너뜀"; fi
lap 기준판

echo "== 변이(사본만) =="
cp -Rp "$KIT" "$T/bin"
sha_before="$(shasum "$KIT/ft-index-lint.sh" | awk '{print $1}')"
mutate() {  # $1 이름 $2 원문 $3 바꿀 글 — 치환 뒤 run_cases 중 한 시험이 FAIL 해야 한다($4 = 기대 FAIL 이름)
  cp -p "$KIT/ft-index-lint.sh" "$T/bin/ft-index-lint.sh"
  python3 -I - "$T/bin/ft-index-lint.sh" "$2" "$3" <<'PY' || { echo "FAIL 변이 $1 — 자리 못 찾음"; fail=$((fail+1)); return; }
import sys
p, a, b = sys.argv[1:]
s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a)
open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  ( run_cases "$T/bin" "변이 $1" ) > "$T/mut.log" 2>&1   # 하위 셸 — 변이가 만든 FAIL 이 이 시험의 fail 을 올리지 않게
  grep -q "^FAIL 변이 $1 $4" "$T/mut.log"; ck "변이 $1 → $4 FAIL" $?
  cp -p "$KIT/ft-index-lint.sh" "$T/bin/ft-index-lint.sh"
}
mutate "M1 ts 검사 지움" "    [ -n \"\$ts\" ] && continue" "    continue" "①"
mutate "M2 오빠 낱말 판정 지움" "    case \"\$body\" in *오빠*) ;; *) continue;; esac" "    :" "④"
mutate "M3 없음·취소선 빼기 지움" "    case \"\$body\" in 없음*) continue;; esac" "    :" "⑤"
mutate "M3b 취소선 빼기 지움" "    body=\"\$(printf '%s' \"\$body\" | sed -E 's/~~[^~]*~~//g')\"" "    :" "⑤-b"
mutate "M4 스위치 무시(늘 REJECT)" "if [ \"\${FT_LINT_HUMAN_WAIT:-}\" = reject ]; then" "if true; then" "③"
sha_after="$(shasum "$KIT/ft-index-lint.sh" | awk '{print $1}')"
[ "$sha_before" = "$sha_after" ]; ck "변이 뒤 실 파일 무변경(사본만)" $?
lap 변이

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

echo "== 회귀 =="
reg() {  # $1=시험 파일 → rc 를 $RC 로(명령 대입이 $? 를 지우는 자리 피함)
  ( cd "$HERE" && timeout 70 bash "$1" >"$T/reg.$1.log" 2>&1 ); RC=$?; LAST="$(tail -1 "$T/reg.$1.log")"
}
reg test_index_lint_team_env_r1734.sh; ck "회귀 test_index_lint_team_env_r1734.sh ($LAST)" $RC
# test_index_lint_conditional.sh = r2380 이전부터 3 FAIL(r984 대응표 없는 옛 시험 카드) — 신판이 «늘리지 않았나» 만 본다(기준값 3)
reg test_index_lint_conditional.sh; [ "$LAST" = "fail=3" ]; ck "회귀 test_index_lint_conditional.sh 기준값 유지 ($LAST)" $?
for t in test_card_commit_r2278.sh test_card_commit_ledger_r2283.sh; do
  reg "$t"; ck "회귀 $t ($LAST)" $RC
done
lap 회귀

echo "fail=$fail"; [ "$fail" -eq 0 ]
