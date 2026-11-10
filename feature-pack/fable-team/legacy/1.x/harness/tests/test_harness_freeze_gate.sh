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
echo c >> "$W/scripts/fable-team-bin/ft-x.sh"; git -C "$W" add -A
expect 2 "$W" 'git commit -m y' "워크트리도 공용 루트 표식으로 REJECT(scripts/fable-team-bin)"
git -C "$W" reset -q; git -C "$W" checkout -q -- .
echo c >> "$W/design/harness/card.md"; git -C "$W" add -A
expect 0 "$W" 'git commit -m y' "표식 있어도 design/harness(카드)만 = 통과(r386 전까지 BYZ 카드 커밋)"
git -C "$W" reset -q; git -C "$W" checkout -q -- .; echo c >> "$W/scripts/fable-team-bin/ft-x.sh"; git -C "$W" add -A
expect 2 "$W" 'cd - && git commit -m y' "cd - 뒤 커밋 = 검사 불가 REJECT"
expect 0 "$W" 'git diff --cached --stat' "읽기 = 통과"

rm -f "$R/.fable-team/state/harness-freeze"
expect 0 "$W" 'git commit -m y' "표식 지움 = 통과(해제)"
expect 0 "$T" '{bad json' "명령 아닌 입력 = 통과"

# r407: 옛 가지에 main 병합(충돌 손 해소) — staged 하네스 상태가 MERGE_HEAD 와 같으면(추가·삭제 그대로) 제외 · 손댄 것만 REJECT
M="$T/merge"; mkdir -p "$M/tests/harness" "$M/app" "$M/.fable-team/state"
git -C "$M" init -q -b main && git -C "$M" config user.email t@t && git -C "$M" config user.name t
echo k > "$M/tests/harness/keep.sh"; echo g > "$M/tests/harness/gone.sh"; echo base > "$M/app/c.txt"
git -C "$M" add tests app && git -C "$M" commit -qm init && git -C "$M" branch old
echo x > "$M/tests/harness/x.sh"; git -C "$M" rm -q tests/harness/gone.sh; echo main > "$M/app/c.txt"
git -C "$M" add tests app && git -C "$M" commit -qm main-side
git -C "$M" checkout -q old; echo old > "$M/app/c.txt"; git -C "$M" commit -qam old-side
printf 'start=abc pack=def\n' > "$M/.fable-team/state/harness-freeze"
git -C "$M" merge -q main >/dev/null 2>&1; git -C "$M" rev-parse -q --verify MERGE_HEAD >/dev/null && ok "병합 충돌로 MERGE_HEAD 남음" || bad "MERGE_HEAD 없음(픽스처)"
echo resolved > "$M/app/c.txt"; git -C "$M" add app/c.txt
expect 0 "$M" 'git commit -m merge' "ⓐ 충돌 손 해소 뒤 commit · 하네스 = MERGE_HEAD 그대로(추가 x.sh · 삭제 gone.sh) = 통과"
echo hand >> "$M/tests/harness/x.sh"; git -C "$M" add tests/harness/x.sh
expect 2 "$M" 'git commit -m merge' "ⓑ 병합 중 하네스 파일 손댐(staged ≠ MERGE_HEAD) = REJECT"
grep -q '건드린 파일 1개: tests/harness/x.sh' "$T/err" && ok "ⓑ 손댄 파일만 1개" || bad "ⓑ 개수·이름 — $(head -c 300 "$T/err")"
grep -q 'MERGE_HEAD 와 같은 상태(블롭·삭제) 1개 제외' "$T/err" && ok "ⓑ 제외 1개(gone.sh) 표기" || bad "ⓑ 제외 표기 — $(head -c 300 "$T/err")"
git -C "$M" checkout -q MERGE_HEAD -- tests/harness/x.sh; echo hand >> "$M/tests/harness/x.sh"
expect 2 "$M" 'git commit -am merge' "ⓑ' 작업 트리만 손댐 + -a = REJECT(작업 트리 diff 는 제외 0)"
git -C "$M" checkout -q MERGE_HEAD -- tests/harness/x.sh; git -C "$M" rm -q tests/harness/keep.sh
expect 2 "$M" 'git commit -m merge' "ⓓ main 에 있는 하네스 파일을 손으로 삭제 = REJECT"
grep -q '건드린 파일 1개: tests/harness/keep.sh' "$T/err" && ok "ⓓ 손 삭제 keep.sh 만" || bad "ⓓ — $(head -c 300 "$T/err")"
git -C "$M" merge --abort

# ⓒ MERGE_HEAD 없음 = 고치기 전 훅과 stderr 바이트 동일
OLD="$T/old-gate.sh"
if git -C "$HERE" show "origin/main:feature-pack/fable-team/harness/kit/hooks/harness-freeze-gate.sh" > "$OLD" 2>/dev/null && ! grep -q MERGE_HEAD "$OLD"; then
  echo hand > "$M/tests/harness/keep.sh"; git -C "$M" add tests/harness/keep.sh
  IN=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"git commit -m x"}}))' "$M")
  printf '%s' "$IN" | bash "$GATE" 2>"$T/new"; rn=$?; printf '%s' "$IN" | bash "$OLD" 2>"$T/old"; ro=$?
  [ "$rn$ro" = 22 ] && cmp -s "$T/new" "$T/old" && ok "ⓒ MERGE_HEAD 없음 = rc2 · stderr 바이트 동일" || bad "ⓒ rc=$rn/$ro · $(diff "$T/old" "$T/new" | head -5)"
else
  echo "SKIP ⓒ 바이트 대조 — origin/main 옛 훅을 못 읽음(이미 r407 착지 뒤)"
fi

echo "== $( [ $fail = 0 ] && echo ALL PASS || echo "FAIL $fail" ) =="
[ $fail = 0 ]
