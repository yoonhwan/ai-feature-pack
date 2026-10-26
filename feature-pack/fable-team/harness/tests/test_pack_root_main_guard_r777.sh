#!/usr/bin/env bash
# test_pack_root_main_guard_r777.sh — 팩 루트 main 직접 커밋 거절 훅 + 설치 갈래(--pack-hooks) 시험 (r777)
# 임시 «팩» 리포 + 워크트리만 쓴다 — 머신의 실제 팩 리포·실 git config 접촉 0(GIT_CONFIG_GLOBAL/SYSTEM 격리 · ⓘ 가 실 경로 0 을 확인).
# 대응표: ① 작업 폴더 커밋 통과 = ⓓ · ② 루트 main 거절·표지 통과·다른 가지 통과 = ⓒ ⓔ ⓛ · ③ 없는 hooksPath = ERROR 1줄 = ⓕ
#         ④ 설치 = .git/hooks/pre-commit cmp0 · 기존 훅 불변 · dry-run 쓰기 0 = ⓐ ⓑ · ⑤ 변이 3 = ⓙ(ⓛ)·ⓚ(ⓔ)·ⓜ(G2)
#   r1 추가(DA⑥ HOLD): G1 실재 다른 훅 폴더 = rc1 쓰기 0 · G2 포함 설정 없는 폴더 = rc1·HEALED 0 · G3 전역 설정 없는 폴더 = rc1
#   r2 추가(오빠 결정 10-27 07:4x · 계약 ③): ⓝ core.hooksPath=.git/hooks 명시 + 그 폴더 없음 = ERROR 1줄 · 변이 4
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

T="$(mktemp -d)"; MUT_INST="$HROOT/.mut-r777.sh"; trap 'rm -rf "$T"; rm -f "$MUT_INST"' EXIT
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
printf '%s\n' "$OUT" | grep -qF "ERROR core.hooksPath 폴더 없음 — git 이 보는 훅 자리 = /githooks" && ok "ⓕ ERROR 1줄(조용히 꺼진 채 두지 않음)" || bad "ⓕ ERROR 줄 없음 :: $OUT"
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


# ══ r1(DA⑥ HOLD) 칸 3: 훅 자리 판단 = `git rev-parse --path-format=absolute --git-path hooks` ══
newpack() { local d="$1"; git init -q -b main "$d"; printf 'a\n' > "$d/a.txt"; git -C "$d" add a.txt; git -C "$d" "${GC[@]}" commit -qm init; }
apk() { OUT="$(bash "$INSTALL" --apply --pack-hooks "$1" 2>&1)"; rc=$?; }

# G1 실재하는 다른 훅 폴더(core.hooksPath=.custom-hooks) = 덮지도 지우지도 않고 rc1 · 쓰기 0 · 그 폴더 파일 불변
G1="$T/packG1"; newpack "$G1"; mkdir -p "$G1/.custom-hooks"
printf '#!/bin/sh\nexit 0\n' > "$G1/.custom-hooks/pre-commit"; chmod 755 "$G1/.custom-hooks/pre-commit"
g1_before="$(cat "$G1/.custom-hooks/pre-commit" | shasum | cut -d' ' -f1)"
git -C "$G1" config core.hooksPath .custom-hooks
apk "$G1"
[ "$rc" = 1 ] && ok "G1 실재 다른 훅 폴더 → rc=1" || bad "G1 rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "실재 — 그 폴더의 훅을 끄지 않으려면 사람이 정한다(쓰기 0)" && ok "G1 사람 판정 안내 1줄" || bad "G1 안내 줄 없음 :: $OUT"
[ ! -f "$G1/.git/hooks/pre-commit" ] && ok "G1 .git/hooks/pre-commit 미생성(쓰기 0)" || bad "G1 이 .git/hooks 에 썼다"
[ "$(cat "$G1/.custom-hooks/pre-commit" | shasum | cut -d' ' -f1)" = "$g1_before" ] && ok "G1 그 폴더 파일 불변" || bad "G1 그 폴더 파일을 덮었다"
[ "$(git -C "$G1" config --get core.hooksPath)" = .custom-hooks ] && ok "G1 core.hooksPath 불변" || bad "G1 config 를 건드렸다"

# G2 포함 설정(include.path)이 «없는 폴더» 를 가리킴 = unset 으로 못 지움 → rc1 · HEALED 0 · installed 보고 0
G2="$T/packG2"; newpack "$G2"; printf '[core]\n\thooksPath = /no-such-hooks-r777\n' > "$T/inc.cfg"
git -C "$G2" config include.path "$T/inc.cfg"
apk "$G2"
[ "$rc" = 1 ] && ok "G2 포함 설정 → rc=1" || bad "G2 rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "PACK-HOOKS 자리불일치 now=/no-such-hooks-r777" && ok "G2 자리불일치 ERROR(출처 포함)" || bad "G2 자리불일치 줄 없음 :: $OUT"
printf '%s\n' "$OUT" | grep -qF "$T/inc.cfg" && ok "G2 ERROR 에 출처 파일 원문" || bad "G2 출처 파일 표기 없음 :: $OUT"
printf '%s\n' "$OUT" | grep -q "HEALED" && bad "G2 «HEALED» 를 찍었다" || ok "G2 «HEALED» 0"
printf '%s\n' "$OUT" | grep -q "PACK-HOOKS installed" && bad "G2 설치됐다고 보고했다" || ok "G2 installed 보고 0(조용한 통과 0)"
run_commit "$G2"
[ "$rc" = 0 ] && ok "G2 그 리포의 루트 main 커밋은 여전히 통과(= rc1 이 옳다)" || bad "G2 커밋 rc=$rc — 전제가 달라졌다"

# G3 전역 설정(GIT_CONFIG_GLOBAL)이 «없는 폴더» 를 가리킴 = 로컬 unset 으로 못 지움 → rc1 · HEALED 0
git config --global core.hooksPath /no-such-global-hooks-r777
G3="$T/packG3"; newpack "$G3"; apk "$G3"
[ "$rc" = 1 ] && ok "G3 전역 설정 → rc=1" || bad "G3 rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "PACK-HOOKS 자리불일치 now=/no-such-global-hooks-r777" && ok "G3 자리불일치 ERROR(출처 전역)" || bad "G3 자리불일치 줄 없음 :: $OUT"
printf '%s\n' "$OUT" | grep -q "HEALED" && bad "G3 «HEALED» 를 찍었다" || ok "G3 «HEALED» 0"
git config --global --unset core.hooksPath

# ⓜ 변이 3: 설치 «뒤» --git-path hooks 검사 줄 삭제 → 포함 설정(G2) 리포가 rc0·installed 로 조용히 통과 = G2 FAIL
grep -vF 'PACK-HOOKS 자리불일치' "$INSTALL" > "$MUT_INST"
[ "$(grep -c . "$MUT_INST")" -lt "$(grep -c . "$INSTALL")" ] && ok "ⓜ 변이 3 생성(자리 검사 삭제)" || bad "ⓜ 변이 3 미생성"
bash -n "$MUT_INST" || bad "ⓜ 변이 3 bash -n"
G2M="$T/packG2m"; newpack "$G2M"; git -C "$G2M" config include.path "$T/inc.cfg"
OUT="$(bash "$MUT_INST" --apply --pack-hooks "$G2M" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -q "PACK-HOOKS installed" && ok "ⓜ 변이 3 = 못 도는 자리에 installed rc0 → G2 FAIL(변이 잡힘)" || bad "ⓜ 변이 3 인데도 rc=$rc :: $OUT"
rm -f "$MUT_INST"


# ⓝ DA⑥ r2 재현(계약 ③): core.hooksPath=.git/hooks 를 «명시» 했고 그 폴더가 없다 → dry-run ERROR 1줄 rc1 · apply = ERROR + 설치 cmp0 + 거절
DN="$T/packDA"; mkdir -p "$T/emptytpl"
git init -q -b main --template="$T/emptytpl" "$DN"
printf 'a\n' > "$DN/a.txt"; git -C "$DN" add a.txt; git -C "$DN" "${GC[@]}" commit -qm init
git -C "$DN" config core.hooksPath .git/hooks
[ ! -d "$DN/.git/hooks" ] && ok "ⓝ 전제: .git/hooks 폴더 없음(빈 템플릿 init)" || bad "ⓝ 전제가 다르다(.git/hooks 가 있다)"
OUT="$(bash "$INSTALL" --pack-hooks "$DN" 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "ⓝ dry-run: 폴더 없음 → rc=1" || bad "ⓝ dry-run rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "ERROR core.hooksPath 폴더 없음 — git 이 보는 훅 자리 = " && ok "ⓝ ERROR 1줄(기본 자리와 같아도)" || bad "ⓝ ERROR 줄 없음 :: $OUT"
printf '%s\n' "$OUT" | grep -qF "출처 file:.git/config .git/hooks" && ok "ⓝ 출처 원문(--show-origin)" || bad "ⓝ 출처 원문 없음 :: $OUT"
[ ! -f "$DN/.git/hooks/pre-commit" ] && ok "ⓝ dry-run 쓰기 0" || bad "ⓝ dry-run 이 썼다"
OUT="$(bash "$INSTALL" --apply --pack-hooks "$DN" 2>&1)"; rc=$?
[ "$rc" = 0 ] && ok "ⓝ apply rc=0" || bad "ⓝ apply rc=$rc :: $OUT"
printf '%s\n' "$OUT" | grep -qF "ERROR core.hooksPath 폴더 없음" && ok "ⓝ apply 도 ERROR 1줄" || bad "ⓝ apply ERROR 줄 없음 :: $OUT"
printf '%s\n' "$OUT" | grep -q "^PACK-HOOKS installed cmp=0" && ok "ⓝ apply 설치 보고" || bad "ⓝ 설치 보고 없음 :: $OUT"
cmp -s "$HOOK" "$DN/.git/hooks/pre-commit" && ok "ⓝ 설치본 cmp0" || bad "ⓝ 설치본 != 키트 훅"
run_commit "$DN"
[ "$rc" != 0 ] && ok "ⓝ 설치 뒤 루트 main 커밋 거절" || bad "ⓝ 설치 뒤인데 커밋 통과 rc=$rc"

# ⓞ 변이 4: «폴더 없음» 검사 줄 삭제 → ⓝ 의 dry-run 이 rc0·ERROR 0줄(= ⓝ FAIL)
grep -vF 'ERROR core.hooksPath 폴더 없음' "$INSTALL" > "$MUT_INST"
[ "$(grep -c . "$MUT_INST")" -lt "$(grep -c . "$INSTALL")" ] && bash -n "$MUT_INST" && ok "ⓞ 변이 4 생성(폴더 없음 검사 삭제)" || bad "ⓞ 변이 4 미생성/문법"
DNM="$T/packDAm"; git init -q -b main --template="$T/emptytpl" "$DNM"
printf 'a\n' > "$DNM/a.txt"; git -C "$DNM" add a.txt; git -C "$DNM" "${GC[@]}" commit -qm init
git -C "$DNM" config core.hooksPath .git/hooks
OUT="$(bash "$MUT_INST" --pack-hooks "$DNM" 2>&1)"; rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$OUT" | grep -q "ERROR core.hooksPath 폴더 없음" || [ "$rc" = 0 ] && ok "ⓞ 변이 4 = ERROR 0줄·rc0 → ⓝ FAIL(변이 잡힘)" || bad "ⓞ 변이 4 인데도 rc=$rc :: $OUT"
rm -f "$MUT_INST"

echo "---"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
