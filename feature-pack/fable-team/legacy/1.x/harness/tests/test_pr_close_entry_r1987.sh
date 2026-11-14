#!/usr/bin/env bash
# test_pr_close_entry_r1987.sh — r1987: 사람 실행 h 의 PR 닫기 진입점 ft-pr-close.sh = ft-merge-lib.sh fm_pr_close 그대로(착지와 같은 쓰기 신원 표)
#   반례 ①~④(카드 동결) · 변이 M1(표 건너뛰고 맨 gh) · M2(실패 삼킴) · 키트 cmp · 가짜 gh·가짜 tank · 실 gh·실 토큰·실 원격 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; BIN="$(cd "$HERE/../bin" && pwd -P)"
fail=0; rc=0; out=""; T0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300} log=$(tr '\n' '|' <"$LOG" 2>/dev/null | cut -c1-300)"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; LOG="$T/gh.log"; echo "닫습니다" > "$T/body.md"
printf '#!/bin/bash\necho "GH $* tok=${GH_TOKEN:-}${GITHUB_TOKEN:-}" >> "$STUB_LOG"\n[ -z "${FAIL_GH:-}" ] || { echo "GraphQL: 가짜 실패" >&2; exit 1; }\n' > "$T/gh"
printf '#!/bin/bash\necho "TANK $* repo=${FT_ISSUE_REPO:-}" >> "$STUB_LOG"\n' > "$T/tank"; chmod +x "$T/gh" "$T/tank"
export FT_GH="$T/gh" FT_GH_WRITE="$T/tank" STUB_LOG="$LOG" GH_TOKEN=bot-tok GITHUB_TOKEN=bot-tok2; unset FT_PR_CLOSE_AS_USER FAIL_GH
run() { local s="$1"; shift; : > "$LOG"; out="$(env "$@" bash "$s" "${ARGS[@]}" 2>&1)"; rc=$?; }
case_all() {  # case_all <진입점> <접두> — 반례 ①~④
  local s="$1" p="$2"
  ARGS=(yoonhwan/ai-feature-pack 1171 "$T/body.md"); run "$s"
  [ "$rc" = 0 ] && [ "$(grep -c '^GH pr close 1171 -R yoonhwan/ai-feature-pack --comment 닫습니다 tok=$' "$LOG")" = 1 ] && ! grep -q '^TANK' "$LOG"
  ck "${p}① 팩 → 가짜 gh 1회 · GH_TOKEN·GITHUB_TOKEN 빈 · tank 0 · rc0" $?
  ARGS=(yoonhwan/BYZ-Agents 42 "$T/body.md"); run "$s"
  [ "$rc" = 0 ] && grep -q "^TANK pr-close 42 --comment $T/body.md --apply repo=yoonhwan/BYZ-Agents$" "$LOG" && ! grep -q '^GH' "$LOG"
  ck "${p}② BYZ → 쓰기 도구(가짜 tank) 1회 · gh 0" $?
  ARGS=(yoonhwan/ai-feature-pack 7 "$T/body.md"); run "$s" FAIL_GH=1
  [ "$rc" != 0 ] && [ "$(grep -c '^ERROR PR #7 닫기 실패' <<<"$out")" = 1 ] && ! grep -q '^TANK' "$LOG"
  ck "${p}③ 가짜 gh 실패 → rc≠0 · 사유 1줄 · 갈아타기 0" $?
  ARGS=(yoonhwan/ai-feature-pack 7 "$T/없음.md"); run "$s"
  [ "$rc" = 2 ] && [[ "$out" == usage:* ]] && [ ! -s "$LOG" ]
  ck "${p}④ 본문 파일 없음 → usage rc2 · gh 호출 0" $?
}
S1=$SECONDS; case_all "$BIN/ft-pr-close.sh" ""; S2=$SECONDS
mut() {  # mut <이름> <바꿀 문자열> <새 문자열> <잡혀야 할 반례 접두>
  rm -rf "$T/m"; cp -R "$BIN" "$T/m"
  python3 -c 'import sys;p,a,b=sys.argv[1:];s=open(p).read();assert s.count(a)==1,a;open(p,"w").write(s.replace(a,b))' "$T/m/ft-pr-close.sh" "$2" "$3" || { echo "FAIL 변이 $1 적용 못 함"; fail=$((fail+1)); return; }
  local f0=$fail; case_all "$T/m/ft-pr-close.sh" "[$1] " >"$T/mut.out"
  fail=$f0; grep -q "^FAIL \[$1\] $4" "$T/mut.out"; ck "변이 $1 → $4 FAIL(반례가 잡음)" $?
}
mut M1 'fm_pr_close "$1" "$2" "$3" "${FT_GH_WRITE:-$HERE/ft-gh-as-tank.sh}"' '"${FT_GH:-gh}" pr close "$2" -R "$1" --comment "$(cat "$3")"' ①
mut M2 'exit "$rc"' 'exit 0' ③
S3=$SECONDS
cmp -s "$BIN/ft-pr-close.sh" "$BIN/../kit/fable-team/bin/ft-pr-close.sh"; ck "키트 사본 cmp0" $?
echo "단계별 초: 반례 $((S2 - S1)) · 변이 $((S3 - S2)) · 합계 $((SECONDS - T0))"
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
