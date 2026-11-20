#!/usr/bin/env bash
# test_scope_tests_sql_fixture_r2345.sh — r2345: 리포 맨 위 tests/ 아래 «새 일반 파일»(A · 000000→100644) 시험 fixture SQL 은
#   code kind=test-sql-fixture · 마이그레이션 자리(migrations·alembic·supabase)·심링크·수정·삭제·가려진 forbid 줄은 지금 판정 그대로.
# 반례 ①~⑳(카드 동결 집합) + 변이 M1~M7(사본에서만 · 변이마다 원본 대조 1회) · 임시 origin(bare)+clone · 실 원격·Redis·고정 sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLS="$BIN/autonomy_scope_classify.py"; KIT="$HERE/../../harness/kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

printf 'docs\tdocs\t^design/\n' > "$T/pack-no-ddl.tsv"   # ⑳ 팩 표(--table · ddl 줄 없음)

cat > "$T/check.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])   # python -I 는 PYTHONPATH 무시 — argv 로 넣는다
import autonomy_scope_rules as r
TB = r.BYZ_TABLE
res = []
def ok(name, cond): res.append((name, bool(cond)))
def jr(row, table=None, ddl=None): return r.judge_row(table or TB, row, ddl or (lambda p: False))[:2]
def A(p, mode="100644"): return ("000000", mode, "A", [p])

ok("① tests/gateway/sql/x.sql A 100644 → code test-sql-fixture", jr(A("tests/gateway/sql/x.sql")) == ("code", "test-sql-fixture"))
ok("② tests/fixtures/x.sql A → code test-sql-fixture", jr(A("tests/fixtures/x.sql")) == ("code", "test-sql-fixture"))
ok("③ supabase/migrations/x.sql A → forbid ddl-no-record(그대로)", jr(A("supabase/migrations/x.sql")) == ("forbid", "ddl-no-record"))
ok("④ tests/migrations/x.sql A → forbid ddl-no-record(마디 migrations)", jr(A("tests/migrations/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑤ tests/supabase/x.sql A → forbid ddl-no-record(마디 supabase)", jr(A("tests/supabase/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑥ tests/Alembic/x.sql A → forbid ddl-no-record(대소문자 무시)", jr(A("tests/Alembic/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑦ tests/gateway/sql/x.sql 심링크(000000→120000) → forbid mode(그대로)", jr(A("tests/gateway/sql/x.sql", "120000")) == ("forbid", "mode"))
ok("⑧ tests/gateway/sql/x.sql M 수정 → forbid ddl(그대로 · 범위 밖)", jr(("100644", "100644", "M", ["tests/gateway/sql/x.sql"])) == ("forbid", "ddl"))
ok("⑨ tests/gateway/sql/x.sql D → forbid delete(글자 고정)", jr(("100644", "000000", "D", ["tests/gateway/sql/x.sql"])) == ("forbid", "delete"))
ok("⑩ gateway/tests/x.sql A(맨 위 아님) → forbid ddl-no-record", jr(A("gateway/tests/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑪ design/rag/sql/x.sql A + record-only 줄 → docs ddl-record-only(r2104 그대로)",
   jr(A("design/rag/sql/x.sql"), ddl=lambda p: "ddl-record-only") == ("docs", "ddl-record-only"))
ok("⑭ tests/x.sql.sh 이중 확장자 → code code(지금 그대로)", jr(A("tests/x.sql.sh")) == ("code", "code"))
ok("⑮ tests/secrets/seed.sql A → forbid ddl-no-record(가려진 key)", jr(A("tests/secrets/seed.sql")) == ("forbid", "ddl-no-record"))
ok("⑯ tests/fixtures/credential_seed.sql A → forbid ddl-no-record(가려진 key)", jr(A("tests/fixtures/credential_seed.sql")) == ("forbid", "ddl-no-record"))
ok("⑰ tests/billing/credit_seed.sql A → forbid ddl-no-record(가려진 billing)", jr(A("tests/billing/credit_seed.sql")) == ("forbid", "ddl-no-record"))
ok("⑰ tests/.claude/x.sql A → forbid ddl-no-record(가려진 global-rule)", jr(A("tests/.claude/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑰ tests/harness/kit/x.sql A → forbid ddl-no-record(가려진 global-rule)", jr(A("tests/harness/kit/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑰ tests/cloudbuild.sql A → forbid ddl-no-record(가려진 deploy)", jr(A("tests/cloudbuild.sql")) == ("forbid", "ddl-no-record"))
ok("⑱ Tests/x.sql A(첫 마디 대소문자 다름) → forbid ddl-no-record 그대로", jr(A("Tests/x.sql")) == ("forbid", "ddl-no-record"))
ok("⑲ tests/x.SQL A(확장자 대문자) → forbid ddl 그대로", jr(A("tests/x.SQL")) == ("forbid", "ddl"))
pack = r.load_table(sys.argv[2])
ok("⑳ 팩 표(ddl 줄 없음) tests/x.sql A → forbid repo-outside 그대로", jr(A("tests/x.sql"), table=pack) == ("forbid", "repo-outside"))

for n, c in res: print(("PASS " if c else "FAIL ") + n)
PY

run_py() { python3 -I "$T/check.py" "$1" "$T/pack-no-ddl.tsv" 2>&1; }
python3 -I -m py_compile "$BIN/autonomy_scope_rules.py" "$CLS"; ck "py_compile rules·classify" $?
OUT="$(run_py "$BIN")"; echo "$OUT"
echo "$OUT" | grep -q '^FAIL' && fail=$((fail+1))
grep -qx 'PASS ① tests/gateway/sql/x.sql A 100644 → code test-sql-fixture' <<<"$OUT"; ck "① 새 파일 tests/sql → 시험 코드" $?
[ "$(grep -c '^PASS' <<<"$OUT")" = 21 ]; ck "①~⑳ PASS 줄 수 21" $?
cmp -s "$BIN/autonomy_scope_rules.py" "$KIT/autonomy_scope_rules.py"; ck "bin·kit 사본 cmp0" $?

# ── ⑬ classify 통째 · ⑫ 분류 code + critical destroy — 임시 origin(bare)+clone
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
mkdir -p "$W/design"; echo d > "$W/design/x.md"; cm "$W" base2; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
BASE="$(sha "$W" HEAD)"
mk() { local br="$1" from="$2"; shift 2; git -C "$W" checkout -q -B "$br" "$from"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
cls() { out="$(python3 "$CLS" classify "$1" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }

mk c1 "$BASE" 'mkdir -p tests/gateway/sql; printf "create table if not exists t (a int);\n" > tests/gateway/sql/x.sql; echo "print(1)" > tests/test_x.py'
cls "$SHA"; FIX_RC="$rc"; FIX_OUT="$out"
want "⑬ fixture sql + tests/test_x.py 커밋 → CLASS code" 0 "CLASS code"
S_FIX="$SHA"
mk c0 "$BASE" 'mkdir -p gateway; echo "print(1)" > gateway/y.py'
cls "$SHA"; [ "$rc" = "$FIX_RC" ]; ck "⑬ 그 행 rc = 지금 code 행 rc($FIX_RC)" $?
[ -n "$FIX_OUT" ]; ck "⑬ fixture 커밋 출력 있음" $?
mk c2 "$BASE" 'mkdir -p tests/gateway/sql; printf "create table if not exists t (a int);\nDROP TABLE t;\n" > tests/gateway/sql/x.sql'
cls "$SHA"; want "⑫ fixture sql + DROP TABLE → 분류 code(그대로)" 0 "CLASS code"
out="$(python3 "$CLS" classify "$SHA" --repo "$W" --critical 2>&1)"; rc=$?
want "⑫ 그 커밋 --critical → CRITICAL kind=destroy(크리티컬 그대로)" 3 "CRITICAL kind=destroy"

# 변이 M1~M7 — 사본에서만 고친다 · 기대 FAIL 줄이 «그 칸» 에서 나야 변이 통과 · 변이마다 원본으로 같은 사례 1회
cat > "$T/mutate.py" <<'PY'
import sys
src, dst, snip = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src, encoding="utf-8").read()
ns = {"s": s, "re": __import__("re")}
exec(open(snip, encoding="utf-8").read(), ns)
if ns["s"] == s:
    sys.exit("mutation no-op")
open(dst, "w", encoding="utf-8").write(ns["s"])
PY
mut() {  # mut <이름> <기대 FAIL 앞부분…> — 고칠 조각은 $T/<이름>/mut.py(s 호출 전 mk_mut 으로 써 둔다)
  local name="$1"; shift
  local -a want=("$@"); local bad=0 p o o2
  python3 -I "$T/mutate.py" "$BIN/autonomy_scope_rules.py" "$T/$name/autonomy_scope_rules.py" "$T/$name/mut.py" \
    || { echo "FAIL 변이 $name 적용 실패"; fail=$((fail+1)); return; }
  o="$(run_py "$T/$name")"
  for p in "${want[@]}"; do grep -q -- "^FAIL $p" <<<"$o" || { echo "FAIL 변이 $name 가 «${p}» 을 못 깸"; bad=1; }; done
  o2="$(run_py "$BIN")"
  for p in "${want[@]}"; do grep -q -- "^PASS $p" <<<"$o2" || { echo "FAIL 변이 $name 원본 대조 «${p}»"; bad=1; }; done
  if [ "$bad" = 0 ]; then echo "PASS 변이 $name → FAIL ${want[*]}"; else echo "$o" | grep '^FAIL'; fail=$((fail+1)); fi
}
mk_mut() { mkdir -p "$T/$1"; cat > "$T/$1/mut.py"; }
BLK_RE='\n    # r2345.*?return "code", "test-sql-fixture", None\n'

mk_mut m1-no-exception <<'MM'
s = re.sub(r'\n    # r2345.*?return "code", "test-sql-fixture", None\n', "\n", s, count=1, flags=re.S)
MM
mut m1-no-exception "① " "② "

mk_mut m2-any-tests-dir <<'MM'
s = s.replace('len(seg) > 1 and seg[0] == "tests"', 'len(seg) > 1 and "tests" in seg')
MM
mut m2-any-tests-dir "⑩ "

mk_mut m3-no-dir-filter <<'MM'
s = s.replace(' and not any(x.lower() in ("migrations", "alembic", "supabase") for x in seg)', "")
MM
mut m3-no-dir-filter "④ "

mk_mut m4-case-sensitive <<'MM'
s = s.replace("x.lower() in", "x in")
MM
mut m4-case-sensitive "⑥ "

mk_mut m5-no-state-a <<'MM'
s = s.replace('(st, om) == ("A", "000000") and ', '')
MM
mut m5-no-state-a "⑧ "

mk_mut m6-before-mode-check <<'MM'
m = re.search(r'\n    # r2345.*?return "code", "test-sql-fixture", None\n', s, re.S)
blk = m.group(0)[1:].replace('nm == "100644" and bool(bad)', 'bool(bad)')   # E1 새 모드 조건 지움
s = s.replace(m.group(0), "\n")
s = s.replace("    if not new_test_sh and ", blk + "    if not new_test_sh and ", 1)
MM
mut m6-before-mode-check "⑦ "

mk_mut m7-first-hit-only <<'MM'
s = s.replace('\n                        and not any(c == "forbid" and k != "ddl" and rx.search(paths[0]) for c, k, rx in table)', "")
MM
mut m7-first-hit-only "⑮ "

echo "---- fail=$fail"
[ "$fail" = 0 ]
