#!/usr/bin/env bash
# test_install_hook_check.sh — install.sh 의 «훅 등록 확인 줄»: 홈 훅 same/diff/absent · settings registered/absent.
# mktemp 홈만 쓴다(실 ~/.claude 미접촉). block-destructive 템플릿은 실 홈 파일과 cmp(있을 때만).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="$HERE/../../scripts/harness-install/fable-team"
INSTALL="$KIT/install.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

bash -n "$INSTALL" && ok "bash -n install.sh" || bad "bash -n install.sh"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NAME="gh-issue-author-guard.sh"
TPL="$KIT/templates/hooks/$NAME"
run() { bash "$INSTALL" --home "$1" --machine t --team t; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

# ⓐ 훅 파일 없음 + settings.json 없음 → absent / absent · rc=0 · 기존 줄 유지
H1="$T/h1"; mkdir -p "$H1"
OUT="$(run "$H1")"; rc=$?
[ "$rc" = 0 ] && ok "a rc=0" || bad "a rc=$rc"
has "hook $NAME home=absent settings=absent" && ok "a home=absent settings=absent" || bad "a absent 줄"
has "machine=t team=t mode=dry-run" && has "files=" && has "kit_sha=" && ok "a 기존 출력 줄(machine=·files=·kit_sha=) 유지" || bad "a 기존 출력 줄"
printf '%s\n' "$OUT" | grep -qE '^hooks same=0 diff=0 absent=[0-9]+ registered=0$' && ok "a 요약 줄" || bad "a 요약 줄"

# ⓑ 키트와 같은 파일 + settings 등록 → same / registered
H2="$T/h2"; mkdir -p "$H2/.claude/hooks"
cp -p "$TPL" "$H2/.claude/hooks/$NAME"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"$HOME/.claude/hooks/%s"}]}]}}\n' "$NAME" > "$H2/.claude/settings.json"
OUT="$(run "$H2")"; rc=$?
[ "$rc" = 0 ] && ok "b rc=0" || bad "b rc=$rc"
has "hook $NAME home=same settings=registered" && ok "b same/registered" || bad "b same/registered"
printf '%s\n' "$OUT" | grep -qE '^hooks same=1 diff=0 absent=[0-9]+ registered=1$' && ok "b 요약 줄" || bad "b 요약 줄"

# ⓒ 한 바이트 다른 파일 → diff
H3="$T/h3"; mkdir -p "$H3/.claude/hooks"
cp -p "$TPL" "$H3/.claude/hooks/$NAME"; printf '#' >> "$H3/.claude/hooks/$NAME"
OUT="$(run "$H3")"; rc=$?
[ "$rc" = 0 ] && ok "c rc=0" || bad "c rc=$rc"
has "hook $NAME home=diff settings=absent" && ok "c diff" || bad "c diff"
printf '%s\n' "$OUT" | grep -qE '^hooks same=0 diff=1 absent=[0-9]+ registered=0$' && ok "c 요약 줄" || bad "c 요약 줄"

# ⓓ settings.json 없음 + 훅은 있음 → settings=absent
has "settings=absent" && ok "d settings.json 없음 → settings=absent" || bad "d settings=absent"

# 읽기 전용: 홈 훅·settings 를 건드리지 않고 dest 도 만들지 않는다(dry-run)
[ ! -e "$H1/.fable-team" ] && ok "dry-run: dest 미생성" || bad "dry-run: dest 생성됨"
[ ! -e "$H1/.claude" ] && ok "홈 .claude 미생성(복사·등록 0)" || bad "홈 .claude 생성됨"

# block-destructive 템플릿 = 실 홈 파일(바이트 동일) — 홈 파일이 있는 머신에서만
BD="$KIT/templates/hooks/block-destructive.sh"
[ -f "$BD" ] && ok "block-destructive 템플릿 존재" || bad "block-destructive 템플릿 없음"
[ -x "$BD" ] && ok "block-destructive 실행 비트" || bad "block-destructive 실행 비트 없음"
if [ -f "$HOME/.claude/hooks/block-destructive.sh" ]; then
  cmp -s "$BD" "$HOME/.claude/hooks/block-destructive.sh" && ok "block-destructive 템플릿 == 홈 파일" || bad "block-destructive 템플릿 != 홈 파일"
else
  echo "SKIP block-destructive cmp — 이 머신에 홈 파일 없음"
fi

echo "---"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILED=$fail"
exit "$fail"
