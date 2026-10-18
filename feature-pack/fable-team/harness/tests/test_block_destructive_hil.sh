#!/usr/bin/env bash
# test_block_destructive_hil.sh — R115: block-destructive 훅의 (②) git 전역 옵션 구멍 + (①) ft-hil.sh «등록» 오탐.
# 키트 훅에 PreToolUse JSON 만 넣고 종료코드만 본다 — 실제 명령 실행·삭제 0 (명령은 JSON 문자열일 뿐).
# ①은 훅·판정기를 임시 폴더에 복사해 그 옆 hil-paths.txt 로 시험한다(홈 훅·홈 파일 0).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
KIT="${BD_KIT:-$HERE/../../harness/kit/fable-team/templates/hooks}"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
mkdir -p "$T/hooks" "$T/bin" "$T/evil" "$T/repo"
git -C "$T/repo" init -q
cp "$KIT/block-destructive.sh" "$KIT/block-destructive-judge.py" "$KIT/block_destructive_hil.py" "$T/hooks/"
HOOK="$T/hooks/block-destructive.sh"
HIL="$T/bin/ft-hil.sh"; EVIL="$T/evil/ft-hil.sh"; : > "$HIL"; : > "$EVIL"
fail=0; nb=0; np=0

run() {  # <명령> [JSON cwd] → 훅 종료코드
  python3 -c 'import json,sys
print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "${2:-$T/repo}" \
    | /bin/bash "$HOOK" >/dev/null 2>&1
}
expect() {  # <기대 rc> <카운터> <명령>
  local rc; run "$3"; rc=$?
  if [ "$rc" = "$1" ]; then echo "PASS [$2] rc=$rc :: ${3:0:80}"; eval "$2=\$(($2+1))"
  else echo "FAIL [$2] want=$1 got=$rc :: $3"; fail=$((fail+1)); fi
}
blk() { expect 2 nb "$1"; }
pas() { expect 0 np "$1"; }

# ── ② git 전역 옵션 뒤 파괴 하위명령 = 차단 (지금은 구멍) ──
blk 'git -C /tmp/x worktree remove /tmp/x/wt'
blk 'git -c core.x=1 worktree remove /tmp/x/wt'
blk 'git -C /tmp/x branch -D feat'
blk 'git --git-dir=/tmp/x/.git push --force origin main'
blk 'git --git-dir /tmp/x/.git push --force origin main'
blk 'git --work-tree=/tmp/x --no-pager branch -D feat'
blk "git -C '/tmp/a b' worktree remove /tmp/a"
blk 'git --no-pager -C /tmp/x -c a=b push origin +main'
# 통과 유지 (옵션이 있어도 파괴 아님)
pas 'git -C /tmp/x status'
pas 'git -C /tmp/x log --oneline'
pas 'git -c core.x=1 push origin main'
pas 'git --no-pager diff'

# ── ① ft-hil.sh 등록(실행 0) = 통과 · 악용 꼴 = 차단 ──
RM='git worktree remove /tmp/x/.worktrees/tmp-origin'
python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$HIL" > "$T/hooks/hil-paths.txt"   # 목록은 realpath 줄(설치가 쓰는 꼴)
pas "bash $HIL --cmd '$RM'"
pas "bash $HIL --add /tmp/plan.sh.hil"
pas $'cat > /tmp/p.sh.hil <<\'EOF\'\n'"$RM"$'\nEOF\nbash '"$HIL"' --add /tmp/p.sh.hil'
blk "bash $HIL --cmd 'echo' && $RM"
blk "bash $HIL --cmd '$RM' && bash /tmp/h9"
blk "bash $HIL --cmd \"\$($RM)\""
blk "bash $EVIL --cmd '$RM'"
blk "bash $HIL --cmd '$RM' ; $RM"
blk "bash $HIL --cmd '$RM' extra"
blk "bash $HIL --run '$RM'"
blk "bash $HIL --cmd '$RM' > /tmp/out"
blk "X=1 bash $HIL --cmd '$RM'"
blk "cd /tmp && bash $HIL --cmd '$RM'"
# DA⑥ HOLD 1: 허용 hil 파일·별칭·목록 파일에 «쓰는» 구간이 있으면 hil 자격 취소 (계획 파일 쓰기는 그대로 통과)
ln -s "$HIL" "$T/bin/alias.sh"; ln "$HIL" "$T/bin/hard.sh"
REG="bash $HIL --cmd '$RM'"
blk $'cat > '"$HIL"$' <<\'EOF\'\nrm -rf x\nEOF\n'"$REG"
blk $'cat > '"$T/bin/alias.sh"$' <<\'EOF\'\nrm -rf x\nEOF\n'"$REG"
blk $'cat > '"$T/bin/hard.sh"$' <<\'EOF\'\nrm -rf x\nEOF\n'"$REG"
blk $'tee '"$HIL"$' <<\'EOF\'\nrm -rf x\nEOF\n'"$REG"
blk "echo x >> $HIL; $REG"
blk "echo x > ../bin/ft-hil.sh; $REG"
blk "echo x > $T/hooks/hil-paths.txt; $REG"
blk "echo x > \$F; $REG"
pas $'cat > /tmp/p.sh.hil <<\'EOF\'\n'"$RM"$'\nEOF\n'"$REG"
# DA⑥ HOLD 2: git 전역 옵션 값 안의 구분문자(; | &)·셸 토큰 단위 정규화
blk "git -C '/tmp/a;b' worktree remove /tmp/r115-victim"
blk "git -C '/tmp/a|b' branch -D x"
blk "git -c 'k=a&b' push --force origin x"
blk "git --git-dir='/tmp/a;b' worktree remove /x"
blk "git --git-dir '/tmp/a;b' --no-pager branch -D x"
blk "/usr/bin/git -C '/tmp/a;b' worktree remove /x"
blk "echo \$(date) && git -C '/tmp/a;b' worktree remove /x"
# DA⑥ r2 HOLD 1(회귀): 옵션 값 안의 파괴 글자 — 정규화 전 검사문도 그대로 PATTERN (main 에서 막히던 꼴이 통과하면 안 된다)
blk "git -c 'core.sshCommand=rm -rf /tmp/r115-victim' fetch origin"
blk "git -c core.pager='rm -rf /tmp/r115-victim' log"
blk "git -C /tmp/x -c 'k=DROP TABLE t' status"
blk "git --no-pager -c 'k=tmux kill-server' status"
# DA⑥ r2 HOLD 2: shlex 실패(주석·짝 안 맞는 따옴표) — 보수 경로: git 파괴 하위명령 글자가 있으면 차단
blk "git -C '/tmp/a;b' worktree remove /tmp/r115-victim # '"
blk "git -C '/tmp/a;b' branch -D x # '"
blk "git --git-dir='/tmp/a;b' push --force origin x # '"
blk "git -c 'k=a;b' push origin +main # \""
blk "bash $HIL --cmd '$RM' # '"
# heredoc 본문(실행 소비자 아닌 명령의 stdin)은 계속 PATTERN 검사 — lines 줄 뒤 주석이 본문 합치기를 삼키던 결함 회귀 방지
blk $'psql <<EOF\nDROP TABLE t;\nEOF'
blk $'psql <<\'EOF\'\nTRUNCATE TABLE t;\nEOF'
pas "git -C '/tmp/a;b' status # '"
pas "git -C '/tmp/a;b' status"
pas "echo 'git -C /tmp/a worktree remove 글자'"
# fail-closed: 목록 파일 없음·빈 파일·목록 밖
rm "$T/hooks/hil-paths.txt"
blk "bash $HIL --cmd '$RM'"
: > "$T/hooks/hil-paths.txt"
blk "bash $HIL --cmd '$RM'"
echo "$T/bin/other.sh" > "$T/hooks/hil-paths.txt"
blk "bash $HIL --cmd '$RM'"

# 모듈 파일이 빠진 설치: hil 싱크만 꺼지고(등록 차단) 나머지 판정은 그대로(글 싱크 통과 · 파괴 차단)
mkdir -p "$T/nomod"; cp "$KIT/block-destructive.sh" "$KIT/block-destructive-judge.py" "$T/nomod/"
python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$HIL" > "$T/nomod/hil-paths.txt"
HOOK="$T/nomod/block-destructive.sh"
blk "bash $HIL --cmd '$RM'"
blk "$RM"
pas "echo 'git worktree remove 글자'"
HOOK="$T/hooks/block-destructive.sh"

# 설치 스크립트: --apply 가 hil-paths.txt 를 쓰고(realpath 줄) · dry-run 은 쓰지 않는다 (임시 홈)
KITDIR="$(cd "$KIT/.." && pwd)"; [ -f "$KITDIR/install.sh" ] || KITDIR="$HERE/../../harness/kit/fable-team"
H="$T/home"; mkdir -p "$H/.claude/hooks"
bash "$KITDIR/install.sh" --home "$H" --team t >/dev/null 2>&1
if [ ! -e "$H/.claude/hooks/hil-paths.txt" ]; then echo "PASS [inst] dry-run 목록 0"; else echo "FAIL [inst] dry-run 이 목록을 썼다"; fail=$((fail+1)); fi
bash "$KITDIR/install.sh" --apply --home "$H" --team t >/dev/null 2>&1
WANT="$(cd "$H/.fable-team/t/bin" && pwd -P)/ft-hil.sh"
if [ "$(cat "$H/.claude/hooks/hil-paths.txt" 2>/dev/null)" = "$WANT" ]; then echo "PASS [inst] --apply 목록 = 설치 ft-hil.sh realpath"; else echo "FAIL [inst] 목록 불일치 want=$WANT got=$(cat "$H/.claude/hooks/hil-paths.txt" 2>&1)"; fail=$((fail+1)); fi

echo "SUMMARY blocked=$nb pass=$np fail=$fail"
[ "$nb" -ge 22 ] && [ "$np" -ge 8 ] && [ "$fail" -eq 0 ] || { echo "FAIL 표 미달 또는 실패 있음"; exit 1; }
echo "OK"
