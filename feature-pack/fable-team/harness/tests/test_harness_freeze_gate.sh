#!/usr/bin/env bash
# test_harness_freeze_gate.sh — r385: kit/hooks/harness-freeze-gate.sh (BYZ freeze 중 하네스 4폴더 커밋 REJECT).
#   픽스처 리포 + 워크트리 1 · 표식 없음 = 통과 · 표식 있음 = 4폴더 staged/-a/워크트리 cd 커밋 REJECT · 4폴더 밖·메시지 글자·읽기 = 통과.
# mktemp 만 쓴다 — 실 리포·실 HOME 쓰기 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$HERE/../kit/hooks/harness-freeze-gate.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
# gate <cwd> <command> → rc
gate() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2" | bash "$GATE" 2>"$T/err"; }
expect() { gate "$2" "$3"; rc=$?; [ "$rc" = "$1" ] && ok "$4 rc=$rc" || bad "$4 — rc=$rc 기대 $1 · $(head -c 300 "$T/err")"; }

R="$T/byz"; mkdir -p "$R/scripts/fable-team-bin" "$R/design/harness" "$R/app" "$R/.fable-team/state"
git -C "$R" init -q -b main && git -C "$R" config user.email t@t && git -C "$R" config user.name t
echo a > "$R/scripts/fable-team-bin/ft-x.sh"; echo a > "$R/app/main.py"; echo a > "$R/design/harness/card.md"
git -C "$R" add -A && git -C "$R" commit -qm init
W="$T/w1"; git -C "$R" worktree add -q "$W" -b w1

# 표식 없음 → 통과
echo b >> "$R/scripts/fable-team-bin/ft-x.sh"; git -C "$R" add -A
expect 0 "$R" 'git commit -m x' "표식 없음 = 4폴더 커밋 통과"

printf 'start=abc pack=def\n' > "$R/.fable-team/state/harness-freeze"
expect 2 "$R" 'git commit -m x' "표식 있음 + staged 4폴더 = REJECT"
grep -q 'scripts/fable-team-bin/ft-x.sh' "$T/err" && ok "사유에 파일 이름" || bad "사유에 파일 이름 없음"
expect 2 "$T" "git -C $R commit -m x" "git -C 대상 = REJECT"
expect 2 "$T" "cd $R && git commit -m x" "cd 따라감 = REJECT"
git -C "$R" reset -q
expect 0 "$R" 'git commit -m x' "staged 0(작업 트리만 변경) + 평범한 커밋 = 통과"
expect 2 "$R" 'git commit -am x' "-am = 작업 트리 4폴더 REJECT"
expect 2 "$R" 'git commit --all -m x' "--all = REJECT"
git -C "$R" checkout -q -- .

# 4폴더 밖 → 통과 · 메시지 글자는 커밋 아님
echo b >> "$R/app/main.py"; git -C "$R" add -A
expect 0 "$R" 'git commit -m "scripts/fable-team-bin 손봄"' "4폴더 밖 파일 = 통과(메시지 글자 무시)"
git -C "$R" reset -q; git -C "$R" checkout -q -- .
expect 0 "$R" 'echo "git commit" && git log --oneline -1' "따옴표 안 git commit = 커밋 아님"

# 워크트리(공용 루트 표식) → REJECT
echo c >> "$W/design/harness/card.md"; git -C "$W" add -A
expect 2 "$W" 'git commit -m y' "워크트리도 공용 루트 표식으로 REJECT(design/harness)"
expect 2 "$W" 'cd - && git commit -m y' "cd - 뒤 커밋 = 검사 불가 REJECT"
expect 0 "$W" 'git diff --cached --stat' "읽기 = 통과"

rm -f "$R/.fable-team/state/harness-freeze"
expect 0 "$W" 'git commit -m y' "표식 지움 = 통과(해제)"
expect 0 "$T" '{bad json' "명령 아닌 입력 = 통과"

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
