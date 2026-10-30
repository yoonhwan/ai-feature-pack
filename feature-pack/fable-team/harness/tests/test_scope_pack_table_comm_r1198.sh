#!/usr/bin/env bash
# test_scope_pack_table_comm_r1198.sh — r1198 팩 분류표: harness/comm/ = code pack-comm · 표 파일 자신 = forbid scope-table · 나머지 그대로
# 격리: load_table + path_class 를 경로 목록으로 직접 부름(실 리포·실 gh 0 · 자기 재호출 0) · 변이 = R1198_TABLE=<comm 줄 지운 사본>
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TABLE="${R1198_TABLE:-$HERE/../kit/fable-team/templates/scope-classes-pack.tsv}"
H=feature-pack/fable-team/harness
out="$(python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1])
import autonomy_scope_rules as r
t = r.load_table(sys.argv[2]); print("ROWS", len(t))
for p in sys.argv[3:]: print("%s %s %s" % ((p,) + r.path_class(t, p)))
' "$HERE/../bin" "$TABLE" \
  "$H/comm/mbox_lineage.py" "$H/comm/README.md" \
  "$H/kit/fable-team/templates/scope-classes-pack.tsv" "$H/kit/fable-team/templates/scope-ddl-record.tsv" \
  "$H/bin/ft-hil.sh" "$H/tests/x.sh" "$H/evidence/y.md" "README.md" 2>&1)"; rc=$?
fail=0
ck() { if grep -qxF -- "$2" <<<"$out"; then echo "PASS $1"; else echo "FAIL $1 :: want «$2»"; fail=$((fail+1)); fi; }
[ "$rc" = 0 ] || { echo "FAIL load_table/path_class rc=$rc :: ${out:0:300}"; fail=$((fail+1)); }
ck "ⓐ R1 comm/*.py → code pack-comm" "$H/comm/mbox_lineage.py code pack-comm"
ck "ⓐ R2 comm/README.md → code pack-comm(md 줄보다 위)" "$H/comm/README.md code pack-comm"
ck "ⓑ R3 표 자신 → forbid scope-table" "$H/kit/fable-team/templates/scope-classes-pack.tsv forbid scope-table"
ck "ⓒ R4 다른 kit 표(ddl 기록표) → code pack-kit" "$H/kit/fable-team/templates/scope-ddl-record.tsv code pack-kit"
ck "ⓓ R5 bin → code pack-bin" "$H/bin/ft-hil.sh code pack-bin"
ck "ⓓ R5 tests → code pack-tests" "$H/tests/x.sh code pack-tests"
ck "ⓓ R5 evidence → docs pack-evidence" "$H/evidence/y.md docs pack-evidence"
ck "ⓓ R5 리포 밖 README.md → forbid repo-outside" "README.md forbid repo-outside"
ck "ⓔ 표 꼴 · 줄 11개" "ROWS 11"
echo "fail=$fail"; [ "$fail" = 0 ]
