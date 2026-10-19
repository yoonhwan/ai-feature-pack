#!/usr/bin/env bash
# ft-ledger-repo-sync.sh <사본 경로>   (r503 · 뉴스·매거진이 읽는 오빠 원장 «사본 체크아웃» 을 매 회 origin/main 으로 전진)
#   사본 = 읽기 전용 detached 체크아웃(예 <루트>/.worktrees/news-ledger-main). 뉴스(ft_news_ledger·ft_news_html)·매거진(magazine_from_news.sh)이 시작에서 부른다.
#   · 가지 위(symbolic-ref 성공) = 누군가의 작업 공간 → 전진 0 + ERROR rc3
#   · 추적 파일 미커밋 수정(status --porcelain -uno) → 전진 0 + ERROR rc3 (미추적 파일 = 뉴스 html 등은 «깨끗함»)
#   · fetch = fm_fetch(7초 + 재시도 1 · ft-merge-lib.sh) · 실패 → ERROR rc4
#   · HEAD == origin/main → `SYNC up-to-date` · 아니면 checkout --detach origin/main → `SYNC <옛 10자>..<새 10자>` rc0
#   출력 1줄(stdout) · 삭제 0 · 되돌림 = git -C <사본> checkout --detach <옛 sha> · exit 0 정상 · 2 usage · 3 전진 거절 · 4 fetch 실패 · 1 그 밖
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/ft-merge-lib.sh"
[ $# -eq 1 ] && [ -n "$1" ] || { echo "usage: $0 <사본 경로>" >&2; exit 2; }
REPO="$1"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "ERROR ledger 사본이 git 체크아웃이 아니다: $REPO"; exit 1; }
if BR="$(git -C "$REPO" symbolic-ref -q --short HEAD)"; then
  echo "ERROR ledger 사본이 가지 $BR 위 — 전진 0 ($REPO)"; exit 3
fi
DIRTY="$(git -C "$REPO" status --porcelain -uno 2>&1)" || { echo "ERROR ledger 사본 status 실패: ${DIRTY%%$'\n'*}"; exit 1; }
if [ -n "$DIRTY" ]; then
  N="$(printf '%s\n' "$DIRTY" | grep -c .)"
  FIRST="$(printf '%s\n' "$DIRTY" | head -1 | cut -c4-)"
  echo "ERROR ledger 사본 미커밋 추적 변경 $N — 전진 0 ($FIRST)"; exit 3
fi
ERR="$(fm_fetch "$REPO" origin main 2>&1 >/dev/null)" || { echo "ERROR ledger 사본 fetch 실패: ${ERR%%$'\n'*}"; exit 4; }
OLD="$(git -C "$REPO" rev-parse HEAD)" || exit 1
NEW="$(git -C "$REPO" rev-parse --verify -q 'origin/main^{commit}')" || { echo "ERROR ledger 사본에 origin/main 없음 ($REPO)"; exit 1; }
[ "$OLD" = "$NEW" ] && { echo "SYNC up-to-date ${NEW:0:10}"; exit 0; }
OUT="$(git -C "$REPO" checkout -q --detach "$NEW" 2>&1)" || { echo "ERROR ledger 사본 checkout 실패: ${OUT%%$'\n'*}"; exit 1; }
echo "SYNC ${OLD:0:10}..${NEW:0:10}"
