#!/usr/bin/env bash
# ft-card-target-lib.sh — 카드 «대상:» 줄(마지막)의 절대경로 뽑기 + 팩/밖 가르기 (r1138 · source 전용)
#   ft-nano-close(⑥--landed-pr 리포 판정)와 ft-index-lint(한 카드 = 한 리포)가 같은 함수를 부른다 — 두 벌 0.
ft_card_pack_root() { ( cd "${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}" 2>/dev/null && pwd -P ); }
ft_card_targets() {  # <카드> → «대상:» 줄(마지막)의 절대경로만 — (…)·«·»·쉼표 = 구분자
  [ -n "${1:-}" ] && [ -f "$1" ] || return 0
  grep -E '^[[:space:]]*-?[[:space:]]*대상:' "$1" 2>/dev/null | tail -1 \
    | sed 's/·/ /g; s/[()]/ /g; s/,/ /g' | tr ' ' '\n' | grep -E '^/' | sed 's/\.$//'
}
ft_card_target_side() {  # <팩 루트(빈 값 = 팩 없음)> <절대경로> → pack | out
  case "$1" in '') echo out;; *) case "$2" in "$1"|"$1"/*) echo pack;; *) echo out;; esac;; esac
}
ft_card_target_lint() {  # <카드> → REJECT 사유 줄(0~2) · ① 팩·밖 섞임 ② 라이브 설치 경로(닫기가 «밖 = ROOT» 로 풀어 엉뚱한 리포 PR 과 비교)
  local pk t ein="" eout="" elive=""
  pk="$(ft_card_pack_root)"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ "$(ft_card_target_side "$pk" "$t")" = pack ]; then ein="${ein:-$t}"; else eout="${eout:-$t}"; fi
    [[ "$t" =~ ^/.+/\.claude/fable-team/live/[^/]+/ ]] && elive="${elive:-$t}"
  done <<< "$(ft_card_targets "$1")"
  [ -n "$ein" ] && [ -n "$eout" ] && echo "한 카드 = 한 리포 — 대상에 팩·BYZ 경로가 섞임($ein · $eout) · 카드를 둘로 나누고 다른 리포 일은 기록 줄로"
  [ -n "$elive" ] && echo "대상에 라이브 설치 경로 — 팩 경로(feature-pack/…)로 쓰고 라이브는 «- 설치:» 줄로($elive)"
  return 0
}
