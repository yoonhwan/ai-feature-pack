#!/usr/bin/env bash
# test_nano_spawn_evidence_in_report_r2246.sh — ft-nano-spawn.sh 첫 발주문(BODY)이 나노에게
# 카드 파일 쓰기를 시키지 않는가 (정적 · 실행·tmux·네트워크 0).
#   r2246: 발주문이 «$IDX_WT/$NEW_IDX 절대경로 Edit» 로 카드를 넘긴 checkout(aifp = 팩 루트)을 쓰기 자리로 줌
#          → 나노 5석 중 3석이 공용 checkout 카드 파일을 고침. 새 규칙(master#328 #333803) = 카드 줄은 arch 가 인수 뒤 docs PR.
# 꼴 = test_nano_spawn_body_after_report_r1035.sh. 두 사본(추적본·키트)의 `^BODY=` 줄과 BODY 가 펼치는 `^_XXX="` 정의 줄을 읽는다.
# 인자(선택): $1 = 추적본 경로 · $2 = 키트 경로 (기준판 Red 대조용)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRACKED="${1:-$HERE/../../harness/bin/ft-nano-spawn.sh}"
KIT="${2:-$HERE/../../harness/kit/fable-team/bin/ft-nano-spawn.sh}"
TPL='증거 줄 템플릿(그대로 복사해 <> 만 채움): 세트: <나노 HEAD 40자> · 시험: <명령 — «(N passed)» 같은 꼬리는 여기> rc=<n> · 이슈: 0 — rc= 바로 뒤는 « · 이슈:» — 괄호·설명은 rc= 앞에.'
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# cnt <글> <구절> — 구절 등장 횟수
cnt() { printf '%s' "$1" | grep -o -F -- "$2" | wc -l | tr -d ' '; }

# expect <label> <글> <구절> <기대 횟수>
expect() {
  local n; n="$(cnt "$2" "$3")"
  [ "$n" = "$4" ] && ok "$1 «$3» ${n}회" || bad "$1 «$3» ${n}회 (기대 $4)"
}

# expanded <파일> — BODY 줄 + BODY 가 펼치는 고정 문단(_XXX) 정의 줄
expanded() {
  local f="$1" body v
  body="$(grep '^BODY="' "$f")"
  printf '%s\n' "$body"
  for v in $(printf '%s' "$body" | grep -o '\${\{0,1\}_[A-Z]\{2,4\}}\{0,1\}' | tr -d '${}' | sort -u); do
    grep "^$v=\"" "$f"
  done
}

check_file() {
  local label="$1" f="$2" body all
  [ -f "$f" ] || { bad "$label 파일 없음: $f"; return; }
  body="$(grep '^BODY="' "$f")"
  all="$(expanded "$f")"
  # ① BODY 쓰기 지시 0 · 완료 쪽지 본문 1
  expect "$label ①" "$body" "절대경로 Edit" 0
  expect "$label ①" "$body" "완료 쪽지 본문" 1
  # ② 증거 줄 템플릿 문장 바이트 그대로
  expect "$label ②" "$body" "$TPL" 1
  # ③ 역할 줄
  expect "$label ③" "$body" "카드 증거 줄은 arch" 1
  expect "$label ③" "$body" "카드 증거 줄을 쓰지 않는다" 0
  # ⑤ 펼친 BODY(_AFX 포함) 전체
  case "$all" in *'_AFX="'*) ok "$label ⑤ 펼친 BODY 에 _AFX 포함";; *) bad "$label ⑤ 펼친 BODY 에 _AFX 없음";; esac
  expect "$label ⑤" "$all" "카드 «상태» 절에 더한다" 0
  expect "$label ⑤" "$all" "행은 그 턴에 닫고" 0
  expect "$label ⑤" "$all" "카드 파일 쓰기 0" 1
  # O4 r1035 단언 글자 그대로
  expect "$label O4" "$all" "«완료 조건» 표를 행마다 다시 훑어" 1
}

check_file "추적본" "$TRACKED"
check_file "키트" "$KIT"
cmp -s "$TRACKED" "$KIT" && ok "추적본·키트 cmp 0" || bad "추적본·키트 다름"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
