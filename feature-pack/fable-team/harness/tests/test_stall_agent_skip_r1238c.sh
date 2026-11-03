#!/usr/bin/env bash
# test_stall_agent_skip_r1238c.sh — r1238 단계 C: ft-tick.sh stall() 이 비-claude 좌석(codex·pi)을 jsonl 나이로 깨우지 않는다.
#   원인: seat-status `one` 을 FT_SEATS_JSON 없이 불러 AGENT 열이 «-» 로 비었고, stall() 은 4열을 버렸다.
#   반례 C1 codex(같은 이름 옛 claude jsonl 20000초) → 깨움 0 + skip 1줄 · C2 claude → 깨움 · C3 pi → 깨움 0 · C4 agent 칸 없음 → 깨움 + WARN 1줄 · C0 팀 명부 전달.
#   bash tests/test_stall_agent_skip_r1238c.sh            # 전 칸
#   bash tests/test_stall_agent_skip_r1238c.sh --mutate   # 변이 3종(사본 한 줄을 어긋나게 하고 «그 칸이 무너지는지» 본다)
#   실 tmux·실 우편함·실 좌석 0 · 자기 재호출 0(재진입 표지) · 고정 sleep 0.
[ "${FT_TEST_STALL_AGENT_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_STALL_AGENT_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"
BIN="${FT_TEST_STALL_AGENT_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
MUT=0; case "${1:-}" in --mutate) MUT=1;; esac
fail=0; T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT

# ── 가짜 도구 ────────────────────────────────────────────────────────────────
FB="$T/fakebin"; mkdir -p "$FB"
cat > "$FB/tmux" <<'EOF'
#!/bin/bash
pane_arg() { local prev=""; for a in "$@"; do [ "$prev" = "-t" ] && { echo "$a"; return; }; prev="$a"; done; }
case "$1" in
  list-panes) printf '%s\n' "${FAKE_PANES:-}"; exit 0;;
  capture-pane) printf '❯ \n'; exit 0;;
  send-keys) printf 'SENDKEYS %s %s\n' "$(pane_arg "$@")" "$*" >> "${TMUX_LOG:-/dev/null}"; exit 0;;
esac
exit 0
EOF
cat > "$FB/mbox.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
# seat-status 대역 — one: 받은 FT_SEATS_JSON 을 기록하고, 그 명부의 agent 를 4열로 낸다(명부 못 받음·칸 없음 = «-»). jsonl 나이는 전부 20000초(옛 claude jsonl).
cat > "$T/seatstatus-stub.sh" <<'EOF'
#!/bin/bash
case "$1" in
  one) printf '%s\n' "${FT_SEATS_JSON:-NONE}" >> "${SS_LOG:-/dev/null}"
       agent="-"
       if [ -n "${FT_SEATS_JSON:-}" ] && [ -f "$FT_SEATS_JSON" ]; then
         agent="$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get(sys.argv[2]) or {}).get("agent") or "-")' "$FT_SEATS_JSON" "$2")"
       fi
       echo "$2 IDLE 20000 $agent"; exit 0;;
  turn) echo "IDLE 1793400000 0 no jsonl"; exit 0;;
esac
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$T/goal-stub.sh"; printf '#!/bin/bash\nexit 0\n' > "$T/alive-stub.sh"
chmod +x "$FB/tmux" "$FB/mbox.sh" "$T/seatstatus-stub.sh" "$T/goal-stub.sh" "$T/alive-stub.sh"
mkdir -p "$T/repo/.fable-team/bin"
cat > "$T/seats.json" <<'EOF'
{"_master":"M#1",
 "M#1":{"role":"master","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null},
 "C#1":{"role":"nano","agent":"claude","model":"claude-sonnet-5-5[1m]","tick":null},
 "X#1":{"role":"nano","agent":"codex","model":"gpt-6-luna","tick":null},
 "P#1":{"role":"nano","agent":"pi","model":"deepseek-v4.1-flash","tick":null},
 "N#1":{"role":"nano","model":"","tick":null}}
EOF
export FAKE_PANES='M#1 %11
C#1 %12
X#1 %13
P#1 %14
N#1 %15'

# 한 바퀴(--once)를 지정한 틱 파일로 돌린다 → $T/<이름>/{out,tmux.log,ss.log}
runtick() {   # $1 = 이름 · $2 = 틱 파일
  local n="$1" tick="$2"; mkdir -p "$T/$n/state"; : > "$T/$n/tmux.log"; : > "$T/$n/ss.log"
  cp "$tick" "$T/repo/.fable-team/bin/ft-tick.$n.sh"
  ( cd "$T/repo" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
      FT_TICK_SEATS="$T/seats.json" FT_TICK_MBOX="$FB/mbox.sh" FT_TICK_SEAT_STATUS="$T/seatstatus-stub.sh" \
      FT_TICK_IDLE_ENABLED=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_LAUNCHD=0 \
      FT_TICK_LEAK_REAP=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_QUEUE=0 FT_TICK_QUEUE_FULL=0 FT_TICK_UNPUSHED=0 \
      FT_TICK_RENAMED=0 FT_TICK_RAISED=0 FT_TICK_DRIFT=0 FT_TICK_PATH_FIRST="$FB" FT_TICK_WT_SWEEP=0 FT_TICK_AUTONOMY=0 \
      FT_TICK_ZOMBIE_CLEAN=0 FT_TICK_IDLE_LONG=0 FT_TICK_ACCT_PAUSE=0 FT_TICK_STALL_INTERVAL=0 FT_TICK_STALL_MIN=15 FT_TICK_STALL_WAKE_GAP=0 \
      FT_TICK_MASTER_INTERVAL=99999 FT_TICK_PM_INTERVAL=99999 FT_TICK_GOAL_INTERVAL=99999 FT_TICK_GOAL_TICK="$T/goal-stub.sh" FT_TICK_AGENT_ALIVE="$T/alive-stub.sh" \
      FT_TICK_STATE_DIR="$T/$n/state" FT_TICK_STAMP_PREFIX="$T/$n/p-" FT_TICK_PIDFILE="$T/$n/pid" \
      TMUX_LOG="$T/$n/tmux.log" SS_LOG="$T/$n/ss.log" PATH="$FB:$PATH" \
      timeout 70 bash "$T/repo/.fable-team/bin/ft-tick.$n.sh" --once > "$T/$n/out" 2>&1 )
}
woke() { grep -c "^SENDKEYS $2 .*stall-wake" "$T/$1/tmux.log" 2>/dev/null || true; }
outhas() { grep -c -- "$2" "$T/$1/out" 2>/dev/null || true; }

# 판정 4칸 + 명부 전달 → 실패한 칸 이름들(공백 구분)을 stdout 으로
judge() {   # $1 = 이름
  local n="$1" f=""
  [ "$(woke "$n" %13)" = 0 ] || f="$f C1-codex-깨움"
  [ "$(outhas "$n" 'stall skip X#1 agent=codex')" = 1 ] || f="$f C1-skip줄"
  [ "$(woke "$n" %12)" -ge 1 ] || f="$f C2-claude-깨움0"
  [ "$(woke "$n" %14)" = 0 ] || f="$f C3-pi-깨움"
  [ "$(woke "$n" %15)" -ge 1 ] || f="$f C4-칸없음-깨움0"
  [ "$(outhas "$n" 'WARN stall N#1 agent=-')" = 1 ] || f="$f C4-WARN줄"
  [ "$(grep -c "^$T/seats.json\$" "$T/$n/ss.log")" -ge 4 ] || f="$f C0-명부미전달"
  echo "${f# }"
}

PH "spec"
bash -n "$BIN/ft-tick.sh" && ok "bash -n ft-tick.sh" || bad "bash -n"
if [ -z "${FT_TEST_STALL_AGENT_BIN:-}" ]; then
  cmp -s "$BIN/ft-tick.sh" "$KIT/ft-tick.sh" && ok "bin·kit cmp0 ft-tick.sh" || bad "bin·kit 어긋남 ft-tick.sh"
  [ ! -x "$HERE/test_stall_agent_skip_r1238c.sh" ] && ok "신설 시험 0o644(실행 비트 0)" || bad "신설 시험에 실행 비트"
fi

if [ "$MUT" = 0 ]; then
  PH "C0-C4"
  runtick base "$BIN/ft-tick.sh"
  r="$(judge base)"
  [ -z "$r" ] && ok "C0~C4 전 칸(명부 전달 · codex 0 · claude 깨움 · pi 0 · 칸 없음 깨움+WARN)" || bad "C0~C4 실패: $r"
else
  PH "mutate"
  mut() {   # $1 = 이름 · $2 = 어긋낼 python 치환 (from→to) · $3 = 반드시 무너져야 할 칸
    python3 - "$BIN/ft-tick.sh" "$T/mut-$1.sh" "$2" "$3" <<'PY'
import sys
src, dst, a, b = sys.argv[1:5]
t = open(src, encoding="utf-8").read()
if a not in t:
    sys.exit("변이 대상 줄 없음: " + a)
open(dst, "w", encoding="utf-8").write(t.replace(a, b, 1))
PY
    [ $? = 0 ] || { bad "변이 $1 적용 실패"; return; }
    runtick "m$1" "$T/mut-$1.sh"
    local r; r="$(judge "m$1")"
    case " $r " in *" $4 "*) ok "변이 $1 → $4 FAIL ($r)";; *) bad "변이 $1 가 $4 를 못 무너뜨림 (실패 칸: ${r:-없음})";; esac
  }
  mut V-C1 '      *) log "stall skip $seat agent=$agent — jsonl 나이 판정 대상 아님"; continue;;' '      *) :;;' C1-codex-깨움 C1-codex-깨움
  mut V-C2 'FT_SEATS_JSON="$SEATS" bash "$SEAT_STATUS" one' 'bash "$SEAT_STATUS" one' C0-명부미전달
  mut V-C3 "      ''|-) echo \"\$(date '+%F %T') WARN stall \$seat agent=- — 명부에 agent 칸 없음 · jsonl 나이로 판정\" >&2;;" "      ''|-) continue;;" C4-칸없음-깨움0
fi
echo "RESULT fail=$fail total=$(( $(date +%s) - T0 ))s"
[ "$fail" = 0 ]
