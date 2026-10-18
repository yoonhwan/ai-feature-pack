#!/usr/bin/env bash
# test_proposal_card.sh — ft-proposal-card.sh 시험(설계 §7-1): 가짜 팀 env(임시 디렉터리) → 카드 생성 + lint OK ·
#   같은 slug 두 번 → rc≠0 · 잘못된 slug → rc≠0 · 팀 env 없음 → rc≠0. 임시 리포에서만 돈다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CARD="$HERE/../../harness/kit/proposal/ft-proposal-card.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$CARD" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" && git init -q . || { echo "FAIL git init"; exit 1; }
mkdir -p design/fake .fable-team/bin-fake
G1='골 첫 줄은 닫는 증거로 쓸 만큼 긴 시험용 문장이다.'
printf '%s\n' "$G1" '골 둘째 줄 시험용 문장이다.' '골 셋째 줄 시험용 문장이다.' > .fable-team/bin-fake/goal-lines.txt
# 실제 팀 원장처럼: 머리에 20자+ 인용 줄(닫는 증거로 고르면 안 된다) + 골 줄 + 그 밖의 본문
printf '# 원장\n> 확정 2026-09-15 · 발행 FB_FAKE#8 머리 인용 줄\n\n%s\n골 둘째 줄 시험용 문장이다.\n골 셋째 줄 시험용 문장이다.\n\n닫는 증거는 이 원장의 이 줄을 복붙한 것이어야 한다 — 시험.\n' "$G1" > design/fake/GOAL-fake.md
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

# --- R22: 팀 골 줄 수·닫는 증거를 골 줄에서·경로 기준 = 호출 워크트리 ---
mk() {  # mk <팀> <원장 본문(printf %b)> <골 줄들…> — 가짜 팀 env 한 벌
  local t="$1" led="$2"; shift 2
  mkdir -p "design/$t" ".fable-team/bin-$t"
  printf '%s\n' "$@" > ".fable-team/bin-$t/goal-lines.txt"
  printf '%b' "$led" > "design/$t/GOAL-$t.md"
  printf 'export FT_GOAL_LEDGER=design/%s/GOAL-%s.md\nexport FT_GOAL_LINES_FILE=%s/.fable-team/bin-%s/goal-lines.txt\nexport FT_CARD_REQUIRE_PREVERIFY=1\n' "$t" "$t" "$T" "$t" > ".fable-team/bin-$t/$t-env.sh"
}
L1='첫째 골 줄은 이 팀 정본이 요구하는 문장이다.'; L2='둘째 골 줄도 이 팀 정본이 요구하는 문장이다.'
L3='셋째 골 줄 문장이다.'; L4='넷째 골 줄은 CFO 처럼 한 줄이 더 있는 팀의 문장이다.'
LED="> 확정 2026-09-15 · 발행 FB_X#8 머리 인용 줄\n$L1\n$L2\n$L3\n$L4\n"

mk fakefour "$LED" "$L1" "$L2" "$L3" "$L4"
out="$(run fakefour four-lines --origin x --signer "$SIGNER")"; rc=$?
F4=design/fakefour/indices/대기/proposal-four-lines.md
[ $rc -eq 0 ] && echo "$out" | grep -q "^OK $F4" && ok "골 4줄 팀 → 카드 생성+lint OK" || bad "골 4줄 팀 rc=$rc"
grep -q '^## 골 원문 (항상 이 4줄)$' "$F4" && ok "제목 「항상 이 4줄」" || bad "제목이 4줄이 아니다"
for g in "$L1" "$L2" "$L3" "$L4"; do grep -qxF -- "$g" "$F4" || { bad "골 줄 누락: ${g:0:8}"; break; }; done && ok "골 4줄 전부 바이트 일치"
! grep -q 'FB_X#8' "$F4" && ok "원장 머리 인용 줄이 카드에 안 들어간다" || bad "머리 인용 줄이 카드에 들어갔다"
! grep -q 'FB_FAKE#8' "design/fake/indices/대기/proposal-ko-line-break.md" && ok "기본 픽스처도 머리 인용 줄 0" || bad "기본 픽스처 카드에 머리 인용 줄"
grep -q "「${L1}」" "$F4" && ok "닫는 증거 = 골 1줄(20자+)" || bad "닫는 증거가 골 1줄이 아니다"
grep -q '읽기: 팀 골 원장 `design/fakefour/GOAL-fakefour.md`' "$F4" && grep -q 'design/fakefour/GOAL-fakefour.md:[0-9]' "$F4" && ok "구현 범위·조사 근거에 팀 골 원장 인용" || bad "원장 인용 누락"

mk fakeshort "$LED" '짧은 첫 줄이다.' "$L2" "$L3"
out="$(run fakeshort short-first --origin x --signer "$SIGNER")"; rc=$?
[ $rc -eq 0 ] && grep -q "「${L2}」" design/fakeshort/indices/대기/proposal-short-first.md && ok "첫 골 줄 <20자 → 다음 줄에서 증거" || bad "짧은 첫 줄 rc=$rc"

W='감싸인 닫는 증거 시험용 조각 문장입니다'
mk fakewrap "${W}\n" "「${W}」" "$L2" "$L3"
out="$(run fakewrap wrapped --origin x --signer "$SIGNER")"; rc=$?
[ $rc -eq 0 ] && grep -q "닫는 증거(정본 복붙): 「${W}」" design/fakewrap/indices/대기/proposal-wrapped.md && ok "「…」 로 감싼 골 줄 → 조각에서 증거" || bad "감싼 골 줄 rc=$rc"

mk fakenoev "# 원장\n골과 무관한 줄이 여기에 길게 적혀 있다 — 증거 아님\n" "$L1" "$L2" "$L3"
out="$(run fakenoev no-evidence --origin x --signer "$SIGNER")"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q '골 원장에 없다' && [ ! -e design/fakenoev/indices/대기/proposal-no-evidence.md ] && ok "증거 조각이 원장에 없으면 rc≠0·카드 0 ($rc)" || bad "증거가 원장에 없는데 rc=$rc"

mk faketwo "$LED" "$L1" "$L2"
out="$(run faketwo two-lines --origin x --signer "$SIGNER")"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q '3줄 미만' && ok "골 2줄 → rc≠0 ($rc)" || bad "골 2줄 rc=$rc"

out="$(FT_PROPOSAL_DESIGN_REF=design/fake/NOPE.md run fake no-design --origin x --signer "$SIGNER")"; rc=$?
[ $rc -eq 0 ] && echo "$out" | grep -q '^OK design/fake/indices/대기/proposal-no-design.md' && grep -q 'git show origin/main:design/fake/NOPE.md' design/fake/indices/대기/proposal-no-design.md && ok "설계·템플릿 파일이 없는 리포에서도 lint OK" || bad "설계 파일 없음 rc=$rc"

# --- r2(판정 357): 실험·예측 시뮬 완료 조건 + 나노 범위의 evidence 폴더 쓰기 허용 ---
CARD=design/fake/indices/대기/proposal-ko-line-break.md
grep -qF '템플릿 `## 실험·예측 시뮬` 칸을 세 형식(실측 · 예측 · 「없음 — 사유」) 중 하나로 채운다.' "$CARD" && grep -qF '실측 산출물은 `design/fake/evidence/proposal-ko-line-break/`' "$CARD" && ok "완료 조건에 실험 절 줄 + 산출물 폴더" || bad "완료 조건에 실험 절 줄 없음"
grep -qF '`design/fake/evidence/proposal-ko-line-break/` 에 쓸 수 있다(그 폴더 쓰기 허용' "$CARD" && grep -q '^금지: 코드·설정 수정 0' "$CARD" && ok "나노 범위 = evidence 폴더 쓰기 허용 + 코드·설정 수정 0 유지" || bad "나노 범위 evidence 줄 없음"
awk '/^## 구현 범위/{f=1;next}/^## /{f=0}f' "$CARD" | grep -qF 'Issue 쓰기 0' && ok "Issue 쓰기 0 금지 유지" || bad "금지선이 사라졌다"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
