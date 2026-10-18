#!/usr/bin/env bash
# test_settings_lint.sh — ft-settings-lint.py 시험(판정 1097b). 중복 키 · 훅 경로 실재 · 리포 settings.json 정상.
# 픽스처 = tests/harness/fixtures/settings-lint/*.json — 일회용 루트(.claude/settings.json + hooks 스텁)에 복사해 돈다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
LINT="$REPO/scripts/fable-team-bin/ft-settings-lint.py"
FX="$HERE/fixtures/settings-lint"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/hooks"; touch "$T/.claude/hooks/a.sh" "$T/.claude/hooks/b.sh"

# lint_fx <픽스처> — 일회용 루트에 settings.json 으로 복사해 돌린다. 출력+rc 는 OUT·RC.
lint_fx() { cp "$FX/$1" "$T/.claude/settings.json"; OUT="$(python3 -I "$LINT" "$T/.claude/settings.json" 2>&1)"; RC=$?; }
expect_ok()  { lint_fx "$1"; [ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK ' && ok "$2" || bad "$2 → rc=$RC $OUT"; }
expect_rej() { lint_fx "$1"; [ $RC -eq 1 ] && echo "$OUT" | grep -q "$3" && ok "$2" || bad "$2 → rc=$RC $OUT"; }

[ -f "$LINT" ] && ok "lint 스크립트 실재" || bad "lint 스크립트 없음 $LINT"
expect_ok  ok.json "정상 → OK(경로 실재 · 셸 한 줄 훅은 경로 검사 제외)"
expect_rej dup-pretooluse.json "중복 PreToolUse → REJECT(행 번호 2개)" 'REJECT .*settings.json 중복 키 PreToolUse 3,9'
expect_rej dup-sessionstart.json "중복 SessionStart → REJECT" 'REJECT .*settings.json 중복 키 SessionStart 3,6'
expect_rej missing-command.json "훅 command 경로 없음 → REJECT" 'REJECT .*settings.json 훅 경로 실재 0 .*ghost.sh'

printf '{ "a": 1,\n' > "$T/.claude/settings.json"
OUT="$(python3 -I "$LINT" "$T/.claude/settings.json" 2>&1)"; RC=$?
[ $RC -eq 1 ] && echo "$OUT" | grep -q 'REJECT .*JSON' && ok "깨진 JSON → REJECT(rc=1)" || bad "깨진 JSON → rc=$RC $OUT"

python3 -I "$LINT" "$T/없는파일.json" >/dev/null 2>&1; [ $? -eq 2 ] && ok "파일 없음 → rc=2(usage)" || bad "파일 없음 rc!=2"

# 리포 실물 — 09-22 이후 PreToolUse 키가 2번이던 파일. 병합 전엔 REJECT(빨강) · 병합 뒤 OK.
OUT="$(python3 -I "$LINT" "$REPO/.claude/settings.json" 2>&1)"; RC=$?
[ $RC -eq 0 ] && echo "$OUT" | grep -q '^OK ' && ok "리포 .claude/settings.json → OK" || bad "리포 .claude/settings.json → rc=$RC $OUT"

[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
