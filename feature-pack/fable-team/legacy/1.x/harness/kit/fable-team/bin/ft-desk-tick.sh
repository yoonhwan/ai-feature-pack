#!/usr/bin/env bash
# ft-desk-tick.sh <desk 좌석>   (r1462 · desk 깨우는 턴의 도구 = 이 호출 1회 + 결정 필요 N)
#   desk 틱 1턴 = 이 스크립트 1회. 모델이 6항을 «직접 재지» 않는다 — 비모델이 재서 출력 ≤30줄 · 마지막 줄 `결정 필요: N`.
#   N=0 이면 그 턴의 도구는 «이 호출 1회» 뿐이다(추가 0) · N≥1 이면 그 항목만 도구 1회 더 = 총 2회. E3(틱 턴 도구 ≤1)는 N=0 경로에서만 닫힌다.
#   실행은 하지 않는다 — ⑥ 발송 하나만 이 스크립트가 한다.
#   ① ft-hil.sh --pending 중 이 desk 몫(.notify 가 desk 계보) ② launchctl print(stall-scan · ft-tick · news 2종) state/last exit
#      + stall-scan 로그 마지막 ts ③ 팀장별 마지막 쪽지 시각(mailbox.log.jsonl · 20분+ 만 줄) ④ 받은편지함 감시(ft-inbox-watch) owner
#   ⑤ mbox.sh recv <desk> 머리(seq·from·본문 60자 · 전문은 상태 폴더 파일) ⑥ planner _master 에 [완료] 3줄(스크립트가 조립·발송)
#   ★소비 경계★: recv 는 우편함을 소비한다 — 결속(root·현재 desk·planner _master·`_desk` 일치)을 «확인한 뒤» 에만 부르고,
#   전문 사본 저장까지 실패하면 완료를 보내지 않는다(판정 불가 1줄 · rc1). `_desk` 가 비었거나 불일치면 recv 0·송신 0
#   (이름 접두로 소비 권한을 주지 않는다 · DA #273899).
#   ④ 감시 판정은 «이름» 이 아니라 argv 로 한다 — 실 watcher 의 argv 는 실행 파일 이름과 무관하게 «-u - <bin> <좌석>» 꼴이다
#   (이 Mac 실측: /opt/homebrew/…/Python.app/Contents/MacOS/Python -u - <bin> <좌석>).
#   한 항목이 실패하면 그 항목 «판정 불가 rc=N» 1줄 · 나머지는 계속 · 전체 rc1(조용한 0 금지 · docs/rules/no_silent_fallback.md).
#   항목당 7초 · 전체 FT_DESK_TICK_BUDGET(기본 25초) — 하위 명령은 모두 «남은 예산» 안에서만 돌고 남은 예산 0 이면 실행 0 · rc124.
#   출력 30줄(넘으면 접고 마지막 줄은 지킨다). 전부 rc0 = 0 · usage = 2.
#   env(시험·이식용): FT_ROOT · FT_HIL_DIR · FT_DESK_TICK_MBOX · FT_DESK_TICK_HIL · FT_DESK_TICK_LAUNCHCTL · FT_DESK_TICK_PS
#                     FT_DESK_TICK_STALL_LOG · FT_DESK_TICK_LOG · FT_DESK_TICK_NOW(epoch) · FT_DESK_TICK_STATE_DIR · FT_DESK_TICK_UID · FT_DESK_TICK_MAX_LINES · FT_DESK_TICK_BUDGET
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
usage() { echo "usage: ft-desk-tick.sh <desk 좌석>" >&2; exit 2; }
[ $# -ge 1 ] || usage
SEAT="$1"; DESKBASE="${SEAT%%#*}"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="${FT_ROOT:-$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || ROOT="$WT"
MBOX="${FT_DESK_TICK_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
HIL="${FT_DESK_TICK_HIL:-$HERE/ft-hil.sh}"
LAUNCHCTL="${FT_DESK_TICK_LAUNCHCTL:-launchctl}"
PS="${FT_DESK_TICK_PS:-ps}"
HILDIR="${FT_HIL_DIR:-/tmp}"
LOG="${FT_DESK_TICK_LOG:-$ROOT/.fable-team/comm/mailbox.log.jsonl}"
UIDN="${FT_DESK_TICK_UID:-$(id -u)}"
NOW="${FT_DESK_TICK_NOW:-$(date +%s)}"
STATE="${FT_DESK_TICK_STATE_DIR:-${TMPDIR:-/tmp}/ft-desk-tick}"
MAXL="${FT_DESK_TICK_MAX_LINES:-30}"
BUDGET="${FT_DESK_TICK_BUDGET:-25}"
PLANNER_SEATS="$ROOT/.fable-team/seats-planner.json"
START="$(date +%s)"
iso() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
NOWISO="$(iso "$NOW")"

to() {  # to <초> <명령…> — 항목당 7초 상한(외부 호출 7초 룰). macOS 에 timeout 이 없어 perl alarm 으로 받친다.
  local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$s" "$@" 2>/dev/null; fi
}
left() { echo $(( BUDGET - ( $(date +%s) - START ) )); }
X() {  # X <명령…> — 전체 예산(BUDGET 초)과 항목 상한 7초 «둘 다» 지킨다. 남은 예산 0 이면 실행 0 · rc 124
  local l t; l="$(left)"
  [ "$l" -ge 1 ] || return 124
  t=$(( l > 7 ? 7 : l ))
  to "$t" "$@"
}

OUT=("DESK-TICK $SEAT $NOWISO"); FAILS=0; DEC=0; OKN=0
HIL_N=0; HIL_DESK=0; MAIL_N=0; LAUNCH_BAD=0; STALE=0; WATCH="?"
o() { OUT+=("$*"); }
fail_line() { o "$1 판정 불가 rc=$2"; FAILS=$((FAILS+1)); DEC=$((DEC+1)); }
item() {  # item <이름> — 전체 25초를 넘으면 그 항목은 실행하지 않고 판정 불가 1줄(6항 자리는 지킨다)
  if [ $(( $(date +%s) - START )) -gt 25 ]; then fail_line "$1" 124; return 1; fi
  return 0
}

# ① 사람 결정 대기 중 «이 desk 몫»
if item HIL; then
  hil_out="$(X bash "$HIL" --pending --each 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line HIL "$rc"; else
    OKN=$((OKN+1)); dlines=""; dcount=0
    while read -r h min; do
      [ -n "${h:-}" ] || continue
      HIL_N=$((HIL_N+1))
      if grep -qsF "$DESKBASE" "$HILDIR/$h.notify" 2>/dev/null; then
        HIL_DESK=$((HIL_DESK+1))
        if [ "$dcount" -lt 3 ]; then dcount=$((dcount+1)); dlines="$dlines  $h ${min:-?}분"$'\n'; fi
      fi
    done <<< "$hil_out"
    o "HIL 대기 ${HIL_N}건 · desk ${HIL_DESK}건"
    if [ -n "$dlines" ]; then while IFS= read -r dl; do [ -n "$dl" ] && o "$dl"; done <<< "$dlines"; fi
    if [ "$HIL_DESK" -gt 0 ]; then DEC=$((DEC+1)); fi
  fi
fi

# ② launchd 4종 state/last exit + stall-scan 로그 마지막 ts
if item LAUNCH; then
  for spec in "stall-scan=com.byz.ft-stall-scan" "tick=com.byz.ft-tick" "news-planner=com.byz.ft-news-planner" "news-desk=com.byz.ft-news-desk"; do
    nm="${spec%%=*}"; label="${spec#*=}"
    lout="$(X "$LAUNCHCTL" print "gui/$UIDN/$label" 2>&1)"; rc=$?
    if [ "$rc" -ne 0 ]; then fail_line "LAUNCH $nm" "$rc"; LAUNCH_BAD=$((LAUNCH_BAD+1)); continue; fi
    OKN=$((OKN+1))
    st="$(printf '%s\n' "$lout" | sed -n 's/^[[:space:]]*state = //p' | head -1)"
    ex="$(printf '%s\n' "$lout" | sed -n 's/^[[:space:]]*last exit code = //p' | head -1)"
    o "LAUNCH $nm state=${st:-?} last_exit=${ex:-?}"
    exv="${ex:-0}"; case "$exv" in ""|"(never exited)") exv=0;; esac   # KeepAlive 좌석은 «아직 종료한 적 없음» 이 정상이다
    [ "$exv" = 0 ] || { DEC=$((DEC+1)); LAUNCH_BAD=$((LAUNCH_BAD+1)); }
  done
  slog="${FT_DESK_TICK_STALL_LOG:-}"
  if [ -z "$slog" ]; then
    for c in /tmp/byz-ft-stall-scan.log "$ROOT/.fable-team/state/stall-scan.log"; do [ -f "$c" ] && { slog="$c"; break; }; done
  fi
  if [ -z "$slog" ] || [ ! -f "$slog" ]; then fail_line "STALL-SCAN 로그" 2; else
    tse="$(tail -n 50 "$slog" | tr ' ' '\n' | sed -n 's/^ts=//p' | sort -n | tail -1)"
    if [ -z "${tse:-}" ]; then fail_line "STALL-SCAN 로그" 3; else
      OKN=$((OKN+1)); age=$(( (NOW - tse) / 60 )); [ "$age" -ge 0 ] || age=0
      o "STALL-SCAN 로그 $(iso "$tse") (${age}분 전)"
      [ "$age" -lt 10 ] || DEC=$((DEC+1))
    fi
  fi
fi

# ③ 팀장별 마지막 쪽지 시각 — 20분 넘은 팀만 줄을 낸다
if item 팀장; then
  stale="$(X python3 - "$ROOT/.fable-team" "$LOG" "$NOW" <<'PY' 2>&1
import datetime, glob, json, os, sys
d, log, now = sys.argv[1], sys.argv[2], int(sys.argv[3])
def ep(s):
    s = str(s or "").replace("Z", "+00:00")
    try: return int(datetime.datetime.fromisoformat(s).timestamp())
    except Exception: return None
bases = set()
for f in sorted(glob.glob(os.path.join(d, "seats-*.json"))):
    try: cfg = json.load(open(f, encoding="utf-8"))
    except Exception: continue
    if isinstance(cfg, dict) and str(cfg.get("_master") or "").strip():
        bases.add(str(cfg["_master"]).strip().split("#")[0])
if not bases: sys.exit(4)
try: fh = open(log, encoding="utf-8", errors="replace")
except OSError: sys.exit(3)
last = {}
with fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try: r = json.loads(line)
        except ValueError: continue
        if not isinstance(r, dict): continue
        b = str(r.get("from") or "").split("#")[0]
        if b not in bases: continue
        t = ep(r.get("ts"))
        if t and (b not in last or t > last[b]): last[b] = t
rows = sorted(((b, (now - t) // 60) for b, t in last.items() if (now - t) // 60 >= 20), key=lambda x: -x[1])
if rows: print("팀장 정체 %d팀(20분+)" % len(rows))
for b, m in rows[:3]: print("  %s 마지막 쪽지 %d분 전" % (b, m))
if len(rows) > 3: print("  … 외 %d팀" % (len(rows) - 3))
sys.exit(0)
PY
)"; rc=$?
  if [ "$rc" -ge 3 ]; then fail_line 팀장 "$rc"
  else
    OKN=$((OKN+1)); STALE="$(printf '%s\n' "$stale" | sed -n 's/^팀장 정체 \([0-9][0-9]*\)팀(20분+)$/\1/p' | head -1)"; STALE="${STALE:-0}"
    [ -n "$stale" ] && o "$stale"; DEC=$((DEC+STALE))
  fi
fi

# ④ 받은편지함 감시 owner — 실 watcher 의 argv 는 `python3 -u - <bin> <좌석>` 이다(이름 «ft-inbox-watch» 만으로는 안 잡힌다 · 반례③)
if item 감시; then
  pout="$(X "$PS" -Ao pid=,command= 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line 감시 "$rc"; else
    OKN=$((OKN+1))
    hit="$(printf '%s\n' "$pout" | awk -v d="$DESKBASE" 'index($0,d)>0 && (index($0,"ft-inbox-watch")>0 || index($0," -u - ")>0)' | grep -v ft-desk-tick | head -1)"
    if [ -n "$hit" ]; then o "INBOX-WATCH $(printf '%s' "$hit" | awk '{print $1}') $DESKBASE 감시 중"; WATCH="감시 중"
    else o "INBOX-WATCH 없음(desk 감시 프로세스 0)"; WATCH="없음"; DEC=$((DEC+1)); fi
  fi
fi

# 결속 확인 — 우편함을 «소비하기 전» 에 root·현재 desk·planner 가 이 좌석으로 묶였는지 본다(반례②). 실패면 recv 0 · 송신 0
BIND_OK=0; PLANNER=""; SAVE_OK=1
if item 결속; then
  if [ ! -f "$MBOX" ]; then fail_line 결속 5; else
    bind="$(X python3 - "$PLANNER_SEATS" "$DESKBASE" <<'PY'
import json, sys
try: cfg = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception: sys.exit(6)
if not isinstance(cfg, dict): sys.exit(6)
m = str(cfg.get("_master") or "").strip(); d = str(cfg.get("_desk") or "").strip()
if not m: sys.exit(7)
if not d: sys.exit(8)                                     # _desk 빈칸 = 이 좌석에 «소비 권한» 을 줄 근거가 없다(이름 접두 fallback 금지)
if d.split("#")[0] != sys.argv[2]: sys.exit(9)             # 불일치도 같은 이유로 권한 없음
print(m)
PY
)"; rc=$?
    case "$rc" in
      0) PLANNER="$(printf '%s\n' "$bind" | head -1)"; BIND_OK=1; OKN=$((OKN+1)); o "결속 OK planner ${PLANNER}";;
      *) fail_line 결속 "$rc";;
    esac
  fi
fi

# ⑤ 내 쪽지 머리 — recv 는 소비다. 전문은 상태 폴더에 남겨 잃지 않는다. 저장까지 실패하면 완료송신 0(반례②)
if [ "$BIND_OK" = 1 ] && item 쪽지; then
  recv_out="$(X bash "$MBOX" recv "$SEAT" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line 쪽지 "$rc"; else
    OKN=$((OKN+1))
    MAIL_N="$(printf '%s\n' "$recv_out" | awk '/^READ \[/{c++} END{print c+0}')"
    o "쪽지 ${MAIL_N}건"
    if [ "$MAIL_N" -gt 0 ]; then
      heads="$(printf '%s\n' "$recv_out" | awk '/^READ \[/{print}' | head -3)"
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        o "  $(printf '%s' "$l" | sed -E 's/^READ \[([^]]*)->[^]]*\] #([0-9]+) [^ ]+ (.*)$/#\2 \1 \3/' | cut -c1-100)"
      done <<< "$heads"
      if mkdir -p "$STATE" 2>/dev/null && printf '%s\n' "$recv_out" > "$STATE/$SEAT-recv-$NOW.txt" 2>/dev/null; then
        o "쪽지 전문 $STATE/$SEAT-recv-$NOW.txt"
      else
        o "쪽지 전문 저장 실패 $STATE (완료송신 0)"; fail_line "쪽지 저장" 1; SAVE_OK=0
      fi
      DEC=$((DEC+1))
    fi
  fi
fi

# ⑥ planner _master 에 [완료] 3줄 — 본문은 스크립트가 조립한다(모델 출력이 아니다: 백틱·$() 가 들어갈 자리 0). 첫 줄 = [완료] 머리(반례④)
if [ "$BIND_OK" = 1 ] && [ "$SAVE_OK" = 1 ]; then
  body="$(printf '[완료] desk 틱 — HIL 대기 %d건(desk %d) · 쪽지 %d건 · launch 경고 %d건\n남은 일: 결정 필요 %d · 팀장 정체 %d건 · 감시 %s\n회차: %s · 6항 판정 불가 %d건 · 좌석 %s' \
    "$HIL_N" "$HIL_DESK" "$MAIL_N" "$LAUNCH_BAD" "$DEC" "$STALE" "$WATCH" "$NOWISO" "$FAILS" "$DESKBASE")"
  sout="$(X bash "$MBOX" send "$PLANNER" "$SEAT" "$body" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line 완료쪽지 "$rc"; else OKN=$((OKN+1)); o "완료쪽지 → $PLANNER (3줄)"; fi
fi

o "결정 필요: $DEC"
n="${#OUT[@]}"
if [ "$n" -gt "$MAXL" ]; then  # 상한 초과 = 앞을 접고 마지막 줄(결정 필요)은 지킨다
  keep=$((MAXL-2)); cut=("${OUT[@]:0:$keep}")
  cut+=("… 외 $((n-keep-1))줄 접음" "${OUT[$((n-1))]}")
  OUT=("${cut[@]}")
fi
printf '%s\n' "${OUT[@]}"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
