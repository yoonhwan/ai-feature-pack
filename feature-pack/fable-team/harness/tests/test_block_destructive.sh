#!/usr/bin/env bash
# test_block_destructive.sh — 키트 block-destructive 훅(판정 466)에 PreToolUse JSON 만 넣어 종료코드를 본다.
# 홈 훅·실제 명령 실행 0 (명령은 JSON 문자열일 뿐). mbox 시험은 mktemp 임시 git 리포 + 빈 mbox.sh 만 쓴다.
# 표: 차단 유지(exit 2) ≥ 52 · 통과(exit 0) ≥ 18 · STAGE 회귀 2 · 실측 표본 재생 5.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
HOOK="${BD_HOOK:-$ROOT/harness/kit/fable-team/templates/hooks/block-destructive.sh}"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
git -C "$T" init -q
mkdir -p "$T/.fable-team/comm"
: > "$T/.fable-team/comm/mbox.sh"
MB="$T/.fable-team/comm/mbox.sh"
fail=0; nb=0; np=0; ns=0; nr=0

run() {  # <명령> [JSON cwd — 기본 임시 리포 · "-" 면 cwd 키 없음] → 훅 종료코드 (셔뱅 그대로 /bin/bash)
  python3 -c 'import json,sys
d={"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}
if sys.argv[2]!="-": d["cwd"]=sys.argv[2]
print(json.dumps(d))' "$1" "${2:-$T}" \
    | /bin/bash "$HOOK" >/dev/null 2>&1
  return $?
}
expect() {  # <기대 rc> <종류 카운터 이름> <명령> [JSON cwd]
  local want="$1" ctr="$2" cmd="$3" rc
  run "$cmd" "${4:-}"; rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS [$ctr] rc=$rc :: ${cmd:0:70}"; eval "$ctr=\$(($ctr+1))"
  else echo "FAIL [$ctr] want=$want got=$rc :: $cmd"; fail=$((fail+1)); fi
}
blk() { expect 2 nb "$1" "${2:-}"; }
pas() { expect 0 np "$1" "${2:-}"; }
stg() { expect 2 ns "$1"; }
smp() { expect 0 nr "$1"; }

# ── 차단 유지: 패턴 15종 각각 명령 자리 ─────────────────────────────────
blk 'tmux kill-server'
blk 'pkill -f x'
blk 'kill -9 1'
blk 'git branch -D x'
blk 'git push --force'
blk 'git push -f origin x'
blk 'git push origin +main'
blk 'git push origin +HEAD:main'
blk 'git push origin :main'
blk 'git push --delete origin x'
blk 'git push -d origin x'
blk 'git push --mirror origin'
blk 'git push --force-with-lease origin x'
blk 'rm -rf /tmp/zz'
blk 'rm -fr /tmp/zz'
blk 'rm -r -f /tmp/zz'
blk 'dropdb x'
blk 'psql -c "DROP TABLE t"'
blk 'psql -c "TRUNCATE TABLE t"'
blk 'gcloud compute instances delete vm1'
blk 'terraform destroy'
blk 'kubectl delete pod x'
blk 'git worktree remove x'
blk 'supabase db delete x'
# ── 차단 유지: 우회 꼴 ──────────────────────────────────────────────────
blk 'bash -c "rm -rf /tmp/zz"'
blk "sh -c 'pkill -f x'"
blk 'eval "git branch -D x"'
blk 'echo "$(rm -rf /tmp/zz)"'
blk 'echo `rm -rf /tmp/zz`'
blk 'X=1 rm -rf /tmp/zz'
blk 'sudo rm -rf /tmp/zz'
blk 'cd /tmp && rm -rf zz'
blk 'echo "rm -rf zz" | sh'
blk "printf 'x' | xargs kill -9"
blk $'bash <<EOF\nrm -rf zz\nEOF'
blk $'python3 - <<EOF\nimport os\nos.system("rm -rf zz")\nEOF'
blk '$CMD rm -rf x'
blk 'echo "rm -rf zz'
# ── 차단 유지: DA r1·r2·r3 반례 ─────────────────────────────────────────
blk "printf '%s\n' 'rm -rf zz' > x.sh && bash x.sh"
blk "printf 'DROP TABLE t' > x.sql && psql -f x.sql"
blk "echo 'DROP TABLE t' | psql"
blk "P='rm -rf zz'; eval \"\$P\""
blk "P='DROP TABLE t'; psql -c \"\$P\""
blk $'cat <<\'EOF\' > >(bash)\nrm -rf zz\nEOF'
blk $'cat <<EOF\n$(rm -rf zz)\nEOF'
blk "printf '%s' '#'; rm -rf zz"
blk "printf '%s\n' 'rm -rf zz' | tee x | sh"
blk $'cat <<A; cat <<B\nhello\nA\nrm -rf zz\nB'
blk $'cat <<EOF | bash\nrm -rf zz\nEOF'
blk $'cat > t.sh <<\'EOF\' && chmod +x t.sh && ./t.sh\nrm -rf zz\nEOF'
blk '{ rm -rf zz; }'
blk '! rm -rf zz'
blk 'time rm -rf zz'
blk 'coproc rm -rf zz'
blk $'rm -rf \\\n/tmp/zz'
blk $'echo $\'rm -rf zz\''
blk "bash /tmp/x/mbox.sh send a b 'rm -rf zz'"
blk "bash \$M send a b 'rm -rf zz'"
blk "rg --pre 'rm -rf zz' ."
blk "P='DROP TABLE t'; V=P; psql -c \"\${!V}\""
blk "P='DROP TABLE t'; declare -n V=P; psql -c \"\$V\""
# ── 차단 유지: 구현 중 추가한 경계 (정본 mbox 뒤 다른 구간 · 경로 ".." · printf -v 대입) ──
blk "bash $MB send a#1 b#1 \"ok\"; rm -rf /tmp/zz"
blk "bash $T/.fable-team/../.fable-team/comm/mbox.sh send a#1 b#1 'rm -rf zz'"
blk "printf -v P '%s' 'DROP TABLE t'; psql -c \"\$P\""

# ── 통과: 글자로만 들어 있는 명령 ────────────────────────────────────────
pas "bash $MB send a#1 b#1 \"git branch -D x 원문 인용\""
pas "bash $MB relay a#1 b#1 /tmp/f \"rm -rf zz 요약\""
pas "bash $MB send a#1 b#1 \"pkill 원문\" 2>&1 | tail -1"
pas 'echo "gcloud iam service-accounts keys delete 문장"'
pas "printf '%s\n' \"rm -rf zz 설명\" >> ledger.md"
pas 'git commit -m "git push --force 금지 기록"'
pas 'grep -E "tmux kill-server|kill -9" f | head'
pas "P='tmux kill-server|pkill'; grep -oiE \"\$P\" f"
pas $'cat > t.sh <<\'EOF\'\ntrap \'rm -rf "$T"\' EXIT\nEOF'
pas $'tee f <<\'EOF\'\nDROP TABLE t;\nEOF'
pas 'echo a; grep -c "kill -9" f'
pas 'ls -la'
pas $'cat <<\'EOF\'\nrm -rf zz\nEOF'
pas "echo 'dropdb x' >> /dev/null"
pas 'git push origin main'
pas 'git push -u origin feat/x'
pas 'git push origin HEAD:refs/heads/x'
pas 'git push --dry-run origin x'
pas 'git commit -m "git push origin +main 금지 기록"'
pas "bash $MB send a#1 b#1 \"git push --delete 원문 인용\""

# ── R64 상대경로 정본 mbox: JSON cwd 기준 realpath 일치만 글 싱크 (cd/pushd/popd 있으면 인정 0) ──
T2="$(mktemp -d)"; trap '[ -n "$T" ] && rm -rf "$T" "$T2"' EXIT
git -C "$T2" init -q; mkdir -p "$T/a/b" "$T2/.fable-team/comm"
: > "$T2/.fable-team/comm/mbox.sh"; : > "$T2/x.sh"
ln -s "$MB" "$T/a/link.sh"; ln -s "$T2/x.sh" "$T/a/evil.sh"
REL2="$(python3 -c 'import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))' "$T2/.fable-team/comm/mbox.sh" "$T/a/b")"
pas "bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz 인용'" "$T/a/b"
pas "bash .fable-team/comm/mbox.sh send x y 'git branch -D x 인용'" "$T"
pas "bash ../link.sh send x y 'rm -rf zz'" "$T/a/b"
blk "cd /tmp && bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "c''d /tmp && bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "c\\d /tmp && bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "cd; bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "c''d; bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "popd; bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "bash $REL2 send x y 'rm -rf zz'" "$T/a/b"
blk "bash ../evil.sh send x y 'rm -rf zz'" "$T/a/b"
blk "bash \$D/../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "$T/a/b"
blk "bash ../../.fable-team/comm/mbox.sh send x y 'rm -rf zz'" "-"

# ── STAGE 회귀 (이 카드 무변경) ──────────────────────────────────────────
stg 'git add -A'
stg 'git add .'

# ── 실측 표본 재생 (hil-falsepos.log 10-08 ①~⑤ 꼴 · 본문은 재구성) ──────────
PAT="$(sed -n "s/^PATTERN='\(.*\)'$/\1/p" "$HOOK")"
smp "bash $MB send arch#1 nano#1 \"[보고] 훅이 tmux kill-server 와 git branch -D 글자를 막았다\""
smp 'echo "오빠, 훅이 rm -rf 글자만 보고 막았습니다"'
smp $'cat > t.sh <<\'EOF\'\n#!/bin/bash\ntrap \'rm -rf "$T"\' EXIT\nEOF'
smp "P='$PAT'; grep -c \"\$P\" f"
smp "printf '| R39 | %s | rm -rf 오탐 |\n' x >> ledger.md"

echo "SUMMARY blocked=$nb pass=$np stage=$ns sample=$nr fail=$fail"
[ "$nb" -ge 52 ] && [ "$np" -ge 18 ] && [ "$ns" -eq 2 ] && [ "$nr" -eq 5 ] && [ "$fail" -eq 0 ] || { echo "FAIL 표 미달 또는 실패 있음"; exit 1; }
echo "OK"
