#!/usr/bin/env bash
# test_issues_daily_paging_r1395.sh — r1395: 이슈 일일 표 «열린 목록 = 50건 1쪽 GraphQL cursor» 반례 9 + 기준판 + 변이 4
#   계기: 열린 Issue 308건 + 코멘트를 `gh issue list --limit 1000 --json 7필드` 1회로 읽던 호출이 10.4초 걸려
#         `timeout 7` × 재시도 1 을 둘 다 넘었다(11-05 18:53 손 실행 · 00:10 자동 회차 «판정 불가» · #261327).
#   방식: 임시 FT_ROOT + 가짜 gh(tests/_gh_graphql_stub.py 대역 · 호출 기록 · 상한 초과 = exit 124 흉내)
#         + 표 폴더. 실 GitHub 0 · 네트워크 0 · 고정 sleep 0 · 자기 재호출 0(이 파일은 자기 자신을 부르지 않는다)
#         · ulimit -u + timeout 70 (하드 룰 22 — 시험 1개 단독 70초).
#   기준판 = 팩 origin/main r1115 판(922168e0e7 고정 40hex) — 그 판은 graphql 을 안 부르므로 C1~C7 이 FAIL 이어야 한다.
#   exit 0 = 전부 통과 · 1 = 실패 1건 이상
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
TO_LIMIT=70
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
KIT="$(cd "$HERE/../kit" && pwd)"
TOOL="$BIN/ft-issues-daily.sh"
STUB="$HERE/_gh_graphql_stub.py"
[ -f "$TOOL" ] || { echo "도구 없음: $TOOL" >&2; exit 1; }
[ -f "$STUB" ] || { echo "대역 없음: $STUB" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
has() { if grep -Fq -- "$1" "$2"; then echo "  OK   $3"; else echo "  FAIL $3 — 없음[$1] in ${2##*/}"; fail=1; fi; }
nhas() { if grep -Fq -- "$1" "$2"; then echo "  FAIL $3 — 있으면 안 되는[$1] in ${2##*/}"; fail=1; else echo "  OK   $3"; fi; }
NOW="$(python3 -c 'import datetime;print(int(datetime.datetime(2026,11,5,0,12).timestamp()))')"
DAY=20261105
export NOW
CLOSE_COMMENT='닫는 사건: 재현 후 수리 착지
PR: #9001
재현 PASS: 3/3
정리: 임시 파일 0
기록: 카드 r9000
정본: design/harness/ISSUE-TRANSITIONS.md#3@0123456789abcdef0123456789abcdef01234567
원인 확정: Y — 락 해제 순서가 뒤집혀 있었다
같은 증상 보류: 0'
export CLOSE_COMMENT
mkdir -p "$T/bin" "$T/fix" "$T/mbox"

# ── 시나리오 생성기 — stdin 스펙 → <out>.json (열린 쪽·닫힌 쪽·초과 횟수) ──
cat > "$T/gen.py" <<'PY'
import datetime, json, os, sys
out, spec = sys.argv[1], json.load(sys.stdin)
now = int(os.environ["NOW"])
def iso(off):
    return datetime.datetime.fromtimestamp(now + int(off), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
def comments_of(raw):
    if raw is None:
        return []
    if isinstance(raw, list):
        return [{"body": os.environ["CLOSE_COMMENT"] if c.get("body") == "@CLOSE" else c.get("body", ""),
                 "createdAt": iso(c.get("offset", -1800))} for c in raw]
    n = int(raw.get("n") or 0)
    made = [{"body": f"메모 {i}", "createdAt": iso(-3600 - i)} for i in range(1, n + 1)]
    tail = str(raw.get("tail") or "")
    if made and tail:
        made[-1] = {"body": os.environ["CLOSE_COMMENT"] if tail == "@CLOSE" else tail,
                    "createdAt": iso(-600)}
    return made
def row(r):
    num = int(r.get("number") or 0)
    return {"number": num, "title": r.get("title") or f"issue {num}",
            "labels": [{"name": x} for x in (r.get("labels") or [])],
            "createdAt": iso(r.get("created_offset", -950400)),
            "updatedAt": iso(r.get("updated_offset", -691200)),
            "body": r.get("body") or "", "comments": comments_of(r.get("comments"))}
o = spec.get("open") or {}
if o.get("pages") is not None:
    open_pages = [[row(r) for r in pg] for pg in o["pages"]]
else:
    rows = ([row(r) for r in o["rows"]] if o.get("rows") is not None
            else [row({"number": 100 + i}) for i in range(int(o.get("count") or 0))])
    size = int(o.get("page") or 50)
    open_pages = [rows[i:i + size] for i in range(0, len(rows), size)] or [[]]
c = spec.get("closed") or {}
if c.get("pages") is not None:
    closed_pages = c["pages"]
else:
    size = int(c.get("page") or 100)
    rows = [{"number": 9000 + i, "closed_offset": c.get("closed_offset", -3600)}
            for i in range(int(c.get("count") or 0))]
    closed_pages = [rows[i:i + size] for i in range(0, len(rows), size)] or [[]]
closed_pages = [[{"number": int(r.get("number") or 0), "closedAt": iso(r.get("closed_offset", -3600))}
                 for r in pg] for pg in closed_pages]
payload = {"repo": spec.get("repo") or {"owner": "byz", "name": "pack"},
           "open": {"totalCount": sum(len(p) for p in open_pages), "pages": open_pages},
           "closed": {"pages": closed_pages, "totalCount": sum(len(p) for p in closed_pages)}}
if c.get("issueCount") is not None:
    payload["closed"]["issueCount"] = int(c["issueCount"])
if spec.get("timeout"):
    payload["timeout"] = dict(spec["timeout"])
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False)
PY
mkfix() { python3 "$T/gen.py" "$T/fix/$1.json"; }

# ── 가짜 gh (대역 · 호출 기록 · 모르는 호출 = rc1) ──
GH="$T/bin/gh"; GH_LOG="$T/gh-calls.log"; export GH_LOG
{ echo '#!/usr/bin/env bash'; echo 'exec python3 "'"$STUB"'" --fixture "${FIX:?}" "$@"'; } > "$GH"
chmod +x "$GH"; : > "$GH_LOG"

# ── 가짜 mbox (이 시험은 발신을 안 본다 · 실제 발신 0) ──
MBOX="$T/bin/mbox-stub.sh"
printf '#!/usr/bin/env bash\necho "QUEUED seq=stub"\n' > "$MBOX"; chmod +x "$MBOX"

# ── 임시 루트(명부·state·표 폴더) ──
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design/teams/issues/daily"
printf '{"_master":"byz-planner-master-claude#234"}\n' > "$ROOT/.fable-team/seats-planner.json"
printf '{"_master":"byz-issues-master-claude#49"}\n'  > "$ROOT/.fable-team/seats-issues.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/allstop-ok.sh"; chmod +x "$T/bin/allstop-ok.sh"

run_tool() { # <도구> <표폴더> <시나리오> [env…]
  local tool="$1" dir="$2" fix="$3"; shift 3
  ( export FT_ROOT="$ROOT" FT_NOW="$NOW" FT_GH="$GH" FT_MBOX_SH="$MBOX" FT_ISSUES_DAILY_DIR="$dir" \
           FT_ISSUES_DAILY_CLASSIFY="$BIN/ft-issue-classify.sh" FT_ALLSTOP="$T/bin/allstop-ok.sh" \
           FT_ISSUES_DAILY_REPO="byz/pack" FT_ISSUES_DAILY_NO_SEND=1 FIX="$fix"
    for kv in "$@"; do export "${kv?}"; done
    timeout $TO_LIMIT bash "$tool" )
}
fresh() { local d="$T/out-$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }

# ── 기준판 = 팩 origin/main r1115 판(922168e0e7 고정 40hex) — 반례 1 의 «graphql 쪽 호출» 검사가 여기서 FAIL 해야 한다 ──
BASE="$T/base"; mkdir -p "$BASE"
git -C "$HERE/.." show 922168e0e762031296eda0f7a27284719d8c2b6a:feature-pack/fable-team/harness/bin/ft_issues_daily.py > "$BASE/ft_issues_daily.py" 2>/dev/null
cp "$BIN/ft-issues-daily.sh" "$BASE/" 2>/dev/null || true
echo "== C0 기준판(r1115) 에 반례 1 을 넣으면 FAIL — 옛 경로는 쪽 읽기(graphql)를 안 부른다 =="
if [ -f "$BASE/ft_issues_daily.py" ]; then
  mkfix c0 <<'JSON'
{"open": {"count": 120, "page": 50}, "closed": {"count": 1}}
JSON
  : > "$GH_LOG"; D0="$(fresh c0)"
  run_tool "$BASE/ft-issues-daily.sh" "$D0" "$T/fix/c0.json" >/dev/null 2>&1; RC0=$?
  TB0="$D0/TABLE-daily-$DAY.md"
  chk "C0 기준판 rc=0(옛 경로도 표는 쓴다)" 0 "$RC0"
  chk "C0 옛 경로 = 쪽 읽기(graphql) 호출 0 → C1 검사가 FAIL" 0 "$(grep -c 'issues(states:OPEN' "$GH_LOG")"
  nhas "totalCount=" "$TB0" "C0 옛 경로 = 합 검산 줄에 totalCount 없음 → C1 검사가 FAIL"
else
  echo "  FAIL 기준판(922168e0 r1115) 없음 — 고정 40hex 확인"; fail=1
fi

echo "== C1 열린 120건 · 50건 1쪽 3쪽 → 건수 120 · 판정 불가 0 =="
mkfix c1 <<'JSON'
{"open": {"count": 120, "page": 50}, "closed": {"count": 1}}
JSON
: > "$GH_LOG"; D1="$(fresh c1)"
run_tool "$TOOL" "$D1" "$T/fix/c1.json" >/dev/null 2>"$T/err1"; RC1=$?
TB1="$D1/TABLE-daily-$DAY.md"
chk "C1 rc=0" 0 "$RC1"
has "- 열린 총수: 120" "$TB1" "C1 표 건수 120(쪽 합치기)"
has "totalCount=120" "$TB1" "C1 합 검산 줄에 첫 쪽 totalCount 동봉"
nhas "## 판정 불가" "$TB1" "C1 판정 불가 0"
chk "C1 열린 쪽 호출 3회" 3 "$(grep -c 'issues(states:OPEN' "$GH_LOG")"
chk "C1 2쪽 호출 = cursor c2" 1 "$(grep -c -- '-F c=c2' "$GH_LOG")"
chk "C1 3쪽 호출 = cursor c3" 1 "$(grep -c -- '-F c=c3' "$GH_LOG")"
has "- 닫힌(24h): 1건" "$TB1" "C1 닫힌(24h) 칸 = search 쪽 읽기 1건"
chk "C1 쪽마다 PAGE 시간 줄 4개(열린 3 + 닫힌 1)" 4 "$(grep -c '^PAGE ' "$T/err1")"

echo "== C2 2쪽 1회 상한 초과 · 재시도 성공 → 표 정상 =="
mkfix c2 <<'JSON'
{"open": {"count": 120, "page": 50}, "closed": {"count": 1}, "timeout": {"open:2": 1}}
JSON
: > "$GH_LOG"; D2="$(fresh c2)"
run_tool "$TOOL" "$D2" "$T/fix/c2.json" >/dev/null 2>"$T/err2"; RC2=$?
TB2="$D2/TABLE-daily-$DAY.md"
chk "C2 rc=0" 0 "$RC2"
has "- 열린 총수: 120" "$TB2" "C2 재시도 성공 → 120건"
nhas "## 판정 불가" "$TB2" "C2 판정 불가 0"
chk "C2 2쪽 = 2회 호출(초과 1 + 재시도 1)" 2 "$(grep -c -- '-F c=c2' "$GH_LOG")"

echo "== C3 2쪽 2회 연속 상한 초과 → 판정 불가 · rc 5 =="
mkfix c3 <<'JSON'
{"open": {"count": 120, "page": 50}, "closed": {"count": 1}, "timeout": {"open:2": 2}}
JSON
: > "$GH_LOG"; D3="$(fresh c3)"
run_tool "$TOOL" "$D3" "$T/fix/c3.json" >/dev/null 2>"$T/err3"; RC3=$?
TB3="$D3/TABLE-daily-$DAY.md"
chk "C3 rc=5" 5 "$RC3"
has "## 판정 불가" "$TB3" "C3 판정 불가 표(0건으로 숨김 0)"
has "gh api graphql 2쪽 실패(2회)" "$TB3" "C3 원인 = 2쪽 실패(2회)"
nhas "- 열린 총수:" "$TB3" "C3 잘린 표 0"

echo "== C4 한 Issue 코멘트 120개(totalCount) → 101~120번째 이어 읽어 8항 판정 =="
mkfix c4 <<'JSON'
{"open": {"rows": [
  {"number": 101, "title": "v65 교정 항목", "labels": ["approved"]},
  {"number": 102, "title": "[이슈] 이슈팀 정리", "labels": ["approved", "team:issues"]},
  {"number": 103, "title": "이슈팀 정리", "labels": ["approved"], "comments": {"n": 120, "tail": "@CLOSE"}},
  {"number": 3807, "title": "제안서: 야간 장치", "labels": ["status:proposal-pending"]},
  {"number": 4400, "title": "라벨 없이 온 것", "created_offset": -3600, "updated_offset": -1800}
 ]}, "closed": {"count": 1}}
JSON
: > "$GH_LOG"; D4="$(fresh c4)"
run_tool "$TOOL" "$D4" "$T/fix/c4.json" >/dev/null 2>"$T/err4"; RC4=$?
TB4="$D4/TABLE-daily-$DAY.md"
chk "C4 rc=0" 0 "$RC4"
has "- #103 이슈팀 정리" "$TB4" "C4 닫기 후보 = 120번째 코멘트의 8항을 봤다"
chk "C4 코멘트 이어 읽기 1회" 1 "$(grep -c -F 'issue(number:$num' "$GH_LOG")"
has "totalCount=5" "$TB4" "C4 합 검산 totalCount=5"

echo "== C5 라벨 50개 초과 → 판정 불가(이어 읽기 없음) · rc 5 =="
python3 -c 'import json;n=[f"lab-{i}" for i in range(51)];print(json.dumps({"open":{"rows":[{"number":7001,"title":"라벨 51개","labels":n}]},"closed":{"count":0}}))' | mkfix c5
: > "$GH_LOG"; D5="$(fresh c5)"
run_tool "$TOOL" "$D5" "$T/fix/c5.json" >/dev/null 2>"$T/err5"; RC5=$?
TB5="$D5/TABLE-daily-$DAY.md"
chk "C5 rc=5" 5 "$RC5"
has "라벨 50개 초과" "$TB5" "C5 라벨 잘림 = 판정 불가"

echo "== C6 41쪽(2,050건) → 판정 불가 · 2,000건 초과 · rc 5 · 잘린 표 0 =="
mkfix c6 <<'JSON'
{"open": {"count": 2050, "page": 50}, "closed": {"count": 0}}
JSON
: > "$GH_LOG"; D6="$(fresh c6)"
run_tool "$TOOL" "$D6" "$T/fix/c6.json" >/dev/null 2>"$T/err6"; RC6=$?
TB6="$D6/TABLE-daily-$DAY.md"
chk "C6 rc=5" 5 "$RC6"
has "2,000건 초과" "$TB6" "C6 쪽 수 상한 = 판정 불가"
nhas "- 열린 총수:" "$TB6" "C6 잘린 표 0"
chk "C6 열린 쪽 호출 40회(41쪽째에서 멈춤)" 40 "$(grep -c 'issues(states:OPEN' "$GH_LOG")"

echo "== C7 닫힌(24h) = search 쪽 · issueCount 대조 =="
mkfix c7a <<'JSON'
{"open": {"count": 3, "page": 50}, "closed": {"count": 250, "page": 100, "issueCount": 250}}
JSON
: > "$GH_LOG"; D7="$(fresh c7a)"
run_tool "$TOOL" "$D7" "$T/fix/c7a.json" >/dev/null 2>"$T/err7"; RC7=$?
TB7="$D7/TABLE-daily-$DAY.md"
chk "C7a rc=0" 0 "$RC7"
has "- 닫힌(24h): 250건" "$TB7" "C7a 3쪽 합 250 = issueCount 250 → 칸 250"
chk "C7a 닫힌 쪽 호출 3회" 3 "$(grep -c 'search(type:ISSUE' "$GH_LOG")"
mkfix c7b <<'JSON'
{"open": {"count": 3, "page": 50}, "closed": {"count": 200, "page": 100, "issueCount": 250}}
JSON
D7b="$(fresh c7b)"
run_tool "$TOOL" "$D7b" "$T/fix/c7b.json" >/dev/null 2>"$T/err7b"; RC7B=$?
TB7B="$D7b/TABLE-daily-$DAY.md"
chk "C7b rc=0(그 칸만 죽는다)" 0 "$RC7B"
has "- 닫힌(24h): 판정 불가(잘림)" "$TB7B" "C7b 합 200 != issueCount 250 → 그 칸만 판정 불가(잘림)"
has "- 열린 총수: 3" "$TB7B" "C7b 표 나머지는 정상"

echo "== C8 같은 입력 → 옛 경로(기준판 r1115)와 표 본문이 같다(머리 시각·검산 줄 제외) =="
mkfix c8 <<'JSON'
{"open": {"rows": [
  {"number": 101, "title": "v65 교정 항목", "labels": ["approved"]},
  {"number": 102, "title": "[이슈] 이슈팀 정리", "labels": ["approved", "team:issues"]},
  {"number": 103, "title": "이슈팀 정리", "labels": ["approved"], "comments": [{"body": "@CLOSE", "offset": -1800}]},
  {"number": 3807, "title": "제안서: 야간 장치", "labels": ["status:proposal-pending"]},
  {"number": 4200, "title": "제안서: 매거진 칸", "labels": ["status:proposal-pending"]},
  {"number": 4300, "title": "needs triage 것", "labels": ["needs-triage"]},
  {"number": 4400, "title": "라벨 없이 온 것", "created_offset": -3600, "updated_offset": -1800}
 ]}, "closed": {"pages": [[{"number": 9000, "closed_offset": -3600}]], "issueCount": 1}}
JSON
if [ -f "$BASE/ft_issues_daily.py" ]; then
  D8="$(fresh c8)"; DB8="$(fresh c8base)"
  run_tool "$TOOL" "$D8" "$T/fix/c8.json" "FT_ISSUES_DAILY_REPO=" >/dev/null 2>"$T/err8"; RC8=$?
  run_tool "$BASE/ft-issues-daily.sh" "$DB8" "$T/fix/c8.json" >/dev/null 2>"$T/err8b"; RCB8=$?
  TB8="$D8/TABLE-daily-$DAY.md"; TBB8="$DB8/TABLE-daily-$DAY.md"
  chk "C8 새 경로 rc=0" 0 "$RC8"
  chk "C8 기준판 rc=0" 0 "$RCB8"
  has "totalCount=7" "$TB8" "C8 새 경로 = 총수 + totalCount"
  nhas "totalCount=" "$TBB8" "C8 기준판 = totalCount 없음(옛 경로 확인)"
  strip_head() { grep -v -e '^# 이슈 일일 표 —' -e '^- 합:' "$1"; }
  if diff -u <(strip_head "$TBB8") <(strip_head "$TB8") > "$T/c8.diff" 2>&1; then
    echo "  OK   C8 표 본문 바이트 같음(하류 꼴 변경 0)"
  else
    echo "  FAIL C8 표 본문이 다르다 — $(head -8 "$T/c8.diff" | tr '\n' ' ')"; fail=1
  fi
else
  echo "  FAIL C8 기준판 없음 — 고정 40hex 확인"; fail=1
fi

echo "== C9 쪽 사이 중복 번호 1건 → 1번만 셈 =="
mkfix c9 <<'JSON'
{"open": {"pages": [
   [{"number": 11, "title": "a"}, {"number": 12, "title": "b"}, {"number": 13, "title": "c"}],
   [{"number": 13, "title": "c"}, {"number": 14, "title": "d"}]
 ]}, "closed": {"count": 0}}
JSON
D9="$(fresh c9)"
run_tool "$TOOL" "$D9" "$T/fix/c9.json" >/dev/null 2>"$T/err9"; RC9=$?
TB9="$D9/TABLE-daily-$DAY.md"
chk "C9 rc=0" 0 "$RC9"
has "- 열린 총수: 4" "$TB9" "C9 중복 번호는 1번만 셈"
has "= 4 · totalCount=5" "$TB9" "C9 대조 차이는 숫자 두 개를 그대로 적는다(판정 불가 아님)"

echo "== 변이 4 (고친 자리 하나씩 망가뜨리면 그 반례가 FAIL 이어야 한다) =="
MUT="$T/mut"; mkdir -p "$MUT/bin"
mutate() { # <번호> <설명>
  rm -rf "$MUT/bin"; mkdir -p "$MUT/bin"
  cp "$BIN/ft_issues_daily.py" "$BIN/ft-issues-daily.sh" "$MUT/bin/"
  python3 - "$MUT/bin/ft_issues_daily.py" "$1" <<'PY'
import sys
p, which = sys.argv[1], sys.argv[2]
t = open(p, encoding="utf-8").read()
PAIRS = {
 "1": ('    for _ in (1, 2):', '    for _ in (1,):'),
 "2": ('        if not info.get("hasNextPage"):\n            break', '        break'),
 "3": ('    if want > len(comments):', '    if False:'),
 "4": ('        if count is None or len(pairs) != count or count > CLOSED_MAX:',
       '        if count is None or count > CLOSED_MAX:'),
}
old, new = PAIRS[which]
if t.count(old) != 1:
    print(f"MUTFAIL {which} — 닻 {t.count(old)}개")
    raise SystemExit(2)
open(p, "w", encoding="utf-8").write(t.replace(old, new, 1))
PY
}
# 변이 ① 재시도 제거 → C2(2쪽 1회 초과 후 재시도) FAIL — 시나리오는 새로 만든다(초과 횟수를 앞 시험이 이미 써버렸다)
mkfix c2mut <<'JSON'
{"open": {"count": 120, "page": 50}, "closed": {"count": 1}, "timeout": {"open:2": 1}}
JSON
mutate 1 || { echo "  FAIL 변이① 적용 실패(닻 불일치)"; fail=1; }
DM="$(fresh mut1)"
run_tool "$MUT/bin/ft-issues-daily.sh" "$DM" "$T/fix/c2mut.json" >/dev/null 2>&1; RCM=$?
if [ "$RCM" = 5 ] && grep -Fq "2쪽 실패" "$DM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  OK   변이① 재시도 제거 → C2 가 판정 불가(시험이 잡는다)"
else echo "  FAIL 변이① — 재시도를 지웠는데 C2 가 통과했다(rc=$RCM)"; fail=1; fi
# 변이 ② 1쪽에서 멈춤 → C1(120건) FAIL
mutate 2 || { echo "  FAIL 변이② 적용 실패(닻 불일치)"; fail=1; }
DM="$(fresh mut2)"
run_tool "$MUT/bin/ft-issues-daily.sh" "$DM" "$T/fix/c1.json" >/dev/null 2>&1
if grep -Fq -- "- 열린 총수: 120" "$DM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  FAIL 변이② — 1쪽에서 멈췄는데 120건이 나왔다"; fail=1
else echo "  OK   변이② hasNextPage 루프 제거 → C1 FAIL(시험이 잡는다)"; fi
# 변이 ③ 코멘트 이어 읽기 제거 → C4(120번째 코멘트 8항) FAIL
mutate 3 || { echo "  FAIL 변이③ 적용 실패(닻 불일치)"; fail=1; }
DM="$(fresh mut3)"
run_tool "$MUT/bin/ft-issues-daily.sh" "$DM" "$T/fix/c4.json" >/dev/null 2>&1
if grep -Fq -- "- #103 이슈팀 정리" "$DM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  FAIL 변이③ — 이어 읽기를 지웠는데 #103 이 닫기 후보로 나왔다"; fail=1
else echo "  OK   변이③ 코멘트 이어 읽기 제거 → C4 FAIL(시험이 잡는다)"; fi
# 변이 ④ 닫힌 칸 issueCount 대조 제거 → C7b(잘림) FAIL
mutate 4 || { echo "  FAIL 변이④ 적용 실패(닻 불일치)"; fail=1; }
DM="$(fresh mut4)"
run_tool "$MUT/bin/ft-issues-daily.sh" "$DM" "$T/fix/c7b.json" >/dev/null 2>&1
if grep -Fq -- "판정 불가(잘림)" "$DM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  FAIL 변이④ — issueCount 대조를 지웠는데 잘림을 잡았다"; fail=1
else echo "  OK   변이④ issueCount 대조 제거 → C7b FAIL(시험이 잡는다)"; fi

echo "== bin·kit cmp0 · 새 파일 모드(실행 비트 0) =="
for f in ft_issues_daily.py ft-issues-daily.sh; do
  if cmp -s "$BIN/$f" "$KIT/fable-team/bin/$f"; then echo "  OK   cmp0 $f"
  else echo "  FAIL cmp0 $f — harness/bin 과 kit/fable-team/bin 이 다르다"; fail=1; fi
done
for f in "$STUB" "$HERE/test_issues_daily_paging_r1395.sh"; do
  chk "모드 644 ${f##*/}(실행 비트 0 · r1305)" "0o644" \
      "$(python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$f")"
done

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (C1~C9 · 기준판 · 변이 4) — 단계: 표 ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
