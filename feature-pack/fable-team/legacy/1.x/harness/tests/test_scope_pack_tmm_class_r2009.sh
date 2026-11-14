#!/usr/bin/env bash
# test_scope_pack_tmm_class_r2009.sh — r2009 팩 분류표: feature-pack/tmm/ = code pack-tmm(마지막 forbid repo-outside 줄보다 위) · 그 밖 그대로
# 격리: load_table·path_class 직접 + 분류기 CLI 를 임시 git 저장소에(실 리포·실 gh·실 슬랙 0) · 변이 = R2009_TABLE=<사본>
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; CLS="$BIN/autonomy_scope_classify.py"
TABLE="${R2009_TABLE:-$HERE/../kit/fable-team/templates/scope-classes-pack.tsv}"
H=feature-pack/fable-team/legacy/1.x/harness
TMM1=feature-pack/tmm/core/bin/tmm; TMM2=feature-pack/tmm/test/verify.sh
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
out="$(pc "$TABLE" "$TMM1" "$TMM2" feature-pack/other/x.sh feature-pack/tmmx/a.sh "$H/kit/fable-team/templates/scope-classes-pack.tsv")"
has "$out" "$TMM1 code pack-tmm"; ok "T1 $TMM1 → code pack-tmm" $? "$out"
has "$out" "$TMM2 code pack-tmm"; ok "T1 $TMM2 → code pack-tmm" $? "$out"
has "$out" "feature-pack/other/x.sh forbid repo-outside"; ok "T2 분류표 밖 feature-pack/other/x.sh → forbid repo-outside" $? "$out"
has "$out" "feature-pack/tmmx/a.sh forbid repo-outside"; ok "T2 이름만 닮은 feature-pack/tmmx/ → forbid repo-outside" $? "$out"
has "$out" "$H/kit/fable-team/templates/scope-classes-pack.tsv forbid scope-table"; ok "T3 표 자신 → forbid scope-table 그대로" $? "$out"
rows="$(grep -v '^#' "$TABLE" | grep -v '^$')"
[ "$(tail -1 <<<"$rows")" = "$(printf 'forbid\trepo-outside\t.')" ]; ok "T3 마지막 줄 = forbid repo-outside ." $?
[ "$(tail -3 <<<"$rows" | head -2)" = "$(printf 'code\tcode-intel\t^feature-pack/code-intel/\ncode\tpack-tmm\t^feature-pack/tmm/')" ]; ok "자리 = code-intel 바로 아래 · 마지막 forbid 바로 위" $?

# 분류기 CLI(try-auto 분류 단계와 같은 분류기·표) — 임시 저장소: 기준에 tmm 파일(실행 비트) → 가지에서 내용만 수정
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$W/feature-pack/tmm/core/bin" "$W/feature-pack/tmm/test" "$W/feature-pack/other"
printf '#!/bin/sh\necho a\n' > "$W/$TMM1"; printf '#!/bin/sh\necho v\n' > "$W/$TMM2"; printf '#!/bin/sh\n' > "$W/feature-pack/other/x.sh"
chmod +x "$W/$TMM1" "$W/$TMM2" "$W/feature-pack/other/x.sh"; cm "$W" base2; git -C "$W" push -q origin main
git -C "$W" checkout -q -b t1; echo 'echo b' >> "$W/$TMM1"; echo 'echo w' >> "$W/$TMM2"; cm "$W" t1; S1="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b t2 main; echo 'echo y' >> "$W/feature-pack/other/x.sh"; cm "$W" t2; S2="$(sha "$W" HEAD)"
c1="$(python3 "$CLS" classify "$S1" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r1=$?
[ "$r1" = 0 ] && [[ "$c1" == "CLASS code"* ]]; ok "T1 분류기 tmm 2파일 → CLASS code rc0(FORBID 0)" $? "rc=$r1 $c1"
c2="$(python3 "$CLS" classify "$S2" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r2=$?
[ "$r2" = 3 ] && [[ "$c2" == "FORBID kind=repo-outside"* ]]; ok "T2 분류기 분류표 밖 → FORBID kind=repo-outside rc3" $? "rc=$r2 $c2"
echo "fail=$fail"; [ "$fail" = 0 ]
