#!/bin/bash
# seat-scan.sh — 전 좌석 pane 을 한 번에 훑어 «멈춤»을 종류별로 가른다.
#
# ★왜 필요한가★: 좌석의 보고는 전부 mbox(=Bash)를 탄다. Bash 가 막히면 좌석은
# 회신할 수단이 없고, 마스터는 mbox 만 보므로 «일하는 중»과 구분이 안 된다.
# 이 스크릅트는 mbox 를 거치지 않고 pane 을 직접 읽어 그 구멍을 메운다.
#
# 출력 한 줄 = 한 좌석: 상태 | 마지막 의미 있는 줄
#   HUMAN  사람 입력 대기(인터뷰·승인 프롬프트) — 즉시 사람에게 알릴 것
#   BLOCK  도구/모델 오류로 막힘(분류기 5xx·503·429) — 재시도 또는 좌석 교체
#   STUCK  미제출 입력(❯ 에 텍스트 잔류) — Enter 미전송
#   BUSY   작업 중
#   IDLE   프롬프트 비어 있음
set +e
LINES="${SEAT_SCAN_LINES:-150}"

for s in $(tmux list-sessions -F '#S' 2>/dev/null); do
  # ★현재 상태와 «최근 이력»은 다른 캡처로 본다★
  #   now  = 보이는 화면만. «지금 무엇을 기다리는가»는 여기서만 판정한다.
  #   hist = 스크롤백. 최근 오류 흔적을 찾는 용도로만 쓴다.
  # 이 둘을 섞으면 스크롤백에 남은 «과거 제출된 입력»(❯ 로 시작하는 지난 프롬프트)을
  # 현재 미제출 입력으로 오판한다(실측: 30좌석이 STUCK 오탐).
  now="$(tmux capture-pane -t "$s" -p 2>/dev/null)"
  hist="$(tmux capture-pane -t "$s" -p -S "-$LINES" 2>/dev/null)"
  cap="$now"
  [ -n "$now" ] || { printf '%-26s %-6s %s\n' "$s" "DEAD" "(capture 실패)"; continue; }

  # ★바이트 매치★ — pane 에는 잘린 멀티바이트·박스문자가 섞여 UTF-8 grep 이 오판한다.
  state=BUSY
  if printf '%s\n' "$now" | LC_ALL=C grep -aqE 'Enter to select|Do you want to proceed|❯ [0-9]\.'; then
    state=HUMAN
  elif printf '%s\n' "$hist" | tail -40 | LC_ALL=C grep -aqE 'API Error: (429|5[0-9]{2})'; then
    # ★«에러 렌더»만 센다★ — 오류 «이름»(auth_unavailable·rate_limit_error·분류기)은
    # 좌석이 그 오류를 «보고하는 글» 에도 나온다. 이름으로 매치하면 남의 장애를
    # 분석 중인 멀쩡한 좌석이 BLOCK 으로 잡힌다(실측 7건 중 3건이 그 오탐이었다).
    # 실제로 멈춘 좌석에는 TUI 가 찍은 `API Error: <코드>` 줄이 남는다.
    state=BLOCK
  elif [ "$(printf '%s\n' "$now" | LC_ALL=C grep -anE '^❯' | tail -1 \
           | LC_ALL=C grep -acE '^[0-9]+:❯[[:space:]]+[^[:space:]]')" = 1 ]; then
    # ★«마지막» ❯ 줄만 본다★ — 화면에는 과거 제출된 프롬프트도 ❯ 로 남아 있어서
    # "❯ 뒤에 글자가 있는 줄이 하나라도 있으면 미제출"로 보면 전부 오탐이다
    # (실측: 19좌석 STUCK 중 확인한 2건 모두 과거 프롬프트였다).
    # 살아 있는 입력줄은 «항상 맨 아래 ❯» 이고, 비어 있으면 대기·글자가 있으면 미제출이다.
    state=STUCK
  elif printf '%s\n' "$cap" | LC_ALL=C grep -aqE '^\s*(⏵⏵|✻|✽).*(auto mode|bypass permissions)' \
     && ! printf '%s\n' "$cap" | LC_ALL=C grep -aqE '✻ .*(Spinning|Thinking|Working|esc to interrupt)'; then
    state=IDLE
  fi

  last="$(printf '%s\n' "$cap" | LC_ALL=C grep -avE '^\s*$|^\s*(⏵⏵|─|═)|^\s*\[OMC|^\s*[0-9]+h:|^\s*session:' | tail -1 | cut -c1-96)"
  printf '%-26s %-6s %s\n' "$s" "$state" "$last"
done | sort -k2,2
