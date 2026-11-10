#!/usr/bin/env bash
# test_post_checkout_reapply_r1030.sh — r1030 표식층: kit/fable-team/githooks/post-checkout 이 «표식이 곧 목표» 로 수렴하는가.
#   계약 = 카드 r1030-wt-sparse-hook-idempotent-reapply §계약↔시험 대응표 ⓐ~ⓗ. 되돌리기(원값 적어 두기·복원) 코드가 없다는 것도 단언한다.
#   픽스처 = mktemp 리포 2(B = design/teams/{a,b,c} · P = 팩 꼴) · core.hooksPath = 키트 훅 사본만 · .beads/hooks/post-checkout 스텁(커밋).
#   실 리포·실 훅 0 · GIT_* env 0 · 바깥 네트워크 0. 변이 = 사본 한 줄 → 이 파일 재실행(R1030_MUT=1 재귀 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../kit/fable-team/githooks/post-checkout"
HOOK="${R1030_HOOK:-$SRC}"
STAMP="$HERE/../kit/fable-team/bin/ft-wt-mode-stamp.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
. "$HERE/lib/test_only.sh"   # r1026 · FT_TEST_ONLY 칸만 돌리기(변이·검증 좌히기 · 하드 룰 22)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$HOOK" ] || { bad "훅 파일 없음: $HOOK"; echo "== 결과: FAIL=$fail"; exit 1; }
mkdir -p "$T/hooks"; cp "$HOOK" "$T/hooks/post-checkout"; chmod +x "$T/hooks/post-checkout"
B="$T/byz"; P="$T/pack"
for r in "$B" "$P"; do
  git init -q -b main "$r"; git -C "$r" config user.name t; git -C "$r" config user.email t@t; git -C "$r" config core.hooksPath "$T/hooks"
  mkdir -p "$r/.beads/hooks"; printf '#!/bin/sh\nexit 0\n' > "$r/.beads/hooks/post-checkout"; chmod +x "$r/.beads/hooks/post-checkout"
  echo x > "$r/README.md"
done
for t in a b c; do mkdir -p "$B/design/teams/$t"; echo "$t" > "$B/design/teams/$t/f.md"; done
for r in "$B" "$P"; do git -C "$r" add -A; git -C "$r" commit -qm init; done
unset FT_WT_FULL FT_R835_SPARSE_HOOK
LOG="$B/.fable-team/state/wt-add-full.log"
gd() { git -C "$1" rev-parse --path-format=absolute --git-dir; }
wt() { git -C "$B" -c core.hooksPath=/dev/null worktree add -q --no-checkout "$B/.worktrees/$1" -b "$1" main 2>/dev/null; }
co() { ( cd "$B/.worktrees/$1" && git checkout -q ) >"$T/o" 2>"$T/e"; }
mark() { cat "$(gd "$B/.worktrees/$1")/ft-wt-mode" 2>/dev/null; }
setmark() { printf '%s\n' "$2" > "$(gd "$B/.worktrees/$1")/ft-wt-mode"; }
setpat() { mkdir -p "$(gd "$B/.worktrees/$1")/info"
  if [ "$2" = empty ]; then : > "$(gd "$B/.worktrees/$1")/info/sparse-checkout"
  else printf '/*\n!/design/teams/*/\n/design/teams/b/\n' > "$(gd "$B/.worktrees/$1")/info/sparse-checkout"; fi; }
sum() { if [ -e "$1" ]; then cksum < "$1"; else echo none; fi; }
# snap <워크트리> — 그 턴에 바뀌면 안 되는 것 전부(표식·패턴 파일·설정 2값)를 한 줄로
snap() { printf 'mark=%s|pat=%s|sc=%s|wtc=%s' \
  "$(sum "$(gd "$B/.worktrees/$1")/ft-wt-mode")" "$(sum "$(gd "$B/.worktrees/$1")/info/sparse-checkout")" \
  "$(git -C "$B/.worktrees/$1" config --get core.sparseCheckout 2>/dev/null || echo unset)" \
  "$(git -C "$B" config --get extensions.worktreeConfig 2>/dev/null || echo unset)"; }
sparse_on() { [ "$(git -C "$1" config --bool core.sparseCheckout 2>/dev/null)" = true ]; }
pat() { git -C "$B/.worktrees/$1" sparse-checkout list 2>/dev/null; }
errn() { grep -c '^ERROR ft-wt-mode' "$T/e"; }
DENY="$(command -v sandbox-exec 2>/dev/null | head -1)"
deny_at() { printf '(version 1)(allow default)(deny file-write* (literal "%s"))' "$1"; }

echo "== ⓐ 표식 있음(값 무관) × 패턴 3꼴 = 변경 0 (계약 ①)"
if ft_only ⓐ; then
  i=0; bada=0
  for v in "full 열 글자 넘는 사유 문장" legacy-full custom-marker "" "sparse " "SPARSE"; do
    for p in none empty team; do
      i=$((i+1)); w="x$i"; wt "$w"
      if [ -n "$v" ]; then setmark "$w" "$v"; else : > "$(gd "$B/.worktrees/$w")/ft-wt-mode"; fi
      [ "$p" = none ] || setpat "$w" "$p"
      b0="$(snap "$w")"; co "$w"; rc=$?; b1="$(snap "$w")"
      if [ "$rc" != 0 ] || [ "$b0" != "$b1" ] || [ -s "$T/e" ]; then bada=$((bada+1)); echo "  ⓐ 어긋남 값=«$v» 패턴=$p rc=$rc $b0 → $b1 e=$(head -c 200 "$T/e")"; fi
    done
  done
  [ "$bada" = 0 ] && ok "ⓐ 표식 6값 × 패턴 3꼴 18조합 = 체크섬 그대로 · stderr 0(팀 패턴은 어떤 길에서도 덮이지 않음)" || bad "ⓐ 어긋남 $bada 조합"
  w="an"; wt "$w"; setmark "$w" sparse; setpat "$w" team; b0="$(snap "$w")"; co "$w"; rc=$?
  [ "$rc" = 0 ] && [ "$b0" = "$(snap "$w")" ] && [ ! -s "$T/e" ] && ok "ⓐ 표식 sparse + 도구 팀 패턴(내용 있음) → 덮지 않음 · 설정 변경 0" || bad "ⓐ sparse+팀 패턴 rc=$rc $b0 → $(snap "$w") · $(head -c 200 "$T/e")"
fi

echo "== ⓑ 수렴 · ⓑ2 멱등 (계약 ②)"
if ft_only ⓑ ⓑ2; then
  j=0
  for form in none false empty team-wt; do
    j=$((j+1)); w="b$j"; wt "$w"; setmark "$w" sparse
    case "$form" in
      false) git -C "$B/.worktrees/$w" config core.sparseCheckout false;;
      empty) setpat "$w" empty;;
      team-wt) git -C "$B" config extensions.worktreeConfig true; git -C "$B/.worktrees/$w" config --worktree --bool core.sparseCheckout false;;
    esac
    co "$w"; rc=$?
    if [ "$rc" = 0 ] && sparse_on "$B/.worktrees/$w" && [ "$(mark "$w")" = sparse ] && [ "$(pat "$w")" = "$(printf '/*\n!/design/teams/*/')" ] \
       && [ "$(errn)" = 0 ] && [ "$(grep -c '\[r835\]' "$T/e")" = 1 ] && ! [ -e "$B/.worktrees/$w/design/teams/b" ]; then
      ok "ⓑ 표식 sparse + 실제 풀($form) → set 1회 → sparse(패턴 2줄 · 표식 sparse)"
    else bad "ⓑ $form rc=$rc sc=$(git -C "$B/.worktrees/$w" config --bool core.sparseCheckout 2>&1) 표식=$(mark "$w") 패턴=$(pat "$w") · $(head -c 200 "$T/e")"; fi
    [ "$form" = team-wt ] && git -C "$B" config --unset extensions.worktreeConfig
  done
  w=b5; wt "$w"; setmark "$w" sparse; co "$w"; s0="$(snap "$w")"
  co "$w"; rc=$?
  [ "$rc" = 0 ] && [ "$s0" = "$(snap "$w")" ] && [ ! -s "$T/e" ] && [ "$(mark "$w")" = sparse ] \
    && ok "ⓑ2 같은 입력 2번째 실행 = 표식·패턴 바이트 동일 · stderr 0(멱등)" || bad "ⓑ2 rc=$rc $s0 → $(snap "$w") · $(head -c 200 "$T/e")"
fi

echo "== ⓒ 실패 주입 7종 = ERROR 1줄 + rc1 + 그 턴 상태 변경 0 (계약 ③)"
if ft_only ⓒ ⓒ2; then
  site() {  # <이름> <준비함수> <checkout 명령 문자열>  — 표식·패턴·설정 체크섬이 그대로인지 본다
    local w="$1" b0 b1 rc
    wt "$w"; "$2" "$w"
    b0="$(snap "$w")"
    "$3" >"$T/o" 2>"$T/e"; rc=$?
    b1="$(snap "$w")"
    if [ "$rc" != 0 ] && [ "$(errn)" = 1 ] && [ "$b0" = "$b1" ]; then ok "ⓒ $w 실패 자리: ERROR 1줄 · rc≠0 · 설정·패턴·표식 체크섬 그대로"
    else bad "ⓒ $w rc=$rc ERROR=$(errn) $b0 → $b1 · $(head -c 200 "$T/e")"; fi
  }
  pre_mark() { setmark "$1" sparse; }
  pre_team() { setmark "$1" sparse; setpat "$1" team; }
  pre_none() { :; }
  pre_lock() { setmark "$1" sparse; git -C "$B" config extensions.worktreeConfig true; git -C "$B/.worktrees/$1" config core.sparseCheckout true; touch "$(gd "$B/.worktrees/$1")/info"; }
  mkdir -p "$T/g1" "$T/g2" "$T/c1" "$T/c2"
  printf '#!/bin/sh\ncase "$*" in "rev-parse --show-toplevel") exit 128;; esac\nexec /usr/bin/git "$@"\n' > "$T/g1/git"
  printf '#!/bin/sh\ncase "$*" in *"--get core.sparseCheckout"*) exit 128;; esac\nexec /usr/bin/git "$@"\n' > "$T/g2/git"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in */ft-wt-mode) exit 1;; esac; done\nexec /bin/cat "$@"\n' > "$T/c1/cat"
  printf '#!/bin/sh\nfor a in "$@"; do case "$a" in */info/sparse-checkout) exit 1;; esac; done\nexec /bin/cat "$@"\n' > "$T/c2/cat"
  chmod +x "$T/g1/git" "$T/g2/git" "$T/c1/cat" "$T/c2/cat"
  inj_c1() { ( cd "$B/.worktrees/c1" && PATH="$T/g1:$PATH" "$T/hooks/post-checkout" ); }   # git 이 훅에 자기 exec-path 를 PATH 앞에 붙이므로 직접 실행으로 주입
  inj_c2() { ( cd "$B/.worktrees/c2" && PATH="$T/g2:$PATH" "$T/hooks/post-checkout" ); }
  inj_c3() { co c3; }
  inj_c4() { ( cd "$B/.worktrees/c4" && "$DENY" -p '(version 1)(allow default)(deny file-write-create (regex ".*ft-wt-mode[.]pending[.].*"))' git checkout -q ); }
  inj_c5() { local m; m="$(gd "$B/.worktrees/c5")/ft-wt-mode"; ( cd "$B/.worktrees/c5" && "$DENY" -p "$(deny_at "$m")" git checkout -q ); }
  inj_c6() { ( cd "$B/.worktrees/c6" && PATH="$T/c1:$PATH" "$T/hooks/post-checkout" ); }
  inj_c7() { ( cd "$B/.worktrees/c7" && PATH="$T/c2:$PATH" "$T/hooks/post-checkout" ); }
  site c1 pre_mark inj_c1
  site c2 pre_team inj_c2
  site c3 pre_lock inj_c3
  site c4 pre_none inj_c4
  site c5 pre_none inj_c5
  site c6 pre_mark inj_c6
  site c7 pre_team inj_c7
  cks=$([ "$(grep -cE 'getcfg|putcfg|pre_capture|_ftw_restore|info_bak|info\.\$\$' "$HOOK")" = 0 ] && echo 0 || echo X)
  [ "$cks" = 0 ] && ok "ⓒ2 되돌리기 코드 글자 0(getcfg·putcfg·pre_capture·restore·info_bak)" || bad "ⓒ2 되돌리기 코드 글자 있음"
fi

echo "== ⓓ 실패 뒤 다음 checkout = 같은 목표 재적용 (계약 ④)"
if ft_only ⓓ; then
  wt d1; setmark d1 sparse; touch "$(gd "$B/.worktrees/d1")/info"
  co d1; rc1=$?; m1="$(mark d1)"
  rm -f "$(gd "$B/.worktrees/d1")/info"
  co d1; rc2=$?
  [ "$rc1" != 0 ] && [ "$m1" = sparse ] && [ "$rc2" = 0 ] && [ "$(errn)" = 0 ] && sparse_on "$B/.worktrees/d1" \
    && [ "$(pat d1)" = "$(printf '/*\n!/design/teams/*/')" ] && ok "ⓓ set 실패(정보 파일 자리 충돌) 1회 → 표식 sparse 유지 → 다음 checkout 이 마저 적용(ERROR 0)" \
    || bad "ⓓ rc1=$rc1 rc2=$rc2 표식=$m1 sc=$(git -C "$B/.worktrees/d1" config --bool core.sparseCheckout 2>&1) · $(head -c 200 "$T/e")"
fi

echo "== ⓔ 처음 보는 워크트리 = 목표 정하기 (계약 ⑤)"
if ft_only ⓔ; then
  git -C "$B" config --unset core.sparseCheckout 2>/dev/null; git -C "$B" config --unset extensions.worktreeConfig 2>/dev/null
  wt e1; n0=$( { wc -l < "$LOG"; } 2>/dev/null | tr -d ' ' || echo 0)
  ( cd "$B/.worktrees/e1" && FT_SEAT=seat-t FT_WT_FULL="시험용 풀 체크아웃 사유" git checkout -q ) >"$T/o" 2>"$T/e"; rc=$?
  n1=$( { wc -l < "$LOG"; } 2>/dev/null | tr -d ' ' || echo 0)
  [ "$rc" = 0 ] && [ "$(mark e1)" = "full 시험용 풀 체크아웃 사유" ] && [ "$n1" = $((n0+1)) ] && ! sparse_on "$B/.worktrees/e1" \
    && ok "ⓔ FT_WT_FULL 13자 → 표식 full <사유> · wt-add-full.log 1줄 · sparse 0" || bad "ⓔ rc=$rc 표식=$(mark e1) log=${n0}→${n1} · $(head -c 200 "$T/e")"
  wt e2
  ( cd "$B/.worktrees/e2" && FT_WT_FULL="짧은사유" git checkout -q ) >"$T/o" 2>"$T/e"; rc=$?
  [ "$rc" = 0 ] && [ "$(mark e2)" = sparse ] && grep -q '사유 짧음(4자' "$T/e" && sparse_on "$B/.worktrees/e2" \
    && ok "ⓔ FT_WT_FULL 4자 → 무시 안내 + sparse" || bad "ⓔ 짧음 rc=$rc 표식=$(mark e2) · $(head -c 200 "$T/e")"
  wt e3; b0="$(snap e3)"
  ( cd "$B/.worktrees/e3" && "$DENY" -p "$(deny_at "$(gd "$B/.worktrees/e3")/ft-wt-mode")" git checkout -q ) >"$T/o" 2>"$T/e"; rc=$?
  [ "$rc" != 0 ] && [ "$(errn)" = 1 ] && [ "$b0" = "$(snap e3)" ] && ! sparse_on "$B/.worktrees/e3" \
    && ok "ⓔ 표식 쓰기 실패 = ERROR 1줄 + rc1 + 상태 변경 0(sparse 0)" || bad "ⓔ 쓰기 실패 rc=$rc $b0 → $(snap e3) · $(head -c 200 "$T/e")"
fi

echo "== ⓕ 표식 쓰기 = pending → 읽어 대조 → mv 1회 · 임시 자리 잔존 0 (계약 ⑥)"
if ft_only ⓕ; then
  wt f1; co f1; pend1=$(ls -d "$(gd "$B/.worktrees/f1")"/ft-wt-mode.pending.* 2>/dev/null | wc -l | tr -d ' ')
  wt f2; b0="$(snap f2)"
  ( cd "$B/.worktrees/f2" && "$DENY" -p "$(deny_at "$(gd "$B/.worktrees/f2")/ft-wt-mode")" git checkout -q ) >"$T/o" 2>"$T/e"
  pend2=$(ls -d "$(gd "$B/.worktrees/f2")"/ft-wt-mode.pending.* 2>/dev/null | wc -l | tr -d ' ')
  mvline=$(grep -c 'mv "\$_ftw_pend/ft-wt-mode" "\$_mark"' "$HOOK")
  direct=$(grep -cE '> *"\$_mark"' "$HOOK")
  [ "$pend1" = 0 ] && [ "$pend2" = 0 ] && [ "$mvline" = 1 ] && [ "$direct" = 0 ] && [ "$b0" = "$(snap f2)" ] \
    && ok "ⓕ 성공·실패 모두 pending 잔존 0 · 최종 자리로 mv 1회 · 표식 직접 쓰기 0" || bad "ⓕ pending 성공=$pend1 실패=$pend2 mv줄=$mvline 직접쓰기=$direct"
fi

echo "== ⓖ 훅 자체 점검(회귀 4종 시험은 따로 돈다 — 완료 조건 ⓖ)"
if ft_only ⓖ; then
  lines=$(wc -l < "$HOOK" | tr -d ' ')
  /bin/bash -n "$HOOK" 2>/dev/null; b1=$?
  sh -n "$HOOK" 2>/dev/null; b2=$?
  cmp -s "$STAMP" "$HERE/../bin/ft-wt-mode-stamp.sh"; b3=$?
  [ "$b1" = 0 ] && [ "$b2" = 0 ] && [ "$b3" = 0 ] && [ "$lines" -lt 169 ] \
    && ok "ⓖ /bin/bash 3.2 -n · sh -n · stamp 짝 cmp0 · 훅 ${lines}줄 < 169" || bad "ⓖ bash=$b1 sh=$b2 stamp=$b3 lines=$lines"
fi

echo "== 결과: FAIL=$fail"
ft_only_report || fail=$((fail+1))
[ "${R1030_MUT:-0}" = 1 ] && exit $((fail > 0))

echo "== ⓗ 변이 3(사본 한 줄 · 그 칸이 FAIL 이어야)"
mutate() {  # <이름> <찾을 글자> <바꿀 글자> <FAIL 이어야 할 칸> <그 변이를 보는 시험 칸들>
  ft_only "변이-$1" || return 0
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$SRC" "$d/f"
  python3 - "$d/f" "$2" "$3" <<'PY' || { bad "변이 $1 글자 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  env R1030_MUT=1 R1030_HOOK="$d/f" FT_TEST_ONLY="$5" bash "$0" >"$d/run.txt" 2>&1; local rc=$?
  [ "$rc" != 0 ] && grep -q "^FAIL $4" "$d/run.txt" && ok "변이 $1 → $(grep -m1 "^FAIL $4" "$d/run.txt" | head -c 100)" || bad "변이 $1 이 안 잡혔음 rc=$rc · $(grep -m1 '^FAIL' "$d/run.txt" | head -c 150)"
}
mutate set-fail-rc0 'git sparse-checkout set --no-cone --stdin >/dev/null 2>&1; _tc=$?' 'git sparse-checkout set --no-cone --stdin >/dev/null 2>&1; _tc=0' 'ⓒ c3' 'ⓒ'
mutate pattern-overwrite '  [ -n "$_ftw_out" ] || return 2' '  return 2' 'ⓐ sparse+팀 패턴' 'ⓐ'
mutate set-before-marker '_ftw_write sparse && _ftw_converge' '_ftw_converge && _ftw_write sparse' 'ⓔ 쓰기 실패' 'ⓔ'
echo "== 결과(변이 포함): FAIL=$fail"
[ "$fail" = 0 ]
