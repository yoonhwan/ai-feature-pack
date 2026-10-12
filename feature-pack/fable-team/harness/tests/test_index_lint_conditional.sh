#!/usr/bin/env bash
# test_index_lint_conditional.sh — ft-index-lint 「마지막 판정 HOLD + planner 조건부 승인」 예외 시험(판정 1206·1219). 임시 리포에서만 돈다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LINT="$HERE/../../scripts/harness-install/fable-team/bin/ft-index-lint.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$LINT" && ok "bash -n" || bad "bash -n"
LINES="$(awk 'END{print NR}' "$LINT")"; [ "$LINES" -le 160 ] && ok "키트 ${LINES}줄 ≤160" || bad "키트 ${LINES}줄 > 160"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design/planner src
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > goal.txt
echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > design/LEDGER.md
printf 'l1\nl2\nl3\n' > src/target.sh
printf '판정 1: APPROVE\n판정 2: HOLD\n' > design/da-hold.md
printf '판정 1: HOLD\n판정 2: REJECT\n' > design/da-reject.md
printf '판정 1: HOLD\n판정 2: APPROVE\n' > design/da-ok.md
{ echo '# 시험용 planner 원장'
  echo '- **9001** (시험) 사전 DA 2회 소진 → ① 조건부 승인 · 잔여 HOLD 를 완료 조건으로 고정'
  echo '- **9002** (시험) 이건 반려 판정'
  echo '- **1220** (시험) 선례 언급 — 1219 조건부 승인 선례'; } > design/planner/VERDICTS-planner-1-20261012.md
git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
export FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md" FT_CARD_REQUIRE_PREVERIFY=1

# mkc <이름> <사전검증 본문> <완료 조건 본문> — 카드 경로 출력
mkc() {
  local f="$T/$1.md"
  { echo "# 인덱스: $1"; echo '- 제안서: 없음 — 시험 카드'; echo "## 골 원문"; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; printf '%b\n' "$3"
    echo "## 사전검증"; printf '%b\n' "$2"
    echo "## 조사 근거"; echo '- src/target.sh:2 확인'
    echo "## 상태"; echo '- 시험'; } > "$f"
  echo "$f"
}
run() { ( cd "$T" && bash "$LINT" "$1" 2>&1 ); }
INFO='^INFO 사전검증: DA 마지막 판정 HOLD — planner 판정 9001 조건부 승인으로 통과$'
HOLD='소환: 예\nDA: design/da-hold.md'; EXC='lint 예외 1건: 판정 9001 ① 조건부 승인'; DONE='시험 통과.\n잔여 HOLD: 시험 잔여 결함 고정'
expect_ok()  { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 0 ] && echo "$out" | grep -q '^OK ' && { [ -z "${3:-}" ] || echo "$out" | grep -q "$3"; } && ok "$2" || bad "$2 → rc=$rc $out"; }
expect_rej() { local out rc; out="$(run "$1")"; rc=$?; [ $rc -eq 1 ] && echo "$out" | grep -q "$3" && ! echo "$out" | grep -q '^INFO ' && ok "$2" || bad "$2 → rc=$rc $out"; }

expect_ok  "$(mkc a "$HOLD\n- $EXC" "$DONE")"   "ⓐ 마지막 HOLD + 예외 줄 + 원장 조건부 승인 + 잔여 HOLD → OK + INFO 1줄" "$INFO"
expect_rej "$(mkc b "$HOLD\n- lint 예외 1건: 판정 9999 ① 조건부 승인" "$DONE")" "ⓑ 원장에 번호 없음 REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mkc c "$HOLD\n- lint 예외 1건: 판정 9002 ① 조건부 승인" "$DONE")" "ⓒ 원장 줄은 있으나 조건부 승인 아님 REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mkc d "$HOLD\n- $EXC" '시험 통과.')"                                  "ⓓ 완료 조건에 잔여 HOLD 없음 REJECT" "APPROVE 가 아니다 (HOLD)"
expect_rej "$(mkc e '소환: 예\nDA: design/da-reject.md\n'"- $EXC" "$DONE")"          "ⓔ 마지막 REJECT + 나머지 참 → REJECT" "APPROVE 가 아니다 (REJECT)"
git update-ref -d refs/remotes/origin/main
expect_rej "$(mkc f "$HOLD\n- $EXC" "$DONE")"                                       "ⓕ origin/main ref 없음 REJECT" "원장 확인 불가"
git update-ref refs/remotes/origin/main HEAD
expect_rej "$(mkc g "$HOLD" "$DONE")"                                               "ⓖ 예외 줄 없음 + HOLD → 지금 문구 그대로 REJECT" "APPROVE 가 아니다 (HOLD)"
g_out="$(run "$T/g.md")"; echo "$g_out" | grep -qF '  - 사전검증: DA 판정문의 마지막 판정이 APPROVE 가 아니다 (HOLD)' && ok "ⓖ 사유 문구 바이트 동일(꼬리 없음)" || bad "ⓖ 사유 문구 변형 → $g_out"
expect_ok  "$(mkc h '소환: 예\nDA: design/da-ok.md' '시험 통과.')"                    "ⓗ 마지막 APPROVE → 그대로 OK(INFO 0)"
h_out="$(run "$T/h.md")"; echo "$h_out" | grep -q '^INFO ' && bad "ⓗ APPROVE 인데 INFO 출력 → $h_out" || ok "ⓗ APPROVE 경로 INFO 0"
expect_rej "$(mkc i1 "$HOLD\n- lint 예외 1건: 판정 1219 ① 조건부 승인" "$DONE")"       "ⓘ 번호가 원장 다른 줄 안에만 있음(1219 는 1220 줄 본문) REJECT" "APPROVE 가 아니다 (HOLD)"

echo "fail=$fail"; [ $fail -eq 0 ]
