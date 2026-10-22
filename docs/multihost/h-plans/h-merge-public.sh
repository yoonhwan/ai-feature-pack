#!/usr/bin/env bash
# h-merge-public.sh — 멀티호스트 공개용 문서 가지를 main 에 병합한다(PR 생성 → 병합). 비대화형 · 멱등.
# 오빠 승인 필요(main 반영). 병합 대상은 «공개용» 가지(주소·계정 자리표시자, 커밋 1개)뿐이다.
# ★로컬 계획 가지 docs/multihost-plan-20261021 은 히스토리에 원문 IP 가 있어 병합·push 금지★
# rc: 0 병합 완료(또는 이미 병합됨) · 2 사전점검 실패 · 3 PR 생성 실패 · 4 병합 실패
set -uo pipefail
REPO=yoonhwan/ai-feature-pack
HEAD_BR=docs/multihost-public-20261022
say() { printf '[h-merge] %s\n' "$*"; }
die() { printf '[h-merge] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
command -v gh >/dev/null 2>&1 || die 2 "gh 가 없다"
gh auth status >/dev/null 2>&1 || die 2 "gh 로그인이 안 되어 있다"
gh api "repos/$REPO/branches/$HEAD_BR" --jq .name >/dev/null 2>&1 || die 2 "원격에 $HEAD_BR 가 없다"

STATE="$(gh pr list --repo "$REPO" --head "$HEAD_BR" --state all --json number,state --jq '.[0] | "\(.number) \(.state)"' 2>/dev/null || true)"
case "$STATE" in
  *MERGED*) say "이미 병합됨: PR $STATE"; exit 0 ;;
  *OPEN*)   PR="${STATE%% *}"; say "열린 PR #$PR 사용" ;;
  *)        say "1/2 PR 생성"
            gh pr create --repo "$REPO" --base main --head "$HEAD_BR" \
              --title "[docs] 멀티 호스트(tmm·tmuxc·fable-team) 기획·실측 — 설계 r8 DA 승인 + 실측 + 운영 UX (공개용)" \
              --body "멀티호스트 기획 정본 문서(docs/multihost/ 만). 주소·계정·도메인은 자리표시자. 구현은 하네스 카드 r673~r678." >/dev/null 2>&1 \
              || die 3 "PR 생성 실패"
            PR="$(gh pr list --repo "$REPO" --head "$HEAD_BR" --state open --json number --jq '.[0].number')" ;;
esac
[ -n "${PR:-}" ] || die 3 "PR 번호를 못 찾았다"
say "2/2 병합 PR #$PR (merge commit · 가지 삭제 안 함)"
gh pr merge "$PR" --repo "$REPO" --merge >/dev/null 2>&1 || die 4 "병합 실패(충돌이면 PR #$PR 화면 확인)"
say "완료 — PR #$PR 병합됨. 되돌리기: GitHub 에서 PR #$PR 의 Revert."
exit 0
