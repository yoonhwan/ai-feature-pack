#!/usr/bin/env bash
# test_da_verdict_head_r1593.sh — r1593 «DA 판정문 머리 4줄» (카드 r1593-da-verdict-head-four-lines-for-d2) ⓐⓑ + 변이 M1
#   ⓐ da-counterexample.md §4 꼴 블록의 자리표를 가짜 값으로 채운 본문 → live std_field 4번 rc0 · 격리 줄 세트 = 승인 sha · ⓑ 키 4개 각각 정확히 1줄
#   M1 «격리: 세트 <A 40hex> · rc=0» → «격리: 세트=<A 40hex> rc=0» 변이면 ⓐ FAIL — 그 줄이 실제로 검사된다(변이 = 제품 doc 1곳)
#   격리: 임시 STATE·LOG 만 · 실 상태·원격·슬랙 0 · press 0(나노는 쏘지 않는다) · 실 doc 은 읽기만
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"; DOC="$(cd "$HERE/../../skill/references" && pwd -P)/da-counterexample.md"
fail=0; rc=0; out=""; T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
export STATE="$T/state" LOG="$T/state/autonomy.log"; mkdir -p "$STATE"; : > "$LOG"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
head_body() {  # <doc> → stdout = §4 첫 블록 중 «승인 sha:» 가 든 것 · 자리표 <…> 만 가짜 값으로(다른 글자 불변)
python3 - "$1" <<'PY'
import re, sys
A, S, OUT = "a" * 40, "b" * 64, "/tmp/r1593-head/da-fixture.out"
s = open(sys.argv[1], encoding="utf-8").read()
b = re.findall(r"^```\n(.*?)^```", s[s.index("## 4."):s.index("## 5.")], re.S | re.M)
p = next((x for x in b if "승인 sha:" in x), None)
if p is None:
    sys.exit(4)
def fill(l):
    v = S if "sha256:" in l else A if ("승인 sha:" in l or "격리:" in l) else OUT if "DA 원문:" in l else None
    return l if v is None else re.sub(r"<[^<>]*>", v, l)
print("\n".join(map(fill, p.splitlines())))
PY
}
judge() {  # <본문> rc0 = live std_field 4번 통과 ∧ 격리 세트 = 승인 sha · 판정 값은 $T/judge.out 한 줄
  local o r
  o="$( { HERE="$BIN"; . "$BIN/ft-autonomy-standing.sh"
    std_field J_A "$1" '승인 sha:' '([0-9a-f]{40})'
    std_field J_O "$1" 'DA 원문:' '(/[^[:space:]]+)'
    std_field J_S "$1" 'DA 원문 sha256:' '([0-9a-f]{64})'
    std_field J_I "$1" '격리:' '(세트 [0-9a-f]{40} · rc=0)'
    [ "$J_I" = "세트 $J_A · rc=0" ] || exit 1
    printf '%s\t%s\t%s\t%s\n' "$J_A" "$J_O" "$J_S" "$J_I"; } 2>&1 )"
  r=$?; printf '%s' "$o" > "$T/judge.out"; return $r
}
body="$(head_body "$DOC")"; rc=$?; [ "$rc" = 0 ] && [ -n "$body" ]; ck "ⓐ0 da-counterexample.md §4 에 «승인 sha:» 가 든 꼴 블록이 있다" $?
judge "$body"; ck "ⓐ1 꼴 블록을 자리표 채운 본문 = live std_field 4번 모두 rc0" $?
[ "$(awk -F'\t' '{print ($4 == "세트 " $1 " · rc=0") ? "ok" : "no"}' "$T/judge.out")" = ok ]; ck "ⓐ2 격리 줄 세트 = 승인 sha(같은 40hex)" $?
b_ok=0; for k in '승인 sha:' 'DA 원문:' 'DA 원문 sha256:' '격리:'; do n="$(grep -cE -- "^[-*]?[[:space:]]*$k" <<<"$body")"; [ "$n" = 1 ] || { echo "  키 [$k] 줄 수 = ${n:-0}"; b_ok=1; }; done
ck "ⓑ 키 4개가 각각 정확히 1줄(같은 키 2줄 0)" $b_ok
python3 - "$DOC" "$T/mut.md" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old, new = "격리: 세트 <A 40hex> · rc=0", "격리: 세트=<A 40hex> rc=0"
assert s.count(old) == 1, s.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new))
PY
judge "$(head_body "$T/mut.md")"; rc=$?; [ "$rc" != 0 ] && grep -q '격리:» 줄이 0개' "$T/judge.out"; ck "ⓘM1 «격리: 세트=<A> rc=0» 변이 → ⓐ FAIL(빨강)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
