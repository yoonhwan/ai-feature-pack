#!/usr/bin/env bash
# test_issues_daily_status_prefix_r2309.sh — §① 상태별 칸이 status: 접두 라벨도 센다 (r2309)
#   반례 ①~④ · ①b · ⑥(계약 A1~A3) + 변이 M1~M4(사본에서만 · 변이마다 원본 같은 사례 1회 대조).
#   방식: r2305 꼴 — 모듈 로드 → 가짜 Issue dict → norm_issue → bucket()/build() · gh 0 · 라벨 쓰기 0.
#   ④ 기준판 = 고정 sha 9935e420(git show · 실패면 «판정 불가» rc 2) · ISSUES_DAILY_BIN=<dir> 로 다른 판 시험.
#   ⑥b diff 대상 = R2309_DIFF_BASE=<ref> 줄 때만(기본 건너뜀 · 나중 main 변경과 무관하게).
#   exit 0 = 전부 통과 · 1 = 실패 · 2 = 판정 불가
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
TO_LIMIT=70
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${ISSUES_DAILY_BIN:-$(cd "$HERE/../bin" && pwd)}"
MOD="$BIN/ft_issues_daily.py"
KIT="$HERE/../kit/fable-team/bin/ft_issues_daily.py"
REL="feature-pack/fable-team/legacy/1.x/harness/bin/ft_issues_daily.py"
BASE_SHA="9935e42086ca6f2b1bd0fd276348763b5c53baa3"
[ -f "$MOD" ] || { echo "도구 없음: $MOD" >&2; exit 1; }
TO="$(command -v timeout || command -v gtimeout || true)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
git -C "$HERE" show "$BASE_SHA:$REL" > "$T/base.py" 2>/dev/null \
  || { echo "판정 불가: 기준판 git show 실패($BASE_SHA)"; exit 2; }

cat > "$T/judge.py" <<'PY'
import importlib.util, re, sys
def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
m = load(sys.argv[1], "fid"); BASE = sys.argv[2]
def raw(n, labels=()):
    return {"number": n, "title": f"이슈 {n}", "body": "", "labels": [{"name": x} for x in labels],
            "createdAt": "2026-11-16T00:00:00Z", "updatedAt": "2026-11-16T00:00:00Z", "comments": []}
def counts(mod, raws):
    out = {"approved": 0, "pp": 0, "nt": 0, "none": 0, "other": 0}
    for r in raws:
        out[mod.bucket(mod.norm_issue(r))] += 1
    return {k: v for k, v in out.items() if v}
def text(mod, raws):
    return mod.build([mod.norm_issue(r) for r in raws], None, None, None, 1794870000.0, "20261120")[0]
def section(t, head):
    return t.split("## " + head, 1)[1].split("\n## ", 1)[0]
CASES = {
    "1":  ([raw(1, ["status:approved"]), raw(2, ["approved"]), raw(3, ["status:needs-triage"]),
            raw(4, ["type:bug"])], {"approved": 2, "nt": 1, "other": 1}),
    "1b": ([raw(5, ["hil:approved"])], {"other": 1}),
    "2":  ([raw(6, ["status:approved", "status:proposal-pending"]), raw(7, ["approved", "status:approved"])],
           {"approved": 2}),
    "3":  ([raw(8, ["status:needs-triage", "status:proposal-pending"]), raw(9)], {"pp": 1, "none": 1}),
}
def case4():
    raws = [r for c in CASES.values() for r in c[0]]
    new, old = text(m, raws), text(load(BASE, "base"), raws)
    same_tail = all(section(new, h) == section(old, h) for h in ("④", "⑤", "⑥"))
    state = lambda t: re.sub(r"\d+", "N", next(ln for ln in t.splitlines() if ln.startswith("- 상태별:")))
    same_row = state(new) == state(old)
    total = sum(counts(m, raws).values()) == len(raws)
    return (same_tail and same_row and total), f"④⑤⑥ 같음 {same_tail} · 상태별 줄 꼴 같음 {same_row} · 합 {total}"
for case in sys.argv[3:]:
    if case == "4":
        ok, info = case4()
    else:
        want = CASES[case][1]; got = counts(m, CASES[case][0]); ok = got == want
        info = f"기대 {want} · 실제 {got}"
    print(f"{'OK  ' if ok else 'FAIL'} {case} {info}")
PY

judge() { ${TO:+$TO $TO_LIMIT} python3 "$T/judge.py" "$1" "$T/base.py" "${@:2}"; }

echo "== 반례 ①~④ · ①b ($MOD) =="
out="$(judge "$MOD" 1 1b 2 3 4 2>&1)"; echo "$out" | sed 's/^/  /'
case "$out" in *FAIL*|"") fail=1;; esac
[ "$(echo "$out" | grep -c '^OK')" = 5 ] || fail=1

echo "== ⑥ bin·kit · 대상 파일 =="
if cmp -s "$MOD" "$KIT"; then echo "  OK   ⑥ bin·kit cmp0"; else echo "  FAIL ⑥ bin·kit 다름"; fail=1; fi
if [ -n "${R2309_DIFF_BASE:-}" ]; then
  names="$(git -C "$HERE" diff --name-only "$R2309_DIFF_BASE" 2>/dev/null)" \
    || { echo "판정 불가: git diff 실패"; exit 2; }
  want="$(printf '%s\n' "$REL" feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft_issues_daily.py \
    feature-pack/fable-team/legacy/1.x/harness/tests/test_issues_daily_status_prefix_r2309.sh | sort)"
  if [ "$(echo "$names" | sort)" = "$want" ]; then echo "  OK   ⑥b diff = 대상 3파일"
  else echo "  FAIL ⑥b diff 이름 · $(echo "$names" | tr '\n' ' ')"; fail=1; fi
else echo "  건너뜀 ⑥b (R2309_DIFF_BASE 없음)"; fi

mutate() {  # <이름> <검출 칸> <old> <new>
  local name="$1" case="$2" mdir="$T/mut-$1"; mkdir -p "$mdir"
  cp "$MOD" "$mdir/ft_issues_daily.py"
  python3 - "$mdir/ft_issues_daily.py" "$3" "$4" <<'PY' || { echo "  FAIL $name 변이 심기 실패(원문 없음)"; fail=1; return; }
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text(encoding="utf-8")
if sys.argv[2] not in t: sys.exit(1)
p.write_text(t.replace(sys.argv[2], sys.argv[3], 1), encoding="utf-8")
PY
  local mo oo; mo="$(judge "$mdir/ft_issues_daily.py" "$case" 2>&1)"; oo="$(judge "$MOD" "$case" 2>&1)"
  case "$mo" in FAIL*) echo "  OK   $name 변이 → 칸 $case FAIL(잡힘) · $mo";;
                *) echo "  FAIL $name 변이를 못 잡음 · $mo"; fail=1;; esac
  case "$oo" in OK*) echo "  OK   $name 원본 대조 → 칸 $case OK";;
                *) echo "  FAIL $name 원본 대조 · $oo"; fail=1;; esac
}
echo "== 변이 M1~M4 =="
mutate M1 1 'LABEL_APPROVED_ALL = (LABEL_APPROVED, "status:approved")' 'LABEL_APPROVED_ALL = (LABEL_APPROVED,)'
mutate M2 1 'LABEL_NT_ALL = (LABEL_NT, "status:needs-triage")' 'LABEL_NT_ALL = (LABEL_NT,)'
mutate M3 2 '    if any(lab in LABEL_APPROVED_ALL for lab in labels):
        return "approved"
    if LABEL_PP in labels:
        return "pp"
' '    if LABEL_PP in labels:
        return "pp"
    if any(lab in LABEL_APPROVED_ALL for lab in labels):
        return "approved"
'
mutate M4 1b 'if any(lab in LABEL_APPROVED_ALL for lab in labels):' 'if any(lab.endswith("approved") for lab in labels):'

[ "$fail" = 0 ] && { echo "PASS r2309 status: 접두 칸"; exit 0; }
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
