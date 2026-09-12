#!/bin/bash
# ft-goal-tick.sh — OS crontab 에서 실행되는 «골 틱» (세션이 죽어도 계속 온다).
#   crontab:  */4 * * * *  <절대경로>/ft-goal-tick.sh >>/tmp/ft-goal-tick.log 2>&1
#   대상 좌석: FT_GOAL_TICK_TARGET (기본 ft-v65-master#39) — 승계 시 crontab 한 줄만 바꾼다.
#
# 무엇을 «강제»하나 (#11389 ①~④):
#   ① 업데이트 = «좌석 원장»(.fable-team/state/goal-read-ledger.json) 의 read_at/head_sha/cited.
#      골 원장 파일은 안 바뀐다(수락 항목 원장). 바뀌는 것은 «읽었다는 증거»다.
#   ② 주기 4분(정각 회피). 디바운스는 안 한다 — 틱마다 ft-goal-check 결과가 «값»으로 큐에 남는다.
#   ③ 크론이 하는 일 = ft-goal-check.sh 를 «먼저 실행»하고 그 출력(GOAL-OK+NEXT / REREAD-REQUIRED)을
#      틱 프롬프트 «맨 앞»에 박아 mbox 로 보낸다. 좌석이 스크립트를 안 돌려도 결과는 도착한다.
#   ④ 강제 = 3중: (a) REREAD-REQUIRED 면 프롬프트 1번이 「정본 열고 --touch 뒤에만 착수」
#      (b) commit-msg 훅이 같은 상태를 읽어 만료면 커밋 거부 (c) 연속 3틱 REREAD-REQUIRED 면
#      사람 호출 줄을 프롬프트에 추가 + ~/.claude/…/goal-tick-alert 스탬프.
set -uo pipefail
# [master#39 2026-09-12] 크론 기본 PATH 에 tmux 가 없어 5회 연속 "target absent" 로 헛돌았다
#   (11:32/36/40/44/48/52 · 세션은 실재 · env -i PATH=/usr/bin:/bin tmux -> "No such file").
#   crontab 한 줄로 고치는 대신 스크립트가 자기 PATH 를 보장한다 — 승계·재설치 때도 따라간다.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
ROOT="${FT_GOAL_TICK_ROOT:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees/v6-realtime-live}"
TARGET="${FT_GOAL_TICK_TARGET:-ft-v65-master#39}"
STREAK_FILE="${FT_GOAL_TICK_STREAK:-/tmp/ft-goal-tick.streak}"
cd "$ROOT" || exit 0
MBOX=.fable-team/comm/mbox.sh
CHECK="${FT_GOAL_TICK_CHECK:-.fable-team/bin/ft-goal-check.sh}"
PROMPT=design/v65/20260912/TICK-PROMPT-v65-unified.md
[ -x "$MBOX" ] && [ -x "$CHECK" ] && [ -f "$PROMPT" ] || { echo "$(date '+%F %T') missing mbox/check/prompt — exit"; exit 0; }
tmux has-session -t "=$TARGET" 2>/dev/null || { echo "$(date '+%F %T') target absent: $TARGET"; exit 0; }

# ① 골 게이트를 «크론이» 먼저 돌린다 — 파이프 금지, rc 를 따로 잡는다.
GATE_OUT="$(bash "$CHECK" "$TARGET" 2>&1)"; GATE_RC=$?

# ④(c) 연속 REREAD 카운트
if [ "$GATE_RC" -eq 3 ]; then
  STREAK=$(( $(cat "$STREAK_FILE" 2>/dev/null || echo 0) + 1 )); echo "$STREAK" > "$STREAK_FILE"
else
  STREAK=0; echo 0 > "$STREAK_FILE"
fi
ALERT=""
if [ "$STREAK" -ge 3 ]; then
  ALERT="★★ 연속 ${STREAK}틱 REREAD-REQUIRED — 좌석이 골 원장을 안 열고 있다. 이 틱은 착수 금지, 오빠에게 «골 원장 미독 ${STREAK}틱» 1줄 보고 후 정본을 연다. ★★"
fi

# ③ 프롬프트 = 게이트 결과 + 단일본(코드블록 안) · <세션명> 치환
BODY="$(awk '/^```/{f=!f; next} f' "$PROMPT" | sed "s/<세션명>/$TARGET/g")"
MSG="[goal-tick $(date '+%H:%M') · OS크론 · 세션 무관] ft-goal-check 결과(rc=$GATE_RC):
$GATE_OUT
${ALERT:+$ALERT
}— 위 결과가 REREAD-REQUIRED 면 아래 2번을 «먼저» 이행한다. GOAL-OK 면 NEXT 행이 이번 틱의 착수 단위다.

$BODY"

# 긴 본문은 relay 정본 절차(요약+경로) — 700자 넘는 것을 큐에 직접 넣지 않는다.
TMP="$(mktemp /tmp/goal-tick.XXXXXX)"; printf '%s\n' "$MSG" > "$TMP"
SUMMARY="[goal-tick $(date '+%H:%M')] rc=$GATE_RC · $(printf '%s' "$GATE_OUT" | head -1 | cut -c1-160)${ALERT:+ · ★연속 ${STREAK}틱 미독★}"
bash "$MBOX" relay "$TARGET" os-goal-tick "$TMP" "$SUMMARY" >/dev/null 2>&1
echo "$(date '+%F %T') tick sent target=$TARGET rc=$GATE_RC streak=$STREAK"
