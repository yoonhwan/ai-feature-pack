#!/usr/bin/env bash
# test_plan_handoff.sh — C17 ft-plan-handoff.sh 시험: 정상 정리본 / 머리줄 누락 정리본 (+ 수신자 없음 · 단위 0)
# --dry-run 과 임시 seats 파일만 쓴다 — 실제 mbox 발신·Issue 생성 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CMD="$HERE/../../harness/bin/ft-plan-handoff.sh"
TPL="$HERE/../../harness/design/harness/PLAN-HANDOFF-TEMPLATE.md"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo '{"_master":"ft-issue-manager#0"}' > "$T/seats-issues.json"
echo '{"_master":"byz-planner-arch#3"}' > "$T/seats-planner.json"
export FT_ISSUES_SEATS="$T/seats-issues.json" FT_PLANNER_SEATS="$T/seats-planner.json" FT_ME="byz-planner-master-claude#0"
unset FT_SEND_DRY
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$CMD" && ok "bash -n" || bad "bash -n"

# 정상 정리본
printf '주제: 샘플 주제\n골좌표: 표 A / 닫는 증거: 이상 1건 = Issue 1건\n쪼갠 단위 3\n\n# 본문\n' > "$T/good.md"
out="$(bash "$CMD" "$T/good.md" --dry-run 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "정상 정리본 rc=0" || bad "정상 정리본 rc=$rc $(cat "$T/err")"
[ "$(printf '%s\n' "$out" | grep -c '^DRY send')" = 2 ] && ok "mbox 본문 2통" || bad "본문 통수: $out"
printf '%s\n' "$out" | grep -q 'DRY send to=ft-issue-manager#0 from=byz-planner-master-claude#0 body=\[계획 인계\]' && ok "1통 = 매니저" || bad "매니저 줄 없음"
printf '%s\n' "$out" | grep -q 'DRY send to=byz-planner-arch#3 .*\[분류 요청 예고\]' && ok "2통 = planner" || bad "planner 줄 없음"
printf '%s\n' "$out" | grep -q 'good.md' && ok "본문에 정리본 경로" || bad "경로 없음"
printf '%s\n' "$out" | grep -q '골좌표: 표 A / 닫는 증거: 이상 1건 = Issue 1건' && ok "본문에 골좌표" || bad "골좌표 없음"
printf '%s\n' "$out" | grep -q '쪼갠 단위 3' && ok "본문에 단위 수" || bad "단위 수 없음"
printf '%s\n' "$out" | grep -q '`' && bad "본문에 백틱(mbox 가드 위반)" || ok "백틱 0"
FT_SEND_DRY=1 bash "$CMD" "$T/good.md" >/dev/null 2>&1 && ok "FT_SEND_DRY=1 도 dry" || bad "FT_SEND_DRY=1 실패"

# 머리줄 누락 정리본 3종(주제 · 골좌표 · 쪼갠 단위) — 전부 REJECT
printf '골좌표: x\n쪼갠 단위 2\n' > "$T/no-topic.md"
printf '주제: x\n쪼갠 단위 2\n'   > "$T/no-goal.md"
printf '주제: x\n골좌표: y\n'     > "$T/no-units.md"
for c in no-topic no-goal no-units; do
  out="$(bash "$CMD" "$T/$c.md" --dry-run 2>&1)"; rc=$?
  [ $rc -eq 1 ] && ok "$c → exit 1" || bad "$c rc=$rc"
  printf '%s\n' "$out" | grep -q '^REJECT 머리줄' && ok "$c → 사유 출력" || bad "$c 사유: $out"
  printf '%s\n' "$out" | grep -q '^DRY send' && bad "$c 인데 본문이 나갔다" || ok "$c → 본문 0"
done

# 경계: 단위 0 · 파일 없음 · 수신자 없음(폴백 0)
printf '주제: x\n골좌표: y\n쪼갠 단위 0\n' > "$T/zero.md"
bash "$CMD" "$T/zero.md" --dry-run >/dev/null 2>&1 && bad "단위 0 허용됨" || ok "단위 0 REJECT"
bash "$CMD" "$T/nope.md" --dry-run >/dev/null 2>&1 && bad "없는 파일 허용됨" || ok "없는 파일 REJECT"
FT_ISSUES_SEATS="$T/none.json" bash "$CMD" "$T/good.md" --dry-run >/dev/null 2>&1 && bad "매니저 행 없음 허용됨" || ok "매니저 행 없음 REJECT"
FT_PLANNER_SEATS="$T/none.json" bash "$CMD" "$T/good.md" --dry-run >/dev/null 2>&1 && bad "planner 행 없음 허용됨" || ok "planner 행 없음 REJECT"
bash "$CMD" >/dev/null 2>&1; [ $? -eq 2 ] && ok "인자 없음 exit 2" || bad "인자 없음 rc"

# 템플릿 자체가 정상 정리본으로 통과한다
bash "$CMD" "$TPL" --dry-run >/dev/null 2>&1 && ok "PLAN-HANDOFF-TEMPLATE.md 통과" || bad "템플릿이 머리줄 검증을 못 통과"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
