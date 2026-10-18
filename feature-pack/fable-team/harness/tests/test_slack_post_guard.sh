#!/usr/bin/env bash
# test_slack_post_guard.sh — slack-post-guard.sh 시험: deny 6 · allow 4(+ 비 Bash·JSON 오류 fail-open). 가짜 PreToolUse JSON 입력만 — 슬랙 호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
G="$HERE/../../harness/kit/fable-team/templates/hooks/slack-post-guard.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
bash -n "$G" && ok "bash -n" || bad "bash -n"

# run <도구> <명령> → 훅 rc
run() { python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]},"cwd":"/tmp"}))' "$1" "$2" | bash "$G" >/dev/null 2>&1; echo $?; }
deny()  { [ "$(run Bash "$2")" = 2 ] && ok "deny: $1" || bad "deny 기대인데 통과: $1"; }
allow() { [ "$(run Bash "$2")" = 0 ] && ok "allow: $1" || bad "allow 기대인데 차단: $1"; }

deny "--to slack:채널" 'hermes send --to slack:C0C6MJGRR89 "제안서 본문"'
deny "-t slack" 'hermes send -t slack -m hi'
deny "-t slack:#채널" 'hermes send -t slack:#byz-agent "x"'
deny "--to slack 값 분리" 'hermes send --to slack "x"'
deny "변수 대입 우회" 'T=slack; hermes send -t $T "x"'
deny "따옴표 분리 우회" "hermes send -t 'sl''ack' x"
deny "앞 명령 결합" 'cd /tmp && hermes send --to slack:C1 "m"'

allow "telegram" 'hermes send --to telegram:123 hi'
allow "--list" 'hermes send --list slack'
allow "hermes send 아님" 'ls ~/.hermes/skills | grep slack'
allow "무관한 명령" 'git status --short'
allow "heredoc 본문 안의 글자" $'cat <<\'EOF\' > /tmp/x.md\nhermes send -t slack 설명\nEOF'
# 실측 오탐 4건(master 재현 62867) — hermes 가 명령 위치에 없다
allow "오탐1 mbox send 본문에 slack hermes 낱말" 'bash .fable-team/comm/mbox.sh send master me "hermes send -t slack 금지 훅 수정: slack 낱말 오탐"'
allow "오탐2 git commit -m 메시지" 'git commit -m "[feature] hermes send slack 차단 훅 slack-post-guard"'
allow "오탐3 grep send slack-mirror ~/.hermes" 'grep -rn "send" ~/.hermes/scripts/slack-mirror ~/.hermes/skills | head'
allow "오탐4 tail gateway.log | grep 패턴" 'tail -200 ~/.hermes/logs/gateway.log | grep -E "hermes.*send.*slack"'
allow "대상 인자 없는 hermes send" 'hermes send hello'
deny "빈 따옴표로 쪼갠 명령어 her\"\"mes" 'her""mes send -t slack x'
deny "파이프 뒤 xargs hermes" 'echo msg | xargs hermes send -t slack'
deny "xargs 옵션(-I {}) 뒤 hermes" 'echo msg | xargs -I {} hermes send -t slack:C1 {}'
allow "xargs 로 다른 명령" 'echo msg | xargs -n 1 echo hermes send -t slack'
deny "bash -c 안쪽 재귀" "bash -c 'hermes send -t slack:C1 x'"
deny "env 접두 + 경로 hermes" 'env X=1 ~/.hermes/bin/hermes send --to=slack:C1 x'

# deny 마다 오탐 기록 1줄(state/hook-falsepos.log) — allow 는 기록 0
LOG="$(mktemp)"; export FT_HOOK_FALSEPOS_LOG="$LOG"; : > "$LOG"
run Bash 'git status' >/dev/null; [ ! -s "$LOG" ] && ok "log: allow 는 기록 0" || bad "log: allow 가 기록함"
run Bash 'hermes send -t slack:C1 "원문 X"' >/dev/null
[ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] && grep -q 'hermes send -t slack:C1 "원문 X"' "$LOG" && ok "log: deny 1건 = 원문 1줄" || bad "log: $(cat "$LOG")"
export FT_HOOK_FALSEPOS_LOG="/proc-none-$$/x/log"   # 루트 아래 디렉터리 생성 불가 경로 — 기록 실패를 흉내
[ "$(run Bash 'hermes send -t slack x')" = 2 ] && ok "log: 기록 실패해도 deny 유지" || bad "log 실패 시 deny 풀림"
unset FT_HOOK_FALSEPOS_LOG; rm -f "$LOG"

# 비 Bash 도구 · JSON 오류 = fail-open(허용)
[ "$(run Read 'hermes send -t slack x')" = 0 ] && ok "allow: 비 Bash 도구" || bad "비 Bash 도구 차단"
echo 'not json' | bash "$G" >/dev/null 2>&1; [ "$?" = 0 ] && ok "allow: JSON 오류 fail-open" || bad "JSON 오류 차단"

echo "fail=$fail"; [ "$fail" = 0 ]
