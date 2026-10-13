#!/bin/bash
# ft-tick.sh — Seatbelt 0.4 통합 틱 (ft-master-tick.sh · ft-pm-tick.sh · ft-goal-tick.sh 를 한 프로세스로)
#   한 루프마다 <리포루트>/.fable-team/seats.json 을 «다시 읽어» tick != null 이고 _replaced_by 없는 좌석마다
#   그 tick 종류의 간격·프롬프트를 적용한다. 승계 = seats.json 한 줄 교체(env 재기동 0회).
#   생존은 launchd KeepAlive (ft-tick.plist · ft-tick-install.sh) — 이 스크립트는 워치독을 갖지 않는다.
#
#   tick 종류: ft-master-tick(900s) · ft-pm-tick(600s · REPORT_TO = seats.json 의 현역 master)
#              + master 좌석엔 goal-tick(240s · ft-goal-tick.sh 를 그대로 호출 — rc=0 GOAL-OK 면 조용)
#   4중 디바운스(원본 그대로): ① 단일 인스턴스 pidfile ② 최소 간격(좌석별 stamp /tmp/ft-tick-<좌석>.last)
#              ③ pane busy·미제출 입력 스킵 ④ 전송 후 제출 검증(미제출이면 Enter 1회)
#   ft-tick.sh [--once] [--dry-run]   --once=한 바퀴만 · --dry-run=대상·메시지 앞 80자만 출력(전송·stamp 없음)
#   seats.json 을 못 읽으면 stderr 에 찍고 다음 루프(조용히 건너뛰지 않는다). 세션명에 '#' 가 있어 pane_id 로 송신.
#
#   ★Seatbelt 1.1 (2026-09-14 오빠: 「대상세션 pane읽어서 작업 안하고있으면 master에도 mbox 리드 메세지 직접 보내는것으로 하자」)★
#   idle_watch(): 매 루프(60s) 현역 좌석 전부(master 제외)의 «턴 경계»를 ft-seat-status.sh turn 으로 읽어 WORKING→IDLE
#   «전이 순간» 1회만 master 우편함에 [idle-detected] 를 --urgent 로 묶어 보낸다(DRAFT-harness-upgrade-v65.md §7). stall() 은 회복 경로로 그대로.
#   env: FT_TICK_IDLE_ENABLED(1) · FT_TICK_STATE_DIR(/tmp/ft-tick-state · --dry-run 은 /tmp/ft-tick-state-dry — 실전 상태를 안 건드린다)
#        FT_TICK_TURN_FIXTURE_DIR(<dir>/<seat>.jsonl 이 있으면 그 파일로 판정 — 완료조건 dry-run 3회 시험용)
#   --dry-run 도 상태파일은 쓴다(전송만 생략) — 전이 판정을 3회 연속 실행으로 검증하기 위해.
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
SEATS="${FT_TICK_SEATS:-${ROOT:-$WT}/.fable-team/seats.json}"
GOAL_TICK="${FT_TICK_GOAL_TICK:-$HERE/ft-goal-tick.sh}"
LOOP_SEC="${FT_TICK_LOOP_SEC:-60}"
PIDFILE="${FT_TICK_PIDFILE:-/tmp/ft-tick.pid}"
MASTER_INTERVAL="${FT_TICK_MASTER_INTERVAL:-300}"; MASTER_MIN_GAP="${FT_TICK_MASTER_MIN_GAP:-240}"  # 2026-09-14 오빠: 나노 완료 회신 뒤 master 반응까지 리드가 너무 길다 → 900/840→300/240
PM_INTERVAL="${FT_TICK_PM_INTERVAL:-600}";         PM_MIN_GAP="${FT_TICK_PM_MIN_GAP:-540}"
GOAL_INTERVAL="${FT_TICK_GOAL_INTERVAL:-240}"
# ★정지 감시 (2026-09-14 오빠: 「멈춰있으면 안 돼. 안 멈춰있게 장치 마련」)★
#   판정 = ft-seat-status.sh(jsonl mtime AND pane) — 정지면 그 좌석 창에 «깨우는 한 줄»을 넣고,
#   2회 깨워도 그대로면 master 에 --urgent. 사람 입력(옵션 모드) 대기면 깨우지 않고 바로 master(09-02 원장).
#   대상 = seats.json 현역 중 role ∈ master·da·pm·nano·harness-design (tester 는 제외 — press 슬롯은 master 게이트).
STALL_INTERVAL="${FT_TICK_STALL_INTERVAL:-300}"   # 감시 주기(초)
STALL_MIN="${FT_TICK_STALL_MIN:-15}"              # 이 분 이상 jsonl 무활동이면 정지
STALL_WAKE_GAP="${FT_TICK_STALL_WAKE_GAP:-900}"   # 같은 좌석 재깨움 최소 간격(초)
SEAT_STATUS="${FT_TICK_SEAT_STATUS:-$HERE/ft-seat-status.sh}"
MBOX="${FT_TICK_MBOX:-$HERE/../comm/mbox.sh}"
# ★워크트리 정리 sweep (하네스 0.5 행 2 r3 · DA r2 조건 2)★ — 닫힌 나노의 계획(.fable-team/state/wt-clean/*.sh)을 매 루프 실행. 가드·원장 표식은 계획이 맡는다.
#   [HIL] 줄이 나오면 현역 master 우편함으로 올린다(계획이 mbox 를 직접 쏘지 않는다 — 오빠 규칙 2026-09-25). FT_TICK_WT_SWEEP=0 으로 끔.
API_OUTAGE="${FT_TICK_API_OUTAGE_BIN:-$HERE/ft_api_outage.py}"
WT_SWEEP="${FT_TICK_WT_SWEEP_BIN:-$HERE/ft-wt-sweep.sh}"; WT_SWEEP_ENABLED="${FT_TICK_WT_SWEEP:-1}"
# ★라이브 bin 드리프트 경고 (카드 live-bin-drift-check · Issue 816 ③)★ — 설치 꼴(*/.fable-team/bin)에서 돌 때만, 라이브 도구 ↔ origin/main 키트를 FT_TICK_DRIFT_INTERVAL(600s)마다 대조.
#   어긋남 목록이 «바뀐 때만» master 우편함 1회(서명 $STATE_DIR/drift.sig). FT_TICK_DRIFT=0 으로 끔(경고만 끄는 스위치 — spawn·close 입구 BLOCK 은 끌 수 없다).
DRIFT_CHECK="${FT_TICK_DRIFT_BIN:-$HERE/ft-live-bin-drift-check.sh}"; DRIFT_ENABLED="${FT_TICK_DRIFT:-1}"; DRIFT_INTERVAL="${FT_TICK_DRIFT_INTERVAL:-600}"
ONCE=0; DRY=0
for a in "$@"; do case "$a" in --once) ONCE=1;; --dry-run) DRY=1;; *) echo "usage: $0 [--once] [--dry-run]" >&2; exit 2;; esac; done
IDLE_ENABLED="${FT_TICK_IDLE_ENABLED:-1}"
STATE_DIR="${FT_TICK_STATE_DIR:-/tmp/ft-tick-state$([ "$DRY" = 1 ] && echo -dry)}"
FIXTURE_DIR="${FT_TICK_TURN_FIXTURE_DIR:-}"

log() { echo "$(date '+%F %T') $*"; }
now() { date +%s; }
STAMP_PREFIX="${FT_TICK_STAMP_PREFIX:-/tmp/ft-tick-}"   # R27: 시험이 scratch 로 돌릴 수 있게(기본값=원본 동작)
stamp_of() { echo "${STAMP_PREFIX}$1${2:+.$2}.last"; }
pane_of() { tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null | awk -v s="$1" '$1==s{print $2; exit}'; }

# seats.json → "seat<TAB>tick<TAB>role" (현역만: _ 키 제외 · tick != null · _replaced_by 없음). 실패면 rc≠0.
read_seats() {
  python3 - "$SEATS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if v.get("tick") is None or v.get("_replaced_by"): continue
    print(f"{k}\t{v['tick']}\t{v.get('role','')}")
PY
}
# ★master 정본 = 좌석표 _master 하나(R27)★ role 첫 행·tick 행 순서로 고르지 않는다(폴백 0). 행이 있고 _replaced_by 없고 role=master 일 때만 출력.
master_seat() {   # $1=좌석표 파일(기본 $SEATS) — sweep_wt 가 팀 좌석표(seats-<팀>.json)의 master 를 찾을 때도 쓴다
  python3 - "${1:-$SEATS}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = d.get("_master"); v = d.get(m) if isinstance(m, str) else None
if isinstance(v, dict) and not v.get("_replaced_by") and v.get("role") == "master": print(m)
PY
}
# 뉴스 행 검사(R27): 현역 ft-master-tick 행이 있으면 그 중 _master 와 같은 행이 «정확히 1개» — 아니면 ERROR+알림(상태 서명이 바뀔 때 1회)·master news 0 → rc 1. $1=rows $2=master
master_news_ok() {
  local news sig sf
  sf="$(stamp_of _all mtsig)"
  news="$(awk -F'\t' '$2=="ft-master-tick"{print $1}' <<< "$1" | paste -sd, -)"
  if [ -z "$news" ] || { [ -n "$2" ] && [[ ",$news," == *",$2,"* ]]; }; then rm -f "$sf"; return 0; fi
  sig="_master=${2:-none}|$news"; [ "$(cat "$sf" 2>/dev/null)" = "$sig" ] && return 1
  echo "$sig" > "$sf"; log "ERROR master news row invalid (_master=${2:-none} · news rows=$news) — master news 0"
  printf '%s master news row invalid (_master=%s · news rows=%s) in %s\n' "$(date '+%F %T')" "${2:-none}" "$news" "$SEATS" >> "${STAMP_PREFIX}DEAD-SEATS.alert"; return 1
}

# ★master 틱 = «뉴스 발행» (2026-09-14 오빠 지시 원문: 「master는 메세지가 이런게 아니고 진행중과 남은작업을 정리해서 현재 어떤 작업을
#   하고 있다는 뉴스가 발행되야하낟. 테스트는 어떻게 계획중이고 완성까지 전망을 발행. 멈춘거면 어디 세션을 확인하라고 알리던가
#   master가 인터뷰 걸어서 나에게 알리고 선택하면 전파 돌파」). 점검 항목 나열이 아니라 «지금·남은·테스트·전망» 네 칸의 짧은 뉴스다.
#   정지는 ft-tick 의 stall 감시가 [stall] 로 master 에 올린다 — master 는 그걸 받으면 «어느 세션을 보라» 한 줄 또는 AskUserQuestion.
# 오빠 정정 3회차(2026-09-14): 「이거봐 인덱스 덩어리자나. 그리고 어디 세션이 무엇을하는지 세션 상태는 마지막에 따로 공유」
#   ⇒ 인덱스 «파일명»(M5-owner-live-operation-id 같은 슬러그)을 뉴스에 쓰지 않는다 — 그건 좌표지 뉴스가 아니다.
#      뉴스는 «사람 말»로: 무엇이 안 되던 것을 무엇으로 고치는 중인가. 좌석·세션은 뉴스 밖 «세션 상태» 절에 따로.
# ★2026-09-14 오빠: 「중간 뉴스랑 크론 메세지 길이 확인 너무 중복 매번 발행량이 많은듯」 — 1923B 규칙서를 매 틱 pane 에 꽂던 것을 «한 줄 + 정본 포인터»로.
#   규칙 본문은 SEATBELT-README §6-1(master 항)에 있다 — 프롬프트는 형식을 «가리키고», 뉴스 4칸 + 세션 상태 절 자체는 짧게(변화 없으면 1줄).
MASTER_MSG="[cron-tick · 뉴스] 형식은 SEATBELT-README §6-1 master 항 그대로(★⓪ 완성 상태 트리 = ft-news-tick ⑥ 출력 그대로 맨 위★ · 뉴스 4칸 ≤6불릿 · 빈 줄 · 세션 상태 트리 · 같은 턴에 1건 착수). 변화 없으면 \"변화 없음 — <증상 한 줄>\" 만. 총 ≤900자."
pm_msg() { # $1 = report_to — 규칙은 README §6-1 · 정본 3종은 pm 인박스 README 에. 여기선 4항 이름만.
  echo "[cron-tick] pm 틱 — ①골 대조 1줄(M?/G?) ②원장 미등재 ③활성 나노 @zc_v65_active 전수(0 이면 즉시 set-option) ④사람 확인 필요분 → $1. 변화 없으면 \"변화 없음\" 1줄. 정본·형식: SEATBELT-README §6-1."
}

# 한 좌석·한 종류 발사: ② 간격 → ③ busy → 전송 → ④ 제출 검증. $1 seat $2 kind $3 interval $4 min_gap $5 msg
fire() {
  local seat="$1" kind="$2" interval="$3" min_gap="$4" msg="$5" stamp gap pane tail
  stamp="$(stamp_of "$seat" "$kind")"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY seat=$seat kind=$kind interval=${interval}s gap=${gap}s msg=${msg:0:80}"; return 0; fi
  [ "$gap" -ge "$interval" ] || return 0                                   # 아직 차례 아님(조용)
  [ "$gap" -ge "$min_gap" ] || { log "skip $seat/$kind — debounce (${gap}s < ${min_gap}s)"; return 0; }
  pane="$(pane_of "$seat")"; [ -n "$pane" ] || { log "skip $seat/$kind — session absent"; return 0; }
  tail="$(tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -3)"
  if printf '%s' "$tail" | LC_ALL=C grep -qaE 'esc to interrupt|Working|Thinking'; then log "skip $seat/$kind — pane busy (working)"; return 0; fi
  if printf '%s' "$tail" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then log "skip $seat/$kind — pane has unsubmitted input"; return 0; fi
  tmux send-keys -t "$pane" -l "$msg"; sleep 0.3; tmux send-keys -t "$pane" Enter
  now > "$stamp"
  sleep 1.5
  if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -2 | LC_ALL=C grep -qaE '^[›❯] +\[cron-tick\]'; then
    log "$seat/$kind not submitted — sending Enter once more"; tmux send-keys -t "$pane" Enter
  fi
  log "$kind sent to $seat ($pane)"
}

# goal-tick: 기존 ft-goal-tick.sh 를 좌석 대상으로 «그대로» 실행(내부에서 ft-goal-check → rc=0 이면 조용, rc≠0 relay).
goal() {
  local seat="$1" stamp gap
  stamp="$(stamp_of "$seat" goal)"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  [ -x "$GOAL_TICK" ] || [ -f "$GOAL_TICK" ] || { echo "$(date '+%F %T') goal-tick script missing: $GOAL_TICK" >&2; return 0; }
  if [ "$DRY" = 1 ]; then
    echo "DRY seat=$seat kind=goal-tick interval=${GOAL_INTERVAL}s gap=${gap}s msg=(ft-goal-tick.sh 결과 → rc≠0 일 때만 relay)"; return 0
  fi
  [ "$gap" -ge "$GOAL_INTERVAL" ] || return 0
  FT_GOAL_TICK_TARGET="$seat" bash "$GOAL_TICK" | sed "s/^/goal-tick[$seat] /"
  now > "$stamp"
}

# seats.json 현역 전부(tick 유무 무관) → "seat<TAB>role". stop-ready·_replaced_by·tester 제외.
active_seats() {
  python3 - "$SEATS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = d.get("_master")
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if isinstance(m, str) and v.get("role") == "master" and k != m: continue  # R43 · R27 정본: 깨울 master 는 _master 하나 — 승계 뒤 남은 옛 role=master 행은 건너뛴다
    # impl/checker 는 나노 계열이라 정지 감시 대상. tester 는 press 슬롯을 master 가 게이트하므로 제외.
    # role=stop-ready 는 «정지가 정상»인 좌석 — 깨우지 않는다(실측 2026-09-14: 정지 레디 좌석을 17분마다 깨웠다).
    #   정지 레디로 갈 때 seats.json 행의 role 을 stop-ready 로 바꾼다(arch-fable#40 선례). 되살리면 role 을 원래로.
    if v.get("_replaced_by") or v.get("role") not in ("master", "da", "pm", "nano", "impl", "checker", "harness-design"): continue
    print(f"{k}\t{v.get('role','')}")
PY
}

stall() {
  local stamp gap rows seat role line pane age thr p wstamp wgap cnt msg master
  stamp="$(stamp_of _all stall)"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY kind=stall interval=${STALL_INTERVAL}s min=${STALL_MIN}m seats=$(active_seats 2>/dev/null | cut -f1 | tr '\n' ' ')"; return 0; fi
  [ "$gap" -ge "$STALL_INTERVAL" ] || return 0
  now > "$stamp"
  [ -f "$SEAT_STATUS" ] || { echo "$(date '+%F %T') stall: seat-status missing $SEAT_STATUS" >&2; return 0; }
  rows="$(active_seats 2>/dev/null)" || { echo "$(date '+%F %T') stall: seats.json unreadable" >&2; return 0; }
  master="$(master_seat)"
  thr=$(( STALL_MIN * 60 ))
  while IFS=$'\t' read -r seat role; do
    [ -n "$seat" ] || continue
    p="$(pane_of "$seat")"; [ -n "$p" ] || continue          # 세션 없음은 정지가 아니라 부재 — master 틱이 본다
    line="$(bash "$SEAT_STATUS" one "$seat" 2>/dev/null)"
    read -r _ pane age _ _ <<< "$line"
    case "$age" in ''|*[!0-9]*) continue;; esac              # 비-claude 는 jsonl 없음 — 여기선 판정 안 함
    # 정지 = jsonl ≥ thr AND (pane IDLE  OR  jsonl ≥ 2×thr) — 후자는 «완료 요약행 BUSY 오판» 대비
    if [ "$age" -ge "$thr" ] && { [ "$pane" = IDLE ] || [ "$age" -ge $(( thr * 2 )) ]; }; then
      if tmux capture-pane -t "$p" -p 2>/dev/null | LC_ALL=C grep -qa 'Enter to select'; then
        [ -n "$master" ] && [ "$seat" != "$master" ] && bash "$MBOX" send "$master" ft-tick "[stall] $seat 가 사람 입력(옵션 모드) 대기 ${age}s — 깨우지 않았다. 오빠 개입 필요" --urgent >/dev/null 2>&1
        log "stall $seat — option mode (age=${age}s), escalated to ${master:-none}"; continue
      fi
      wstamp="$(stamp_of "$seat" stall)"; wgap=$(( $(now) - $(cat "$wstamp" 2>/dev/null || echo 0) ))
      [ "$wgap" -ge "$STALL_WAKE_GAP" ] || continue
      cnt=$(( $(cat "$wstamp.count" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$wstamp.count"
      msg="[stall-wake $((age/60))분 정지 · ${cnt}회] 멈춰 있지 마라. ① bash $MBOX recv $seat ② $SEATS 의 내 행 index/inbox 를 열어 다음 단위 착수 ③ 정말 할 일이 없으면 ${master:-master} 에 mbox 로 «정지 레디» 1줄 보고 후 대기. 판단이 갈리면 묻지 말고 값과 함께 ${master:-master} 에."
      tmux send-keys -t "$p" -l "$msg"; sleep 0.3; tmux send-keys -t "$p" Enter
      now > "$wstamp"; log "stall-wake sent to $seat (age=${age}s pane=$pane cnt=$cnt)"
      if [ "$cnt" -ge 2 ] && [ -n "$master" ] && [ "$seat" != "$master" ]; then
        bash "$MBOX" send "$master" ft-tick "[stall] $seat ${age}s 정지 · 깨움 ${cnt}회 무응답(pane=$pane, role=$role) — 좌석 교체(ft-role-spawn/ft-nano-spawn) 또는 오빠 개입 판단" --urgent >/dev/null 2>&1
      fi
    else
      rm -f "$(stamp_of "$seat" stall).count" 2>/dev/null   # 회복 → 카운터 리셋
    fi
  done <<< "$rows"
}

# ── Seatbelt 1.1 idle 전이 알림 ──────────────────────────────────────────────────────────────
# seats.json 현역 «전부» → "seat<TAB>role" (_ 키·_replaced_by·role=stop-ready 제외 · role 무관 — 오빠 「어떤 세션이던 제네럴하게」)
all_seats() {
  python3 - "$SEATS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = d.get("_master")
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if isinstance(m, str) and v.get("role") == "master" and k != m: continue  # R43 · R27 정본(active_seats 와 같은 기준)
    if v.get("_replaced_by") or v.get("role") == "stop-ready": continue
    print(f"{k}\t{v.get('role','')}")
PY
}
iso_epoch() { TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%S' "${1%%.*}" +%s 2>/dev/null; }
turn_line() {  # $1 seat → "STATE TURN_END DURATION_MS REPORTED SOURCE" (픽스처가 있으면 그 파일로)
  if [ -n "$FIXTURE_DIR" ] && [ -f "$FIXTURE_DIR/$1.jsonl" ]; then bash "$SEAT_STATUS" turn --file "$FIXTURE_DIR/$1.jsonl" 2>/dev/null
  else bash "$SEAT_STATUS" turn "$1" 2>/dev/null; fi
}

# 상태파일 STATE_DIR/<seat>.turn = "state turn_end notified" 3값. 알림 = «전이 순간» 1회 (같은 turn_end 로 두 번 안 보낸다).
#   jsonl 좌석: 이전 상태가 IDLE 이 아니거나 turn_end 가 바뀌었으면(사이에 한 턴이 끝남) 전이. 첫 관측은 전이가 아니다 —
#              turn_end 가 2×LOOP_SEC 안쪽이면 알리고 아니면 심기만(오래된 idle 은 stall() 몫 · 재기동 폭풍 0).
#   pane 좌석(jsonl 없는 codex·cmd·opencode): WORKING→IDLE1(1루프 조용)→IDLE 로 2루프 연속 디바운스. 첫 관측 IDLE 은 그냥 심는다.
#   옵션모드(Enter to select) = waiting=human — 전이·창 무관하게 대상, 키는 <turn_end>/human 으로 1회.
#   pane 없는 좌석은 상태파일 삭제·무알림(부재는 master 틱·close 몫). 한 루프의 대상 전부 → master 에 한 메시지 --urgent.
idle_watch() {
  local rows master seat role p st end dur rep src pst pend pnot notify key human ep lines targets n body rc t_seat t_st t_end t_key hhmm secs
  [ "$IDLE_ENABLED" = 1 ] || { log "idle_watch disabled (FT_TICK_IDLE_ENABLED=$IDLE_ENABLED)"; return 0; }
  [ -f "$SEAT_STATUS" ] || { echo "$(date '+%F %T') idle_watch: seat-status missing $SEAT_STATUS" >&2; return 0; }
  rows="$(all_seats 2>/dev/null)" || { echo "$(date '+%F %T') idle_watch: seats.json unreadable ($SEATS)" >&2; return 0; }
  master="$(master_seat)"
  [ -n "$master" ] || { echo "$(date '+%F %T') idle_watch: no active master in $SEATS" >&2; return 0; }
  mkdir -p "$STATE_DIR"
  lines=""; targets=""; n=0
  while IFS=$'\t' read -r seat role; do
    [ -n "$seat" ] && [ "$seat" != "$master" ] || continue
    p="$(pane_of "$seat")"
    [ -n "$p" ] || { rm -f "$STATE_DIR/$seat.turn"; continue; }
    read -r st end dur rep src <<< "$(turn_line "$seat")"
    [ -n "$st" ] || continue
    read -r pst pend pnot <<< "$(cat "$STATE_DIR/$seat.turn" 2>/dev/null)"
    human=0; tmux capture-pane -t "$p" -p 2>/dev/null | LC_ALL=C grep -qa 'Enter to select' && human=1
    notify=no; key="$end"
    if [ "$src" = pane ]; then
      key="pane@$(now)"
      case "${pst:-}:$st" in
        WORKING:IDLE) st=IDLE1;;
        IDLE1:IDLE)   notify=yes;;
      esac
    elif [ "$st" = IDLE ]; then
      if [ -z "${pst:-}" ]; then
        ep="$(iso_epoch "$end")"; [ -n "$ep" ] && [ $(( $(now) - ep )) -le $(( 2 * LOOP_SEC )) ] && notify=yes
      elif [ "$pst" != IDLE ] || [ "$end" != "$pend" ]; then notify=yes
      fi
      [ "$key" = "${pnot:-}" ] && notify=no
    fi
    if [ "$human" = 1 ]; then key="$end/human"; [ "$key" != "${pnot:-}" ] && notify=yes; fi
    [ "$DRY" = 1 ] && echo "DRY kind=idle seat=$seat state=$st prev=${pst:--} turn_end=$end notify=$notify"
    if [ "$notify" != yes ]; then echo "$st $end ${pnot:--}" > "$STATE_DIR/$seat.turn"; continue; fi
    # 알림 대상은 여기서 상태를 쓰지 않는다 — send 결과를 본 뒤 쓴다(실패면 이전 상태 유지 → 다음 루프 재감지)
    secs="-"; case "$dur" in ''|-|*[!0-9]*) ;; *) secs=$(( dur / 1000 ));; esac
    hhmm="-"; ep="$(iso_epoch "$end")"; [ -n "$ep" ] && hhmm="$(date -r "$ep" +%T)"
    lines+="[idle-detected] $seat role=$role turn=${secs}s end=$hhmm reported=$rep source=$src$([ "$human" = 1 ] && echo ' waiting=human')"$'\n'
    targets+="$seat"$'\t'"$st"$'\t'"$end"$'\t'"$key"$'\t'"${pst:-}"$'\t'"${pend:-}"$'\t'"${pnot:-}"$'\n'; n=$(( n + 1 ))
  done <<< "$rows"
  [ "$n" -gt 0 ] || return 0
  body="${lines}mbox recv 뒤 다음 발주 판단"
  if [ "$DRY" = 1 ]; then echo "DRY kind=idle send to=$master n=$n"; rc=0
  else bash "$MBOX" send "$master" ft-tick "$body" --urgent >/dev/null 2>&1; rc=$?; fi
  while IFS=$'\t' read -r t_seat t_st t_end t_key t_pst t_pend t_pnot; do
    [ -n "$t_seat" ] || continue
    if [ "$rc" = 0 ]; then echo "$t_st $t_end $t_key" > "$STATE_DIR/$t_seat.turn"
    else
      echo "$(date '+%F %T') idle_watch: mbox failed rc=$rc seat=$t_seat" >&2
      if [ -n "$t_pst" ]; then echo "$t_pst $t_pend ${t_pnot:--}" > "$STATE_DIR/$t_seat.turn"; else rm -f "$STATE_DIR/$t_seat.turn"; fi
    fi
  done <<< "$targets"
  [ "$rc" = 0 ] && [ "$DRY" != 1 ] && { now > "$(stamp_of _all idle-sent)"; log "idle-detected ×$n sent to $master"; }
  return 0
}

# ── R146 API 장애 시작·끝 알림 + 끊긴 좌석 복구 뒤 1회 재개 (판정 1633) ─────────────────────────────
# ft_api_outage.py 가 현역 좌석 jsonl 의 «오류 레코드로 끝난 턴»을 읽는다 — 장애 중엔 Claude 좌석이 못 움직이므로 감시는 이 bash 틱에서.
# 알림 대상 = FT_API_OUTAGE_NOTIFY > 좌석표 _hil_route > _master. 상태 = <루트>/.fable-team/state/api-outage/<좌석표 이름>.json.
# 도구 실패는 ERROR 1줄만 남기고 틱은 계속(조용한 생략 0). FT_TICK_API_OUTAGE=0 으로 끔.
outage_watch() {
  local rows seat p f notify lines state out rc
  [ "${FT_TICK_API_OUTAGE:-1}" = 1 ] || return 0
  notify="${FT_API_OUTAGE_NOTIFY:-$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("_hil_route") or d.get("_master") or "")' "$SEATS" 2>/dev/null)}"
  state="${FT_TICK_API_OUTAGE_STATE:-${ROOT:-$WT}/.fable-team/state/api-outage/$(basename "$SEATS")}"
  if [ "$DRY" = 1 ]; then echo "DRY kind=api-outage bin=$API_OUTAGE notify=${notify:--} state=$state"; return 0; fi
  [ -n "$notify" ] || { echo "$(date '+%F %T') outage_watch: ERROR api_outage: no notify target (_hil_route/_master) in $SEATS" >&2; return 0; }
  rows="$(all_seats 2>/dev/null)" || { echo "$(date '+%F %T') outage_watch: ERROR api_outage: seats.json unreadable ($SEATS)" >&2; return 0; }
  lines=""
  while IFS=$'\t' read -r seat _; do
    [ -n "$seat" ] && [ -n "$(pane_of "$seat")" ] || continue
    f="$(bash "$SEAT_STATUS" jsonl "$seat" 2>/dev/null)" && [ -n "$f" ] && lines+="$seat"$'\t'"$f"$'\n'
  done <<< "$rows"
  out="$(printf '%s' "$lines" | python3 "$API_OUTAGE" --state "$state" --mbox "$MBOX" --notify "$notify" 2>&1)"; rc=$?
  [ "$rc" = 0 ] || echo "$(date '+%F %T') outage_watch: ERROR api_outage rc=$rc: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2
  return 0
}

sweep_wt() {
  local out hil master rows tagged team lines hdr tf
  [ "$WT_SWEEP_ENABLED" = 1 ] || return 0
  [ -x "$WT_SWEEP" ] || { echo "$(date '+%F %T') sweep_wt: missing $WT_SWEEP" >&2; return 0; }
  if [ "$DRY" = 1 ]; then echo "DRY kind=wt-sweep bin=$WT_SWEEP plans=$(bash "$WT_SWEEP" --dry-run 2>/dev/null | grep -c '^DRY ')"; return 0; fi
  out="$(bash "$WT_SWEEP" 2>&1)"; rc=$?
  log "wt-sweep: rc=$rc $(printf '%s\n' "$out" | grep -v '^$' | tail -1)"
  hil="$(printf '%s\n' "$out" | grep '^\[HIL\]')" || return 0
  # ★[HIL] 은 계획 좌석(seat=byz-<팀>-…)의 «팀 master» 로★ — 접두 <팀> ↔ <좌석표 디렉터리>/seats-<팀>.json. v65(byz-v65-·ft-v65-)·좌석 표기 없음 = 자기 master.
  #   팀 좌석표가 없거나 현역 master 가 없으면 자기 master 로 보내되 «[라우팅 실패 <팀>]» 머리 + stderr 1줄(조용한 후퇴 0).
  tagged="$(printf '%s\n' "$hil" | awk '{ s=""; for (i=1;i<=NF;i++) if ($i ~ /^seat=/) { s=substr($i,6); break }
    t="-"; if (s ~ /^byz-v65-/ || s ~ /^ft-v65-/) t="v65"; else if (s ~ /^byz-[A-Za-z0-9]+-/) { split(s,a,"-"); t=a[2] } else if (s != "") t="?"
    print t "\t" $0 }')"
  # shellcheck disable=SC2013  # 팀 키는 공백 없는 토큰(seats 파일 이름 조각) — 단어 단위 순회가 의도
  for team in $(cut -f1 <<< "$tagged" | sort -u); do
    lines="$(awk -F'\t' -v t="$team" '$1==t { print substr($0, index($0,"\t")+1) }' <<< "$tagged")"
    hdr=""; master=""
    case "$team" in
      -|v65) master="$(master_seat)";;
      *) tf="$(dirname "$SEATS")/seats-$team.json"; [ -f "$tf" ] && master="$(master_seat "$tf" 2>/dev/null)"
         if [ -z "$master" ]; then
           hdr="[라우팅 실패 $team] "; master="$(master_seat)"   # 표식은 «[HIL] 뒤» — planner 머리 검사(reject)는 본문이 [HIL] 로 시작해야 통과(DA⑥)
           echo "$(date '+%F %T') sweep_wt: team '$team' master not found ($tf) — routed to own master" >&2
         fi;;
    esac
    [ -n "$master" ] || { echo "$(date '+%F %T') sweep_wt: [HIL] pending (team $team) but no active master" >&2; continue; }
    bash "$MBOX" send "$master" ft-tick "[HIL] ${hdr}워크트리 정리 사람 판정 $(printf '%s\n' "$lines" | grep -c .)건 — $(printf '%s\n' "$lines" | head -3 | cut -c1-160 | tr '\n' ' ')" --urgent >/dev/null 2>&1 \
      || echo "$(date '+%F %T') sweep_wt: mbox failed (team $team)" >&2
  done
}

drift_watch() {
  local out err errf cause rc shrc hdr items sig sigf stamp rows master
  [ "$DRIFT_ENABLED" = 1 ] || return 0
  case "$HERE" in */.fable-team/bin|*/.fable-team/*/bin) ;; *) return 0;; esac
  stamp="$(stamp_of _all drift)"
  if [ "$DRY" != 1 ] && [ $(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) )) -lt "$DRIFT_INTERVAL" ]; then return 0; fi
  [ -f "$DRIFT_CHECK" ] || { echo "$(date '+%F %T') drift_watch: missing $DRIFT_CHECK" >&2; return 0; }
  # stdout 만 머리글·항목·서명 — stderr(locale 경고 등)가 머리글이 되면 로그·알림·서명이 오염된다. stderr 는 rc≥2 원인 줄로만 쓴다.
  errf="$(mktemp)" && [ -n "$errf" ] || { echo "$(date '+%F %T') drift_watch: ERROR mktemp failed — check not run" >&2; return 0; }
  out="$(bash "$DRIFT_CHECK" --bin "$HERE" ${ROOT:+--repo "$ROOT"} 2>"$errf")"; rc=$?
  err="$(cat "$errf" 2>/dev/null)"; rm -f "$errf"
  if [ "$DRY" = 1 ]; then echo "DRY kind=drift bin=$HERE rc=$rc"; return 0; fi
  now > "$stamp"; sigf="$STATE_DIR/drift.sig"; mkdir -p "$STATE_DIR"
  case "$rc" in
    0) [ -f "$sigf" ] && { rm -f "$sigf"; log "drift: OK"; };;
    1)
      hdr="$(printf '%s\n' "$out" | head -1)"; items="$(printf '%s\n' "$out" | grep -E '^(MISSING|DIFF|MODE|EXTRA) ')"
      log "drift: ${hdr#DRIFT } $(printf '%s\n' "$items" | head -3 | tr '\n' ' ')"
      sig="$(printf '%s\n' "$items" | LC_ALL=C shasum)"; shrc=$?; sig="${sig:0:40}"   # 해시만 LC_ALL=C — C.UTF-8 에서 perl shasum 이 panic(rc=9)
      if [ "$shrc" != 0 ] || [ -z "$sig" ]; then echo "$(date '+%F %T') drift_watch: ERROR signature hash failed rc=$shrc — no alert sent" >&2; return 0; fi
      [ "$(cat "$sigf" 2>/dev/null)" = "$sig" ] && return 0
      master="$(master_seat)"
      [ -n "$master" ] || { echo "$(date '+%F %T') drift_watch: drift pending but no active master" >&2; return 0; }
      if bash "$MBOX" send "$master" ft-tick "[drift] 라이브 bin ↔ main 키트 어긋남 ${hdr#DRIFT } — $(printf '%s\n' "$items" | head -3 | tr '\n' ' ')— master 라이브 cp 필요" >/dev/null 2>&1; then echo "$sig" > "$sigf"
      else echo "$(date '+%F %T') drift_watch: mbox failed" >&2; fi;;
    *) # 원인 = stderr 의 첫 «실제» 줄(알려진 locale 경고는 건너뜀) · 경고뿐이면 경고 1줄
      cause="$(printf '%s\n' "$err" | grep -v -E 'setlocale|Setting locale failed|Please check that your locale|locale settings|LANG(UAGE)? =|LC_[A-Z]+ =|are supported and installed|Falling back' | grep -m1 .)"
      [ -n "$cause" ] || cause="$(printf '%s\n' "$err" | head -1)"
      echo "$(date '+%F %T') drift_watch: check rc=$rc: $(printf '%s\n' "$out" | head -1)${cause:+ [stderr] $cause}" >&2;;
  esac
  return 0
}

# R125(판정 1437): 뉴스 입력 = 오빠 원장 한 파일 — 지금 커밋 ≠ 기준선이면 바뀐 줄만 발행(R118b 30분 무초안 감시는 초안이 없어져 삭제).
# 원장 갱신 0 인 새 판정 알림도 같은 스크립트가 보므로 매 루프 부른다(기준선이 같으면 git log 1번). FT_TICK_NEWS_LEDGER=0 으로 끔.
news_ledger() {
  local out
  [ "${FT_TICK_NEWS_LEDGER:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=news-ledger"; return 0; fi
  out="$(env ${ROOT:+FT_ROOT="$ROOT"} bash "$HERE/ft-news-ledger.sh" 2>&1)" || echo "$(date '+%F %T') news_ledger: $(printf '%s\n' "$out" | tail -1)" >&2
  return 0
}

pass() {
  local rows seat tick role report_to master mok
  idle_watch
  outage_watch
  stall
  sweep_wt
  drift_watch
  news_ledger
  rows="$(read_seats 2>&1)" || { echo "$(date '+%F %T') seats.json unreadable ($SEATS): ${rows//$'\n'/ | }" >&2; return 1; }
  [ -n "$rows" ] || { log "no active seat with tick in $SEATS"; return 0; }
  master="$(master_seat)"; report_to="${FT_TICK_PM_REPORT_TO:-${master:-ft-v65-master}}"
  master_news_ok "$rows" "$master"; mok=$?
  while IFS=$'\t' read -r seat tick role; do
    case "$tick" in
      ft-master-tick)
        if [ "$mok" != 0 ]; then continue; fi   # ERROR 는 master_news_ok 가 기록(서명당 1회) — master news 0
        if [ "$seat" != "$master" ]; then [ -f "$(stamp_of "$seat" mtwarn)" ] || { now > "$(stamp_of "$seat" mtwarn)"; log "WARN master-tick row $seat ≠ _master $master — skipped"; }; continue; fi
        # ★2026-09-14 오빠 「중간 뉴스랑 크론 메세지 … 너무 중복」★ — idle-detected 가 방금 master 에 갔으면 뉴스 틱은 그 턴에 겹치지 않는다
        #   (master 는 이미 행동할 이벤트를 받았다). 실측 18:24~19:31: 뉴스 15회 + idle 14회 = 4.4분마다 1건이 pane 에 꽂혔다.
        igap=$(( $(now) - $(cat "$(stamp_of _all idle-sent)" 2>/dev/null || echo 0) ))
        # ★2026-09-28 master#69 실측: idle-detected 가 1~2분마다 와서 17:01 뒤 뉴스 0회(굶음) — 연기는 최대 FT_TICK_NEWS_MAX_DEFER 까지만★
        ngap=$(( $(now) - $(cat "$(stamp_of "$seat" master)" 2>/dev/null || echo 0) ))
        if [ "$igap" -lt "${FT_TICK_IDLE_QUIET_SEC:-$MASTER_MIN_GAP}" ] && [ "$ngap" -lt "${FT_TICK_NEWS_MAX_DEFER:-900}" ] && [ "$DRY" != 1 ]; then log "skip $seat/master — idle-detected ${igap}s ago (news deferred · last news ${ngap}s)"
        else fire "$seat" master "$MASTER_INTERVAL" "$MASTER_MIN_GAP" "$MASTER_MSG"; fi
        goal "$seat";;
      ft-pm-tick)     fire "$seat" pm "$PM_INTERVAL" "$PM_MIN_GAP" "$(pm_msg "$report_to")";;
      ft-goal-tick)   goal "$seat";;
      *) echo "$(date '+%F %T') unknown tick kind '$tick' for $seat — skipped" >&2;;
    esac
  done <<< "$rows"
}

if [ "$DRY" = 1 ]; then pass; exit $?; fi

# ── ① 단일 인스턴스 — 살아 있는 선점자가 있으면 죽을 때까지 대기(launchd 재스폰 폭주 방지) ──
while :; do
  OLD="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill -0 "$OLD" 2>/dev/null; then
    [ "$ONCE" = 1 ] && { log "already running (pid=$OLD) — exit"; exit 0; }
    log "already running (pid=$OLD) — standby"; sleep 10; continue
  fi
  echo "$$" > "$PIDFILE"; break
done
trap 'rm -f "$PIDFILE"; log "ft-tick stopped"; exit 0' INT TERM
log "ft-tick started pid=$$ seats=$SEATS loop=${LOOP_SEC}s master=${MASTER_INTERVAL}s pm=${PM_INTERVAL}s goal=${GOAL_INTERVAL}s"
while :; do
  pass
  [ "$ONCE" = 1 ] && { rm -f "$PIDFILE"; exit 0; }
  sleep "$LOOP_SEC"
done
