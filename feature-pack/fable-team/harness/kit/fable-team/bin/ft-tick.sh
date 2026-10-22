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
PATH="${FT_TICK_PATH_FIRST:+$FT_TICK_PATH_FIRST:}/opt/homebrew/bin:/usr/local/bin:$PATH"; export PATH   # FT_TICK_PATH_FIRST = 시험 전용 가짜 tmux·pgrep 폴더(R163) — 비면 바이트 불변
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# r459 기동 1회 자가 검사: 형제 ft_raised.py 가 shim(연결 파일)이면 이 파일은 shim 폴더에서 도는 «옛 통째 사본» — 조용히 돌지 않는다
head -3 "$HERE/ft_raised.py" 2>/dev/null | grep -qF 'ft-root-bin-shim' && { echo "$(date '+%F %T') ERROR shim 폴더에서 실행 — launchctl kickstart 로 LIVE_BIN 재기동 ($HERE)" >&2; exit 3; }
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="${FT_ROOT:-$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"   # R382: env FT_ROOT 우선(코드가 다른 리포로 가도 프로젝트 루트 고정) — 데이터 루트는 그 안의 .fable-team/LIVE_ROOT 파일
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
MBOX="${FT_TICK_MBOX:-}"
# r507: 형제 ft-harness-root.sh 는 런타임 경로 — SC1091(info) 도 shellcheck rc1 이라 시험이 RED
# shellcheck source=/dev/null
[ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r459: comm = 공용 루트 .fable-team/comm(ft_comm_dir · LIVE_ROOT 0) — AGENT_ALIVE 도 그 옆
# ★워크트리 정리 sweep (하네스 0.5 행 2 r3 · DA r2 조건 2)★ — 닫힌 나노의 계획(.fable-team/state/wt-clean/*.sh)을 매 루프 실행. 가드·원장 표식은 계획이 맡는다.
#   [HIL] 줄이 나오면 현역 master 우편함으로 올린다(계획이 mbox 를 직접 쏘지 않는다 — 오빠 규칙 2026-09-25). FT_TICK_WT_SWEEP=0 으로 끔.
API_OUTAGE="${FT_TICK_API_OUTAGE_BIN:-$HERE/ft_api_outage.py}"
WT_SWEEP="${FT_TICK_WT_SWEEP_BIN:-$HERE/ft-wt-sweep.sh}"; WT_SWEEP_ENABLED="${FT_TICK_WT_SWEEP:-1}"
# ★라이브 bin 드리프트 경고 (카드 live-bin-drift-check · Issue 816 ③)★ — 설치 꼴(*/.fable-team/bin)에서 돌 때만, 라이브 도구 ↔ origin/main 키트를 FT_TICK_DRIFT_INTERVAL(600s)마다 대조.
#   어긋남 목록이 «바뀐 때만» master 우편함 1회(서명 $STATE_DIR/drift.sig). FT_TICK_DRIFT=0 으로 끔(경고만 끄는 스위치 — spawn·close 입구 BLOCK 은 끌 수 없다).
DRIFT_CHECK="${FT_TICK_DRIFT_BIN:-$HERE/ft-live-bin-drift-check.sh}"; DRIFT_ENABLED="${FT_TICK_DRIFT:-1}"; DRIFT_INTERVAL="${FT_TICK_DRIFT_INTERVAL:-600}"
# ★상향 좌석 «내릴 것» 경보 (R149 · 판정 1641)★ — 명부 raised.card 가 완성/ 으로 갔거나 없어졌는데 행이 남은 좌석을 목록이 «바뀔 때만» master 우편함 1회(서명 $STATE_DIR/raised.sig). FT_TICK_RAISED=0 으로 끔. 판별은 형제 모듈 ft_raised.py.
RAISED="${FT_TICK_RAISED_BIN:-$HERE/ft_raised.py}"
# ★r468 개명 팀 옛 계보 우편 감시★ — 명부 _renamed_from 이 7일 안인 팀의 옛 이름 계보(byz-<옛>-*)에 쌓인 우편을 그 명부 _master 에 1줄(목록이 «바뀔 때만» · 서명 $STATE_DIR/renamed.sig).
#   FT_TICK_RENAMED_SEC(3600)마다 1번 · FT_TICK_RENAMED=0 으로 끔 · 판별은 형제 ft_team_rename.py watch(peek 만 · 우편 소비 0).
RENAMED="${FT_TICK_RENAMED_BIN:-$HERE/ft_team_rename.py}"
# ★R163 (판정 1675 ②) 죽은 좌석 자동 재개★ — 살아 있는 claude 좌석 스냅샷(live_snapshot) · 죽음 판정+재개(dead_seat_watch) · 누적 정지(idle_long_watch). 끄는 스위치 FT_TICK_LIVE_SNAPSHOT / FT_TICK_RESUME / FT_TICK_IDLE_LONG = 0.
RESUME_ATTEMPT="${FT_TICK_RESUME_ATTEMPT:-$HERE/ft-resume-attempt.sh}"
AUTONOMY_BIN="${FT_TICK_AUTONOMY_BIN:-$HERE/ft-autonomy.sh}"
RESOURCE_GATE="${FT_TICK_RESOURCE_GATE:-$HERE/ft-resource-gate.sh}"
ZC_BIN="${FT_TICK_ZOMBIE_CLEAN:-$HOME/.claude/skills/zombie-clean/scripts/zombie-clean.sh}"
IDLE_STALL_MIN="${FT_TICK_IDLE_STALL_MIN:-10}"   # 누적 정지 알림 문턱(분) — stall()(STALL_MIN 15 · 깨움)과 별개의 «알림만» 문턱
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
# R150: 팀 틱이 라이브 bin 을 같이 돌린다 — 팀 문구는 plist 환경변수(FT_TICK_MASTER_MSG · FT_TICK_PM_MSG)로 주입. 미설정이면 아래 문구 그대로(메인 틱 바이트 불변). override 값은 확장·치환 없이 그대로 출력.
MASTER_MSG="${FT_TICK_MASTER_MSG:-[cron-tick · 뉴스] 형식은 SEATBELT-README §6-1 master 항 그대로(★⓪ 완성 상태 트리 = ft-news-tick ⑥ 출력 그대로 맨 위★ · 뉴스 4칸 ≤6불릿 · 빈 줄 · 세션 상태 트리 · 같은 턴에 1건 착수). 변화 없으면 \"변화 없음 — <증상 한 줄>\" 만. 총 ≤900자.}"
pm_msg() { # $1 = report_to — 규칙은 README §6-1 · 정본 3종은 pm 인박스 README 에. 여기선 4항 이름만.
  echo "${FT_TICK_PM_MSG:-[cron-tick] pm 틱 — ①골 대조 1줄(M?/G?) ②원장 미등재 ③활성 나노 @zc_v65_active 전수(0 이면 즉시 set-option) ④사람 확인 필요분 → $1. 변화 없으면 \"변화 없음\" 1줄. 정본·형식: SEATBELT-README §6-1.}"
}

# 한 좌석·한 종류 발사: ② 간격 → ③ busy → 전송 → ④ 제출 검증. $1 seat $2 kind $3 interval $4 min_gap $5 msg
#   R199 FT_TICK_FIRE_V2=1 (기본 0 = 메인 틱 바이트 불변) — 팀 사본(bin-<팀>/ft-tick.sh)이 09-16 에 고친 busy·미제출 감지: 창 14줄·스피너(↓ N tokens·소문자 thinking)·입력줄 «무엇이든» 을 미제출로. 팀 틱 plist 가 켠다.
FIRE_V2="${FT_TICK_FIRE_V2:-0}"
# ★R346 전경·정지 판정★ — pane 은 있어도 전경이 «맨 셸»(claude 꺼짐·정지(T)·재기동 실패 래퍼만)이면 발사하지 않는다(셸이 틱 문구를 glob 으로 해석해 `bad pattern` 유실).
#   판정기 = ft-agent-alive.sh 하나(doorbell 과 같은 것 · MBOX 옆). NOAGENT = 발사 0 + DEAD-SEATS.alert 1회(좌석당 · 회복하면 표식을 지워 다시 죽을 때 재경보) · 판정 불가(rc2) = 발사 0 + 로그(alive 로 안 돌린다).
AGENT_ALIVE="${FT_TICK_AGENT_ALIVE:-$(dirname "$MBOX")/ft-agent-alive.sh}"
#   ★표식 전이는 좌석별 잠금(mkdir <표식>.lock) 안에서 «판정 → 표식 재확인 → alert append → 성공해야 표식 저장 / ALIVE 복귀 rm» 한 번에★(DA⑥ H3 — 같은 prefix 의 동시 틱 둘이 경보를 두 번 쓰거나 rm 과 기록이 엇갈리는 것 차단).
#   append 실패 = 표식 저장 0 → 다음 틱 재시도 · 잠금 못 잡으면 이 틱은 조용히 건너뜀(발사 0 · 다음 틱) · 30초 넘은 잠금은 죽은 주인 것으로 보고 회수.
_gate_lock() { local l="$1.lock"; mkdir "$l" 2>/dev/null && return 0
  [ "$(( $(now) - $(stat -f %m "$l" 2>/dev/null || echo 0) ))" -gt 30 ] || return 1
  rmdir "$l" 2>/dev/null; mkdir "$l" 2>/dev/null; }
_gate_step() {   # $1 seat $2 kind $3 mark — 잠금 안에서만 부른다
  local seat="$1" kind="$2" mark="$3" line rc=0 fg
  line="$(bash "$AGENT_ALIVE" "$seat" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) rm -f "$mark"; return 0;;
    1) fg="$(sed -n 's/.* fg=\([^ ]*\).*/\1/p' <<< "$line")"
       if [ ! -f "$mark" ]; then
         if printf '%s agent absent %s fg=%s (session alive) — kind=%s · claude 꺼짐/정지 — 재기동·재개 필요\n' "$(date '+%F %T')" "$seat" "$fg" "$kind" 2>/dev/null >> "${STAMP_PREFIX}DEAD-SEATS.alert"; then
           now > "$mark"; log "NOAGENT $seat/$kind — fg=$fg (session alive) · alert written once (further skips silent)"
         else log "ERROR NOAGENT $seat/$kind — alert 쓰기 실패 (${STAMP_PREFIX}DEAD-SEATS.alert) · 표식 저장 0 → 다음 틱 재시도"; fi
       fi
       return 1;;
    *) log "skip $seat/$kind — 에이전트 판정 불가 (${line:-$AGENT_ALIVE 실행 실패}) · 발사 0"; return 1;;
  esac
}
agent_gate() {   # $1 seat $2 kind → rc 0 발사 가능 · 1 발사 0
  local mark rc; mark="$(stamp_of "$1" noagent)"
  _gate_lock "$mark" || return 1
  _gate_step "$1" "$2" "$mark"; rc=$?
  rmdir "$mark.lock" 2>/dev/null; return "$rc"
}
fire() {
  local seat="$1" kind="$2" interval="$3" min_gap="$4" msg="$5" stamp gap pane tail tailn=3 busy='esc to interrupt|Working|Thinking' sub='^[›❯] +\[cron-tick\]' subn=2
  [ "$FIRE_V2" = 1 ] && { tailn=14; busy="$busy|↓ [0-9,]+ tokens|\| *thinking"; sub='^[›❯] +[^ ]'; subn=6; }
  stamp="$(stamp_of "$seat" "$kind")"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY seat=$seat kind=$kind interval=${interval}s gap=${gap}s msg=${msg:0:80}"; return 0; fi
  [ "$gap" -ge "$interval" ] || return 0                                   # 아직 차례 아님(조용)
  [ "$gap" -ge "$min_gap" ] || { log "skip $seat/$kind — debounce (${gap}s < ${min_gap}s)"; return 0; }
  pane="$(pane_of "$seat")"; [ -n "$pane" ] || { log "skip $seat/$kind — session absent"; return 0; }
  agent_gate "$seat" "$kind" || return 0
  tail="$(tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -"$tailn")"
  if printf '%s' "$tail" | LC_ALL=C grep -qaE "$busy"; then log "skip $seat/$kind — pane busy (working)"; return 0; fi
  if printf '%s' "$tail" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then log "skip $seat/$kind — pane has unsubmitted input"; return 0; fi
  tmux send-keys -t "$pane" -l "$msg"; sleep 0.3; tmux send-keys -t "$pane" Enter
  now > "$stamp"
  sleep 1.5
  if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -"$subn" | LC_ALL=C grep -qaE "$sub"; then
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
# R597: 살아 있는 나노 좌석 = 명부($1 = "seat<TAB>role" 줄) role=nano ∧ pane 실재. 팀장 정지가 «나노 회신 대기» 인지 판정한다.
live_nano_seats() {
  local pan seat role
  pan="$(tmux list-panes -a -F '#{session_name} #{pane_id}' 2>/dev/null)" || return 0
  while IFS=$'\t' read -r seat role; do
    [ "$role" = nano ] || continue
    [ -n "$(awk -v s="$seat" '$1==s{print $2; exit}' <<< "$pan")" ] || continue
    printf '%s\n' "$seat"
  done <<< "$1"
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

# ── r497 역할 좌석 모델 한도 → 대체 모델 후계 자동 교대 ─────────────────────────────────────────────
# ft_model_swap.py 가 명부 «전체»(seats*.json)의 역할 좌석을 보므로 공용 루트 틱(명부 seats.json) 1곳에서만 — 팀 틱(seats-<팀>.json)은 건너뛴다(중복 교대 0).
# PLAN·HIL 줄은 틱 로그에 · 도구 실패는 ERROR 1줄만 남기고 틱은 계속(조용한 생략 0). FT_MODEL_SWAP=0 으로 끔.
MODEL_SWAP="${FT_TICK_MODEL_SWAP_BIN:-$HERE/ft_model_swap.py}"
model_swap() {
  local out rc ft
  [ "${FT_MODEL_SWAP:-1}" = 1 ] && [ "$(basename "$SEATS")" = seats.json ] || return 0
  ft="$(dirname "$SEATS")"   # 루트 = 명부가 놓인 .fable-team 의 부모 — 임시 명부(시험)로 실제 루트 좌석을 교대하지 않는다
  if [ "$DRY" = 1 ]; then echo "DRY kind=model-swap bin=$MODEL_SWAP fable-team=$ft"; return 0; fi
  [ "$(basename "$ft")" = .fable-team ] || { log "model_swap: skip — 명부가 <루트>/.fable-team/seats.json 꼴 아님 ($SEATS)"; return 0; }
  out="$(python3 "$MODEL_SWAP" --root "$(dirname "$ft")" --mbox "$MBOX" 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -E '^(PLAN|HIL|BUSY) ' | while IFS= read -r l; do log "model_swap: $l"; done
  [ "$rc" = 0 ] || echo "$(date '+%F %T') model_swap: ERROR model_swap rc=$rc: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2
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
  case "$HERE" in */.fable-team/bin|*/.fable-team/*/bin|*/fable-team/live/*/bin) ;; *) return 0;; esac
  stamp="$(stamp_of _all drift)"
  if [ "$DRY" != 1 ] && [ $(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) )) -lt "$DRIFT_INTERVAL" ]; then return 0; fi
  [ -f "$DRIFT_CHECK" ] || { echo "$(date '+%F %T') drift_watch: missing $DRIFT_CHECK" >&2; return 0; }
  # stdout 만 머리글·항목·서명 — stderr(locale 경고 등)가 머리글이 되면 로그·알림·서명이 오염된다. stderr 는 rc≥2 원인 줄로만 쓴다.
  errf="$(mktemp)" && [ -n "$errf" ] || { echo "$(date '+%F %T') drift_watch: ERROR mktemp failed — check not run" >&2; return 0; }
  out="$(bash "$DRIFT_CHECK" --bin "$HERE" 2>"$errf")"; rc=$?   # 키트 리포·경로 = 하네스 코드 루트(r385 · 프로젝트 리포 전제 0)
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

raised_watch() {
  local out rc sig sigf master shrc   # check 는 rc 0 일 때만 stdout 목록을 내고, rc 2 면 stderr 원인 줄만 낸다 → 2>&1 로 한 변수에 받아도 섞이지 않는다
  [ "${FT_TICK_RAISED:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=raised bin=$RAISED"; return 0; fi
  sigf="$STATE_DIR/raised.sig"; mkdir -p "$STATE_DIR"
  out="$(python3 "$RAISED" check "$SEATS" "$(dirname "$SEATS")/seats-*.json" ${ROOT:+--root "$ROOT"} 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "$(date '+%F %T') raised_watch: ERROR check rc=$rc: $(printf '%s\n' "$out" | head -1 | cut -c1-200)" >&2; return 0; }
  [ -n "$out" ] || { rm -f "$sigf"; return 0; }
  sig="$(printf '%s\n' "$out" | LC_ALL=C shasum)"; shrc=$?; sig="${sig:0:40}"   # 해시만 LC_ALL=C — drift_watch 와 같은 이유
  { [ "$shrc" = 0 ] && [ -n "$sig" ]; } || { echo "$(date '+%F %T') raised_watch: ERROR signature hash failed rc=$shrc — no alert sent" >&2; return 0; }
  [ "$(cat "$sigf" 2>/dev/null)" = "$sig" ] && return 0
  master="$(master_seat)"; [ -n "$master" ] || { echo "$(date '+%F %T') raised_watch: ▶내릴 것 pending but no active master" >&2; return 0; }
  bash "$MBOX" send "$master" ft-tick "[▶내릴 것] 상향 좌석 $(printf '%s\n' "$out" | grep -c .)건 — $(printf '%s\n' "$out" | head -3 | tr '\n' ' ')— 닫거나 원래 모델로(판정 1641)" >/dev/null 2>&1 \
    && echo "$sig" > "$sigf" || echo "$(date '+%F %T') raised_watch: mbox failed" >&2
}

renamed_watch() {   # r468 — 옛 계보 우편 «있음» 을 새 명부 _master 에 알린다(relay 는 master 손 · 계획 §4-4)
  local out pend sig sigf stamp last to f seatfiles=()
  [ "${FT_TICK_RENAMED:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=renamed bin=$RENAMED"; return 0; fi
  mkdir -p "$STATE_DIR"; stamp="$STATE_DIR/renamed.last"; sigf="$STATE_DIR/renamed.sig"
  last="$(cat "$stamp" 2>/dev/null || echo 0)"; case "$last" in ''|*[!0-9]*) last=0;; esac
  [ $(( $(now) - last )) -ge "${FT_TICK_RENAMED_SEC:-3600}" ] || return 0
  now > "$stamp"
  for f in "$(dirname "$SEATS")"/seats-*.json; do [ -e "$f" ] && seatfiles+=("$f"); done   # r507: ls 파싱 0 — 공백 이름·0개 안전
  out="$(python3 -I "$RENAMED" watch "$MBOX" "$SEATS" ${seatfiles[@]+"${seatfiles[@]}"} 2>&1)" \
    || { echo "$(date '+%F %T') renamed_watch: ERROR rc=$?: $(printf '%s\n' "$out" | head -1 | cut -c1-200)" >&2; return 0; }
  printf '%s\n' "$out" | grep '^ERROR' | head -3 | sed "s/^/$(date '+%F %T') renamed_watch: /" >&2
  pend="$(printf '%s\n' "$out" | grep '^PENDING')"
  [ -n "$pend" ] || { rm -f "$sigf"; return 0; }
  sig="$(printf '%s\n' "$pend" | LC_ALL=C shasum)"; sig="${sig:0:40}"
  [ "$(cat "$sigf" 2>/dev/null)" = "$sig" ] && return 0
  for to in $(printf '%s\n' "$pend" | cut -f2 | sort -u); do
    [ "$to" != - ] || { echo "$(date '+%F %T') renamed_watch: 옛 계보 우편 있음 · 명부 _master 없음" >&2; continue; }
    bash "$MBOX" send "$to" ft-tick "[개명 우편] 옛 이름 계보에 안 읽은 우편 — $(printf '%s\n' "$pend" | awk -F'\t' -v t="$to" '$2==t{printf "%s %s건(%s→%s) ", $3, $4, $5, $6}')— bash $MBOX recv '<옛 좌석>' 로 받아 새 좌석에 relay(r468)" >/dev/null 2>&1 \
      || { echo "$(date '+%F %T') renamed_watch: mbox failed to=$to" >&2; return 0; }
  done
  echo "$sig" > "$sigf"
}

# ★r630 우편함 거의 참★ — 모든 명부(seats*.json · desk 가 있는 planner 명부 포함) 좌석의 미읽음이 ring-2(8)건+ 이면 그 팀 _master 에 1통.
#   서명(건수·가장 오래된 seq)이 바뀔 때만 다시 · 판별은 형제 ft_queue_watch.py · 명부 깨짐 = ERROR 줄 + 그 명부만 건너뜀. FT_TICK_QUEUE_FULL=0 으로 끔.
queue_full_watch() {
  local out rc
  [ "${FT_TICK_QUEUE_FULL:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=queue-full"; return 0; fi
  out="$(python3 -I "$HERE/ft_queue_watch.py" scan --mbox "$MBOX" --rosters "$(dirname "$SEATS")" --state "${FT_TICK_QUEUE_FULL_STATE:-$(dirname "$SEATS")/state/queue-watch.json}" 2>&1)"; rc=$?
  [ "$rc" = 0 ] || echo "$(date '+%F %T') queue_full_watch: ERROR rc=$rc: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2
  printf '%s\n' "$out" | grep -E '^(ERROR|WARN) ' | sed "s/^/$(date '+%F %T') queue_full_watch: /" >&2
  printf '%s\n' "$out" | grep '^SENT ' | while IFS= read -r l; do log "queue_full_watch: $l"; done
  return 0
}

# ★r529 오빠 큐 재질문★ — 보여준 지 60분 넘은 «대기» 줄·재확인 시각 지난 «보류» 줄을 그 팀 명부 _master 에 [재질문] 1통
#   (ft-queue.sh remind · 팀 - = planner _master · 같은 줄 60분 안 반복 0 · 자율 ON = 쪽지 0 · 아침 묶음 줄만 r291). FT_TICK_QUEUE=0 으로 끔 · FT_TICK_QUEUE_MIN(60).
queue_watch() {
  local out
  [ "${FT_TICK_QUEUE:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=queue-reask"; return 0; fi
  out="$(env ${ROOT:+FT_ROOT="$ROOT"} bash "$HERE/ft-queue.sh" remind --rosters "$(dirname "$SEATS")" --mbox "$MBOX" --min "${FT_TICK_QUEUE_MIN:-60}" 2>&1)" \
    || echo "$(date '+%F %T') queue_watch: $(printf '%s\n' "$out" | grep -m1 -E '^(ERROR|REJECT)' | cut -c1-200)" >&2
  return 0
}

# R125(판정 1437): 뉴스 입력 = 오빠 원장 한 파일 — 지금 커밋 ≠ 기준선이면 바뀐 줄만 발행(R118b 30분 무초안 감시는 초안이 없어져 삭제).
# 원장 갱신 0 인 새 판정 알림도 같은 스크립트가 보므로 매 루프 부른다(기준선이 같으면 git log 1번). FT_TICK_NEWS_LEDGER=0 으로 끔.
news_ledger() {
  local out
  [ "${FT_TICK_NEWS_LEDGER:-1}" = 1 ] || { [ "$DRY" = 1 ] || [ "${FT_TICK_NEWS_WATCH:-1}" != 1 ] || env ${ROOT:+FT_ROOT="$ROOT"} python3 "$HERE/ft_news_ledger.py" stale 2>&1 | tail -1 >&2; return 0; }  # R209 H1: 게시를 끄면 정지 감시만 매 루프(FT_TICK_NEWS_WATCH=0 으로 끔)
  if [ "$DRY" = 1 ]; then echo "DRY kind=news-ledger"; return 0; fi
  out="$(env ${ROOT:+FT_ROOT="$ROOT"} bash "$HERE/ft-news-ledger.sh" 2>&1)" || echo "$(date '+%F %T') news_ledger: $(printf '%s\n' "$out" | tail -1)" >&2
  return 0
}

# ── R163 죽은 좌석 자동 재개 (판정 1675 ②) ──────────────────────────────────────────────────────
# 현역 좌석 → "seat<TAB>role<TAB>agent<TAB>model" (all_seats 와 같은 제외 기준 · 빈 칸은 '-')
resume_rows() {   # $1 = 명부 경로(기본 $SEATS)
  python3 - "${1:-$SEATS}" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); m = d.get("_master")
for k, v in d.items():
    if k.startswith("_") or not isinstance(v, dict): continue
    if isinstance(m, str) and v.get("role") == "master" and k != m: continue
    if v.get("_replaced_by") or v.get("role") == "stop-ready": continue
    print("\t".join([k, v.get("role") or "-", v.get("agent") or "claude", v.get("model") or "-"]))
PY
}
route_seat() { python3 -c 'import json,sys;v=json.load(open(sys.argv[1])).get("_hil_route");print(v if isinstance(v,str) else "")' "$SEATS" 2>/dev/null; }
# ★r718 표식 수신자 — h<N>.notify(seat= · comm= 두 줄)가 있으면 그 쪽지함의 그 좌석으로★
#   $1=h 이름 → `좌석<TAB>쪽지함` · 표식 없음 = 빈 줄 · 손상(줄 없음·폴더 없음) = `!<사유>`(표식은 지우지 않는다)
hil_marker() {
  local nf="${HIL_DIR:-/tmp}/$1.notify" seat comm
  [ -e "$nf" ] || return 0
  seat="$(sed -n 's/^seat=//p' "$nf" 2>/dev/null | head -1)"; comm="$(sed -n 's/^comm=//p' "$nf" 2>/dev/null | head -1)"
  if [ -z "$seat" ] || [ -z "$comm" ] || [ ! -d "$comm" ]; then
    echo "!seat=«${seat:--}» comm=«${comm:--}»$([ -n "$comm" ] && [ ! -d "$comm" ] && echo ' 폴더 없음')"; return 0
  fi
  printf '%s\t%s' "$seat" "$comm"
}
# $1=좌석 $2=쪽지함 폴더 $3=본문 → 그 쪽지함으로 1통(다른 팀 쪽지함은 FT_MBOX_DIR 로 갈아탄다) · 실패 1
hil_notify_marker() {
  [ "$DRY" = 1 ] && { echo "DRY kind=hil-notify-marker to=$1 comm=$2 body=${3:0:60}"; return 0; }
  FT_MBOX_DIR="$2" bash "$MBOX" send "$1" ft-tick "$3" >/dev/null 2>&1 || { echo "$(date '+%F %T') hil_notify_marker: mbox failed to=$1 comm=$2" >&2; return 1; }
}
# $1 = 본문 · $2 = both(그 팀 master + planner) | planner(planner, 없으면 master). 하나라도 실패면 rc 1(호출자가 서명을 남기지 않는다).
notify_team() {
  local master route t rc=0; master="$(master_seat)"; route="$(route_seat)"
  [ -n "$route" ] || route="$master"
  [ "$DRY" = 1 ] && { echo "DRY kind=notify to=${route:--}${master:+,$master} body=${1:0:80}"; return 0; }
  for t in $route $([ "$2" = both ] && [ "$master" != "$route" ] && echo "$master"); do
    [ -n "$t" ] || continue
    bash "$MBOX" send "$t" ft-tick "$1" >/dev/null 2>&1 || { echo "$(date '+%F %T') notify_team: mbox failed to=$t" >&2; rc=1; }
  done
  return $rc
}

# ★R185 (판정 1720 ①) 자율 끝 시각 도달 기록★ — 매 루프 `ft-autonomy.sh expire`(단일 기록자 = 틱). EXPIRED 일 때만 로그 1줄 + planner(_hil_route) 앞 쪽지 1통.
#   `mode`·`status` 는 expire 없이도 끝 도달을 OFF 로 읽는다 — 이 함수는 상태 파일·로그를 «어긋나지 않게» 맞출 뿐. FT_TICK_AUTONOMY=0 으로 끔.
autonomy_expire() {
  local out rc
  [ "${FT_TICK_AUTONOMY:-1}" = 1 ] || return 0
  [ -f "$AUTONOMY_BIN" ] || { echo "$(date '+%F %T') autonomy_expire: missing $AUTONOMY_BIN" >&2; return 0; }
  if [ "$DRY" = 1 ]; then echo "DRY kind=autonomy-expire bin=$AUTONOMY_BIN"; return 0; fi
  out="$(bash "$AUTONOMY_BIN" expire 2>&1)"; rc=$?
  [ "$rc" = 0 ] || { echo "$(date '+%F %T') autonomy_expire: ERROR rc=$rc: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2; return 0; }
  case "$out" in
    EXPIRED\ A*) log "autonomy_expire: $out"; notify_team "[자율 ${out#EXPIRED } 끝 도달 → OFF] 끝 시각이 지나 ft-autonomy.sh expire 가 OFF 로 기록했다. 다시 켜려면 오빠 ! 한 줄(on)." planner
                 log "autonomy_interview: $(bash "$AUTONOMY_BIN" interview-note "${out#EXPIRED }" expire 2>&1 | tail -1)";;   # r466: desk 에 [자율 인터뷰] 1통(연장/종료/레벨 변경 · 10분 중복 억제)
  esac
  return 0
}

# ★R186 (판정 1720) 미실행 h 감시★ — 오빠 실행 파일(/tmp/h<N>)이 발급만 되고 안 쳐진 채 팀이 멈추는 일(10-15 h4 9.5시간)을 사람보다 먼저 드러낸다.
#   ft-hil.sh --pending(미실행·미대체 진입 파일)이 1개 이상이고 «개수가 바뀐 때만» 로그 1줄(서명 $STATE_DIR/hil.sig) · 30분 넘은 h 는 하루 h 당 1통(표식 $STATE_DIR/hil-notified/).
#   ★r718 수신자★ — h<N>.notify(ft-hil.sh --add --notify 가 쓴다)가 있으면 «그 쪽지함(comm=)» 의 «그 좌석(seat=)» 앞 1통(BYZ planner 쪽 0) · 없으면 지금처럼 planner(_hil_route) · 표식이 손상이면 로그 ERROR 1줄 + planner 에 «표식 손상» 1통(조용한 대체 0).
#   FT_TICK_HIL=0 으로 끔(틱을 실제로 도는 시험은 «명시 설정» — 실 /tmp 의 h 파일에 기대지 않는다).
#   ★메인 틱만 돈다(drift·raised 와 같은 R150 꼴 · DA⑥ H3)★ — 좌석표 이름이 seats.json 이 아니면(팀 틱 seats-<팀>.json) 건너뛴다: h 폴더는 팀 공통이라 팀마다 보면 중복·누락.
#   하루 h 당 1통 = mkdir 선점(성공한 틱만 송신 · 송신 실패면 rmdir 해 다음 틱 재시도) · 상태는 이 틱의 STATE_DIR 아래.
HIL_BIN="${FT_TICK_HIL_BIN:-$HERE/ft-hil.sh}"; HIL_NOTIFY_MIN="${FT_TICK_HIL_NOTIFY_MIN:-30}"
hil_watch() {
  local out sigf cnt each h m sdir day seat comm mk tab body
  [ "${FT_TICK_HIL:-1}" = 1 ] || return 0
  [ "$(basename "$SEATS")" = seats.json ] || return 0
  [ -f "$HIL_BIN" ] || { echo "$(date '+%F %T') hil_watch: missing $HIL_BIN" >&2; return 0; }
  out="$(bash "$HIL_BIN" --pending 2>&1)" || { echo "$(date '+%F %T') hil_watch: ERROR --pending: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2; return 0; }
  if [ "$DRY" = 1 ]; then echo "DRY kind=hil pending=${out:--}"; return 0; fi
  sigf="$STATE_DIR/hil.sig"; mkdir -p "$STATE_DIR"
  [ -n "$out" ] || { rm -f "$sigf"; return 0; }
  cnt="$(printf '%s' "$out" | sed -n 's/^미실행 h \([0-9][0-9]*\)개.*/\1/p')"
  [ -n "$cnt" ] || { echo "$(date '+%F %T') hil_watch: ERROR 요약 줄을 못 읽었다: ${out:0:120}" >&2; return 0; }
  [ "$(cat "$sigf" 2>/dev/null)" = "$cnt" ] || { echo "$cnt" > "$sigf"; log "hil_watch: $out"; }
  each="$(bash "$HIL_BIN" --pending --each 2>/dev/null)"; sdir="$STATE_DIR/hil-notified"; day="$(date +%Y%m%d)"
  while read -r h m; do
    [ -n "$h" ] && [ "${m:-0}" -ge "$HIL_NOTIFY_MIN" ] || continue
    body="[HIL 미실행] $h 가 ${m}분째 안 끝났다(미실행 또는 중단/실행 중) — 오빠가 칠 줄 = ! bash ${HIL_DIR:-/tmp}/$h (이미 대체된 장이면 무시)"
    # 원자적 선점 — 진 쪽은 송신하지 않는다
    if ! { mkdir -p "$sdir" && mkdir "$sdir/$h.$day" 2>/dev/null; }; then continue; fi
    mk="$(hil_marker "$h")"; tab=$'\t'; seat="${mk%%"$tab"*}"; comm="${mk#*"$tab"}"
    case "$mk" in
      "") notify_team "$body" planner || rmdir "$sdir/$h.$day" 2>/dev/null ;;                                     # 표식 없음 = 지금 그대로 planner
      !*) echo "$(date '+%F %T') hil_watch: ERROR 표식 손상 ${HIL_DIR:-/tmp}/$h.notify ${mk#!}" >&2               # 조용한 대체 0 — 로그 1줄 + planner 1통(표식 보존)
          notify_team "[HIL 미실행 · 표식 손상] $h — 표식 수신자를 못 읽어 planner 로 보낸다(${HIL_DIR:-/tmp}/$h.notify · ${mk#!})" planner \
            || rmdir "$sdir/$h.$day" 2>/dev/null ;;
      *)  hil_notify_marker "$seat" "$comm" "$body" || rmdir "$sdir/$h.$day" 2>/dev/null ;;
    esac
  done <<< "$each"
  return 0
}

live_snapshot() {   # ① claude 좌석의 대화 스냅샷 — jsonl 이 바뀐 좌석만 쓴다(ft-resume-attempt.sh snapshot · codex·cmd 는 쓰지 않음)
  #   R324: 틱 데몬이 없는 팀(harness·planner·graphics·issues·chatbot·room·lecture…)은 재개 기록이 0 이었다 — 이 틱은 자기 명부 «뒤에» 같은 폴더의 다른 명부(seats.json·seats-*.json)도 훑는다.
  #   다른 명부 훑기는 상태 폴더의 live-sweep stamp 로 FT_TICK_LIVE_SWEEP_SEC(300)마다 1번만(틱 여러 개가 같은 상태 폴더를 쓰면 하나만 돈다 · 스냅샷은 UNCHANGED 면 쓰기 0 이라 겹쳐도 무해) · dry-run 은 stamp 를 쓰지 않는다.
  local rows seat role agent model out roster seen=" " sweep sstamp last
  [ "${FT_TICK_LIVE_SNAPSHOT:-1}" = 1 ] || return 0
  [ -f "$RESUME_ATTEMPT" ] || { echo "$(date '+%F %T') live_snapshot: missing $RESUME_ATTEMPT" >&2; return 0; }
  sweep=0; sstamp="$STATE_DIR/live-sweep"; last="$(cat "$sstamp" 2>/dev/null || echo 0)"; case "$last" in ''|*[!0-9]*) last=0;; esac
  [ $(( $(now) - last )) -ge "${FT_TICK_LIVE_SWEEP_SEC:-300}" ] && sweep=1
  for roster in "$SEATS" $([ "$sweep" = 1 ] && ls "$(dirname "$SEATS")"/seats.json "$(dirname "$SEATS")"/seats-*.json 2>/dev/null); do
    [ -f "$roster" ] || continue
    rows="$(resume_rows "$roster" 2>/dev/null)" || { echo "$(date '+%F %T') live_snapshot: seats.json unreadable ($roster)" >&2; continue; }
    while IFS=$'\t' read -r seat role agent model; do
      [ -n "$seat" ] && [ "$agent" = claude ] && [ -n "$(pane_of "$seat")" ] || continue
      case "$seen" in *" $seat "*) continue;; esac; seen="$seen$seat "
      [ "$model" != - ] || { log "live_snapshot: $seat — 명부에 model 없음, 건너뜀"; continue; }
      if [ "$DRY" = 1 ]; then echo "DRY kind=live-snapshot seat=$seat"; continue; fi
      out="$(bash "$RESUME_ATTEMPT" snapshot "$seat" --agent "$agent" --model "$model" 2>&1)" || echo "$(date '+%F %T') live_snapshot: ERROR $seat: $(printf '%s\n' "$out" | tail -1 | cut -c1-200)" >&2
    done <<< "$rows"
  done
  if [ "$sweep" = 1 ] && [ "$DRY" != 1 ]; then mkdir -p "$STATE_DIR" && now > "$sstamp"; fi
  return 0
}

# ★R615 나노 제외 + 재개 직전 재확인★ — 정상으로 닫힌 나노(ft-nano-close: 명부 pop → 세션 kill)는 «죽은 좌석» 이 아니다(나노는 카드로 새로 연다 · 판정 2219).
#   죽음 목록을 만들 때 role=nano 는 건너뛰고(같은 좌석 하루 1번 로그), claim 바로 앞에서 명부를 «다시» 읽어 그 줄이 없거나 닫힌 표식이면 재개 0.
#   이유 = 명부는 루프 첫머리에 한 번 읽는데 좌석마다 pane_of·record·rested 를 도는 사이에 닫기가 끼면 «줄 있음 + 화면 없음» = 죽음 오판(2026-10-21 07:12 실사건).
nano_skip_note() {   # 같은 좌석은 하루 1번(disabled 경보와 같은 표식 규칙)
  local f
  [ "$DRY" = 1 ] && return 0
  f="$STATE_DIR/nano-skip/$(printf '%s' "$1" | tr '/#' '__').$(date +%Y%m%d)"
  mkdir -p "$STATE_DIR/nano-skip" 2>/dev/null || return 0
  [ -e "$f" ] && return 0
  : > "$f" 2>/dev/null || return 0
  log "dead_seat_watch: $1 — 재개 대상 아님(nano · spawn 으로 다시 연다)"
}
# $1 = 좌석 → active | absent | retired | nano | unreadable (명부 재확인 · 실패는 재개 0 쪽으로 fail-closed)
resume_target_state() {
  python3 - "$SEATS" "$1" <<'PY' 2>/dev/null || echo unreadable
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: print("unreadable"); raise SystemExit
v = d.get(sys.argv[2])
if not isinstance(v, dict): print("absent")
elif v.get("_replaced_by") or v.get("role") == "stop-ready": print("retired")
elif v.get("role") == "nano": print("nano")
else: print("active")
PY
}

# $1 = 좌석 → 계보 사유 1줄(출력 있으면 재개 0) · 없으면 통과. ★같은 베이스의 더 큰 번호 세션이 살아 있으면 재개 0(그 이름을 남긴다)★ — 이름에 번호가 없거나 tmux 목록을 못 읽으면 fail-closed.
lineage_busy() {
  local seat="$1" base num out n m
  case "$seat" in *'#'*) base="${seat%#*}"; num="${seat##*#}";; *) echo "이름에 번호 없음"; return 0;; esac
  case "$num" in ''|*[!0-9]*) echo "이름에 번호 없음"; return 0;; esac
  out="$(tmux list-panes -a -F '#{session_name}' 2>/dev/null)" || { echo "tmux 목록 못 읽음"; return 0; }   # 명령 실패만 fail-closed — 빈 목록(세션 0)은 계보 충돌 0
  for n in $out; do
    case "$n" in "$base"\#*) ;; *) continue;; esac
    m="${n##*#}"; case "$m" in ''|*[!0-9]*) continue;; esac
    [ "$m" -gt "$num" ] && { echo "같은 계보 $n 생존"; return 0; }
  done
  return 0
}

# ② 죽음 = 명부 현역 ∧ tmux 세션 없음 ∧ «완료·휴식» 아님. ON 일 때만 한 루프 1석(master→planner→arch→그 밖) 자원 문지기 통과 시 같은 대화로 재개.
#    시도 = 원장 선점(mkdir lock) → pending → zombie-clean resume --from-live. pending·failed 는 영구 제외 — 풀 수 있는 것은 오빠 allow 토큰 1개뿐. OFF = 재개 0 · 죽음 목록 1통(바뀐 때만).
dead_seat_watch() {
  local rows mode seat role agent model uuid jl st dead="" n=0 line key sigf sig shrc tried=0 lines="" can why out rc tstate lbusy
  [ "${FT_TICK_RESUME:-1}" = 1 ] || return 0
  [ -f "$RESUME_ATTEMPT" ] || { echo "$(date '+%F %T') dead_seat_watch: missing $RESUME_ATTEMPT" >&2; return 0; }
  rows="$(resume_rows 2>/dev/null)" || { echo "$(date '+%F %T') dead_seat_watch: seats.json unreadable ($SEATS)" >&2; return 0; }
  [ "$DRY" = 1 ] || bash "$RESUME_ATTEMPT" sweep >/dev/null 2>&1 || echo "$(date '+%F %T') dead_seat_watch: ERROR ledger sweep failed" >&2
  mode="$(bash "$AUTONOMY_BIN" mode 2>/dev/null)"
  case "$mode" in on) ;; off) ;; *) echo "$(date '+%F %T') dead_seat_watch: ERROR autonomy mode unreadable (${mode:-none}) — OFF 로 취급(재개 0)" >&2; mode=off;; esac
  while IFS=$'\t' read -r seat role agent model; do
    [ -n "$seat" ] && [ -z "$(pane_of "$seat")" ] || continue
    if [ "$role" = nano ]; then   # 나노는 자동 재개 대상 아님 — 죽음 목록·누적 정지 어디에도 싣지 않는다
      [ "$DRY" = 1 ] && echo "DRY kind=dead-seat-nano seat=$seat"
      nano_skip_note "$seat"; continue
    fi
    jl="$(bash "$RESUME_ATTEMPT" record "$seat" jsonl 2>/dev/null)" && bash "$RESUME_ATTEMPT" rested "$jl" && continue   # 완료·휴식 = 죽은 게 아니라 쉬는 중
    case "$role" in master) key=0;; *) case "$seat" in *-planner-*) key=1;; *-arch-*) key=2;; *) key=3;; esac;; esac
    dead+="$key"$'\t'"$seat"$'\t'"$agent"$'\n'
  done <<< "$rows"
  dead="$(printf '%s' "$dead" | sort -s -t$'\t' -k1,1n)"
  while IFS=$'\t' read -r key seat agent; do
    [ -n "$seat" ] || continue; n=$(( n + 1 ))
    tstate="$(resume_target_state "$seat")"; case "$tstate" in
      active) ;;
      absent) log "dead_seat_watch: $seat — 명부에 없음(닫힘) — 재개 0"; continue;;
      *)      log "dead_seat_watch: $seat — 재개 대상 아님($tstate) — 재개 0"; continue;;   # retired·nano·unreadable = fail-closed
    esac
    lbusy="$(lineage_busy "$seat")"; [ -z "$lbusy" ] || { log "dead_seat_watch: $seat — 재개 대상 아님($lbusy) — 재개 0"; continue; }
    uuid=""; [ "$agent" = claude ] && uuid="$(bash "$RESUME_ATTEMPT" record "$seat" uuid 2>/dev/null)"
    if [ -z "$uuid" ]; then lines+="$seat(재개 기록 없음 — 사람 판정) "; continue; fi
    can="$(bash "$RESUME_ATTEMPT" can-try "$seat" "$uuid" 2>/dev/null)"
    if [ "$mode" != on ]; then lines+="$seat(재개 기록 있음 · 자율 OFF) "; continue; fi
    case "$can" in
      fresh|allowed) [ "$tried" = 0 ] || continue;;                    # 한 루프 1석 — 나머지는 다음 루프
      *) lines+="$seat(자동 재개 소진: $can · 오빠 재허용 = ft-resume-attempt.sh allow '$seat' $uuid) "; continue;;
    esac
    if [ "$DRY" = 1 ]; then echo "DRY kind=dead-seat seat=$seat can=$can mode=on"; tried=1; continue; fi
    why="$(bash "$RESOURCE_GATE" check 2>&1)"; rc=$?; why="$(printf '%s\n' "$why" | tail -1)"
    [ "$rc" = 0 ] || { lines+="$seat(자원 문지기 REJECT — 재개 0: ${why:0:100}) "; tried=1; continue; }
    [ "$can" = allowed ] && { bash "$RESUME_ATTEMPT" consume-allow "$seat" "$uuid" >/dev/null 2>&1 || { lines+="$seat(오빠 토큰 소비 실패 — 재개 0) "; tried=1; continue; }; }
    bash "$RESUME_ATTEMPT" claim "$seat" "$uuid" >/dev/null 2>&1 || { log "dead_seat_watch: $seat — 원장 선점 실패(이미 시도됨), 건너뜀"; continue; }
    tried=1
    out="$(bash "$ZC_BIN" resume "$seat" --from-live 2>&1)"; rc=$?
    if [ "$rc" = 0 ]; then notify_team "[재개] $seat — 죽은 좌석을 같은 대화(uuid=$uuid)로 다시 열었다(자율 ON · 자원 통과). 결과는 3루프 안에 ok/failed 로 원장에 남는다" both
    else bash "$RESUME_ATTEMPT" settle "$seat" "$uuid" failed >/dev/null 2>&1
         notify_team "[재개 실패] $seat uuid=$uuid — $(printf '%s\n' "$out" | tail -1 | cut -c1-160) · 자동 재시도 0 · 오빠 재허용 = ft-resume-attempt.sh allow '$seat' $uuid" both; fi
    log "dead_seat_watch: resume $seat rc=$rc"
  done <<< "$dead"
  [ "$DRY" = 1 ] && echo "DRY kind=dead-seat mode=$mode dead=$n"
  sigf="$STATE_DIR/dead.sig"; mkdir -p "$STATE_DIR"
  [ -n "$lines" ] || { rm -f "$sigf"; return 0; }
  sig="$(printf '%s' "$lines" | LC_ALL=C shasum)"; shrc=$?; sig="${sig:0:40}"
  { [ "$shrc" = 0 ] && [ -n "$sig" ]; } || { echo "$(date '+%F %T') dead_seat_watch: ERROR signature hash failed rc=$shrc — no alert sent" >&2; return 0; }
  [ "$(cat "$sigf" 2>/dev/null)" = "$sig" ] && return 0
  notify_team "[죽은 좌석 $n] 자율 $(printf %s "$mode" | tr '[:lower:]' '[:upper:]') — ${lines% }" planner && [ "$DRY" != 1 ] && echo "$sig" > "$sigf"
  return 0
}

# ③ 누적 정지 — IDLE 지속 ≥ IDLE_STALL_MIN 분 ∧ 받은 발주 0 ∧ 완료·휴식 아님. master 도 대상(master 정지 → planner · 그 밖 → master). 같은 정지(turn_end 같음)는 1회만.
idle_long_watch() {
  local rows master route seat role p st end dur rep src ep mins pend jl to sdir body nn lists nanotag
  local nanos="" nanos_read=0
  [ "${FT_TICK_IDLE_LONG:-1}" = 1 ] || return 0
  [ -f "$SEAT_STATUS" ] || return 0
  rows="$(all_seats 2>/dev/null)" || return 0
  master="$(master_seat)"; route="$(route_seat)"; [ -n "$route" ] || route="$master"
  sdir="$STATE_DIR/idlelong"; mkdir -p "$sdir"
  while IFS=$'\t' read -r seat role; do
    [ -n "$seat" ] || continue
    p="$(pane_of "$seat")"; [ -n "$p" ] || { rm -f "$sdir/$seat"; continue; }
    [ "$role" = nano ] && { rm -f "$sdir/$seat"; continue; }   # R615: 나노는 누적 정지 감지 대상 아님(카드로 새로 연다)
    read -r st end dur rep src <<< "$(turn_line "$seat")"
    [ "$st" = IDLE ] && [ "$src" != pane ] || { rm -f "$sdir/$seat"; continue; }
    ep="$(iso_epoch "$end")"; [ -n "$ep" ] || continue
    mins=$(( ($(now) - ep) / 60 )); [ "$mins" -ge "$IDLE_STALL_MIN" ] || continue
    [ "$(cat "$sdir/$seat" 2>/dev/null)" = "$end" ] && continue
    pend="$(bash "$MBOX" peek "$seat" 2>/dev/null | sed -n 's/.*pending=\([0-9][0-9]*\).*/\1/p' | head -1)"; [ "$pend" = 0 ] || continue
    jl="$(bash "$SEAT_STATUS" jsonl "$seat" 2>/dev/null)"; [ -n "$jl" ] && [ -f "$RESUME_ATTEMPT" ] && bash "$RESUME_ATTEMPT" rested "$jl" && continue
    # R597: 팀장 정지인데 같은 명부에 살아 있는 나노가 있으면 «나노 회신 대기»(정상) — 문턱(6×) 전엔 알림 0 · 로그만.
    nn=0; lists=""; nanotag=""
    if [ "$role" = master ]; then
      [ "$nanos_read" = 1 ] || { nanos="$(live_nano_seats "$rows")"; nanos_read=1; }
      if [ -n "$nanos" ]; then
        nn="$(printf '%s\n' "$nanos" | wc -l | tr -d ' ')"; lists="$(printf '%s\n' "$nanos" | paste -sd',' - | sed 's/,/, /g')"; nanotag=" nanos=$nn"
        if [ "$mins" -lt "$(( IDLE_STALL_MIN * 6 ))" ]; then
          if [ "$DRY" = 1 ]; then echo "DRY kind=idle-long-nano-wait seat=$seat nanos=$nn"; else log "idle_long_watch: $seat 정지 ${mins}분 — 나노 ${nn} 회신 대기($lists)"; fi
          continue
        fi
      fi
    fi
    to="$master"; [ "$seat" = "$master" ] && to="$route"
    [ -n "$to" ] && [ "$to" != "$seat" ] || { echo "$(date '+%F %T') idle_long_watch: $seat 정지 ${mins}분 — 알릴 상위 좌석 없음" >&2; continue; }
    if [ "$DRY" = 1 ]; then echo "DRY kind=idle-long seat=$seat mins=$mins to=$to$nanotag"; continue; fi
    if [ "$nn" -gt 0 ]; then   # 문턱(6×)을 넘겨도 나노가 살아 있으면 사유를 «나노 회신 대기» 로 적는다
      body="[정지 ${mins}분] $seat role=$role — 기다리는 것 = 나노 ${nn} 회신(${lists}) · 나노 대기 ${mins}분 · 나노 pane 확인·깨우기·닫기 중 하나"
    else
      body="[정지 ${mins}분] $seat role=$role — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"
    fi
    bash "$MBOX" send "$to" ft-tick "$body" >/dev/null 2>&1 \
      && echo "$end" > "$sdir/$seat" || echo "$(date '+%F %T') idle_long_watch: mbox failed seat=$seat" >&2
  done <<< "$rows"
}

# ★예약 감시 (R184)★ — 08:15 아침 매거진 미발행 경보(ft-magazine-check.sh · _hil_route 가 있는 팀 틱만 · 같은 날 1회는 도구의 표식) + 기대 예약표의 꺼진 예약 점검(ft-launchd-check.sh · 출력이 «바뀔 때만» 로그 1줄).
#   FT_TICK_LAUNCHD=0 은 두 점검 전부 · FT_TICK_MAGAZINE=0 은 08:15 매거진 경보만 끈다(ft-tick 을 실제로 도는 시험은 두 스위치를 «명시 설정» — 임시 HOME 의 로그 부재에 기대지 않는다). 두 도구 모두 로컬 파일·launchctl 만 읽는다.
launchd_watch() {
  local out sig mseats="${FT_TICK_MAG_SEATS:-$SEATS}"   # 경보용 명부 — 메인 틱 명부에 _hil_route 가 없을 때 planner 명부를 따로 받는다(R194)
  [ "${FT_TICK_LAUNCHD:-1}" = 1 ] || return 0
  if [ "$DRY" = 1 ]; then echo "DRY kind=launchd-watch magazine=$HERE/ft-magazine-check.sh launchd=$HERE/ft-launchd-check.sh mag_seats=$mseats"; return 0; fi
  if [ "${FT_TICK_MAGAZINE:-1}" = 1 ] && grep -q '"_hil_route": *"' "$mseats" 2>/dev/null && [ -f "$HERE/ft-magazine-check.sh" ]; then
    out="$(FT_MAG_SEATS="$mseats" bash "$HERE/ft-magazine-check.sh" 2>&1)"; case "$out" in ALERT*|ERROR*) log "launchd_watch: $out";; esac
  fi
  [ -f "$HERE/ft-launchd-check.sh" ] || return 0
  out="$(FT_LDC_SEATS="$SEATS" bash "$HERE/ft-launchd-check.sh" 2>&1)"; mkdir -p "$STATE_DIR"
  sig="$(printf '%s' "$out" | cksum | cut -d' ' -f1)"
  [ "$sig" = "$(cat "$STATE_DIR/launchd.sig" 2>/dev/null)" ] && return 0
  printf '%s' "$sig" > "$STATE_DIR/launchd.sig"; [ -n "$out" ] && log "launchd_watch: ${out//$'\n'/ | }"
  return 0
}

# ★R347 유출 부하 경보★ — 좌석이 SIGKILL 로 끊겨 EXIT trap 이 안 돈 busy-loop 고아(2026-10-17 load 151)를 매 루프 «dry-run 으로만» 찾아 planner 큐에 알린다.
#   틱은 영구히 --kill 을 부르지 않는다(사살 실행자 = 머신 launchd 가드 1). 판정·경보 규칙은 ft-leak-watch.sh · 끄는 스위치 FT_TICK_LEAK_REAP=0.
leak_watch() {
  local out lw_args=()
  [ "${FT_TICK_LEAK_REAP:-1}" = 1 ] || return 0
  [ -f "$HERE/ft-leak-watch.sh" ] || { echo "$(date '+%F %T') leak_watch: missing $HERE/ft-leak-watch.sh" >&2; return 0; }
  [ "$DRY" = 1 ] && lw_args=(--dry-run)
  out="$(FT_TICK_SEATS="$SEATS" FT_TICK_MBOX="$MBOX" bash "$HERE/ft-leak-watch.sh" ${lw_args[@]+"${lw_args[@]}"} 2>&1)"
  if [ -n "$out" ]; then
    if [ "$DRY" = 1 ]; then echo "$out"; else log "${out//$'\n'/ | }"; fi
  fi
  return 0
}

pass() {
  local rows seat tick role report_to master mok
  autonomy_expire
  leak_watch
  hil_watch
  live_snapshot
  dead_seat_watch
  idle_watch
  idle_long_watch
  outage_watch
  model_swap
  stall
  sweep_wt
  drift_watch
  raised_watch
  renamed_watch
  queue_full_watch
  queue_watch
  launchd_watch
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
