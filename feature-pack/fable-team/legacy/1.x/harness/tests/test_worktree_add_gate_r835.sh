#!/usr/bin/env bash
# test_worktree_add_gate_r835.sh — r835 r3: kit/hooks/worktree-add-gate.sh = «안내» 층(deny 0). BYZ 꼴 리포의 맨손 git worktree add 에
#   additionalContext + stderr 1줄로 ft-wt-add.sh 를 안내하고 · 팩 리포·판별 실패·인자 속 글자는 조용히 통과하는가.
#   픽스처 = 훅 직접 실행 + stdin PreToolUse JSON · mktemp 리포 2(B = design/teams/ 있음 · P = 팩 꼴) + B 의 연결 워크트리 1.
#   DA r2 반례 ② 두 꼴은 실제로도 실행(core.hooksPath = 키트 post-checkout 사본) → rc0 · 팩 워크트리 sparse 0.
#   실 리포·실 훅 등록 0. 변이 = 사본 한 줄 → 이 파일 재실행(R835_MUT=1 재귀 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../kit/hooks/worktree-add-gate.sh"
GATE="${R835_GATE:-$SRC}"
PC="$HERE/../kit/fable-team/githooks/post-checkout"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/hooks"; cp "$PC" "$T/hooks/post-checkout"; chmod +x "$T/hooks/post-checkout"
B="$T/byz"; P="$T/pack"
for r in "$B" "$P"; do git init -q -b main "$r"; git -C "$r" config user.name t; git -C "$r" config user.email t@t; git -C "$r" config core.hooksPath "$T/hooks"; echo x > "$r/README.md"; done
mkdir -p "$B/design/teams/a"; echo a > "$B/design/teams/a/f.md"
for r in "$B" "$P"; do git -C "$r" add -A; git -C "$r" commit -qm init; done
git -C "$B" worktree add -q "$B/.worktrees/linked" -b linked main 2>/dev/null
mkdir -p "$B/sub/dir"

# gate <command> [cwd] [tool] → rc · stdout $T/o · stderr $T/e
gate() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[3],"cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' \
    "$1" "${2:-$B}" "${3:-Bash}" | bash "$GATE" >"$T/o" 2>"$T/e"
}
WANT='팀 워크트리는 ft-wt-add.sh <이름> --team <팀> -b <가지> 로 (sparse · r835)'
# note <이름> <명령> [cwd] — 안내: rc0 · stdout = additionalContext(안내 원문) 1개 · permissionDecision 없음 · stderr 1줄
note() { gate "$2" "${3:-$B}"; local rc=$?
  [ "$rc" = 0 ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["hookSpecificOutput"]; assert "permissionDecision" not in d and sys.argv[2] in d["additionalContext"]' "$T/o" "$WANT" 2>/dev/null \
    && [ "$(wc -l < "$T/e" | tr -d ' ')" = 1 ] && grep -qF "$WANT" "$T/e" \
    && ok "$1" || bad "$1 — 안내 아님 rc=$rc · o=$(head -c 300 "$T/o") · e=$(head -c 200 "$T/e")"; }
# quiet <이름> <명령> [cwd] [tool] — 조용히 통과: rc0 · stdout 0 · stderr 0
quiet() { gate "$2" "${3:-$B}" "${4:-Bash}"; local rc=$?
  [ "$rc" = 0 ] && [ ! -s "$T/o" ] && [ ! -s "$T/e" ] && ok "$1" || bad "$1 — 조용한 통과 아님 rc=$rc · o=$(head -c 300 "$T/o") · e=$(head -c 200 "$T/e")"; }

[ -f "$GATE" ] || { bad "훅 파일 없음: $GATE"; echo "== 결과: FAIL=$fail"; exit 1; }

echo "== ⓕ BYZ 꼴 리포의 맨손 worktree add = 안내(deny 0)"
note "ⓕ cwd=B · git worktree add .worktrees/x -b y main" 'git worktree add .worktrees/x -b y main'
note "ⓕ cwd=P · git -C <B> worktree add" "git -C $B worktree add $B/.worktrees/x -b y origin/main" "$P"
note "ⓕ cwd=B 하위 폴더 · 상대경로" 'git worktree add ../../.worktrees/x -b y main' "$B/sub/dir"
note "ⓕ cwd=B 연결 워크트리(주 워크트리로 판정)" 'git worktree add ../y -b y main' "$B/.worktrees/linked"
note "ⓕ git -C sub -C dir (누적 -C)" 'git -C sub -C dir worktree add ../../.worktrees/x -b y main'
note "ⓕ cd <B> && git worktree add (cwd=P)" "cd $B && git worktree add .worktrees/x -b y main" "$P"
note "ⓕ /usr/bin/git · 전역 옵션 -c k=v --no-pager" '/usr/bin/git -c core.x=1 --no-pager worktree add .worktrees/x -b y main'
note "ⓕ bash -c '…' 감싸기" "bash -c 'git worktree add .worktrees/x -b y main'"
note "ⓕ bash --norc -lc \"…\" 감싸기" 'bash --norc -lc "cd sub && git worktree add ../.worktrees/x -b y main"'
note "ⓕ eval '…' 감싸기" "eval 'git worktree add .worktrees/x -b y main'"
note "ⓕ 앞 명령 뒤 줄바꿈" "$(printf 'echo hi\ngit worktree add .worktrees/x -b y main')"
note "ⓕ cwd=P · git --git-dir=<B>/.git worktree add" "git --git-dir=$B/.git worktree add $B/.worktrees/x -b y main" "$P"
note "ⓕ cwd=P · git --git-dir <B>/.git (띄움 꼴)" "git --git-dir $B/.git worktree add $B/.worktrees/x -b y main" "$P"
note "ⓕ cwd=P · env X=1 git -C <B>" "env X=1 git -C $B worktree add .worktrees/x -b y main" "$P"
note "ⓕ cd \$X 뒤 절대 -C <B>" "cd \$X && git -C $B worktree add .worktrees/x -b y main" "$P"

echo "== ⓕ 조용히 통과"
quiet "ⓕ DA r2 반례②-1 · cwd=B · git --git-dir=.git -C <P>(상대 git-dir = -C 뒤 기준)" "git --git-dir=.git -C $P worktree add $P/.worktrees/q1 -b q1 main"
quiet "ⓕ DA r2 반례②-2 · cwd=P · (cd <B>); git worktree add(서브셸 cd 는 안 샘)" "(cd $B); git worktree add .worktrees/q2 -b q2 main" "$P"
quiet "ⓕ DA r1 오탐1 · cwd=B · --git-dir=<P>/.git" "git --git-dir=$P/.git worktree add $P/.worktrees/x -b x main"
quiet "ⓕ DA r1 오탐2 · git ls-files -- git worktree add" 'git ls-files -- git worktree add'
quiet "ⓕ echo 인자 속 git worktree add" 'echo git worktree add'
quiet "ⓕ heredoc 본문 속 git worktree add" "$(printf 'cat > note.md <<EOF\ngit worktree add .worktrees/x -b y main\nEOF')"
quiet "ⓕ 미전개 git -C \$W (cwd=B)" 'W=/x; git -C $W worktree add $W/.worktrees/x -b y main'
quiet "ⓕ 미전개 --git-dir=\"\$B/.git\"" 'git --git-dir="$B/.git" worktree add x -b y main' "$P"
quiet "ⓕ cd \$X 뒤 맨 git worktree add" 'cd $X && git worktree add .worktrees/x -b y main'
quiet "ⓕ 팩 리포(design/teams/ 없음) · 발주문 꼴" "git -C $P worktree add $P/.worktrees/r835 -b nano/r835 origin/main" "$P"
quiet "ⓕ cwd=P · 맨손 worktree add" 'git worktree add .worktrees/x -b y main' "$P"
quiet "ⓕ ft-wt-add.sh 호출" "bash $HERE/../kit/fable-team/bin/ft-wt-add.sh land-x --team a -b docs/x"
quiet "ⓕ ft-nano-spawn.sh 호출" 'bash .fable-team/bin/ft-nano-spawn.sh design/teams/a/indices/대기/x.md'
quiet "ⓕ ft-scratch-repo.sh 호출" 'bash .fable-team/bin/ft-scratch-repo.sh origin/main'
quiet "ⓕ worktree list" 'git worktree list'
quiet "ⓕ worktree remove" 'git worktree remove .worktrees/x'
quiet "ⓕ worktree prune" 'git -C . worktree prune'
quiet "ⓕ 커밋 메시지 속 글자" 'git commit -m "r835 git worktree add 를 막는다"'
quiet "ⓕ git 밖 폴더 cwd" 'git worktree add x -b y main' "$T"
quiet "ⓕ Bash 아닌 도구" 'git worktree add .worktrees/x -b y main' "$B" Write
[ ! -e "$B/.worktrees/x" ] && [ ! -e "$P/.worktrees/x" ] && ok "ⓕ 훅이 worktree add 를 실행하지 않음(폴더 0)" || bad "ⓕ 훅 실행 흔적"

echo "== ⓕ DA r2 반례② 실제 실행 — rc0 · 팩 워크트리 sparse 0"
(cd "$B" && git --git-dir=.git -C "$P" worktree add -q "$P/.worktrees/q1" -b q1 main) >/dev/null 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ -f "$P/.worktrees/q1/README.md" ] && [ "$(git -C "$P/.worktrees/q1" config --bool core.sparseCheckout)" != true ] && ok "ⓕ 반례②-1 실행 rc0 · 팩 워크트리 sparse 0" || bad "ⓕ 반례②-1 rc=$rc · $(cat "$T/e")"
(cd "$P" && bash -c "(cd $B); git worktree add -q .worktrees/q2 -b q2 main") >/dev/null 2>"$T/e"; rc=$?
[ "$rc" = 0 ] && [ -f "$P/.worktrees/q2/README.md" ] && [ "$(git -C "$P/.worktrees/q2" config --bool core.sparseCheckout)" != true ] && ok "ⓕ 반례②-2 실행 rc0 · 팩 워크트리 sparse 0" || bad "ⓕ 반례②-2 rc=$rc · $(cat "$T/e")"

echo "== ⓖ 입력 깨짐 = 통과(fail-open) + stderr 1줄"
for c in '{not json' '{"tool_name":"Bash","tool_input":{}}' '{"tool_name":"Bash","tool_input":{"command":""}}'; do
  printf '%s' "$c" | bash "$GATE" >"$T/o" 2>"$T/e"; rc=$?
  [ "$rc" = 0 ] && [ ! -s "$T/o" ] && [ "$(wc -l < "$T/e" | tr -d ' ')" = 1 ] && grep -q '^WARN worktree-add-gate: .* — 통과$' "$T/e" \
    && ok "ⓖ $(head -c 40 <<<"$c") → 통과 + WARN 1줄" || bad "ⓖ $c — rc=$rc o=$(cat "$T/o") e=$(cat "$T/e")"
done
grep -q '"permissionDecision"' "$GATE" && bad "ⓖ 훅 원문에 permissionDecision 이 남음(deny 0 위반)" || ok "ⓖ 훅 원문 permissionDecision 0(deny 0)"

echo "== 결과: FAIL=$fail"
[ "${R835_MUT:-0}" = 1 ] && exit $((fail > 0))

echo "== ⓘ 변이(사본 한 줄 · 그 칸이 FAIL 이어야)"
mutate() {  # <이름> <찾을 글자> <바꿀 글자> <FAIL 이어야 할 칸 접두>
  local d="$T/mut-$1"; mkdir -p "$d"; cp "$SRC" "$d/gate.sh"
  python3 - "$d/gate.sh" "$2" "$3" <<'PY' || { bad "ⓘ $1 변이 글자 못 찾음"; return; }
import sys
p, a, b = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(a) == 1, s.count(a); open(p, "w", encoding="utf-8").write(s.replace(a, b))
PY
  R835_MUT=1 R835_GATE="$d/gate.sh" bash "$0" >"$d/run.txt" 2>&1; local rc=$?
  [ "$rc" != 0 ] && grep -q "^FAIL $4" "$d/run.txt" && ok "ⓘ $1 → $(grep -m1 "^FAIL $4" "$d/run.txt" | head -c 120)" || bad "ⓘ $1 변이가 안 잡힘 rc=$rc"
}
mutate no-note '                hits.append(hit)' '                pass' 'ⓕ cwd=B · git worktree add'
mutate no-pack-pass 'return root if os.path.isdir(os.path.join(root, "design", "teams")) else None' 'return root' 'ⓕ 팩 리포'
mutate anywhere-git '        if not start:' '        if False:' 'ⓕ DA r1 오탐2'
mutate early-gitdir 'return j, ("gitdir", join(d, gd))' 'return j, ("gitdir", join(cur, gd))' 'ⓕ DA r2 반례②-1'
mutate subshell-leak '                elif ch == ")" and stack:' '                elif False:' 'ⓕ DA r2 반례②-2'
echo "== 결과(변이 포함): FAIL=$fail"
[ "$fail" = 0 ]
