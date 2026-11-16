#!/usr/bin/env bash
# test_scope_pack_harness_pi_class_r2099.sh — r2099 팩 분류표: legacy/1.x/harness/pi/ = code pack-harness-pi(pack-comm 아래 · pack-install 위) · 그 밖 그대로
# 격리: load_table·path_class 직접 + 분류기 CLI 를 임시 git 저장소에(실 리포·실 gh·실 슬랙 0) · 변이 = R2099_TABLE=<사본>
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; CLS="$BIN/autonomy_scope_classify.py"
TABLE="${R2099_TABLE:-$HERE/../kit/fable-team/templates/scope-classes-pack.tsv}"
H=feature-pack/fable-team/legacy/1.x/harness
NEW="$(printf 'code\tpack-harness-pi\t^feature-pack/fable-team/legacy/1\\.x/harness/pi/')"
. "$HERE/_merge_fixture.sh"
fail=0
ok() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: ${3:-}"; fail=$((fail+1)); fi; }
pc() {  # pc <표> <경로…> → «경로 종류 키» 줄들
  python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import autonomy_scope_rules as r
t = r.load_table(sys.argv[2])
for p in sys.argv[3:]: print("%s %s %s" % ((p,) + r.path_class(t, p)))
' "$BIN" "$@" 2>&1
}
has() { grep -qxF -- "$2" <<<"$1"; }
# 기준판(팩 origin/main 7a2349b818 · fa8c3427) 규칙 23줄 — 글자·순서 동결(⑩)
BASE23="$(cat <<'B23'
forbid	scope-table	(?i)^feature-pack/fable-team/legacy/1\.x/harness/kit/fable-team/templates/scope-classes-[^/]*\.tsv$
code	pack-kit	^feature-pack/fable-team/legacy/1\.x/harness/kit/
code	pack-bin	^feature-pack/fable-team/legacy/1\.x/harness/bin/
code	pack-comm	^feature-pack/fable-team/legacy/1\.x/harness/comm/
code	pack-install	^feature-pack/fable-team/legacy/1\.x/harness/install\.sh$
code	pack-tests	^feature-pack/fable-team/legacy/1\.x/harness/tests/
docs	pack-changes	^feature-pack/fable-team/legacy/1\.x/CHANGES\.md$
docs	pack-manifest	^feature-pack/fable-team/legacy/1\.x/manifest\.json$
docs	pack-evidence	^feature-pack/fable-team/legacy/1\.x/harness/evidence/
docs	pack-md	^feature-pack/fable-team/legacy/1\.x/.*\.md$
code	ft2-core	^feature-pack/fable-team/ft2/core/
code	ft2-adapters	^feature-pack/fable-team/ft2/adapters/
code	ft2-tests	^feature-pack/fable-team/ft2/tests/
code	ft2-tools	^feature-pack/fable-team/ft2/tools/
docs	ft2-md	^feature-pack/fable-team/ft2/README\.md$
forbid	repo-outside	^feature-pack/fable-team/ft2/contracts/
code	ft2-all	^feature-pack/fable-team/ft2/
docs	pack-design-md	^design/[^/]+/.*\.md$
code	pack-skill	^feature-pack/fable-team/legacy/1\.x/skill/
code	code-intel	^feature-pack/code-intel/
code	pack-tmm	^feature-pack/tmm/
code	pack-ctx	^feature-pack/ctx-(plan|burn)/
forbid	repo-outside	.
B23
)"

# ① 자리 · 줄 수
rows="$(grep -v '^#' "$TABLE" | grep -v '^$')"
[ "$(wc -l <<<"$rows" | tr -d ' ')" = 24 ]; ok "① 규칙 줄 = 24" $? "$(wc -l <<<"$rows")"
n="$(grep -nxF -- "$NEW" <<<"$rows" | cut -d: -f1)"
[ -n "$n" ] && [ "$(grep -cxF -- "$NEW" <<<"$rows")" = 1 ]; ok "① 새 줄 글자 1개" $? "n=$n"
prev="$(sed -n "$(( ${n:-1} - 1 ))p" <<<"$rows")"; next="$(sed -n "$(( ${n:-0} + 1 ))p" <<<"$rows")"
[ -n "$n" ] && [[ "$prev" == "$(printf 'code\tpack-comm\t')"* ]]; ok "① 앞 줄 = pack-comm" $? "prev=$prev"
[ -n "$n" ] && [[ "$next" == "$(printf 'code\tpack-install\t')"* ]]; ok "① 뒷 줄 = pack-install" $? "next=$next"

out="$(pc "$TABLE" "$H/pi/ft-live-write-guard.ts" "$H/pi/ft-mbox-wake.ts" "$H/pi/ft-tool-result-cap.ts" "$H/pi/README.md" \
  "$H/pi-other/x.ts" "$H/pix/x.ts" "$H/pi" feature-pack/fable-team/legacy/1ax/harness/pi/x.ts \
  feature-pack/fable-team/legacy/1.x/pi/x.ts feature-pack/fable-team/pi/x.ts feature-pack/pi/x.ts \
  "$H/fixtures/x.json" "$H/state/x.json" "$H/plans/x.txt" "$H/kit/fable-team/templates/scope-classes-pack.tsv" \
  "$H/bin/ft-hil.sh" "$H/comm/mbox_lineage.py" "$H/tests/x.sh" "$H/evidence/y.md" feature-pack/ctx-plan/bin/ctx-plan)"
for p in "$H/pi/ft-live-write-guard.ts" "$H/pi/ft-mbox-wake.ts"; do has "$out" "$p code pack-harness-pi"; ok "② $p → code pack-harness-pi" $? "$out"; done
has "$out" "$H/pi/ft-tool-result-cap.ts code pack-harness-pi"; ok "③ pi/ft-tool-result-cap.ts → code pack-harness-pi" $? "$out"
has "$out" "$H/pi/README.md code pack-harness-pi"; ok "④ pi/README.md → code pack-harness-pi(pack-md 아님)" $? "$out"
for p in "$H/pi-other/x.ts" "$H/pix/x.ts" "$H/pi"; do has "$out" "$p forbid repo-outside"; ok "⑤ 이름만 닮음 $p → forbid repo-outside" $? "$out"; done
has "$out" "feature-pack/fable-team/legacy/1ax/harness/pi/x.ts forbid repo-outside"; ok "⑥ 점 자리 1ax → forbid repo-outside" $? "$out"
for p in feature-pack/fable-team/legacy/1.x/pi/x.ts feature-pack/fable-team/pi/x.ts feature-pack/pi/x.ts; do has "$out" "$p forbid repo-outside"; ok "⑦ 다른 자리 $p → forbid repo-outside" $? "$out"; done
for p in "$H/fixtures/x.json" "$H/state/x.json" "$H/plans/x.txt"; do has "$out" "$p forbid repo-outside"; ok "⑧ 표에 없는 $p → forbid repo-outside" $? "$out"; done
has "$out" "$H/kit/fable-team/templates/scope-classes-pack.tsv forbid scope-table"; ok "⑨ 표 자신 → forbid scope-table" $? "$out"
[ "$(tail -1 <<<"$rows")" = "$(printf 'forbid\trepo-outside\t.')" ]; ok "⑨ 마지막 규칙 줄 = forbid repo-outside ." $?
[ "$(grep -vxF -- "$NEW" <<<"$rows")" = "$BASE23" ]; ok "⑩ 새 줄 뺀 23줄 = 기준판 글자·순서" $?
has "$out" "$H/bin/ft-hil.sh code pack-bin"; ok "⑩ bin → code pack-bin" $? "$out"
has "$out" "$H/comm/mbox_lineage.py code pack-comm"; ok "⑩ comm → code pack-comm" $? "$out"
has "$out" "$H/tests/x.sh code pack-tests"; ok "⑩ tests → code pack-tests" $? "$out"
has "$out" "$H/evidence/y.md docs pack-evidence"; ok "⑩ evidence → docs pack-evidence" $? "$out"
has "$out" "feature-pack/ctx-plan/bin/ctx-plan code pack-ctx"; ok "⑩ ctx-plan → code pack-ctx" $? "$out"

# 분류기 CLI(try-auto 분류 단계와 같은 분류기·표) — 임시 저장소 · ③ r2083 꼴(새 파일 A 2개) · ⑧ fixtures 만 바꾼 가지
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$W/$H/pi" "$W/$H/tests" "$W/$H/fixtures"
printf 'export default 1;\n' > "$W/$H/pi/ft-mbox-wake.ts"; printf '{"v": 1}\n' > "$W/$H/fixtures/x.json"
cm "$W" base2; git -C "$W" push -q origin main
git -C "$W" checkout -q -b t3; printf 'export default 2;\n' > "$W/$H/pi/ft-tool-result-cap.ts"
printf '#!/usr/bin/env bash\necho ok\n' > "$W/$H/tests/test_pi_tool_result_cap_r2083.sh"; cm "$W" t3; S3="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b t8 main; printf '{"v": 2}\n' > "$W/$H/fixtures/x.json"; cm "$W" t8; S8="$(sha "$W" HEAD)"
o3="$(pc "$TABLE" "$H/pi/ft-tool-result-cap.ts" "$H/tests/test_pi_tool_result_cap_r2083.sh")"
has "$o3" "$H/pi/ft-tool-result-cap.ts code pack-harness-pi" && has "$o3" "$H/tests/test_pi_tool_result_cap_r2083.sh code pack-tests"
ok "③ path_class r2083 2파일 = pack-harness-pi · pack-tests" $? "$o3"
c3="$(python3 "$CLS" classify "$S3" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r3=$?
[ "$r3" = 0 ] && [[ "$c3" == "CLASS code"* ]]; ok "③ 분류기 r2083 꼴 → CLASS code rc0(FORBID 0)" $? "rc=$r3 $c3"
c8="$(python3 "$CLS" classify "$S8" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r8=$?
[ "$r8" = 3 ] && [[ "$c8" == "FORBID kind=repo-outside"* ]]; ok "⑧ 분류기 fixtures 만 → FORBID kind=repo-outside rc3" $? "rc=$r8 $c8"
echo "fail=$fail"; [ "$fail" = 0 ]
