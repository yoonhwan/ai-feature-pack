#!/usr/bin/env bash
# test_hil_ledger.sh — C3 질문 원장 1바퀴 시험: ask → answer → applied (+ 거부·실패 경로)
# 임시 원장·FT_SEND_DRY=1·가짜 mbox 만 쓴다 — 실제 _hil_route 좌석·라이브 mbox 파일은 건드리지 않는다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"
ASK="$BIN/ft-hil-ask.sh"; ANS="$BIN/ft-hil-answer.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

export HIL_LEDGER="$T/HIL-LEDGER.md" FT_ME="seat-x" FT_HIL_ROUTE="route-seat" FT_SEND_DRY=1
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
row() { grep -E "^\| $1 \|" "$HIL_LEDGER"; }
cells() { row "$1" | awk -F'|' '{print NF-2}'; }

bash -n "$ASK" && bash -n "$ANS" && ok "bash -n" || bad "bash -n"

# 1 ask → 행 1 open · 8칸
out="$(bash "$ASK" "배포를 지금 할까요?" --options "예|아니오|보류" --recommend 예 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "ask rc=0 ($out)" || bad "ask rc=$rc $(cat "$T/err")"
[ "$(cells 1)" = 8 ] && ok "행 8칸" || bad "행 칸 수 $(cells 1)"
row 1 | grep -q '| seat-x | dry | 배포를 지금 할까요? | 예¦아니오¦보류 | 예 | open |' && ok "행1 open·좌석·선택지" || bad "행1 내용: $(row 1)"
grep -q 'DRY send to=route-seat from=seat-x body=\[HIL\] 행#1' "$T/err" && ok "mbox [HIL] → _hil_route" || bad "DRY 송신 줄 없음"

# 2 두 번째 행은 #2, 파이프는 ¦ 로
bash "$ASK" "a|b 중 뭐?" >/dev/null 2>&1
row 2 | grep -q 'a¦b 중 뭐?' && ok "행2 번호·파이프 치환" || bad "행2: $(row 2)"

# 3 answer → applied, 다른 행 불변
out="$(bash "$ANS" 1 예 2>"$T/err")"; rc=$?
[ $rc -eq 0 ] && ok "answer rc=0 ($out)" || bad "answer rc=$rc $(cat "$T/err")"
row 1 | grep -q '| applied:예 |' && ok "행1 applied:예" || bad "행1: $(row 1)"
row 2 | grep -q '| open |' && ok "행2 open 유지" || bad "행2: $(row 2)"
grep -q 'DRY send to=seat-x .*\[HIL-답\] 행#1 (질문 seq #dry) 값: 예' "$T/err" && ok "회신 = 질문 좌석" || bad "회신 줄 없음"

# 4 거부 경로
bash "$ANS" 1 아니오 >/dev/null 2>&1 && bad "applied 행 재답 허용됨" || ok "applied 행 재답 REJECT"
bash "$ANS" 99 x >/dev/null 2>&1 && bad "없는 행 허용됨" || ok "없는 행 REJECT"
bash "$ASK" "" >/dev/null 2>&1 && bad "빈 질문 허용됨" || ok "빈 질문 REJECT"
bash "$ASK" "q" --options "a|b" --recommend z >/dev/null 2>&1 && bad "선택지 밖 추천 허용됨" || ok "선택지 밖 추천 REJECT"
FT_HIL_ROUTE="" FT_SEATS="$T/none.json" bash "$ASK" "q" >/dev/null 2>&1 && bad "route 없음 허용됨" || ok "route 없음 REJECT"

# 5 mbox 실패: ask 는 행 추가 0, answer 는 answered 에서 멈추고 재시도로 applied
printf '#!/bin/bash\necho "mbox down" >&2; exit 1\n' > "$T/bad-mbox.sh"
printf '#!/bin/bash\necho "QUEUED seq=777 to=$3 pending=1 doorbell=sent"\n' > "$T/ok-mbox.sh"
n0="$(grep -cE '^\| [0-9]+ \|' "$HIL_LEDGER")"
FT_SEND_DRY=0 FT_MBOX_CMD="$T/bad-mbox.sh" bash "$ASK" "실패해야 함" >/dev/null 2>&1 && bad "mbox 실패에 ask 성공" || ok "mbox 실패 → ask exit≠0"
[ "$(grep -cE '^\| [0-9]+ \|' "$HIL_LEDGER")" = "$n0" ] && ok "mbox 실패 → 행 추가 0" || bad "실패했는데 행이 늘었다"
FT_SEND_DRY=0 FT_MBOX_CMD="$T/ok-mbox.sh" bash "$ASK" "가짜 mbox seq" >/dev/null 2>&1
row 3 | grep -q '| seat-x | 777 |' && ok "mbox seq 파싱 → 행3 seq=777" || bad "행3: $(row 3)"
FT_SEND_DRY=0 FT_MBOX_CMD="$T/bad-mbox.sh" bash "$ANS" 2 b >/dev/null 2>&1 && bad "mbox 실패에 answer 성공" || ok "mbox 실패 → answer exit≠0"
row 2 | grep -q '| answered:b |' && ok "행2 answered 에서 멈춤" || bad "행2: $(row 2)"
FT_SEND_DRY=0 FT_MBOX_CMD="$T/ok-mbox.sh" bash "$ANS" 2 b >/dev/null 2>&1
row 2 | grep -q '| applied:b |' && ok "재시도 → applied" || bad "행2: $(row 2)"

# 6 잠금 잔류 0 (라이브 mbox 는 다른 좌석도 쓰므로 해시 비교 대신, 위 모든 송신이 DRY·가짜 mbox 였음을 구조로 보장)
[ ! -d "$HIL_LEDGER.lock" ] && ok "원장 잠금 잔류 0" || bad "잠금 디렉터리가 남았다"

echo "---- ledger ----"; cat "$HIL_LEDGER"
[ $fail -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
