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
# r459 기동 1회 자가 검사: 형제 ft_raised.py 가 shim(연결 파일)이면 이 파일은 shim 폴더에서 도는 «옛 통째 사본» — 조용히 돌지 않는다
head -3 "$HERE/ft_raised.py" 2>/dev/null | grep -qF 'ft-root-bin-shim' && { echo "$(date '+%F %T') ERROR shim 폴더에서 실행 — launchctl kickstart 로 LIVE_BIN 재기동 ($HERE)" >&2; exit 3; }
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
MBOX="${FT_TICK_MBOX:-}"; [ -n "$MBOX" ] || { . "$HERE/ft-harness-root.sh"; _CM="$(ft_comm_dir "$HERE")" || exit 1; MBOX="$_CM/mbox.sh"; }   # r459: comm = 공용 루트 .fable-team/comm(ft_comm_dir · LIVE_ROOT 0) — AGENT_ALIVE 도 그 옆
ONCE=0; DRY=0
for a in "$@"; do case "$a" in --once) ONCE=1;; --dry-run) DRY=1;; *) echo "usage: $0 [--once] [--dry-run]" >&2; exit 2;; esac; done

log() { echo "$(date '+%F %T') $*"; }
now() { date +%s; }
STAMP_PREFIX="${FT_TICK_STAMP_PREFIX:-/tmp/ft-tick-}"   # 2026-09-15 FB_CFO#9: 트랙별 stamp 네임스페이스(기본값=원본 동작)
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
master_seat() {
  python3 - "$SEATS" <<'PY'
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
MASTER_MSG="${FT_TICK_MASTER_MSG:-[cron-tick · 뉴스] 제품(M0–M7·K1–K5)만. ★인덱스 파일명·슬러그·경로·좌석명을 뉴스 본문에 쓰지 않는다★ — 「M5-owner-live-…」 같은 덩어리는 좌표지 뉴스가 아니다(오빠 「인덱스 덩어리자나」). 사람 말로 불릿: ▶지금 — «어떤 증상»을 «무엇으로» 고치는 중, 단계(①press②원인③DA④구현⑤재press⑥클로즈) 1~2불릿 / ▶남은 것 — 다음에 고칠 증상 ≤3불릿(선행이 있으면 «~뒤») / ▶테스트 — 다음 press 가 «무엇이 0/≥1 이면 통과» 1~2불릿 / ▶전망 — 닫히는 축(M?/K? 한 글자만) · press 몇 회 1불릿. 그 아래 빈 줄 뒤 「세션 상태」 절 따로 — 불릿 한 줄씩 ★«세션명 - 상태 - 역할 - 진행내용»★(오빠 5회차 「앞에 상태를 두자 - 세션명 - 상태 - 역할 - 진행내용」). 상태는 ft-seat-status.sh 값(작업중/대기/정지레디/정지)이지 «받았다» 같은 이벤트가 아니다 — «DA — 판정요청 2건 받음» 은 상태가 아니라 «대기»다. 예: 「- ft-v65-arch-fable#41 - 작업중 - DA - 팩 mbox seats.json 경로 차이 판정」 「- byz-v65-nano-owner-opid#0 - 대기 - 오너-충돌 수정 나노 - 산출 완료, 재press 대기」. ★뉴스·세션 상태를 쓰고 «끝내지 않는다»★ — 발행 뒤 같은 턴에 «내가 지금 굴릴 수 있는 것»(대기 중 좌석에 다음 단위 발주·press 슬롯 GO·pm 정렬 요청) 을 최소 1건 착수한다. 좌석이 전부 «대기»면 그건 master 가 발주를 안 한 것이다(오빠 「이렇게 쓰고 아무것도 안하는건 master 문제인가?」 → 그렇다). 뉴스와 섞지 않는다. [stall] 있으면 맨 위 «확인할 세션: <좌석> — <이유>», 선택 필요하면 AskUserQuestion. 운영(미커밋·USER-ORDERS)은 하고 쓰지 않는다. 변화 없으면 \"변화 없음 — <증상 한 줄>\" + 세션 상태 절.}"
pm_msg() { # $1 = report_to
  echo "${FT_TICK_PM_MSG:-[cron-tick] pm 점검 틱(v65 정본 기준, 2026-09-13 master-sonnet#0 개정 — PROGRESS.md/fable-orch/ammo 계열 폐기, 참조 금지) — RUNLOG-pm1-v65-timeline.md(최신 E번호)·NANO-LEDGER-pm1-temp-sessions.md·GOAL-LEDGER-v65.md·GOAL-20260912-clear-list.md 대조해 ①골 대조 한 줄(지금 진행 중인 것이 M?/G? 어느 축인가) ②원장 미등재 항목 유무 ③활성 나노(byz-v65-nano-* · 옛 이름 ft-v65-temp-*) 전수 @zc_v65_active 태그 확인 — 0 인 활성 좌석은 이 틱에서 즉시 tmux set-option 으로 표식 ④사람 확인 필요 항목은 모아서 $1 에. 변화 없으면 \"변화 없음\" 1줄.}"
}

# ★죽은 좌석 가드 도우미(판정 ㊼)★
# heir_of <seat>: 같은 계보(「베이스#N」의 베이스가 같은 것) 중 tmux 에 살아 있고 «N 이 dead 의 N 보다 큰» 최대 N. 없으면 빈 줄(낮거나 같은 N = 옛 incarnation · R27).
heir_of() {
  local base="${1%#*}" dn="${1##*#}"
  [ "$base" != "$1" ] || return 0
  case "$dn" in ''|*[!0-9]*) return 0;; esac
  tmux ls -F '#{session_name}' 2>/dev/null | awk -v b="$base" -v d="$dn" -F'#' '$1==b && NF==2 && $2 ~ /^[0-9]+$/ && $2+0 > d+0 {print $2}' | sort -n | tail -1
}
# retarget_seat <dead> <heir_n>: seats 파일에서 dead 행 tick→null·_replaced_by=heir, heir 행(없으면 신설)에 dead 의 tick·role 부여. 백업 1개 남긴다.
#   rc 3 = heir 행이 이미 은퇴(_replaced_by) — 명부 쓰기 0(R27). _master 는 «_master == dead» 일 때만 같은 dump 안에서 heir 로.
retarget_seat() {
  python3 - "$SEATS" "$1" "${1%#*}#$2" <<'PY'
import json, sys, datetime, shutil
p, dead, heir = sys.argv[1:4]
d = json.load(open(p, encoding="utf-8"))
if d.get(heir, {}).get("_replaced_by"): sys.exit(3)
shutil.copy(p, p + ".bak-retarget-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
src = d[dead]; tick = src.get("tick"); role = src.get("role")
src["tick"] = None; src["_replaced_by"] = heir; src["role"] = "stop-ready"
dst = d.setdefault(heir, {"agent": src.get("agent", "claude"), "model": src.get("model")})
dst["tick"] = tick; dst["role"] = role; dst.pop("_replaced_by", None)  # 상속자는 현역 — 남은 교체 표식은 지운다
dst["_replaces"] = sorted(set(dst.get("_replaces", []) + [dead]))
dst["_auto_retarget"] = f"{datetime.datetime.now().isoformat(timespec='seconds')} by ft-tick (dead={dead})"
if d.get("_master") == dead: d["_master"] = heir
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

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
# 한 좌석·한 종류 발사: ② 간격 → ③ busy → 전송 → ④ 제출 검증. $1 seat $2 kind $3 interval $4 min_gap $5 msg
fire() {
  local seat="$1" kind="$2" interval="$3" min_gap="$4" msg="$5" stamp gap pane tail
  stamp="$(stamp_of "$seat" "$kind")"; gap=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
  if [ "$DRY" = 1 ]; then echo "DRY seat=$seat kind=$kind interval=${interval}s gap=${gap}s msg=${msg:0:80}"; return 0; fi
  [ "$gap" -ge "$interval" ] || return 0                                   # 아직 차례 아님(조용)
  [ "$gap" -ge "$min_gap" ] || { log "skip $seat/$kind — debounce (${gap}s < ${min_gap}s)"; return 0; }
  pane="$(pane_of "$seat")"
  if [ -z "$pane" ]; then
    # ★죽은 좌석 가드(판정 ㊼ 2026-09-27 · 오빠 「죽은 세션 뉴스 크론 안돌도록」)★ — 9/18~9/27 FB_CFO#12 부재를 «매분 skip» 11,204회만 찍고
    #   뉴스 0회. 부재면 ①같은 계보(베이스명#N)의 살아 있는 최대 N 으로 seats 를 «자동 승계»(백업 남김 · 다음 루프부터 그쪽으로)
    #   ②후보가 없으면 경보 파일 1회 + 로그 1회(좌석당 · 반복 금지). 조용한 skip 반복은 «가려짐»이라 없앴다.
    local heir rc=1
    heir="$(heir_of "$seat")"
    [ -z "$heir" ] || { retarget_seat "$seat" "$heir"; rc=$?; }
    if [ "$rc" = 0 ]; then log "RETARGET $seat → ${seat%#*}#$heir (session absent · lineage heir · seats=$SEATS)"
    elif [ -n "$heir" ] && [ "$rc" != 3 ]; then log "RETARGET FAILED $seat → ${seat%#*}#$heir (seats write error)"
    else
      local dead="$(stamp_of "$seat" dead)"
      if [ ! -f "$dead" ]; then
        now > "$dead"
        printf '%s dead seat %s (kind=%s) — no live heir in lineage; fix %s (tick→null or new master row)\n' "$(date '+%F %T')" "$seat" "$kind" "$SEATS" >> "${STAMP_PREFIX}DEAD-SEATS.alert"
        log "DEAD $seat/$kind — session absent, no heir; alert written once to ${STAMP_PREFIX}DEAD-SEATS.alert (further skips silent)"
      fi
    fi
    return 0
  fi
  agent_gate "$seat" "$kind" || return 0
  # ★tail -3 은 «상태줄 3줄»만 잡아 busy 를 «한 번도» 못 걸렀다(2026-09-16 실측: skip busy 0건 / master sent 10건 중 절반 유실).
  #   상태줄(branch·Model·session·bypass)이 최대 5줄이라 작업표시가 그 위로 밀린다 — 창을 넓혀서 본다.
  tail="$(tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -14)"
  # ★작업중 신호: 구 문구(esc to interrupt/Working/Thinking) + 현 UI(스피너 「… (12s · ↓ N tokens)」·상태줄 소문자 thinking).
  if printf '%s' "$tail" | LC_ALL=C grep -qaE 'esc to interrupt|Working|Thinking|↓ [0-9,]+ tokens|\| *thinking'; then log "skip $seat/$kind — pane busy (working)"; return 0; fi
  if printf '%s' "$tail" | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then log "skip $seat/$kind — pane has unsubmitted input"; return 0; fi
  tmux send-keys -t "$pane" -l "$msg"; sleep 0.3; tmux send-keys -t "$pane" Enter
  now > "$stamp"
  sleep 1.5
  # ★구 검증은 입력줄 첫 글자가 「[cron-tick」 로 «보일 때»만 잡았다 — 긴 메시지는 줄바꿈돼 마지막 2줄에 그 앞부분이 «안 보인다».
  #   그래서 미제출을 «한 번도» 못 잡았다(2026-09-16 실측: not submitted 0건). 입력줄에 «무엇이든» 남아 있으면 미제출로 본다.
  if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -vE '^\s*$' | tail -6 | LC_ALL=C grep -qaE '^[›❯] +[^ ]'; then
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
  master="$(master_seat)"
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

# ★R347 유출 부하 경보★ — ft-tick.sh 의 같은 이름 함수와 같은 계약(dry-run 경보만 · 사살은 머신 launchd 가드 1 · 끄는 스위치 FT_TICK_LEAK_REAP=0).
leak_watch() {
  local out
  [ "${FT_TICK_LEAK_REAP:-1}" = 1 ] || return 0
  [ -f "$HERE/ft-leak-watch.sh" ] || { echo "$(date '+%F %T') leak_watch: missing $HERE/ft-leak-watch.sh" >&2; return 0; }
  out="$(FT_TICK_SEATS="$SEATS" FT_TICK_MBOX="$MBOX" bash "$HERE/ft-leak-watch.sh" $([ "$DRY" = 1 ] && echo --dry-run) 2>&1)"
  [ -n "$out" ] && { [ "$DRY" = 1 ] && echo "$out" || log "${out//$'\n'/ | }"; }
  return 0
}

pass() {
  local rows seat tick role report_to master mok
  leak_watch
  stall
  rows="$(read_seats 2>&1)" || { echo "$(date '+%F %T') seats.json unreadable ($SEATS): ${rows//$'\n'/ | }" >&2; return 1; }
  [ -n "$rows" ] || { log "no active seat with tick in $SEATS"; return 0; }
  master="$(master_seat)"; report_to="${FT_TICK_PM_REPORT_TO:-${master:-ft-v65-master}}"
  master_news_ok "$rows" "$master"; mok=$?
  while IFS=$'\t' read -r seat tick role; do
    case "$tick" in
      ft-master-tick)
        if [ "$mok" != 0 ]; then :   # ERROR 는 master_news_ok 가 기록(서명당 1회) — master news 0
        elif [ "$seat" != "$master" ]; then [ -f "$(stamp_of "$seat" mtwarn)" ] || { now > "$(stamp_of "$seat" mtwarn)"; log "WARN master-tick row $seat ≠ _master $master — skipped"; }
        else fire "$seat" master "$MASTER_INTERVAL" "$MASTER_MIN_GAP" "$MASTER_MSG"; goal "$seat"; fi;;
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
