#!/usr/bin/env bash
# test_proposal_card.sh — ft-proposal-card.sh 시험(설계 §7-1): 가짜 팀 env(임시 디렉터리) → 카드 생성 + lint OK ·
#   같은 slug 두 번 → rc≠0 · 잘못된 slug → rc≠0 · 팀 env 없음 → rc≠0. 임시 리포에서만 돈다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CARD="$HERE/../../scripts/harness-install/proposal/ft-proposal-card.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$CARD" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design/fake .fable-team/bin-fake
printf '%s\n' '골 첫 줄 시험용 문장이다.' '골 둘째 줄 시험용 문장이다.' '골 셋째 줄 시험용 문장이다.' > .fable-team/bin-fake/goal-lines.txt
printf '# 원장\n\n닫는 증거는 이 원장의 이 줄을 복붙한 것이어야 한다 — 시험.\n' > design/fake/GOAL-fake.md
echo '설계 시험용 한 줄' > design/fake/DESIGN.md
cat > .fable-team/bin-fake/fake-env.sh <<EOF
export FT_GOAL_LEDGER=design/fake/GOAL-fake.md
export FT_GOAL_LINES_FILE=$T/.fable-team/bin-fake/goal-lines.txt
export FT_CARD_REQUIRE_PREVERIFY=1
EOF
export FT_PROPOSAL_ROOT="$T" FT_PROPOSAL_DESIGN_REF="design/fake/DESIGN.md"
SIGNER='byz-fake-arch-claude#0'

run() { bash "$CARD" "$@" 2>&1; }

out="$(run fake ko-line-break --origin "줄바꿈 CSS 를 보자" --source "https://example.com/a" --signer "$SIGNER")"; rc=$?
echo "$out" | sed 's/^/    /'
[ $rc -eq 0 ] && ok "정상 생성 rc=0" || bad "정상 생성 rc=$rc"
F=design/fake/indices/대기/proposal-ko-line-break.md
[ -f "$F" ] && ok "카드 파일 생성" || bad "카드 파일 없음"
echo "$out" | grep -q "^OK $F" && ok "lint OK 줄" || bad "lint OK 줄 없음"
grep -q '줄바꿈 CSS 를 보자' "$F" && grep -q 'https://example.com/a' "$F" && ok "원문·자료 링크 기재" || bad "원문·자료 링크 누락"
grep -q '^- 면제: .* — arch 서명 byz-fake-arch-claude#0' "$F" && ok "사전검증 면제 줄(arch 서명)" || bad "사전검증 면제 줄 없음"

out="$(run fake ko-line-break --origin x --signer "$SIGNER")"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q '이미 있다' && ok "같은 slug 두 번 → rc≠0 ($rc)" || bad "같은 slug 두 번 rc=$rc"

for s in 'AB_c' 'ab' 'has space' "$(printf 'a%.0s' $(seq 1 41))"; do
  out="$(run fake "$s" --origin x --signer "$SIGNER")"; rc=$?
  [ $rc -ne 0 ] && echo "$out" | grep -q 'slug 형식 오류' && ok "잘못된 slug 「${s:0:12}」 → rc≠0" || bad "잘못된 slug 「${s:0:12}」 rc=$rc"
done

out="$(run nope some-slug --origin x --signer "$SIGNER")"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q '팀 env 없음' && ok "팀 env 없음 → rc≠0 ($rc)" || bad "팀 env 없음 rc=$rc"
[ ! -e design/nope ] && ok "env 없는 팀 폴더 생성 0" || bad "env 없는 팀 폴더가 생겼다"

out="$(run fake no-origin --signer "$SIGNER")"; rc=$?
[ $rc -eq 2 ] && ok "--origin 없음 → usage rc=2" || bad "--origin 없음 rc=$rc"

out="$(run fake bad-signer --origin x --signer 'byz-fake-nano-claude#0')"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q 'REJECT' && ok "arch 아닌 서명 → lint REJECT rc≠0 ($rc)" || bad "arch 아닌 서명 rc=$rc"
[ -f design/fake/indices/대기/proposal-bad-signer.md ] && ok "lint 실패 카드는 지우지 않는다" || bad "lint 실패 카드가 사라졌다"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
