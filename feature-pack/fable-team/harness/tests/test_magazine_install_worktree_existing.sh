#!/usr/bin/env bash
# test_magazine_install_worktree_existing.sh — r619: install-magazine.sh 마지막 워크트리 갈래
# ⓐ 가지 있음 · 폴더 없음 → 그 가지로 붙이기 rc0 (고치기 전 = `-b` 재생성 시도 → rc≠0)
# ⓑ 가지 없음 · 폴더 없음 → 지금처럼 `-b` 로 만듦 rc0
# ⓒ 폴더 있음 → «worktree 있음 (그대로)» rc0 · 가지 sha 불변
# ⓓ 가지가 다른 워크트리에 붙어 있음 → 붙이기 0 + WARN 1줄(그 경로) + rc0
# 픽스처 = 임시 git 리포 + 가짜 HOME. 실 ~/.hermes·launchctl·~/.worktrees 는 건드리지 않는다(launchctl 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../kit/slack-mirror"
SH="$KIT/install-magazine.sh"
PY="${PYTHON:-/opt/homebrew/bin/python3}"; [ -x "$PY" ] || PY="$(command -v python3)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# 픽스처: $1 = 리포 경로. main 브랜치 1커밋 + origin/main = HEAD + 가짜 HOME
fixture() {
  local root="$1"
  git init -q -b main "$root" || return 1
  mkdir -p "$root/.fable-team" && : > "$root/.fable-team/.keep"
  git -C "$root" -c user.email=t@t -c user.name=t add -A >/dev/null
  git -C "$root" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$root" update-ref refs/remotes/origin/main "$(git -C "$root" rev-parse HEAD)"
  mkdir -p "$root/home"
}

# $1 = 리포 · $2 = 워크트리 경로 · $3 = 출력 파일. rc 를 stdout 마지막 줄 밖으로 돌려준다.
run_install() {
  HOME="$1/home" BYZ_ROOT="$1" MAGAZINE_PY="$PY" MAGAZINE_WORKTREE="$2" \
    bash "$SH" >"$3" 2>&1
}

# ⓐ 가지 있음 · 폴더 없음
R="$T/a"; fixture "$R"
git -C "$R" branch ops/magazine origin/main
SHA0="$(git -C "$R" rev-parse ops/magazine)"
WT="$R/.worktrees/ops-magazine"
if run_install "$R" "$WT" "$T/a.out"; then
  WTP="$(cd "$WT" 2>/dev/null && pwd -P)"
  if [ -e "$WT/.git" ] && [ "$(git -C "$R" rev-parse ops/magazine)" = "$SHA0" ] \
     && git -C "$R" worktree list --porcelain | grep -qxF "worktree $WTP"; then
    ok "ⓐ 가지 있음+폴더 없음 → 그 가지로 붙음 · sha 불변"
  else
    bad "ⓐ rc0 이나 폴더/가지/등록이 어긋남: $(tr '\n' '|' < "$T/a.out")"
  fi
else
  bad "ⓐ rc≠0 (고치기 전 동작): $(tr '\n' '|' < "$T/a.out")"
fi

# ⓑ 가지 없음 · 폴더 없음 → -b 로 새로 만든다
R="$T/b"; fixture "$R"
WT="$R/.worktrees/ops-magazine"
if run_install "$R" "$WT" "$T/b.out" && [ -e "$WT/.git" ] \
   && git -C "$R" show-ref --verify --quiet refs/heads/ops/magazine; then
  ok "ⓑ 가지 없음 → -b 로 생성 rc0"
else
  bad "ⓑ 새 가지 생성 실패: $(tr '\n' '|' < "$T/b.out")"
fi

# ⓒ 폴더 있음 → 그대로
SHA1="$(git -C "$R" rev-parse ops/magazine)"
if run_install "$R" "$WT" "$T/c.out" && grep -q "worktree 있음" "$T/c.out" \
   && [ "$(git -C "$R" rev-parse ops/magazine)" = "$SHA1" ]; then
  ok "ⓒ 폴더 있음 → 그대로 rc0 · sha 불변"
else
  bad "ⓒ 폴더 있음 갈래 어긋남: $(tr '\n' '|' < "$T/c.out")"
fi

# ⓓ 가지가 다른 워크트리에 이미 붙어 있음 → 붙이기 0 + WARN(경로) + rc0
R="$T/d"; fixture "$R"
git -C "$R" branch ops/magazine origin/main
OTHER="$T/d-other"
git -C "$R" worktree add -q "$OTHER" ops/magazine
WT="$R/.worktrees/ops-magazine"
if run_install "$R" "$WT" "$T/d.out" && [ ! -e "$WT" ] \
   && grep -q "WARN" "$T/d.out" && grep -qF "$OTHER" "$T/d.out"; then
  ok "ⓓ 다른 워크트리에 붙음 → 붙이기 0 · WARN 경로 · rc0"
else
  bad "ⓓ 중복 붙이기 갈래 어긋남: $(tr '\n' '|' < "$T/d.out")"
fi

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
