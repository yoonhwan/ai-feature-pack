#!/usr/bin/env bash
# test_card_number_r1695.sh — r1695 ft-card-number.sh(카드 번호 발급 단일화) + ft-index-lint.sh ⑮ 호출
#   ⓔ 원본 세 곳(BASE 트리 카드 · 원격 가지 이름 · 발급 원장)에 각각만 있는 번호를 심음 → next = 최댓값 + 1 · 원장에 먼저 적음
#      같은 순간 두 번 호출 = 서로 다른 번호 2개 · ⓧ3 꼴(두 기준 가지에 같은 번호 · 다른 팀) → check rc1 + 다른 팀 자리 1줄 · 빈 번호 FREE rc0
#      lint: 새 카드가 다른 팀 번호 = BAD · BASE 에 이미 있는 카드 = «기존 겹침 1» WARN · 카드 자리 아님 = 출력 0
#   수정 1(규칙 ⓒ'): next 는 트리 최댓값+100 초과 가지 번호를 뺌(경계 포함) · check 는 가지 번호 전부(team=?)
#   변이(사본): M2 가지 이름 원본을 뺌 → 그 원본에만 있는 번호(r30)를 넘지 못해 ⓔ FAIL
# 임시 bare 원격 · 원장 = 임시 파일 · 실 리포·실 원장 0 · sleep 0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo "$T"; S0=$SECONDS
card() { mkdir -p "$(dirname "$W/$1")"; echo "# $1" > "$W/$1"; }
card 'design/teams/planner/indices/대기/r10-p.md'; card 'design/teams/planner/indices/완성/r40-p.md'; cm "$W" "main cards"; git -C "$W" push -q origin main
git -C "$W" checkout -q -b ops/main-base "$M0"; card 'design/harness/indices/진행/r12-h.md'; card 'design/harness/indices/진행/r40-h.md'; cm "$W" "ops cards"; git -C "$W" push -q origin ops/main-base
git -C "$W" push -q origin "$M0:refs/heads/nano/r30-only-branch"; git -C "$W" checkout -q main; git -C "$W" fetch -q origin
export FT_CARD_NUMBER_LEDGER="$T/ledger.tsv"; printf '20\tkk\tledger-only\t-\t2026-11-11T00:00:00\n' > "$FT_CARD_NUMBER_LEDGER"
cn() { out="$(bash "${CN:-$BIN/ft-card-number.sh}" "$@" --repo "$W" --no-fetch 2>&1)"; rc=$?; }
case_next() {  # next = max(트리 12·40, 가지 30, 원장 20) + 1 = 41 · 원장에 41 행
  cn next harness first-slug; [ "$rc" = 0 ] && [[ "$(tail -n1 <<<"$out")" == "ISSUED r41 team=harness slug=first-slug "* ]] && grep -q "$(printf '^41\tharness\tfirst-slug\t')" "$FT_CARD_NUMBER_LEDGER"
}
cp "$FT_CARD_NUMBER_LEDGER" "$T/ledger0"
printf '20\tkk\tledger-only\t-\t2026-11-11T00:00:00\n50\tkk\tledger-max\t-\t2026-11-11T00:00:01\n' > "$FT_CARD_NUMBER_LEDGER"; cn next harness y; [ "$rc" = 0 ] && grep -q '^ISSUED r51 ' <<<"$out"; ck "ⓔ 원장 원본에만 있는 50 → 51" $?
cp "$T/ledger0" "$FT_CARD_NUMBER_LEDGER"
git -C "$W" push -q origin "$M0:refs/heads/docs/team-r60-branch"; git -C "$W" fetch -q origin; cn next harness z; [ "$rc" = 0 ] && grep -q '^ISSUED r61 ' <<<"$out"; ck "ⓔ 가지 이름 원본에만 있는 60 → 61" $?
git -C "$W" push -q origin --delete docs/team-r60-branch; git -C "$W" fetch -q --prune origin; cp "$T/ledger0" "$FT_CARD_NUMBER_LEDGER"
case_next; ck "ⓔ 트리 원본 40 이 최댓값(가지 30·원장 20) → r41 · 원장에 먼저 적음" $?
bash "$BIN/ft-card-number.sh" next feature a --repo "$W" --no-fetch > "$T/p1" 2>&1 & bash "$BIN/ft-card-number.sh" next feature b --repo "$W" --no-fetch > "$T/p2" 2>&1 & wait
n1="$(sed -nE 's/^ISSUED r([0-9]+) .*/\1/p' "$T/p1")"; n2="$(sed -nE 's/^ISSUED r([0-9]+) .*/\1/p' "$T/p2")"
[ -n "$n1" ] && [ -n "$n2" ] && [ "$n1" != "$n2" ] && [ "$(cut -f1 "$FT_CARD_NUMBER_LEDGER" | sort | uniq -d | wc -l | tr -d ' ')" = 0 ]; ck "ⓔ 같은 순간 두 번 = 서로 다른 번호(${n1}·${n2}) · 원장 중복 0" $?
cn check r40 planner; [ "$rc" = 1 ] && grep -qx 'USED r40 team=harness src=ops:design/harness/indices/진행/r40-h.md' <<<"$out" && [ "$(grep -c '^USED ' <<<"$out")" = 1 ]; ck "ⓔ ⓧ3 꼴 check r40 planner → rc1 + harness 자리 1줄" $?
cn check r10 planner; [ "$rc" = 0 ] && grep -qx 'FREE r10 team=planner' <<<"$out"; ck "ⓔ 같은 팀만 쓰는 번호 → FREE rc0" $?
cn check r20 harness; [ "$rc" = 1 ] && grep -q '^USED r20 team=kk src=ledger:1 slug=ledger-only$' <<<"$out"; ck "ⓔ 원장 행의 다른 팀 → USED rc1" $?
cn check r999 planner; [ "$rc" = 0 ]; ck "ⓔ 빈 번호 → FREE rc0" $?
cn check r40 planner --base deadbeef -; [ "$rc" = 3 ] && grep -q '^판정 불가 트리' <<<"$out"; ck "git 실패 = rc3 판정 불가" $?

card 'design/teams/planner/indices/대기/r12-new.md'
cn lint "$W/design/teams/planner/indices/대기/r12-new.md"; [ "$rc" = 0 ] && grep -q '^BAD 카드 번호 r12 가 다른 팀과 겹침(team=harness ' <<<"$out"; ck "lint: 새 카드가 다른 팀 번호 → BAD" $?
cn lint "$W/design/teams/planner/indices/완성/r40-p.md"; [ "$rc" = 0 ] && grep -q '^WARN 기존 겹침 1: 카드 번호 r40 ' <<<"$out"; ck "lint: BASE 에 이미 있는 카드 겹침 → «기존 겹침 1» WARN" $?
echo x > "$T/r12-loose.md"; cn lint "$T/r12-loose.md"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "lint: 카드 자리 아님 → 출력 0" $?
printf '<!-- ledger: design/L.md -->\n# x\n' > "$W/design/teams/planner/indices/대기/r12-new.md"; echo l > "$W/design/L.md"
out="$(cd "$W" && bash "$KIT/ft-index-lint.sh" "design/teams/planner/indices/대기/r12-new.md" 2>&1)"; rc=$?
[ "$rc" != 0 ] && grep -q '카드 번호 r12 가 다른 팀과 겹침' <<<"$out"; ck "ft-index-lint.sh ⑮ 가 lint 를 불러 REJECT 사유에 넣음" $?

M2="$T/mut-M2.sh"; python3 - "$BIN/ft-card-number.sh" "$M2" <<'PY' || { echo "FAIL M2 변이 적용 실패"; fail=$((fail+1)); }
import sys
s=open(sys.argv[1],encoding='utf-8').read(); a="bmax = max((x for x in branch_nums(root) if x[0] <= tmax + BRANCH_GAP), default=(0, '-'))"; assert s.count(a)==1
open(sys.argv[2],'w',encoding='utf-8').write(s.replace(a,"bmax = (0, '-')"))
PY
printf '20\tkk\tledger-only\t-\t2026-11-11T00:00:00\n' > "$FT_CARD_NUMBER_LEDGER"
git -C "$W" update-ref refs/remotes/origin/main "$M0"; git -C "$W" update-ref -d refs/remotes/origin/ops/main-base   # 트리 0 · 가지 30 · 원장 20
cn next harness m0; [ "$rc" = 0 ] && grep -q '^ISSUED r31 ' <<<"$out"; ck "ⓔ 원본 가지 30 이 최댓값일 때 r31" $?
printf '20\tkk\tledger-only\t-\t2026-11-11T00:00:00\n' > "$FT_CARD_NUMBER_LEDGER"
CN="$M2" cn next harness m2; [ "$rc" = 0 ] && grep -q '^ISSUED r31 ' <<<"$out"; [ $? != 0 ]; ck "M2 변이(가지 원본 뺌) → r31 아님(r21 · ⓔ FAIL 잡힘)" $?

# 수정 1(planner#265 #285974 규칙 ⓒ'): next 만 «트리 최댓값 + 100 초과» 가지 번호를 뺀다 · check 는 가지 번호 전부 · 경계(최댓값+100) 포함
mkrepo "$T/two"; export FT_CARD_NUMBER_LEDGER="$T/ledger2.tsv"
card 'design/teams/planner/indices/완성/r1696-p.md'; cm "$W" "tree max 1696"; git -C "$W" push -q origin main
git -C "$W" push -q origin "$M0:refs/heads/docs/knowledge-r3889-live-wording-20261103"; git -C "$W" fetch -q origin
cn next planner gap-a; [ "$rc" = 0 ] && grep -q '^ISSUED r1697 .*branch:0(-)' <<<"$out"; ck "수정 ⓐ 트리 최대 r1696 + 가지 r3889 → next r1697(먼 가지 뺌)" $?
git -C "$W" push -q origin "$M0:refs/heads/docs/team-r1697-card-before-land"; git -C "$W" fetch -q origin
cn check r1697 planner; [ "$rc" = 1 ] && grep -qx 'USED r1697 team=? src=branch:docs/team-r1697-card-before-land' <<<"$out"; ck "수정 ⓑ 착지 전 docs 가지 r1697 → check r1697 rc1(가지 자리 1줄)" $?
cn check r3889 planner; [ "$rc" = 1 ] && grep -q 'src=branch:docs/knowledge-r3889-live-wording-20261103$' <<<"$out"; ck "수정 ⓑ check 는 먼 가지 번호(r3889)도 그대로 셈" $?
cn next planner gap-b; [ "$rc" = 0 ] && grep -q '^ISSUED r1698 ' <<<"$out"; ck "수정 ⓑ 그때 next r1698" $?
git -C "$W" push -q origin "$M0:refs/heads/nano/r1797-just-over"; git -C "$W" fetch -q origin
cn next planner gap-c0; [ "$rc" = 0 ] && grep -q '^ISSUED r1699 ' <<<"$out"; ck "수정 ⓒ 경계 밖(최대+101 = r1797) 가지는 next 에서 뺌 → r1699" $?
git -C "$W" push -q origin "$M0:refs/heads/nano/r1796-edge"; git -C "$W" fetch -q origin
cn next planner gap-c; [ "$rc" = 0 ] && grep -q '^ISSUED r1797 ' <<<"$out"; ck "수정 ⓒ 경계 = 최대+100(r1796) 가지는 next 에 포함 → r1797" $?
echo "secs=$((SECONDS-S0)) fail=$fail"
[ "$fail" = 0 ]
