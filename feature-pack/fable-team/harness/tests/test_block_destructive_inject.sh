#!/usr/bin/env bash
# test_block_destructive_inject.sh — 키트 block-destructive 훅의 INJECT 블록(R63b)에 PreToolUse JSON 만 넣어 종료코드를 본다.
# 홈 훅·실제 명령 실행 0 (명령은 JSON 문자열일 뿐). 대조표 1행 = 1검사 + 변이(복사본에서 결과가 뒤집혀야 시험이 «잡는 힘»이 있다).
# TABLE_OUT=<경로> 를 주면 대조표(markdown 행)를 그 파일에 쓴다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
HOOK="${BD_HOOK:-$ROOT/scripts/harness-install/fable-team/templates/hooks/block-destructive.sh}"
T="$(mktemp -d)"
trap '[ -n "$T" ] && rm -rf "$T"' EXIT
git -C "$T" init -q
mkdir -p "$T/.fable-team/comm"
: > "$T/.fable-team/comm/mbox.sh"
MB="$T/.fable-team/comm/mbox.sh"
H="$HOOK"
fail=0; nb=0; np=0; nm=0
[ -n "${TABLE_OUT:-}" ] && : > "$TABLE_OUT"

run() {  # <명령> → H 훅 종료코드 (JSON cwd = 임시 리포 · 셔뱅 그대로 /bin/bash)
  python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$1" "$T" \
    | /bin/bash "$H" >/dev/null 2>&1
  return $?
}
expect() {  # <id> <기대 rc> <카운터> <명령>
  local id="$1" want="$2" ctr="$3" cmd="$4" rc shown
  run "$cmd"; rc=$?
  if [ "$rc" = "$want" ]; then echo "PASS [$id] rc=$rc :: ${cmd:0:70}"; eval "$ctr=\$(($ctr+1))"
  else echo "FAIL [$id] want=$want got=$rc :: $cmd"; fail=$((fail+1)); fi
  if [ -n "${TABLE_OUT:-}" ]; then
    shown="${cmd//$'\n'/⏎}"; shown="${shown//|/\\|}"
    printf '| %s | `%s` | %s | %s |\n' "$id" "${shown//$MB/<mbox.sh>}" "$want" "$rc" >> "$TABLE_OUT"
  fi
}
blk() { expect "$1" 2 nb "$2"; }
pas() { expect "$1" 0 np "$2"; }
mut() {  # <출력> <바꿀 글자> <새 글자> — 변이 복사본 (적용 안 되면 시험 실패)
  python3 -c 'import sys
t=open(sys.argv[1]).read()
if sys.argv[3] not in t: sys.exit(1)
open(sys.argv[2],"w").write(t.replace(sys.argv[3],sys.argv[4],1))' "$HOOK" "$1" "$2" "$3" \
    || { echo "FAIL [변이 미적용] $1"; fail=$((fail+1)); }
}

# ── 차단 (B) ────────────────────────────────────────────────────────────
blk B1 'redis-cli PUBLISH room_events:r1 '"'"'{"t":1}'"'"
blk B2 'redis-cli -p 6380 SET k v'
blk B3 'docker exec byz-redis redis-cli HSET k f v'
blk B4 'bash -c "redis-cli XADD s '"'*'"' a b"'
blk B5 "curl -s 'http://127.0.0.1:3001/dev/bubble-replay?scenario=static'"
blk B6 $'python3 - <<\'EOF\'\npage.goto(\'http://x/dev/bubble-replay\')\nEOF'
blk B7a 'redis-cli -c -p 7000 SET k v'
blk B7b 'redis-cli -h 10.0.0.1 -p 6379 -n 2 HSET k f v'
blk B7c 'redis-cli "PUBLISH" ch x'
blk B7d 'rg x tests; redis-cli SET k v'
blk B7e 'gh pr view 1; curl -s http://h/dev/bubble-replay'
blk B8 'redis-cli --user=u -p 1 SET k v'
blk B9 'python3 run.py --url "$BASE/dev/bubble-replay"'

# ── 통과 (P) ────────────────────────────────────────────────────────────
pas P1a 'redis-cli GET k'
pas P1b 'redis-cli HGETALL k'
pas P1c "redis-cli --scan --pattern 'stt:*'"
pas P1d 'redis-cli GET setting'
pas P2a 'redis-cli DEL k'
pas P2b 'redis-cli FLUSHDB'
pas P3 'python -m pytest tests/shared/prompts -q'
pas P4 'python3 tests/e2e/realtime_multi_e2e.py --help'
pas P5 'curl -s http://127.0.0.1:8080/health'
pas P6 "bash $MB send a#1 b#1 \"redis-cli SET 와 /dev/bubble-replay 글자 인용\""
pas P7a "grep -n 'redis-cli PUBLISH' f"
pas P7b 'echo "/dev/bubble-replay"'
pas P7c 'git commit -m "redis-cli SET 금지"'
# r1 반송 오탐 7행 (arch 재현)
pas P8a 'npx eslint app/dev/bubble-replay/page.tsx'
pas P8b 'ls clients/web/app/dev/bubble-replay/'
pas P8c 'git diff origin/main -- clients/web/app/dev/bubble-replay/page.tsx'
pas P8d "git grep -n 'redis-cli PUBLISH' origin/main"
pas P8e "rg -n 'redis-cli SET' tests"
pas P8f "gh pr create --title x --body 'redis-cli SET 금지 카드'"
pas P8g 'redis-cli GET "set"'
pas P9a 'redis-cli -c -p 7000 GET k'
pas P9b 'redis-cli -h 10.0.0.1 -n 2 HGETALL k'
pas P10a "redis-cli --scan --pattern 'session:*' | head"
pas P10b 'redis-cli CONFIG GET maxmemory'
pas P10c "cat f.sh | grep -n 'redis-cli SET'"
pas P11a 'git grep -n /dev/bubble-replay origin/main'
pas P11b 'rg -n "redis-cli SET k v" tests'
# r2 (DA r1 Q2): 실행 치환이 있으면 검색·게시 예외 0
blk B10a 'gh pr create --title x --body "$(redis-cli SET k v)"'
blk B10b 'gh pr comment 1 --body "`redis-cli HSET k f v`"'
blk B10c 'rg x <(redis-cli SET k v)'
blk B10d 'git grep -n x $(redis-cli PUBLISH ch m)'
pas P12a 'echo "$(date)"'
pas P12b 'git log --format=%h -1 $(git merge-base origin/main HEAD)'
pas P12c 'gh pr create --title x --body-file /tmp/b.md'
# r3 (DA r2 Q2): 따옴표·역슬래시 이어붙임은 한 단어로 본다
blk B11a 'gh pr create --body "$(redis-'"''"'cli SET k v)"'
blk B11b 'gh pr create --body "$(redis-cli S'"''"'ET k v)"'
blk B11c "redis-''cli SET k v"
blk B11d 're\dis-cli SET k v'
blk B11e 'redis-cli "S"ET k v'
pas P13 "redis-cli GET 'SET'"

# ── 변이 (M): 변이 복사본에서는 결과가 뒤집혀야 한다 ──────────────────────
mut "$T/m1.sh" 'printf '"'%s'"' "$CHK" | grep -qiE' 'printf '"'%s'"' "$CMD" | grep -qiE'                  # EFFECTIVE→원문
sed '/^# INJECT-BEGIN$/,/^# INJECT-END$/d' "$HOOK" > "$T/m2.sh"                                         # 블록 제거
cmp -s "$HOOK" "$T/m2.sh" && { echo "FAIL [변이 미적용] m2"; fail=$((fail+1)); }
mut "$T/m3.sh" 's#$INJECT_SKIP#\\1#g; ' ''                                                              # 검색·게시 구간 제거 빼기
mut "$T/m4.sh" 'INJECT_PATTERN="$INJECT_REDIS|/dev/bubble-replay"' \
  $'INJECT_PATTERN="redis-cli[^;&|]*[[:space:]\'\\"]($INJECT_VERBS)([[:space:]\'\\"]|\\$)|/dev/bubble-replay"'  # 옛 «아무 위치» 규칙
mut "$T/m5.sh" '; s#app/dev/bubble-replay##g' ''                                                        # 페이지 경로 제거 빼기
mut "$T/m6.sh" "*'\$('*|*'\`'*|*'<('*|*'>('*)" "*'ZZNEVERZZ'*)"                                         # 치환 검사 case 빼기
mut "$T/m7.sh" ' | LC_ALL=C tr -d "\\\\'"'"'\""' ''                                                  # tr -d 빼기
H="$T/m1.sh"
expect M1-P6 2 nm "bash $MB send a#1 b#1 \"redis-cli SET 와 /dev/bubble-replay 글자 인용\""
expect M1-P7b 2 nm 'echo "/dev/bubble-replay"'
expect M1-P7c 2 nm 'git commit -m "redis-cli SET 금지"'
H="$T/m2.sh"
expect M2-B1 0 nm 'redis-cli PUBLISH room_events:r1 '"'"'{"t":1}'"'"
expect M2-B5 0 nm "curl -s 'http://127.0.0.1:3001/dev/bubble-replay?scenario=static'"
H="$T/m3.sh"
expect M3-P8f 2 nm "gh pr create --title x --body 'redis-cli SET 금지 카드'"
expect M3-P11a 2 nm 'git grep -n /dev/bubble-replay origin/main'
expect M3-P11b 2 nm 'rg -n "redis-cli SET k v" tests'
H="$T/m4.sh"
expect M4-P8g 2 nm 'redis-cli GET "set"'
H="$T/m5.sh"
expect M5-P8a 2 nm 'npx eslint app/dev/bubble-replay/page.tsx'
expect M5-P8b 2 nm 'ls clients/web/app/dev/bubble-replay/'
H="$T/m6.sh"
expect M6-B10a 0 nm 'gh pr create --title x --body "$(redis-cli SET k v)"'
expect M6-B10b 0 nm 'gh pr comment 1 --body "`redis-cli HSET k f v`"'
H="$T/m7.sh"
expect M7-B11a 0 nm 'gh pr create --body "$(redis-'"''"'cli SET k v)"'
expect M7-B11b 0 nm 'gh pr create --body "$(redis-cli S'"''"'ET k v)"'
H="$HOOK"

echo "SUMMARY block=$nb pass=$np mutant=$nm fail=$fail"
[ "$nb" -eq 22 ] && [ "$np" -eq 31 ] && [ "$nm" -eq 15 ] && [ "$fail" -eq 0 ] || { echo "FAIL 표 미달 또는 실패 있음"; exit 1; }
echo "OK"
