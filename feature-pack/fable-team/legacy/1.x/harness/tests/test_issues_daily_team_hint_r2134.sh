#!/usr/bin/env bash
# test_issues_daily_team_hint_r2134.sh — 00시 이슈 표 §⑤ 팀 후보 = 제목만 · 실제 team:* 라벨 이름 (r2134)
#   반례 ①~⑤(계약 H1~H5) + 변이 M1~M3(사본에서만 · 변이마다 원본 같은 사례 1회 대조).
#   방식: ft_issues_daily.py 를 모듈로 읽어 gh 꼴 이슈 json → norm_issue → build() 렌더 → §⑤ 줄 비교.
#         실 gh·실 우편함·라벨 쓰기 0 · 고정 sleep 0 · 자기 재호출 0 · ulimit -u + timeout 70.
#   ISSUES_DAILY_BIN=<dir> 로 다른 판(기준판 사본)을 시험한다(기본 = ../bin).
#   exit 0 = 전부 통과 · 1 = 실패 1건 이상
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
TO_LIMIT=70
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${ISSUES_DAILY_BIN:-$(cd "$HERE/../bin" && pwd)}"
MOD="$BIN/ft_issues_daily.py"
[ -f "$MOD" ] || { echo "도구 없음: $MOD" >&2; exit 1; }
TO="$(command -v timeout || command -v gtimeout || true)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0

# ── 판정기: <모듈> <사례...> → 사례마다 «OK|FAIL 사례 — 기대 · 실제» 1줄 ──
cat > "$T/judge.py" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("fid", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
BODY = "## 재현\n- issue 링크: #1\n- 판정: planner 가 본다\n"
def raw(n, title, labels=(), body=BODY):
    return {"number": n, "title": title, "body": body, "labels": [{"name": x} for x in labels],
            "createdAt": "2026-11-16T00:00:00Z", "updatedAt": "2026-11-16T00:00:00Z", "comments": []}
def rows(raws):
    issues = [m.norm_issue(r) for r in raws]
    text, _ = m.build(issues, None, None, None, 1794870000.0, "20261117")
    sec = text.split("## ⑤", 1)[1].split("\n## ", 1)[0]
    out = {}
    for ln in sec.splitlines():
        if ln.startswith("| #") and "(후보)" in ln:
            c = [x.strip() for x in ln.strip("|").split("|")]
            out[int(c[0][1:])] = c[1].replace("(후보)", "")
    return out
TITLES = json.load(open(sys.argv[2], encoding="utf-8"))
CASES = {
    "1": ([raw(8645, TITLES["8645"])], {8645: "harness-ops"}),
    "2": ([raw(8488, TITLES["8488"])], {8488: "ops"}),
    "3": ([raw(8510, TITLES["8510"])], {8510: "harness-ops"}),
    "4": ([raw(9001, "LangSmith 계정 이전 정리", body="본문에만 planner 낱말")], {}),
    "5": ([raw(int(k), v) for k, v in TITLES.items()]
          + [raw(9002, "[ops] ft2 이미 라벨 있음", labels=("team:ops",))],
          {int(k): ("ops" if k == "8488" else "harness-ops") for k in TITLES}),
}
for case in sys.argv[3:]:
    issues, want = CASES[case]
    got = rows(issues)
    if case == "5":
        hit = sum(1 for k, v in want.items() if got.get(k) == v)
        extra = sorted(set(got) - set(want))
        ok = hit == len(want) and not extra
        print(f"{'OK  ' if ok else 'FAIL'} ⑤ 13개 제목 맞음 {hit}/{len(want)} · 덧줄 {extra}")
    else:
        ok = got == want
        print(f"{'OK  ' if ok else 'FAIL'} {'①②③④'[int(case) - 1]} 기대 {want} · 실제 {got}")
PY

cat > "$T/titles.json" <<'JSON'
{
  "8488": "[ops] LangSmith 계정 이전(developer.ts@byourz.com) + 키 교체 + 추적 연동 재선정",
  "8510": "[aifp] ci search 비ASCII 결과 줄 probe panic — 래퍼 감지·rg 폴백·rc 정직",
  "8631": "ft2 Slack 접수(dict-work)가 접수 칸 영구 점유",
  "8632": "ft2 2.0 완료 전 keeper fill 새 카드 투입 — 전 팀 새 카드 보류 설정 없음",
  "8633": "ft2 launch-failed PARKED 잔류·착지 끝 카드 대기/ 잔류로 keeper 재발주",
  "8640": "ft2 keeper 쪽지 받는 곳 없음·재시도 중복·바퀴 통 수 상한 없음",
  "8643": "ft2 Slack 접수 뒤 깨움 실패가 다시 보내지지 않음",
  "8644": "ft2 착지 끝난 좌석이 60분 유휴를 기다리고 마감 답장 1통에 닫기가 막힘",
  "8645": "ft2 글뿐인 선행 줄이 바퀴마다 판정 불가를 찍음",
  "8647": "ft2 card_stage git 7초 초과 · 동시 실행이 남의 카드 이동을 되돌림",
  "8650": "ft2 keeper 가 penalty 팀에 나노를 새로 엶(fill·다음 카드 pick 이 PENALTY_STOP 안 읽음)",
  "8653": "ci search 가 시험 파일을 못 찾는다(--allow-tests 누락 · 모르는 인자 path 삼킴)",
  "8655": "aifp ci 시험 기준판 sha 고정(ci-test-base-sha-pin)"
}
JSON

judge() { ${TO:+$TO $TO_LIMIT} python3 "$T/judge.py" "$1" "$T/titles.json" "${@:2}"; }

echo "== 반례 ①~⑤ ($MOD) =="
out="$(judge "$MOD" 1 2 3 4 5 2>&1)"; echo "$out" | sed 's/^/  /'
case "$out" in *FAIL*|"") fail=1;; esac
[ "$(echo "$out" | grep -c '^OK')" = 5 ] || fail=1

# ── 변이: 사본에서만 · 변이된 판은 검출 칸 FAIL · 원본은 같은 칸 OK ──
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
mutate M1 4 'hay = issue["title"].lower()' 'hay = f"{issue['"'"'title'"'"']}\n{issue['"'"'body'"'"'][:2000]}".lower()'
m1_one="$(judge "$T/mut-M1/ft_issues_daily.py" 1 2>&1)"
echo "  참고 M1 에서 ① = ${m1_one%% *}(제목 ft2 가 먼저 맞아 PASS 남음 = 정상)"
mutate M2 2 '    head = re.match(r"\[([^\]]+)\]", issue["title"])' '    head = None'
mutate M3 1 'TEAM_HINTS = (SHARED_HARNESS_HINT,) + OTHER_HINTS' 'TEAM_HINTS = OTHER_HINTS + (SHARED_HARNESS_HINT,)'

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (①~⑤ · 변이 M1~M3) — 단계: 표 ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
