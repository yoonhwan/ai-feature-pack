#!/usr/bin/env bash
# test_scope_pack_goal_close_class_r2265.sh — r2265 팩 분류표: feature-pack/fable-team/goal-close/ = code goal-close(ft2-all 아래 · pack-design-md 위) · 그 밖 그대로
# 격리: load_table·path_class 직접 + 분류기 CLI 를 임시 git 저장소에(실 리포·실 gh·실 슬랙 0) · 변이 = R2265_TABLE=<사본>
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; CLS="$BIN/autonomy_scope_classify.py"
TABLE="${R2265_TABLE:-$HERE/../kit/fable-team/templates/scope-classes-pack.tsv}"
F=feature-pack/fable-team; G="$F/goal-close"; H="$F/legacy/1.x/harness"
NEW="$(printf 'code\tgoal-close\t^feature-pack/fable-team/goal-close/')"
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
subseq() {  # subseq <기준 줄들> <규칙 줄들> → 기준 줄이 같은 글자·같은 순서로 모두 있으면 0(사이 다른 줄 허용)
  python3 -I -c '
import sys; it = iter(sys.argv[2].split("\n"))
sys.exit(0 if all(any(b == r for r in it) for b in sys.argv[1].split("\n")) else 1)
' "$1" "$2"
}
# 기준판(팩 origin/main 75d731527d) 규칙 24줄 — 글자·순서 동결(⑨ · 부분열)
BASE24="$(cat <<'B24'
forbid	scope-table	(?i)^feature-pack/fable-team/legacy/1\.x/harness/kit/fable-team/templates/scope-classes-[^/]*\.tsv$
code	pack-kit	^feature-pack/fable-team/legacy/1\.x/harness/kit/
code	pack-bin	^feature-pack/fable-team/legacy/1\.x/harness/bin/
code	pack-comm	^feature-pack/fable-team/legacy/1\.x/harness/comm/
code	pack-harness-pi	^feature-pack/fable-team/legacy/1\.x/harness/pi/
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
B24
)"

# ① 자리 · 새 줄(줄 수는 고정하지 않는다 · 줄 수 검사 = r1198 ⓔ)
rows="$(grep -v '^#' "$TABLE" | grep -v '^$')"
n="$(grep -nxF -- "$NEW" <<<"$rows" | cut -d: -f1)"
[ -n "$n" ] && [ "$(grep -cxF -- "$NEW" <<<"$rows")" = 1 ]; ok "① 새 줄 글자 1개" $? "n=$n"
prev="$(sed -n "$(( ${n:-1} - 1 ))p" <<<"$rows")"; next="$(sed -n "$(( ${n:-0} + 1 ))p" <<<"$rows")"
[ -n "$n" ] && [[ "$prev" == "$(printf 'code\tft2-all\t')"* ]]; ok "① 앞 줄 = ft2-all" $? "prev=$prev"
[ -n "$n" ] && [[ "$next" == "$(printf 'docs\tpack-design-md\t')"* ]]; ok "① 뒷 줄 = pack-design-md" $? "next=$next"

out="$(pc "$TABLE" "$G/phrases.tsv" "$G/MODULE.json" "$G/roles/nano.md" "$G/00-flow.md" "$G/50-new.md" "$G/roles/tester.md" \
  "$F/ft2/adapters/pi/keeper_next.py" "$F/ft2/tests/test_x_r2159.py" \
  "$F/goal-close-old/x.md" "$F/goal-closer/x.md" "$F/goal-close" \
  feature-pack/goal-close/x.md "$F/ft2/goal-close/x.md" "$F/legacy/1.x/goal-close/x.md" "x/$G/y.md" \
  "$F/Goal-Close/x.md" "$F/design/x.md" "$F/troubleshoot/x.md" \
  "$H/kit/fable-team/templates/scope-classes-pack.tsv" "$F/ft2/contracts/x.md" "$H/pi/x.ts" feature-pack/ctx-plan/bin/ctx-plan)"
for p in "$G/phrases.tsv" "$G/MODULE.json" "$G/roles/nano.md" "$G/00-flow.md"; do has "$out" "$p code goal-close"; ok "② $p → code goal-close" $? "$out"; done
for p in "$G/50-new.md" "$G/roles/tester.md"; do has "$out" "$p code goal-close"; ok "④ 새 파일 $p → code goal-close" $? "$out"; done
for p in "$F/goal-close-old/x.md" "$F/goal-closer/x.md" "$F/goal-close"; do has "$out" "$p forbid repo-outside"; ok "⑤ 이름만 닮음 $p → forbid repo-outside" $? "$out"; done
has "$out" "feature-pack/goal-close/x.md forbid repo-outside"; ok "⑥ feature-pack/goal-close → forbid repo-outside" $? "$out"
has "$out" "$F/ft2/goal-close/x.md code ft2-all"; ok "⑥ ft2/goal-close → code ft2-all" $? "$out"
has "$out" "$F/legacy/1.x/goal-close/x.md docs pack-md"; ok "⑥ legacy/1.x/goal-close → docs pack-md" $? "$out"
has "$out" "x/$G/y.md forbid repo-outside"; ok "⑥ 앞 고정 x/… → forbid repo-outside" $? "$out"
has "$out" "$F/Goal-Close/x.md forbid repo-outside"; ok "⑦ 대소문자 Goal-Close → forbid repo-outside" $? "$out"
for p in "$F/design/x.md" "$F/troubleshoot/x.md"; do has "$out" "$p forbid repo-outside"; ok "⑧ 표에 없는 $p → forbid repo-outside" $? "$out"; done
has "$out" "$H/kit/fable-team/templates/scope-classes-pack.tsv forbid scope-table"; ok "⑨ 표 자신 → forbid scope-table" $? "$out"
[ "$(tail -1 <<<"$rows")" = "$(printf 'forbid\trepo-outside\t.')" ]; ok "⑨ 마지막 규칙 줄 = forbid repo-outside ." $?
subseq "$BASE24" "$rows"; ok "⑨ 기준판 24줄 = 같은 글자·같은 순서(부분열)" $?
has "$out" "$F/ft2/contracts/x.md forbid repo-outside"; ok "⑨ ft2/contracts → forbid repo-outside" $? "$out"
has "$out" "$H/pi/x.ts code pack-harness-pi"; ok "⑨ harness/pi → code pack-harness-pi" $? "$out"
has "$out" "feature-pack/ctx-plan/bin/ctx-plan code pack-ctx"; ok "⑨ ctx-plan → code pack-ctx" $? "$out"

# 분류기 CLI(try-auto 분류 단계와 같은 분류기·표) — 임시 저장소 · ③ r2159 꼴 4파일 · ⑧ troubleshoot 만 바꾼 가지
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$W/$F/ft2/adapters/pi" "$W/$F/ft2/tests" "$W/$G" "$W/$F/troubleshoot"
printf 'A = 1\n' > "$W/$F/ft2/adapters/pi/keeper_next.py"; printf '{"v": 1}\n' > "$W/$G/MODULE.json"
printf 'k\tv1\n' > "$W/$G/phrases.tsv"; printf 'x1\n' > "$W/$F/troubleshoot/x.md"
cm "$W" base2; git -C "$W" push -q origin main
git -C "$W" checkout -q -b t3; printf 'A = 2\n' > "$W/$F/ft2/adapters/pi/keeper_next.py"
printf 'def test_x():\n    pass\n' > "$W/$F/ft2/tests/test_x_r2159.py"; printf '{"v": 2}\n' > "$W/$G/MODULE.json"
printf 'k\tv2\n' > "$W/$G/phrases.tsv"; cm "$W" t3; S3="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b t8 main; printf 'x2\n' > "$W/$F/troubleshoot/x.md"; cm "$W" t8; S8="$(sha "$W" HEAD)"
o3="$(pc "$TABLE" "$F/ft2/adapters/pi/keeper_next.py" "$F/ft2/tests/test_x_r2159.py" "$G/MODULE.json" "$G/phrases.tsv")"
has "$o3" "$F/ft2/adapters/pi/keeper_next.py code ft2-adapters" && has "$o3" "$F/ft2/tests/test_x_r2159.py code ft2-tests" \
  && has "$o3" "$G/MODULE.json code goal-close" && has "$o3" "$G/phrases.tsv code goal-close"
ok "③ path_class r2159 4파일 = ft2-adapters · ft2-tests · goal-close · goal-close" $? "$o3"
c3="$(python3 "$CLS" classify "$S3" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r3=$?
[ "$r3" = 0 ] && [[ "$c3" == "CLASS code"* ]]; ok "③ 분류기 r2159 꼴 → CLASS code rc0(FORBID 0)" $? "rc=$r3 $c3"
c8="$(python3 "$CLS" classify "$S8" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r8=$?
[ "$r8" = 3 ] && [[ "$c8" == "FORBID kind=repo-outside"* ]]; ok "⑧ 분류기 troubleshoot 만 → FORBID kind=repo-outside rc3" $? "rc=$r8 $c8"
echo "fail=$fail"; [ "$fail" = 0 ]
