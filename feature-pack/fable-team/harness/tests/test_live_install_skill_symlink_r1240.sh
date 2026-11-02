#!/usr/bin/env bash
# test_live_install_skill_symlink_r1240.sh — r1240: 라이브 스킬 `~/.claude/skills/<이름>` 이 «git 체크아웃 안을 가리키는 심링크» 일 때
# ft-live-install-check 가 그 체크아웃의 뒤처짐(behind) · skill 폴더 추적 파일 차이(diff)를 `WARN skill-symlink` 1줄로 낸다.
# 반례(동결 r1240): R1 뒤 3 · diff 2 → WARN 1줄 · R2 같음 → WARN 0 · R3 복사본 → 0 · R4 git 밖 → 0 · R5 깨진 .git → 판정 불가 1줄 · 다른 점검 그대로.
# 임시 HOME·임시 git 리포·임시 워크트리만 — 실 ~/.claude·실 팩 체크아웃 쓰기 0 · press 0 · Redis 0.
if [ -n "${FT_R1240_SKILL_SYMLINK_GUARD:-}" ]; then  # r1041 재진입 표지(자기 재호출 0 · 그래도 있으면 즉시 종료)
  echo "SKIP 재진입 표지"; exit 0
fi
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
CHK="$BIN/ft-live-install-check.sh"
KITMAP="$HERE/../../harness/kit/LIVE-MAP.tsv"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:600}"; fail=$((fail+1)); fi; }
has() { [[ "$out" == *"$1"* ]]; }
warn_lines() { printf '%s\n' "$out" | grep -c '^WARN skill-symlink ' || true; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 FT_R1240_SKILL_SYMLINK_GUARD=1
export HOME="$T/home"; mkdir -p "$HOME/.claude/skills"
A="$T/repo"; KD=scripts/harness-install
mkdir -p "$A/$KD" "$A/skill/scripts"
cp "$KITMAP" "$A/$KD/LIVE-MAP.tsv"
G() { git -C "$A" "$@"; }
G init -q -b main . && G config user.name t && G config user.email t@t
printf 'v0\n' > "$A/skill/SKILL.md"; printf 'v0\n' > "$A/skill/scripts/x.sh"; printf 'base\n' > "$A/README.md"
G add -A && G commit -qm c0
C0="$(G rev-parse HEAD)"
printf 'v1\n' > "$A/skill/SKILL.md"; G commit -qam c1                                   # skill 폴더 diff 1
printf 'v1\n' > "$A/skill/scripts/x.sh"; G commit -qam c2                              # skill 폴더 diff 2
printf 'other\n' > "$A/README.md"; G commit -qam c3                                    # skill 폴더 밖(뒤 3 중 하나)
G update-ref refs/remotes/origin/main HEAD
git -C "$A" worktree add -q --detach "$T/co" "$C0"                                     # 체크아웃 = 3 커밋 뒤
git -C "$A" worktree add -q --detach "$T/co-fresh" HEAD                                # 체크아웃 = origin/main
chk() { out="$(bash "$CHK" --all --repo "$A" --kit "$KD" 2>&1)"; rc=$?; }
link() { rm -rf "$HOME/.claude/skills/"*; ln -s "$1" "$HOME/.claude/skills/fable-team"; }

# R1 체크아웃이 origin/main 보다 3 뒤 · skill 추적 파일 diff 2 → WARN 1줄(뒤 3 · diff 2) · rc 는 PENDING 이 아니다(0)
link "$T/co/skill"; chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 1 ] && has "WARN skill-symlink fable-team behind=3 diff=2 -> " && has "-> $T/co/skill " \
  && has "(고침: git -C " && has "merge --ff-only origin/main"
ck "R1 뒤 3 · diff 2 → WARN 1줄 · rc0(WARN≠PENDING) · 고침 명령" $?

# R2 체크아웃 = origin/main · diff 0 → WARN 0
link "$T/co-fresh/skill"; chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 0 ] && has "OK n=" && ! has "WARN"
ck "R2 같음 → WARN 0 · OK · rc0" $?

# R3 심링크 아님(복사본 스킬) → 이 갈래 대상 밖 · 줄 0
rm -f "$HOME/.claude/skills/"*; cp -R "$T/co/skill" "$HOME/.claude/skills/fable-team"; chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 0 ] && ! has "WARN"
ck "R3 복사본(심링크 아님) → 줄 0 · rc0" $?

# R4 심링크 대상이 git 밖 → 대상 밖 · 줄 0
mkdir -p "$T/plain/skill"; link "$T/plain/skill"; chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 0 ] && ! has "판정 불가"
ck "R4 git 밖 대상 → 줄 0 · rc0" $?

# R5 깨진 .git(대상 폴더의 .git 이 쓰레기) → 판정 불가 1줄 · 다른 점검 그대로(OK 줄 유지 · rc0)
mkdir -p "$T/broken"; printf 'not a gitdir\n' > "$T/broken/.git"; link "$T/broken"; chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 1 ] && has "WARN skill-symlink fable-team 판정 불가 — " && has "OK n=" \
  && [[ "$out" != *"behind="* ]]
ck "R5 깨진 .git → 판정 불가 1줄 · 다른 점검 그대로 · rc0" $?

# R5b 뒤처진 체크아웃 + 깨진 .git 이 같이 있어도 R1 경보는 살아 있다(한 건 실패가 다른 점검을 죽이지 않는다)
rm -rf "$HOME/.claude/skills/"*; ln -s "$T/co/skill" "$HOME/.claude/skills/fable-team"; ln -s "$T/broken" "$HOME/.claude/skills/broken"
chk
[ "$rc" = 0 ] && [ "$(warn_lines)" = 2 ] && has "behind=3 diff=2" && has "broken 판정 불가"
ck "R5b 판정 불가 + WARN 동시 → 각 1줄(다른 점검 유지)" $?

# 안전: 이 시험은 실 ~/.claude 를 안 건드린다(전부 $HOME = 임시 폴더)
[ "$HOME" = "$T/home" ] && [ -d "$HOME/.claude/skills" ]
ck "격리: HOME = 임시 폴더" $?

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
