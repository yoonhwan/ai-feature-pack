#!/usr/bin/env bash
# test_scope_classify_keyword_docs.sh — r514: 낱말 금지(과금·키)는 문서 줄 아래 · 경로로 지정한 문서 금지만 문서 줄 위
# 임시 origin(bare)+clone · 외부 호출 0 · GIT_* 환경 변수 안 건다(BOOT 25)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLS="$BIN/autonomy_scope_classify.py"; RULES="$BIN/autonomy_scope_rules.py"
KIT="$HERE/../../harness/kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkdir -p "$W/docs"; echo d > "$W/docs/a.md"; cm "$W" base2; git -C "$W" push -q origin main; BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin   # BASE 에서 딴 가지 = main 조상 아님 → docs(ff 아님)
mk() { local br="$1"; shift; git -C "$W" checkout -q -B "$br" "$BASE"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
cls() { out="$(python3 "$CLS" classify "$SHA" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }   # want <이름> <rc> <출력 머리>
f() { mkdir -p "$(dirname "$1")" && echo x > "$1"; }   # f <경로> — 빈 폴더 만들고 1줄 파일

# ⓐ 이름에 과금 낱말 든 문서만 → docs (고치기 전 FORBID kind=billing)
mk a1 'f docs/architect/CFO_BILLING_X.md'; cls; want "ⓐ docs/architect/CFO_BILLING_X.md → CLASS docs" 0 "CLASS docs"
mk a2 'f design/cfo/credit-ledger.md; f docs/pricing/toss-subscription.md'; cls; want "ⓐ 낱말 문서 2(credit·pricing/toss/subscription) → CLASS docs" 0 "CLASS docs"
# ⓑ 코드 경로의 과금 낱말은 그대로 금지
mk b1 'f gateway/billing/x.py'; cls; want "ⓑ gateway/billing/x.py → FORBID kind=billing" 3 "FORBID kind=billing 과금"
mk b2 'f design/billing/x.py'; cls; want "ⓑ design/billing/x.py(design 아래 코드) → FORBID kind=billing" 3 "FORBID kind=billing 과금"
mk b3 'f docs/payment.sh'; cls; want "ⓑ docs/payment.sh(.md 아님) → FORBID kind=billing" 3 "FORBID kind=billing 과금"
# ⓒ 혼합 = 코드 기준 금지 · 변이(문서만 남김) = docs
mk c1 'f docs/architect/CFO_BILLING_X.md; f gateway/billing/x.py'; cls; want "ⓒ 문서(BILLING) + gateway/billing/x.py → FORBID kind=billing" 3 "FORBID kind=billing 과금 경로: gateway/billing/x.py"
mk c2 'f docs/architect/CFO_BILLING_X.md; f gateway/billing/x.py; rm gateway/billing/x.py'; cls; want "ⓒ 변이 — 문서 1파일만 남김 → CLASS docs" 0 "CLASS docs"
# ⓓ 경로로 지정한 문서 금지는 문서 줄 위 그대로
mk d1 'f docs/architect/COST_BASE_TABLE.md'; cls; want "ⓓ docs/architect/COST_BASE_TABLE.md → FORBID kind=billing" 3 "FORBID kind=billing 과금"
mk d2 'f CLAUDE.md'; cls; want "ⓓ CLAUDE.md → FORBID kind=global-rule" 3 "FORBID kind=global-rule 전역 규칙"
mk d3 'f .claude/rules/x.md'; cls; want "ⓓ .claude/rules/x.md → FORBID kind=global-rule" 3 "FORBID kind=global-rule 전역 규칙"
mk d4 'f design/x/COMM-GUIDE.md'; cls; want "ⓓ design/x/COMM-GUIDE.md → FORBID kind=global-rule" 3 "FORBID kind=global-rule 전역 규칙"
# ⓔ 키 낱말 — 문서는 docs · 코드·경로 줄은 그대로
mk e1 'f design/x/credential-rotation.md'; cls; want "ⓔ design/x/credential-rotation.md → CLASS docs" 0 "CLASS docs"
mk e2 'f shared/credential_store.py'; cls; want "ⓔ shared/credential_store.py → FORBID kind=key" 3 "FORBID kind=key 키"
mk e3 'f secrets/a.json'; cls; want "ⓔ secrets/a.json → FORBID kind=key" 3 "FORBID kind=key 키"
mk e4 'f docs/x.cred'; cls; want "ⓔ docs/x.cred → FORBID kind=key" 3 "FORBID kind=key 키"

# 분류표 구조 — 낱말 줄은 docs 줄 아래 · code 줄 위 · 경로 줄은 docs 줄 위
order="$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import autonomy_scope_rules as r
ks = [(c, k, x.pattern) for c, k, x in r.BYZ_TABLE]; d = [c for c, _, _ in ks].index("docs"); code = [c for c, _, _ in ks].index("code")
kw = lambda k: next(i for i, (c, kk, p) in enumerate(ks) if kk == k and "|" in p and not p.startswith("^"))
cost = next(i for i, (c, kk, p) in enumerate(ks) if "COST_BASE_TABLE" in p); sec = next(i for i, (c, kk, p) in enumerate(ks) if "secrets/" in p)   # r909: (^|/)secrets/ 로 넓힘(하위 폴더 포함)
print(int(d < kw("billing") < code and cost < d and sec < d and not any("credential" in p for c, kk, p in ks[:d])))' "$BIN" 2>&1)"
out="$order"; [ "$order" = 1 ]; ck "분류표: 낱말 줄 docs 아래·code 위 · COST_BASE_TABLE·secrets 경로 줄 docs 위 · credential 낱말 docs 위 0" $?
python3 -I -m py_compile "$RULES"; ck "py_compile rules" $?
cmp -s "$RULES" "$KIT/autonomy_scope_rules.py"; ck "키트 사본 == harness/bin (cmp0)" $?
[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
