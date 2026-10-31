#!/usr/bin/env bash
# test_autonomy_scope_billing_team_r1248.sh — r1248(판정 2997): 팀 폴더 «그림·PDF 증거(100644)» 는 과금 낱말 금지 밖 · 그 밖은 그대로 FORBID
# 반례 R1~R11(카드 동결 집합) + 변이 4종(사본에서만 고침 · 각 1회) · git·네트워크·Redis 0 · 자기 재호출 0 · 고정 sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; KIT="$HERE/../../harness/kit/fable-team/bin"
fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

cat > "$T/check.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])   # python -I 는 PYTHONPATH 무시 — argv 로 넣는다
import autonomy_scope_rules as r
TB = r.BYZ_TABLE
P = "design/teams/cfo/"
res = []
def ok(name, cond): res.append((name, bool(cond)))
def pc(p): return r.path_class(TB, p)
def jr(row, learned=()):
    j = [r.judge_row(TB, row, lambda p: False)]
    r.apply_learned(j, set(learned))
    return j[0][:2]
def A(p): return ("000000", "100644", "A", [p])

R1 = P + "evidence/cfo-orgsub-7-7a-press/raw/04-member-no-subscription-area.png"
ok("R1 그림 증거 A 100644 → docs team-billing-doc", jr(A(R1)) == ("docs", "team-billing-doc"))
PR5535 = [P + "evidence/cfo-orgsub-7-7a-press/" + n for n in (
    "RESULT.md", "SEED-orgsub-press-20261031.md", "raw/00-g.test.1-organization-no-org.png", "raw/02-active-owner.png",
    "raw/02-cancel-reserved-owner.png", "raw/02-pending-owner.png", "raw/03-return-503.png", "raw/03-return-href-rerun.txt",
    "raw/03-return-network-rerun.txt", "raw/03-return-network.txt", "raw/03-return-rerun.png", "raw/04-member-no-subscription-area.png",
    "raw/05-turbopack-get-errors-rerun.txt", "raw/05-turbopack-get-errors.txt", "raw/06-audit-log-network.txt", "raw/06-gateway-log.txt")]
ok("R2 PR 5535 파일 목록(.json 4개 제외) 전부 billing forbid 0", all(jr(A(p))[1] != "billing" and jr(A(p))[0] != "forbid" for p in PR5535))
R3 = ["billing-run.ts", "billing.js", "billing.tsx", "billing.mjs", "billing.ipynb", "billing.yaml", "billing.command", "billing/Makefile", "billing/run",
      "credit_tool.py", "evidence/billing-run.sh", "ops/sched/PLAN-ddl-dev-apply-credit-expire-runs.sh.hil", "credit-run.sh.txt",
      "evidence/credit-run.json", "evidence/credit-run.html", "credit-notes.txt", "credit.csv"]
ok("R3 실행·설정·데이터·.hil 전부 forbid billing", all(jr(A(P + p)) == ("forbid", "billing") for p in R3))
ok("R3b 실행기 입력 .json → forbid billing", jr(A(P + "evidence/ccu-test-credit-rows-p2-supabase-20261007.json")) == ("forbid", "billing"))
R4 = ["design/teams/graphics/evidence/g1087-credits-sub2-impl/fixture_test.tsx", P + "billing/test_credential.ts", P + "billing.test.ts"]
ok("R4 팀 폴더 과금 낱말 시험 코드 → forbid billing", all(jr(A(p)) == ("forbid", "billing") for p in R4))
ok("R5 .pem·.key·credential 그림 → forbid · docs 0", all(jr(A(P + p))[0] == "forbid" for p in ("billing.pem", "billing.key", "evidence/credential-subscription.png")))
ok("R6 secrets/·.env → forbid key", all(jr(A(P + p)) == ("forbid", "key") for p in ("secrets/subscription.txt", ".env.subscription")))
bad = [("000000", "120000", "A", [R1]), ("000000", "100755", "A", [R1]), ("120000", "120000", "M", [R1]),
       ("100644", "100755", "M", [R1]), ("100755", "100755", "R100", [R1, R1.replace("/raw/", "/raw2/")])]
ok("R7 심링크·실행 비트 5꼴 → forbid mode", all(jr(b) == ("forbid", "mode") for b in bad))
ok("R7 learned={billing} 줘도 forbid mode 그대로", all(jr(b, ["billing"]) == ("forbid", "mode") for b in bad))
ok("R7 사유에 모드 값·경로", "120000" in r.judge_row(TB, bad[0], lambda p: False)[2] and R1 in r.judge_row(TB, bad[0], lambda p: False)[2])
mv = ("100644", "100644", "R100", [R1, R1.replace("/raw/", "/raw2/")])
ok("R8 R100 이동 100644 → 지금 이동 규칙(docs move)", jr(mv) == ("docs", "move"))
R9 = ["gateway/domains/credit/x.py", "clients/web/src/domains/credit/y.ts", "tests/gateway/unit/test_org_subscription_status_route.py",
      "worker/billing/z.py", "design/subscription-flow.png", "docs/architect/COST_BASE_TABLE.md"]
ok("R9 코드 경로·팀 폴더 밖·COST 표 → forbid billing", all(jr(A(p)) == ("forbid", "billing") for p in R9))
ok("R10 .sql → forbid ddl", all(jr(A(P + p))[1] == "ddl-no-record" for p in ("billing.sql", "migrations/credit.sql")))
ok("R11 과금 낱말 없는 팀 파일 → docs team-file", all(jr(A(P + p)) == ("docs", "team-file") for p in ("evidence/cfo-orgsub-7-7a-press/raw/03-return-network.txt", "evidence/cfo-orgsub-7-7a-press/raw/02-active-owner.png")))
for n, c in res: print(("PASS " if c else "FAIL ") + n)
PY

run_py() { python3 -I "$T/check.py" "$1" 2>&1; }
OUT="$(run_py "$BIN")"; echo "$OUT"
echo "$OUT" | grep -q '^FAIL' && fail=$((fail+1))
[ "$(echo "$OUT" | grep -c '^PASS')" = 14 ] || { echo "FAIL PASS 줄 수 14 아님"; fail=$((fail+1)); }
cmp -s "$BIN/autonomy_scope_rules.py" "$KIT/autonomy_scope_rules.py" && echo "PASS bin·kit cmp0" || { echo "FAIL bin·kit cmp"; fail=$((fail+1)); }

# 변이 4종 — 사본($T/mutN)에서 고친다 · 기대 FAIL 줄이 «그 칸» 에서 나야 변이 통과
mut() {  # mut <이름> <python 치환식> <기대 FAIL 앞부분>
  mkdir -p "$T/$1"; python3 -I - "$BIN/autonomy_scope_rules.py" "$T/$1/autonomy_scope_rules.py" "$2" <<'PY'
import sys
s = open(sys.argv[1], encoding="utf-8").read()
ns = {"s": s}
exec(sys.argv[3], ns)
if ns["s"] == s:
    sys.exit("mutation no-op")
open(sys.argv[2], "w", encoding="utf-8").write(ns["s"])
PY
  [ $? = 0 ] || { echo "FAIL 변이 $1 적용 실패"; fail=$((fail+1)); return; }
  local o; o="$(run_py "$T/$1")"
  echo "$o" | grep -q "^FAIL $3" && echo "PASS 변이 $1 → FAIL $3" || { echo "FAIL 변이 $1 가 «$3» 을 못 깸"; echo "$o" | grep '^FAIL'; fail=$((fail+1)); }
}
mut m1-no-row 's = "\n".join(l for l in s.split("\n") if "team-billing-doc\", r" not in l)' "R1 "
mut m2-json 's = s.replace("png|jpe?g|gif|webp|pdf", "png|json|jpe?g|gif|webp|pdf")' "R3b "
mut m3-no-mode 's = s.replace("if wrong_mode:", "if False:")' "R7 심링크"
mut m4-mode-billing 's = s.replace("return \"forbid\", \"mode\", \"모드 %s→%s: %s\" % (om, nm, wrong_mode)", "return \"forbid\", \"billing\", \"모드 %s→%s: %s\" % (om, nm, wrong_mode)")' "R7 learned"

echo "---- fail=$fail"
[ "$fail" = 0 ]
