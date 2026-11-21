#!/usr/bin/env bash
# test_model_literal_one_source_r2403.sh — r2403 K3: 모델 글자는 정책표 한 곳에서만 — 팩에 박힌 «fable» 글자가 표(arch@up) 값과 다르면 파일:줄로 FAIL.
#   ⑥-1 고친 팩 = PASS(다른 글자 0) | ⑥-2 skill/scripts 아래 임시 파일에 «claude-fable-5-1» 1줄 → FAIL · 그 파일:줄 1개 | ⑥-3 tests/ 아래 같은 글자 → PASS(세지 않는 자리)
#   변이 M4(세지 않는 자리 목록에서 tests/ 뺌) → ⑥-3 빨강 — 이 파일 사본을 env 로 다시 돌려 «잡힘» 을 본다.
#   읽기만 한다(팩 파일 수정 0 · 임시 파일은 이 시험이 만들고 지운다) · 실 세션·명부·우편함 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
FP="$HERE/../.."                 # legacy/1.x
KIT="$HERE/../kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T_START="$(date +%s)"

# 값 = 정책표 arch@up 한 곳(ft-successor-open.sh --tier up 이 고르는 행)
VAL="$(awk -F'\t' '!/^#/ && $1=="arch@up" {print $3; exit}' "$KIT/runtime-policy.tsv")"
[ -n "$VAL" ] && ok "표 arch@up = $VAL" || bad "표에 arch@up 행이 없다 ($KIT/runtime-policy.tsv)"
WANT_MAJ="${VAL#*fable-}"; WANT_MAJ="${WANT_MAJ%%-*}"; WANT_MIN="${VAL##*-}"; WANT_MIN="${WANT_MIN%%[*}"
echo "기대 숫자 = $WANT_MAJ.$WANT_MIN"

# 세지 않는 자리(K3 목록 고정) — 변이 M4 = 이 목록에서 tests 를 빼고 같은 파일을 다시 스캔(자기 재호출 0)
EXCL_DIRS="tests evidence design fixtures"
EXCL_NAMES="model-scope.tsv model-fallback.tsv provider-of-model.tsv compact_guard_budget.json CHANGES.md"

scan() {   # scan [제외할 폴더들] → 다른 글자마다 «파일:줄: 값» 출력 · 개수를 마지막 줄에 «COUNT n»
  python3 - "$FP" "${1:-$EXCL_DIRS}" "$EXCL_NAMES" "$WANT_MAJ" "$WANT_MIN" <<'PY'
import os, re, sys
root, dirs, names, maj, mn = sys.argv[1:6]
root = os.path.abspath(root)
skip_dirs, skip_names = set(dirs.split()), set(names.split())
want = (int(maj), int(mn))
pat = re.compile(r"(?:claude-)?fable[-.]([0-9]+)[-._]([0-9]+)")
hits = []
for base, ds, fs in os.walk(root):
    ds[:] = [d for d in ds if d not in skip_dirs and d != ".git" and not d.startswith(".pytest")]
    for f in fs:
        if f in skip_names or ".bak" in f:   # « .bak » 이름( .bak-gov17-20261002 포함) = 기록 사본 · 세지 않는다
            continue
        p = os.path.join(base, f)
        try:
            if os.path.getsize(p) > 2_000_000: continue
            text = open(p, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            for m in pat.finditer(line):
                if (int(m.group(1)), int(m.group(2))) != want:
                    hits.append("%s:%d: %s" % (os.path.relpath(p, root), i, m.group(0)))
for h in hits:
    print(h)
print("COUNT %d" % len(hits))
PY
}

OUT="$(scan)"; N="$(printf '%s\n' "$OUT" | sed -n 's/^COUNT //p')"
{ [ "${N:-x}" = 0 ]; } && ok "⑥-1 고친 팩 — 표와 다른 글자 0" || bad "⑥-1 표와 다른 글자 $N 건: $(printf '%s\n' "$OUT" | head -5 | tr '\n' ' ')"

T2="$FP/skill/scripts/tmp-fable-literal-r2403.txt"; T3="$FP/harness/tests/tmp-fable-literal-r2403.txt"
trap 'rm -f "$T2" "$T3"' EXIT
printf 'model = claude-fable-5-1[1m]\n' > "$T2"
OUT2="$(scan)"; N2="$(printf '%s\n' "$OUT2" | sed -n 's/^COUNT //p')"; H2="$(printf '%s\n' "$OUT2" | sed '$d')"
{ [ "${N2:-x}" = 1 ] && printf '%s\n' "$H2" | grep -q '^skill/scripts/tmp-fable-literal-r2403.txt:1:'; } \
  && ok "⑥-2 skill/scripts 임시 파일 «claude-fable-5-1» → FAIL 1건 · 그 파일:줄" || bad "⑥-2 잡힘=$N2 [$H2]"
rm -f "$T2"
printf 'model = claude-fable-5-1[1m]\n' > "$T3"
OUT3="$(scan)"; N3="$(printf '%s\n' "$OUT3" | sed -n 's/^COUNT //p')"
{ [ "${N3:-x}" = 0 ]; } && ok "⑥-3 tests/ 아래 같은 글자 → 세지 않음(PASS)" || bad "⑥-3 tests/ 를 세었다: $(printf '%s\n' "$OUT3" | sed '$d' | tr '\n' ' ')"
rm -f "$T3"

# 변이 M4 — «tests 를 세는» 제외 목록으로 같은 파일을 다시 스캔 → 걸려야 한다(사본 자기 재호출 0)
printf 'model = claude-fable-5-1[1m]\n' > "$T3"
OUTM="$(scan 'evidence design fixtures')"; NM="$(printf '%s\n' "$OUTM" | sed -n 's/^COUNT //p')"; HM="$(printf '%s\n' "$OUTM" | sed '$d')"
{ [ "${NM:-0}" -ge 1 ] && printf '%s\n' "$HM" | grep -q '^harness/tests/tmp-fable-literal-r2403.txt:1:'; } \
  && ok "M4 세지 않는 자리에서 tests 뺌 → ⑥-3 빨강(잡힘 · COUNT $NM)" || bad "M4 안 잡힘 COUNT=${NM:-없음} [$HM]"
rm -f "$T3"

echo "RUN 전체 $(( $(date +%s) - T_START ))초"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
