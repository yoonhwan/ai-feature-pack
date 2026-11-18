#!/usr/bin/env bash
# ft-desk-tick.sh <desk 좌석>   (r1462 · desk 깨우는 턴의 도구 = 이 호출 1회 + 결정 필요 N)
#   desk 틱 1턴 = 이 스크립트 1회. 모델이 6항을 «직접 재지» 않는다 — 비모델이 재서 출력 ≤30줄 · 마지막 줄 `결정 필요: N`.
#   N=0 이면 그 턴의 도구는 «이 호출 1회» 뿐이다(추가 0) · N≥1 이면 그 항목만 도구 1회 더 = 총 2회. E3(틱 턴 도구 ≤1)는 N=0 경로에서만 닫힌다.
#   실행은 하지 않는다 — ⑥ 발송 하나만 이 스크립트가 한다.
#   ① ft-hil.sh --pending 중 이 desk 몫(.notify 가 desk 계보) ② launchctl print(stall-scan · keeper · board-news · r2102) state/last exit
#      + stall-scan 로그 마지막 ts ③ 팀장별 마지막 쪽지 시각(mailbox.log.jsonl · 20분+ 만 줄) ④ 받은편지함 감시(ft-inbox-watch) owner
#   ⑤ mbox.sh peek <desk> --rows 머리(seq·from·본문 첫 줄 ≤3 · «외» · recv 안내) ⑥ planner _master 에 [완료] 3줄(스크립트가 조립·발송)
#   ★우편함 경계★(r2187): 틱은 쪽지를 읽기만 한다(peek · recv 0 · 사본 파일 0) — desk 가 «결정 필요» 를 보고 직접 recv 한다.
#   peek 도 결속(root·현재 desk·planner _master·`_desk` 일치)을 «확인한 뒤» 에만 부른다. `_desk` 가 비었거나 불일치면 mbox 호출 0·송신 0
#   (이름 접두로 권한을 주지 않는다 · DA #273899).
#   ④ 감시 판정은 «이름» 이 아니라 argv 로 한다 — 실 watcher 의 argv 는 실행 파일 이름과 무관하게 «-u - <bin> <좌석>» 꼴이다
#   (이 Mac 실측: /opt/homebrew/…/Python.app/Contents/MacOS/Python -u - <bin> <좌석>).
#   한 항목이 실패하면 그 항목 «판정 불가 rc=N» 1줄 · 나머지는 계속 · 전체 rc1(조용한 0 금지 · docs/rules/no_silent_fallback.md).
#   항목당 7초 · 전체 FT_DESK_TICK_BUDGET(기본 25초) — 하위 명령은 모두 «남은 예산» 안에서만 돌고 남은 예산 0 이면 실행 0 · rc124.
#   r2137: ①~⑤ 는 BUDGET−7 초 안에서만 돈다 · 결속 확인과 ⑥ send 는 늘 7초(남은 예산이 7 미만이면 남은 만큼) — ⑥ 몫 보장.
#   ⑥ send rc≠0 이면 LOG 끝 400줄에서 from=이 좌석 · to=planner · 본문 «회차: <NOWISO>» 줄을 찾는다(늦은 확인) — 있으면 보냄.
#   «결정 필요» 바로 앞 1줄 = «초: ① a · … · ⑥ f · 전체 g/BUDGET»(돌지 않은 항목 = -).
#   출력 30줄(넘으면 접고 마지막 2줄 «초:» · «결정 필요» 는 지킨다). 전부 rc0 = 0 · usage = 2.
#   env(시험·이식용): FT_ROOT · FT_HIL_DIR · FT_DESK_TICK_MBOX · FT_DESK_TICK_HIL · FT_DESK_TICK_LAUNCHCTL · FT_DESK_TICK_GIT · FT_DESK_TICK_NEWS_STALE_H · FT_DESK_TICK_PS
#                     FT_DESK_TICK_STALL_LOG · FT_DESK_TICK_LOG · FT_DESK_TICK_NOW(epoch) · FT_DESK_TICK_UID · FT_DESK_TICK_MAX_LINES · FT_DESK_TICK_BUDGET · FT_DESK_TICK_HEAD
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
GIT="${FT_DESK_TICK_GIT:-git}"; LEDGER=design/teams/planner/PLAN-oppa-ledger.md   # r2102 NEWS 줄 = 원장 리포 git(fetch 0)
PS="${FT_DESK_TICK_PS:-ps}"
HILDIR="${FT_HIL_DIR:-/tmp}"
LOG="${FT_DESK_TICK_LOG:-$ROOT/.fable-team/comm/mailbox.log.jsonl}"
UIDN="${FT_DESK_TICK_UID:-$(id -u)}"
NOW="${FT_DESK_TICK_NOW:-$(date +%s)}"
MAXL="${FT_DESK_TICK_MAX_LINES:-30}"
BUDGET="${FT_DESK_TICK_BUDGET:-25}"
PLANNER_SEATS="$ROOT/.fable-team/seats-planner.json"
START="$(date +%s)"
iso() { date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
NOWISO="$(iso "$NOW")"
lmin() { date -r "$1" '+%Y-%m-%dT%H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%dT%H:%M'; }   # 지역 시각 분까지(news-last at 과 같은 꼴)

to() {  # to <초> <명령…> — 항목당 7초 상한(외부 호출 7초 룰). macOS 에 timeout 이 없어 perl alarm 으로 받친다.
  local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else perl -MTime::HiRes=alarm -e 'alarm shift; exec @ARGV' "$s" "$@" 2>/dev/null; fi
}
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }   # 밀리초 시계 — 초 내림으로 ⑥ 몫이 1초 깎이지 않게(r2137)
START_MS="$(ms)"; RESERVE=7   # ⑥ 몫 7초(T3)
XB() {  # XB <남길 초> <명령…> — 전체 예산에서 남길 몫을 뺀 예산과 항목 상한 7초 «둘 다» 지킨다. 남은 예산 0 이면 실행 0 · rc 124
  local r=$(( $1 * 1000 )) l; shift
  l=$(( BUDGET * 1000 - ( $(ms) - START_MS ) - r ))
  [ "$l" -ge 1 ] || return 124
  [ "$l" -le 7000 ] || l=7000
  to "$(printf '%d.%03d' $((l / 1000)) $((l % 1000)))" "$@"
}
X() { XB "$RESERVE" "$@"; }   # ①~⑤ = BUDGET−7 안
X6() { XB 0 "$@"; }           # 결속 · ⑥ = 전체 예산 안(DA 조건 ⓐ: 결속이 앞 항목 예산 소진으로 빠지지 않는다)
RAN=0; T0=0; SECS=""
tick() { RAN=0; T0="$(ms)"; }
tock() { if [ "$RAN" = 1 ]; then SECS="$SECS · $1 $(( ($(ms) - T0 + 500) / 1000 ))"; else SECS="$SECS · $1 -"; fi; }

OUT=("DESK-TICK $SEAT $NOWISO"); FAILS=0; DEC=0; OKN=0
HIL_N=0; HIL_DESK=0; MAIL_N=0; LAUNCH_BAD=0; STALE=0; WATCH="?"
o() { OUT+=("$*"); }
fail_line() { o "$1 판정 불가 rc=$2"; FAILS=$((FAILS+1)); DEC=$((DEC+1)); }
news_fail() { o "NEWS 판정 불가 — $1 rc=$([ "$2" -ne 0 ] && echo "$2" || echo 1)"; FAILS=$((FAILS+1)); DEC=$((DEC+1)); }   # r2102
budget_ok() { [ $(( BUDGET * 1000 - ( $(ms) - START_MS ) - $1 * 1000 )) -ge 1 ]; }   # budget_ok <남길 초> — XB 와 같은 예산 확인
item() {  # item <이름> [남길 초] — 전체 25초를 넘으면 그 항목은 실행하지 않고 판정 불가 1줄(6항 자리는 지킨다)
  if [ $(( $(date +%s) - START )) -gt 25 ]; then fail_line "$1" 124; return 1; fi
  if budget_ok "${2:-$RESERVE}"; then RAN=1; fi   # 예산 확인 통과 뒤에만 «돈 항목»(T4 · DA #322039)
  return 0
}

# ① 사람 결정 대기 중 «이 desk 몫»
tick
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
tock ①
# 머리 카운터(r2255) — planner-tick 폴더 없음 = 생략 1줄(rc 영향 0) · 있음 = TEAM-STATUS.md 1행 새로(① 실패면 «스크립트 ?» · ① 성공 = OKN 1)
HEADPY="${FT_DESK_TICK_HEAD:-$HERE/ft_team_status_line.py}"; hilarg="?"; [ "$OKN" -ge 1 ] && hilarg="$HIL_N"
if [ ! -d "$ROOT/.fable-team/state/planner-tick" ]; then o "머리 생략(폴더 없음)"
elif item 머리; then hout="$(X python3 "$HEADPY" --hil "$hilarg" --root "$ROOT" --now "$NOW" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then o "머리 $hout"; else fail_line 머리 "$rc"; fi
fi

# ② launchd 3종 state/last exit + stall-scan 로그 마지막 ts + 뉴스 마지막 발행(r2102)
tick
if item LAUNCH; then
  for spec in "stall-scan=com.byz.ft-stall-scan" "keeper=com.byz.ft2-keeper" "board-news=com.byz.ft-board-news"; do   # r2102 2.0 적재 라벨
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
  # r2102 뉴스 줄 — 마지막 발행(news-last.json · 못 읽으면 ?) · 골 진행 표 커밋 T · T 뒤 완성/ 추가 커밋 수 behind(fetch 0 · git 2회)
  #   behind = origin/main · origin/ops/main-base 에서 닿고 T 에서 안 닿고 커밋 시각 ≥ T(같은 초 포함) · age ≥ 상한 ∧ behind ≥ 1 = STALE(경보만)
  lp="$(X python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["at"][:16])' "$ROOT/.fable-team/state/board/news-last.json" 2>/dev/null)" || lp=""
  #   T = 절 안의 표 데이터 줄(`|` 로 시작)을 바꾼 마지막 커밋 — 다음 절 제목 · 설명 줄만 바뀐 커밋은 T 가 아니다(DA #316668 R2)
  #   r2180: T 를 정하면 awk 가 끝낸다(이력 끝까지 읽기 0) · 그 뒤 git SIGPIPE 141 은 실패 아님 = 성공 판정은 T 있음
  tl="$(X "$GIT" -C "$ROOT" log --format='C %H %ct' -L "/^## 골 진행$/,/^## /:$LEDGER" origin/main 2>/dev/null | awk '/^C [0-9a-f]+ [0-9]+$/{c=substr($0,3); next} /^[-+]\|/ && c!=""{t=c; exit} END{print t}')"; rc=$?
  if [ -z "$tl" ]; then news_fail 표 "$rc"; else
    tct="${tl##* }"   # 둘째 log = git 쪽에서 시각 ≥ T 로 먼저 거른다(전체 이력 읽기 0 · DA #316668 R1)
    bl="$(X "$GIT" -C "$ROOT" log --full-history --diff-filter=AR --name-only --format=@%ct --since="@$tct" origin/main origin/ops/main-base "^${tl%% *}" -- ':(glob)design/**/indices/완성/**' 2>/dev/null)"; rc=$?
    if [ "$rc" -ne 0 ]; then news_fail 완성 "$rc"; else
      OKN=$((OKN+1))
      nb="$(printf '%s\n' "$bl" | awk -v t="$tct" '/^@/{c=substr($0,2)+0; f=0; next} NF && !f && c>=t {n++; f=1} END{print n+0}')"
      nage=$(( (NOW - tct) / 3600 )); [ "$nage" -ge 0 ] || nage=0
      line="NEWS last_post=${lp:-?} table=$(lmin "$tct") age=${nage}h behind=$nb"
      if [ "$nage" -ge "${FT_DESK_TICK_NEWS_STALE_H:-3}" ] && [ "$nb" -ge 1 ]; then o "$line STALE"; DEC=$((DEC+1)); else o "$line"; fi
    fi
  fi
fi
tock ②

# ③ 팀장별 마지막 쪽지 시각 — 20분 넘은 팀만 줄을 낸다
tick
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
tock ③

# ④ 받은편지함 감시 owner — 실 watcher 의 argv 는 `python3 -u - <bin> <좌석>` 이다(이름 «ft-inbox-watch» 만으로는 안 잡힌다 · 반례③)
tick
if item 감시; then
  pout="$(X "$PS" -Ao pid=,command= 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line 감시 "$rc"; else
    OKN=$((OKN+1))
    hit="$(printf '%s\n' "$pout" | awk -v d="$DESKBASE" 'index($0,d)>0 && (index($0,"ft-inbox-watch")>0 || index($0," -u - ")>0)' | grep -v ft-desk-tick | head -1)"
    if [ -n "$hit" ]; then o "INBOX-WATCH $(printf '%s' "$hit" | awk '{print $1}') $DESKBASE 감시 중"; WATCH="감시 중"
    else o "INBOX-WATCH 없음(desk 감시 프로세스 0)"; WATCH="없음"; DEC=$((DEC+1)); fi
  fi
fi
tock ④

# 결속 확인 — 우편함을 «보기 전» 에 root·현재 desk·planner 가 이 좌석으로 묶였는지 본다(반례②). 실패면 mbox 호출 0 · 송신 0
BIND_OK=0; PLANNER=""
tick
if item 결속 0; then
  if [ ! -f "$MBOX" ]; then fail_line 결속 5; else
    bind="$(X6 python3 - "$PLANNER_SEATS" "$DESKBASE" <<'PY'
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

# ⑤ 내 쪽지 머리 — peek --rows 는 읽기만 한다(r2187 · 소비 0 · 사본 0). 판독 = mail_peek 한 함수
mail_peek() {  # 1줄째 = N · 그 뒤 머리 ≤3줄(seq 작은 순 · 100자 안) · rc≠0 = 판정 불가(peek rc 그대로 · 꼴 어긋남 65)
  local raw rc
  raw="$(X bash "$MBOX" peek "$SEAT" --rows 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  python3 - "$raw" <<'PY'
import json, re, sys
lines = sys.argv[1].split("\n")
m = re.fullmatch(r"pending=(\d+)( .*)?", lines[0])
if not m: sys.exit(65)
rows = [l for l in lines[1:] if l.strip()]
if len(rows) != int(m.group(1)): sys.exit(65)
try: rows = [json.loads(l) for l in rows]
except ValueError: sys.exit(65)
if not all(isinstance(r, dict) for r in rows): sys.exit(65)
print(len(rows))
for r in rows[:3]:
    first = (str(r.get("body") or "").splitlines() or [""])[0]
    print(("  #%s %s %s" % (r.get("seq"), r.get("from"), first))[:100])
PY
}
if [ "$BIND_OK" = 1 ] && item 쪽지; then
  mp="$(mail_peek)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line 쪽지 "$rc"; else
    OKN=$((OKN+1))
    MAIL_N="$(printf '%s\n' "$mp" | head -1)"
    o "쪽지 ${MAIL_N}건"
    if [ "$MAIL_N" -gt 0 ]; then
      while IFS= read -r l; do o "$l"; done <<< "$(printf '%s\n' "$mp" | sed 1d)"
      [ "$MAIL_N" -le 3 ] || o "  외 $((MAIL_N-3))통"
      o "쪽지 읽기: bash $MBOX recv $SEAT"
      DEC=$((DEC+1))
      if [ "$MAIL_N" -ge "${FT_MBOX_RING:-10}" ]; then   # ring 상한 = mbox_conf MAX_PER_TO · 넘치면 send 가 옛 쪽지를 버린다
        o "우편함 가득 — 다음 쪽지부터 옛 것 버림 · 지금 recv"; DEC=$((DEC+1))
      fi
    fi
  fi
fi
tock ⑤

# ⑥ planner _master 에 [완료] 3줄 — 본문은 스크립트가 조립한다(모델 출력이 아니다: 백틱·$() 가 들어갈 자리 0). 첫 줄 = [완료] 머리(반례④)
tick
if [ "$BIND_OK" = 1 ]; then
  if budget_ok 0; then RAN=1; fi
  body="$(printf '[완료] desk 틱 — HIL 대기 %d건(desk %d) · 쪽지 %d건 · launch 경고 %d건\n남은 일: 결정 필요 %d · 팀장 정체 %d건 · 감시 %s\n회차: %s · 6항 판정 불가 %d건 · 좌석 %s' \
    "$HIL_N" "$HIL_DESK" "$MAIL_N" "$LAUNCH_BAD" "$DEC" "$STALE" "$WATCH" "$NOWISO" "$FAILS" "$DESKBASE")"
  sout="$(X6 bash "$MBOX" send "$PLANNER" "$SEAT" "$body" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then OKN=$((OKN+1)); o "완료쪽지 → $PLANNER (3줄)"
  # 늦은 확인(T1 · T2) — send 가 큐에 넣은 뒤 마무리에서 끊겨도 이 회차 줄이 LOG 에 있으면 보냄. 전체 예산 안(X6)
  elif X6 python3 - "$LOG" "$SEAT" "$PLANNER" "회차: $NOWISO" <<'PY' >/dev/null 2>&1; then
import collections, json, sys
log, seat, to, mark = sys.argv[1:5]
with open(log, encoding="utf-8", errors="replace") as fh:
    tail = collections.deque(fh, maxlen=400)
for line in tail:
    try: r = json.loads(line)
    except ValueError: continue
    if isinstance(r, dict) and r.get("from") == seat and r.get("to") == to and mark in str(r.get("body") or ""): sys.exit(0)
sys.exit(1)
PY
    OKN=$((OKN+1)); o "완료쪽지 → $PLANNER (3줄 · 늦은 확인 rc=$rc)"
  else fail_line 완료쪽지 "$rc"; fi
fi
tock ⑥

o "초:${SECS# ·} · 전체 $(( ($(ms) - START_MS + 500) / 1000 ))/$BUDGET"
o "결정 필요: $DEC"
n="${#OUT[@]}"
if [ "$n" -gt "$MAXL" ]; then  # 상한 초과 = 앞을 접고 마지막 2줄(초 · 결정 필요)은 지킨다
  keep=$((MAXL-3)); cut=("${OUT[@]:0:$keep}")
  cut+=("… 외 $((n-keep-2))줄 접음" "${OUT[$((n-2))]}" "${OUT[$((n-1))]}")
  OUT=("${cut[@]}")
fi
printf '%s\n' "${OUT[@]}"
[ "$FAILS" -eq 0 ] || exit 1
exit 0
