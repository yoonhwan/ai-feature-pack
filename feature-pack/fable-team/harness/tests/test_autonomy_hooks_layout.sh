#!/usr/bin/env bash
# test_autonomy_hooks_layout.sh — 실 배치 재현: 메인 루트 ≠ 라이브 도구 루트 (R176 · 판정 1675 ①)
# test_autonomy_hooks.sh 는 FT_ROOT·FT_AUTONOMY_SH·FT_AUTONOMY_STATE_DIR 를 전부 주입해 이 배치를 한 번도 안 돈다.
# 여기선 셋 다 주입 0 — 임시 «메인 루트»(git + bin-harness/harness-env.sh 가 임시 «라이브 워크트리» bin 을 가리킴) + 그 워크트리 cwd.
# 격리: HOME·루트·라이브·상태 전부 임시 — 실 ~/.claude·실 상태·실 gh 0.
set -uo pipefail
export FT_AUTONOMY_LEVEL=each   # r466: --level 생략 = full(범위 승인 + 슬랙 게시) — 이 시험은 레벨 밖이라 each(실 슬랙 0)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; HK="$ROOT/harness/kit/fable-team/templates/hooks"
IG="$HK/autonomy-interview-gate.sh"; MG="$HK/autonomy-merge-guard.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
unset FT_ROOT FT_AUTONOMY_SH FT_AUTONOMY_STATE_DIR CLAUDE_PROJECT_DIR FT_PLANNER_DIR FT_AUTONOMY_HOOK_LOG GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
MAIN="$T/main"; LIVE="$T/live"; WT="$T/main-wt"; LOG="$HOME/.claude/logs/autonomy-hooks.log"
git -c init.defaultBranch=main init -q "$MAIN" && git -C "$MAIN" checkout -q -B main && git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m one
git -C "$MAIN" worktree add -q -b wt "$WT" main
mkdir -p "$MAIN/.fable-team/bin-harness" "$LIVE/.fable-team/bin"
printf '%s\n' '#!/bin/bash' "export FT_BIN=$LIVE/.fable-team/bin" > "$MAIN/.fable-team/bin-harness/harness-env.sh"
bash "$HERE/lib/kit_bin_copy.sh" "$LIVE/.fable-team/bin" >/dev/null || { echo "FAIL kit_bin_copy"; exit 1; }   # 도구는 «라이브 루트» 안 — 상태도 거기(= 오빠 `!` 가 쓰는 곳) · r536: 키트 bin 통째(ft-harness-root.sh 등 형제 짝)
H="$(git -C "$MAIN" rev-parse HEAD)"; S="$LIVE/.fable-team/state"
a() { "$BASH" "$LIVE/.fable-team/bin/ft-autonomy.sh" "$@"; }   # 오빠 `!` 와 같은 호출 — FT_ROOT 없음
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$2"; }
mkask() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"AskUserQuestion","cwd":sys.argv[2],"tool_input":{"questions":[{"question":sys.argv[1],"header":"","multiSelect":False,"options":[{"label":"a","description":"x"},{"label":"b","description":"y"}]}]}},ensure_ascii=False))' "$1" "$2"; }
run() { out="$(printf '%s' "$2" | "$BASH" "$1" 2>"$T/err")"; rc=$?; }
dn() { run "$1" "$2"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$3" $?; }
al() { run "$1" "$2"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$3" $?; }
GH="gh pr merge 7 --squash"

a on >/dev/null 2>&1; [ "$(a mode)" = on ] && [ ! -e "$MAIN/.fable-team/state/autonomy.json" ]; ck "ⓛ0 준비: 라이브 상태만 ON · 메인 루트 상태 없음" $?
dn "$MG" "$(mkbash "$GH" "$WT")" "ⓛ1 ON + 워크트리 cwd + 미승인 pr merge → deny"
dn "$MG" "$(mkbash "$GH --match-head-commit $H" "$WT")" "ⓛ2 ON + 승인 없는 sha → deny"
dn "$IG" "$(mkask "고를까요?" "$WT")" "ⓛ3 ON + 인터뷰 → deny (자율 대리 결정)"
grep -q '자율 ON' <<<"$out"; ck "ⓛ3b deny 사유에 라이브 상태(자율 ON)" $?
a approve-merge "$H" >/dev/null 2>&1
al "$MG" "$(mkbash "$GH --match-head-commit $H" "$WT")" "ⓛ4 오빠 승인(라이브 상태) sha → allow"
al "$MG" "$(mkbash "gh pr view 7" "$WT")" "ⓛ5 병합 아닌 명령 → allow"
a off >/dev/null 2>&1
al "$MG" "$(mkbash "$GH" "$WT")" "ⓛ6 OFF → allow"
[ ! -s "$LOG" ] || ! grep -q '못 읽음' "$LOG"; ck "ⓛ7 정상 배치에서는 로그에 «못 읽음» 0줄" $?

# 도구 없음 = 못 읽음 → 컨펌 값(병합 deny · 인터뷰 allow + 경고)
mv "$LIVE/.fable-team/bin/ft-autonomy.sh" "$LIVE/.fable-team/bin/x.off"
dn "$MG" "$(mkbash "$GH" "$WT")" "ⓛ8 도구 없음 → 병합 deny"
grep -q '못 읽어' <<<"$out" && grep -q '못 읽음' "$LOG"; ck "ⓛ8b 사유 + 로그에 못 읽음" $?
al "$MG" "$(mkbash "git status" "$WT")" "ⓛ8c 도구 없음 + 병합 아닌 명령 → allow"
run "$IG" "$(mkask "고를까요?" "$WT")"; [ "$rc" = 0 ] && ! grep -q permissionDecision <<<"$out" && grep -q 'systemMessage' <<<"$out" && grep -q '못 읽어' "$T/err"; ck "ⓛ9 도구 없음 → 인터뷰 allow + 화면 경고" $?
mv "$LIVE/.fable-team/bin/x.off" "$LIVE/.fable-team/bin/ft-autonomy.sh"

# BYZ 밖 allow 불변
mkdir -p "$T/outside"; a on >/dev/null 2>&1
al "$MG" "$(mkbash "$GH" "$T/outside")" "ⓛ10 BYZ 밖 cwd → allow"
al "$IG" "$(mkask "고를까요?" "$T/outside")" "ⓛ10b BYZ 밖 cwd 인터뷰 → allow"

# 두 훅의 해석 함수 = 같은 문장
blk() { sed -n '/^# --- R176 resolve begin/,/^# --- R176 resolve end/p' "$1"; }
[ -n "$(blk "$MG")" ] && [ "$(blk "$MG")" = "$(blk "$IG")" ]; ck "ⓛ11 두 훅의 R176 해석 블록 바이트 일치" $?
[ "$(git -C "$MAIN" config --get core.bare)" = false ] && [ "$(git -C "$ROOT" config --get core.bare 2>/dev/null || echo false)" = false ]; ck "ⓛ12 core.bare = false" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
