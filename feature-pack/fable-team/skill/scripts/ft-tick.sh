#!/bin/bash
# ★런타임 사본은 git 추적 밖이다 — 실전은 <워크트리>/.fable-team/bin/ 의 사본으로 돌린다. 이 파일이 팩 SSOT(Seatbelt 1.0.1).★
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
set -uo pipefail
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
SEATS="${FT_TICK_SEATS:-${ROOT:-$WT}/.fable-team/seats.json}"
GOAL_TICK="${FT_TICK_GOAL_TICK:-$HERE/ft-goal-tick.sh}"
LOOP_SEC="${FT_TICK_LOOP_SEC:-60}"
PIDFILE="${FT_TICK_PIDFILE:-/tmp/ft-tick.pid}"
MASTER_INTERVAL="${FT_TICK_MASTER_INTERVAL:-900}"; MASTER_MIN_GAP="${FT_TICK_MASTER_MIN_GAP:-840}"
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
ONCE=0; DRY=0
for a in "$@"; do case "$a" in --once) ONCE=1;; --dry-run) DRY=1;; *) echo "usage: $0 [--once] [--dry-run]" >&2; exit 2;; esac; done

log() { echo "$(date '+%F %T') $*"; }
now() { date +%s; }
stamp_of() { echo "/tmp/ft-tick-$1${2:+.$2}.last"; }
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
master_seat() { awk -F'\t' '$3=="master"{print $1; exit}' <<< "$1"; }

# ★master 틱 = «뉴스 발행» (2026-09-14 오빠 지시 원문: 「master는 메세지가 이런게 아니고 진행중과 남은작업을 정리해서 현재 어떤 작업을
#   하고 있다는 뉴스가 발행되야하낟. 테스트는 어떻게 계획중이고 완성까지 전망을 발행. 멈춘거면 어디 세션을 확인하라고 알리던가
#   master가 인터뷰 걸어서 나에게 알리고 선택하면 전파 돌파」). 점검 항목 나열이 아니라 «지금·남은·테스트·전망» 네 칸의 짧은 뉴스다.
#   정지는 ft-tick 의 stall 감시가 [stall] 로 master 에 올린다 — master 는 그걸 받으면 «어느 세션을 보라» 한 줄 또는 AskUserQuestion.
# 오빠 정정 3회차(2026-09-14): 「이거봐 인덱스 덩어리자나. 그리고 어디 세션이 무엇을하는지 세션 상태는 마지막에 따로 공유」
#   ⇒ 인덱스 «파일명»(M5-owner-live-operation-id 같은 슬러그)을 뉴스에 쓰지 않는다 — 그건 좌표지 뉴스가 아니다.
#      뉴스는 «사람 말»로: 무엇이 안 되던 것을 무엇으로 고치는 중인가. 좌석·세션은 뉴스 밖 «세션 상태» 절에 따로.
MASTER_MSG="${FT_TICK_MASTER_MSG:-[cron-tick · 뉴스] 제품(M0–M7·K1–K5)만. ★인덱스 파일명·슬러그·경로·좌석명을 뉴스 본문에 쓰지 않는다★ — 「M5-owner-live-…」 같은 덩어리는 좌표지 뉴스가 아니다(오빠 「인덱스 덩어리자나」). 사람 말로 불릿: ▶지금 — «어떤 증상»을 «무엇으로» 고치는 중, 단계(①press②원인③DA④구현⑤재press⑥클로즈) 1~2불릿 / ▶남은 것 — 다음에 고칠 증상 ≤3불릿(선행이 있으면 «~뒤») / ▶테스트 — 다음 press 가 «무엇이 0/≥1 이면 통과» 1~2불릿 / ▶전망 — 닫히는 축(M?/K? 한 글자만) · press 몇 회 1불릿. 그 아래 빈 줄 뒤 「세션 상태」 절 따로 — 불릿 한 줄씩 ★«세션명 - 상태 - 역할 - 진행내용»★(오빠 5회차 「앞에 상태를 두자 - 세션명 - 상태 - 역할 - 진행내용」). 상태는 ft-seat-status.sh 값(작업중/대기/정지레디/정지)이지 «받았다» 같은 이벤트가 아니다 — «DA — 판정요청 2건 받음» 은 상태가 아니라 «대기»다. 예: 「- ft-v65-arch-fable#41 - 작업중 - DA - 팩 mbox seats.json 경로 차이 판정」 「- ft-v65-temp-owner-opid#0 - 대기 - 오너-충돌 수정 나노 - 산출 완료, 재press 대기」. ★뉴스·세션 상태를 쓰고 «끝내지 않는다»★ — 발행 뒤 같은 턴에 «내가 지금 굴릴 수 있는 것»(대기 중 좌석에 다음 단위 발주·press 슬롯 GO·pm 정렬 요청) 을 최소 1건 착수한다. 좌석이 전부 «대기»면 그건 master 가 발주를 안 한 것이다(오빠 「이렇게 쓰고 아무것도 안하는건 master 문제인가?」 → 그렇다). 뉴스와 섞지 않는다. [stall] 있으면 맨 위 «확인할 세션: <좌석> — <이유>», 선택 필요하면 AskUserQuestion. 운영(미커밋·USER-ORDERS)은 하고 쓰지 않는다. 변화 없으면 \"변화 없음 — <증상 한 줄>\" + 세션 상태 절.}"
pm_msg() { # $1 = report_to
  echo "${FT_TICK_PM_MSG:-[cron-tick] pm 점검 틱(v65 정본 기준, 2026-09-13 master-sonnet#0 개정 — PROGRESS.md/fable-orch/ammo 계열 폐기, 참조 금지) — RUNLOG-pm1-v65-timeline.md(최신 E번호)·NANO-LEDGER-pm1-temp-sessions.md·GOAL-LEDGER-v65.md·GOAL-20260912-clear-list.md 대조해 ①골 대조 한 줄(지금 진행 중인 것이 M?/G? 어느 축인가) ②원장 미등재 항목 유무 ③활성 나노(ft-v65-temp-*) 전수 @zc_v65_active 태그 확인 — 0 인 활성 좌석은 이 틱에서 즉시 tmux set-option 으로 표식 ④사람 확인 필요 항목은 모아서 $1 에. 변화 없으면 \"변화 없음\" 1줄.}"
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
d = json.load(open(sys.argv[1]))
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    # impl/checker 는 나노 계열이라 정지 감시 대상. tester 는 press 슬롯을 master 가 게이트하므로 제외.
    if v.get("_replaced_by") or v.get("role") not in ("master", "da", "pm", "nano", "impl", "checker", "harness-design"): continue
    print(f"{k}\t{v.get('role','')}")
PY
}

stall() {
  local stamp gap rows seat role line pane age agent thr p wstamp wgap cnt msg master
  stamp="$(stamp_of _all stall)"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY kind=stall interval=${STALL_INTERVAL}s min=${STALL_MIN}m seats=$(active_seats 2>/dev/null | cut -f1 | tr '\n' ' ')"; return 0; fi
  [ "$gap" -ge "$STALL_INTERVAL" ] || return 0
  now > "$stamp"
  [ -f "$SEAT_STATUS" ] || { echo "$(date '+%F %T') stall: seat-status missing $SEAT_STATUS" >&2; return 0; }
  rows="$(active_seats 2>/dev/null)" || { echo "$(date '+%F %T') stall: seats.json unreadable" >&2; return 0; }
  master="$(awk -F'\t' '$2=="master"{print $1; exit}' <<< "$rows")"
  thr=$(( STALL_MIN * 60 ))
  while IFS=$'\t' read -r seat role; do
    [ -n "$seat" ] || continue
    p="$(pane_of "$seat")"; [ -n "$p" ] || continue          # 세션 없음은 정지가 아니라 부재 — master 틱이 본다
    line="$(bash "$SEAT_STATUS" one "$seat" 2>/dev/null)"
    read -r _ pane age agent _ <<< "$line"
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

pass() {
  local rows seat tick role report_to
  stall
  rows="$(read_seats 2>&1)" || { echo "$(date '+%F %T') seats.json unreadable ($SEATS): ${rows//$'\n'/ | }" >&2; return 1; }
  [ -n "$rows" ] || { log "no active seat with tick in $SEATS"; return 0; }
  report_to="$(master_seat "$rows")"; report_to="${FT_TICK_PM_REPORT_TO:-${report_to:-ft-v65-master}}"
  while IFS=$'\t' read -r seat tick role; do
    case "$tick" in
      ft-master-tick) fire "$seat" master "$MASTER_INTERVAL" "$MASTER_MIN_GAP" "$MASTER_MSG"; goal "$seat";;
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
