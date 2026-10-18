#!/bin/bash
# ★런타임 사본은 git 추적 밖이다(작동 원리 — README 참조). 추적 백업: harness/comm/ · 드리프트 확인: harness/comm/check-drift.sh
# ft-v65-master#3 크론 틱 — 상태 점검 + HIL 상신 트리거
#
# 2026-08-17 신설 (사용자 지시): "pm, master 디바운스 크론 등록.
# HIL master에서 진행되도록 항목별 구현"
# => master 가 주기적으로 트랙 상태를 점검하고, 사용자 확인이 필요한 항목을
#    모아서 올린다. 워커가 사용자에게 직접 묻지 않는다.
#
# ft-pm-tick.sh 와 같은 4중 디바운스:
#   ① 단일 인스턴스 lock (pidfile + 생존 확인)
#   ② 최소 간격 (직전 전송 이후 MIN_GAP 미만이면 스킵)
#   ③ pane busy 스킵 (작업 중이거나 미제출 입력이 있으면 안 보낸다)
#   ④ 전송 후 제출 검증 (미제출이면 1회 Enter 보정)
#
# 세션명에 '#'가 있어 -t 직접 타겟 금지: pane_id 로 해석해 송신한다.

set -uo pipefail

TARGET_SESSION="${FT_MASTER_TICK_TARGET:-ft-v65-master#4}"
INTERVAL="${FT_MASTER_TICK_INTERVAL:-900}"
MIN_GAP="${FT_MASTER_TICK_MIN_GAP:-840}"
PIDFILE="${FT_MASTER_TICK_PIDFILE:-/tmp/ft-master-tick.pid}"
STAMP="${FT_MASTER_TICK_STAMP:-/tmp/ft-master-tick.last}"
# ★워치독 — 다른 tick 프로세스(pm-tick 등)의 pidfile 을 감시한다★ (2026-09-13 재발방지)
#   왜: pm-tick 이 SIGTERM 으로 조용히 죽어 30분 넘게 아무도 몰랐다(원인 미확정,
#   harness 레벨 가능성). mbox 큐 자체는 살아 있어도 자동 점검·능동보고가 멈춘다.
#   콤마구분 "label:pidfile" 쌍. 예: FT_MASTER_TICK_WATCH="pm-tick:/tmp/ft-pm-tick-pm3.pid"
WATCH="${FT_MASTER_TICK_WATCH:-}"
WATCH_STAMP="${FT_MASTER_TICK_WATCH_STAMP:-/tmp/ft-master-tick-watch.last}"
WATCH_GAP="${FT_MASTER_TICK_WATCH_GAP:-300}"  # 워치독 알림 자체도 5분 디바운스(도배 방지)

log() { echo "$(date '+%F %T') $*"; }

# ── ① 단일 인스턴스 lock ────────────────────────────────────────────
if [ -f "$PIDFILE" ]; then
  OLD=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    log "already running (pid=$OLD) — exit"
    exit 0
  fi
  log "stale pidfile (pid=${OLD:-none}) — taking over"
fi
echo "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"; log "master tick loop stopped"; exit 0' INT TERM

log "master tick started pid=$$ target=$TARGET_SESSION interval=${INTERVAL}s min_gap=${MIN_GAP}s"

# FT_MASTER_TICK_MSG 로 틱 본문을 좌석별로 바꿀 수 있다(orch/master 병행 등록용 · 2026-09-23)
MSG_DEFAULT="[cron-tick] master 점검 틱 — ★i-have-adhd 스타일로 출력(행동 우선·표·상태 재고지)★. ①★세션별 상세 테이블 필수★: 좌석명 / 에이전트 / ★지금 무슨 작업을 하는가★ / 상태(작업중·대기·응답없음·소진) — mbox 로 확인하고 pane 캡처로 판정 금지 ②★arch 가 지정한 구현 윈도우 상태★: 지금 닫는 인덱스 번호와 제목 / 사이클 단계(①기획~⑥정리 중 어디) / ★무엇을 구현 중인가★ / 남은 것 ③사용자 확인이 필요한 항목 — 있으면 모아서 한 번에(워커가 직접 묻지 않는다) ④press 순번 충돌과 GPU 창 잔여 ⑤미커밋 산출물이 있으면 커밋 ⑥★새 지시가 있었으면 USER-ORDERS-REGISTER 에 등록됐는지 확인★ ⑦★★oc 좌석 정지 감지★★ — impl-oc·checker-oc·tester-oc 등 opencode 좌석은 ★가끔 조용히 멈춘다★. 판별: ★작업 중인 파일의 mtime 이 10분 이상 정지★ + ★git diff --stat 변화 없음★ + ctx·비용 거의 안 움직임. ★★멈춘 것으로 보이면 오빠께 즉시 개입 요청★★(오빠가 취소 후 continue 를 걸면 재개된다). 실측 근거(파일 mtime·경과분)를 함께 올릴 것. 변화 없으면 \"변화 없음\" 1줄."
MSG="${FT_MASTER_TICK_MSG:-$MSG_DEFAULT}"

while :; do
  PANE=$(tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null \
         | awk -v s="$TARGET_SESSION" '$1==s{print $2; exit}')
  if [ -z "$PANE" ]; then
    log "target session gone — master tick exit"
    exit 0
  fi

  # ── ★워치독★ — pane busy/debounce 와 무관하게 즉시 확인·즉시 경보 ──────
  if [ -n "$WATCH" ]; then
    DEAD=""
    IFS=',' read -ra PAIRS <<< "$WATCH"
    for pair in "${PAIRS[@]}"; do
      label="${pair%%:*}"; pf="${pair#*:}"
      if [ -f "$pf" ]; then
        wpid=$(cat "$pf" 2>/dev/null)
        if [ -n "$wpid" ] && ! kill -0 "$wpid" 2>/dev/null; then
          DEAD="$DEAD $label(pid=$wpid stale-pidfile)"
        fi
      else
        DEAD="$DEAD $label(pidfile-missing:$pf)"
      fi
    done
    if [ -n "$DEAD" ]; then
      WLAST=$(cat "$WATCH_STAMP" 2>/dev/null || echo 0)
      WNOW=$(date +%s)
      if [ $(( WNOW - WLAST )) -ge "$WATCH_GAP" ]; then
        WMSG="[watchdog] tick 프로세스 사망 감지 —$DEAD — 재기동 필요(원인 조사는 부차, 재기동 먼저)."
        tmux send-keys -t "$PANE" -l "$WMSG"; sleep 0.3; tmux send-keys -t "$PANE" Enter
        date +%s > "$WATCH_STAMP"
        log "watchdog fired:$DEAD"
      fi
    fi
  fi

  SKIP=""

  # ── ② 최소 간격 (디바운스) ────────────────────────────────────────
  if [ -f "$STAMP" ]; then
    LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    GAP=$(( NOW - LAST ))
    [ "$GAP" -lt "$MIN_GAP" ] && SKIP="debounce (last tick ${GAP}s ago < ${MIN_GAP}s)"
  fi

  # ── ③ pane busy 스킵 ─────────────────────────────────────────────
  if [ -z "$SKIP" ]; then
    TAIL=$(tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -vE '^\s*$' | tail -3)
    if printf '%s' "$TAIL" | LC_ALL=C grep -qaE 'esc to interrupt|Working|Thinking'; then
      SKIP="pane busy (working)"
    elif printf '%s' "$TAIL" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then
      SKIP="pane has unsubmitted input"
    fi
  fi

  if [ -n "$SKIP" ]; then
    log "skip — $SKIP"
    sleep "$INTERVAL"
    continue
  fi

  # ── 전송 ─────────────────────────────────────────────────────────
  tmux send-keys -t "$PANE" -l "$MSG"
  sleep 0.3
  tmux send-keys -t "$PANE" Enter
  date +%s > "$STAMP"

  # ── ④ 제출 검증 ──────────────────────────────────────────────────
  sleep 1.5
  if tmux capture-pane -t "$PANE" -p 2>/dev/null | grep -vE '^\s*$' | tail -2 \
     | LC_ALL=C grep -qaE '^[›❯] +\[cron-tick\]'; then
    log "not submitted — sending Enter once more"
    tmux send-keys -t "$PANE" Enter
  fi

  log "master tick sent to $PANE"
  sleep "$INTERVAL"
done
