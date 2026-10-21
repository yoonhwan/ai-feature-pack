#!/usr/bin/env bash
# test_live_snapshot_all_rosters.sh — R324: 틱 데몬이 없는 팀의 현역 좌석도 재개 기록(seat-live)이 남는다.
# 틱 1개가 자기 명부 + 같은 폴더의 다른 명부(seats.json·seats-*.json)를 훑어 «지금 tmux 에 살아 있는» claude 좌석을 스냅샷한다 · 다른 명부 훑기는 FT_TICK_LIVE_SWEEP_SEC 마다 1번.
# 가짜 tmux·가짜 ft-resume-attempt.sh 만 쓴다 — 실 tmux·실 ~/.claude/state 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; TICK="$REPO/harness/bin/ft-tick.sh"; KIT="$REPO/harness/kit/fable-team/bin/ft-tick.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { [ "$2" = "$3" ] && ok "$1" || bad "$1 — «$2» ≠ «$3»"; }
bash -n "$TICK" && ok "bash -n ft-tick.sh" || bad "bash -n"
cmp -s "$TICK" "$KIT" && ok "키트 사본 cmp 0" || bad "키트 사본 어긋남"

mkdir -p "$T/bin" "$T/ros" "$T/repo"; git -C "$T/repo" init -q
printf '#!/bin/bash\ncase "$1" in list-panes) printf "%%b" "$FAKE_PANES";; *) exit 1;; esac\n' > "$T/bin/tmux"
printf '#!/bin/bash\n[ "$1" = snapshot ] && echo "$2" >> "$SNAP_LOG"\nexit 0\n' > "$T/resume-stub.sh"
printf '#!/bin/bash\nexit 0\n' > "$T/noop.sh"; chmod +x "$T/bin/tmux" "$T/resume-stub.sh" "$T/noop.sh"
# 명부 3개: 자기(t) · 틱 없는 팀(x) · 기본(seats.json) — X-M#1 은 두 명부에 중복
cat > "$T/ros/seats-t.json" <<'J'
{"_master":"T-M#1","T-M#1":{"role":"master","agent":"claude","model":"mt","tick":null},"T-N#1":{"role":"nano","agent":"claude","model":"mt"}}
J
cat > "$T/ros/seats-x.json" <<'J'
{"_master":"X-M#1","X-M#1":{"role":"master","agent":"claude","model":"mx"},"X-N#1":{"role":"nano","agent":"claude","model":"mx"},"X-DEAD#0":{"role":"nano","agent":"claude","model":"mx"},
 "X-STOP#1":{"role":"stop-ready","agent":"claude","model":"mx"},"X-NOMODEL#1":{"role":"nano","agent":"claude"},"X-CODEX#1":{"role":"da","agent":"codex","model":"gpt"},"X-REPL#1":{"role":"nano","agent":"claude","model":"mx","_replaced_by":"X-N#1"}}
J
cat > "$T/ros/seats.json" <<'J'
{"_master":"D-M#1","D-M#1":{"role":"master","agent":"claude","model":"md"},"X-M#1":{"role":"master","agent":"claude","model":"WRONG"}}
J
printf '{"_master": BROKEN' > "$T/ros/seats-bad.json"   # ⓔ 깨진 명부 — 나머지 명부는 계속 · 오류 1줄 stderr
export FAKE_PANES='T-M#1 %1\nT-N#1 %2\nX-M#1 %3\nX-N#1 %4\nX-STOP#1 %5\nX-NOMODEL#1 %6\nX-CODEX#1 %7\nX-REPL#1 %8\nD-M#1 %9\nNOROSTER#1 %10\n'
SNAP_LOG="$T/snap.log"; export SNAP_LOG
runtick() { # runtick <상태폴더> [KEY=VAL…]
  local sd="$1"; shift; : > "$SNAP_LOG"; mkdir -p "$sd"
  ( cd "$T/repo" && env FT_TICK_PATH_FIRST="$T/bin" FT_TICK_SEATS="$T/ros/seats-t.json" FT_TICK_STATE_DIR="$sd" FT_TICK_STAMP_PREFIX="$sd/p-" FT_TICK_PIDFILE="$sd/pid" \
      FT_TICK_RESUME_ATTEMPT="$T/resume-stub.sh" FT_TICK_RESUME=0 FT_TICK_API_OUTAGE=0 FT_TICK_HIL=0 FT_TICK_AUTONOMY=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_WT_SWEEP=0 \
      FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_TICK_STALL_INTERVAL=9999999999 \
      FT_TICK_MBOX="$T/noop.sh" FT_TICK_GOAL_TICK="$T/none" "$@" bash "$TICK" --once >"$sd/out" 2>&1 ); }
calls() { sort "$SNAP_LOG" | tr '\n' ' '; }

runtick "$T/s1"
chk "1회차: 자기 명부 + 다른 팀 명부의 «살아 있는» claude 좌석 전부 스냅샷(중복·codex·stop-ready·replaced·model 없음·죽은 좌석·명부 밖 제외)" \
  "$(calls)" "D-M#1 T-M#1 T-N#1 X-M#1 X-N#1 "
chk "중복 좌석(X-M#1)은 1번만" "$(grep -c '^X-M#1$' "$SNAP_LOG")" 1
chk "깨진 명부(seats-bad.json): 오류 1줄 stderr · 나머지 명부는 계속" "$(grep -c 'live_snapshot: seats.json unreadable .*seats-bad.json' "$T/s1/out")" 1
runtick "$T/s1"
chk "같은 상태 폴더 2회차(스윕 간격 안): 자기 명부만" "$(calls)" "T-M#1 T-N#1 "
runtick "$T/s1" FT_TICK_LIVE_SWEEP_SEC=0
chk "간격 0 → 다시 다른 명부까지" "$(calls)" "D-M#1 T-M#1 T-N#1 X-M#1 X-N#1 "
runtick "$T/s2" FT_TICK_LIVE_SNAPSHOT=0
chk "FT_TICK_LIVE_SNAPSHOT=0 → 스냅샷 0" "$(calls)" ""
cp "$T/s1/out" "$T/s1/out.keep"; : > "$SNAP_LOG"
( cd "$T/repo" && env FT_TICK_PATH_FIRST="$T/bin" FT_TICK_SEATS="$T/ros/seats-t.json" FT_TICK_STATE_DIR="$T/s3" FT_TICK_RESUME_ATTEMPT="$T/resume-stub.sh" FT_TICK_MBOX="$T/noop.sh" bash "$TICK" --once --dry-run 2>&1 ) > "$T/dry.out"
chk "dry-run: 다른 명부 좌석도 DRY 줄에 나오되 스냅샷 호출 0" "$(grep -c 'kind=live-snapshot seat=X-N#1' "$T/dry.out")|$(calls)" "1|"
[ ! -e "$T/s3/live-sweep" ] && ok "dry-run 은 스윕 stamp 를 쓰지 않음" || bad "dry-run 이 stamp 를 씀"

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
