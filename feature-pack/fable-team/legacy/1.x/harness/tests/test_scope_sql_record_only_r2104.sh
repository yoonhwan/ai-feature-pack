#!/usr/bin/env bash
# test_scope_sql_record_only_r2104.sh — r2104: design/ 아래 실행 0 SQL 기록 파일 = planner 원장(<remote>/<target> 끝 tree)의
#   «전체 경로 + record-only + 판정 번호» 1줄이 있으면 CLASS docs(kind ddl-record-only) · 머지가 곧 실행인 경로는 그대로 FORBID
# 임시 origin(bare)+clone · 키트 기록표 · 임시 원장 · 실 리포 fetch 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLS="$BIN/autonomy_scope_classify.py"; KBIN="$HERE/../kit/fable-team/bin"
KT="$HERE/../kit/fable-team/templates"; REC="$KT/scope-ddl-record.tsv"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
L=design/teams/planner/PLAN-oppa-ledger.md

# origin/main: 원장(사례마다 다른 SQL 경로) + 고칠 대상 sql 1개 → main 은 한 칸 더(가지 = main 조상 아님 = docs)
mkdir -p "$W/design/teams/planner" "$W/design/rag/sql" "$W/bin"
cat > "$W/$L" <<'EOF'
# planner 원장(시험용)
- design/rag/sql/a.sql record-only 판정 12
- record-only: 12 design/rag/sql/o.sql
- supabase/migrations/001.sql record-only 판정 12
- design/x/migrations/002.sql record-only 판정 12
- alembic/versions/003.sql record-only 판정 12
- scripts/004.sql record-only 판정 12
- design/a/x.sql record-only 판정 12
- design/rag/sql/b.sql.backup.sql record-only 판정 12
- archive/design/rag/sql/c.sql record-only 판정 12
- `design/rag/sql/d.sql` record-only 판정 12
- design/x/MIGRATIONS/a.sql record-only 판정 12
- design/y/Alembic/a.sql record-only 판정 12
- design/rag/sql/m.sql record-only 판정 12
EOF
echo "select 1;" > "$W/design/rag/sql/m.sql"; echo d > "$W/design/x.md"
cm "$W" base2; BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin
mk() { local br="$1"; shift; git -C "$W" checkout -q -B "$br" "$BASE"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }
sq() { mkdir -p "$(dirname "$1")"; echo "delete from t where x is null;" > "$1"; }   # sq <경로> — 사람이 h 로 돌릴 SQL 글
cls() { out="$(python3 "$CLS" classify "$SHA" --repo "$W" --scope S1 "$@" 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }   # want <이름> <rc> <출력 머리>

python3 -I -m py_compile "$CLS" "$BIN/autonomy_scope_rules.py"; ck "py_compile 2종" $?

# ① 기록만 통과(A1)
mk a1 'sq design/rag/sql/a.sql'; cls --ddl-records "$REC"; want "① 원장 record-only 줄 + 새 design sql → CLASS docs" 0 "CLASS docs"
mk a2 'sq design/rag/sql/a.sql; echo n > design/n.md'; cls --ddl-records "$REC"; want "① 같은 PR + 문서 1 → CLASS docs" 0 "CLASS docs"
mk a3 'sq design/rag/sql/o.sql'; cls --ddl-records "$REC"; want "① 원장 줄 순서 다름(record-only: 12 <경로>) → FORBID" 3 "FORBID kind=ddl-no-record"

# ② 닫힌 쪽(A2)
mk b1 'sq supabase/migrations/001.sql'; cls --ddl-records "$REC"; want "② supabase/migrations + 줄 → FORBID ddl-no-record" 3 "FORBID kind=ddl-no-record"
mk b2 'sq design/x/migrations/002.sql'; cls --ddl-records "$REC"; want "② design/x/migrations + 줄 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b3 'sq alembic/versions/003.sql'; cls --ddl-records "$REC"; want "② alembic/versions + 줄 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b4 'sq scripts/004.sql'; cls --ddl-records "$REC"; want "② scripts/ + 줄 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b5 'sq design/rag/sql/p.sql; echo "- design/rag/sql/p.sql record-only 판정 12" > design/notes.md'; cls --ddl-records "$REC"; want "② 줄이 PR 추가 줄에만 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b6 'sq design/rag/sql/q.sql; echo "- design/rag/sql/q.sql record-only 판정 12" >> '"$L"; cls --ddl-records "$REC"; want "② 줄이 PR tree 원장에만(origin/main 원장 없음) → FORBID" 3 "FORBID kind=ddl-no-record"
mk b7 'sq design/b/x.sql'; cls --ddl-records "$REC"; want "② 원장 design/a/x.sql · PR design/b/x.sql(이름만 같음) → FORBID" 3 "FORBID kind=ddl-no-record"
mk b8 'sq design/rag/sql/b.sql'; cls --ddl-records "$REC"; want "② 원장 <경로>.backup.sql 줄만 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b9 'sq design/rag/sql/c.sql'; cls --ddl-records "$REC"; want "② 원장 archive/<경로> 줄만 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b10 'sq design/rag/sql/d.sql'; cls --ddl-records "$REC"; want "② 원장 줄 경로가 백틱 안 → CLASS docs" 0 "CLASS docs"
mk b11 'sq design/x/MIGRATIONS/a.sql'; cls --ddl-records "$REC"; want "② design/x/MIGRATIONS(대소문자) + 줄 → FORBID" 3 "FORBID kind=ddl-no-record"
mk b12 'sq design/y/Alembic/a.sql'; cls --ddl-records "$REC"; want "② design/y/Alembic(대소문자) + 줄 → FORBID" 3 "FORBID kind=ddl-no-record"
printf 'record-only\tdesign/teams/planner/NONE.md\t(?:^|[\\s`]){path}`?\\s+record-only:?\\s*(판정\\s*)?[0-9]+\n' > "$T/none.tsv"
mk b13 'sq design/rag/sql/a.sql'; cls --ddl-records "$T/none.tsv"; want "② origin/main 에 기록 파일 없음 → FORBID" 3 "FORBID kind=ddl-no-record"
mkdir -p "$T/fake"; REALGIT="$(command -v git)"
printf '#!/bin/bash\nfor a in "$@"; do case "$a" in refs/remotes/*:%s) exit 9;; esac; done\nexec "%s" "$@"\n' "$L" "$REALGIT" > "$T/fake/git"; chmod +x "$T/fake/git"
out="$(PATH="$T/fake:$PATH" python3 "$CLS" classify "$SHA" --repo "$W" --scope S1 --ddl-records "$REC" 2>&1)"; rc=$?
[ "$rc" != 0 ] && ! grep -q "^CLASS" <<<"$out"; ck "② 가짜 git 이 원장 읽기에 rc 9 → rc≠0 · CLASS 줄 0" $?

# ③ PR 구성(A3)
mk c1 'sq design/rag/sql/a.sql; echo "print(1)" > bin/x.py'; cls --ddl-records "$REC"; want "③ 기록만 sql + 코드 1 → FORBID kind=ddl 문서 밖 변경" 3 "FORBID kind=ddl DDL 기록 PR 에 문서 밖 변경"

# ④ 기록표 꼴(A4)
printf 'other\t%s\t{path}\n' "$L" > "$T/bad3.tsv"; printf 'record-only\t%s\t{path}\tx\n' "$L" > "$T/bad4.tsv"
printf -- '-\t{sql}.*applied:?\\s*[0-9]+\n' > "$T/two.tsv"
mk e1 'sq design/rag/sql/a.sql'
cls --ddl-records "$T/bad3.tsv"; want "④ 3칸 첫 칸 other → ERROR rc1" 1 "ERROR"
cls --ddl-records "$T/bad4.tsv"; want "④ 4칸 → ERROR rc1" 1 "ERROR"
cls --ddl-records "$T/two.tsv"; want "④ record-only 줄 없는 기록표 + ① 입력 → FORBID" 3 "FORBID kind=ddl-no-record"
cls; want "④ --ddl-records 없음 + ① 입력 → FORBID" 3 "FORBID kind=ddl-no-record"

# ⑤ 불변(A5)
mk g1 'sq db/migrations/007_z.sql; echo "- 007_z.sql applied: 판정 5" > design/ddl-log.md'; cls --ddl-records "$REC"; want "⑤ 새 sql + 같은 PR applied 줄 → CLASS docs" 0 "CLASS docs"
mk g2 'echo "-- more" >> design/rag/sql/m.sql'; cls --ddl-records "$REC"; want "⑤ 기존 sql 수정(M) + record-only 줄 → FORBID kind=ddl(기준판과 같음)" 3 "FORBID kind=ddl DDL"
cmp -s "$BIN/autonomy_scope_rules.py" "$KBIN/autonomy_scope_rules.py" && cmp -s "$CLS" "$KBIN/autonomy_scope_classify.py"; ck "⑤ bin 과 kit 사본 cmp 0" $?

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED $fail"
exit "$fail"
