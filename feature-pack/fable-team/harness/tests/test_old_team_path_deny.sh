#!/usr/bin/env bash
# test_old_team_path_deny.sh — r402: kit/hooks/old-team-path-new-file-gate.sh (꼴2 팀의 옛 꼴1 경로 «새 파일» deny · 판정 2294 ⓑ).
#   가짜 리포(TEAMS.md 에 꼴2 v65 · 꼴1 ops · 꼴3 harness) · 훅 stdin JSON · 카드 시험 입력 ⓐ 6절 + ⓑ(리포 밖 · 꼴3 · bash -n) + Bash 꼴 보강.
# mktemp 만 쓴다 — 실 리포·실 HOME·실 settings 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../kit/hooks/old-team-path-new-file-gate.sh"
KITBIN="$HERE/../kit/fable-team/bin"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
export HOME="$T/home"; mkdir -p "$HOME"
export FT_BIN="$KITBIN"
unset FT_TEAMS_MD FT_REPO_ROOT FT_HARNESS_ROOT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
# hook <tool> <cwd> <key> <value> → stdout $T/out · stderr $T/err
hook() { python3 -c 'import json,sys; t,c,k,v=sys.argv[1:5]; print(json.dumps({"tool_name":t,"cwd":c,"tool_input":{k:v}}))' "$@" | bash "$GATE" >"$T/out" 2>"$T/err"; }
deny()  { hook "$@"; grep -q '"permissionDecision": "deny"' "$T/out"; }
allow() { hook "$@"; [ ! -s "$T/out" ]; }

R="$T/byz"; mkdir -p "$R/design/teams/v65" "$R/design/v65" "$R/design/ops" "$R/app"
cat > "$R/design/TEAMS.md" <<'EOF'
| 팀 | 폴더 |
|---|---|
| v65 | design/teams/v65/ |
| ops | design/ops/ |
| harness | $FT_HARNESS_ROOT/design/harness/ |
EOF
echo old > "$R/design/v65/old.md"; echo a > "$R/app/a.txt"
git -C "$R" init -q -b main

# ⓐ 6절
deny Write "$R" file_path design/v65/x.md && grep -q '바른 경로: design/teams/v65/x.md' "$T/out" \
  && ok "① Write 꼴2 팀 옛 경로 새 파일 = deny + 바른 경로" || bad "① $(cat "$T/out" "$T/err")"
allow Write "$R" file_path design/teams/v65/x.md && ok "② Write 새 꼴2 경로 = allow" || bad "② $(cat "$T/out")"
allow Edit "$R" file_path "$R/design/v65/old.md" && ok "③ Edit 옛 경로 기존 파일 = allow" || bad "③ $(cat "$T/out")"
deny Bash "$R" command "cp app/a.txt design/v65/new.md" && grep -q 'design/teams/v65/new.md' "$T/out" \
  && ok "④ Bash cp 옛 경로 새 파일 = deny" || bad "④ $(cat "$T/out" "$T/err")"
allow Write "$R" file_path design/ops/x.md && ok "⑤ Write 꼴1 팀 = allow" || bad "⑤ $(cat "$T/out")"
R2="$T/noteams"; mkdir -p "$R2/design/v65"; git -C "$R2" init -q -b main
allow Write "$R2" file_path design/v65/x.md && [ "$(grep -c 'WARN' "$T/err")" = 1 ] \
  && ok "⑥ TEAMS.md 없음 = allow + WARN 1줄" || bad "⑥ out=$(cat "$T/out") err=$(cat "$T/err")"

# ⓑ 리포 밖 · 꼴3 · 하위 폴더 · 절대경로
mkdir -p "$T/plain/design/v65"
allow Write "$T/plain" file_path design/v65/x.md && [ ! -s "$T/err" ] && ok "ⓑ 리포 밖 = allow(WARN 0)" || bad "ⓑ 리포 밖 $(cat "$T/out" "$T/err")"
allow Write "$R" file_path design/harness/x.md && ok "ⓑ 꼴3 팀 = 대상 아님" || bad "ⓑ 꼴3 $(cat "$T/out")"
deny Write "$T" file_path "$R/design/v65/sub/deep/y.md" && grep -q 'design/teams/v65/sub/deep/y.md' "$T/out" \
  && ok "ⓑ 절대경로 · 없는 하위 폴더 = deny" || bad "ⓑ 절대경로 $(cat "$T/out" "$T/err")"
allow Write "$R" file_path design/unknown/x.md && ok "ⓑ 명단에 없는 폴더 = allow" || bad "ⓑ 명단 밖 $(cat "$T/out")"
bash -n "$GATE" && ok "ⓑ bash -n" || bad "ⓑ bash -n"

# Bash 꼴 보강 — 리다이렉트·tee·touch·mv 는 대상만 · 그 밖은 통과(과잉 차단 0)
deny Bash "$R" command "echo hi > design/v65/r.md" && ok "Bash > 대상 = deny" || bad "Bash > $(cat "$T/out")"
deny Bash "$R" command "echo hi >> design/v65/r.md" && ok "Bash >> 대상 = deny" || bad "Bash >> $(cat "$T/out")"
deny Bash "$R" command "echo hi | tee design/v65/t.md" && ok "Bash tee = deny" || bad "Bash tee $(cat "$T/out")"
deny Bash "$R" command "touch design/v65/t2.md" && ok "Bash touch = deny" || bad "Bash touch $(cat "$T/out")"
deny Bash "$R" command "mv app/a.txt design/v65/m.md" && ok "Bash mv = deny" || bad "Bash mv $(cat "$T/out")"
allow Bash "$R" command "cat design/v65/old.md > /dev/null 2>&1" && ok "Bash 읽기 + /dev/null = allow" || bad "Bash 읽기 $(cat "$T/out")"
allow Bash "$R" command "echo 'cp a design/v65/q.md' && ls design/v65" && ok "Bash 따옴표 안 글자 = allow" || bad "Bash 따옴표 $(cat "$T/out")"
allow Bash "$R" command "cp design/v65/new.md design/teams/v65/new.md" && ok "Bash 옛 경로 → 새 경로 cp = allow" || bad "Bash 옛→새 $(cat "$T/out")"
allow Bash "$R" command "echo hi > design/v65/old.md" && ok "Bash 기존 파일 덮어쓰기 = allow" || bad "Bash 기존 $(cat "$T/out")"
allow Bash "$R" command "echo hi >&2" && ok "Bash >&2 = allow" || bad "Bash >&2 $(cat "$T/out")"

# fail-open
printf '{bad json' | bash "$GATE" >"$T/out" 2>"$T/err"; [ ! -s "$T/out" ] && grep -q WARN "$T/err" \
  && ok "JSON 파싱 실패 = allow + WARN" || bad "JSON 실패 $(cat "$T/out" "$T/err")"
allow Bash "$R" command "echo 'unterminated > design/v65/z.md" && grep -q WARN "$T/err" \
  && ok "Bash 토큰화 실패 = allow + WARN" || bad "토큰화 실패 $(cat "$T/out" "$T/err")"
( export FT_BIN="$T/nolib"; allow Write "$R" file_path design/v65/x.md && grep -q 'ft-team-lib.sh 없음' "$T/err" ) \
  && ok "lib 없음 = allow + WARN" || bad "lib 없음 $(cat "$T/out" "$T/err")"
( unset FT_BIN; mkdir -p "$HOME/.claude/fable-team/live/1.0.9/bin" "$HOME/.claude/fable-team/live/1.0.10/bin"
  cp "$KITBIN/ft-team-lib.sh" "$HOME/.claude/fable-team/live/1.0.10/bin/"
  deny Write "$R" file_path design/v65/x.md ) && ok "FT_BIN 없음 → live 최신(1.0.10 · sort -V) lib = deny" || bad "live 최신 $(cat "$T/out" "$T/err")"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
