#!/usr/bin/env bash
# test_autonomy_scope_research_r1521.sh — r1521(#8138): design/harness/{research,inventory}/** «데이터 확장자·SHA256SUMS» 는 docs(research-data) · .py .sh .js .ts 와 중간 이름(x.py.txt)은 code · forbid 5종은 순서대로 앞
# 사례 ①~㉓(카드 동결 집합 · PR 8130·8132 실측 목록 포함) + 변이 5종(사본에서만 고침 · 각 1회) · git·네트워크·Redis 0 · 자기 재호출 0 · 고정 sleep 0
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
RD = "design/harness/research/ft-2.0/journal-cap-v2/"
INV = "design/harness/inventory/r1482-leftover-scripts-tools/"
PR8132 = """design/harness/research/ft-2.0/journal-cap-v2/DIFF-min.md
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/PLAN-ft20@328e1db99d.md
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/R1514-card.md
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/SHA256SUMS
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/hil.md
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/main-276167.txt
design/harness/research/ft-2.0/journal-cap-v2/INPUT-v2/main-276186.txt
design/harness/research/ft-2.0/journal-cap-v2/INPUT/DA-275682.txt
design/harness/research/ft-2.0/journal-cap-v2/INPUT/PLAN-ft20-single-module-and-slack-20261109@27b168d630.md
design/harness/research/ft-2.0/journal-cap-v2/INPUT/SHA256SUMS
design/harness/research/ft-2.0/journal-cap-v2/INPUT/arch-275665-review-journal-cap.txt
design/harness/research/ft-2.0/journal-cap-v2/REPORT-r1504-journal-cap-20261109.md
design/harness/research/ft-2.0/journal-cap-v2/REPORT-r1514-journal-cap-20261109.md
design/harness/research/ft-2.0/journal-cap-v2/branch_check_c4r.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c1.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c2.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c3.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c4.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c4r.py
design/harness/research/ft-2.0/journal-cap-v2/cases_c5.py
design/harness/research/ft-2.0/journal-cap-v2/checker-r1505/VERDICT-r1505-journal-cap-20261109.md
design/harness/research/ft-2.0/journal-cap-v2/checker-r1505/raw/listings.json
design/harness/research/ft-2.0/journal-cap-v2/checker-r1505/raw/recount.json
design/harness/research/ft-2.0/journal-cap-v2/checker-r1505/raw/recount.txt
design/harness/research/ft-2.0/journal-cap-v2/checker-r1505/recount.py
design/harness/research/ft-2.0/journal-cap-v2/child_append.py
design/harness/research/ft-2.0/journal-cap-v2/child_rotate.py
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/C4R.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b1.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b10.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b11.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b12.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b13.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b14.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b15.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b16.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b2.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b3.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b4.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b5.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b6.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b7.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b8.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/bodies/b9.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184258/c4r/writer.lock
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/C4R.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b1.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b10.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b11.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b12.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b13.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b14.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b15.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b16.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b2.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b3.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b4.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b5.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b6.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b7.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b8.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/bodies/b9.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence-c4r-20261109-184722/c4r/writer.lock
design/harness/research/ft-2.0/journal-cap-v2/evidence/C1/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C1/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C1/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C1/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash1/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash1/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash2/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash2/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash3/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash3/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash4/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-crash4/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-oldfd/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2-oldfd/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C2/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C3/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C3/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C3/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4R/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4R/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4R/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C4R/state.json
design/harness/research/ft-2.0/journal-cap-v2/evidence/C5/journal.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C5/listing.txt
design/harness/research/ft-2.0/journal-cap-v2/evidence/C5/ops.jsonl
design/harness/research/ft-2.0/journal-cap-v2/evidence/C5/state.json""".split()
PR8130 = """design/harness/inventory/r1482-leftover-scripts-tools/01-live-bin-list.txt
design/harness/inventory/r1482-leftover-scripts-tools/01b-live-bin-files.txt
design/harness/inventory/r1482-leftover-scripts-tools/01c-hits-claude.txt
design/harness/inventory/r1482-leftover-scripts-tools/01c-rg-err.txt
design/harness/inventory/r1482-leftover-scripts-tools/01d-hits-aifp.txt
design/harness/inventory/r1482-leftover-scripts-tools/01d-rg-err.txt
design/harness/inventory/r1482-leftover-scripts-tools/01e-hits-total.tsv
design/harness/inventory/r1482-leftover-scripts-tools/01f-zero-call.txt
design/harness/inventory/r1482-leftover-scripts-tools/01g-hits-by-dir.tsv
design/harness/inventory/r1482-leftover-scripts-tools/01h-hits-excl-self.tsv
design/harness/inventory/r1482-leftover-scripts-tools/01i-zero-excl-self.txt
design/harness/inventory/r1482-leftover-scripts-tools/01j-orphan-wider.txt
design/harness/inventory/r1482-leftover-scripts-tools/01k-orphan-callers.txt
design/harness/inventory/r1482-leftover-scripts-tools/01l-import-modules.txt
design/harness/inventory/r1482-leftover-scripts-tools/01l-import-recheck.tsv
design/harness/inventory/r1482-leftover-scripts-tools/02-launchagents-all-list.txt
design/harness/inventory/r1482-leftover-scripts-tools/02-launchctl-com.byz.txt
design/harness/inventory/r1482-leftover-scripts-tools/02-plist-byz-list.txt
design/harness/inventory/r1482-leftover-scripts-tools/02b-plist-detail.tsv
design/harness/inventory/r1482-leftover-scripts-tools/02c-plist-script-wake.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03a-state-prefix.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03b-state-subdirs.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03c-support-leftover.txt
design/harness/inventory/r1482-leftover-scripts-tools/03d-folder-callers.txt
design/harness/inventory/r1482-leftover-scripts-tools/03d-subdirs-judged.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03e-state-headclass.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03f-tmph-ref-map.tsv
design/harness/inventory/r1482-leftover-scripts-tools/03f-tmph-refs.txt
design/harness/inventory/r1482-leftover-scripts-tools/04a-hooks.tsv
design/harness/inventory/r1482-leftover-scripts-tools/04b-crontab.txt
design/harness/inventory/r1482-leftover-scripts-tools/05a-bin-teams.txt
design/harness/inventory/r1482-leftover-scripts-tools/05b-bin-stale.txt
design/harness/inventory/r1482-leftover-scripts-tools/05c-loose-plist.txt
design/harness/inventory/r1482-leftover-scripts-tools/05d-stale-cmp.tsv
design/harness/inventory/r1482-leftover-scripts-tools/05e-bin-team-counts.txt
design/harness/inventory/r1482-leftover-scripts-tools/card.md
design/harness/inventory/r1482-leftover-scripts-tools/card2.md""".split()
res = []
def ok(name, cond): res.append((name, bool(cond)))
def pc(p): return r.path_class(TB, p)
def jr(row): return r.judge_row(TB, row, lambda p: False)[:2]
def A(p, mode="100644"): return ("000000", mode, "A", [p])

ok("① research a.json A 100644 → docs research-data", jr(A(RD + "a.json")) == ("docs", "research-data"))
ok("② research INPUT/SHA256SUMS → docs research-data", jr(A(RD + "INPUT/SHA256SUMS")) == ("docs", "research-data")
   and jr(A(RD + "INPUT-v2/SHA256SUMS")) == ("docs", "research-data"))
ok("③ .jsonl·.txt·.tsv·.html·.log → docs research-data",
   all(pc(RD + "raw/a" + e) == ("docs", "research-data") for e in (".jsonl", ".txt", ".tsv", ".html", ".log")))
ok("④ cases_c1.py·.js·.ts → code(실행 확장자 유지)",
   all(jr(A(RD + n))[0] == "code" for n in ("cases_c1.py", "x/a.js", "x/a.ts")))
ok("⑤ run.sh 100644 → code(실행 비트 0 이어도 code)", jr(A(RD + "run.sh"))[0] == "code")
ok("⑥ a.py.txt(중간 이름)·a.lock·SHA256SUMS.x → docs research-data 0",
   all(pc(RD + n)[1] != "research-data" for n in ("a.py.txt", "a.sh.json", "a.lock", "SHA256SUMS.x"))
   and jr(A(RD + "a.py.txt"))[0] == "code")
ok("⑦ requirements.txt → forbid deps(새 줄보다 앞)", jr(A(RD + "requirements.txt")) == ("forbid", "deps"))
ok("⑧ package.json → forbid deps", jr(A(RD + "package.json")) == ("forbid", "deps"))
ok("⑨ CLAUDE.md → forbid global-rule", jr(A(RD + "CLAUDE.md")) == ("forbid", "global-rule"))
ok("⑩ credit-ledger.json → forbid billing", jr(A(RD + "credit-ledger.json")) == ("forbid", "billing"))
ok("⑪ credential.json → forbid key", jr(A(RD + "credential.json")) == ("forbid", "key"))
ok("⑫ a.json A 100755 → forbid mode", jr(A(RD + "a.json", "100755")) == ("forbid", "mode"))
ok("⑬ a.json M 100644→100755 → forbid mode",
   jr(("100644", "100755", "M", [RD + "a.json"])) == ("forbid", "mode")
   and jr(("000000", "120000", "A", [RD + "a.json"])) == ("forbid", "mode"))
ok("㉑ research a.json M 100755→100755 → forbid mode(같은 100755 수정도 mode)",
   jr(("100755", "100755", "M", [RD + "a.json"])) == ("forbid", "mode")
   and jr(("100755", "100755", "R100", [RD + "a.json", RD + "b/a.json"])) == ("forbid", "mode"))
ok("㉒ inventory a.txt M 100755→100755 → forbid mode",
   jr(("100755", "100755", "M", [INV + "a.txt"])) == ("forbid", "mode")
   and jr(("100755", "100755", "M", [INV + "a.tsv"])) == ("forbid", "mode"))
BILL = "design/teams/cfo/evidence/x/billing-a.png"
ok("㉓ team-billing-doc 모드 사례 회귀 0(A 100644 = docs · 나머지 = forbid mode)",
   jr(("000000", "100644", "A", [BILL])) == ("docs", "team-billing-doc")
   and all(jr(row) == ("forbid", "mode") for row in (
       ("000000", "100755", "A", [BILL]), ("100755", "100755", "M", [BILL]),
       ("100644", "100755", "M", [BILL]), ("000000", "120000", "A", [BILL])))
   and jr(("100644", "100644", "R100", [BILL, BILL.replace("x/", "x2/")])) == ("docs", "move"))
c32 = [pc(p) for p in PR8132]
ok("⑭ PR 8132 실측 100행 — .py 10 code · .lock 2 deps · 나머지 88 docs(md 8 = 기존 :21 · 80 = research-data)",
   len(PR8132) == 100
   and sum(1 for p in PR8132 if p.endswith(".py")) == 10
   and c32.count(("code", "code")) == 10
   and sum(1 for c in c32 if c == ("forbid", "deps")) == 2
   and c32.count(("docs", "research-data")) == 80
   and c32.count(("docs", "docs")) == 8)
c30 = [pc(p) for p in PR8130]
ok("⑮ PR 8130 실측 37행 전부 docs(inventory/ .txt 22·.tsv 13 = research-data · .md 2)",
   len(PR8130) == 37 and all(c[0] == "docs" for c in c30)
   and c30.count(("docs", "research-data")) == 35 and c30.count(("docs", "docs")) == 2)
ok("⑯ design/teams/x/a.json 회귀 → docs team-file", jr(A("design/teams/cfo/a.json")) == ("docs", "team-file"))
ok("⑰ inventory/x/run.sh 100644 → code", jr(A(INV + "x/run.sh"))[0] == "code")
ok("⑱ research/x/credential.md → docs(기존 :21 선행 · 낱말 무관)", pc(RD + "credential.md") == ("docs", "docs"))
ok("⑲ inventory/x/a.py.md → docs(기존 :21 · .md 는 import 경로 아님)", pc(INV + "x/a.py.md") == ("docs", "docs"))
idx = {(c, k): i for i, (c, k, _) in enumerate(TB)}
i_res = idx.get(("docs", "research-data"), -1)
last_forbid = max(i for i, (c, k, _) in enumerate(TB) if c == "forbid")
ok("⑳ 새 줄 위치 = 마지막 forbid 줄(%d) 뒤 · pytest(%d) 앞 · 기존 규칙 회귀 0" % (last_forbid, idx.get(("code", "pytest"), -1)),
   last_forbid < i_res < min(idx.get(("code", "pytest"), 0), idx.get(("docs", "team-file"), 0))
   and pc("design/teams/cfo/conftest.py") == ("code", "pytest")
   and pc("design/teams/cfo/test_a.py") == ("code", "test-file")
   and pc("design/teams/cfo/evidence/raw/a.sh") == ("docs", "team-evidence")
   and pc("gateway/domains/journey/x.py") == ("code", "code")
   and pc("docs/rules/a.md") == ("docs", "docs"))

for n, c in res: print(("PASS " if c else "FAIL ") + n)
PY

run_py() { python3 -I "$T/check.py" "$1" 2>&1; }
OUT="$(run_py "$BIN")"; echo "$OUT"
echo "$OUT" | grep -q '^FAIL' && fail=$((fail+1))
[ "$(echo "$OUT" | grep -c '^PASS')" = 23 ] || { echo "FAIL PASS 줄 수 23 아님"; fail=$((fail+1)); }
cmp -s "$BIN/autonomy_scope_rules.py" "$KIT/autonomy_scope_rules.py" && echo "PASS bin·kit cmp0" || { echo "FAIL bin·kit cmp"; fail=$((fail+1)); }

# 변이 5종 — 사본($T/mutN)에서 고친다 · 기대 FAIL 줄이 «그 칸» 에서 나야 변이 통과
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
mut m1-no-row 's = "\n".join(l for l in s.split("\n") if "\"research-data\", r" not in l)' "① "
mut m2-py-in-ext 's = s.replace("json|jsonl|txt|tsv|html|log", "json|jsonl|txt|tsv|html|log|py")' "④ "
mut m3-no-lookahead 's = s.replace("(?!(?:.*/)?[^/]*\\.(?:py|sh|js|ts)\\.[^/]*$)", "")' "⑥ "
mut m4-broad-scope 's = s.replace("^design/harness/(?:research|inventory)/", "^design/")' "⑯ "
mut m5-no-inventory 's = s.replace("^design/harness/(?:research|inventory)/", "^design/harness/research/")' "⑮ "

echo "---- fail=$fail"
[ "$fail" = 0 ]
