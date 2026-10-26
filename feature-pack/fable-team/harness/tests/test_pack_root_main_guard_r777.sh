#!/usr/bin/env bash
# test_pack_root_main_guard_r777.sh — 팩 루트 main 직접 커밋 거절 훅 + 설치 갈래(--pack-hooks) 시험 (r777)
# 임시 «팩» 리포 + 워크트리만 쓴다 — 머신의 실제 팩 리포·실 git config 접촉 0(GIT_CONFIG_GLOBAL/SYSTEM 격리 · ⓘ 가 실 경로 0 을 확인).
# 대응표: ① 작업 폴더 커밋 통과 = ⓓ · ② 루트 main 거절·표지 통과·다른 가지 통과 = ⓒ ⓔ ⓛ · ③ 없는 hooksPath = ERROR 1줄 = ⓕ
#         ④ 설치 = .git/hooks/pre-commit cmp0 · 기존 훅 불변 · dry-run 쓰기 0 = ⓐ ⓑ · ⑤ 변이 2 = ⓙ(ⓛ 이 잡음) ⓚ(ⓔ 가 잡음)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HROOT="$(cd "$HERE/.." && pwd -P)"
INSTALL="$HROOT/install.sh"
KIT="$HROOT/kit/fable-team"
HOOK="$KIT/githooks/pack/pack-pre-commit"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$INSTALL" && ok "bash -n install.sh" || bad "bash -n install.sh"
bash -n "$HOOK" && ok "bash -n pack-pre-commit" || bad "bash -n pack-pre-commit"
[ -x "$HOOK" ] && ok "키트 팩 훅 실행 비트" || bad "키트 팩 훅 실행 비트 없음"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
GC=(-c user.email=t@t -c user.name=t -c commit.gpgsign=false)

# 「팩」 리포: 루트 체크아웃(main) + 작업 폴더 .worktrees/x (가지 nano/x) + 기존 훅 2개(cairn 자리)
P="$T/pack"; git init -q -b main "$P"; PR="$(cd "$P" && pwd -P)"
printf 'a\n' > "$P/a.txt"; git -C "$P" add a.txt; git -C "$P" "${GC[@]}" commit -qm init
git -C "$P" worktree add -q "$P/.worktrees/x" -b nano/x
printf '#!/bin/sh\nexit 0\n' > "$P/.git/hooks/post-checkout"; chmod 755 "$P/.git/hooks/post-checkout"
printf '#!/bin/sh\nexit 0\n' > "$P/.git/hooks/post-merge";    chmod 755 "$P/.git/hooks/post-merge"
sha_before="$(cat "$P/.git/hooks/post-checkout" "$P/.git/hooks/post-merge" | shasum | cut -d' ' -f1)"

# run_commit <dir> [ENV=VAL…] — pre-commit 이 도는 실제 커밋(빈 커밋). 출력은 OUT, rc 는 전역 rc
run_commit() { local d="$1"; shift; OUT="$( ( cd "$d" && env "$@" git "${GC[@]}" commit -q --allow-empty -m m 2>&1 ) )"; rc=$?; }

# ⓠ 지금 판(훅 없음) = 루트 main 커밋이 «성공»한다 — 훅이 없으면 사고가 난다는 대조(빨강 먼저)
run_commit "$P"
[ "$rc" = 0 ] && ok "ⓠ 훅 없음: 루트 main 커밋 통과(대조 = 고치기 전 판)" || bad "ⓠ 훅 없음인데 rc=$rc :: $OUT"

# ⓐ dry-run(기본) = 쓰기 0 · PACK-HOOKS 줄 · 훅 파일 미생성 · hooksPath 그대로
head0="$(git -C "$P" rev-parse HEAD)"   # ⓠ 커밋까지 반영한 기준(아래 «커밋 0» 판정)
[ ! -f "$P/.git/hooks/pre-commit" ] || bad "ⓐ 시작 전 pre-commit 이 이미 있다"
OUT="$(bash "$INSTALL" --pack-hooks "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ⓐ dry-run rc=0" || bad "ⓐ dry-run rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "PACK-HOOKS $PR/.git/hooks/pre-commit <- $HOOK (dry-run · 쓰기 0)" && ok "ⓐ PACK-HOOKS PLAN 줄" || bad "ⓐ PACK-HOOKS 줄 :: $OUT"
[ ! -f "$P/.git/hooks/pre-commit" ] && ok "ⓐ dry-run: pre-commit 미생성" || bad "ⓐ dry-run 이 훅을 씀"
[ -z "$(git -C "$P" config --get core.hooksPath || true)" ] && ok "ⓐ dry-run: core.hooksPath 불변" || bad "ⓐ dry-run 이 config 를 씀"

# ⓑ --apply = .git/hooks/pre-commit = 키트 훅 cmp0 · 실행 비트 · 기존 훅 2개 바이트 불변
OUT="$(bash "$INSTALL" --apply --pack-hooks "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ⓑ apply rc=0" || bad "ⓑ apply rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qE '^PACK-HOOKS installed cmp=0 exec=yes hooksPath=unset$' && ok "ⓑ 설치 요약 줄" || bad "ⓑ 설치 요약 줄 :: $OUT"
cmp -s "$HOOK" "$P/.git/hooks/pre-commit" && ok "ⓑ 설치본 = 키트 훅 cmp0" || bad "ⓑ 설치본 != 키트 훅"
[ -x "$P/.git/hooks/pre-commit" ] && ok "ⓑ 설치본 실행 비트" || bad "ⓑ 설치본 실행 비트 없음"
sha_after="$(cat "$P/.git/hooks/post-checkout" "$P/.git/hooks/post-merge" | shasum | cut -d' ' -f1)"
[ "$sha_before" = "$sha_after" ] && ok "ⓑ 기존 post-checkout·post-merge 불변" || bad "ⓑ 기존 훅이 바뀜"

# ⓒ 루트 체크아웃 main 커밋 = REJECT rc≠0 · 커밋 0 · 안내 1줄
run_commit "$P"
[ "$rc" != 0 ] && ok "ⓒ 루트 main 커밋 거절 rc=$rc" || bad "ⓒ 루트 main 커밋이 통과했다(rc=0)"
printf '%s' "$OUT" | grep -qF "REJECT 팩 루트 main 직접 커밋" && ok "ⓒ REJECT 안내 1줄" || bad "ⓒ REJECT 안내 없음 :: $OUT"
printf '%s' "$OUT" | grep -qF ".worktrees/<slug>" && ok "ⓒ 작업 폴더 안내 포함" || bad "ⓒ 작업 폴더 안내 없음"
[ "$(git -C "$P" rev-parse HEAD)" = "$head0" ] && ok "ⓒ 루트 main 커밋 0(HEAD 불변)" || bad "ⓒ 루트 main 에 커밋이 쌓였다"

# ⓓ 작업 폴더(.worktrees/x) nano/x 커밋 = 통과
run_commit "$P/.worktrees/x"
[ "$rc" = 0 ] && ok "ⓓ 작업 폴더 커밋 통과(rc=0)" || bad "ⓓ 작업 폴더 커밋 거절 rc=$rc :: $OUT"

# ⓔ 루트 main 이어도 표지 FT_PACK_ROOT_COMMIT=1 = 통과(정상 착지 도구 길)
run_commit "$P" FT_PACK_ROOT_COMMIT=1
[ "$rc" = 0 ] && ok "ⓔ 표지 1 = 루트 main 커밋 통과" || bad "ⓔ 표지 1 인데 거절 rc=$rc :: $OUT"
git -C "$P" reset -q --hard "$head0"   # 표지로 쌓인 빈 커밋 되돌림(아래 판정을 head0 기준으로)

# ⓕ core.hooksPath 가 «없는 폴더» → dry-run ERROR 1줄 + rc1 + 쓰기 0 → apply = 해제 + 훅 설치 + 거절 동작
P2="$T/pack2"; git init -q -b main "$P2"
printf 'a\n' > "$P2/a.txt"; git -C "$P2" add a.txt; git -C "$P2" "${GC[@]}" commit -qm init
git -C "$P2" config core.hooksPath /githooks
OUT="$(bash "$INSTALL" --pack-hooks "$P2" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "ⓕ dry-run: 없는 hooksPath → rc=1" || bad "ⓕ dry-run rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "ERROR core.hooksPath=/githooks 폴더 없음" && ok "ⓕ ERROR 1줄(조용히 꺼진 채 두지 않음)" || bad "ⓕ ERROR 줄 없음 :: $OUT"
[ ! -f "$P2/.git/hooks/pre-commit" ] && [ "$(git -C "$P2" config --get core.hooksPath)" = /githooks ] && ok "ⓕ dry-run 쓰기 0" || bad "ⓕ dry-run 이 고쳤다"
OUT="$(bash "$INSTALL" --apply --pack-hooks "$P2" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -qF "HEALED core.hooksPath 해제" && ok "ⓕ apply = HEALED rc=0" || bad "ⓕ apply :: rc=$rc $OUT"
[ -z "$(git -C "$P2" config --get core.hooksPath || true)" ] && ok "ⓕ apply 뒤 core.hooksPath 해제됨" || bad "ⓕ hooksPath 그대로"
cmp -s "$HOOK" "$P2/.git/hooks/pre-commit" && ok "ⓕ apply 뒤 .git/hooks/pre-commit cmp0" || bad "ⓕ 훅 미설치"
head2="$(git -C "$P2" rev-parse HEAD)"; run_commit "$P2"
[ "$rc" != 0 ] && [ "$(git -C "$P2" rev-parse HEAD)" = "$head2" ] && ok "ⓕ 고친 리포에서 루트 main 커밋 거절" || bad "ⓕ 고친 리포인데 커밋 통과 rc=$rc"

# ⓖ 멱등: 같은 apply 2회째 = rc0 · cmp0 · 요약 줄 그대로
OUT="$(bash "$INSTALL" --apply --pack-hooks "$P" 2>&1)"; rc=$?
[ "$rc" = 0 ] && cmp -s "$HOOK" "$P/.git/hooks/pre-commit" && ok "ⓖ 2회째 멱등(cmp0)" || bad "ⓖ 2회째 :: rc=$rc $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^PACK-HOOKS installed')" = 1 ] && ok "ⓖ 요약 줄 1줄" || bad "ⓖ 요약 줄 개수"

# ⓗ usage: --pack-hooks 와 --project 동시 = rc2(쓰기 0) · 인자 없음 = rc2
OUT="$(bash "$INSTALL" --pack-hooks "$P" --project "$P" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "ⓗ --pack-hooks + --project = rc2" || bad "ⓗ 동시 사용 rc=$rc :: $OUT"
OUT="$(bash "$INSTALL" --bogus 2>&1)"; rc=$?
[ "$rc" = 2 ] && printf '%s' "$OUT" | grep -qF -- "--pack-hooks <팩 리포>" && ok "ⓗ usage 에 --pack-hooks 갈래 표기" || bad "ⓗ usage :: rc=$rc $OUT"

# ⓘ 실 팩 리포·실 config 접촉 0: 이 시험 파일이 실 경로를 안 쓴다(경로 문자열은 쪼개서 검색 — 자기 줄에 안 걸리게)
_RE='ai-feature-'
grep -qF "/Project/${_RE}pack" "${BASH_SOURCE[0]:-$0}" && bad "ⓘ 시험 파일이 실 팩 리포 경로를 쓴다" || ok "ⓘ 실 팩 리포 경로 0"
unset _RE

# ⓛ 루트 체크아웃이라도 가지가 main 이 아니면 통과(거절 범위 = main 하나)
git -C "$P" checkout -q -b side
run_commit "$P"
[ "$rc" = 0 ] && ok "ⓛ 루트 체크아웃 다른 가지(side) 커밋 통과" || bad "ⓛ side 커밋 거절 rc=$rc :: $OUT"
git -C "$P" checkout -q main; git -C "$P" reset -q --hard "$head0"

# ⓙ 변이 1: 가지 비교 줄 삭제 → 다른 가지 커밋까지 거절(과차단) = ⓛ 이 잡는다
M1="$T/mut1"; grep -vF '[ "$_br" = main ] || exit 0' "$HOOK" > "$M1"
[ "$(grep -c . "$M1")" -lt "$(grep -c . "$HOOK")" ] && ok "ⓙ 변이 1 생성(가지 비교 삭제)" || bad "ⓙ 변이 1 미생성"
cp "$M1" "$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
git -C "$P" checkout -q -b side2
run_commit "$P"
[ "$rc" != 0 ] && ok "ⓙ 변이 1 = 다른 가지도 거절 → ⓛ FAIL(변이 잡힘)" || bad "ⓙ 변이 1 인데도 통과 — 시험이 변이를 못 잡는다"
git -C "$P" checkout -q main; git -C "$P" branch -qD side2 2>/dev/null; git -C "$P" reset -q --hard "$head0"

# ⓚ 변이 2: 표지 검사 줄 삭제 → FT_PACK_ROOT_COMMIT=1 인데 거절(= ⓔ 가 잡는다)
M2="$T/mut2"; grep -vF '[ "${FT_PACK_ROOT_COMMIT:-0}" = 1 ] && exit 0' "$HOOK" > "$M2"
[ "$(grep -c . "$M2")" -lt "$(grep -c . "$HOOK")" ] && ok "ⓚ 변이 2 생성(표지 검사 삭제)" || bad "ⓚ 변이 2 미생성"
cp "$M2" "$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
run_commit "$P" FT_PACK_ROOT_COMMIT=1
[ "$rc" != 0 ] && ok "ⓚ 변이 2 = 표지 커밋 거절 → ⓔ FAIL(변이 잡힘)" || bad "ⓚ 변이 2 인데도 통과 — 시험이 변이를 못 잡는다"
git -C "$P" reset -q --hard "$head0"

# 되돌림: 키트 판 재설치 = 원상(연속 시험 안전)
cp "$HOOK" "$P/.git/hooks/pre-commit"; chmod +x "$P/.git/hooks/pre-commit"
cmp -s "$HOOK" "$P/.git/hooks/pre-commit" && ok "끝: 키트 판 복원 cmp0" || bad "끝: 복원 실패"

echo "---"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
