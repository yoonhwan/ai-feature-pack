#!/usr/bin/env bash
# test_issues_daily_timeout_r1395.sh — r1395 C10: 쪽 호출 상한이 «기본 25초» 인지 가른다 (하드 룰 12 로컬 하네스 · 판정 4114)
#   DA⑥ 조건부 APPROVE(#265027 · master #265067) 가 요구한 칸: 기본값이 7초로 되돌아가면 이 시험이 FAIL 한다.
#     · env 없음 + 1쪽 8초 지연 → rc0 (8초 < 기본 25초 · 표 정상)
#     · 같은 지연에 FT_ISSUES_DAILY_TIMEOUT_S=7 → 판정 불가 rc5 (7초 초과)
#     · 변이 «기본 상한 25 → 7 되돌림» → 위 첫 칸이 판정 불가가 되어 FAIL
#   ★이 파일만 «진짜 sleep» 을 쓴다★ — 상한 판정은 시간이 흐르지 않으면 관측이 불가능하다(고정 sleep 0 원칙의 명시 예외).
#     앞 시험(test_issues_daily_paging_r1395.sh)과 나눈 이유 = 하드 룰 22 «시험 1개 단독 70초» 여유(합치면 47초 · 부하 시 96초).
#   실 GitHub 0 · 네트워크 0 · 자기 재호출 0 · ulimit -u + timeout 70.
#   exit 0 = 전부 통과 · 1 = 실패 1건 이상
set -uo pipefail
NPROC=$(ulimit -u 2>/dev/null || echo 3000)
ulimit -u $((NPROC + 64)) 2>/dev/null || true
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
mkdir -p "$T/bin" "$T/fix"

# ── 가짜 gh (대역) ──
GH="$T/bin/gh"; GH_LOG="$T/gh-calls.log"; export GH_LOG
{ echo '#!/usr/bin/env bash'; echo 'exec python3 "'"$STUB"'" --fixture "${FIX:?}" "$@"'; } > "$GH"
chmod +x "$GH"; : > "$GH_LOG"

# ── 임시 루트(명부·state·표 폴더) ──
ROOT="$T/root"; mkdir -p "$ROOT/.fable-team/state" "$ROOT/design/teams/issues/daily"
printf '{"_master":"byz-planner-master-claude#234"}\n' > "$ROOT/.fable-team/seats-planner.json"
printf '{"_master":"byz-issues-master-claude#49"}\n'  > "$ROOT/.fable-team/seats-issues.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/allstop-ok.sh"; chmod +x "$T/bin/allstop-ok.sh"
printf '#!/usr/bin/env bash\necho "QUEUED seq=stub"\n' > "$T/bin/mbox-stub.sh"; chmod +x "$T/bin/mbox-stub.sh"

# ── 시나리오: 열린 3건 1쪽 · 그 쪽이 «진짜로» 8초 걸린다(7 < 8 < 25 를 가르는 최소 지연) ──
python3 - "$T/fix/slow.json" "$NOW" <<'PY'
import datetime, json, sys
out, now = sys.argv[1], int(sys.argv[2])
def iso(off):
    return datetime.datetime.fromtimestamp(now + off, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
rows = [{"number": 100 + i, "title": f"issue {100 + i}", "labels": [],
         "createdAt": iso(-950400), "updatedAt": iso(-691200), "body": "", "comments": []}
        for i in range(3)]
payload = {"repo": {"owner": "byz", "name": "pack"},
           "open": {"totalCount": 3, "pages": [rows]},
           "closed": {"issueCount": 0, "pages": [[]]},
           "slow": {"open:1": 8}}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False)
PY

run_tool() { # <도구> <표폴더> [env…]
  local tool="$1" dir="$2"; shift 2
  ( export FT_ROOT="$ROOT" FT_NOW="$NOW" FT_GH="$GH" FT_MBOX_SH="$T/bin/mbox-stub.sh" \
           FT_ISSUES_DAILY_DIR="$dir" FT_ISSUES_DAILY_CLASSIFY="$BIN/ft-issue-classify.sh" \
           FT_ALLSTOP="$T/bin/allstop-ok.sh" FT_ISSUES_DAILY_REPO="byz/pack" \
           FT_ISSUES_DAILY_NO_SEND=1 FIX="$T/fix/slow.json"
    for kv in "$@"; do export "${kv?}"; done
    timeout $TO_LIMIT bash "$tool" )
}
fresh() { local d="$T/out-$1"; rm -rf "$d"; mkdir -p "$d"; printf '%s' "$d"; }

echo "== C10a env 없음 + 1쪽 8초 지연 → rc0 (기본 상한 = 25초 · 7초였으면 죽었을 시간) =="
DA="$(fresh a)"
run_tool "$TOOL" "$DA" >/dev/null 2>"$T/errA"; RCA=$?
TBA="$DA/TABLE-daily-$DAY.md"
chk "C10a rc=0" 0 "$RCA"
has "- 열린 총수: 3" "$TBA" "C10a 표 정상(지연이 기본 상한 안)"
nhas "## 판정 불가" "$TBA" "C10a 판정 불가 0"
if grep -Eq '^PAGE .* (8|9|1[0-9])\.[0-9]s' "$T/errA"; then
  echo "  OK   C10a 쪽 시간이 7초를 넘었다(그래도 통과 = 기본 상한 25초)"
else
  echo "  FAIL C10a 쪽 시간 줄이 7초 초과가 아니다 — $(grep '^PAGE' "$T/errA" | head -2 | tr '\n' ' ')"; fail=1
fi

echo "== C10b 같은 8초 지연에 FT_ISSUES_DAILY_TIMEOUT_S=7 → 판정 불가 rc5 =="
DB="$(fresh b)"
run_tool "$TOOL" "$DB" "FT_ISSUES_DAILY_TIMEOUT_S=7" >/dev/null 2>"$T/errB"; RCB=$?
TBB="$DB/TABLE-daily-$DAY.md"
chk "C10b rc=5" 5 "$RCB"
has "## 판정 불가" "$TBB" "C10b 상한을 넘으면 판정 불가(빈 표 0)"
has "7초 초과" "$TBB" "C10b 원인에 «7초 초과»"
nhas "- 열린 총수:" "$TBB" "C10b 잘린 표 0"

echo "== 변이: 기본 상한 25 → 7 되돌림 → C10a 가 FAIL 이어야 한다 =="
MUT="$T/mut"; mkdir -p "$MUT/bin"
cp "$BIN/ft_issues_daily.py" "$BIN/ft-issues-daily.sh" "$MUT/bin/"
python3 - "$MUT/bin/ft_issues_daily.py" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
PAIRS = [('FT_ISSUES_DAILY_TIMEOUT_S") or 25))', 'FT_ISSUES_DAILY_TIMEOUT_S") or 7))'),
         ('    except ValueError:\n        return 25', '    except ValueError:\n        return 7')]
for old, new in PAIRS:
    if t.count(old) != 1:
        print(f"MUTFAIL 기본 상한 — 닻 {t.count(old)}개")
        raise SystemExit(2)
    t = t.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(t)
PY
if [ $? -ne 0 ]; then echo "  FAIL 변이 적용 실패(닻 불일치)"; fail=1; fi
DM="$(fresh m)"
run_tool "$MUT/bin/ft-issues-daily.sh" "$DM" >/dev/null 2>&1
if grep -Fq -- "## 판정 불가" "$DM/TABLE-daily-$DAY.md" 2>/dev/null; then
  echo "  OK   변이(기본 상한 7) → C10a FAIL(시험이 잡는다)"
else echo "  FAIL 변이 — 상한을 7로 되돌렸는데 8초 지연 표가 정상으로 나왔다"; fail=1; fi

echo "== 파일 모드(실행 비트 0 · r1305) =="
chk "모드 644 ${BASH_SOURCE[0]##*/}" "0o644" \
    "$(python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "${BASH_SOURCE[0]}")"

echo
if [ "$fail" = 0 ]; then echo "ALL PASS (C10a·C10b · 변이 기본상한) — 단계: 표 ${SECONDS}s"; exit 0; fi
echo "FAIL 있음 — 위 FAIL 줄"; exit 1
