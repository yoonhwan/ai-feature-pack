#!/usr/bin/env bash
# test_proposal_interview_gate.sh — proposal-interview-gate.sh(PreToolUse:AskUserQuestion 훅) 시험(R77 r1 · 판정 826). stdin JSON 만 먹인다 — 실 도구·실 gh 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK="$HERE/../../scripts/harness-install/fable-team/templates/hooks/proposal-interview-gate.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1 :: rc=$rc out=$out"; fail=$((fail+1)); }
bash -n "$HOOK" && ok "bash -n" || bad "bash -n"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_PROPOSAL_INTERVIEW_LOG="$T/log/proposal-interview-gate.log"
GH="https://github.com/SecondWindStudio/byz-agents/issues/12"; SLACK="https://x.slack.com/archives/C0C6MJGRR89/p1791590226702839"
# ask <question> <header> <label> <description> <preview> → AskUserQuestion stdin JSON
ask() { python3 -c 'import json,sys;q,h,l,d,p=sys.argv[1:6];print(json.dumps({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":q,"header":h,"multiSelect":False,"options":[{"label":l,"description":d,"preview":p},{"label":"다른 안","description":"x"}]}]}},ensure_ascii=False))' "$@"; }
run() { out="$(printf '%s' "$1" | bash "$HOOK" 2>/dev/null)"; rc=$?; }
denied() { echo "$out" | python3 -c 'import json,sys;d=json.load(sys.stdin)["hookSpecificOutput"];sys.exit(0 if d["permissionDecision"]=="deny" and "제안 Issue 링크 필수(판정 826)" in d["permissionDecisionReason"] else 1)' 2>/dev/null; }
allowed() { [ "$rc" = 0 ] && [ -z "$out" ]; }

run "$(ask "제안 Issue #12 를 승인할까요? 원문 $GH" 승인 '승인' '채택' '')";   allowed && ok "1 제안 Issue 번호 + Issue 링크 → allow" || bad "1"
run "$(ask '제안 Issue #12 를 승인할까요?' 승인 '승인' '채택' '')";            [ "$rc" = 0 ] && denied && ok "2 「제안 Issue #12 승인할까요」 링크 없음 → deny" || bad "2"
run "$(ask '제안서 #12 를 컨펌하시겠어요?' 승인 '예' '컨펌' '')";               [ "$rc" = 0 ] && denied && ok "2b 「제안서 #12」 링크 없음 → deny" || bad "2b"
run "$(ask '어느 안으로 갈까요?' 선택 'PROPOSAL-foo-20261010.md 채택' 'A안' "원문 $SLACK")"
[ "$rc" = 0 ] && denied && ok "3 PROPOSAL 경로 + 슬랙 링크만(Issue 링크 없음) → deny" || bad "3"
run "$(ask '어느 안으로 갈까요?' 선택 'PROPOSAL-foo-20261010.md 채택' 'A안' "원문 $GH")"
allowed && ok "3b PROPOSAL 경로 + Issue 링크 → allow" || bad "3b"
run "$(ask '[HIL] 제안서 원본 파일 보존 작업을 승인할까요?' HIL '예' '보존' '')"
allowed && ok "4 ★B1 반례★ 일반 HIL 승인 질문(제안서 파일 보존) → allow" || bad "4"
run "$(ask '제안서 폴더를 정리해도 될까요?' HIL '정리' '이동' '')";               allowed && ok "4b 제안서 낱말만 있는 질문 → allow" || bad "4b"
run "$(ask '배포 방식을 고를까요?' 배포 '롤링' '순차 교체' '')";                 allowed && ok "5 제안 무관 질문 → allow" || bad "5"
run '{깨진 json'
allowed && grep -q 'JSON 파싱 불가' "$FT_PROPOSAL_INTERVIEW_LOG" && ok "6 깨진 JSON → allow + 로그 1줄" || bad "6 log=$(cat "$FT_PROPOSAL_INTERVIEW_LOG" 2>&1)"
run '{"tool_name":"AskUserQuestion","tool_input":{}}';                          allowed && ok "7 questions 없음 → allow" || bad "7"
out="$(printf '' | bash "$HOOK" 2>&1)"; rc=$?; allowed && ok "8 빈 stdin → allow" || bad "8"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
