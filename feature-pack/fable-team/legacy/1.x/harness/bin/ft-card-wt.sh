#!/usr/bin/env bash
# ft-card-wt.sh <좌석 이름> [<가지>] — r2278: 카드 폴더만 펼친 sparse worktree 를 좌석 베이스당 1개 다시 쓴다.
#   경로 = ${FT_CARDWT_DIR:-/private/tmp/ft-cardwt}/<좌석 베이스(#N 뺀 이름)> · 가지 기본 = ops/main-base
#   없으면 non-cone sparse(패턴 고정 · cone 은 와일드카드를 못 받고 부모 직속 파일을 함께 펼친다) worktree 를 분리 HEAD 로 만든다.
#   있으면 status 0 일 때만 checkout --detach origin/<가지> · 수정 파일 있음 = REJECT(덮어쓰기 0).
#   rc 0 = «WT <경로> head=<sha40>» · 1 = REJECT · 2 = usage · 3 = «판정 불가 <단계>»(하드 룰 20)
set -uo pipefail
die() { echo "판정 불가 $1"; exit 3; }
rej() { echo "REJECT $1"; exit 1; }
{ [ $# -ge 1 ] && [ $# -le 2 ]; } || { echo "usage: $0 <좌석 이름> [<가지>]" >&2; exit 2; }
S="${1%%#*}" B="${2:-ops/main-base}"
[[ "$S" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || rej "좌석 이름 꼴 ($1)"
command -v git >/dev/null 2>&1 || die git
git check-ref-format "refs/heads/$B" || rej "가지 이름 꼴 ($B)"
t7() { perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' 7 "$@"; }   # 외부 호출 1회 7초(하드 룰 12)
PATTERNS=('/design/*/indices/' '/design/teams/*/indices/' '/design/TEAMS.md' '/design/*/GOAL-*.md' '/design/teams/*/GOAL-*.md')
D="${FT_CARDWT_DIR:-/private/tmp/ft-cardwt}/$S"
COMMON="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || die repo
{ t7 git fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B" || t7 git fetch -q origin "+refs/heads/$B:refs/remotes/origin/$B"; } >/dev/null 2>&1 || die fetch
H="$(git rev-parse -q --verify "refs/remotes/origin/$B^{commit}")" || die fetch
if [ -e "$D" ]; then
  [ "$(git -C "$D" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" = "$COMMON" ] || rej "이 리포의 worktree 아님 ($D)"
  st="$(git -C "$D" status --porcelain 2>/dev/null)" || die status
  [ -z "$st" ] || { echo "REJECT 수정 파일 있음 ($D · 덮어쓰기 0)"; printf '%s\n' "$st" | head -5; exit 1; }
  git -C "$D" checkout -q --detach "$H" >/dev/null 2>&1 || die checkout
else
  mkdir -p "$(dirname "$D")" || die mkdir
  git worktree add -q --no-checkout --detach "$D" "$H" >/dev/null 2>&1 || die worktree-add
  git -C "$D" sparse-checkout set --no-cone "${PATTERNS[@]}" >/dev/null 2>&1 || die sparse-checkout   # 새 git 의 non-cone 경고(stderr)는 거른다
  git -C "$D" read-tree -mu HEAD >/dev/null 2>&1 || die read-tree   # --no-checkout 은 index 가 비어 있다 → 패턴 안만 채운다
fi
echo "WT $D head=$(git -C "$D" rev-parse HEAD)"
