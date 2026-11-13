#!/usr/bin/env bash
# test_issues_daily_r1115.sh — ft-issues-daily.sh · ft-issues-daily-check.sh 반례 R1~R10 + 변이 2 + plist/install(cmp0)
#   방식: 임시 FT_ROOT + 가짜 gh(대역 JSON · 호출 기록) + 가짜 mbox(발신 본문 기록) + 가짜 launchctl · 실 GitHub·Slack·launchd 0 ·
#         고정 sleep 0 · 자기 재호출 0(이 파일은 자기 자신을 부르지 않는다) · ulimit -u + timeout 70.
#   변이 2 = ⓐ proposal-pending 칸 끔(→ R1 FAIL) · ⓑ gh 쓰기 호출 추가(→ R4·R5 FAIL). 둘 다 «FAIL 이어야» 통과.
#   exit 0 = 전부 통과 · 1 = 실패 1건 이상
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true          # r1041 안전선
TO_LIMIT=70
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$(cd "$HERE/../bin" && pwd)"
TOOL="$BIN/ft-issues-daily.sh"
CHECK="$BIN/ft-issues-daily-check.sh"
[ -f "$TOOL" ] || { echo "도구 없음: $TOOL" >&2; exit 1; }
[ -f "$CHECK" ] || { echo "도구 없음: $CHECK" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
chk() { if [ "$2" = "$3" ]; then echo "  OK   $1"; else echo "  FAIL $1 — 기대[$2] 실제[$3]"; fail=1; fi; }
has() { if grep -Fq -- "$1" "$2"; then echo "  OK   $3"; else echo "  FAIL $3 — 없음[$1] in ${2##*/}"; fail=1; fi; }
hasstr() { if case "$2" in *"$1"*) true;; *) false;; esac; then echo "  OK   $3"; else echo "  FAIL $3 — 없음[$1]"; fail=1; fi; }
nhas() { if grep -Fq -- "$1" "$2"; then echo "  FAIL $2 — 있으면 안 되는[$1]"; fail=1; else echo "  OK   $3"; fi; }
NOW="$(python3 -c 'import datetime;print(int(datetime.datetime(2026,11,5,0,12).timestamp()))')"
DAY=20261105
PREV=20261104

# ── 가짜 gh (호출 기록 + 대역 JSON · 쓰기 호출도 여기 남는다) ──
GH="$T/bin/gh"; mkdir -p "$T/bin"
cat > "$GH" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$*" in
  *"repo view"*) printf '{"owner":{"login":"byz"},"name":"pack"}\n';;
  *"api graphql"*)
    case "$*" in
      *"search(type:ISSUE"*) [ "${FAIL_CLOSED:-0}" = 1 ] && exit 1;;
      *) [ "${FAIL_OPEN:-0}" = 1 ] && { echo "gh: not logged in" >&2; exit 1; };;
    esac
    exec python3 "$STUB_PY" --fixture "$GQL_JSON" "$@";;
  *"--state closed"*) [ "${FAIL_CLOSED:-0}" = 1 ] && exit 1; cat "$CLOSED_JSON";;
  *) [ "${FAIL_OPEN:-0}" = 1 ] && { echo "gh: not logged in" >&2; exit 1; }; cat "$OPEN_JSON";;
esac
SH
chmod +x "$GH"
export GH_LOG="$T/gh-calls.log" OPEN_JSON="$T/open.json" CLOSED_JSON="$T/closed.json"
export GQL_JSON="$T/gql.json" STUB_PY="$HERE/_gh_graphql_stub.py"
: > "$GH_LOG"

# ── 가짜 mbox (발신 본문 파일 기록 · 실제 발신 0) ──
mkdir -p "$T/mbox"
MBOX="$T/bin/mbox-stub.sh"
cat > "$MBOX" <<SH
#!/usr/bin/env bash
n=\$(ls "$T/mbox" 2>/dev/null | grep -c '^body-')
printf '%s\n' "\$2" > "$T/mbox/to-\$((n+1)).txt"
printf '%s\n' "\$4" > "$T/mbox/body-\$((n+1)).txt"
echo "QUEUED seq=stub\$((n+1))"
SH
chmod +x "$MBOX"

# ── 임시 루트(명부·state) ──
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design/teams/issues/daily"
printf '{"_master":"byz-planner-master-claude#234"}\n' > "$ROOT/.fable-team/seats-planner.json"
printf '{"_master":"byz-issues-master-claude#49"}\n'  > "$ROOT/.fable-team/seats-issues.json"
printf '{"_master":"byz-harness-master-claude#163"}\n' > "$ROOT/.fable-team/seats-harness.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/allstop-ok.sh"; chmod +x "$T/bin/allstop-ok.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/allstop-stop.sh"; chmod +x "$T/bin/allstop-stop.sh"
printf '#!/usr/bin/env bash\necho "com.byz.ft-issues-daily = { state = waiting }"\n' > "$T/bin/launchctl-stub.sh"; chmod +x "$T/bin/launchctl-stub.sh"

# ── 픽스처: 열린 7건(R1 분모) · 닫힌 1건(24h) ──
CLOSE_COMMENT='닫는 사건: 재현 후 수리 착지
PR: #9001
재현 PASS: 3/3
정리: 임시 파일 0
기록: 카드 r9000
정본: design/harness/ISSUE-TRANSITIONS.md#3@0123456789abcdef0123456789abcdef01234567
원인 확정: Y — 락 해제 순서가 뒤집혀 있었다
같은 증상 보류: 0'
export CLOSE_COMMENT NOW
python3 - "$T/open.json" "$T/closed.json" <<'PY'
import datetime, json, os, sys
now = int(os.environ["NOW"])
err = sys.argv[1:]
def iso(off: int) -> str:
    return datetime.datetime.fromtimestamp(now + off, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
comment = os.environ["CLOSE_COMMENT"]
open_rows = [
    {"number": 101, "title": "v65 교정 항목", "labels": [{"name": "approved"}],
     "createdAt": iso(-950400), "updatedAt": iso(-691200), "body": "", "comments": []},
    {"number": 102, "title": "[이슈] 이슈팀 정리", "labels": [{"name": "approved"}, {"name": "team:issues"}],
     "createdAt": iso(-950400), "updatedAt": iso(-691200), "body": "", "comments": []},
    {"number": 103, "title": "이슈팀 정리", "labels": [{"name": "approved"}],
     "createdAt": iso(-86400), "updatedAt": iso(-3600), "body": "",
     "comments": [{"createdAt": iso(-1800), "body": comment}]},
    {"number": 3807, "title": "제안서: 야간 장치", "labels": [{"name": "status:proposal-pending"}],
     "createdAt": iso(-864000), "updatedAt": iso(-172800), "body": "", "comments": []},
    {"number": 4200, "title": "제안서: 매거진 칸", "labels": [{"name": "status:proposal-pending"}],
     "createdAt": iso(-864000), "updatedAt": iso(-172800), "body": "", "comments": []},
    {"number": 4300, "title": "needs triage 것", "labels": [{"name": "needs-triage"}],
     "createdAt": iso(-864000), "updatedAt": iso(-172800), "body": "", "comments": []},
    {"number": 4400, "title": "라벨 없이 온 것", "labels": [],
     "createdAt": iso(-3600), "updatedAt": iso(-1800), "body": "", "comments": []},
]
closed_rows = [{"number": 9000, "closedAt": iso(-3600)}, {"number": 9001, "closedAt": iso(-259200)}]
for path, rows in zip(err, (open_rows, closed_rows)):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(rows, fh, ensure_ascii=False)
PY
# r1395 쪽 읽기 대역 시나리오: 열린 목록 = 1쪽 그대로 · 닫힌(24h) = search 창(closed:>=now-24h) 안의 것만
python3 - "$T/open.json" "$T/closed.json" "$T/gql.json" "$NOW" <<'PY'
import datetime, json, sys
open_rows = json.load(open(sys.argv[1], encoding="utf-8"))
closed_rows = json.load(open(sys.argv[2], encoding="utf-8"))
now = int(sys.argv[4])
recent = [r for r in closed_rows
          if now - datetime.datetime.fromisoformat(r["closedAt"].replace("Z", "+00:00")).timestamp() < 86400]
scenario = {"repo": {"owner": "byz", "name": "pack"},
            "open": {"totalCount": len(open_rows), "pages": [open_rows]},
            "closed": {"issueCount": len(recent), "pages": [recent]}}
with open(sys.argv[3], "w", encoding="utf-8") as fh:
    json.dump(scenario, fh, ensure_ascii=False)
PY

run_tool() { # <도구> <표폴더> [env…] — timeout 70 안에서
  local tool="$1" dir="$2"; shift 2
  ( export FT_ROOT="$ROOT" FT_NOW="$NOW" FT_GH="$GH" FT_MBOX_SH="$MBOX" FT_ISSUES_DAILY_DIR="$dir" \
           FT_ISSUES_DAILY_CLASSIFY="$BIN/ft-issue-classify.sh" FT_ALLSTOP="$T/bin/allstop-ok.sh"
    for kv in "$@"; do export "${kv?}"; done
    timeout $TO_LIMIT bash "$tool" )
}

echo "== R1~R5 표 1장 (열린 7 · approved 3 · proposal-pending 2 · needs-triage 1 · 라벨 없음 1) =="
OUT1="$T/out1"; mkdir -p "$OUT1"
: > "$GH_LOG"
run_tool "$TOOL" "$OUT1" >/dev/null 2>"$T/err1"; RC1=$?
TB="$OUT1/TABLE-daily-$DAY.md"
chk "rc=0" 0 "$RC1"
chk "표 파일 1장" 1 "$(ls "$OUT1"/TABLE-daily-*.md 2>/dev/null | wc -l | tr -d ' ')"
has "3+2+1+1+0 = 7" "$TB" "① 머리 합 검산 (한 이슈 = 한 칸)"
has "- 열린 총수: 7" "$TB" "① 열린 총수 7"
has "status:proposal-pending 2" "$TB" "① proposal-pending 2"
has "| #3807 | ⓒ |" "$TB" "R1 proposal-pending #3807 이 ④ⓒ 칸에 있다(묻힘 0)"
has "| #4200 | ⓒ |" "$TB" "R1 proposal-pending #4200 이 ④ⓒ 칸에 있다"
has "7일+ 정체(갱신일 기준): 2건" "$TB" "R2 7일+ 정체 2건"
has "#101(8일)" "$TB" "R2 정체 목록에 #101(8일)"
has "중복 후보(제목 정규화 같음): 1쌍 #102 ≈ #103" "$TB" "R3 중복 후보 1쌍"
nhas "중복 확정" "$TB" "R3 판정 낱말 0(«후보» 만)"
has "| #101 | v65(후보) |" "$TB" "R4 team:* 없음 + 폼 키워드 v65 → 팀 후보"
has "#103 이슈팀 정리" "$TB" "R5 닫기 8항 코멘트 있는 #103 = 닫기 후보"
has "라벨 부여·배정·닫기·코멘트 쓰기 0" "$TB" "장치가 하지 않은 것 칸"
if grep -Eq -- '--add-label|issue (edit|close|comment|lock)' "$GH_LOG"; then
  echo "  FAIL R4/R5 gh 쓰기 호출 있음 — $(grep -E -- '--add-label|issue (edit|close|comment)' "$GH_LOG" | head -1)"; fail=1
else echo "  OK   R4/R5 gh 쓰기 호출 0 (list 2회만)"; fi
chk "R10 쪽지 2통" 2 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
if [ -f "$T/mbox/body-1.txt" ] && [ -f "$T/mbox/body-2.txt" ]; then
  if cmp -s "$T/mbox/body-1.txt" "$T/mbox/body-2.txt"; then echo "  FAIL R10 두 쪽지 본문이 같다(FANOUT 가드 위반)"; fail=1
  else echo "  OK   R10 두 쪽지 본문이 다르다(FANOUT 가드 통과)"; fi
fi
has "byz-planner-master-claude#234" "$T/mbox/to-1.txt" "쪽지1 = planner master"
has "byz-issues-master-claude#49" "$T/mbox/to-2.txt" "쪽지2 = issues master"

echo "== R9 어제 표 있음 → 차이 +1 -1 / 없음 → «차이: 첫 표» =="
printf '# 이슈 일일 표\n\n- 열린 총수: 84\n' > "$OUT1/TABLE-daily-$PREV.md"
OUT9="$T/out9"; mkdir -p "$OUT9"
cp "$OUT1/TABLE-daily-$PREV.md" "$OUT9/TABLE-daily-$PREV.md"
run_tool "$TOOL" "$OUT9" "FT_ISSUES_DAILY_NO_SEND=1" >/dev/null 2>&1
has "어제 대비: +1 −1 · 열린 총수 84→7 (-77)" "$OUT9/TABLE-daily-$DAY.md" "R9 어제 표 있음 → 차이 +새로 열린 −닫힌 · 총수 이동"
OUT9b="$T/out9b"; mkdir -p "$OUT9b"
run_tool "$TOOL" "$OUT9b" "FT_ISSUES_DAILY_NO_SEND=1" >/dev/null 2>&1
has "어제 대비: 차이: 첫 표" "$OUT9b/TABLE-daily-$DAY.md" "R9 어제 표 없음 → 첫 표"

echo "== R6 전팀 정지 표식 → «건너뜀» 표 1장 + 쪽지 1통 =="
rm -f "$T/mbox"/body-*.txt "$T/mbox"/to-*.txt
OUT6="$T/out6"; mkdir -p "$OUT6"
run_tool "$TOOL" "$OUT6" "FT_ALLSTOP=$T/bin/allstop-stop.sh" >/dev/null 2>&1; RC6=$?
chk "R6 rc=0(건너뜀은 실패 아님)" 0 "$RC6"
has "## 건너뜀 — 전팀 정지(ALL_STOP)" "$OUT6/TABLE-daily-$DAY.md" "R6 건너뜀 표 · 사유 적힘(빈 표 0)"
chk "R6 쪽지 1통" 1 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"

echo "== R7 gh 실패 → «판정 불가» 표 + rc≠0 + 쪽지 1통 =="
rm -f "$T/mbox"/body-*.txt "$T/mbox"/to-*.txt
OUT7="$T/out7"; mkdir -p "$OUT7"
run_tool "$TOOL" "$OUT7" "FAIL_OPEN=1" >/dev/null 2>"$T/err7"; RC7=$?
chk "R7 rc=5(판정 불가)" 5 "$RC7"
has "## 판정 불가" "$OUT7/TABLE-daily-$DAY.md" "R7 판정 불가 표(0건으로 숨김 0)"
chk "R7 쪽지 1통" 1 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
has "판정 불가" "$T/mbox/body-1.txt" "R7 쪽지 본문에 «판정 불가»"

echo "== R8 check: 00:40 뒤 표 없음 → 1통 · 두 번째 틱 0 · 표 있으면 0 · 00:40 전 0 =="
CHKROOT="$T/chkroot"; mkdir -p "$CHKROOT/.fable-team/state" "$CHKROOT/.fable-team/bin" "$CHKROOT/design/teams/issues/daily"
printf '{"_hil_route":"fx#0"}\n' > "$CHKROOT/.fable-team/seats-planner.json"   # r1825: 공용 잡 주인 루트 표식(없으면 launchd-new SKIP)
mkdir -p "$CHKROOT/.fable-team/state"; python3 "$HERE/../bin/ft_launchd_llm_gate.py" list-dyncalls --root-dir "$HERE/../kit/fable-team/bin" --root-key live-bin | awk -F'\t' -v OFS='\t' '{print $1,$2,$3,"fx-h1"}' > "$CHKROOT/.fable-team/state/launchd-dyncall-baseline.tsv"   # r1838: H1 뒤 기준선(실 판정기)
printf '{"_master":"byz-harness-master-claude#163"}\n' > "$CHKROOT/.fable-team/seats-harness.json"
rm -f "$T/mbox"/body-*.txt
chk_run() { # <epoch> [표있음=1]
  ( export FT_ROOT="$CHKROOT" FT_NOW="$1" FT_MBOX_SH="$MBOX" FT_LAUNCHCTL="$T/bin/launchctl-stub.sh" \
           FT_ISSUES_DAILY_DIR="$CHKROOT/design/teams/issues/daily" FT_ISSUES_DAILY_STATE="$CHKROOT/.fable-team/state/issues-daily"
    timeout $TO_LIMIT bash "$CHECK" )
}
N0040="$(python3 -c 'import datetime;print(int(datetime.datetime(2026,11,5,0,40).timestamp()))')"
N0039="$(python3 -c 'import datetime;print(int(datetime.datetime(2026,11,5,0,39).timestamp()))')"
chk_run "$N0039" >/dev/null 2>&1; chk "R8 00:39 = 아직 안 봄(경보 0)" 0 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
O8="$(chk_run "$N0040" 2>&1)"; RC8=$?
chk "R8 rc=0" 0 "$RC8"
chk "R8 표 없음 → 경보 1통" 1 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
has "[경보] 00시 이슈 표 없음 20261105" "$T/mbox/body-1.txt" "R8 경보 본문"
has "launchd" "$T/mbox/body-1.txt" "R8 경보에 launchd 상태 동봉"
chk "R8 ALARM 줄 출력" "yes" "$(case "$O8" in *"ALARM 20261105"*) echo yes;; *) echo no;; esac)"
chk_run "$N0040" >/dev/null 2>&1
chk "R8 같은 날 두 번째 틱 = 0" 1 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
printf '# 이슈 일일 표 — 2026-11-05\n\n- 열린 총수: 3\n' > "$CHKROOT/design/teams/issues/daily/TABLE-daily-20261105.md"
rm -f "$CHKROOT/.fable-team/state/issues-daily/20261105.alarm" "$T/mbox"/body-*.txt
chk_run "$N0040" >/dev/null 2>&1
chk "R8 표 있으면 0" 0 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"
printf '# 이슈 일일 표\n\n## 판정 불가\n\n- 원인: x\n' > "$CHKROOT/design/teams/issues/daily/TABLE-daily-20261105.md"
O8b="$(chk_run "$N0040" 2>&1)"
chk "R8 표가 «판정 불가» 면 경보" 1 "$(ls "$T/mbox"/body-*.txt 2>/dev/null | wc -l | tr -d ' ')"

echo "== ⓖ plist·install: 라벨 등록 경로 · 00:10 · cmp0 =="
KIT="$(cd "$HERE/../kit" && pwd)"
TPL="$KIT/launchd/com.byz.ft-issues-daily.plist.template"
[ -f "$TPL" ] && echo "  OK   kit plist 템플릿 있음" || { echo "  FAIL kit plist 템플릿 없음 $TPL"; fail=1; }
cmd_out="$(python3 "$BIN/ft_plist_env.py" bin-list "$KIT" 2>&1)"
hasstr "com.byz.ft-issues-daily" "$cmd_out" "bin-list 가 새 라벨을 나열"
python3 - "$TPL" <<'PY' && echo "  OK   plist: Label · 00:10 · RunAtLoad 0 · ProgramArguments=ft-issues-daily.sh · ProcessType Interactive" || { echo "  FAIL plist 내용"; exit 1; }
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
assert d["Label"] == "com.byz.ft-issues-daily", d["Label"]
assert d["StartCalendarInterval"] == {"Hour": 0, "Minute": 10}, d["StartCalendarInterval"]
assert d["RunAtLoad"] is False
assert d["ProgramArguments"][-1].endswith("/ft-issues-daily.sh"), d["ProgramArguments"]
assert d["ProcessType"] == "Interactive"
assert d["StandardOutPath"] == "/tmp/byz-ft-issues-daily.log"
PY
git -C "$CHKROOT" init -q 2>/dev/null || true   # render-bin 은 «git 공용 루트» 를 본다(시험 루트도 리포로)
HINST="$T/install-home"; mkdir -p "$HINST"
PLAN="$(cd "$HERE/.." && FT_LAUNCHCTL="$T/bin/launchctl-ok.sh" timeout $TO_LIMIT bash "$HERE/../install.sh" --dry-run --project "$CHKROOT" --home "$HINST" --launchd-new com.byz.ft-issues-daily 2>&1)"
hasstr "com.byz.ft-issues-daily" "$PLAN" "install.sh --launchd-new 가 그 라벨을 본다"
hasstr "PLAN launchd-new com.byz.ft-issues-daily" "$PLAN" "install.sh --launchd-new dry-run = PLAN 1줄(쓰기 0)"
BADLBL="$(cd "$HERE/.." && FT_LAUNCHCTL="$T/bin/launchctl-ok.sh" timeout $TO_LIMIT bash "$HERE/../install.sh" --dry-run --project "$CHKROOT" --home "$HINST" --launchd-new com.byz.nope 2>&1)"
hasstr "키트에 그 Label 템플릿이 없다" "$BADLBL" "install.sh --launchd-new 오타 라벨 = ERROR(조용한 통과 0)"
# apply 갈래는 «루트 shim 이 이미 있는» 상태를 전제한다(--need-exist) — shim 은 착지한 ref(HEAD)의 키트 목록으로 만들어진다.
# 그래서 HEAD 에 이 파일이 들어간 뒤(커밋 뒤)에만 apply 시험을 돌린다. 커밋 전이면 SKIP(거짓 OK 0 · 거짓 FAIL 0).
PREFIX="$(git -C "$HERE/.." rev-parse --show-prefix 2>/dev/null)"
if git -C "$HERE/.." cat-file -e "HEAD:${PREFIX}kit/fable-team/bin/ft-issues-daily.sh" 2>/dev/null; then
  APPLY="$(cd "$HERE/.." && FT_LAUNCHCTL="$T/bin/launchctl-stub.sh" timeout $TO_LIMIT bash "$HERE/../install.sh" --apply --project "$CHKROOT" --home "$HINST" --launchd-new com.byz.ft-issues-daily 2>&1)"
  hasstr "LAUNCHD new com.byz.ft-issues-daily" "$APPLY" "apply = 새 라벨 첫 등록 + launchctl print state 확인"
  if [ -f "$HINST/Library/LaunchAgents/com.byz.ft-issues-daily.plist" ]; then
    echo "  OK   apply 가 ~/Library/LaunchAgents 에 plist 를 썼다(시험 home)"
    hasstr "ft-issues-daily.sh" "$(cat "$HINST/Library/LaunchAgents/com.byz.ft-issues-daily.plist")" "적재된 plist 의 ProgramArguments = 루트 shim"
  else echo "  FAIL apply 가 plist 를 안 썼다 $HINST/Library/LaunchAgents"; fail=1; fi
else
  echo "  SKIP apply 등록 경로 — HEAD 에 키트 사본이 아직 없다(이 카드 커밋 뒤 같은 시험을 다시 돌린다: 드라이런·오타·cmp0 는 위에서 이미 봤다)"
fi
cmpok=1
for f in ft-issues-daily.sh ft_issues_daily.py ft-issues-daily-check.sh ft-stall-scan.sh; do
  cmp -s "$BIN/$f" "$KIT/fable-team/bin/$f" || { cmpok=0; echo "  FAIL cmp0 $f — harness/bin 과 kit/fable-team/bin 이 다르다"; fail=1; }
done
[ "$cmpok" = 1 ] && echo "  OK   cmp0 harness/bin ↔ kit/fable-team/bin 4파일 같은 내용(설치기가 엉뚱한 판을 안 싣는다)"

echo "== 틱 연결: ft-stall-scan.sh 가 check 를 부른다(120초 틱 · --dry-run 제외) =="
has "ft-issues-daily-check.sh" "$BIN/ft-stall-scan.sh" "ft-stall-scan.sh 에 호출 줄 1(경보 경로)"
grep -Fq -- '[ "${1:-}" = --dry-run ] || [ ! -f "$HERE/ft-issues-daily-check.sh" ]' "$BIN/ft-stall-scan.sh" \
  && echo "  OK   --dry-run 에서는 부르지 않는다(판정 시험 오염 0)" \
  || { echo "  FAIL --dry-run 가드 없음"; fail=1; }

echo "== 변이 2 =="
MUT="$T/mut"; mkdir -p "$MUT/bin"
cp "$BIN/ft_issues_daily.py" "$BIN/ft-issues-daily.sh" "$BIN/ft-issue-classify.sh" "$MUT/bin/"
# 변이 ⓐ: proposal-pending 칸을 끈다(ⓒ 축·상태 칸 둘 다) → R1 이 FAIL 이어야 한다
python3 - "$MUT/bin/ft_issues_daily.py" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace('    if LABEL_PP in labels:\n        return "pp"\n', '    if False:\n        return "pp"\n')
t = t.replace('    if LABEL_PP in labels:\n        return "ⓒ"\n', '    if False:\n        return "ⓒ"\n')
p.write_text(t)
PY
OUTM="$T/outm"; mkdir -p "$OUTM"
rm -f "$T/mbox"/body-*.txt
( export FT_ROOT="$ROOT" FT_NOW="$NOW" FT_GH="$GH" FT_MBOX_SH="$MBOX" FT_ISSUES_DAILY_DIR="$OUTM" \
         FT_ISSUES_DAILY_CLASSIFY="$MUT/bin/ft-issue-classify.sh" FT_ALLSTOP="$T/bin/allstop-ok.sh"
  timeout $TO_LIMIT bash "$MUT/bin/ft-issues-daily.sh" >/dev/null 2>&1 )
if grep -Fq "| #3807 | ⓒ |" "$OUTM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  FAIL 변이ⓐ — proposal-pending 칸을 껐는데도 ⓒ 칸에 있다(R1 시험이 약하다)"; fail=1
else echo "  OK   변이ⓐ proposal-pending 칸 끔 → R1 검사 FAIL(시험이 잡는다)"; fi
# 변이 ⓑ: gh 쓰기 호출(label)을 끼워 넣는다 → R4·R5 검사가 FAIL 이어야 한다
cp "$BIN/ft_issues_daily.py" "$MUT/bin/ft_issues_daily.py"
python3 - "$MUT/bin/ft_issues_daily.py" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace('    if dry:\n', '    subprocess.run([gh, "issue", "edit", "1", "--add-label", "team:x"], capture_output=True)\n    if dry:\n', 1)
p.write_text(t)
PY
: > "$GH_LOG"
OUTN="$T/outn"; mkdir -p "$OUTN"
( export FT_ROOT="$ROOT" FT_NOW="$NOW" FT_GH="$GH" FT_MBOX_SH="$MBOX" FT_ISSUES_DAILY_DIR="$OUTN" \
         FT_ISSUES_DAILY_CLASSIFY="$BIN/ft-issue-classify.sh" FT_ALLSTOP="$T/bin/allstop-ok.sh"
  timeout $TO_LIMIT bash "$MUT/bin/ft-issues-daily.sh" >/dev/null 2>&1 )
if grep -Eq -- '--add-label' "$GH_LOG"; then
  echo "  OK   변이ⓑ label 호출 추가 → R4·R5 쓰기 0 검사 FAIL(시험이 잡는다)"
else echo "  FAIL 변이ⓑ — 쓰기 호출을 심었는데 기록에 없다"; fail=1; fi

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (R1~R10 · 변이 2 · plist/install) — 단계: 표 ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
