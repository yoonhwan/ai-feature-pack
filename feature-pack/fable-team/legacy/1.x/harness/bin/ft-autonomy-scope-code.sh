#!/usr/bin/env bash
# ft-autonomy-scope-code.sh — 범위 승인 종류 code 의 «시험 통과 세트» 검사 (R411 · 판정 2326) — ft-autonomy-scope.sh 가 source 한다(단독 실행 금지)
#   scope_code_check <sha> <카드> → 통과 = CODE_A(카드 세트 sha) · CODE_EQUIV(A≠sha 면 A) · 못 통과 = SCOPE-REJECT(사유 그대로 · 승인 쓰기 0)
#   ①카드 «## 상태» 마지막 `세트: <A 40hex> · 시험: … rc=0 · 이슈: 0` 줄 ②ft-nano-evidence-check.sh <카드> --repo ROOT --ancestor-of <sha> rc0
#   ③A ≠ sha 면 ft-approval-equiv.sh A <sha> --repo ROOT 가 EQUIV rc0(A 위에 main 병합만). 판단 못 함 = REJECT(#0 RULE) · 도구마다 7초 상한(판정 666).

scope_code_tool() {  # <도구> <인자…> → OUT·RC·FIRST (7초 상한 — 넘으면 rc≠0 = REJECT 쪽)
  local t="$HERE/$1"; shift
  [ -f "$t" ] || scope_err "code 검사 도구 없음: $t"
  OUT="$(perl -e 'alarm 7; exec @ARGV' -- "$BASH" "$t" "$@" 2>&1)"; RC=$?
  FIRST="${OUT%%$'\n'*}"
}

scope_code_check() {
  local sha="$1" card="$2" line re='세트:[[:space:]]*([0-9a-f]{40})[[:space:]]*·[[:space:]]*시험:.+[[:space:]]rc=0[[:space:]]*·[[:space:]]*이슈:[[:space:]]*0[[:space:]]*$'
  [ -n "$card" ] || scope_err "종류 code 는 --card <카드.md> 필요(시험 통과 세트 증거 줄)"
  [ -f "$card" ] || scope_err "카드 없음: $card"
  line="$(grep -E '세트:' "$card" | tail -1)"
  [[ "$line" =~ $re ]] || scope_err "카드 증거 줄이 «세트: <40hex> · 시험: … rc=0 · 이슈: 0» 꼴 아님: ${line:0:160}"
  CODE_A="${BASH_REMATCH[1]}"; CODE_EQUIV=""
  scope_code_tool ft-nano-evidence-check.sh "$card" --repo "${SCOPE_REPO:-$ROOT}" --ancestor-of "$sha"
  [ "$RC" = 0 ] || scope_err "증거 검사 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  [ "$CODE_A" = "$sha" ] && return 0
  scope_code_tool ft-approval-equiv.sh "$CODE_A" "$sha" --repo "${SCOPE_REPO:-$ROOT}"   # r466: --repo pack 이면 팩 리포
  [ "$RC" = 0 ] && [[ "$FIRST" == EQUIV\ * ]] || scope_err "세트 ${CODE_A:0:9} ≠ $sha — 동일 승인 아님 rc=$RC: ${FIRST:-출력 없음(시간 초과 7초 포함)}"
  CODE_EQUIV="$CODE_A"
}

scope_code_used() { awk -v s="$1" '$1=="scope-use" && $2==s && $4=="code" {n++} END{print n+0}' "$LOG" 2>/dev/null; }
