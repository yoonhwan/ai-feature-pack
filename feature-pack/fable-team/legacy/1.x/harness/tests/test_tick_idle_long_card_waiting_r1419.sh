#!/usr/bin/env bash
# test_tick_idle_long_card_waiting_r1419.sh — R1419: ft-tick 누적 정지 경보(idle_long_watch)가 팀장 좌석이면 배정 원장(card-assign/<카드>.json)과 팀장 심박([정리])을 읽는다.
#   T1 대기 5장 전부 원장 waiting 선행(2시간 안) · 심박 10분 = 경보 0 · 로그 1줄 / T2 T1 + waiting 아닌 카드 1장 = 경보 1 + 그 카드 이름
#   T3 T1 + 심박 25분 = 경보 1 / T4 waiting 선행이 2시간 창 밖 = 경보 1(stall-scan 같은 판독) / T5 원장 꼴 깨짐 = 경보 1 + «카드 판독 불가»
#   T6 role=arch 좌석 = 지금과 같은 경보 / T7 팀이 TEAMS 명단 밖 = 지금 문구 그대로
# 모든 쓰기는 mktemp scratch — 실 tmux·실 우편함·실 /tmp 상태 0. tmux·mbox·seat-status·lint 는 가짜. 고정 sleep 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="${R1419_KIT:-$REPO/harness/bin}"; INST="$REPO/harness/kit/fable-team/bin"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got=[$2])";; esac; }

bash -n "$KIT/ft-tick.sh" && ok "bash -n kit" || bad "bash -n kit"
[ -n "${R1419_KIT:-}" ] || chk "키트 두 사본 동일 ft-tick.sh" "$(cmp -s "$KIT/ft-tick.sh" "$INST/ft-tick.sh" && echo same || echo differ)" same

# ── 가짜 세계 ──
R="$TMP/repo"; FT="$R/.fable-team"
mkdir -p "$FT/bin" "$FT/comm" "$FT/state" "$R/design" "$TMP/mins"
LIVE="$FT/bin/ft-tick.sh"; cp "$KIT/ft-tick.sh" "$LIVE"; cp "$KIT"/*.py "$FT/bin/" 2>/dev/null
tmux() { case "$1" in list-panes) printf '%s\n' "$FAKE_PANES";; esac; return 0; }
export -f tmux
cat > "$TMP/seatstatus-stub.sh" <<'STUB'
#!/bin/bash
case "$1" in
  turn) s="$2"; e="$(cat "$MINTS_DIR/$s.end" 2>/dev/null)"; [ -n "$e" ] && echo "IDLE $e 0 no jsonl"; exit 0;;
esac
exit 0
STUB
cat > "$TMP/mbox-stub.sh" <<'STUB'
#!/bin/bash
case "$1" in
  peek) echo "pending=0";;
  send) shift 2; printf '%s\t%s\n' "$1" "$2" >> "$SENT_LOG"; echo "QUEUED";;
esac
exit 0
STUB
printf '#!/bin/sh\nexit 0\n' > "$TMP/lint.sh"; chmod +x "$TMP/lint.sh"
export MINTS_DIR="$TMP/mins" SENT_LOG="$TMP/sent.log"
MA="byz-alpha-master-claude#1"; AR="byz-alpha-arch-claude#1"; PL="byz-planner-master-claude#1"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | x | 현역 |\n| planner | `design/teams/planner/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '{"_master":"%s","_hil_route":"%s","_cards":"cards/alpha","%s":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"%s":{"role":"arch","agent":"claude","model":"m","tick":null}}' "$MA" "$AR" "$MA" "$AR" > "$FT/seats-alpha.json"
printf '{"_master":"%s","_cards":"cards/planner","%s":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"}}' "$PL" "$PL" > "$FT/seats-planner.json"
mkdir -p "$R/cards/planner/대기"
FAKE_PANES="$MA %1"$'\n'"$AR %2"; export FAKE_PANES

NOWS="$(date +%s)"
MEND15="$(TZ=UTC date -u -r $((NOWS - 900)) '+%Y-%m-%dT%H:%M:%S')"
CARDS="F-1 F-2 F-3 F-4 F-5"
world() {  # 대기 5장 · 원장 전부 waiting 선행(10분 전) · 심박 <분> 전 · 상태 폴더 비움
  rm -rf "$R/cards/alpha" "$FT/state/card-assign" "$TMP/mins"; mkdir -p "$R/cards/alpha/대기" "$R/cards/alpha/진행" "$FT/state/card-assign" "$TMP/mins"
  local c; for c in $CARDS; do printf '# %s\n- 선행: 없음\n' "$c" > "$R/cards/alpha/대기/$c.md"; ledger "$c" "선행" 600; done
  heartbeat "${1:-10}"; : > "$SENT_LOG"
}
ledger() { printf '{"state":"waiting","reason":"%s","updated":%s}\n' "$2" "$((NOWS - $3))" > "$FT/state/card-assign/$1.json"; }
heartbeat() { printf '{"seq":900,"ts":"%s","to":"%s","from":"%s","body":"[정리] 한 일 3줄"}\n' "$(date -r $((NOWS - $1 * 60)) '+%Y-%m-%dT%H:%M:%S')" "$PL" "$MA" > "$FT/comm/mailbox.jsonl"; }
m15() { local s; for s in "$@"; do echo "$MEND15" > "$TMP/mins/$s.end"; done; }

BASE=(FT_ROOT="$R" FT_TICK_MBOX="$TMP/mbox-stub.sh" FT_TICK_SEAT_STATUS="$TMP/seatstatus-stub.sh" FT_TICK_SEATS="$FT/seats-alpha.json"
  FT_INDEX_LINT="$TMP/lint.sh" FT_MBOX_DIR="$FT/comm" FT_STALL_STATE_DIR="$FT/state" FT_TEAMS_MD="$R/design/TEAMS.md"
  FT_TICK_TURN_FIXTURE_DIR= FT_TICK_IDLE_LONG=1 FT_TICK_IDLE_STALL_MIN=10 FT_TICK_PAUSED_SKIP=1
  FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0
  FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_RENAMED=0 FT_TICK_RAISED=0
  FT_TICK_DRIFT=0 FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 FT_TICK_STALL_INTERVAL=0 FT_TICK_MASTER_INTERVAL=0
  FT_TICK_PM_INTERVAL=0 FT_TICK_GOAL_INTERVAL=0 FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_RESUME_ATTEMPT="$TMP/no-resume-attempt"
  FT_TICK_MASTER_MSG=x FT_TICK_PM_MSG=x FT_TICK_GOAL_TICK="$TMP/none")
runtick() {  # runtick <이름> [KEY=VAL...]
  local n="$1"; shift; mkdir -p "$TMP/$n/state"
  ( cd "$R" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      "${BASE[@]}" FT_TICK_STATE_DIR="$TMP/$n/state" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_PIDFILE="$TMP/$n/pid" \
      "$@" timeout 70 bash "$LIVE" --once > "$TMP/$n/out" 2>&1 )
}
stops()   { grep -c '정지 ' "$SENT_LOG" 2>/dev/null; }
stopbody(){ grep -F '정지 ' "$SENT_LOG" 2>/dev/null | sed 's/^[^	]*	//' | paste -sd'|' -; }
BASE_M="[정지 15분] $MA role=master — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"

# ── T1 전부 waiting 선행 · 심박 10분 = 경보 0 · 로그 1줄 ──
world 10; m15 "$MA"
runtick t1
chk "T1 경보 0" "$(stops)" 0
chk "T1 로그 1줄" "$(grep -c "idle_long_watch: $MA 정지 15분 — 카드 전부 waiting(5장) · 심박 10분" "$TMP/t1/out")" 1
runtick t1   # 같은 상태 폴더 · 같은 turn_end 다시 = 또 경보 0(서명 파일 안 씀)
chk "T1 두 번째 틱도 경보 0" "$(stops)" 0

# ── T2 T1 + waiting 아닌 대기 카드 1장 = 경보 1 + 카드 이름 ──
world 10; m15 "$MA"; printf '# F-9\n- 선행: 없음\n' > "$R/cards/alpha/대기/F-9.md"
runtick t2
chk "T2 경보 1" "$(stops)" 1
chk "T2 문구 = base + 카드 이름" "$(stopbody)" "$BASE_M · waiting 아닌 카드 1장: F-9"

# ── T3 T1 + 심박 25분 = 경보 1 ──
world 25; m15 "$MA"
runtick t3
chk "T3 경보 1" "$(stops)" 1
chk "T3 문구 = base" "$(stopbody)" "$BASE_M"

# ── T4 waiting 선행이 2시간 창 밖(3시간 전) = 경보 1 · 그 카드가 waiting 아님으로 읽힘 ──
world 10; m15 "$MA"; ledger F-3 "선행" 10800
runtick t4
chk "T4 경보 1" "$(stops)" 1
chk "T4 문구 = base + F-3" "$(stopbody)" "$BASE_M · waiting 아닌 카드 1장: F-3"

# ── T5 원장 꼴 깨짐 = 경보 1 + «카드 판독 불가» ──
world 10; m15 "$MA"; printf '{"state":"waiting",' > "$FT/state/card-assign/F-2.json"
runtick t5
chk "T5 경보 1" "$(stops)" 1
has "T5 문구에 판독 불가 원문" "$(stopbody)" "$BASE_M · 카드 판독 불가 RefUnavailable: 배정 원장 JSON 깨짐 F-2"

# ── T6 role=arch 좌석 = 지금과 같은 경보(원장·심박 무관) ──
world 10; m15 "$AR"
runtick t6
chk "T6 경보 1" "$(stops)" 1
chk "T6 문구 = base(arch)" "$(stopbody)" "[정지 15분] $AR role=arch — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"

# ── T7 팀이 TEAMS 명단 밖 = 지금 문구 그대로(알려진 한계 · 판독 0) ──
world 10; m15 "$MA"
runtick t7 FT_TEAMS_MD="$TMP/no-teams.md"
chk "T7 경보 1" "$(stops)" 1
chk "T7 문구 = base" "$(stopbody)" "$BASE_M"

# ── T8 판독 함수는 부르는 쪽 env 에 FT_ROOT 가 없어도(launchd·git 밖 cwd) 틱의 ROOT 로 읽는다 ──
world 10
awk '/^team_card_wait\(\) \{/,/^\}/' "$LIVE" > "$TMP/fn.sh"
T8="$(cd "$TMP" && env -u FT_ROOT FT_INDEX_LINT="$TMP/lint.sh" FT_MBOX_DIR="$FT/comm" FT_STALL_STATE_DIR="$FT/state" FT_TEAMS_MD="$R/design/TEAMS.md" \
  timeout 70 bash -c 'HERE="$1"; ROOT="$2"; now() { date +%s; }; . "$3"; team_card_wait alpha' _ "$FT/bin" "$R" "$TMP/fn.sh" | cut -f1-4)"
chk "T8 FT_ROOT 없는 env = wait 5장" "$T8" "wait	0	5	10분"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
