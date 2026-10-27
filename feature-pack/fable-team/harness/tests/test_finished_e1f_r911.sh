#!/usr/bin/env bash
# test_finished_e1f_r911.sh — r911 「main 과 파일 단위 내용이 같으면 끝」(판정 2745) = 판정기 E1f 갈래
#   ⓐ squash 착지(카드 착지 줄 없음 · 완성/ 아님) 내용 같음 → FINISHED `E1f ok files=3`
#   ⓑ 바꾼 3 중 1개만 다름 → ACTIVE `E1f no` + 다른 경로 1줄
#   ⓒ 가지가 지운 파일 = main 에도 없음 → 같음 / main 에 있음 → 다름
#   ⓓ E1f 참이어도 E3(좌석)·E0(미커밋) 거짓 → ACTIVE
#   ⓔ git 읽기 실패·시간 초과 → rc2(«안 끝남» 쪽 · 조용한 FINISHED 0)
#   ⓕ ft-branch-archive 가 ⓐ 가지를 refs/archive 로 옮김 · `branch -D` 0 · 폴더는 그대로
#   ⓖ ft-wt-sweep --launchd 재확인 경로가 같은 판정기로 E1f 가지를 옮긴다(코드 변경 0 = 자동 반영)
#   FT_R911_CHK=<스크립트> 로 판정기를 바꿔 «전 빨강»(옛 판) · 변이 빨강을 같은 파일로 잰다.
#   ⓞ rc 계약 — 정상 판정(ACTIVE·ORPHAN·EMPTY·FINISHED) 전부 rc0 · rc1 0 (DA⑥ r4 HOLD 1)
#   ⓟ 호출자 대조 — ft-branch-archive.sh 는 판정기 rc 를 읽지 않고 1행 판정 이름만 본다(rc0/1/2 모두 «FINISHED 아님 = 이동 0»)
# 픽스처 = 임시 리포 + 가짜 tmux·mbox · 실제 워크트리·세션·우편함 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
B="$(cd -- "$HERE/../bin" && pwd)"
CHK="${FT_R911_CHK:-$B/ft-finished-check.sh}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }

# ── 픽스처 ──
R="$T/R"; mkdir -p "$R/design/teams/lecture/indices/완성" "$R/design/teams/lecture/indices/진행" "$R/.fable-team/state" "$T/bin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | h | 현역 |\n| lecture | `design/teams/lecture/` | l | 현역 |\n| v65 | `design/teams/v65/` | v | 현역 |\n' > "$R/design/TEAMS.md"
echo r > "$R/README"; echo g > "$R/g.txt"; echo h > "$R/h.txt"
git -C "$R" init -q -b main && G "$R" add design README g.txt h.txt && G "$R" commit -qm base
git -C "$R" update-ref refs/remotes/origin/main HEAD
printf '#!/bin/sh\n[ -f "%s/tmuxfail" ] && exit 1\n[ "$1" = list-sessions ] && cat "%s/sessions" 2>/dev/null\nexit 0\n' "$T" "$T" > "$T/bin/tmux"; chmod 755 "$T/bin/tmux"; : > "$T/sessions"
printf '#!/bin/sh\necho "$@" >> "%s/mbox.log"\n' "$T" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '{"byz-lecture-master-claude#2":{"role":"master"}}\n' > "$R/.fable-team/seats-lecture.json"
export FT_TMUX_BIN="$T/bin/tmux"
land() { git -C "$R" update-ref refs/remotes/origin/main "$(git -C "$R" rev-parse HEAD)"; }
newbr() { G "$R" branch "nano/$1" "${2:-origin/main}"; }
wt()    { git -C "$R" worktree add -q "$T/wt-$1" "nano/$1"; }
wipe()  { git -C "$R" worktree remove --force "$T/wt-$1" 2>/dev/null; }
card()  { printf '## 상태\n- %s\n' "${2:-진행}" > "$R/design/teams/lecture/indices/${3:-진행}/$1.md"; }
fc() { OUT="$(bash "$CHK" "$1" --repo "$R" 2>&1)"; RC=$?; V="${OUT%%$'\n'*}"; V="${V%% *}"; }
ba() { OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$CHK" bash "$B/ft-branch-archive.sh" "$@" --repo "$R" 2>&1)"; RC=$?; }

# ⓐ 가지가 바꾼 3 파일이 main 과 같은 내용(squash 착지) · 카드 착지 줄 없음 · 완성/ 아님 · 좌석 0
newbr a1-eq; wt a1-eq
for i in 1 2 3; do echo "v$i" > "$T/wt-a1-eq/f$i.txt"; done
G "$T/wt-a1-eq" add f1.txt f2.txt f3.txt && G "$T/wt-a1-eq" commit -qm "a1 3파일"; wipe a1-eq
for i in 1 2 3; do echo "v$i" > "$R/f$i.txt"; done
G "$R" add f1.txt f2.txt f3.txt && G "$R" commit -qm "land a1(squash)"; land
card a1-eq
fc nano/a1-eq
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=3$' && printf '%s' "$OUT" | grep -q '^WARN card '; } \
  && ok "ⓐ 내용 같음(squash 착지·카드 착지 줄 없음) → FINISHED · E1f ok files=3 · WARN 1줄" || bad "ⓐ rc=$RC [$OUT]"

# ⓑ 바꾼 3 중 1개만 다름
newbr b1-part; wt b1-part
for i in 1 2 3; do echo "b$i" > "$T/wt-b1-part/p$i.txt"; done
G "$T/wt-b1-part" add p1.txt p2.txt p3.txt && G "$T/wt-b1-part" commit -qm "b1"; wipe b1-part
echo "b1" > "$R/p1.txt"; echo "b2" > "$R/p2.txt"; echo "OTHER" > "$R/p3.txt"
G "$R" add p1.txt p2.txt p3.txt && G "$R" commit -qm "land b1(1개 다름)"; land
card b1-part
fc nano/b1-part
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=p3.txt$'; } \
  && ok "ⓑ 1개만 다름 → ACTIVE · E1f no files=1 first=p3.txt" || bad "ⓑ [$OUT]"

# ⓒ 지운 파일: main 에도 없음 = 같음 / main 에 있음 = 다름
newbr c1-del-same; wt c1-del-same; git -C "$T/wt-c1-del-same" rm -q g.txt; G "$T/wt-c1-del-same" commit -qm "c1 del g"; wipe c1-del-same
git -C "$R" rm -q g.txt && G "$R" commit -qm "main 도 g 삭제"; land
card c1-del-same; fc nano/c1-del-same
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=1$'; } && ok "ⓒ 가지가 지운 파일을 main 도 지움 → 같음(FINISHED)" || bad "ⓒ1 [$OUT]"
newbr c2-del-diff; wt c2-del-diff; git -C "$T/wt-c2-del-diff" rm -q h.txt; G "$T/wt-c2-del-diff" commit -qm "c2 del h"; wipe c2-del-diff
card c2-del-diff; fc nano/c2-del-diff
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=h.txt$'; } && ok "ⓒ 가지가 지웠는데 main 에 있음 → 다름(ACTIVE)" || bad "ⓒ2 [$OUT]"

# ⓓ E1f 참이어도 E3(좌석 살아 있음)·E0(미커밋) 이 거짓이면 ACTIVE
newbr d1-eq; wt d1-eq; echo d1 > "$T/wt-d1-eq/d1.txt"; G "$T/wt-d1-eq" add d1.txt; G "$T/wt-d1-eq" commit -qm d1; wipe d1-eq
echo d1 > "$R/d1.txt"; G "$R" add d1.txt; G "$R" commit -qm "land d1"; land
card d1-eq
echo 'byz-lecture-nano-d1-eq#0' > "$T/sessions"; fc nano/d1-eq
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f ok' && printf '%s' "$OUT" | grep -q '^E3 no tmux'; } && ok "ⓓ E1f 참 + 좌석 살아 있음 → ACTIVE(E3 no)" || bad "ⓓ 좌석 [$OUT]"
: > "$T/sessions"
newbr d2-eq; wt d2-eq; echo d2 > "$T/wt-d2-eq/d2.txt"; G "$T/wt-d2-eq" add d2.txt; G "$T/wt-d2-eq" commit -qm d2
echo d2 > "$R/d2.txt"; G "$R" add d2.txt; G "$R" commit -qm "land d2"; land
card d2-eq    # 폴더를 남긴 채 미커밋 1개 만들고 판정
echo dirty > "$T/wt-d2-eq/dirty.txt"; fc nano/d2-eq
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E0 no'; } && ok "ⓓ E1f 참 + 미커밋 → ACTIVE(E0 no)" || bad "ⓓ 미커밋 [$OUT]"
rm -f "$T/wt-d2-eq/dirty.txt"; wipe d2-eq

# ⓔ 읽기 실패·시간 초과 → rc2 · 조용한 FINISHED 0
printf '#!/bin/sh\ncase "$*" in *diff*) echo boom >&2; exit 128;; esac\nexec git "$@"\n' > "$T/bin/gitfail"; chmod 755 "$T/bin/gitfail"
OUT="$(FT_FINISHED_GIT="$T/bin/gitfail" bash "$CHK" nano/a1-eq --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q '^ERROR' && ! printf '%s' "$OUT" | grep -q '^FINISHED'; } \
  && ok "ⓔ blob 조회 rc≠0 → rc2 판정 불가(FINISHED 0)" || bad "ⓔ rc=$RC [$OUT]"
printf '#!/bin/sh\ncase "$*" in *diff*) sleep 3;; esac\nexec git "$@"\n' > "$T/bin/gitslow"; chmod 755 "$T/bin/gitslow"
OUT="$(FT_FINISHED_GIT="$T/bin/gitslow" FT_FINISHED_GIT_TIMEOUT_S=0.3 bash "$CHK" nano/a1-eq --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q '시간 초과' && ! printf '%s' "$OUT" | grep -q '^FINISHED'; } \
  && ok "ⓔ 7초 룰(시험값 0.3s) 초과 → rc2 판정 불가(FINISHED 0)" || bad "ⓔ slow rc=$RC [$OUT]"

# ⓓ' 바꾼 파일 0(빈 커밋만) → E1f 대상 아님(카드 규칙으로 ACTIVE) — 옛 시험 test_finished_cleanup_auto ⓓ/ⓔ 와 같은 값
newbr h1-empty; wt h1-empty; G "$T/wt-h1-empty" commit -q --allow-empty -m e; wipe h1-empty
card h1-empty; fc nano/h1-empty
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=0'; } && ok "ⓓ' 빈 커밋만 가지 → E1f 대상 아님(ACTIVE · 카드 규칙)" || bad "ⓓ' [$OUT]"

# ⓕ ft-branch-archive — FINISHED(E1f) 가지를 refs/archive 로 · `branch -D` 0 · 폴더 그대로
newbr f1-eq; wt f1-eq; echo f1 > "$T/wt-f1-eq/q1.txt"; G "$T/wt-f1-eq" add q1.txt; G "$T/wt-f1-eq" commit -qm f1
echo f1 > "$R/q1.txt"; G "$R" add q1.txt; G "$R" commit -qm "land f1"; land
card f1-eq
SHAF="$(git -C "$R" rev-parse nano/f1-eq)"
OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$CHK" bash "$B/ft-branch-archive.sh" nano/f1-eq --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && [ "$(git -C "$R" rev-parse -q --verify refs/archive/nano/f1-eq)" = "$SHAF" ] \
  && [ -d "$T/wt-f1-eq" ] && grep -q '가지 유지' "$R/.fable-team/state/branch-archive.log"; } \
  && ok "ⓕ E1f FINISHED → refs/archive 생성 · 폴더 쓰는 중이라 가지 유지 · 폴더 그대로" || bad "ⓕ rc=$RC [$OUT]"
wipe f1-eq
OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$CHK" bash "$B/ft-branch-archive.sh" nano/f1-eq --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 0 ] && ! git -C "$R" rev-parse -q --verify refs/heads/nano/f1-eq >/dev/null; } && ok "ⓕ 폴더 정리 뒤 같은 판정으로 가지 목록에서 뺌(보관 ref 유지)" || bad "ⓕ2 rc=$RC [$OUT]"
hits="$(grep -nE 'branch[[:space:]]+-D' "$B/ft-branch-archive.sh" "$CHK" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
[ -z "$hits" ] && ok "ⓕ \`git branch -D\` 호출 0" || bad "ⓕ -D $hits"
ba nano/b1-part; { [ "$RC" = 1 ] && git -C "$R" rev-parse -q --verify refs/heads/nano/b1-part >/dev/null; } && ok "ⓕ ACTIVE(E1f no) 가지 → 이동 0" || bad "ⓕ ACTIVE [$OUT]"

# ⓖ ft-wt-sweep --launchd 재확인 경로 — E1f 로 끝난 nano 가지를 같은 판정기로 옮긴다(정리 도구 코드 변경 0)
newbr g1-eq; wt g1-eq; echo g1 > "$T/wt-g1-eq/g1.txt"; G "$T/wt-g1-eq" add g1.txt; G "$T/wt-g1-eq" commit -qm g1; wipe g1-eq
echo g1 > "$R/g1.txt"; G "$R" add g1.txt; G "$R" commit -qm "land g1"; land
card g1-eq
WC="$R/.fable-team/state/wt-clean"; mkdir -p "$WC"
OUT="$(cd "$T" && env FT_ROOT="$R" FT_MBOX_SH="$T/mbox.sh" FT_FINISHED_CHECK="$CHK" FT_WT_SHELL_SCAN_SEC=0 bash "$B/ft-wt-sweep.sh" --launchd 2>&1)"; RC=$?
L="$(tail -1 "$R/.fable-team/state/wt-sweep.log" 2>/dev/null)"
{ [ "$RC" = 0 ] && git -C "$R" rev-parse -q --verify refs/archive/nano/g1-eq >/dev/null && printf '%s' "$L" | grep -qE 'archived=[1-9]' \
  && git -C "$R" rev-parse -q --verify refs/heads/nano/b1-part >/dev/null; } \
  && ok "ⓖ wt-sweep --launchd: E1f 끝난 가지 이동(archived=${L##*archived=}) · ACTIVE 가지는 그대로(정리 도구 코드 변경 0)" || bad "ⓖ rc=$RC log=[$L] out=${OUT:0:300}"

# ⓗ 리포 설정 diff.ignoreSubmodules=all 이어도 서브모듈(gitlink) 변경을 잡는다 (DA⑥ r1 HOLD-①)
SMA="$(git -C "$R" rev-parse HEAD)"
git -C "$R" config diff.ignoreSubmodules all
newbr h1-sub; wt h1-sub
git -C "$T/wt-h1-sub" update-index --add --cacheinfo "160000,$SMA,sub"
G "$T/wt-h1-sub" commit -qm "sub=A"; wipe h1-sub
echo sublevel > "$R/submark"; G "$R" add submark; G "$R" commit -qm "main 기준점"; SMB="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-index --add --cacheinfo "160000,$SMB,sub"; G "$R" commit -qm "main sub=B"; land
card h1-sub; fc nano/h1-sub
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=sub$'; } \
  && ok "ⓗ diff.ignoreSubmodules=all 이어도 gitlink 다름 → ACTIVE(E1f no files=1 first=sub)" || bad "ⓗ [$OUT]"
git -C "$R" config --unset diff.ignoreSubmodules

# ⓘ 501개+ 대량 조회에서 «한쪽은 폴더(tree) · 한쪽은 없음» 을 같음으로 보지 않는다 (DA⑥ r1 HOLD-② · 500 경계 양쪽)
mkbulk() { # $1 = 워크트리/리포 경로 · 나머지 = 개수 — 같은 내용을 양쪽에 만든다
  local d="$1" n="$2" i; mkdir -p "$d/bulk"; for ((i=0;i<n;i++)); do printf 'k%s\n' "$i" > "$(printf '%s/bulk/f%03d.txt' "$d" "$i")"; done; }
# ⓘ-1 작은 쪽(500 이하) = 3 경로 중 1개가 «파일 → 폴더» 로 바뀐 꼴
echo tr2 > "$R/tr2"; G "$R" add tr2; G "$R" commit -qm "tr2 파일"; land
newbr i1-small; wt i1-small; git -C "$T/wt-i1-small" rm -q tr2; echo x > "$T/wt-i1-small/s1.txt"; echo y > "$T/wt-i1-small/s2.txt"
G "$T/wt-i1-small" add -A .; G "$T/wt-i1-small" commit -qm "i1 small"; wipe i1-small
git -C "$R" rm -q tr2; mkdir -p "$R/tr2"; echo n > "$R/tr2/new"; echo x > "$R/s1.txt"; echo y > "$R/s2.txt"
G "$R" add -A .; G "$R" commit -qm "land i1 small(tree)"; land
card i1-small; fc nano/i1-small
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=3$'; } \
  && ok "ⓘ (500 이하) 가지가 파일 tr2 삭제 · main 은 tr2 폴더 → «파일 tr2 = 양쪽 없음» = 같음(FINISHED · DA⑥ r3 §2 파일 단위 정의)" || bad "ⓘ small [$OUT]"
# ⓘ-2 큰 쪽(501 경로 = 경계 초과) — 500 bulk 는 양쪽 같은 내용 · 다른 것은 tr 하나뿐
echo tr > "$R/tr"; G "$R" add tr; G "$R" commit -qm "tr 파일"; land
newbr i2-bulk; wt i2-bulk; git -C "$T/wt-i2-bulk" rm -q tr; mkbulk "$T/wt-i2-bulk" 500
G "$T/wt-i2-bulk" add -A .; G "$T/wt-i2-bulk" commit -qm "i2 501경로"; wipe i2-bulk
git -C "$R" rm -q tr; mkdir -p "$R/tr"; echo n > "$R/tr/new"; mkbulk "$R" 500
G "$R" add -A .; G "$R" commit -qm "land i2(tr=폴더 · bulk 500 같음)"; land
card i2-bulk; fc nano/i2-bulk
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=501$'; } \
  && ok "ⓘ (501 경로) bulk 500 같고 tr 은 «폴더 자체의 차이» → 파일 단위로는 같음(FINISHED · files=501)" || bad "ⓘ bulk [$OUT]"
newbr i3-eq; wt i3-eq; for i in 1 2 3; do echo "z$i" > "$T/wt-i3-eq/z$i.txt"; done
G "$T/wt-i3-eq" add z1.txt z2.txt z3.txt; G "$T/wt-i3-eq" commit -qm "i3 3파일"; wipe i3-eq
for i in 1 2 3; do echo "z$i" > "$R/z$i.txt"; done
G "$R" add z1.txt z2.txt z3.txt; G "$R" commit -qm "land i3(같은 내용)"; land
card i3-eq; fc nano/i3-eq
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=3$'; } \
  && ok "ⓘ 501 경로 가지를 지난 뒤에도 «내용 같음» 판정 그대로(FINISHED · files=3)" || bad "ⓘ 재확인 [$OUT]"

# ⓙ criss-cross(merge-base 2개) → rc2 «판정 불가»(안 끝남 쪽)
JX="$(git -C "$R" rev-parse HEAD)"
newbr jc-a; wt jc-a; echo A > "$T/wt-jc-a/ja.txt"; G "$T/wt-jc-a" add ja.txt; G "$T/wt-jc-a" commit -qm ja; JA="$(git -C "$R" rev-parse nano/jc-a)"; wipe jc-a
newbr jc-b; wt jc-b; echo B > "$T/wt-jc-b/jb.txt"; G "$T/wt-jc-b" add jb.txt; G "$T/wt-jc-b" commit -qm jb; JB="$(git -C "$R" rev-parse nano/jc-b)"; wipe jc-b
TREE="$(git -C "$R" rev-parse "$JX^{tree}")"
M1="$(G "$R" commit-tree "$TREE" -p "$JA" -p "$JB" -m m1)"; M2="$(G "$R" commit-tree "$TREE" -p "$JB" -p "$JA" -m m2)"
git -C "$R" update-ref refs/heads/jc-m1 "$M1"; git -C "$R" update-ref refs/heads/jc-m2 "$M2"
[ "$(git -C "$R" merge-base --all jc-m1 jc-m2 | wc -l | tr -d ' ')" = 2 ] || bad "ⓙ 픽스처: merge-base 2개 아님"
card jc-m2
OUT="$(FT_FINISHED_MAIN=jc-m1 bash "$CHK" jc-m2 --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -q '여러 merge-base' && ! printf '%s' "$OUT" | grep -q '^FINISHED'; } \
  && ok "ⓙ criss-cross(merge-base 2개) → rc2 판정 불가(FINISHED 0)" || bad "ⓙ rc=$RC [$OUT]"

# ⓚ 이름이 pathspec 매직 꼴이어도 «경로로» 읽지 않는다 (DA⑥ r2 HOLD-① · 경로를 git 에 넘기지 않음)
newbr k1-magic; wt k1-magic
( cd "$T/wt-k1-magic" && printf 'A\n' > ':(literal)x' && printf 'A\n' > ':(glob)*' && printf 'A\n' > '*' && printf 'A\n' > '[ab]' && printf 'A\n' > '-x' )
G "$T/wt-k1-magic" add -A .; G "$T/wt-k1-magic" commit -qm "k1 magic 이름 5"; wipe k1-magic
( cd "$R" && printf 'B\n' > ':(literal)x' && printf 'B\n' > ':(glob)*' && printf 'B\n' > '*' && printf 'B\n' > '[ab]' && printf 'B\n' > '-x' )
G "$R" add -A .; G "$R" commit -qm "main magic 이름 5(내용 다름)"; land
card k1-magic; fc nano/k1-magic
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=5 first='; } \
  && ok "ⓚ :(literal)x·:(glob)*·*·[ab]·-x 5개가 main≠tip → ACTIVE(E1f no files=5)" || bad "ⓚ [$OUT]"
newbr k2-magic; wt k2-magic
( cd "$T/wt-k2-magic" && printf 'C\n' > ':(literal)y' && printf 'C\n' > ':(glob)?' && printf 'C\n' > 'w[1]' )
G "$T/wt-k2-magic" add -A .; G "$T/wt-k2-magic" commit -qm "k2 magic 이름 3 같음"; wipe k2-magic
( cd "$R" && printf 'C\n' > ':(literal)y' && printf 'C\n' > ':(glob)?' && printf 'C\n' > 'w[1]' )
G "$R" add -A .; G "$R" commit -qm "main magic 이름 3(같은 내용)"; land
card k2-magic; fc nano/k2-magic
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=3$'; } \
  && ok "ⓚ magic 꼴 이름이 main 과 같은 내용 → FINISHED(E1f ok files=3)" || bad "ⓚ ok [$OUT]"

# ⓛ 경로 5,000개 · 호출 고정 3회 · 전체 마감 70초 (DA⑥ r2 HOLD-②)
mk5000() { python3 - "$1" 5000 <<'PY2'
import os, sys
d = os.path.join(sys.argv[1], "many"); os.makedirs(d, exist_ok=True)
for i in range(int(sys.argv[2])):
    with open(os.path.join(d, "f%04d.txt" % i), "w", encoding="utf-8") as f: f.write("k%d\n" % i)
PY2
}
newbr l1-many; wt l1-many; mk5000 "$T/wt-l1-many"
G "$T/wt-l1-many" add -A .; G "$T/wt-l1-many" commit -qm "l1 5000경로"; wipe l1-many
mk5000 "$R"; G "$R" add -A .; G "$R" commit -qm "land l1(같은 5000)"; land
card l1-many
: > "$T/calls.log"
printf '#!/bin/sh\necho "$*" >> "%s/calls.log"\nsleep 4\nexec git "$@"\n' "$T" > "$T/bin/gitslow4"; chmod 755 "$T/bin/gitslow4"
T0S=$SECONDS
# r5: 대역 각 4초 + 7초/호출 상한은 부하에서 경계에 걸린다(기계 부하로 간헐 빨강) → 이 칸은 «호출 3회 고정» 이 목적이므로 호출 상한만 20초로 올린다(7초 룰 자체는 ⓔ·기본값 칸이 잰다)
OUT="$(FT_FINISHED_GIT="$T/bin/gitslow4" FT_FINISHED_GIT_TIMEOUT_S=20 bash "$CHK" nano/l1-many --repo "$R" 2>&1)"; RC=$?
EL=$((SECONDS - T0S)); CALLS=$(wc -l < "$T/calls.log" | tr -d ' ')
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -q '^E1f ok files=5000$' && [ "$CALLS" = 3 ] && [ "$EL" -lt 70 ]; } \
  && ok "ⓛ 5,000 경로 · git 대역 각 4초 → 호출 3회 · ${EL}초(<70) · FINISHED(ok files=5000)" || bad "ⓛ rc=$RC calls=$CALLS el=${EL}s [$OUT]"
printf '#!/bin/sh\necho "$*" >> "%s/calls.log"\nsleep 2\nexec git "$@"\n' "$T" > "$T/bin/gitslow2"; chmod 755 "$T/bin/gitslow2"
: > "$T/calls.log"
OUT="$(FT_FINISHED_GIT="$T/bin/gitslow2" FT_FINISHED_DEADLINE_S=3 bash "$CHK" nano/l1-many --repo "$R" 2>&1)"; RC=$?
{ [ "$RC" = 2 ] && printf '%s' "$OUT" | grep -qE '총 마감|남은 .*s' && ! printf '%s' "$OUT" | grep -q '^FINISHED'; } \
  && ok "ⓛ 전체 마감(시험값 3s) 초과 → rc2 판정 불가(남은 시간으로 호출을 줄이다 마감 · FINISHED 0)" || bad "ⓛ deadline rc=$RC [$OUT]"
grep -q 'FT_FINISHED_DEADLINE_S:-70' "$CHK" && ok "ⓛ 기본 전체 마감 = 70초(하드 룰 12)" || bad "ⓛ 기본 마감 70 아님"

# ⓜ 비교 단위 = 파일(블롭·심링크·gitlink) — 모드만 다름 · 파일↔심링크 → 다름
newbr m1-mode; wt m1-mode; echo run > "$T/wt-m1-mode/sh.txt"; chmod 755 "$T/wt-m1-mode/sh.txt"
G "$T/wt-m1-mode" add -A .; G "$T/wt-m1-mode" commit -qm "m1 실행권한"; wipe m1-mode
echo run > "$R/sh.txt"; chmod 644 "$R/sh.txt"; G "$R" add -A .; G "$R" commit -qm "land m1(644)"; land
card m1-mode; fc nano/m1-mode
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=sh.txt$'; } \
  && ok "ⓜ 모드(실행권한)만 다름 → ACTIVE(E1f no files=1 first=sh.txt)" || bad "ⓜ mode [$OUT]"
newbr m2-link; wt m2-link; echo target > "$T/wt-m2-link/tgt.txt"; ln -sf tgt.txt "$T/wt-m2-link/ln.txt"
G "$T/wt-m2-link" add -A .; G "$T/wt-m2-link" commit -qm "m2 심링크"; wipe m2-link
echo target > "$R/tgt.txt"; echo tgt.txt > "$R/ln.txt"; G "$R" add -A .; G "$R" commit -qm "land m2(일반 파일)"; land
card m2-link; fc nano/m2-link
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=ln.txt$'; } \
  && ok "ⓜ 파일↔심링크 교체 → ACTIVE(E1f no files=1 first=ln.txt)" || bad "ⓜ link [$OUT]"

# ⓞ rc 계약 = 0 또는 2 뿐 — 정상 판정 네 갈래 전부 rc0 (DA⑥ r4 HOLD 1 · r5)
newbr o1-diff; wt o1-diff; echo o1tip > "$T/wt-o1-diff/o1.txt"; G "$T/wt-o1-diff" add o1.txt; G "$T/wt-o1-diff" commit -qm o1; wipe o1-diff
echo o1main > "$R/o1.txt"; G "$R" add o1.txt; G "$R" commit -qm "land o1(다름)"; land
card o1-diff; fc nano/o1-diff
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -q '^E1f no files=1 first=o1.txt$'; } \
  && ok "ⓞ E1f no + ACTIVE(보통 ASCII 이름) → rc0(1 아님)" || bad "ⓞ ACTIVE rc=$RC [$OUT]"
newbr o2-orphan; wt o2-orphan; echo o2tip > "$T/wt-o2-orphan/o2.txt"; G "$T/wt-o2-orphan" add o2.txt; G "$T/wt-o2-orphan" commit -qm o2; wipe o2-orphan
echo o2main > "$R/o2.txt"; G "$R" add o2.txt; G "$R" commit -qm "land o2(다름)"; land
fc nano/o2-orphan   # 카드 없음 → ORPHAN
{ [ "$RC" = 0 ] && [ "$V" = ORPHAN ]; } && ok "ⓞ 카드 없는 가지(ORPHAN) → rc0" || bad "ⓞ ORPHAN rc=$RC [$OUT]"
newbr o3-empty; fc nano/o3-empty   # 커밋 0 → EMPTY
{ [ "$RC" = 0 ] && [ "$V" = EMPTY ]; } && ok "ⓞ 커밋 0 가지(EMPTY) → rc0" || bad "ⓞ EMPTY rc=$RC [$OUT]"
newbr o4-eq; wt o4-eq; echo o4 > "$T/wt-o4-eq/o4.txt"; G "$T/wt-o4-eq" add o4.txt; G "$T/wt-o4-eq" commit -qm o4; wipe o4-eq
echo o4 > "$R/o4.txt"; G "$R" add o4.txt; G "$R" commit -qm "land o4(같은 내용)"; land
card o4-eq; fc nano/o4-eq
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ]; } && ok "ⓞ E1f 로 끝난 가지(FINISHED) → rc0" || bad "ⓞ FINISHED rc=$RC [$OUT]"
case "$RC" in 0|2) ok "ⓞ 판정기 rc 값역 = {0,2}(rc=$RC · rc1 0)";; *) bad "ⓞ rc 값역 밖: rc=$RC [$OUT]";; esac
grep -qE '^exit 0([[:space:]]|$)' "$CHK" && ok "ⓞ 판정기 마지막 = \`exit 0\`(rc 계약 고정 · 변이 m11 이 이 칸을 빨갛게 한다)" || bad "ⓞ exit 0 줄 없음(rc 계약 미고정)"
grep -qE '^\[ "\$E1F" = 1 \] && \[ "\$V" = FINISHED \] && \{' "$CHK" \
  && bad "ⓞ 옛 159줄 && 사슬 남음 — E1f no 인 정상 판정이 rc1 로 끝난다" \
  || ok "ⓞ 옛 159줄 && 사슬 0(정상 판정이 rc1 로 끝나지 않는다)"

# ⓟ 호출자 대조 — ft-branch-archive.sh 는 판정기 rc 를 읽지 않고 1행 판정 이름만 본다(고칠 것 3 · rc0=판정·rc2=불가 계약과 어긋나지 않음)
bfake() { OUT="$(env FT_ROOT="$R" FT_FINISHED_CHECK="$1" bash "$B/ft-branch-archive.sh" "$2" --repo "$R" 2>&1)"; RC=$?; }
printf '#!/bin/sh\necho "ACTIVE $1"\nexit 1\n' > "$T/bin/chk-rc1"; chmod 755 "$T/bin/chk-rc1"
bfake "$T/bin/chk-rc1" nano/o1-diff
{ [ "$RC" = 1 ] && ! git -C "$R" rev-parse -q --verify refs/archive/nano/o1-diff >/dev/null; } \
  && ok "ⓟ 판정기 rc1 + 1행 ACTIVE → 이동 0(SKIP rc1 · 호출자는 rc 를 안 읽는다)" || bad "ⓟ rc1 rc=$RC [$OUT]"
printf '#!/bin/sh\necho "ERROR 판정 불가"\nexit 2\n' > "$T/bin/chk-err"; chmod 755 "$T/bin/chk-err"
bfake "$T/bin/chk-err" nano/o1-diff
{ [ "$RC" = 1 ] && ! git -C "$R" rev-parse -q --verify refs/archive/nano/o1-diff >/dev/null; } \
  && ok "ⓟ 판정기 rc2 + 1행 ERROR → 이동 0(«판정 불가 = 안 끝남» 계약과 일치)" || bad "ⓟ rc2 rc=$RC [$OUT]"
CHKLINE="$(grep -nE 'bash "\$CHK"' "$B/ft-branch-archive.sh")"
printf '%s' "$CHKLINE" | grep -qE '\$\?|RC=' && bad "ⓟ 호출자가 판정기 rc 를 읽는다: $CHKLINE" \
  || ok "ⓟ 호출자 ft-branch-archive.sh 판정기 호출 줄에 rc 읽기 0(1행 판정 이름만)"


# ⓝ 비 UTF-8 경로 이름(raw-\xff) — 판정은 바이트 집합 · 출력은 \xNN 이스케이프(DA⑥ r3 HOLD)
#   macOS 파일계는 0xff 이름을 거부(Errno 92) → index 에 바이트로 직접 넣어 트리를 만든다(파일계 우회)
#   macOS 파일계는 0xff 이름을 거부(Errno 92 · worktree 체크아웃도 실패) → index 에 바이트로 직접 넣어 트리를 만든다
pathfix() { python3 - "$R" "$1" "$2" "$3" "$4" <<'PY3'
# pathfix <br|main> <브랜치이름|-> <경로(파이썬 바이트 리터럴)> <내용> — 트리에 그 경로 1개를 넣은 커밋
import ast, os, subprocess, sys
repo = os.fsencode(sys.argv[1]); mode, br, raw, body = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
path = ast.literal_eval("b'" + raw + "'")
env = dict(os.environ, GIT_INDEX_FILE=os.path.join(sys.argv[1], ".git", "pathidx"))
def g(*a, inp=None):
    return subprocess.run([b"git", b"-C", repo] + list(a), input=inp, capture_output=True, check=True, env=env).stdout.strip().decode()
base = g(b"rev-parse", b"origin/main" if mode == "br" else b"HEAD")
g(b"read-tree", base)
blob = g(b"hash-object", b"-w", b"--stdin", inp=body.encode() + b"\n")
g(b"update-index", b"--add", b"--cacheinfo", b"100644," + blob.encode() + b"," + path)
tree = g(b"write-tree")
c = subprocess.run([b"git", b"-C", repo, b"-c", b"user.name=t", b"-c", b"user.email=t@t", b"commit-tree", tree.encode(), b"-p", base.encode(), b"-m", ("p-" + mode + "-" + raw).encode()], capture_output=True, check=True, env=env).stdout.strip().decode()
if mode == "br":
    subprocess.run([b"git", b"-C", repo, b"branch", b"-f", ("nano/" + br).encode(), c.encode()], check=True)
else:
    subprocess.run([b"git", b"-C", repo, b"update-ref", b"refs/heads/main", c.encode()], check=True)
os.unlink(os.path.join(sys.argv[1], ".git", "pathidx"))
PY3
}
# ⓝ 비 UTF-8 경로 이름(raw-\xff) — 판정은 바이트 집합 · 출력은 \xNN 이스케이프 (DA⑥ r3 HOLD 1)
pathfix br n1-raw 'raw-\xff' v1; card n1-raw; fc nano/n1-raw
{ [ "$RC" = 0 ] && [ "$V" = ACTIVE ] && printf '%s' "$OUT" | grep -qxF 'E1f no files=1 first=raw-\xff'; } \
  && ok "ⓝ 비 UTF-8 이름(raw-\\xff)이 main 과 다름 → 판정 rc=$RC(2 아님) · ACTIVE · E1f no files=1 first=raw-\\xff" || bad "ⓝ differ rc=$RC [$OUT]"
# 같은 내용(= 끝) 쪽도 예외 없이 판정되어야 한다 — UnicodeEncodeError 로 rc2 가 되면 빨강
pathfix main - 'raw-\xff' v1; land
card n2-raw; fc nano/n1-raw
{ [ "$RC" = 0 ] && [ "$V" = FINISHED ] && printf '%s' "$OUT" | grep -qx 'E1f ok files=1'; } \
  && ok "ⓝ 비 UTF-8 이름이 main 과 같은 내용 → rc0 FINISHED(E1f ok files=1 · UnicodeEncodeError 0)" || bad "ⓝ same rc=$RC [$OUT]"
# 개행이 든 경로도 «1줄» 로 나온다(개수 + 첫 경로 1줄 규약)
pathfix br n3-nl 'nl-\n-x' v1; card n3-nl; fc nano/n3-nl
{ [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qxF 'E1f no files=1 first=nl-\n-x'; } \
  && ok "ⓝ 개행 든 경로 → first=nl-\\n-x (E1f 증거 1줄 유지 · 개수+첫 경로 규약)" || bad "ⓝ newline rc=$RC [$OUT]"

[ $fail -eq 0 ] && echo "ALL PASS" || echo "($fail failed)"
exit $fail
