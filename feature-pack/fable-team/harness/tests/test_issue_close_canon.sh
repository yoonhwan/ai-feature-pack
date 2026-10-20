#!/usr/bin/env bash
# test_issue_close_canon.sh — ft-issue-close-check.sh 6항 「정본」 시험 (판정 440 설계 r2 · 444)
# 임시 git 리포 + --from-json 픽스처만 쓴다 — 실제 gh 호출·Issue 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
FX="$HERE/../fixtures/issue_close"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$BIN/ft-issue-close-check.sh" && ok "bash -n" || bad "bash -n"

# ── 임시 리포: main 흉내 ──
R="$T/repo"; mkdir -p "$R/design/harness" "$R/.fable-team"; cd "$R" || exit 2   # r516: .fable-team = ⑧ close-reason-check 가 --repo 없이 cwd 리포를 공용 루트로 푼다(ft_repo_root)
git init -q -b main; git config user.email t@t; git config user.name t
X=design/harness/ISSUE-TRANSITIONS.md
echo base > a.txt; echo v0 > "$X"; git add -A; git commit -qm base; B="$(git rev-parse HEAD)"
git checkout -qb card
echo card > "$X"; git commit -qam "card: X only on card branch"; S_CARD="$(git rev-parse HEAD)"
git checkout -q main
echo v1 > "$X"; echo c1 > b.txt; git add -A; git commit -qm "squash land with X"; S_X1="$(git rev-parse HEAD)"
echo code > c.txt; git add -A; git commit -qm "squash land code only"; S_CODE="$(git rev-parse HEAD)"
echo v2 > "$X"; git commit -qam "second partial with X"; S_X2="$(git rev-parse HEAD)"
echo later > d.txt; git add -A; git commit -qm "later commit (X untouched)"; S_LATER="$(git rev-parse HEAD)"
# ff 랜딩: 카드 두 commit(코드 → X)이 그대로 main 에 올라옴
git checkout -qb ff-card; echo ffc > e.txt; git add -A; git commit -qm "ff c1 code"; FF1="$(git rev-parse HEAD)"
echo v3 > "$X"; git commit -qam "ff c2 X"; FF2="$(git rev-parse HEAD)"
git checkout -q main; git merge -q --ff-only ff-card
export FT_LAND_REF=main

run() { # run <fixture> -> $T/out · rc
  OUT="$(bash "$BIN/ft-issue-close-check.sh" 9000 --from-json "$1" --repo "$R" 2>"$T/err")"; RC=$?
}
sub() { sed -e "s/__S1__/$1/g" -e "s/__S2__/${2:-x}/g" -e "s/__REASON__/${3:-x}/g" "$FX/$4" > "$T/fx.json"; }

# ① 정본 X 가 랜딩 S 에 있음 → PASS
sub "$S_X1" "" "" closed-with-6items-canon.json; run "$T/fx.json"
[ $RC -eq 0 ] && grep -q "PASS #9000" <<<"$OUT" && ok "① 정본 X 가 랜딩 S 에 있음 → PASS" || bad "① rc=$RC $OUT"

# ② 카드 브랜치엔 X 수정, 랜딩 S 엔 코드만 → MISS(나)
sub "$S_CODE" "" "" closed-with-6items-canon.json; run "$T/fx.json"
[ $RC -eq 1 ] && grep -q "랜딩 commit 에 정본 .* 없음" <<<"$OUT" && ok "② 랜딩 S 에 정본 X 없음 → MISS(나)" || bad "② rc=$RC $OUT"

# ③ S 가 main 조상 아님 → MISS(가)
sub "$S_CARD" "" "" closed-with-6items-canon.json; run "$T/fx.json"
[ $RC -eq 1 ] && grep -q "랜딩 안 됨" <<<"$OUT" && ok "③ S 가 main 조상 아님 → MISS(가)" || bad "③ rc=$RC $OUT"

# ④ 정상 squash S 가 main 조상 — 뒤에 다른 commit 이 쌓여도 거짓 MISS 0
sub "$S_X1" "" "" closed-with-6items-canon.json; run "$T/fx.json"
git merge-base --is-ancestor "$S_X1" "$S_LATER" && [ $RC -eq 0 ] && ok "④ 뒤 commit 이 쌓여도 거짓 MISS 0" || bad "④ rc=$RC $OUT"
# ④b ff 랜딩 T..S 꼴
sed "s/__S1__/$S_LATER..$FF2/" "$FX/closed-with-6items-canon.json" > "$T/fx.json"; run "$T/fx.json"
[ $RC -eq 0 ] && ok "④b ff 범위 T..S 에 X 있음 → PASS" || bad "④b rc=$RC $OUT"
sed "s/__S1__/$S_LATER..$FF1/" "$FX/closed-with-6items-canon.json" > "$T/fx.json"; run "$T/fx.json"
[ $RC -eq 1 ] && ok "④c ff 범위에 X 없음 → MISS" || bad "④c rc=$RC $OUT"

# ⑤ @S1,S2 각각 통과 · 하나라도 X 없으면 MISS
sub "$S_X1" "$S_X2" "" closed-partial-two-sha.json; run "$T/fx.json"
[ $RC -eq 0 ] && ok "⑤ @S1,S2 둘 다 X → PASS" || bad "⑤ rc=$RC $OUT"
sub "$S_X1" "$S_CODE" "" closed-partial-two-sha.json; run "$T/fx.json"
[ $RC -eq 1 ] && grep -q "$S_CODE" <<<"$OUT" || true
[ $RC -eq 1 ] && ok "⑤b S2 에 X 없음 → MISS" || bad "⑤b rc=$RC $OUT"

# ⑥ 영향 없음 이유 9자 MISS · 10자 PASS
sub "" "" "가나다라마바사아자" closed-with-6items-no-impact.json; run "$T/fx.json"
[ $RC -eq 1 ] && ok "⑥ 이유 9자 → MISS" || bad "⑥ 9자 rc=$RC $OUT"
sub "" "" "가나다라마바사아자차" closed-with-6items-no-impact.json; run "$T/fx.json"
[ $RC -eq 0 ] && ok "⑥ 이유 10자 → PASS" || bad "⑥ 10자 rc=$RC $OUT"

# ⑦ 6항 없는 기존 5항 픽스처 = FAIL
run "$FX/closed-with-5items.json"
[ $RC -eq 1 ] && grep -q "MISS 6항 정본" <<<"$OUT" && ok "⑦ 5항만 → FAIL(6항 MISS)" || bad "⑦ rc=$RC $OUT"

# ⑧ ft-close-reason-check 사유=완성 경로가 새 출력·rc 를 그대로 전달
mk_reason() { jq '.comments += [{"body":"close-사유: 완성"}]' "$1" > "$2"; }
sub "" "" "가나다라마바사아자차" closed-with-6items-no-impact.json; mk_reason "$T/fx.json" "$T/r-ok.json"
bash "$BIN/ft-close-reason-check.sh" 9000 --from-json "$T/r-ok.json" >"$T/o1" 2>&1; r1=$?
mk_reason "$FX/closed-with-5items.json" "$T/r-no.json"
bash "$BIN/ft-close-reason-check.sh" 9000 --from-json "$T/r-no.json" >"$T/o2" 2>&1; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 1 ] && grep -q "MISS 6항 정본" "$T/o2" && ok "⑧ 사유=완성 rc 전달(0/1)" || bad "⑧ r1=$r1 r2=$r2 $(cat "$T/o1" "$T/o2")"

# S 가 로컬에 없으면 fetch 안내 MISS
sub "0123456789abcdef0123456789abcdef01234567" "" "" closed-with-6items-canon.json; run "$T/fx.json"
[ $RC -eq 1 ] && grep -q "S 없음 — git fetch 후 다시" <<<"$OUT" && ok "S 로컬 없음 → fetch 안내 MISS" || bad "S없음 rc=$RC $OUT"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
