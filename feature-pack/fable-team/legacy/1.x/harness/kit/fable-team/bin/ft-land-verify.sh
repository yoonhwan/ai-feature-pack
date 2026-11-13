#!/usr/bin/env bash
# ft-land-verify.sh — r1814 B1 착지 확인(읽기만 · fetch 0 · 쓰기 0 · fetch 는 부르는 쪽이 한다)
#   사용: ft-land-verify.sh <repo> <PR번호> <세트 40hex> [--since <main_before 40hex>] [--head <PR head 40hex>]
#   ⓐ 세트가 origin/main 의 조상 → `LANDED-ANCESTOR <세트>` rc0
#   ⓑ 아니면 --since..origin/main(없으면 최근 first-parent 200개) first-parent 커밋 중 본문에 `PR #<N> (head <--head>)` 줄이 든 커밋이 정확히 1개
#      → `LANDED-SQUASH <그 커밋 40hex>` rc0 (ft-merge-land 의 squash·자동 병합 C 메시지 꼴)
#   ⓒ 0개 → `MISS PR #<N> 세트 <세트10>` rc1 · ⓓ 2개 이상 → `판정 불가 같은 PR·세트 커밋 <n>개` rc3 · ⓔ git 실패 → `판정 불가 git <단계> rc=<n>` rc3
#   --head 기본 = 세트(ft-merge-land 본문의 head = 착지 때 PR head · 착지 h 는 HEADSHA 를 넘긴다)
#   하드 룰 20: 실패는 unj 한 곳이 1줄로 끝낸다 · `git log | grep -q`(pipefail 아래 SIGPIPE rc141) 꼴 0 — 출력을 받아 센다
set -u
export LC_ALL=C
unj() { echo "판정 불가 $1"; exit 3; }
H40='^[0-9a-f]{40}$'
[ $# -ge 3 ] || unj "인자 <repo> <PR번호> <세트 40hex> rc=2"
P="$1" PR="$2" SET="$3"; shift 3; SINCE="" HEAD=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || unj "인자 $1 값 없음 rc=2"
  case "$1" in --since) SINCE="$2";; --head) HEAD="$2";; *) unj "인자 $1 rc=2";; esac
  shift 2
done
HEAD="${HEAD:-$SET}"
{ [[ "$PR" =~ ^[0-9]+$ ]] && [[ "$SET" =~ $H40 ]] && [[ "$HEAD" =~ $H40 ]] && { [ -z "$SINCE" ] || [[ "$SINCE" =~ $H40 ]]; }; } || unj "인자 꼴(PR 숫자 · sha 40hex) rc=2"
G() { git -C "$P" "$@"; }
MAIN=refs/remotes/origin/main
G rev-parse --verify -q "$MAIN^{commit}" >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] || unj "git rev-parse rc=$rc"
if G cat-file -e "$SET^{commit}" 2>/dev/null; then   # 세트 객체가 없으면 main 의 조상일 수 없다 → ⓑ 로
  G merge-base --is-ancestor "$SET" "$MAIN" 2>/dev/null; rc=$?
  [ "$rc" = 0 ] && { echo "LANDED-ANCESTOR $SET"; exit 0; }
  [ "$rc" = 1 ] || unj "git merge-base rc=$rc"
fi
if [ -n "$SINCE" ]; then R=("$SINCE..$MAIN"); else R=(-n 200 "$MAIN"); fi
LOG="$(G log --first-parent --format='%x1e%H%n%B' "${R[@]}" -- 2>/dev/null)"; rc=$?
[ "$rc" = 0 ] || unj "git log rc=$rc"
HITS="$(printf '%s' "$LOG" | awk -v w="PR #$PR (head $HEAD)" 'BEGIN { RS = "\036" } NF { n = split($0, L, "\n"); for (i = 2; i <= n; i++) if (L[i] == w) { print L[1]; break } }')"
N=0; [ -z "$HITS" ] || N="$(printf '%s\n' "$HITS" | wc -l | tr -d ' ')"
case "$N" in
  0) echo "MISS PR #$PR 세트 ${SET:0:10}"; exit 1;;
  1) echo "LANDED-SQUASH $HITS"; exit 0;;
  *) unj "같은 PR·세트 커밋 ${N}개";;
esac
