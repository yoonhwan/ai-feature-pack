#!/usr/bin/env bash
# test_githooks_no_beads_r1345.sh — r1345: 하네스 git 훅(kit/fable-team/githooks)이 beads(bd)를 부르지 않는다.
#   계약 = 카드 r1345-githooks-drop-beads-delegation §계약↔시험 대응표 A1~A5 · 반례 B1~B6 · 변이 1~3.
#   B1 push(게이트 통과) rc0·bd 0 · B2 push(제품코드 range) rc1·PUSH_DENIED·bd 0 · B3 워크트리 checkout(수렴 성공) rc0·.beads post-checkout 0
#   B3b .beads post-checkout 이 rc7 이어도 checkout rc0 · B4 수렴 실패 주입 → rc1(_ftw_rc)·.beads 0 · B5 commit → wall(.beads pre-commit) 1·bd 0
#   B6 루트 checkout rc0·표식층 안 탐·bd 0 · A5 bd 가 PATH 에 없어도 같은 결과(B1·B3 를 bd 없는 PATH 로 1회씩)
#   기준판 = 고정 sha(cdcbe3a2…)의 옛 훅 3종 → B1·B3·B3b·B4·B6 FAIL 이어야 한다 · 변이 1~3 = 현행 훅 사본 한 줄 고쳐 «같은 프로세스 안에서» 다시 돌림.
#   자기 재호출 0(변이도 이 프로세스 안 함수 호출) · 픽스처 = mktemp 리포(로컬 bare origin) · 네트워크 0 · 실 리포·실 훅·실 bd 0 · GIT_* env 0.
#   실행: cd / && ulimit -u <지금 사용자 프로세스 수 + 여유> && timeout 70 bash <이 파일 절대경로>   (단계별 초 = 끝 줄 «단계별 초»)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team/githooks"
BASE_SHA="cdcbe3a2363a698ea1d0a50c129d8e446812db58"   # r1345 착수 전 팩 origin/main — 옛 훅 3종의 고정 기준판
HOOKREL="feature-pack/fable-team/harness/kit/fable-team/githooks"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
. "$HERE/lib/test_only.sh"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_PUSH_DA6_OK FT_WT_FULL
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
REALGIT="$(command -v git)"
ZERO=0000000000000000000000000000000000000000
GB=feat/v6-realtime-live
CALLS="$T/calls"
# 시험이 쓰는 PATH 2종 — WITHBD = 가짜 bd 가 앞 · NOBD = 실 bd 가 없는 최소 PATH(git·python3 는 링크로 넣는다)
mkdir -p "$T/stub" "$T/nobd"
printf '#!/bin/sh\necho "bd $*" >> "%s"\nexit 0\n' "$CALLS" > "$T/stub/bd"; chmod 755 "$T/stub/bd"
for c in git python3 tmux; do p="$(command -v $c 2>/dev/null)"; [ -n "$p" ] && ln -s "$p" "$T/nobd/$c"; done
WITHBD="$T/stub:/usr/bin:/bin"; NOBD="$T/nobd:/usr/bin:/bin"
PATH="$NOBD" command -v bd >/dev/null 2>&1 && { echo "FAIL 전제 — NOBD PATH 에 bd 가 있다"; exit 1; }

REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
# 훅 세트 만들기 — set_hooks <폴더> cur|base
set_hooks() {
  mkdir -p "$1"
  for h in pre-push post-checkout pre-commit; do
    if [ "$2" = cur ]; then cp "$KIT/$h" "$1/$h"
    else "$REALGIT" -C "$REPO" show "$BASE_SHA:$HOOKREL/$h" > "$1/$h" || return 1; fi
    chmod 755 "$1/$h"
  done
}
nbd() { grep -c '^bd ' "$CALLS" 2>/dev/null || true; }
nbk() { grep -c "^$1\$" "$CALLS" 2>/dev/null || true; }   # beads-pc | wall

# scenario <라벨> <훅 폴더> — B1~B6 를 새 픽스처에서 돌려 «B?=PASS|FAIL» 결과를 R_<이름> 변수로 낸다
scenario() {
  local lab="$1" H="$2" R="$T/s-$1" rc b4rc
  mkdir -p "$R"; : > "$CALLS"
  # 시드 리포 → bare origin → 루트 클론(훅 경로 = H) · .beads 스텁 3종은 커밋에 넣는다(워크트리에도 나타나게)
  "$REALGIT" init -q -b main "$R/seed"; local S="$REALGIT -C $R/seed"
  $S config user.email t@t; $S config user.name t
  mkdir -p "$R/seed/gateway" "$R/seed/docs" "$R/seed/design/teams/a" "$R/seed/.beads/hooks"
  echo a > "$R/seed/gateway/a.py"; echo x > "$R/seed/docs/x.md"; echo t > "$R/seed/design/teams/a/f.md"
  printf '#!/bin/sh\necho wall >> "%s"\nexit 0\n' "$CALLS" > "$R/seed/.beads/hooks/pre-commit"
  printf '#!/bin/sh\necho beads-pc >> "%s"\nexit "${BEADS_PC_RC:-0}"\n' "$CALLS" > "$R/seed/.beads/hooks/post-checkout"
  printf '#!/bin/sh\necho beads-pp >> "%s"\nexit 0\n' "$CALLS" > "$R/seed/.beads/hooks/pre-push"
  chmod 755 "$R/seed/.beads/hooks/"*
  $S add -A; $S -c core.hooksPath=/dev/null commit -qm base
  "$REALGIT" clone -q --bare "$R/seed" "$R/origin.git"
  "$REALGIT" clone -q "$R/origin.git" "$R/byz"; local B="$R/byz"
  "$REALGIT" -C "$B" config user.email t@t; "$REALGIT" -C "$B" config user.name t
  : > "$CALLS"
  # B1 — push(게이트 통과 · 게이트 가지 아님) → rc0 · bd 0
  : > "$CALLS"
  printf 'refs/heads/main %s refs/heads/main %s\n' "$("$REALGIT" -C "$B" rev-parse HEAD)" "$("$REALGIT" -C "$B" rev-parse HEAD)" > "$R/in"   # 파이프 대신 파일 stdin — 훅이 stdin 을 안 읽고 끝나도 SIGPIPE(141) 경합 0
  ( cd "$B" && PATH="$WITHBD" sh "$H/pre-push" origin x < "$R/in" ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbd)" = 0 ] && eval "R_${lab}_B1=PASS" || eval "R_${lab}_B1=FAIL"
  # A5 — bd 가 PATH 에 없어도 같은 결과(B1)
  : > "$CALLS"
  ( cd "$B" && PATH="$NOBD" sh "$H/pre-push" origin x < "$R/in" ) >/dev/null 2>"$R/a5a.err"; rc=$?
  [ "$rc" = 0 ] || echo "  [진단] $lab A5a rc=$rc err=$(head -c 200 "$R/a5a.err" | tr '\n' ' ')"
  [ "$rc" = 0 ] && [ "$(nbd)" = 0 ] && eval "R_${lab}_A5a=PASS" || eval "R_${lab}_A5a=FAIL"
  # B2 — 게이트 가지 + 제품코드 range → rc1 · PUSH_DENIED · bd 0
  : > "$CALLS"
  "$REALGIT" -C "$B" checkout -q -b "$GB"; echo p > "$B/gateway/b.py"; "$REALGIT" -C "$B" add -A
  "$REALGIT" -C "$B" -c core.hooksPath=/dev/null commit -qm prod
  printf 'refs/heads/%s %s refs/heads/%s %s\n' "$GB" "$("$REALGIT" -C "$B" rev-parse HEAD)" "$GB" "$ZERO" > "$R/in2"
  ( cd "$B" && PATH="$WITHBD" sh "$H/pre-push" origin x < "$R/in2" ) >/dev/null 2>"$R/b2.err"; rc=$?
  [ "$rc" = 1 ] && grep -q PUSH_DENIED "$R/b2.err" && [ "$(nbd)" = 0 ] && eval "R_${lab}_B2=PASS" || eval "R_${lab}_B2=FAIL"
  "$REALGIT" -C "$B" checkout -q main
  # 훅을 켠다(여기부터 git 이 훅을 부른다)
  "$REALGIT" -C "$B" config core.hooksPath "$H"
  mkdir -p "$B/.worktrees"
  mkwt() { "$REALGIT" -C "$B" -c core.hooksPath=/dev/null worktree add -q --no-checkout "$B/.worktrees/$1" -b "$1" main 2>/dev/null; \
    printf 'sparse\n' > "$("$REALGIT" -C "$B/.worktrees/$1" rev-parse --path-format=absolute --git-dir)/ft-wt-mode"; }
  # B3 — 워크트리 checkout(표식 sparse · 수렴 성공) → rc0 · .beads post-checkout 0
  mkwt w3; : > "$CALLS"
  ( cd "$B/.worktrees/w3" && PATH="$WITHBD" "$REALGIT" checkout -q ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbk beads-pc)" = 0 ] && [ "$(nbd)" = 0 ] && eval "R_${lab}_B3=PASS" || eval "R_${lab}_B3=FAIL"
  # A5 — bd 없는 PATH
  mkwt w3n; : > "$CALLS"
  ( cd "$B/.worktrees/w3n" && PATH="$NOBD" "$REALGIT" checkout -q ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbk beads-pc)" = 0 ] && eval "R_${lab}_A5b=PASS" || eval "R_${lab}_A5b=FAIL"
  # B3b — .beads post-checkout 이 rc7 로 끝나도 checkout rc0 (옛 판: checkout rc = beads rc → r1336 «sparse 체크아웃 실패» 반송)
  mkwt w3b; : > "$CALLS"
  ( cd "$B/.worktrees/w3b" && BEADS_PC_RC=7 PATH="$WITHBD" "$REALGIT" checkout -q ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbk beads-pc)" = 0 ] && eval "R_${lab}_B3b=PASS" || eval "R_${lab}_B3b=FAIL"
  # B4 — 수렴 실패 주입(sparse-checkout rc1) → rc1(_ftw_rc) · .beads 0
  mkwt w4; : > "$CALLS"
  : > "$("$REALGIT" -C "$B/.worktrees/w4" rev-parse --path-format=absolute --git-dir)/info"   # info 자리가 일반 파일 → git sparse-checkout set 이 쓰기에 실패(rc≠0)
  ( cd "$B/.worktrees/w4" && PATH="$WITHBD" "$REALGIT" checkout -q ) >/dev/null 2>"$R/b4.err"; b4rc=$?
  echo "  [진단] $lab B4 rc=$b4rc beads-pc=$(nbk beads-pc) err=$(head -c 160 "$R/b4.err" | tr '\n' ' ')"
  [ "$b4rc" = 1 ] && [ "$(nbk beads-pc)" = 0 ] && eval "R_${lab}_B4=PASS" || eval "R_${lab}_B4=FAIL"
  # B5 — commit → wall(.beads pre-commit) 1 · bd 0 · rc0
  : > "$CALLS"; echo c >> "$B/docs/x.md"; "$REALGIT" -C "$B" add docs/x.md
  ( cd "$B" && PATH="$WITHBD" "$REALGIT" commit -qm c ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbk wall)" = 1 ] && [ "$(nbd)" = 0 ] && eval "R_${lab}_B5=PASS" || eval "R_${lab}_B5=FAIL"
  # B6 — 루트(주 워크트리) checkout → rc0 · 표식층 안 탐(표식 파일 0) · .beads 0
  : > "$CALLS"
  ( cd "$B" && PATH="$WITHBD" "$REALGIT" checkout -q -b rootb ) >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && [ "$(nbk beads-pc)" = 0 ] && [ "$(nbd)" = 0 ] && [ ! -e "$B/.git/ft-wt-mode" ] && eval "R_${lab}_B6=PASS" || eval "R_${lab}_B6=FAIL"
}
# want <라벨> <칸…> — 지정한 칸은 FAIL 이어야 하고(변이·기준판) 나머지는 PASS 여야 한다는 단언 대신, «지정 칸 FAIL» 만 센다
res() { eval "printf %s \"\${R_$1_$2:-NONE}\""; }
expect_all() {  # <라벨> <뜻> — 전 칸 PASS
  local lab="$1" k; local miss=""
  for k in B1 B2 B3 B3b B4 B5 B6 A5a A5b; do [ "$(res "$lab" "$k")" = PASS ] || miss="$miss $k"; done
  [ -z "$miss" ] && ok "$2 — 9칸 전부 PASS" || bad "$2 — FAIL 칸:$miss"
}
expect_fail() {  # <라벨> <뜻> <칸…> — 지정 칸이 전부 FAIL
  local lab="$1" what="$2" k miss=""; shift 2
  for k in "$@"; do [ "$(res "$lab" "$k")" = FAIL ] || miss="$miss $k"; done
  [ -z "$miss" ] && ok "$what — $* FAIL(기대대로)" || bad "$what — FAIL 이어야 하는데 아님:$miss"
}

t0=$SECONDS; tcur=""; tbase=""; tm1=""; tm2=""; tm3=""

echo "== 구문 · 현행 훅"
for h in pre-push post-checkout pre-commit; do sh -n "$KIT/$h" && ok "sh -n $h" || bad "sh -n $h"; done
grep -v '^[[:space:]]*#' "$KIT/pre-push" | grep -q 'bd hooks run' && bad "pre-push 에 bd 위임 문자열 남음" || ok "pre-push 에 bd 위임 문자열 0"
grep -v '^[[:space:]]*#' "$KIT/post-checkout" | grep -q '\.beads/hooks' && bad "post-checkout 코드에 .beads 위임 남음" || ok "post-checkout 코드에 .beads 위임 0"

echo "== 현행 판 — B1~B6 · B3b · A5"
if ft_only cur; then
  set_hooks "$T/H-cur" cur && scenario cur "$T/H-cur" && expect_all cur "현행 훅"
  tcur=$((SECONDS - t0)); t0=$SECONDS
fi

echo "== 기준판(고정 sha ${BASE_SHA%${BASE_SHA#????????}}) — 옛 훅은 반례에 걸린다"
if ft_only base; then
  if set_hooks "$T/H-base" base; then scenario base "$T/H-base"; expect_fail base "기준판 옛 훅" B1 B3 B3b B4 B6
  else bad "기준판 훅을 고정 sha 에서 꺼내지 못함"; fi
  tbase=$((SECONDS - t0)); t0=$SECONDS
fi

echo "== 변이 1~3 — 현행 훅 사본을 한 줄 고쳐 같은 프로세스에서 다시 돌린다"
if ft_only mut; then
  set_hooks "$T/H-m1" cur; { sed '$d' "$T/H-m1/pre-push"; printf 'if command -v bd >/dev/null 2>&1; then\n  exec bd hooks run pre-push "$@"\nfi\nexit 0\n'; } > "$T/H-m1/p" && mv "$T/H-m1/p" "$T/H-m1/pre-push" && chmod 755 "$T/H-m1/pre-push"
  scenario m1 "$T/H-m1"; expect_fail m1 "변이 1 (pre-push 에 bd 위임 되살림)" B1; tm1=$((SECONDS - t0)); t0=$SECONDS
  set_hooks "$T/H-m2" cur; sed '$s/.*/exit 0/' "$T/H-m2/post-checkout" > "$T/H-m2/p" && mv "$T/H-m2/p" "$T/H-m2/post-checkout" && chmod 755 "$T/H-m2/post-checkout"
  scenario m2 "$T/H-m2"; expect_fail m2 "변이 2 (post-checkout 끝을 exit 0)" B4; tm2=$((SECONDS - t0)); t0=$SECONDS
  set_hooks "$T/H-m3" cur; sed '/\.beads\/hooks\/pre-commit" \]/,/^fi$/d' "$T/H-m3/pre-commit" > "$T/H-m3/p" && mv "$T/H-m3/p" "$T/H-m3/pre-commit" && chmod 755 "$T/H-m3/pre-commit"
  scenario m3 "$T/H-m3"; expect_fail m3 "변이 3 (pre-commit wall 위임 제거)" B5; tm3=$((SECONDS - t0)); t0=$SECONDS
fi

echo "단계별 초: 현행=${tcur:-0} 기준판=${tbase:-0} 변이1=${tm1:-0} 변이2=${tm2:-0} 변이3=${tm3:-0}"
ft_only_report || fail=$((fail+1))
echo "== 결과: FAIL=$fail"
[ "$fail" = 0 ]
