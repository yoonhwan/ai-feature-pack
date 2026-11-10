#!/usr/bin/env bash
# test_press_gate_own_set_worktree_r1332.sh — r1332 press 게이트 ①: «이 press 의 세트 워크트리 자신»은 미랜딩으로 세지 않고 ⊘ 한 줄로 보인다
#   G1 세트 = 현역 나노 W1(미랜딩 3) · 다른 나노 없음 → ① OK + «⊘ 세트 자신(v65-k) — 이 press 가 시험하는 미랜딩 3»
#   G2 G1 + 다른 나노 W2(미랜딩 2) → ✗ 미랜딩 2(W2 만) · UNLANDED=2
#   G3 G1 + 카드가 W1 을 선언 제외 → ⊘ 세트 자신 1줄 · 선언 모순 0 · «선언 이름 없음» 경고 0
#   G4 FT_PRESS_WT 를 W1 의 심링크 경로로 줌(realpath 같음) → G1 과 같다
#   G5 FT_PRESS_WT 기본(리포 루트) · W1 미랜딩 3 → ✗ 미랜딩 3(지금과 같다)
#   G6 W1 의 «git rev-parse HEAD» 실패(래퍼가 주입 · 이 한 곳만) → 제외 0 · ✗ 미랜딩 3
#   기준판 = r1332 착수 때 팩 origin/main(9c655199) → G1·G3 FAIL 이어야 한다
#   변이 W1 = 세트 자신 갈래 삭제 · W2 = HEAD 비교 삭제(경로만) · W3 = ⊘ 줄 없이 조용히 제외
#   실 리포·실 tmux·실 Redis·네트워크 0 · 자기 재호출 0(재진입 가드) · 고정 sleep 0
set -uo pipefail
[ -z "${FT_R1332_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1332_REENTRY=1
. "$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/_press_gate_cache_r1260_lib.sh"
BASE_SHA=9c6551995d05f0fae1df73f368a6e54641d403fe
GC="FT_PRESS_GATE_CACHE_SEC=0"
bash -n "$GATE" && ok "bash -n gate" || bad "bash -n gate"
cmp -s "$GATE" "$KIT/ft-press-gate.sh" && ok "bin·kit 같은 판" || bad "bin·kit 판이 다르다"

# 래퍼 git: 로그 + (G6) GITFAIL 로 지정한 워크트리의 «rev-parse HEAD» 만 실패시킨다
printf '#!/bin/sh\nprintf "%%s \\n" "$*" >> "$GITLOG"\n[ -n "${GITFAIL:-}" ] && [ "$1" = "-C" ] && [ "$2" = "$GITFAIL" ] && [ "$3" = rev-parse ] && [ "$4" = HEAD ] && exit 1\nexec "$REALGIT" "$@"\n' > "$FB/git"
chmod +x "$FB/git"

mk2(){ # 나노 둘 — k(= $W · 세트 후보) · z(다른 나노)
  g "$R" worktree add -q -b nano/z "$R/.worktrees/v65-z" main 2>/dev/null
  printf '{"byz-v65-nano-k#0":{"role":"nano"},"byz-v65-nano-z#0":{"role":"nano"}}\n' > "$R/.fable-team/seats.json"
  printf 'byz-v65-nano-k#0\nbyz-v65-nano-z#0\n' > "$CASE/sessions"
}
case_g1(){ mkcase g1; work 3; GWT="$W"; GENV="$GC"; runbin "$1"
  has "⊘ 세트 자신(v65-k) — 이 press 가 시험하는 미랜딩 3" && ! has "✗ 미랜딩 제품 커밋" && has "S1STATE FAIL=0 UNLANDED=0"; }
case_g2(){ mkcase g2; mk2; work 3; cm "$R/.worktrees/v65-z" worker/z1.py "[fix] z1"; cm "$R/.worktrees/v65-z" worker/z2.py "[fix] z2"
  GWT="$W"; GENV="$GC"; runbin "$1"
  has "⊘ 세트 자신(v65-k) — 이 press 가 시험하는 미랜딩 3" && has "✗ 미랜딩 제품 커밋 2 — v65-z" && ! has "✗ 미랜딩 제품 커밋 3" && has "S1STATE FAIL=1 UNLANDED=2"; }
case_g3(){ mkcase g3; work 3; printf '# card\n- press 제외 나노: v65-k — 시험 제외\n' > "$CASE/card.md"
  GWT="$W"; GENV="$GC FT_PRESS_CARD=$CASE/card.md"; runbin "$1"
  has "⊘ 세트 자신(v65-k)" && ! has "선언 모순" && ! has "선언 이름 없음" && has "S1STATE FAIL=0 UNLANDED=0"; }
case_g4(){ mkcase g4; work 3; ln -s "$W" "$CASE/linkset"; GWT="$CASE/linkset"; GENV="$GC"; runbin "$1"
  has "⊘ 세트 자신(v65-k) — 이 press 가 시험하는 미랜딩 3" && ! has "✗ 미랜딩 제품 커밋" && has "S1STATE FAIL=0 UNLANDED=0"; }
case_g5(){ mkcase g5; work 3; GENV="$GC"; runbin "$1"
  has "✗ 미랜딩 제품 커밋 3 — v65-k" && ! has "세트 자신" && has "S1STATE FAIL=1 UNLANDED=3"; }
case_g6(){ mkcase g6; work 3; GWT="$W"; GENV="$GC GITFAIL=$W"; runbin "$1"
  has "✗ 미랜딩 제품 커밋 3 — v65-k" && ! has "세트 자신" && has "S1STATE FAIL=1 UNLANDED=3"; }

ALL="g1 g2 g3 g4 g5 g6"
t0=$SECONDS
P="$(mkprobe "$GATE")" || { bad "probe 사본"; echo "FAILED"; exit 1; }
run_cases "$P" $ALL
[ -z "$BAD" ] && ok "G1~G6 통과" || { bad "실패 칸:$BAD"; printf '%s\n' "$LAST" | tail -12 | sed 's/^/    /'; }
echo "단계 초: 새 판 G1~G6 $((SECONDS-t0))s"

t0=$SECONDS
BASE="$T/base-gate.sh"
git -C "$LIBDIR" show "$BASE_SHA:feature-pack/fable-team/harness/bin/ft-press-gate.sh" > "$BASE" 2>/dev/null && [ -s "$BASE" ] || { bad "기준판($BASE_SHA) 못 읽음"; echo "FAILED $fail"; exit 1; }
PB="$(mkprobe "$BASE")" || { bad "기준판 probe"; echo "FAILED $fail"; exit 1; }
run_cases "$PB" g1 g3 g5
case "$BAD" in *g1*g3*) ok "기준판 → G1·G3 FAIL" ;; *) bad "기준판이 G1·G3 을 못 잡음(BAD=$BAD)" ;; esac
case "$BAD" in *g5*) bad "기준판 G5 가 FAIL(지금과 같아야 함)" ;; *) ok "기준판 G5 PASS(지금과 같다)" ;; esac
echo "단계 초: 기준판 $((SECONDS-t0))s"

mut(){ # $1 = 이름 · $2 = sed 식 · $3 = FAIL 해야 하는 칸들
  local m; m="$(mkprobe "$GATE" "$2")" || { bad "변이 $1 사본"; return; }
  run_cases "$m" $3
  local c; for c in $3; do case "$BAD" in *"$c"*) ok "변이 $1 → $c FAIL" ;; *) bad "변이 $1 이 $c 를 못 잡음" ;; esac; done
}
t0=$SECONDS
mut W1 's/if _set_self "\$W"; then/if false; then/' "g1 g3 g4"
mut W2 's/^  ha="\$(git -C "\$1" rev-parse HEAD.*$/  true/' "g6"
mut W3 's/^      say "⊘" "세트 자신.*$/      :/' "g1"
echo "단계 초: 변이 $((SECONDS-t0))s"

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
