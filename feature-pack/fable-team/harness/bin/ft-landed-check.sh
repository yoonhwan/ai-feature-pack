#!/usr/bin/env bash
# ft-landed-check.sh <리포 루트> <main ref> <가지> <카드 키>  — 나노 가지가 main 에 «착지» 했는가 (읽기 전용 · 삭제 0).
#   r-disk-drop-worktree-scratch-census · DA⑥ HOLD 2~3 — census(표) · ft-nano-close --plan-only(생성 시점) · 정리 계획 본문(실행 시점)이 «같은 판정» 을 쓴다.
#   출력 1단어 = 근거: ancestor(가지 tip 이 main 조상) · cherry(`git cherry <main> <가지>` 에 «+» 0) · card(main 의 design/*/indices/완성/<키>.md «세트: <40hex>» == 가지 tip) · grep(main 커밋 메시지에 키 — ★약한 증거★) · no
#   rc 0 = 강한 근거(ancestor·cherry·card) · rc 1 = 착지 아님(grep·no 포함) · rc 2 = usage/ref 없음.
#   card 는 «카드 증거 세트 == 지금 가지 tip» 일 때만 — 카드 뒤에 미착지 커밋이 더 붙은 가지는 card 가 아니다.
set -uo pipefail
ROOT="${1:-}"; MAIN="${2:-}"; BR="${3:-}"; KEY="${4:-}"
[ -n "$ROOT" ] && [ -n "$MAIN" ] && [ -n "$BR" ] && [ -n "$KEY" ] || { echo "usage: $0 <repo> <main-ref> <branch> <card-key>" >&2; exit 2; }
git -C "$ROOT" rev-parse -q --verify "$MAIN^{commit}" >/dev/null && TIP="$(git -C "$ROOT" rev-parse -q --verify "$BR^{commit}")" || { echo "no"; echo "ref 없음: $MAIN / $BR" >&2; exit 2; }
if git -C "$ROOT" merge-base --is-ancestor "$TIP" "$MAIN"; then echo ancestor; exit 0; fi
ch="$(git -C "$ROOT" cherry "$MAIN" "$BR" 2>/dev/null)"; crc=$?
if [ "$crc" -eq 0 ] && ! printf '%s\n' "$ch" | grep -q '^+'; then echo cherry; exit 0; fi
while IFS= read -r f; do
  git -C "$ROOT" show "$MAIN:$f" 2>/dev/null | grep -oE '세트: [0-9a-f]{40}' | grep -q "$TIP" && { echo card; exit 0; }
done < <(git -C "$ROOT" ls-tree -r --name-only "$MAIN" -- design 2>/dev/null | grep -E "^design/[^/]+/indices/완성/$(printf '%s' "$KEY" | sed 's/[][\.*^$/]/\\&/g')\.md$")
if [ -n "$(git -C "$ROOT" log "$MAIN" --fixed-strings "--grep=$KEY" -n1 --format=%H 2>/dev/null)" ]; then echo grep; exit 1; fi
echo no; exit 1
