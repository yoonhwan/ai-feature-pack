#!/usr/bin/env bash
# ft-approval-equiv.sh <A> <S> [--repo <dir>] [--remote origin] [--target main]   (R247 · 오빠 판정 1917 «승인 sha + main merge 만 → 동일승인»)
#   A = 오빠가 승인한 PR head sha · S = 지금 PR head. «A 가 S 의 조상 · A..S 는 main 병합뿐 · main 대비 자기 변경이 A 때와 같음» 일 때만 EQUIV.
#   읽기 전용 · 로컬 git 만(네트워크 0 — main 은 호출 전에 최신이어야 한다: ft-merge-land 가 게이트에서 fetch 한 뒤 부른다). 규칙 본문은 ft_approval_equiv.py 머리.
#   출력 EQUIV approve=<A> head=<S> merges=<n> files=<n> rc0 · NOT-EQUIV <사유> rc1 · ERROR <사유> rc3(못 판단 = 통과 0 · #0 RULE) · usage rc2.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
A=""; S=""; REPO=""; REMOTE="origin"; TARGET="main"
usage() { echo "usage: $0 <A 40hex> <S 40hex> [--repo <dir>] [--remote origin] [--target main]" >&2; exit 2; }
while [ $# -gt 0 ]; do case "$1" in
  --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2;;
  --remote) [ $# -ge 2 ] || usage; REMOTE="$2"; shift 2;;
  --target) [ $# -ge 2 ] || usage; TARGET="$2"; shift 2;;
  -*) usage;;
  *) if [ -z "$A" ]; then A="$1"; elif [ -z "$S" ]; then S="$1"; else usage; fi; shift;; esac; done
printf '%s' "$A" | grep -Eq '^[0-9a-f]{40}$' && printf '%s' "$S" | grep -Eq '^[0-9a-f]{40}$' || usage
[ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR repo 를 찾을 수 없음"; exit 3; }
exec python3 -I "$HERE/ft_approval_equiv.py" "$REPO" "$A" "$S" "$REMOTE" "$TARGET"
