#!/usr/bin/env bash
# test_scope_pack_ctx_class_r2018.sh — r2018 팩 분류표: feature-pack/ctx-(plan|burn)/ = code pack-ctx(마지막 forbid repo-outside 줄보다 위) · 그 밖 그대로
# 격리: load_table·path_class 직접 + 분류기 CLI 를 임시 git 저장소에(실 리포·실 gh·실 슬랙 0) · 변이 = R2018_TABLE=<사본>
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; CLS="$BIN/autonomy_scope_classify.py"
TABLE="${R2018_TABLE:-$HERE/../kit/fable-team/templates/scope-classes-pack.tsv}"
H=feature-pack/fable-team/legacy/1.x/harness
B1=feature-pack/ctx-burn/bin/ctx-burn; B2=feature-pack/ctx-burn/manifest.json
P1=feature-pack/ctx-plan/bin/ctx-plan; P2=feature-pack/ctx-plan/manifest.json; P3=feature-pack/ctx-plan/test/acceptance.sh
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
out="$(pc "$TABLE" "$B1" "$B2" "$P1" "$P2" "$P3" feature-pack/ctx-other/x.sh feature-pack/ctxplan/x "$H/kit/fable-team/templates/scope-classes-pack.tsv")"
for p in "$B1" "$B2" "$P1" "$P2" "$P3"; do has "$out" "$p code pack-ctx"; ok "T1 $p → code pack-ctx" $? "$out"; done
has "$out" "feature-pack/ctx-other/x.sh forbid repo-outside"; ok "T2 분류표 밖 feature-pack/ctx-other/ → forbid repo-outside" $? "$out"
has "$out" "feature-pack/ctxplan/x forbid repo-outside"; ok "T2 이름만 닮은 feature-pack/ctxplan/ → forbid repo-outside" $? "$out"
has "$out" "$H/kit/fable-team/templates/scope-classes-pack.tsv forbid scope-table"; ok "T3 표 자신 → forbid scope-table 그대로" $? "$out"
rows="$(grep -v '^#' "$TABLE" | grep -v '^$')"
[ "$(tail -1 <<<"$rows")" = "$(printf 'forbid\trepo-outside\t.')" ]; ok "T3 마지막 줄 = forbid repo-outside ." $?
[ "$(tail -3 <<<"$rows" | head -2)" = "$(printf 'code\tpack-tmm\t^feature-pack/tmm/\ncode\tpack-ctx\t^feature-pack/ctx-(plan|burn)/')" ]; ok "자리 = pack-tmm 바로 아래 · 마지막 forbid 바로 위" $?

# 분류기 CLI(try-auto 분류 단계와 같은 분류기·표) — 임시 저장소: 기준에 r1618 PR 5파일(같은 모드) → 가지에서 내용만 수정(PR raw = 모두 M)
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$W/feature-pack/ctx-burn/bin" "$W/feature-pack/ctx-plan/bin" "$W/feature-pack/ctx-plan/test" "$W/feature-pack/ctx-other"
for p in "$B1" "$P1" "$P3" feature-pack/ctx-other/x.sh; do printf '#!/bin/sh\necho a\n' > "$W/$p"; done
for p in "$B2" "$P2"; do printf '{"v": 1}\n' > "$W/$p"; done
chmod +x "$W/$B1" "$W/$P1"; cm "$W" base2; git -C "$W" push -q origin main
git -C "$W" checkout -q -b t1; for p in "$B1" "$B2" "$P1" "$P2" "$P3"; do echo '#b' >> "$W/$p"; done; cm "$W" t1; S1="$(sha "$W" HEAD)"
git -C "$W" checkout -q -b t2 main; echo 'echo y' >> "$W/feature-pack/ctx-other/x.sh"; cm "$W" t2; S2="$(sha "$W" HEAD)"
c1="$(python3 "$CLS" classify "$S1" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r1=$?
[ "$r1" = 0 ] && [[ "$c1" == "CLASS code"* ]]; ok "T1 분류기 r1618 5파일 → CLASS code rc0(FORBID 0)" $? "rc=$r1 $c1"
c2="$(python3 "$CLS" classify "$S2" --repo "$W" --scope S1 --table "$TABLE" 2>&1)"; r2=$?
[ "$r2" = 3 ] && [[ "$c2" == "FORBID kind=repo-outside"* ]]; ok "T2 분류기 분류표 밖 → FORBID kind=repo-outside rc3" $? "rc=$r2 $c2"
echo "fail=$fail"; [ "$fail" = 0 ]
