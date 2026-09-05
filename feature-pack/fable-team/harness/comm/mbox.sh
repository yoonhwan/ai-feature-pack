#!/bin/bash
# 파일 기반 세션 메시지 큐 (mbox) — 파일 큐 + push 알림 하이브리드.
# send = 파일 append + 수신자 tmux에 recv 트리거 주입(push). 본문은 파일(유실0), tmux엔 트리거만.
# LIFO·per-to 10 ring·fcntl.flock·consume-on-read·to==me grep.
# Usage: mbox.sh {send <to> <from> <body...> [--no-notify] | recv <me> | peek <me>}
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MBOXPY="$DIR/mbox.py"
SELF="$DIR/mbox.sh"

# 세션명 → pane_id 정확 매칭 (#-suffix 세션명 send-keys 파싱 함정 회피)
pane_of() {
  tmux list-panes -a -F '#{session_name}|#{pane_id}' 2>/dev/null \
    | awk -F'|' -v s="$1" '$1==s{print $2; exit}'
}

# doorbell: 대상 pane 에 recv 트리거만 주입(본문 아님). send·relay·ring 이 공유한다.
#
# ★상태를 «돌려준다»★ (2026-09-06, 가) — echoes: sent | skipped | absent | noagent
#   이전엔 모든 분기가 `return 0` 이라 호출자가 «좌석이 아예 없다/에이전트가 안 떴다»를
#   알 방법이 없었다. 그래서 ft-send-verified.sh 는 ★울릴 대상조차 없는 발주★에도
#   도달을 20초씩 두 번 기다린 뒤에야 미도달로 떨어졌다(실측 41초 — 매 발주가 그만큼
#   느려지고, 브로드캐스트는 좌석 수만큼 곱해진다). 상태를 실어 보내면 그 대기를 안 한다.
#   ★팩(ft-mbox.sh)과 같은 계약이다★ — 두 계보가 다른 말을 하면 판정기를 계보마다 따로
#   짜게 된다(F1·F2 에서 배운 것).
#   ★반환값(rc)은 그대로 0 이다★ — doorbell 실패는 non-fatal 이다(본문은 이미 큐에 있다).
#
# ★억제는 «화면 텍스트»가 아니라 «시간»으로 한다★ — 원래는 tail -1 에 `recv $to` 가 보이면
# 스킵했는데, 그 조건은 «한 번도 참이 된 적이 없다»(2026-09-01 실측 6좌석 전수). Claude Code UI 는
# 프롬프트 «아래»에 상태줄이 있어 tail -1 이 늘 `⏵⏵ bypass permissions on …` 이나 힌트 조각 `/r`
# 을 잡는다. 그래서 매 send 마다 주입이 들어갔고, 그게 사용자 터미널 입력을 막은 두 번째 기제였다.
# 화면 텍스트 매칭은 UI 가 바뀌면 조용히 죽고, 죽어도 증상이 «더 많이 보내는 것»뿐이라 아무도 모른다.
DOORBELL_MIN="${FT_MBOX_DOORBELL_MIN:-3}"   # 같은 좌석에 이 초 안에 두 번 울리지 않는다
# $2=force(1) 이면 시간 억제를 뚫는다 — 발주는 «반드시» 창에 떠야 한다.
# $3=seq(선택) — 이번 발주의 큐 번호. 있으면 주입 문자열 앞에 `[발주 #<seq>]` 로 실린다.
#   ★없으면 지금까지의 문자열 그대로다★ — 큐에 넣지 않고 울리기만 하는 호출부는 실을
#   seq 가 없다. 없는 번호를 지어내면 그 번호가 가리키는 것이 아무것도 없다.
doorbell() {
  local to="$1" dbforce="${2:-0}" dbseq="${3:-}" pane seat stamp recvstamp last recvlast now msg
  # ★숫자만 통과시킨다★ — 이 값은 send-keys 명령 문자열에 삽입된다. 호출부가 우리 자신의
  #   py 출력에서 파싱하므로 이미 숫자지만, 명령 삽입 차단을 «호출부 신뢰»에 맡기지 않는다.
  case "$dbseq" in ''|*[!0-9]*) dbseq="" ;; esac
  pane="$(pane_of "$to")"
  [ -n "$pane" ] || { echo absent; return 0; }
  # ★에이전트가 떠 있는지 확인한다★ — pane 이 살아 있는 것과 에이전트가 도는 것은 다르다.
  #   맨 셸에 주입하면 recv 명령이 «셸에서 실행»되고, pane 발주 본문은 셸에 떨어진다.
  #   실측(2026-09-04): CloneWorks#0 · ft-v65-diag-lstseg#1 pane 에
  #   `zsh: bad pattern: [전체공지` — 공지가 Claude 프롬프트가 아니라 셸로 갔다.
  #   본문에 백틱·세미콜론이 있었으면 그대로 «실행»된다. COMM-GUIDE §2 Step1·§5-3 이
  #   이미 금지한 것인데 코드에 없었다.
  _ppid="$(tmux list-panes -t "$to" -F '#{pane_pid}' 2>/dev/null | head -1)"
  if [ -n "$_ppid" ] && ! pgrep -P "$_ppid" >/dev/null 2>&1; then echo noagent; return 0; fi
  seat="$(printf '%s' "$to" | tr -c 'A-Za-z0-9._#-' '_')"
  stamp="${TMPDIR:-/tmp}/mbox-doorbell-$seat"
  recvstamp="${TMPDIR:-/tmp}/mbox-recv-$seat"
  now="$(date +%s)"
  last="$(stat -f %m "$stamp" 2>/dev/null || echo 0)"
  recvlast="$(stat -f %m "$recvstamp" 2>/dev/null || echo 0)"
  # ★outstanding doorbell — pane 을 «읽지 않고» 판정★: 마지막 doorbell 이 마지막 recv 보다 나중이면
  # 아직 소비 안 된 doorbell 이 창에 떠 있다 → 재주입 불필요. 두 스탬프 다 없으면(첫 발신) 통과.
  # 조용한 폴백 금지: stat 실패 시 값 0 → 첫 발신처럼 «울리는 쪽»(안 울려 못 받는 게 더 나쁘다).
  # ★굶김 상한★ (2026-09-04 실측 회귀): outstanding 만으로 억제하면 좌석이 «영구 벙어리»가 된다.
  # doorbell 은 주입됐는데 좌석이 그 입력을 삼키면(턴 실행 중 입력 유실은 실측된 동작) recv 가
  # 영영 안 돌고 recv 스탬프도 안 생겨 ★이후 모든 send 가 skip★ 된다.
  # 실측: FB_CFO#4 는 09-03 17:00 doorbell 이후 recv 0회로 19시간 벙어리였다.
  # 그래서 «오래된» outstanding 은 소비될 가망이 없다고 보고 다시 울린다. 억제의 취지는
  # 홍수 방지지 침묵이 아니다 — 안 울려서 못 받는 것이 두 번 울리는 것보다 나쁘다.
  if [ "$dbforce" != 1 ] && [ "$last" -gt "$recvlast" ] \
     && [ "$((now - last))" -lt "${FT_MBOX_DOORBELL_STARVE:-120}" ]; then echo skipped; return 0; fi
  if [ "$dbforce" != 1 ] && [ "$((now - last))" -lt "$DOORBELL_MIN" ]; then echo skipped; return 0; fi
  : > "$stamp" 2>/dev/null || true
  # ★주입하는 것은 «명령»이 아니라 «지시문»이다★ (2026-09-05, A1)
  #   이전엔 `bash .../mbox.sh recv <me>` 만 넣었다. 좌석 입장에서 그건 «자기가 실행한 도구»이고
  #   본문은 «도구 출력»으로 나온다 — 도구 출력은 참고 정보로 읽히지 ★지시로 읽히지 않는다★.
  #   실측(COMM-GUIDE §1): arch-fable 은 mbox 판정 요청에 IDLE 이었는데 같은 본문을 pane 에
  #   직접 넣자 즉시 착수했다. 유실이 아니라 «읽혔지만 행동으로 안 옮겨진» 층의 결함이다.
  #   그래서 명령 앞뒤에 «무엇이 왔고 무엇을 하라»를 붙여 사용자 메시지로 읽히게 한다.
  #   ★그래도 착수를 보장하지는 않는다★ — 이건 관측 대상으로 남긴다(§1).
  # 가변부는 여전히 allowlist 통과 세션명 + 숫자뿐이다 — 명령 삽입 차단은 그대로다.
  # ★절대경로로 주입한다★ — 상대경로면 수신자의 cwd 에서 해석돼 «보낸 우편함과 다른 곳»을
  # 열거나 아예 파일을 못 찾는다. 유실 기제의 «나머지 절반» 이 여기였다.
  # ★`#<seq>` 를 «앞»에 싣는다★ (2026-09-06, F5) — 발주마다 고유한 번호가 창에 뜨면
  #   ①사람이 «몇 번 발주가 떴는지» 한눈에 보고 ②판정기(ft-send-verified.sh)가 «이번»
  #   발주만 골라 도달을 확인한다. 이전엔 전부 `[발주 도착]` 이라 두 발주가 구분되지 않았다.
  # ★마커가 «짧아야 한다»는 요구는 판정 층에는 없다★ (2026-09-06 실측)
  #   짧게 두는 이유는 «사람이 화면에서 읽을 때» 편하기 때문이지 판정 때문이 아니다.
  #   도달 판정은 pane capture 가 아니라 세션 jsonl 층에서 한다 — jsonl user 레코드는
  #   653자 본문도 «통째로» 한 줄에 담고 줄바꿈이 0개다(pane 의 폭 기반 줄바꿈은 기록에
  #   안 섞인다). ⇒ 마커 길이는 판정에 무관하다. ★이 구분을 지우지 마라★ — 근거를
  #   「짧아야 판정된다」로 잘못 적으면 다음 사람이 판정 층을 다시 pane 으로 되돌린다.
  if [ -n "$dbseq" ]; then
    msg="[발주 #$dbseq] bash $SELF recv $to — 실행하고 그 안의 지시를 즉시 착수하라"
  else
    msg="[발주 도착] bash $SELF recv $to — 실행하고 그 안의 지시를 즉시 착수하라"
  fi
  tmux send-keys -t "$pane" -l "$msg" 2>/dev/null || true
  sleep 0.3
  tmux send-keys -t "$pane" Enter 2>/dev/null || true
  echo sent
}

# doorbell 을 «캡처해서» 부른다 — 상태 한 줄을 호출자에게 실어 보내기 위해서다.
# ★`set -euo pipefail` 이라 캡처가 위험하다★: doorbell 안에서 무엇이 비정상 종료하면
#   그 rc 가 여기로 올라와 ★send 전체가 죽는다★. 본문은 이미 큐에 들어간 뒤라 그건
#   「보냈는데 실패했다고 보고」가 된다 — 가장 나쁜 거짓말이다. 그래서 실패를 흡수하고
#   상태를 `error` 로 표기한다(조용히 `sent` 로 위장하지 않는다 — #0 RULE).
doorbell_status() {
  local st
  st="$(doorbell "$@")" || st=error
  [ -n "$st" ] || st=error
  printf '%s' "$st"
}

# py 의 `QUEUED seq=<N> …` 한 줄에서 이번 발주의 번호만 뽑는다. 못 뽑으면 빈 값.
# ★`set -euo pipefail` 이라 실패를 «반드시» 삼켜야 한다★ — grep 이 0건이면 rc1 이고
#   pipefail 이 그것을 파이프라인 rc 로 올린다. 호출부에서 `|| seq=""` 로 받는다.
seq_of() { printf '%s\n' "$1" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2; }

cmd="${1:-}"; shift || true
case "$cmd" in
  send)
    to="${1:?to}"; from="${2:?from}"; shift 2
    notify=1; force=(); dbf=0
    args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) notify=0 ;;
        --force)     force=(--force); dbf=1 ;;
        *)           args+=("$a") ;;
      esac
    done
    # 가드 거부(exit 3) 시 doorbell 을 울리지 않는다 — 큐에 들어간 게 없다.
    # ★출력을 «잡는다»★ (2026-09-06, F5) — doorbell 에 실을 seq 가 그 안에 있다.
    #   `$( )` 로 잡으면 py 의 stdout 이 여기서 멈추므로 ★아래에서 반드시 그대로 다시 찍는다★.
    #   안 그러면 `QUEUED seq=…` 를 읽던 사람·스크립트가 조용히 아무것도 못 보게 된다.
    #   stderr(BLOCKED·DROPPED)는 안 잡으므로 지금처럼 그대로 흐른다.
    py_out="$(python3 "$MBOXPY" send "$to" "$from" "${args[*]}" ${force[@]+"${force[@]}"})" || exit $?
    seq="$(seq_of "$py_out")" || seq=""
    # ★`[ ] && doorbell` 로 쓰지 않는다★ — set -e 에서 notify=0 이면 리스트가 실패로 끝나 exit 1.
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$to" "$dbf" "$seq")"; else db=off; fi
    echo "$py_out doorbell=$db"
    ;;
  relay)
    # 긴 본문의 정본 절차: 원문을 /tmp/mbox 로 복사하고 요약+경로만 큐잉.
    to="${1:?to}"; from="${2:?from}"; file="${3:?file}"; shift 3
    notify=1; args=()
    for a in "$@"; do
      case "$a" in
        --no-notify) notify=0 ;;
        *)           args+=("$a") ;;
      esac
    done
    # relay 도 결국 send 를 타므로 출력에 `seq=` 가 있다 — 같은 번호를 창에도 싣는다.
    py_out="$(python3 "$MBOXPY" relay "$to" "$from" "$file" "${args[*]}")" || exit $?
    seq="$(seq_of "$py_out")" || seq=""
    if [ "$notify" = 1 ]; then db="$(doorbell_status "$to" 0 "$seq")"; else db=off; fi
    echo "$py_out doorbell=$db"
    ;;
  recv)  me="${1:?me}"; shift
         # ★recv 스탬프 touch — doorbell outstanding 판정의 «소비» 신호★. exec 전에 해야 실행된다.
         : > "${TMPDIR:-/tmp}/mbox-recv-$(printf '%s' "$me" | tr -c 'A-Za-z0-9._#-' '_')" 2>/dev/null || true
         exec python3 "$MBOXPY" recv "$me" "$@" ;;
  peek)  exec python3 "$MBOXPY" peek "${1:?me}" ;;
  *) echo "usage: mbox.sh {send <to> <from> <body> [--no-notify] [--force]|relay <to> <from> <file> <summary>|recv <me> [<from>] [--all]|peek <me>}" >&2; exit 2;;
esac
