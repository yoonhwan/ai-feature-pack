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
ft_land_refs() {  # <리포> → 착지 ref 후보(한 줄에 하나 · 이 순서로 본다) — r1754 · close-due · nano-close · evidence-check 가 같이 쓴다
  #   FT_LAND_REF 가 있으면 그 하나 · 없으면 origin/main 다음 origin/ops/main-base(그 리포 원격에 그 가지가 있을 때만)
  #   ls-remote 실패(7초 + 재시도 1) = stdout «판정 불가 착지 ref — <사유>» 1줄 · rc 1(하드 룰 20 · 후보 추측 0)
  local out rc=1 i
  [ -z "${FT_LAND_REF:-}" ] || { printf '%s\n' "$FT_LAND_REF"; return 0; }
  for i in 1 2; do
    out="$(perl -e 'alarm 7; exec @ARGV' git -C "${1:-.}" ls-remote --heads origin refs/heads/ops/main-base 2>&1 </dev/null)"; rc=$?
    [ "$rc" -eq 0 ] && break   # r1754-mut:lsrc
  done
  [ "$rc" -eq 0 ] || { echo "판정 불가 착지 ref — git ls-remote origin rc=$rc: $(printf '%s' "$out" | head -1 | cut -c1-120)"; return 1; }
  echo origin/main
  printf '%s\n' "$out" | grep -qE '[[:space:]]refs/heads/ops/main-base$' && echo origin/ops/main-base   # r1754-mut:ops
  return 0
}
