#!/usr/bin/env bash
# test_da_verdict_head_r1593.sh — r1593 «DA 판정문 머리 4줄» (카드 r1593-da-verdict-head-four-lines-for-d2) ⓐⓑⓓ + 변이 M1 M2
#   ⓐ da-counterexample.md §4 머리 4줄 꼴 블록 자리표를 가짜 값으로 채운 본문 → live std_field 4번 rc0 · 격리 줄 세트 = 승인 sha · ⓑ 키 4개 각각 1줄
#   ⓓ §4 프롬프트 끝 지시문을 붙인 프롬프트로 ft-da-codex.sh 1회(PATH 앞 가짜 codex · --cwd = A 로 detached 한 임시 git 사본) → .out 이 live std_da_out rc0(⑤)
#   M1 «격리: 세트 <A 40hex> · rc=0» → «격리: 세트=<A> rc=0» ⇒ ⓐ FAIL · M2 «최종 답의 마지막 줄도 …» 문장 삭제 ⇒ ⓓ FAIL(변이 = 제품 doc 1곳씩)
#   격리: 임시 STATE·LOG·CODEX_HOME·bg 장부·git 사본만 · 외부 호출 0 · press 0(나노는 쏘지 않는다) · 실 doc 은 읽기만
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"; KIT="$(cd "$HERE/../kit/fable-team/bin" && pwd -P)"
DOC="$(cd "$HERE/../../skill/references" && pwd -P)/da-counterexample.md"
fail=0; rc=0; out=""; T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
export STATE="$T/state" LOG="$T/state/autonomy.log"; mkdir -p "$STATE"; : > "$LOG"
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
block_body() {  # <doc> <키 문구> [fill] → stdout = §4 첫 ``` 블록 중 <키 문구> 가 든 것 · fill 이면 자리표 <…> 만 가짜 값으로(다른 글자 불변)
python3 - "$@" <<'PY'
import re, sys
A, S, OUT = "a" * 40, "b" * 64, "/tmp/r1593-head/da-fixture.out"
s = open(sys.argv[1], encoding="utf-8").read()
b = re.findall(r"^```\n(.*?)^```", s[s.index("## 4."):s.index("## 5.")], re.S | re.M)
p = next((x for x in b if sys.argv[2] in x), None)
if p is None:
    sys.exit(4)
if len(sys.argv) < 4:
    print(p); sys.exit(0)
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
daout() {  # <원문.out> <A> rc0 = live std_da_out 통과 — ⑤ 마지막 codex 블록 APPROVE ∧ .meta head=A rc=0
  local o r
  o="$( { HERE="$BIN"; . "$BIN/ft-autonomy-standing.sh"; std_da_out "$1" "$2"; echo OK; } 2>&1 )"
  r=$?; printf '%s' "$o" > "$T/daout.txt"; return $r
}
body="$(block_body "$DOC" '승인 sha:' fill)"; rc=$?; [ "$rc" = 0 ] && [ -n "$body" ]; ck "ⓐ0 da-counterexample.md §4 에 «승인 sha:» 가 든 꼴 블록이 있다" $?
judge "$body"; ck "ⓐ1 꼴 블록을 자리표 채운 본문 = live std_field 4번 모두 rc0" $?
[ "$(awk -F'\t' '{print ($4 == "세트 " $1 " · rc=0") ? "ok" : "no"}' "$T/judge.out")" = ok ]; ck "ⓐ2 격리 줄 세트 = 승인 sha(같은 40hex)" $?
b_ok=0; for k in '승인 sha:' 'DA 원문:' 'DA 원문 sha256:' '격리:'; do n="$(grep -cE -- "^[-*]?[[:space:]]*$k" <<<"$body")"; [ "$n" = 1 ] || { echo "  키 [$k] 줄 수 = ${n:-0}"; b_ok=1; }; done
ck "ⓑ 키 4개가 각각 정확히 1줄(같은 키 2줄 0)" $b_ok
# ── ⓓ ⑤: 지시문이 붙은 프롬프트로 래퍼 1회 → 그 .out 이 std_da_out 을 지나는가(가짜 codex 는 «마지막 줄» 문구가 있을 때만 끝줄을 판정: APPROVE 로 낸다)
export CODEX_HOME="$T/codex" FT_BG_FINITE_LEDGER="$T/bg-finite.tsv"; mkdir -p "$CODEX_HOME" "$T/fakebin" "$T/da"; : > "$CODEX_HOME/config.toml"
printf '%s\n' '#!/usr/bin/env bash' 'p="${@: -1}"' 'printf "%s\n" codex "판정: APPROVE" "근거: 픽스처 DA"' 'case "$p" in *"마지막 줄"*) printf "%s\n" "판정: APPROVE" ;; esac' 'exit 0' > "$T/fakebin/codex"; chmod +x "$T/fakebin/codex"
git -C "$T/da" init -q; printf 'x\n' > "$T/da/f.txt"; git -C "$T/da" add -A; git -C "$T/da" -c user.email=t@t -c user.name=t commit -qm A
DA_SHA="$(git -C "$T/da" rev-parse HEAD)"; git -C "$T/da" checkout -q --detach "$DA_SHA"
darun() {  # <doc> <프롬프트> <out-dir> → $T/da-run.txt 에 래퍼 출력 · DA_OUT = 마지막 `OUT <경로> rc=` 의 경로
  printf '질문: 이 카드가 계약을 지키는가\n\n%s\n' "$(block_body "$1" '첫 줄')" > "$2"
  out="$(PATH="$T/fakebin:$PATH" bash "$KIT/ft-da-codex.sh" --cwd "$T/da" --prompt-file "$2" --out-dir "$3" 2>&1)"; rc=$?
  printf '%s' "$out" > "$T/da-run.txt"; DA_OUT="$(sed -nE 's/^OUT (.*) rc=[0-9]+$/\1/p' <<<"$out" | tail -1)"; }
darun "$DOC" "$T/prompt.txt" "$T/daout"; [ "$rc" = 0 ] && [ -f "$DA_OUT" ] && [ -f "$DA_OUT.meta" ]; ck "ⓓ0 래퍼 1회 rc0 · .out·.meta 생김(--cwd = A detached 사본)" $?
daout "$DA_OUT" "$DA_SHA"; ck "ⓓ1 가짜 codex 가 지시문대로 낸 마지막 codex 블록 = live std_da_out rc0(.meta head=A rc=0)" $?
python3 - "$DOC" "$T/mut.md" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old, new = "격리: 세트 <A 40hex> · rc=0", "격리: 세트=<A 40hex> rc=0"
assert s.count(old) == 1, s.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new))
PY
judge "$(block_body "$T/mut.md" '승인 sha:' fill)"; rc=$?; [ "$rc" != 0 ] && grep -q '격리:» 줄이 0개' "$T/judge.out"; ck "ⓘM1 «격리: 세트=<A> rc=0» 변이 → ⓐ FAIL(빨강)" $?
python3 - "$DOC" "$T/mut2.md" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read(); old = "최종 답의 마지막 줄도 `판정: APPROVE` 또는 `판정: HOLD` 로 쓴다 — 그 사이에 근거를 적는다.\n"
assert s.count(old) == 1, s.count(old)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, ""))
PY
darun "$T/mut2.md" "$T/prompt2.txt" "$T/daout2"; daout "$DA_OUT" "$DA_SHA"; rc=$?
[ "$rc" != 0 ] && grep -q '⑤ DA 마지막 codex 블록이 APPROVE 아님' "$T/daout.txt"; ck "ⓘM2 «마지막 줄도 판정:» 문장을 지운 doc → ⓓ FAIL(빨강)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
