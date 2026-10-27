#!/usr/bin/env bash
# test_post_checkout_sparse_r835.sh — r835 r3 보장 층: kit/fable-team/githooks/post-checkout 이 «표식(ft-wt-mode) 없는» 팀 워크트리를
#   처음 보는 checkout 에 sparse(`/*` · `!/design/teams/*/`)로 정하고 표식을 남기는가 · 표식 있으면·다른 리포·도구 경로엔 끼어들지 않는가.
#   + ft-wt-mode-stamp.sh(설치 때 1회 기존 워크트리 표식) · ft-nano-spawn 풀 경로 줄(FT_WT_FULL) 실제 줄 eval.
#   픽스처 = mktemp 리포 2(B = design/teams/{a,b,c} · P = 팩 꼴) · core.hooksPath = 키트 post-checkout 사본만 · .beads/hooks/post-checkout 스텁(커밋).
#   실 리포·실 훅 0 · GIT_* env 0. 변이 = 사본 한 줄 → 이 파일 재실행(R835_MUT=1 재귀 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/fable-team"
SRC="$KIT/githooks/post-checkout"
HOOK="${R835_HOOK:-$SRC}"
NANO="${R835_NANO:-$KIT/bin/ft-nano-spawn.sh}"
WT_ADD="$KIT/bin/ft-wt-add.sh"
STAMP="${R835_STAMP:-$KIT/bin/ft-wt-mode-stamp.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
[ -f "$HOOK" ] || { bad "훅 파일 없음: $HOOK"; echo "== 결과: FAIL=$fail"; exit 1; }
mkdir -p "$T/hooks"; cp "$HOOK" "$T/hooks/post-checkout"; chmod +x "$T/hooks/post-checkout"
B="$T/byz"; P="$T/pack"
for r in "$B" "$P"; do
  git init -q -b main "$r"; git -C "$r" config user.name t; git -C "$r" config user.email t@t; git -C "$r" config core.hooksPath "$T/hooks"
  mkdir -p "$r/.beads/hooks"; printf '#!/bin/sh\necho "$(pwd -P) $*" >> "%s/beads.log"\n' "$T" > "$r/.beads/hooks/post-checkout"; chmod +x "$r/.beads/hooks/post-checkout"
  echo x > "$r/README.md"
done
for t in a b c; do mkdir -p "$B/design/teams/$t"; echo "$t" > "$B/design/teams/$t/f.md"; done
for r in "$B" "$P"; do git -C "$r" add -A; git -C "$r" commit -qm init; done
unset FT_R835_SPARSE_HOOK FT_WT_FULL FT_NANO_SPARSE
here() { [ -e "$1" ]; }
sparse_on() { [ "$(git -C "$1" config --bool core.sparseCheckout 2>/dev/null)" = true ]; }
mark() { cat "$(git -C "$1" rev-parse --path-format=absolute --git-dir)/ft-wt-mode" 2>/dev/null; }
beads_n() { grep -c "^$1 " "$T/beads.log" 2>/dev/null; }
r835_n() { grep -c '\[r835\]' "$T/e"; }
LOG="$B/.fable-team/state/wt-add-full.log"
logn() { wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0; }

# sparse_cell <이름> <워크트리> — design/teams/{a,b,c} 디스크 0 · README 있음 · sparseCheckout=true · 표식 sparse · [r835] 1회
sparse_cell() { local w="$2"
  if ! here "$w/design/teams/a" && ! here "$w/design/teams/b" && ! here "$w/design/teams/c" && here "$w/README.md" \
     && sparse_on "$w" && [ "$(mark "$w")" = sparse ] && [ "$(r835_n)" = 1 ]; then ok "$1"
  else bad "$1 — sparse=$(git -C "$w" config --bool core.sparseCheckout 2>&1) a=$(here "$w/design/teams/a" && echo 있음) mark=$(mark "$w") r835=$(r835_n) · e=$(head -c 300 "$T/e")"; fi; }
# full_cell <이름> <워크트리> <표식 값 접두> — b 있음 · sparse 아님 · 표식 · [r835] 안내 0
full_cell() { local w="$2"
  if here "$w/design/teams/b/f.md" && ! sparse_on "$w" && case "$(mark "$w")" in "$3"*) true;; *) false;; esac && ! grep -q '팀 워크트리를 sparse 로' "$T/e"; then ok "$1"
  else bad "$1 — b=$(here "$w/design/teams/b/f.md" && echo 있음) sparse=$(git -C "$w" config --bool core.sparseCheckout 2>&1) mark=$(mark "$w") · e=$(head -c 300 "$T/e")"; fi; }
run() { (cd "${2:-$P}" && bash -c "$1") >"$T/o" 2>"$T/e"; }

echo "== 빠짐 4꼴(DA r1) → sparse + 표식"
run "git --git-dir=\"$B/.git\" worktree add \"$B/.worktrees/e1\" -b e1 main"; sparse_cell "빠짐1 cwd=P · git --git-dir=<B>/.git worktree add" "$B/.worktrees/e1"
[ "$(beads_n "$B/.worktrees/e1")" = 1 ] && ok "beads 위임 1회(빠짐1)" || bad "beads e1=$(beads_n "$B/.worktrees/e1")"
run "W=\"$B\"; git -C \"\$W\" worktree add .worktrees/e2 -b e2 main"; sparse_cell "빠짐2 W=<B>; git -C \"\$W\" worktree add" "$B/.worktrees/e2"
printf '#!/bin/bash\ngit -C "$1" worktree add "$1/.worktrees/e3" -b e3 main\n' > "$T/mk.sh"
run "bash $T/mk.sh $B"; sparse_cell "빠짐3 bash <스크립트 파일> 속 worktree add" "$B/.worktrees/e3"
run "git -C \"$B\" -c alias.wa='worktree add' wa .worktrees/e4 -b e4 main"; sparse_cell "빠짐4 git -c alias.wa='worktree add' wa" "$B/.worktrees/e4"
grep -q "^  자기 팀 폴더 = git -C $B/.worktrees/e4 sparse-checkout add /design/teams/<팀>/ · 다음부터 ft-wt-add.sh <이름> --team <팀>$" "$T/e" && ok "안내 2번째 줄 원문" || bad "안내 줄: $(cat "$T/e")"
[ "$(git -C "$B/.worktrees/e4" sparse-checkout list)" = "$(printf '/*\n!/design/teams/*/')" ] && ok "패턴 2줄(팀 폴더 0 · 추측 0)" || bad "패턴: $(git -C "$B/.worktrees/e4" sparse-checkout list 2>&1)"

echo "== DA r2 반례 ① --no-checkout 뒤 checkout -q"
run "git -C \"$B\" worktree add --no-checkout .worktrees/r1 -b r1 main && git -C \"$B/.worktrees/r1\" checkout -q"
sparse_cell "반례① --no-checkout + checkout -q → sparse · 표식 sparse" "$B/.worktrees/r1"

echo "== DA r2 반례 ③ ft-nano-spawn 풀 경로(실제 줄 eval · FT_WT_FULL)"
NLINE="$(grep -E 'git -C "\$ROOT" worktree add "\$WTDIR" -b "\$BRANCH" "\$BASE_BRANCH" >/dev/null' "$NANO" | head -1)"
[ -n "$NLINE" ] && ok "ft-nano-spawn 풀 경로 줄 찾음" || bad "ft-nano-spawn 풀 경로 줄 없음"
( ROOT="$B" WTDIR="$B/.worktrees/nano-full" BRANCH=nano/full BASE_BRANCH=main _SPT="" IDX_REL=design/teams/a/indices/진행/x.md FT_NANO_SPARSE=0
  eval "$NLINE" ) >"$T/o" 2>"$T/e"
full_cell "반례③ FT_NANO_SPARSE=0 nano 풀 경로 → 풀 · 표식 full" "$B/.worktrees/nano-full" "full nano full(FT_NANO_SPARSE=0"
git -C "$B/.worktrees/nano-full" checkout -q -b nano/full2 >"$T/o" 2>"$T/e"
full_cell "반례③ 다음 checkout 에도 풀 유지" "$B/.worktrees/nano-full" "full "

echo "== 표식 있으면 손대지 않음"
git -C "$B" -c core.hooksPath=/dev/null worktree add -q "$B/.worktrees/old" -b old main 2>/dev/null
bash "$STAMP" --root "$B" >"$T/o" 2>&1
grep -q "^DRY $B/.worktrees/old legacy-full$" "$T/o" && [ -z "$(mark "$B/.worktrees/old")" ] && grep -q "^HAS $B/.worktrees/e1 sparse$" "$T/o" && grep -q '^TOTAL worktrees=.* mode=dry$' "$T/o" \
  && ok "stamp --dry-run(기본) → 목록만 · 표식 0" || bad "stamp dry: $(cat "$T/o")"
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1
[ "$(mark "$B/.worktrees/old")" = legacy-full ] && grep -q "^STAMP $B/.worktrees/old legacy-full$" "$T/o" && grep -q 'mode=apply$' "$T/o" && ok "stamp --apply → legacy-full 표식 · 체크아웃 그대로" || bad "stamp apply: $(cat "$T/o")"
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1
grep -q '^TOTAL worktrees=[0-9]* new=0 has=' "$T/o" && ok "stamp 2회째 new=0(멱등)" || bad "stamp 2회: $(tail -1 "$T/o")"
(cd "$P" && bash "$STAMP") >"$T/o" 2>&1; grep -q '^SKIP .* design/teams/ 없음' "$T/o" && ok "stamp 팩 꼴 리포 = SKIP" || bad "stamp pack: $(cat "$T/o")"
git -C "$B/.worktrees/old" switch -q -c old2 >"$T/o" 2>"$T/e"
full_cell "표식 legacy-full 워크트리에서 git switch → sparse 0" "$B/.worktrees/old" legacy-full
git -C "$B/.worktrees/e2" sparse-checkout disable >/dev/null 2>&1; git -C "$B/.worktrees/e2" checkout -q -b e2b >"$T/o" 2>"$T/e"
here "$B/.worktrees/e2/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/e2" && [ "$(r835_n)" = 0 ] && ok "표식 sparse + 사람이 disable 뒤 checkout → 다시 켜지 않음" || bad "disable 존중 · $(cat "$T/e")"

echo "== FT_WT_FULL 예외"
n0="$(logn)"; (cd "$B" && FT_SEAT=seat-t FT_WT_FULL="시험용 풀 체크아웃 사유" git worktree add -q .worktrees/full -b full main) >"$T/o" 2>"$T/e"
full_cell "FULL 사유 13자 → 풀 · 표식 full <사유>" "$B/.worktrees/full" "full 시험용 풀 체크아웃 사유"
[ "$(logn)" = $((n0+1)) ] && tail -1 "$LOG" | grep -Eq "^[0-9-]+ [0-9:]+ · seat-t · $B/.worktrees/full · 시험용 풀 체크아웃 사유$" && ok "FULL 로그 1줄" || bad "FULL 로그: $(cat "$LOG" 2>&1)"
n0="$(logn)"; (cd "$B" && FT_WT_FULL="아홉글자사유짧음요" git worktree add -q .worktrees/short -b short main) >"$T/o" 2>"$T/e"
sparse_cell "FULL 사유 9자 → 무시하고 sparse" "$B/.worktrees/short"; grep -q '사유 짧음(9자' "$T/e" && [ "$(logn)" = "$n0" ] && ok "«사유 짧음» stderr · 로그 0" || bad "short · $(cat "$T/e")"

echo "== 동작 0 / 도구 경로"
git -C "$B" worktree add -q "$T/outside" -b outside main >"$T/o" 2>"$T/e"
here "$T/outside/design/teams/b/f.md" && ! sparse_on "$T/outside" && [ -z "$(mark "$T/outside")" ] && [ "$(r835_n)" = 0 ] && [ "$(beads_n "$T/outside")" = 1 ] && ok "무동작 .worktrees 밖(ft-scratch-repo 꼴) · beads 1회" || bad "outside · $(cat "$T/e")"
git -C "$P" worktree add -q "$P/.worktrees/p1" -b p1 main >"$T/o" 2>"$T/e"
here "$P/.worktrees/p1/README.md" && ! sparse_on "$P/.worktrees/p1" && [ -z "$(mark "$P/.worktrees/p1")" ] && [ "$(r835_n)" = 0 ] && ok "무동작 팩 꼴 리포(design/teams 없음)" || bad "pack · $(cat "$T/e")"
(cd "$B" && bash "$WT_ADD" wtadd --team a -b wtadd --base main) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ "$(r835_n)" = 0 ] && [ "$(git -C "$B/.worktrees/wtadd" sparse-checkout list)" = "$(printf '/*\n!/design/teams/*/\n/design/teams/a/')" ] && here "$B/.worktrees/wtadd/design/teams/a/f.md" && [ "$(mark "$B/.worktrees/wtadd")" = sparse ] \
  && ok "ft-wt-add --team → 팀 a 패턴 그대로 · 표식 sparse" || bad "ft-wt-add rc=$rc · $(cat "$T/o" "$T/e")"
n0="$(logn)"; (cd "$B" && FT_SEAT=seat-t bash "$WT_ADD" wtfull --full "판정용 전체 사본이 필요함" -b wtfull --base main) >"$T/o" 2>"$T/e"
full_cell "ft-wt-add --full → 풀 · 표식 full" "$B/.worktrees/wtfull" "full 판정용 전체 사본이 필요함"
[ "$(logn)" = $((n0+1)) ] && ok "ft-wt-add --full 로그 1줄(훅·도구 겹침 0)" || bad "wtfull 로그 $(logn) (전 $n0)"
NSP="$(grep -E 'sparse_patterns "\$_SPT" \| git -C "\$WTDIR" sparse-checkout set' "$NANO" | head -1)"
git -C "$B" worktree add --no-checkout "$B/.worktrees/nano" -b nano/x main >/dev/null 2>"$T/e"
printf '/*\n!/design/teams/*/\n/design/teams/b/\n' | git -C "$B/.worktrees/nano" sparse-checkout set --no-cone --stdin >/dev/null 2>>"$T/e" && git -C "$B/.worktrees/nano" checkout -q 2>>"$T/e"
[ -n "$NSP" ] && [ "$(r835_n)" = 0 ] && here "$B/.worktrees/nano/design/teams/b/f.md" && ! here "$B/.worktrees/nano/design/teams/a" && [ "$(mark "$B/.worktrees/nano")" = sparse ] \
  && ok "ft-nano-spawn sparse 꼴(428~429행 명령) → 팀 b 패턴 그대로 · 표식 sparse" || bad "nano 꼴 · $(cat "$T/e")"
git -C "$B" checkout -q -b side main 2>/dev/null; echo y > "$B/README.md"; git -C "$B" commit -qam side; git -C "$B" checkout -q main 2>/dev/null
git -C "$B/.worktrees/full" merge -q --no-edit side >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && full_cell "무동작 merge(풀 워크트리)" "$B/.worktrees/full" "full "
[ -z "$(mark "$B")" ] && ok "주 워크트리 자신은 표식 0(.worktrees 밖)" || bad "주 워크트리 표식 생김"

echo "== r843 표식 쓰기 확인(DA r3 반례 · 못 쓴 표식을 조용히 지나가지 않음)"
gd() { git -C "$1" rev-parse --path-format=absolute --git-dir; }
nohook_wt() { git -C "$B" -c core.hooksPath=/dev/null worktree add -q "$B/.worktrees/$1" -b "$1" main 2>/dev/null; }
nohook_wt m1; M1="$(gd "$B/.worktrees/m1")/ft-wt-mode"; mkdir "$M1"
(cd "$B/.worktrees/m1" && FT_WT_FULL="시험용 풀 체크아웃 사유" git checkout -q -b m1a) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $M1 — 폴더" "$T/e" && ! grep -q '풀 체크아웃 유지' "$T/e" && here "$B/.worktrees/m1/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/m1" \
  && ok "ⓐ1 표식 자리 폴더 + FT_WT_FULL checkout → 표식 자리 이상 · rc≠0 · 풀 그대로" || bad "ⓐ1 rc=$rc · e=$(head -c 300 "$T/e")"
git -C "$B/.worktrees/m1" checkout -q -b m1b >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $M1 — 폴더" "$T/e" && here "$B/.worktrees/m1/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/m1" && [ "$(r835_n)" = 0 ] \
  && ok "ⓐ2 env 없는 다음 checkout → 같은 ERROR · sparse 로 안 바꿈" || bad "ⓐ2 rc=$rc sparse=$(git -C "$B/.worktrees/m1" config --bool core.sparseCheckout 2>&1) · e=$(head -c 300 "$T/e")"
nohook_wt m2; printf '/*\n!/design/teams/*/\n' | git -C "$B/.worktrees/m2" sparse-checkout set --no-cone --stdin >/dev/null 2>&1; M2="$(gd "$B/.worktrees/m2")/ft-wt-mode"; mkdir "$M2"
git -C "$B/.worktrees/m2" checkout -q -b m2a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $M2 — 폴더" "$T/e" && sparse_on "$B/.worktrees/m2" \
  && ok "ⓑ1 이미 sparse(도구가 정함) + 표식 자리 폴더 → 표식 자리 이상 · rc≠0" || bad "ⓑ1 rc=$rc · e=$(head -c 300 "$T/e")"
nohook_wt m6; M6="$(gd "$B/.worktrees/m6")/ft-wt-mode"; ln -s /dev/null "$M6"
git -C "$B/.worktrees/m6" checkout -q -b m6a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $M6 — 심링크" "$T/e" && here "$B/.worktrees/m6/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/m6" \
  && ok "ⓒ1 표식 자리 → /dev/null 심링크 → 표식 자리 이상 · sparse 0" || bad "ⓒ1 rc=$rc sparse=$(git -C "$B/.worktrees/m6" config --bool core.sparseCheckout 2>&1) · e=$(head -c 300 "$T/e")"
nohook_wt m4
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR 표식 자리 이상: $M1 — 폴더" "$T/o" && grep -q "^STAMP $B/.worktrees/m4 legacy-full$" "$T/o" && [ "$(mark "$B/.worktrees/m4")" = legacy-full ] && grep -q '^TOTAL worktrees=.* err=[1-9][0-9]* mode=apply$' "$T/o" \
  && ok "ⓑ2 stamp --apply 표식 자리 폴더 → ERROR 줄 · 쓰기 0 · 다른 워크트리 계속 · 끝 rc≠0" || bad "ⓑ2 stamp rc=$rc · $(cat "$T/o")"
grep -q "^ERROR 표식 자리 이상: $M6 — 심링크" "$T/o" && ! grep -q "^STAMP $B/.worktrees/m6 " "$T/o" \
  && ok "ⓑ3 stamp 표식 자리 /dev/null 심링크 → ERROR(값 안 믿음) · 쓰기 0" || bad "ⓑ3 stamp · $(grep m6 "$T/o")"
nohook_wt m7; M7="$(gd "$B/.worktrees/m7")/ft-wt-mode"; ln -s /dev/null "$M7"
(cd "$B/.worktrees/m7" && FT_WT_FULL="시험용 풀 체크아웃 사유" git checkout -q -b m7a) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $M7 — 심링크" "$T/e" && ! grep -q '풀 체크아웃 유지' "$T/e" && ! sparse_on "$B/.worktrees/m7" \
  && ok "ⓒ2 FT_WT_FULL + 표식 자리 /dev/null 심링크 → 표식 자리 이상 · rc≠0" || bad "ⓒ2 rc=$rc · e=$(head -c 300 "$T/e")"

echo "== r843 r2 (외부 DA r843 r1 반례 · 시험 표식 남김 · checkout 을 안 거치는 풀 생성 길)"
nohook_wt q1; printf 'probe\n' > "$(gd "$B/.worktrees/q1")/ft-wt-mode"
git -C "$B/.worktrees/q1" checkout -q -b q1a >"$T/o" 2>"$T/e"; rc=$?
Q1="$(gd "$B/.worktrees/q1")/ft-wt-mode"
[ "$rc" = 0 ] && ! sparse_on "$B/.worktrees/q1" && here "$B/.worktrees/q1/design/teams/b/f.md" && [ "$(mark "$B/.worktrees/q1")" = probe ] && [ "$(r835_n)" = 0 ] \
  && ok "ⓡ1 남은 표식 값 probe = «있음»(읽힘) → 손대지 않음 · 값 해석 0 · 상태 그대로(r843 r5 DA④)" || bad "ⓡ1 rc=$rc 표식=$(mark "$B/.worktrees/q1") · e=$(head -c 300 "$T/e")"
nohook_wt q3; Q3="$(gd "$B/.worktrees/q3")/ft-wt-mode"; printf 'probe\n' > "$Q3"; chmod 444 "$Q3"
git -C "$B/.worktrees/q3" checkout -q -b q3a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && ! sparse_on "$B/.worktrees/q3" && here "$B/.worktrees/q3/design/teams/b/f.md" && [ "$(mark "$B/.worktrees/q3")" = probe ] \
  && ok "ⓡ3 읽을 수 있는 표식(444) = 있음 → 손대지 않음 · sparse 로 안 바꿈(r843 r5)" || bad "ⓡ3 rc=$rc · e=$(head -c 300 "$T/e")"
chmod 644 "$Q3"
# ⓡ2 = 별도 이름 시험 파일(<표식>.probe.<pid>)을 더 두지 않는다 — 실패 주입도, 남는 파일도 없다(r843 r5 · 표식 자리에 바로 쓰고 다시 읽어 확인)
nohook_wt q2; Q2="$(gd "$B/.worktrees/q2")/ft-wt-mode"
git -C "$B/.worktrees/q2" checkout -q -b q2a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ "$(mark "$B/.worktrees/q2")" = sparse ] && sparse_on "$B/.worktrees/q2" && ! here "$B/.worktrees/q2/design/teams/b" \
  && [ "$(ls "$Q2".probe.* 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && ok "ⓡ2 표식 = sparse · 별도 이름 시험 파일 0(남는 시험 표식 0)" \
  || bad "ⓡ2 rc=$rc 표식=$(mark "$B/.worktrees/q2") sparse=$(git -C "$B/.worktrees/q2" config --bool core.sparseCheckout 2>&1) · e=$(head -c 300 "$T/e")"
git -C "$B/.worktrees/q2" checkout -q -b q2b >"$T/o" 2>"$T/e"
[ "$(r835_n)" = 0 ] && [ "$(mark "$B/.worktrees/q2")" = sparse ] && ok "ⓡ2 다음 checkout → 표식 있음 = 손대지 않음 · 되풀이 0" || bad "ⓡ2 다음 · $(cat "$T/e")"
git -C "$B" worktree add -q --no-checkout "$B/.worktrees/x" -b x main 2>/dev/null; git -C "$B/.worktrees/x" reset -q --hard HEAD >/dev/null 2>&1
nohook_wt q5; printf 'probe\n' > "$(gd "$B/.worktrees/q5")/ft-wt-mode"
nohook_wt q6; mkdir "$(gd "$B/.worktrees/q6")/ft-wt-mode"
bash "$STAMP" --root "$B" --unmarked >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && [ -z "$(mark "$B/.worktrees/x")" ] && ! sparse_on "$B/.worktrees/x" && grep -Eq "^UNMARKED $B/.worktrees/x teams=3 kib=[0-9]+$" "$T/o" \
  && ! grep -q "^UNMARKED $B/.worktrees/q5 " "$T/o" && ! grep -q "^ERROR 표식 자리 이상: $(gd "$B/.worktrees/q5")/ft-wt-mode" "$T/o" \
  && grep -q "^ERROR 표식 자리 이상: $(gd "$B/.worktrees/q6")/ft-wt-mode — 폴더" "$T/o" && ! grep -q "^UNMARKED $B/.worktrees/e1 " "$T/o" && ! grep -q "^UNMARKED $B/.worktrees/old " "$T/o" \
  && ! grep -q "^UNMARKED $B/.worktrees/nano " "$T/o" && grep -Eq '^TOTAL worktrees=[0-9]+ has=[0-9]+ unmarked=[1-9][0-9]* mode=unmarked$' "$T/o" && [ "$(mark "$B/.worktrees/q5")" = probe ] \
  && ok "ⓡ4 --no-checkout + reset --hard(훅 미호출 · 표식 0 · 풀) → --unmarked 목록에 오름 · 표식 폴더 = ERROR 줄 + rc≠0 · 읽히는 값은 해석 0(r843 r5)" || bad "ⓡ4 rc=$rc · $(cat "$T/o")"
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^HAS $B/.worktrees/q5 probe$" "$T/o" && ! grep -q "^STAMP $B/.worktrees/q5 " "$T/o" && grep -q "^STAMP $B/.worktrees/x legacy-full$" "$T/o" \
  && ok "ⓡ5 stamp --apply 읽히는 값 probe = HAS · 쓰기 0 · 다른 워크트리는 계속(r843 r5)" || bad "ⓡ5 · $(grep -E 'q5|/x ' "$T/o")"
bash "$STAMP" --root "$B" --apply --unmarked >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q '^REJECT --apply 와 --unmarked' "$T/o" && ok "ⓡ6 --apply + --unmarked 같이 → REJECT" || bad "ⓡ6 rc=$rc $(cat "$T/o")"

echo "== r843 r4 (외부 DA r843 r2 반례 · 표식 «있음» = -e 또는 -L · 정상 값 아니면 ERROR + 상태 변경 0)"
nohook_wt v1; V1="$(gd "$B/.worktrees/v1")/ft-wt-mode"; printf 'full 판정용 전체 사본이 필요함\n' > "$V1"; chmod 200 "$V1"
git -C "$B/.worktrees/v1" checkout -q -b v1a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $V1 — 못 읽음" "$T/e" && here "$B/.worktrees/v1/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/v1" && [ "$(r835_n)" = 0 ] \
  && ok "ⓡ7 R1 full 표식 0200(못 읽음) → 표식 자리 이상 · rc≠0 · 풀 그대로(안 덮음)" || bad "ⓡ7 rc=$rc sparse=$(git -C "$B/.worktrees/v1" config --bool core.sparseCheckout 2>&1) · e=$(head -c 300 "$T/e")"
git -C "$B/.worktrees/v1" checkout -q -b v1b >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $V1 — 못 읽음" "$T/e" && ! sparse_on "$B/.worktrees/v1" && [ "$(stat -f %z "$V1")" -gt 0 ] \
  && ok "ⓡ8 R1 다음 checkout 도 같은 ERROR · 표식 값 그대로(다시 쓰기 0)" || bad "ⓡ8 rc=$rc · e=$(head -c 300 "$T/e")"
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR 표식 자리 이상: $V1 — 못 읽음" "$T/o" && ! grep -q "^STAMP $B/.worktrees/v1 " "$T/o" && [ "$(stat -f %z "$V1")" -gt 0 ] \
  && ok "ⓡ9 stamp --apply 표식 0200(못 읽음) → ERROR 줄 · 쓰기 0(값 안 바꿈)" || bad "ⓡ9 · $(grep v1 "$T/o")"
chmod 644 "$V1"
nohook_wt v2; V2="$(gd "$B/.worktrees/v2")/ft-wt-mode"; ln -s /nonexistent-ft-wt-mode "$V2"
git -C "$B/.worktrees/v2" checkout -q -b v2a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $V2 — 심링크" "$T/e" && here "$B/.worktrees/v2/design/teams/b/f.md" && ! sparse_on "$B/.worktrees/v2" \
  && ok "ⓡ10 R2 끊긴 심링크 표식 자리 → 표식 자리 이상 · rc≠0 · 풀 그대로" || bad "ⓡ10 rc=$rc · e=$(head -c 300 "$T/e")"
git -C "$B/.worktrees/v2" checkout -q -b v2b >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 자리 이상 $V2 — 심링크" "$T/e" && ! sparse_on "$B/.worktrees/v2" && [ -L "$V2" ] \
  && ok "ⓡ11 R2 다음 checkout 도 같은 ERROR · 심링크 자리 그대로" || bad "ⓡ11 rc=$rc · $(head -c 300 "$T/e")"
nohook_wt v3; chmod 000 "$B/.worktrees/v3/design/teams"
bash "$STAMP" --root "$B" --unmarked >"$T/o" 2>&1; rc=$?
chmod 755 "$B/.worktrees/v3/design/teams"
[ "$rc" != 0 ] && grep -q "^ERROR 팀 폴더 못 읽음: $B/.worktrees/v3/design/teams" "$T/o" && ! grep -q "^UNMARKED $B/.worktrees/v3 " "$T/o" \
  && ok "ⓡ12 R3 design/teams 000 → --unmarked ERROR 줄 + rc≠0(읽기 오류 안 묻음)" || bad "ⓡ12 rc=$rc · $(grep v3 "$T/o")"
mkdir -p "$T/fakecat"; printf '#!/bin/sh\nfor a in "$@"; do case "$a" in */ft-wt-mode) echo other; exit 0;; esac; done\nexec /bin/cat "$@"\n' > "$T/fakecat/cat"; chmod +x "$T/fakecat/cat"
nohook_wt d1
PATH="$T/fakecat:$PATH" git -C "$B/.worktrees/d1" checkout -q -b d1a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 쓰기 실패 — «sparse» 쓰고 다시 읽은" "$T/e" \
  && ok "ⓓ1 훅 표식 쓰기 확인(쓰고 다시 읽어 대조) → 읽은 값이 다르면 ERROR · rc≠0" || bad "ⓓ1 rc=$rc · $(head -c 300 "$T/e")"
nohook_wt d2
PATH="$T/fakecat:$PATH" bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR 표식 쓰기 실패: $(gd "$B/.worktrees/d2")/ft-wt-mode — «legacy-full» 쓰고 다시 읽은 값이 다름" "$T/o" \
  && ok "ⓓ2 stamp --apply 쓰기 확인 → 읽은 값이 다르면 ERROR 표식 쓰기 실패 · rc≠0" || bad "ⓓ2 rc=$rc · $(grep d2 "$T/o")"

echo "== r843 r5 (외부 DA r843 r3 반례 ①②④ · 표식 «먼저» 쓰고 확인 · 값 해석 0)"
# 쓰기 실패 주입 = sandbox-exec 로 «표식 경로만» 쓰기 거부(DA 와 같은 입력) · git 은 정상 동작
DENY="$(command -v sandbox-exec 2>/dev/null | head -1)"
[ -n "$DENY" ] || bad "sandbox-exec 없음 — 반례 ①② 주입 불가(이 시험이 도는 머신에 필요)"
deny_at() { printf '(version 1)(allow default)(deny file-write* (literal "%s"))' "$1"; }
nohook_wt e5; E5="$(gd "$B/.worktrees/e5")/ft-wt-mode"
(cd "$B/.worktrees/e5" && FT_WT_FULL="approved full checkout reason" "$DENY" -p "$(deny_at "$E5")" git checkout -q -b e5a) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 .* 실패 — .*$E5" "$T/e" && ! grep -q '풀 체크아웃 유지' "$T/e" && ! sparse_on "$B/.worktrees/e5" && here "$B/.worktrees/e5/design/teams/b/f.md" && [ -z "$(mark "$B/.worktrees/e5")" ] \
  && ok "ⓔ1 DA① full 선택 + 표식 쓰기만 거부 → ERROR 쓰기 실패 · rc≠0 · 풀 그대로 · 표식 0" || bad "ⓔ1 rc=$rc · $(head -c 300 "$T/e")"
(cd "$B/.worktrees/e5" && "$DENY" -p "$(deny_at "$E5")" git checkout -q -b e5b) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 .* 실패 — .*$E5" "$T/e" && ! sparse_on "$B/.worktrees/e5" && here "$B/.worktrees/e5/design/teams/b/f.md" && [ -z "$(mark "$B/.worktrees/e5")" ] && [ "$(r835_n)" = 0 ] \
  && ok "ⓔ2 DA① env 없는 다음 checkout 도 같은 ERROR · sparse 로 안 덮음(표식 쓰기 실패가 상태를 못 바꿈)" || bad "ⓔ2 rc=$rc sparse=$(git -C "$B/.worktrees/e5" config --bool core.sparseCheckout 2>&1) · $(head -c 300 "$T/e")"
nohook_wt e6; E6="$(gd "$B/.worktrees/e6")/ft-wt-mode"
(cd "$B/.worktrees/e6" && "$DENY" -p "$(deny_at "$E6")" git checkout -q -b e6a) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 .* 실패 — .*$E6" "$T/e" && ! sparse_on "$B/.worktrees/e6" && here "$B/.worktrees/e6/design/teams/b/f.md" && [ -z "$(mark "$B/.worktrees/e6")" ] && [ "$(r835_n)" = 0 ] \
  && ok "ⓔ3 DA② 표식 쓰기 거부 + checkout → ERROR · rc≠0 · sparse 적용 전에 멈춤(상태 변경 0)" || bad "ⓔ3 rc=$rc sparse=$(git -C "$B/.worktrees/e6" config --bool core.sparseCheckout 2>&1) b=$(here "$B/.worktrees/e6/design/teams/b/f.md" && echo 있음) · $(head -c 300 "$T/e")"
nohook_wt e7; E7="$(gd "$B/.worktrees/e7")/ft-wt-mode"; printf 'custom-marker\n' > "$E7"
git -C "$B/.worktrees/e7" checkout -q -b e7a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ -z "$(cat "$T/e")" ] && ! sparse_on "$B/.worktrees/e7" && here "$B/.worktrees/e7/design/teams/b/f.md" && [ "$(mark "$B/.worktrees/e7")" = custom-marker ] \
  && ok "ⓔ4 DA④ 읽히는 표식 custom-marker = 있음 → 손대지 않음 · rc0 · stderr 0 · 값 그대로" || bad "ⓔ4 rc=$rc · $(head -c 300 "$T/e")"
bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1
grep -q "^HAS $B/.worktrees/e7 custom-marker$" "$T/o" && ! grep -q "^STAMP $B/.worktrees/e7 " "$T/o" && ! grep -q "^ERROR 표식 자리 이상: $E7" "$T/o" && [ "$(mark "$B/.worktrees/e7")" = custom-marker ] \
  && ok "ⓔ5 DA④ stamp --apply 도 값 해석 0 → HAS custom-marker · 쓰기 0" || bad "ⓔ5 · $(grep e7 "$T/o")"

echo "== r843 r6 (외부 DA r4 반례 3 · 실패는 fail_closed 한 자리 · pending → mv 1회)"
mkdir -p "$T/rc1cat"; printf '#!/bin/sh\n/bin/cat "$@"\nexit 1\n' > "$T/rc1cat/cat"; chmod +x "$T/rc1cat/cat"
nohook_wt f1; F1="$(gd "$B/.worktrees/f1")/ft-wt-mode"
PATH="$T/rc1cat:$PATH" git -C "$B/.worktrees/f1" checkout -q -b f1a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 쓰기 실패 — «sparse» 쓰고 다시 읽은" "$T/e" && [ ! -e "$F1" ] && ! sparse_on "$B/.worktrees/f1" && [ -z "$(ls -d "$F1".pending.* 2>/dev/null)" ] && here "$B/.worktrees/f1/design/teams/b/f.md" \
  && ok "ⓕ1 DA② 읽기 rc1(출력은 같음) → ERROR · rc≠0 · 표식 0 · pending 잔존 0 · 상태 그대로" || bad "ⓕ1 rc=$rc 표식=$([ -e "$F1" ] && echo 있음 || echo 0) pending=$(ls -d "$F1".pending.* 2>/dev/null | wc -l | tr -d ' ') · $(head -c 300 "$T/e")"
PATH="$T/rc1cat:$PATH" bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR 표식 쓰기 실패: $F1 — «legacy-full»" "$T/o" && [ ! -e "$F1" ] \
  && ok "ⓕ1b stamp --apply 같은 주입 → 읽기 rc≠0 = 실패 · 표식 원복(0)" || bad "ⓕ1b rc=$rc · $(grep f1 "$T/o")"
nohook_wt f4; printf 'sparse\n' > "$(gd "$B/.worktrees/f4")/ft-wt-mode"
PATH="$T/rc1cat:$PATH" bash "$STAMP" --root "$B" --apply >"$T/o" 2>&1; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR 표식 자리 이상: $(gd "$B/.worktrees/f4")/ft-wt-mode — 못 읽음(읽기 rc≠0)" "$T/o" && ! grep -q "^HAS $B/.worktrees/f4" "$T/o" && [ "$(mark "$B/.worktrees/f4")" = sparse ] \
  && ok "ⓕ1c stamp 표식 읽기 rc≠0 → 못 읽음 ERROR · HAS/STAMP 0 · 값 그대로" || bad "ⓕ1c rc=$rc · $(grep f4 "$T/o")"
mkdir -p "$T/quietcat"; printf '#!/bin/sh\nexit 0\n' > "$T/quietcat/cat"; chmod +x "$T/quietcat/cat"
nohook_wt f2; F2="$(gd "$B/.worktrees/f2")/ft-wt-mode"
( cd "$B/.worktrees/f2" && FT_WT_FULL="approved full checkout reason" PATH="$T/quietcat:$PATH" git checkout -q -b f2a ) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode 표식 쓰기 실패" "$T/e" && [ ! -e "$F2" ] && ! sparse_on "$B/.worktrees/f2" && here "$B/.worktrees/f2/design/teams/b/f.md" \
  && ok "ⓕ2 DA② 쓰기 검증 실패(빈 출력) → 빈 표식 0 · 풀 그대로 · rc≠0" || bad "ⓕ2 rc=$rc 표식=$([ -e "$F2" ] && echo 있음 || echo 0) · $(head -c 300 "$T/e")"
( cd "$B/.worktrees/f2" && FT_WT_FULL="approved full checkout reason" PATH="$T/quietcat:$PATH" git checkout -q -b f2b ) >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode" "$T/e" && ! sparse_on "$B/.worktrees/f2" \
  && ok "ⓕ2b 같은 주입 유지한 다음 실행 → 조용한 rc0 0(같은 ERROR 로 처음부터)" || bad "ⓕ2b rc=$rc · $(head -c 300 "$T/e")"
nohook_wt f3; F3="$(gd "$B/.worktrees/f3")/ft-wt-mode"; touch "$(gd "$B/.worktrees/f3")/info"
git -C "$B/.worktrees/f3" checkout -q -b f3a >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" != 0 ] && grep -q "^ERROR ft-wt-mode sparse 설정 실패" "$T/e" && [ ! -e "$F3" ] && [ "$(git -C "$B/.worktrees/f3" config --bool core.sparseCheckout 2>/dev/null || echo unset)" = unset ] && here "$B/.worktrees/f3/design/teams/b/f.md" \
  && ok "ⓕ3 DA② sparse-checkout set 실패 → config 원복(unset) · 표식 0 · rc≠0" || bad "ⓕ3 rc=$rc sc=$(git -C "$B/.worktrees/f3" config --bool core.sparseCheckout 2>&1) 표식=$([ -e "$F3" ] && echo 있음 || echo 0) · $(head -c 300 "$T/e")"
rm -f "$(gd "$B/.worktrees/f3")/info"
git -C "$B/.worktrees/f3" checkout -q -b f3b >"$T/o" 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ "$(mark "$B/.worktrees/f3")" = sparse ] && [ "$(r835_n)" = 1 ] && ! here "$B/.worktrees/f3/design/teams/b" \
  && ok "ⓕ3b 다음 checkout 이 처음부터 다시 적용(sparse · 표식 · [r835] 안내 1회)" || bad "ⓕ3b rc=$rc 표식=$(mark "$B/.worktrees/f3") r835=$(r835_n) · $(head -c 300 "$T/e")"

echo "== 결과: FAIL=$fail"
[ "${R835_MUT:-0}" = 1 ] && exit $((fail > 0))

echo "== 변이(사본 한 줄 · 그 칸이 FAIL 이어야)"
mutate() {  # <이름> <대상 파일> <env 이름> <찾을 글자> <바꿀 글자> <FAIL 이어야 할 칸 접두>
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$2" "$d/f"
  python3 - "$d/f" "$4" "$5" <<'PY' || { bad "변이 $1 글자 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  env R835_MUT=1 "$3=$d/f" bash "$0" >"$d/run.txt" 2>&1; local rc=$?
  [ "$rc" != 0 ] && grep -q "^FAIL $6" "$d/run.txt" && ok "변이 $1 → $(grep -m1 "^FAIL $6" "$d/run.txt" | head -c 120)" || bad "변이 $1 이 안 잡힘 rc=$rc"
}
mutate mark-to-zero-prev "$SRC" R835_HOOK 'if [ -n "$_root" ] && [ -d "$_root/design/teams" ]; then' 'if [ -n "$_root" ] && [ -d "$_root/design/teams" ] && [ "${1:-}" = 0000000000000000000000000000000000000000 ]; then' '반례①'
mutate no-sparse-set "$SRC" R835_HOOK "printf '/*\\n!/design/teams/*/\\n' | git sparse-checkout set --no-cone --stdin >/dev/null 2>&1" 'true' '빠짐1'
mutate legacy-ignored "$SRC" R835_HOOK '  [ -e "$_mark" ] || return 2' '  return 2' 'ⓡ7'
mutate nano-no-full-env "$NANO" R835_NANO 'FT_WT_FULL="nano full(FT_NANO_SPARSE=${FT_NANO_SPARSE:-1} · team=${_SPT:-?}) $IDX_REL" git -C' 'git -C' '반례③'
mutate r843-no-verify "$SRC" R835_HOOK '_ftw_out="$(cat "$1" 2>/dev/null)"; [ "$?" = 0 ]' '_ftw_out="$(cat "$1" 2>/dev/null)"; [ -n "$_ftw_out" ]' 'ⓕ1'
mutate r843-exist-only "$STAMP" R835_STAMP '_o="$(cat "$mark" 2>/dev/null)"; _c=$?' '_o="$(cat "$mark" 2>/dev/null)"; _c=0' 'ⓕ1c'
mutate r843r5-no-state-guard "$SRC" R835_HOOK 'if _ftw_stage sparse; then' 'if true; then' 'ⓔ3'
mutate r843r5-full-swallow "$SRC" R835_HOOK 'if _ftw_stage "full $FT_WT_FULL"; then' '_ftw_stage "full $FT_WT_FULL"; if true; then' 'ⓔ1'
mutate r843r6-fail-noop "$SRC" R835_HOOK '  [ -z "$_ftw_pend" ] || rm -rf "$_ftw_pend" 2>/dev/null
  [ "$_ftw_moved" = 0 ] || rm -f "$_mark" 2>/dev/null' '  :' 'ⓕ1'
mutate r843r5-value-reinterpret "$SRC" R835_HOOK 'if [ -f "$_mark" ] && [ -r "$_mark" ] && head -n 1 "$_mark" >/dev/null 2>&1; then return 0; fi' "if head -n 1 \"\$_mark\" 2>/dev/null | grep -qx 'sparse\|legacy-full'; then return 0; fi" 'ⓔ4'
mutate r843r4-no-dir-check "$SRC" R835_HOOK 'if [ -d "$_mark" ]; then _ftw_slot_bad "폴더(일반 파일 아님)"; return 1; fi' 'if false; then _ftw_slot_bad "폴더(일반 파일 아님)"; return 1; fi' 'ⓐ1'
mutate r843r4-exist-only "$SRC" R835_HOOK 'if [ -L "$_mark" ]; then _ftw_slot_bad "심링크 표식 자리(일반 파일 아님)"; return 1; fi' 'if false; then _ftw_slot_bad "심링크 표식 자리(일반 파일 아님)"; return 1; fi' 'ⓡ10'
mutate r843r2-unm-teams "$STAMP" R835_STAMP '[ "$tn" -ge 2 ] || continue' 'continue' 'ⓡ4'
mutate r843r5-stamp-value "$STAMP" R835_STAMP 'if [ "$_c" = 0 ]; then cur="$(printf '\''%s'\'' "$_o" | head -n 1)"; slot=ok' 'if [ "$_c" = 0 ]; then cur="$(printf '\''%s'\'' "$_o" | head -n 1)"; case "$cur" in sparse|legacy-full) slot=ok;; *) slot=bad; why="정상 값 아님";; esac' 'ⓔ5'
mutate r843r4-stamp-read-absent "$STAMP" R835_STAMP 'elif [ -e "$mark" ]; then' 'elif [ -f "$mark" ] && [ -r "$mark" ]; then' 'ⓡ9'
mutate r843r4-unm-swallow "$STAMP" R835_STAMP 'if [ "$err" -ne 0 ]; then echo "ERROR 표식·읽기 실패' 'if false; then echo "ERROR 표식·읽기 실패' 'ⓡ12'
mutate r843-rc0 "$SRC" R835_HOOK 'exit "$_ftw_rc"' 'exit 0' 'ⓐ1'
mutate r843-stamp-no-verify "$STAMP" R835_STAMP '[ "$?" = 0 ] && [ "$_o" = "$v" ]' 'true' 'ⓓ2'
mutate r843-stamp-rc0 "$STAMP" R835_STAMP '[ "$err" = 0 ]' 'true' 'ⓑ2'
echo "== 결과(변이 포함): FAIL=$fail"
[ "$fail" = 0 ]
