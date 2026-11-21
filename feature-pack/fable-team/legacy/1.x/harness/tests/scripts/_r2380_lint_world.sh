#!/usr/bin/env bash
# _r2380_lint_world.sh — r2380 lint 칸 시험들이 같이 쓰는 «임시 리포 + 카드 + 판정» 도우미(하드 룰 22: 파일마다 70초).
#   부르는 쪽이 HERE·KIT·T·fail·R2380_T0 를 정하고 source 한 뒤 r2380_lint_world "$T" 를 부른다.
set -uo pipefail
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
lap() { echo "단계 $1 $((SECONDS-R2380_T0))초"; R2380_T0=$SECONDS; }
r2380_lint_world() {  # $1=임시 뿌리 → W(세계) 만들고 골줄·원장 env 를 건다
  W="$1/world"; mkdir -p "$W/design" "$W/src"
  git -C "$W" init -q . || return 1
  printf '| 팀 | 폴더 | x | y |\n|---|---|---|---|\n| harness | `design/harness/` | h | 현역 |\n' > "$W/design/TEAMS.md"
  R2380_G1='골 첫 줄 시험용 문장이다.'; R2380_G2='골 둘째 줄 시험용 문장이다.'; R2380_G3='골 셋째 줄 시험용 문장이다.'
  printf '%s\n%s\n%s\n' "$R2380_G1" "$R2380_G2" "$R2380_G3" > "$W/goal.txt"
  echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$W/design/LEDGER.md"
  printf 'l1\nl2\nl3\n' > "$W/src/target.sh"
  export FT_GOAL_LINES_FILE="$W/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md"
  R2380_MK=0
}
mk() {  # $1=«- 선행: …» 줄 그대로 → 카드 경로(다른 절은 통과 꼴로 채운다)
  R2380_MK=$((R2380_MK+1)); local f="$W/card$R2380_MK.md"
  { echo "# 인덱스: card$R2380_MK"; echo '- 제안서: 없음 — 시험 카드'; printf '%s\n' "$1"; echo "## 골 원문"
    printf '%s\n%s\n%s\n' "$R2380_G1" "$R2380_G2" "$R2380_G3"
    echo "## 골좌표"; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo "## 배경"; echo '시험 카드.'
    echo "## 구현 범위"; echo '1. src/target.sh 수정'
    echo "## 완료 조건"; echo '시험 통과.'
    echo "## 계약↔시험 대응표"; echo '| 계약 | 입력 | 기대 | 시험 |'; echo '|---|---|---|---|'
    echo '| C1 오빠 대기 꼴 | 선행 줄 | ts 필수 | ① |'; echo '| C2 대상 줄 | 없음·취소선 | 대상 밖 | ⑤ |'
    echo "## 상태"; echo '- 시험'; } > "$f"
  printf '%s' "$f"
}
lint_at() {  # $1=bin 폴더 $2=카드 $3=FT_LINT_HUMAN_WAIT 값 — 출력은 $OUT, rc 를 돌려준다
  OUT="$( cd "$W" && FT_LINT_HUMAN_WAIT="$3" bash "$1/ft-index-lint.sh" "$2" 2>&1 )"; return $?
}
run_cases() {  # $1=bin 폴더 $2=접두(신판/기준판/변이 이름) → ①~⑤-b 를 그 판으로
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
