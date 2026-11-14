#!/usr/bin/env bash
# ft-lead-tick.sh <팀장 좌석>   (r1472 · 팀장 «사건 턴»(쪽지 doorbell 로 깬 턴)의 도구 = 이 호출 1회 + 결정 필요 N)
#   비모델이 재고 모델은 «결정 필요 N» 항목만 본다. 출력 ≤30줄 · 마지막 줄 `결정 필요: N`. 주기 호출 0(심박 아님).
#   ① 결속: 팀 = 좌석 둘째 토큰 → seats-<팀>.json `_master` == 좌석 (아니면 recv 0 · send 0 · «결속 불일치» · rc1)
#   ② 카드 수 = git ls-tree <REF> <_cards>/{대기,진행} (*.md) · REF = keeper 순서 origin/ops/main-base → origin/main 중 <_cards> 트리가 있는 첫 ref(r1472b)
#   ③ 같은 팀 nano·da 행 × ft-seat-status(tmux·jsonl) → 20분+ 유휴만 줄
#   ④ 열린 h(ft-hil.sh --pending · .notify 에 팀장 이름) ⑤ mbox recv 머리(seq·from·60자 · 전문은 상태 폴더)
#   ⑥ [정리] 4줄(첫 줄 `카드 대기 N · 진행 N · 유휴 N · 다음 수 …` → `골좌표: <N> — <골 앞 12자>` → [정리] → 회차)을 스크립트가 조립해 보고처로 send
#   송신 규칙: 보고처 = `_report_to` · 없으면 planner `_master` · 자기·같은 좌석 = send 0 + «자기 송신 차단» rc1
#             N=0 ∧ ②~④ 가 <상태>/<좌석>.last 와 같음 = send 0 (.last 에 «조용함 ts»)
#   N = 받은 쪽지 중 [HIL]·[결정]·[긴급] 머리 + 20분+ 유휴 좌석 + 이 팀 열린 h + 판정 불가 항목.
#   한 항목 실패 = «<항목> 판정 불가 rc=N» 1줄 · 나머지 계속 · 전체 rc1 (docs/rules/no_silent_fallback.md)
#   항목당 7초 · 전체 FT_LEAD_TICK_BUDGET(기본 25초) — 남은 예산 0 이면 실행 0 · 전체 rc124. usage = 2.
#   env(시험·이식용): FT_ROOT · FT_HIL_DIR · FT_LEAD_TICK_MBOX · FT_LEAD_TICK_HIL · FT_LEAD_TICK_SEAT_STATUS · FT_LEAD_TICK_CARDS_REF(있으면 그 ref 하나) · FT_GOAL_A6_MD
#                     FT_LEAD_TICK_NOW(epoch) · FT_LEAD_TICK_STATE_DIR · FT_LEAD_TICK_IDLE_SEC(1200) · FT_LEAD_TICK_MAX_LINES · FT_LEAD_TICK_BUDGET
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ $# -ge 1 ] || { echo "usage: ft-lead-tick.sh <팀장 좌석>" >&2; exit 2; }
SEAT="$1"; BASE="${SEAT%%#*}"; TEAM="${SEAT#*-}"; TEAM="${TEAM%%-*}"; PREFIX="${SEAT%%-*}-$TEAM-"
WT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ROOT="${FT_ROOT:-$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$ROOT" ] || ROOT="$WT"
MBOX="${FT_LEAD_TICK_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
HIL="${FT_LEAD_TICK_HIL:-$HERE/ft-hil.sh}"
STATUS="${FT_LEAD_TICK_SEAT_STATUS:-$HERE/ft-seat-status.sh}"
TMUX_BIN="${FT_LEAD_TICK_TMUX:-tmux}"   # TMUX(tmux 가 export 한 소켓) 는 대입·unset 0 — 자식 tmux·ft-seat-status 가 원래 값을 받는다(r1472b)
REFS="${FT_LEAD_TICK_CARDS_REF:-origin/ops/main-base origin/main}"   # keeper(keeper_land.py REFS)와 같은 순서
HILDIR="${FT_HIL_DIR:-/tmp}"
NOW="${FT_LEAD_TICK_NOW:-$(date +%s)}"
STATE="${FT_LEAD_TICK_STATE_DIR:-$ROOT/.fable-team/state/lead-tick}"
IDLE_SEC="${FT_LEAD_TICK_IDLE_SEC:-1200}"
MAXL="${FT_LEAD_TICK_MAX_LINES:-30}"
BUDGET="${FT_LEAD_TICK_BUDGET:-25}"
ROSTER="$ROOT/.fable-team/seats-$TEAM.json"
START="$(date +%s)"
NOWISO="$(date -u -r "$NOW" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$NOW" '+%Y-%m-%dT%H:%M:%SZ')"

to() {  # to <초> <명령…> — 항목당 상한(외부 호출 7초 룰)
  local s="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$s" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$s" "$@"; fi
}
left() { echo $(( BUDGET - ( $(date +%s) - START ) )); }
X() {  # 전체 예산과 항목 7초 둘 다 · 남은 예산 0 = 실행 0 · rc124
  local l t; l="$(left)"; [ "$l" -ge 1 ] || return 124
  t=$(( l > 7 ? 7 : l )); to "$t" "$@"
}
OUT=("LEAD-TICK $SEAT $NOWISO"); FAILS=0; DEC=0; BOUT=0
o() { OUT+=("$*"); }
fail_line() { o "$1 판정 불가 rc=$2"; FAILS=$((FAILS+1)); DEC=$((DEC+1)); case "$2" in 124|142) BOUT=1;; esac; }
clean() { printf '%s' "$1" | tr -d '`' | sed 's/\$(/(/g'; }   # 쪽지 본문은 미검증 입력 — 보낼 본문에 백틱·$( 0

# ① 결속 — 우편함을 소비하기 전에 확인한다. 실패면 recv 0 · send 0
BIND_OK=0; REPORT=""; CARDS=""
bind="$(X python3 - "$ROSTER" "$SEAT" "$ROOT/.fable-team/seats-planner.json" "$TEAM" <<'PY'
import json, sys
try: d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception: sys.exit(6)
if not isinstance(d, dict): sys.exit(6)
if str(d.get("_master") or "").strip() != sys.argv[2]: sys.exit(9)
rep = str(d.get("_report_to") or "").strip()
if not rep:
    try: rep = str(json.load(open(sys.argv[3], encoding="utf-8")).get("_master") or "").strip()
    except Exception: rep = ""
t = sys.argv[4]
cards = str(d.get("_cards") or "").strip() or ("design/harness/indices" if t == "harness" else "design/teams/%s/indices" % t)
print(rep or "-"); print(cards)
PY
)"; rc=$?
case "$rc" in
  0) REPORT="$(printf '%s\n' "$bind" | sed -n 1p)"; CARDS="$(printf '%s\n' "$bind" | sed -n 2p)"; BIND_OK=1
     o "결속 OK 팀 $TEAM · 보고처 $REPORT";;
  9) o "결속 불일치 판정 불가 rc=9 ($ROSTER _master ≠ $SEAT · recv 0 · send 0)"; FAILS=$((FAILS+1));;
  *) fail_line "결속($ROSTER)" "$rc";;
esac
if [ "$BIND_OK" != 1 ]; then o "결정 필요: $((DEC+1))"; printf '%s\n' "${OUT[@]}"; [ "$BOUT" = 1 ] && exit 124; exit 1; fi

# ② 카드 수
WAIT="?"; DOING="?"; REF=""; FOUND=0; rc=1
for r in $REFS; do X git -C "$ROOT" cat-file -e "$r:$CARDS" 2>/dev/null; rc=$?; [ "$rc" -eq 0 ] && { REF="$r"; FOUND=1; break; }; done
#   후보 ref 어디에도 카드 트리 없음 = ls-tree 0 · 판정 불가(DA R1 · 없는 path 의 ls-tree 는 rc0 빈 출력이라 카드 0 으로 숨는다)
if [ "$FOUND" != 1 ]; then fail_line "카드($(echo $REFS):$CARDS) 트리 없음" "$rc"
elif lt="$(X git -C "$ROOT" ls-tree -r --name-only "$REF" -- "$CARDS/대기/" "$CARDS/진행/" 2>&1)"; rc=$?; [ "$rc" -ne 0 ]; then fail_line "카드($REF:$CARDS)" "$rc"; else
  WAIT="$(printf '%s\n' "$lt" | grep -c "^$CARDS/대기/[^/]*\.md$")"; DOING="$(printf '%s\n' "$lt" | grep -c "^$CARDS/진행/[^/]*\.md$")"
  o "카드 대기 $WAIT · 진행 $DOING ($REF)"
fi

# ③ 나노·DA 좌석 상태 — 명부 행 × ft-seat-status(tmux 생존 · jsonl 나이)
#   ft-seat-status 의 seats() 는 tmux 실패를 2>/dev/null 로 삼켜 rc0 [] 를 낸다(DA #304580 B2) → 같은 tmux 를 먼저 확인한다(하드 룰 20)
IDLE="미상"; IDLE_HEAD=""
#   리드가 tmux list-sessions 1회(7초 · 재시도 0): «no server running» = 살아 있는 좌석 0 정상 · 그 밖 rc≠0 = 판정 불가
#   status 에 명부 좌석 0 인데 tmux 목록에 명부 nano·da 가 있으면 모순 = 판정 불가(은폐 2중 막기 · 보정 R1)
SNAME="좌석 상태(tmux)"; TL="$(X $TMUX_BIN list-sessions -F '#{session_name}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$TL" | grep -q 'no server running'; then TL=""; rc=0; fi
if [ "$rc" -eq 0 ]; then SNAME="좌석 상태"; st="$(cd "$ROOT" && FT_SEATS_JSON="$ROSTER" X bash "$STATUS" list "^$PREFIX" --json 2>/dev/null)"; rc=$?; fi
if [ "$rc" -ne 0 ]; then fail_line "$SNAME" "$rc"; else
  sl="$(printf '%s' "$st" | TL="$TL" python3 -c '
import os
import json, sys
roster, idle_sec = json.load(open(sys.argv[1], encoding="utf-8")), int(sys.argv[2])
want = {k: v.get("role") for k, v in roster.items() if not k.startswith("_") and isinstance(v, dict)
        and v.get("role") in ("nano", "da") and not v.get("_replaced_by")}
try: rows = json.load(sys.stdin)
except ValueError: sys.exit(3)
live = {"nano": 0, "da": 0}; idle = []
for r in rows if isinstance(rows, list) else []:
    s = r.get("seat")
    if s not in want or r.get("pane") in ("NOSEAT", None): continue
    live[want[s]] += 1
    a = r.get("jsonl_age")
    if r.get("pane") == "IDLE" and isinstance(a, int) and a >= idle_sec: idle.append((a, s))
tl = [s for s in os.environ.get("TL", "").splitlines() if s in want]
if live["nano"] + live["da"] == 0 and tl:
    print("좌석 상태(모순: tmux 명부 좌석 %d · status 0)" % len(tl)); sys.exit(5)
idle.sort(reverse=True)
print("좌석 nano %d · da %d · 유휴(20분+) %d" % (live["nano"], live["da"], len(idle)))
for a, s in idle[:3]: print("  유휴 %s %d분" % (s, a // 60))
' "$ROSTER" "$IDLE_SEC")"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line "$(printf '%s\n' "$sl" | grep -m1 '^좌석 상태(모순' || echo 좌석 상태)" "$rc"; else
    while IFS= read -r l; do [ -n "$l" ] && o "$l"; done <<< "$sl"
    IDLE="$(printf '%s\n' "$sl" | sed -n '1s/.*유휴(20분+) \([0-9]*\)$/\1/p')"; DEC=$((DEC+IDLE))
    IDLE_HEAD="$(printf '%s\n' "$sl" | sed -n '2s/^  //p')"
  fi
fi

# ④ 열린 h — .notify 에 팀장 이름이 있는 것만 이 팀 몫
HTEAM="?"; H_HEAD=""
ho="$(X bash "$HIL" --pending --each 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then fail_line "열린 h" "$rc"; else
  HTEAM=0; HALL=0
  while read -r h min; do
    [ -n "${h:-}" ] || continue; HALL=$((HALL+1))
    if grep -qsF "$BASE" "$HILDIR/$h.notify"; then HTEAM=$((HTEAM+1)); [ -n "$H_HEAD" ] || H_HEAD="열린 $h ${min:-?}분"; fi
  done <<< "$ho"
  o "열린 h ${HALL}건 · 이 팀 ${HTEAM}건${H_HEAD:+ ($H_HEAD)}"; DEC=$((DEC+HTEAM))
fi

# ⑤ 받은 쪽지 머리 — recv 는 소비다. 전문은 상태 폴더에. 저장 실패 = 송신 0
MAIL_N=0; MAIL_HEAD=""; SAVE_OK=1
ro="$(X bash "$MBOX" recv "$SEAT" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ]; then fail_line 쪽지 "$rc"; else
  MAIL_N="$(printf '%s\n' "$ro" | grep -c '^READ \[')"
  # 결정 머리는 «전부» 센다 — 표시 3줄 상한이 집계를 자르지 않는다(DA #304580 B1). 표시 = 결정 머리 먼저 · 합 3줄
  dec_l="$(printf '%s\n' "$ro" | grep -E '^READ \[[^]]*\] #[0-9]+[^—]*— \[(HIL|결정|긴급)\]')"
  MD="$(printf '%s' "$dec_l" | grep -c '^READ \[')"
  o "쪽지 ${MAIL_N}건 · 결정 머리 ${MD}건"
  hd() { printf '%s' "$1" | sed -E 's/^READ \[([^]]*)->[^]]*\] #([0-9]+)[^—]*— (.*)$/#\2 \1 \3/' | cut -c1-100; }
  [ "$MD" -gt 0 ] && MAIL_HEAD="$(hd "$(printf '%s\n' "$dec_l" | head -1)" | cut -c1-60)"
  while IFS= read -r l; do [ -n "$l" ] && o "  $(hd "$l")"; done <<< "$( { printf '%s\n' "$dec_l"; printf '%s\n' "$ro" | grep '^READ \[' | grep -vxF -f <(printf '%s\n' "$dec_l" | grep .) ; } | grep . | head -3)"
  if [ "$MAIL_N" -gt 0 ]; then
    if mkdir -p "$STATE" 2>/dev/null && printf '%s\n' "$ro" > "$STATE/$SEAT-recv-$NOW.txt" 2>/dev/null; then o "쪽지 전문 $STATE/$SEAT-recv-$NOW.txt"
    else fail_line "쪽지 저장" 1; SAVE_OK=0; fi
  fi
  DEC=$((DEC+MD))
fi

# ⑥' 골좌표 — 정본 골 표(ft_goal_table load_canon·parse_rows)에서 팀 칸 첫 낱말 = 이 팀인 첫 행 · 꼴 = check --coord-only 가 받는 꼴(골 앞 12자)
#   행 0·읽기 실패 = 골좌표 줄 0 + 판정 불가(지어내기 0 · 하드 룰 20)
GOAL_LINE="$(cd "$ROOT" && X python3 - "$HERE" "$TEAM" <<'PY'
import re, sys
sys.path.insert(0, sys.argv[1])
try:
    from ft_goal_table import _norm, load_canon, parse_rows
    rows = parse_rows(load_canon()[0])
except Exception as e:
    print(str(e)[:120], file=sys.stderr); sys.exit(6)
for i, r in enumerate(rows, 1):
    if re.split(r"[\s(·]", r[1].strip(), maxsplit=1)[0] == sys.argv[2]:
        print("골좌표: %d — %s" % (i, _norm(r[0])[:12].rstrip())); sys.exit(0)
sys.exit(4)
PY
)"; rc=$?
[ "$rc" -eq 0 ] || { GOAL_LINE=""; fail_line 골좌표 "$rc"; }
NL=$'\n'

# ⑥ [정리] 4줄 — 송신 규칙(보고처 · 자기 0 · N=0 무변화 0)
SIG="대기=$WAIT 진행=$DOING 유휴=$IDLE h=$HTEAM"; LAST="$STATE/$SEAT.last"
NEXT="${MAIL_HEAD:-${IDLE_HEAD:-${H_HEAD:-없음}}}"
if [ "$BOUT" = 1 ] || [ "$(left)" -lt 1 ]; then BOUT=1; o "예산 소진 — [정리] 송신 0"
elif [ "$SAVE_OK" != 1 ]; then o "쪽지 전문 저장 실패 — [정리] 송신 0"
elif [ "$REPORT" = "-" ]; then fail_line "보고처(_report_to·planner _master 없음)" 7
elif [ "${REPORT%%#*}" = "$BASE" ]; then o "자기 송신 차단 판정 불가 rc=1 (보고처 $REPORT = 자기 좌석 · send 0)"; FAILS=$((FAILS+1))
elif [ "$DEC" -eq 0 ] && [ -f "$LAST" ] && [ "$(sed -n 1p "$LAST")" = "$SIG" ]; then
  printf '%s\n조용함 %s\n' "$SIG" "$NOWISO" > "$LAST" 2>/dev/null || fail_line ".last 기록" 1
  o "조용함 — 결정 0 · 직전과 같음 · [정리] 송신 0"
else
  body="$(printf '카드 대기 %s · 진행 %s · 유휴 %s · 다음 수 %s\n%s[정리] 리드 사건 턴 %s · 결정 필요 %d · 열린 h %s · 쪽지 %d\n회차 %s · 판정 불가 %d' \
    "$WAIT" "$DOING" "$IDLE" "$(clean "$NEXT")" "${GOAL_LINE:+$GOAL_LINE$NL}" "$BASE" "$DEC" "$HTEAM" "$MAIL_N" "$NOWISO" "$FAILS")"
  so="$(X bash "$MBOX" send "$REPORT" "$SEAT" "$body" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then fail_line "[정리] 송신" "$rc"; else
    o "[정리] → $REPORT ($(printf '%s\n' "$body" | wc -l | tr -d ' ')줄)"
    { mkdir -p "$STATE" && printf '%s\n보냄 %s\n' "$SIG" "$NOWISO" > "$LAST"; } 2>/dev/null || fail_line ".last 기록" 1
  fi
fi

o "결정 필요: $DEC"
n="${#OUT[@]}"
if [ "$n" -gt "$MAXL" ]; then keep=$((MAXL-2)); OUT=("${OUT[@]:0:$keep}" "… 외 $((n-keep-1))줄 접음" "${OUT[$((n-1))]}"); fi
printf '%s\n' "${OUT[@]}"
[ "$BOUT" = 1 ] && exit 124
[ "$FAILS" -eq 0 ] || exit 1
exit 0
