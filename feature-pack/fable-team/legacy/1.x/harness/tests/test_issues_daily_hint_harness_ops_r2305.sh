#!/usr/bin/env bash
# test_issues_daily_hint_harness_ops_r2305.sh — §⑤ 하네스 팀 후보 = harness-ops (r2305)
#   반례 ①~④ · ②b · ⑥(계약 A1~A3) + 변이 M1~M3(사본에서만 · 변이마다 원본 같은 사례 1회 대조).
#   방식: r2134 꼴 — 모듈 로드 → 가짜 Issue dict → norm_issue → build() → §⑤ 줄 비교 · gh 0 · 라벨 쓰기 0.
#   ④ 기준판 = 고정 sha a598b356(git show · 실패면 «판정 불가» rc 2) · ISSUES_DAILY_BIN=<dir> 로 다른 판 시험.
#   ⑥b diff 대상 = R2305_DIFF_BASE=<ref> 줄 때만(기본 건너뜀 · 나중 main 변경과 무관하게).
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
BASE_SHA="a598b356aa353d80af020e458b5f566914a7a61c"
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
BODY = "## 재현\n- issue 링크: #1\n- 판정: planner 가 본다\n"
def raw(n, title, labels=(), body=BODY):
    return {"number": n, "title": title, "body": body, "labels": [{"name": x} for x in labels],
            "createdAt": "2026-11-16T00:00:00Z", "updatedAt": "2026-11-16T00:00:00Z", "comments": []}
def text(mod, raws):
    return mod.build([mod.norm_issue(r) for r in raws], None, None, None, 1794870000.0, "20261117")[0]
def section(t):
    return t.split("## ⑤", 1)[1].split("\n## ", 1)[0]
def rows(raws):
    out = {}
    for ln in section(text(m, raws)).splitlines():
        if ln.startswith("| #") and "(후보)" in ln:
            c = [x.strip() for x in ln.strip("|").split("|")]
            out[int(c[0][1:])] = c[1].replace("(후보)", "")
    return out
T8645 = "ft2 글뿐인 선행 줄이 바퀴마다 판정 불가를 찍음"
T8510 = "[aifp] ci search 비ASCII 결과 줄 probe panic — 래퍼 감지·rg 폴백·rc 정직"
T8488 = "[ops] LangSmith 계정 이전(developer.ts@byourz.com) + 키 교체 + 추적 연동 재선정"
CASES = {
    "1": ([raw(8645, T8645), raw(8510, T8510)], {8645: "harness-ops", 8510: "harness-ops"}),
    "2": ([raw(9101, "[harness] keeper 바퀴 끊김"), raw(9102, "[harness] 문서 정리")],
          {9101: "harness-ops", 9102: "harness-ops"}),
    "2b": ([raw(9103, "[shared-harness] x"), raw(9104, "[harness-ops] x")],
           {9103: "harness-ops", 9104: "harness-ops"}),
    "3": ([raw(8488, T8488), raw(9002, "[ops] ft2 이미 라벨 있음", labels=("team:ops",)),
           raw(9001, "LangSmith 계정 이전 정리", body="본문에만 planner 낱말"), raw(9105, "v65 무대 줄")],
          {8488: "ops", 9105: "v65"}),
}
ROW = re.compile(r"^\| #\d+ \| [a-z0-9-]+\(후보\) \| .+ \|$")
def case4():
    raws = CASES["1"][0] + CASES["3"][0] + [raw(9106, "이슈 표 정리"), raw(9107, "keeper launchd 재시작")]
    new, old = text(m, raws), text(load(BASE, "base"), raws)
    bad = [ln for ln in section(new).splitlines() if re.match(r"\| #\d", ln) and not ROW.match(ln)]
    same = new == old.replace("shared-harness(후보)", "harness-ops(후보)")
    return (not bad and same), f"줄 꼴 어긋남 {bad} · 기준판과 하네스 칸 빼고 같음 {same}"
for case in sys.argv[3:]:
    if case == "4":
        ok, info = case4()
    else:
        want = CASES[case][1]; got = rows(CASES[case][0]); ok = got == want
        info = f"기대 {want} · 실제 {got}"
    print(f"{'OK  ' if ok else 'FAIL'} {case} {info}")
PY

judge() { ${TO:+$TO $TO_LIMIT} python3 "$T/judge.py" "$1" "$T/base.py" "${@:2}"; }

echo "== 반례 ①~④ · ②b ($MOD) =="
out="$(judge "$MOD" 1 2 2b 3 4 2>&1)"; echo "$out" | sed 's/^/  /'
case "$out" in *FAIL*|"") fail=1;; esac
[ "$(echo "$out" | grep -c '^OK')" = 5 ] || fail=1

echo "== ⑥ bin·kit · 대상 파일 =="
if cmp -s "$MOD" "$KIT"; then echo "  OK   ⑥ bin·kit cmp0"; else echo "  FAIL ⑥ bin·kit 다름"; fail=1; fi
if [ -n "${R2305_DIFF_BASE:-}" ]; then
  names="$(git -C "$HERE" diff --name-only "$R2305_DIFF_BASE" 2>/dev/null)" \
    || { echo "판정 불가: git diff 실패"; exit 2; }
  want="$(printf '%s\n' "$REL" feature-pack/fable-team/legacy/1.x/harness/kit/fable-team/bin/ft_issues_daily.py \
    feature-pack/fable-team/legacy/1.x/harness/tests/test_issues_daily_hint_harness_ops_r2305.sh \
    feature-pack/fable-team/legacy/1.x/harness/tests/test_issues_daily_team_hint_r2134.sh | sort)"
  if [ "$(echo "$names" | sort)" = "$want" ]; then echo "  OK   ⑥b diff = 대상 4파일"
  else echo "  FAIL ⑥b diff 이름 · $(echo "$names" | tr '\n' ' ')"; fail=1; fi
else echo "  건너뜀 ⑥b (R2305_DIFF_BASE 없음)"; fi

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
echo "== 변이 M1~M3 =="
mutate M1 1 'SHARED_HARNESS_HINT = ("harness-ops",' 'SHARED_HARNESS_HINT = ("shared-harness",'
mutate M2 2 '    if head and head.group(1).strip() in HARNESS_HEADS:
        return "harness-ops", f"제목 팀 머리 «[{head.group(1).strip()}]»"
' ''
mutate M3 3 'if head and head.group(1).strip() in HARNESS_HEADS:' 'if head:'

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (①~④ · ②b · ⑥ · 변이 M1~M3) — 단계: 표 ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
