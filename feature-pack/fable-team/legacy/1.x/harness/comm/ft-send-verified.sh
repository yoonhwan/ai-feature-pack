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
# ─ 2026-09-06 개정 (F5): 본문을 창에 밀어 넣지 않는다 — A1 규약으로 전환 ─────
# 개정 전에는 «본문 전체»를 `send-keys -l` 로 pane 에 직접 넣고, 마커를 그 본문의
# ★첫 줄★로 잡았다. 두 가지가 동시에 틀렸다.
#
#   ① 본문이 창으로 간다 — COMM-GUIDE §1(A1) 이 금지한 그 경로다. send-keys 는
#      멀티바이트 손상·미제출 잔류·긴 본문 유실이 «여전히 사실»이고, 발주 본문일수록
#      길어서 그 위험이 제일 크다. 본문은 파일 큐로 가야 한다.
#   ② 마커가 «본문 첫 줄» 이다 — 두 발주가 같은 첫 줄을 공유하면(공지 접두사처럼
#      아주 흔하다) 두 발주가 판정에서 구분되지 않는다. 그러면 ★2차 발주가 1차의
#      도달로 통과★ 하거나 반대로 도달한 것이 미도달로 읽힌다.
#
# 지금은 mbox send 에 위임한다 — 본문은 파일 큐에 들어가고, 창에는 mbox 의 doorbell
# 한 줄(`[발주 #<seq>] bash …/mbox.sh recv <좌석> — …`)만 뜬다. 마커는 그 ★seq★ 다.
# seq 는 큐가 발급하는 단조증가 번호라 발주마다 고유하고, 따라서 «이번 발주»만 정확히
# 골라낸다. 기준값(baseline)은 그래서 항상 0 이다 — 새 번호가 과거 기록에 있을 수 없다.
#
# ★마커를 짧게 두는 이유는 «사람이 화면에서 읽을 때» 이지 판정 때문이 아니다★
#   (2026-09-06 실측) 도달 판정은 jsonl 층에서 한다. jsonl user 레코드는 653자 본문도
#   통째로 한 줄에 담고 줄바꿈이 0개다 — pane 의 폭 기반 줄바꿈(32컬럼에서 프리픽스가
#   쪼개져 미도달로 오판된 사고)은 ★기록에 안 섞인다★. 마커 길이는 판정에 무관하다.
#   이 구분을 지우지 마라 — 근거를 잘못 적으면 다음 사람이 판정 층을 pane 으로 되돌린다.
#
# ─ 2026-09-06 개정 (나): 재발주는 본문을 다시 넣지 않는다 ────────────────────
# 개정 전 재발주는 `mbox send` 재호출이었다. 그러면 ★같은 본문이 큐에 한 벌 더★ 들어가고
# 좌석은 recv 에서 같은 발주를 2건 본다(실측: pending=2, mailbox.jsonl 2행). F5 가 본문을
# 창에서 큐로 옮긴 뒤에도 ★중복의 «자리»만 옮겨갔지 총량은 그대로★ 였다.
#
# 미도달의 실체는 「본문이 큐에 없다」가 아니라 「창에 뜬 doorbell 을 좌석이 삼켰다」이다.
# 큐에는 이미 온전히 있다. 그러니 다시 넣을 것이 아니라 ★다시 울리기만★ 하면 된다.
# 그래서 재발주는 `mbox ring <좌석> <최초 seq>` 다 — 큐를 안 건드리고 doorbell 만 울린다.
#
# ★마커는 최초 seq 그대로다★ — 새 번호를 안 만드니 판정 마커도 안 바뀐다. F5 가 여기에
#   「재발주하면 새 번호가 나오니 마커를 갱신해야 한다」고 적었는데, 이 개정으로 그 문장은
#   ★거짓이 됐다★. COMM-GUIDE §1 의 같은 문장도 함께 고쳤다 — 한쪽만 고치면 다음 사람이
#   반대로 읽는다.
#
# ★인터페이스는 그대로다★ — ft-broadcast.sh 는 이 스크립트를 rc 로만 쓴다(0/1/2/5).
#
# usage: ft-send-verified.sh <session> <text>
#   exit 0 = OK / 1 = SEND_FAILED / 2 = NOT_SUBMITTED / 5 = UNVERIFIED(사람 확인)
set -uo pipefail

SESSION="${1:?session required}"
TEXT="${2:?text required}"
# zsh 로 실행되면 BASH_SOURCE 배열이 없다 → `parameter not set` 으로 죽는다.
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REACH="$HERE/ft-reach-check.sh"
# 본문 큐. 경로는 이 리포의 정본이고, 테스트·다른 설치가 갈아끼울 수 있게 env 를 먼저 본다.
MBOX="${FT_MBOX_SH:-$HERE/../comm/mbox.sh}"
# 발신자 이름 — mbox 의 세션명 allowlist(`[A-Za-z0-9._#-]+`)를 통과해야 한다.
FROM="${FT_SEND_FROM:-dispatch}"

# 마커는 발주 «후»에 정해진다 — 번호를 발급하는 것은 큐다.
MARKER=""
# 최초 발주의 큐 번호. 재발주(ring)가 ★이 번호를 그대로 다시 울린다★ — 새 번호를 만들지
# 않으므로 MARKER 도 그대로 유효하다.
SEQ=""
# 이번 발주의 doorbell 상태(sent|skipped|absent|noagent|error) — mbox 가 실어 보낸다.
DOORBELL=""

# 발주 1회 = mbox send(본문은 파일 큐) + doorbell 주입. 성공하면 MARKER 를 갱신한다.
#
# ★`--force` 를 붙인다★ — 두 가지를 동시에 뚫어야 한다:
#   (a) 발신 가드(RESEND·FANOUT·RATE) — 브로드캐스트는 «같은 본문을 여러 좌석에» 이고
#       재발주는 «같은 본문을 다시» 다. 둘 다 가드가 막으라고 만든 패턴이지만, 여기는
#       사람이 명시적으로 «검증된 발주» 를 요청한 경로다.
#   (b) doorbell 억제(시간·outstanding) — 발주는 ★반드시★ 창에 떠야 판정이 성립한다.
#       억제되면 아무것도 안 뜨고, 그건 미도달과 구분이 안 된다.
dispatch_once() {
    local out seq
    out="$(bash "$MBOX" send "$SESSION" "$FROM" "$TEXT" --force)" || return 1
    seq="$(printf '%s\n' "$out" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)"
    # ★번호를 못 읽으면 실패로 본다★ — 번호 없이 판정하면 무엇을 기다리는지 모른다.
    [ -n "$seq" ] || return 1
    SEQ="$seq"
    MARKER="[발주 #$seq]"
    # doorbell 상태를 같이 받는다 (2026-09-06, 가). 없으면 빈 값 — 옛 mbox 와도 돌아간다
    # (그 경우 아래 분기가 안 걸리고 지금까지의 «기다린다» 경로로 간다).
    DOORBELL="$(printf '%s\n' "$out" | grep -oE 'doorbell=[a-z]+' | tail -1 | cut -d= -f2)"
    printf '%s\n' "$out"
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

if [ ! -f "$MBOX" ]; then
    # ★조용히 send-keys 로 폴백하지 않는다★ — 그 폴백이 바로 이 개정이 없앤 경로다.
    echo "SEND_FAILED session=$SESSION — mbox 래퍼가 없다: $MBOX (FT_MBOX_SH 로 지정하라)" >&2
    exit 1
fi

# ★기준값을 «세지» 않는다 — 판정 층이 «읽히는지»만 미리 본다★
# 마커에 이번 발주만의 seq 가 들어가므로 과거 기록에 있을 수 없다 ⇒ 기준값은 항상 0 이다.
# 그래도 이 프로브는 남긴다: jsonl 디렉터리를 못 읽는 상태(비-ASCII 경로·첫 프롬프트 전·
# 세션 없음)를 ★발주 전에★ 알아야 「발주는 했으나 확인 못 했다(UNVERIFIED)」를 정직하게
# 낼 수 있다. 판정 불가를 화면 판정으로 폴백하지 않는다(#0 RULE — 조용한 폴백 금지).
if ! FT_REACH_COUNT_ONLY=1 bash "$REACH" "$SESSION" "__ft_send_verified_probe__" >/dev/null 2>&1; then
    dispatch_once >/dev/null || {
        echo "SEND_FAILED session=$SESSION (mbox send 실패 — 세션명 거부·가드 차단·큐 오류)" >&2
        exit 1
    }
    echo "UNVERIFIED session=$SESSION — 발주는 했으나 jsonl 층을 못 읽었다. 사람이 확인해야 한다" >&2
    exit 5
fi

# 이미 작업 중인 세션은 입력을 큐에 쌓아둔다. 제출 자체는 되므로 도달 판정은
# 그대로 하되, 큐가 풀릴 때까지 기다리는 시간을 넉넉히 준다.
QUEUED=0
if running; then QUEUED=1; fi

if ! dispatch_once; then
    echo "SEND_FAILED session=$SESSION (mbox send 실패 — 세션명 거부·가드 차단·큐 오류)" >&2
    exit 1
fi

# ★울릴 «대상»이 없으면 기다리지 않는다★ (2026-09-06, 가)
#   `absent` = 그 이름의 좌석이 tmux 에 없다 / `noagent` = pane 은 있으나 에이전트가
#   안 떠 있다(맨 셸). 두 경우 doorbell 은 ★아무것도 주입하지 않았다★ — 창에 뜬 것이
#   없으므로 좌석이 제출할 것도 없고, 20초씩 두 번(실측 41초) 기다려도 값은 안 바뀐다.
#   그 대기는 판정이 아니라 ★순환 전체를 느리게 하는 순수 손실★ 이다.
#
#   ★rc 5(UNVERIFIED)로 내는 근거★ — rc 집합(0/1/2/5)은 ft-broadcast.sh 가 집계에
#   쓰므로 새로 만들지 않고 기존 넷 중에 고른다.
#     · rc 1(SEND_FAILED) 이 아니다 — 발신은 ★성공★했다. 본문은 큐에 온전히 들어가 있어
#       좌석이 나중에 떠서 recv 하면 그대로 읽는다. 실패로 찍으면 사람이 다시 보내고
#       그러면 같은 발주가 큐에 두 벌 쌓인다.
#     · rc 2(NOT_SUBMITTED) 도 아니다 — 그 값의 뜻은 「창에 떴는데 좌석이 제출을 안 했다」,
#       즉 ★좌석 쪽 문제★다. 여기는 창에 뜬 적조차 없다. 두 상태를 한 값으로 묶으면
#       「좌석이 굼뜨다」와 「좌석이 없다」를 구분 못 해 엉뚱한 처방(재발주)을 부른다.
#     · rc 5(UNVERIFIED)가 남는다. 뜻이 「발주는 했으나 도달을 ★확인할 수 없다★ — 사람이
#       봐야 한다」이고, 좌석 부재·에이전트 부재는 정확히 그 축이다(사람이 좌석을 띄우거나
#       이름을 고쳐야 풀린다). ft-broadcast 도 이 값을 「판정불가」로 따로 세어 이름을 남긴다.
case "$DOORBELL" in
    absent|noagent)
        echo "UNVERIFIED session=$SESSION — doorbell=$DOORBELL (본문은 큐에 있다. 좌석이 없거나 에이전트가 안 떠 있어 창에 아무것도 안 떴다 — 사람이 확인해야 한다)" >&2
        exit 5
        ;;
esac

TIMEOUT=20
[ "$QUEUED" -eq 1 ] && TIMEOUT=60

# 기준값 0 을 ★명시★해 넘긴다 — 빈 값으로 넘기면 ft-reach-check 가 자기 나름대로
# 세는데, 그건 이 마커에 대해 늘 0 이라도 «왜 0 인지»가 코드에서 안 보인다.
if bash "$REACH" "$SESSION" "$MARKER" "$TIMEOUT" 0; then
    [ "$QUEUED" -eq 1 ] && echo "  (좌석이 작업 중이었다 — 대기열을 거쳐 제출됐다)"
    exit 0
fi
RC=$?

if [ "$RC" -eq 5 ]; then
    echo "UNVERIFIED session=$SESSION — 발주 후 jsonl 층을 못 읽었다. 사람이 확인해야 한다" >&2
    exit 5
fi

# doorbell 이 창에 안 떴거나 좌석이 그 입력을 삼켰다. ★다시 «울린다» — 다시 «넣지» 않는다★.
# 본문은 1차 발주에서 이미 큐에 온전히 들어갔다. send 를 다시 부르면 같은 본문이 한 벌 더
# 들어가 좌석이 recv 에서 2건을 본다(실측 pending=2). 그래서 큐를 안 건드리는 ring 을 쓴다.
# ★마커는 최초 seq 그대로다★ — ring 이 같은 번호를 다시 울리므로 갱신할 것이 없다.
echo "RESEND session=$SESSION (1차 미도달 — jsonl 에 제출 기록 없음. 본문 재큐잉 없이 doorbell 만 재주입)" >&2
# ★조용히 send 로 폴백하지 않는다★ — ring 이 없는 mbox(구버전·스텁)를 만나면 그 사실을
#   드러내고 죽는다. 폴백하면 이 개정이 없앤 중복이 무증상으로 되살아난다(#0 RULE).
if ! RING_OUT="$(bash "$MBOX" ring "$SESSION" "$SEQ" 2>&1)"; then
    echo "SEND_FAILED session=$SESSION (재발주 실패 — mbox ring 오류: $RING_OUT)" >&2
    exit 1
fi
printf '%s\n' "$RING_OUT"
DOORBELL="$(printf '%s\n' "$RING_OUT" | grep -oE 'doorbell=[a-z]+' | tail -1 | cut -d= -f2)"
case "$DOORBELL" in
    absent|noagent)
        echo "UNVERIFIED session=$SESSION — 재발주 doorbell=$DOORBELL (본문은 큐에 있다 — 사람이 확인해야 한다)" >&2
        exit 5
        ;;
esac
if bash "$REACH" "$SESSION" "$MARKER" "$TIMEOUT" 0; then
    exit 0
fi

echo "NOT_SUBMITTED session=$SESSION — 사람이 확인해야 한다" >&2
exit 2
