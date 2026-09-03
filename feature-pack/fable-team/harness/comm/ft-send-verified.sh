#!/usr/bin/env bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: tools/comm-canonical/ · 드리프트 확인: tools/comm-canonical/check-drift.sh
# tmux 발주 + 제출 확인을 한 번에 묶는다.
#
# 왜 필요한가: `tmux send-keys`는 항상 exit 0이다. 도구 성공이 전달 성공이 아니다.
# 2026-07-28 하루에 미제출 정지가 2회 났고 둘 다 뒤늦게 발견됐다 — 그 시간은
# 대기가 아니라 정지였다. 같은 규약이 COMM-GUIDE 0절에 이미 있었는데도 당했다.
# 즉 선언만으로는 안 지켜진다. 확인을 도구가 대신 해야 한다.
#
# ─ 2026-09-03 개정: 도달 판정을 화면에서 세션 jsonl 로 옮겼다 ────────────────
# 개정 전에는 `capture-pane` 의 `^❯ <텍스트>` 로 미제출을 봤다. 그 판정은
# ★미도달과 화면 재렌더를 둘 다 같은 값으로 찍는다★. 전용 좌석 실증:
#
#   케이스                      capture-pane        jsonl user 레코드
#   A 미도달 (Enter 안 침)       DIRTY               0
#   B 도달   (제출됨)            DIRTY               +1
#   C 재렌더 (입력 없음 30초)     DIRTY               +0
#
# 원인은 화면에 남는 것이 입력줄만이 아니라는 것이다 — ★제출된 메시지가 대화
# 이력으로 `❯ <본문>` 형태로 계속 렌더된다★. 그래서 정규식은 제출 «성공» 뒤에도
# 참이 되고, 그 위에 선 재전송이 같은 발주를 두 번 투입한다. 반대로 진짜
# 미도달도 같은 값이라 「잔여:0」이 도달로 읽힌다.
# 판정은 ft-reach-check.sh 로 분리했다(그쪽 헤더에 매핑 규칙·경계가 있다).
#
# ★화면 판정을 «지우지» 않고 역할만 낮췄다★: 아래 running() 은 여전히 화면을
# 보지만 이제 도달 여부를 결정하지 않는다. 좌석이 작업 중이면 입력이 큐에 쌓여
# 제출이 늦어지므로 «얼마나 기다릴지»를 정하는 데만 쓴다. 그래서 running 이
# 오탐해도 중복 전송이 생기지 않는다.
#
# usage: ft-send-verified.sh <session> <text>
#   exit 0 = OK / 1 = SEND_FAILED / 2 = NOT_SUBMITTED / 5 = UNVERIFIED(사람 확인)
set -uo pipefail

SESSION="${1:?session required}"
TEXT="${2:?text required}"
# zsh 로 실행되면 BASH_SOURCE 배열이 없다 → `parameter not set` 으로 죽는다.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REACH="$HERE/ft-reach-check.sh"

# 마커는 본문 첫 줄로 잡는다. jsonl 에는 개행이 이스케이프되어 저장되므로 여러
# 줄을 통째로 grep 하면 «있는데도 없다»가 나온다.
MARKER="$(printf '%s' "$TEXT" | head -1)"

send_once() {
    tmux send-keys -t "$SESSION" -l "$1" 2>/dev/null || return 1
    sleep 0.4
    tmux send-keys -t "$SESSION" Enter 2>/dev/null || return 1
    return 0
}

# 실행 표시는 pane 하단이 아니라 넓게 봐야 잡힌다.
#
# 표시어를 열거하지 않는다 — 이 CLI는 실행 중 문구를 매번 다른 단어로 바꾼다
# (Actioning / Ebbing / Cooked / Hullaballooing …). 열거하면 새 단어가 나올 때마다
# 오탐이 난다(2026-07-28 실증: Hullaballooing이 목록에 없어 정상 실행을 미제출로 잡았다).
# 대신 스피너 글리프 + 경과시간 패턴으로 본다. 이건 단어가 바뀌어도 형태가 같다.
# 실물 형태: `✢ Hullaballooing… (9m 16s · ↓ 7.3k tokens)` — 줄 맨 앞 글리프,
# 괄호 안 경과시간은 `59s` 또는 `9m 16s` 둘 다 나온다.
running() {
    tmux capture-pane -p -t "$SESSION" -S -40 2>/dev/null \
        | grep -qE '\([0-9]+(m [0-9]+)?s '
}

# ★보내기 전에 기준값을 잡는다★ — 같은 텍스트를 두 번 보내는 경우(재전송 포함)
# 이전 제출과 구분이 안 된다.
BASE="$(FT_REACH_COUNT_ONLY=1 bash "$REACH" "$SESSION" "$MARKER" 2>/dev/null)"
BASE_RC=$?
if [ "$BASE_RC" -ne 0 ]; then
    # 판정 불가를 화면 판정으로 «폴백하지 않는다». 발주는 하되 확인이 안 됐다는
    # 사실을 그대로 드러낸다(#0 RULE — 조용한 폴백 금지).
    send_once "$TEXT"
    echo "UNVERIFIED session=$SESSION — 발주는 했으나 jsonl 층을 못 읽었다. 사람이 확인해야 한다" >&2
    exit 5
fi

# 이미 작업 중인 세션은 입력을 큐에 쌓아둔다. 제출 자체는 되므로 도달 판정은
# 그대로 하되, 큐가 풀릴 때까지 기다리는 시간을 넉넉히 준다.
QUEUED=0
if running; then QUEUED=1; fi

if ! send_once "$TEXT"; then
    echo "SEND_FAILED session=$SESSION (세션이 없거나 tmux 오류)" >&2
    exit 1
fi

TIMEOUT=20
[ "$QUEUED" -eq 1 ] && TIMEOUT=60

if bash "$REACH" "$SESSION" "$MARKER" "$TIMEOUT" "$BASE"; then
    [ "$QUEUED" -eq 1 ] && echo "  (좌석이 작업 중이었다 — 대기열을 거쳐 제출됐다)"
    exit 0
fi
RC=$?

if [ "$RC" -eq 5 ]; then
    echo "UNVERIFIED session=$SESSION — 발주 후 jsonl 층을 못 읽었다. 사람이 확인해야 한다" >&2
    exit 5
fi

# Enter 재전송은 안 먹는다. 텍스트를 통째로 다시 보내야 제출된다.
echo "RESEND session=$SESSION (1차 미도달 — jsonl 에 제출 기록 없음)" >&2
send_once "$TEXT"
if bash "$REACH" "$SESSION" "$MARKER" "$TIMEOUT" "$BASE"; then
    exit 0
fi

echo "NOT_SUBMITTED session=$SESSION — 사람이 확인해야 한다" >&2
exit 2
