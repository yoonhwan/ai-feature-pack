#!/usr/bin/env bash
# test_tick_idle_long_skip_paused_r1300.sh — R1300: ft-tick 누적 정지 경보(idle_long_watch)가 r1291 «팀 정지 표식»(<루트>/.fable-team/state/<팀>-tick/PAUSED)을 읽는다.
#   R1 정지 표식 팀 = 경보 0 + DRY·로그 1줄(판정 N) / R2 표식 없음 = 지금 판과 바이트 같은 경보 / R3 표식 폴더·심링크·꼴 틀림 = 경보 + WARN 1줄
#   R4 좌석 M#1(팀 꼴 아님) = 지금 그대로 경보 / R5 팀마다 python 호출 1회(정지 팀 0경보) / R5b 문턱 밑 좌석은 호출 0
#   R6 FT_TICK_PAUSED_SKIP=0 = 호출 0 · 경보 / R7 표식 만듦 → 경보 0 · 지움 → 같은 turn_end 인데 경보 재개 / R8 팀 이름 꼴(점 허용·잘림 0·바퀴 계속)
# 모든 쓰기는 mktemp scratch — 실 tmux·실 우편함·실 /tmp 상태·launchd 0. tmux·mbox·seat-status 는 가짜. 고정 sleep 0 · 자기 재호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
KIT="$REPO/harness/bin"; INST="$REPO/harness/kit/fable-team/bin"
REALPY="$(command -v python3)"
TMP="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (got=[$2])";; esac; }

bash -n "$KIT/ft-tick.sh" && ok "bash -n kit" || bad "bash -n kit"
chk "키트 두 사본 동일 ft-tick.sh" "$(cmp -s "$KIT/ft-tick.sh" "$INST/ft-tick.sh" && echo same || echo differ)" same
chk "정본 ft_card_assign_pause.py 두 사본 동일" "$(cmp -s "$KIT/ft_card_assign_pause.py" "$INST/ft_card_assign_pause.py" && echo same || echo differ)" same

# ── 가짜 세계 ──
mkdir -p "$TMP/repo/.fable-team/bin" "$TMP/mins" "$TMP/wrap"
LIVE="$TMP/repo/.fable-team/bin/ft-tick.sh"; cp "$KIT/ft-tick.sh" "$TMP/repo/.fable-team/bin/ft-tick.sh"
cp "$KIT"/*.py "$TMP/repo/.fable-team/bin/" 2>/dev/null   # 형제 모듈 전부 = 설치된 bin 꼴(team_paused 체인 ft_directive_watch·ft_penalty …) · 실행≠사본
tmux() { case "$1" in list-panes) printf '%s\n' "$FAKE_PANES";; esac; return 0; }   # pane_of 와 같은 형식만 받는다
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
# 셈 래퍼(DA① 5 · DA② 1): 인자에 team_paused 가 있는 호출만 센다 — all_seats·master_seat 같은 다른 python 호출은 안 센다.
cat > "$TMP/wrap/python3" <<'WRAP'
#!/bin/bash
case "$*" in *team_paused*) printf 'x\n' >> "$CALLS";; esac
exec "$REALPY" "$@"
WRAP
chmod +x "$TMP/wrap/python3"
export MINTS_DIR="$TMP/mins" SENT_LOG="$TMP/sent.log" CALLS="$TMP/calls" REALPY
: > "$SENT_LOG"; : > "$CALLS"

MEND15="$(TZ=UTC date -u -v-15M '+%Y-%m-%dT%H:%M:%S')"
MEND05="$(TZ=UTC date -u -v-5M '+%Y-%m-%dT%H:%M:%S')"
MARK="판정 3131 · 2026-11-02T03:00 · 사람 정지 시험용 사유"
mark()   { mkdir -p "$TMP/repo/.fable-team/state/$1-tick"; printf '%s\n' "$MARK" > "$TMP/repo/.fable-team/state/$1-tick/PAUSED"; }
unmark() { rm -rf "$TMP/repo/.fable-team/state/$1-tick"; }
UNMARK_ALL() { rm -rf "$TMP/repo/.fable-team/state"; }
mins() { rm -rf "$TMP/mins"; mkdir -p "$TMP/mins"; }   # 좌석별 turn_end 파일을 케이스마다 비운다(앞 케이스 잔여 0)
m15() { local s; for s in "$@"; do echo "$MEND15" > "$TMP/mins/$s.end"; done; }   # 좌석 IDLE 15분
m05() { local s; for s in "$@"; do echo "$MEND05" > "$TMP/mins/$s.end"; done; }   # 좌석 IDLE 5분(문턱 밑)

# ── 명부 ──
# A = 한 팀(alpha) master + arch · 정지 표식 시험용
printf '{"_master":"byz-alpha-master-claude#1","_hil_route":"byz-alpha-arch-claude#1","byz-alpha-master-claude#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"byz-alpha-arch-claude#1":{"role":"arch","agent":"claude","model":"m","tick":null}}' > "$TMP/seats-a.json"
# M = 팀 꼴 아닌 좌석(R4 회귀)
printf '{"_master":"M#1","_hil_route":"PLAN#1","M#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"PLAN#1":{"role":"planner","agent":"claude","model":"m","tick":"ft-master-tick"}}' > "$TMP/seats-m.json"
# T = 두 팀(alpha 정지 · beta 아님) · alpha 좌석 2(master·arch) · beta 좌석 1
printf '{"_master":"byz-alpha-master-claude#1","_hil_route":"byz-alpha-arch-claude#1","byz-alpha-master-claude#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"byz-alpha-arch-claude#1":{"role":"arch","agent":"claude","model":"m","tick":null},"byz-beta-arch-claude#1":{"role":"arch","agent":"claude","model":"m","tick":null}}' > "$TMP/seats-t.json"

BASE=(FT_ROOT="$TMP/repo" FT_TICK_MBOX="$TMP/mbox-stub.sh" FT_TICK_SEAT_STATUS="$TMP/seatstatus-stub.sh"
  FT_TICK_TURN_FIXTURE_DIR= FT_TICK_IDLE_LONG=1 FT_TICK_IDLE_STALL_MIN=10 FT_TICK_PAUSED_SKIP=1
  FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0
  FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_RENAMED=0 FT_TICK_RAISED=0
  FT_TICK_DRIFT=0 FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 FT_TICK_STALL_INTERVAL=0 FT_TICK_MASTER_INTERVAL=0
  FT_TICK_PM_INTERVAL=0 FT_TICK_GOAL_INTERVAL=0 FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_RESUME_ATTEMPT="$TMP/no-resume-attempt"
  FT_TICK_MASTER_MSG=x FT_TICK_PM_MSG=x FT_TICK_GOAL_TICK="$TMP/none")
runtick() {  # runtick <이름> <KEY=VAL...> · RT_FLAGS = --once [--dry-run]
  local n="$1"; shift; mkdir -p "$TMP/$n/state"
  ( cd "$TMP/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      "${BASE[@]}" FT_TICK_STATE_DIR="$TMP/$n/state" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_PIDFILE="$TMP/$n/pid" \
      "$@" bash "$LIVE" ${RT_FLAGS:---once} > "$TMP/$n/out" 2>&1 )
}
stops()   { grep -c '정지 ' "$SENT_LOG" 2>/dev/null; }
stopbody(){ grep -F '정지 ' "$SENT_LOG" 2>/dev/null | sed 's/^[^	]*	//' | paste -sd'|' -; }
calls()   { [ -f "$CALLS" ] && wc -l < "$CALLS" | tr -d ' ' || echo 0; }
bodies()  { grep -c 'role=' "$SENT_LOG" 2>/dev/null; }

ALPHA_PANE=$'byz-alpha-master-claude#1 %1\nbyz-alpha-arch-claude#1 %2\nbyz-beta-arch-claude#1 %3'
PANES_M=$'M#1 %1\nPLAN#1 %3'
PANES_DOT=$'byz-alpha.beta-master-claude#1 %1\nbyz-alpha-arch-claude#1 %2'
PANES_CUT=$'byz-alpha- %1\nbyz-alpha-arch-claude#1 %2'
FAKE_PANES="$ALPHA_PANE"; export FAKE_PANES
BASE_M_15="[정지 15분] byz-alpha-master-claude#1 role=master — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"

# ── R1 정지 표식 팀 = 경보 0 + DRY/로그 1줄 ──
UNMARK_ALL; mark alpha; : > "$SENT_LOG"; : > "$CALLS"
mins; m15 "byz-alpha-master-claude#1"
RT_FLAGS="--once --dry-run" runtick r1d "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R1 DRY: 정지 줄 1 · 경보 줄 0" "$(grep -c 'kind=idle-long-paused seat=byz-alpha-master-claude#1 team=alpha' "$TMP/r1d/out") $(grep -c 'kind=idle-long seat=' "$TMP/r1d/out")" "1 0"
RT_FLAGS="--once" runtick r1 "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R1 실전: 경보 0" "$(stops)" 0
chk "R1 로그 1줄(판정 3131)" "$(grep -c 'idle_long_watch: byz-alpha-master-claude#1 정지 15분 — 팀 alpha 정지 표식(판정 3131) · 경보 0' "$TMP/r1/out")" 1
chk "R1 WARN 0" "$(grep -c 'WARN 정지 표식 판정 불가' "$TMP/r1/out")" 0

# ── R2 표식 없음 = 지금 판과 바이트 같은 경보 ──
UNMARK_ALL; : > "$SENT_LOG"
mins; m15 "byz-alpha-master-claude#1"
RT_FLAGS="--once" runtick r2 "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R2 경보 1" "$(stops)" 1
chk "R2 문구 = base 바이트" "$(stopbody)" "$BASE_M_15"
chk "R2 정지 로그 0줄" "$(grep -c '정지 표식' "$TMP/r2/out")" 0

# ── R3 판정 불가(폴더·심링크·꼴 틀림) = 막지 않음 + WARN 1줄 ──
for kind in dir sym bad; do
  UNMARK_ALL; : > "$SENT_LOG"; rmdir "$TMP/repo/.fable-team/state" 2>/dev/null
  mkdir -p "$TMP/repo/.fable-team/state/alpha-tick"
  case "$kind" in
    dir) rmdir "$TMP/repo/.fable-team/state/alpha-tick/PAUSED" 2>/dev/null; mkdir -p "$TMP/repo/.fable-team/state/alpha-tick/PAUSED";;
    sym) printf '%s\n' "$MARK" > "$TMP/repo/.fable-team/state/alpha-tick/real"; ln -sf "$TMP/repo/.fable-team/state/alpha-tick/real" "$TMP/repo/.fable-team/state/alpha-tick/PAUSED";;
    bad) printf '정지\n' > "$TMP/repo/.fable-team/state/alpha-tick/PAUSED";;
  esac
  RT_FLAGS="--once" runtick "r3$kind" "FT_TICK_SEATS=$TMP/seats-a.json"
  chk "R3($kind) 경보 1" "$(stops)" 1
  chk "R3($kind) 문구 = base" "$(stopbody)" "$BASE_M_15"
  chk "R3($kind) WARN 1줄" "$(grep -c 'WARN 정지 표식 판정 불가 — 경보 보냄(' "$TMP/r3$kind/out")" 1
done

# ── R4 좌석 M#1(팀 꼴 아님) · 표식 있어도 지금 그대로 ──
UNMARK_ALL; mark alpha; : > "$SENT_LOG"
mins; m15 "M#1"
RT_FLAGS="--once" runtick r4 "FT_TICK_SEATS=$TMP/seats-m.json" "FAKE_PANES=$PANES_M"
chk "R4 경보 1(억제 0)" "$(stops)" 1
chk "R4 문구" "$(stopbody)" "[정지 15분] M#1 role=master — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"
chk "R4 팀 판정 호출 0" "$(calls)" 0

# ── R5 두 팀: alpha(정지) 좌석 2 · beta(아님) 좌석 1 → alpha 0경보 로그 2줄 · beta 1 · 호출 2 ──
UNMARK_ALL; mark alpha; : > "$SENT_LOG"; : > "$CALLS"
mins; m15 "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-beta-arch-claude#1"
RT_FLAGS="--once" runtick r5 "FT_TICK_SEATS=$TMP/seats-t.json" "FT_TICK_PATH_FIRST=$TMP/wrap"
chk "R5 alpha 경보 0 · beta 경보 1" "$(stops) $(bodies)" "1 1"
has "R5 beta 문구" "$(stopbody)" "[정지 15분] byz-beta-arch-claude#1 role=arch"
chk "R5 alpha 로그 2줄" "$(grep -c '팀 alpha 정지 표식(판정 3131) · 경보 0' "$TMP/r5/out")" 2
chk "R5 python 호출 = 2(팀마다 1회)" "$(calls)" 2

# ── R5b 문턱 밑 좌석은 호출 0 ──
: > "$SENT_LOG"; : > "$CALLS"
mins; m15 "byz-alpha-master-claude#1"; m05 "byz-alpha-arch-claude#1"
RT_FLAGS="--once" runtick r5b "FT_TICK_SEATS=$TMP/seats-t.json" "FT_TICK_PATH_FIRST=$TMP/wrap"
chk "R5b 경보 0 · alpha 로그 1줄" "$(stops) $(grep -c '팀 alpha 정지 표식' "$TMP/r5b/out")" "0 1"
chk "R5b python 호출 = 1(문턱 넘은 좌석의 팀만)" "$(calls)" 1

# ── R6 끄기 = 호출 0 · 경보 ──
: > "$SENT_LOG"; : > "$CALLS"
RT_FLAGS="--once" runtick r6 "FT_TICK_SEATS=$TMP/seats-a.json" "FT_TICK_PATH_FIRST=$TMP/wrap" "FT_TICK_PAUSED_SKIP=0"
chk "R6 경보 1" "$(stops)" 1
chk "R6 정지 로그 0줄" "$(grep -c '정지 표식' "$TMP/r6/out")" 0
chk "R6 python 호출 0" "$(calls)" 0

# ── R7 연속 입력(같은 상태 폴더 · 같은 turn_end): 표식 만듦 → 0 · 지움 → 같은 turn_end 인데 경보 재개 ──
UNMARK_ALL; : > "$SENT_LOG"
mins; m15 "byz-alpha-master-claude#1"
RT_FLAGS="--once" runtick r7 "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R7① 표식 없음 = 경보 1" "$(stops)" 1
chk "R7① turn_end 표식 생김" "$([ -f "$TMP/r7/state/idlelong/byz-alpha-master-claude#1" ] && echo yes)" yes
mark alpha
RT_FLAGS="--once" runtick r7 "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R7② 표식 만듦 = 경보 그대로 1 · turn_end 표식 지워짐" "$(stops) $([ -f "$TMP/r7/state/idlelong/byz-alpha-master-claude#1" ] && echo yes || echo no)" "1 no"
unmark alpha
RT_FLAGS="--once" runtick r7 "FT_TICK_SEATS=$TMP/seats-a.json"
chk "R7③ 표식 지움 = 같은 turn_end 인데 경보 2(재개)" "$(stops)" 2

# ── R8 팀 이름 꼴: 점 허용 / 잘림 0 / 바퀴 계속 ──
UNMARK_ALL; : > "$SENT_LOG"
printf '{"_master":"byz-alpha.beta-master-claude#1","byz-alpha.beta-master-claude#1":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"byz-alpha-arch-claude#1":{"role":"arch","agent":"claude","model":"m","tick":null}}' > "$TMP/seats-dot.json"
mark alpha.beta
mins; m15 "byz-alpha.beta-master-claude#1"
RT_FLAGS="--once" runtick r8a "FT_TICK_SEATS=$TMP/seats-dot.json" "FAKE_PANES=$PANES_DOT"
chk "R8(a) 점 팀 = 경보 0" "$(stops)" 0
chk "R8(a) 로그(판정 3131)" "$(grep -c '팀 alpha.beta 정지 표식(판정 3131)' "$TMP/r8a/out")" 1
unmark alpha.beta
printf '{"_master":"byz-alpha-","_hil_route":"byz-alpha-arch-claude#1","byz-alpha-":{"role":"master","agent":"claude","model":"m","tick":"ft-master-tick"},"byz-alpha-arch-claude#1":{"role":"arch","agent":"claude","model":"m","tick":null}}' > "$TMP/seats-cut.json"
: > "$SENT_LOG"; mark alpha
mins; m15 "byz-alpha-"
RT_FLAGS="--once" runtick r8b "FT_TICK_SEATS=$TMP/seats-cut.json" "FAKE_PANES=$PANES_CUT"
chk "R8(b) 잘린 이름 = 팀 없음 → 경보 1(억제 0)" "$(stops)" 1
chk "R8(b) 정지 로그 0줄" "$(grep -c '정지 표식' "$TMP/r8b/out")" 0
# R8(c) 한 명부 두 arch 좌석 — all_seats 가 둘 다 내는지 먼저 보고(둘 다 DRY 줄이 나오면 바퀴가 둘 다 돈 것) → 첫 좌석 continue 뒤 둘째 경보
UNMARK_ALL; mark alpha; : > "$SENT_LOG"; : > "$CALLS"
mins; m15 "byz-alpha-master-claude#1" "byz-alpha-arch-claude#1" "byz-beta-arch-claude#1"
RT_FLAGS="--once --dry-run" runtick r8c1 "FT_TICK_SEATS=$TMP/seats-t.json"   # 사전: all_seats 가 두 arch 좌석을 둘 다 내는지(DRY 줄이 곧 all_seats 출력)
chk "R8(c) 사전: all_seats 출력에 두 arch 좌석 다 있음" "$([ "$(grep -c 'byz-alpha-arch-claude#1' "$TMP/r8c1/out")" -ge 1 ] && [ "$(grep -c 'byz-beta-arch-claude#1' "$TMP/r8c1/out")" -ge 1 ] && echo both)" both
RT_FLAGS="--once" runtick r8c "FT_TICK_SEATS=$TMP/seats-t.json" "FT_TICK_PATH_FIRST=$TMP/wrap"
chk "R8(c) 첫 좌석 continue 뒤 둘째 경보 1(바퀴 중단 0)" "$(stops)" 1
chk "R8(c) beta 문구" "$(stopbody)" "[정지 15분] byz-beta-arch-claude#1 role=arch — IDLE 지속 · 받은 발주 0 · 기다리는 것 = 없음(할 일을 못 받았다). 다음 발주·닫기·깨우기 중 하나"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
