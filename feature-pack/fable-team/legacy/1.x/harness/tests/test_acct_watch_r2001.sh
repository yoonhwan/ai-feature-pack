#!/usr/bin/env bash
# test_acct_watch_r2001.sh — r2001: 2.0 루트 계정 한도 정지·풀림 재개 잡(ft-acct-watch.sh) + 공통 진입점 acct_cycle(루트 잠금 · 시도 소유 확인 · 손 정지 clear 0).
#   반례 ⓪~⑪(카드 동결 + 보정 R1 ⓔ) · 변이 M1~M4 = --mutate.
#   bash tests/test_acct_watch_r2001.sh            # 전 칸
#   bash tests/test_acct_watch_r2001.sh --mutate   # 변이 4종(사본 한 줄을 어긋나게 → 대응 칸이 무너지는지)
# 실 좌석·실 우편함·실 정지 파일·실 네트워크 0: 임시 루트 · 가짜 예측·tmux·mbox · 실 ft-acct-pause.sh(임시 루트) · 가상 시각(FT_TICK_ACCT_NOW·FT_ACCT_NOW) · 고정 sleep 0.
[ "${FT_TEST_ACCT_WATCH_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_ACCT_WATCH_RUNNING=1
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_ROOT FT_TICK_ACCT_BIN FT_TICK_ACCT_PAUSE_BIN FT_TICK_SEATS FT_TICK_ACCT_NOTIFY FT_MBOX_DIR
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_ACCT_BIN:-$HERE/../bin}"; KIT="${FT_TEST_ACCT_KIT:-$HERE/../kit/fable-team/bin}"
fail=0; MUT=0; case "${1:-}" in --mutate) MUT=1;; esac
T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "${3:-판정}" || bad "${3:-판정} — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "${3:-판정}";; *) bad "${3:-판정} — 없음: «${2}» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "${3:-판정} — 있으면 안 됨: «${2}» ← ${1:0:300}";; *) ok "${3:-판정}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; LIVEP=""
trap '[ -z "$LIVEP" ] || kill "$LIVEP" 2>/dev/null; rm -rf "$T"' EXIT
cd "$T" || exit 2
export GIT_CEILING_DIRECTORIES="$(dirname -- "$T")"
BASE=1793400000
ISOZ() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
cnt() { [ -f "$1" ] || { echo 0; return; }; grep -c -- "$2" "$1" || true; }

# ── 가짜 도구 ──────────────────────────────────────────────────────────────────────
cat > "$T/fc.sh" <<'EOF'
#!/bin/bash
echo run >> "$FAKE_DIR/fc.runs"
[ -n "${FAKE_FC_SLEEP:-}" ] && sleep "$FAKE_FC_SLEEP"
[ -n "${FAKE_FC_MSG:-}" ] && { echo "$FAKE_FC_MSG" >&2; exit "${FAKE_FC_RC:-2}"; }
cat "$FAKE_DIR/fc.json"; exit 0
EOF
cat > "$T/tmux" <<'EOF'
#!/bin/bash
case "$1" in list-panes) printf 'M#1 %%1\nN#1 %%2\nN#2 %%3\n';; esac
exit 0
EOF
cat > "$T/mbox.sh" <<'EOF'
#!/bin/bash
case "$1" in
  send) printf 'send\t%s\t%s\n' "$2" "$4" >> "$FAKE_DIR/mbox.log"; echo "QUEUED seq=1 doorbell=quiet";;
  ring) printf 'ring\t%s\n' "$2" >> "$FAKE_DIR/mbox.log";;
esac
exit 0
EOF
# 경쟁 정지 도구: set 을 «끊김(rc124)» 으로 끝내되 그 사이 무엇이 걸렸는지는 모드로 정한다 · 나머지는 실도구 그대로
cat > "$T/race.sh" <<'EOF'
#!/bin/bash
REAL="$FAKE_BIN/ft-acct-pause.sh"
case "${RACE_MODE:-} $1" in
  "hand set")  bash "$REAL" set --provider claude --until "$RACE_UNTIL" --reason "손 정지 — 사람이 직접 건 회차" --set-by manual-owner >/dev/null 2>&1; exit 124;;
  "mine set")  bash "$REAL" "$@" >/dev/null 2>&1; exit 124;;
  "swap clear") bash "$REAL" clear --provider claude >/dev/null 2>&1
               bash "$REAL" set --provider claude --until "$RACE_UNTIL" --reason "손 정지 — clear 사이 교체" --set-by manual-owner >/dev/null 2>&1
               exec bash "$REAL" "$@";;
esac
exec bash "$REAL" "$@"
EOF
cat > "$T/slowpause.sh" <<'EOF'
#!/bin/bash
sleep 10; echo "pause=none"
EOF
chmod +x "$T"/*.sh "$T/tmux"

mkbin() {   # $1 = 사본 폴더 → 실 bin 사본 + 예측만 가짜(명부 이름 조건을 우회하는 FT_TICK_ACCT_BIN 은 쓰지 않는다)
  mkdir -p "$1"; cp -R "$BIN"/. "$1/"; cp "$T/fc.sh" "$1/ft-acct-forecast.sh"
}
B="$T/bin"; mkbin "$B"
mk() {   # mk <폴더> <가용> <계정수> <pool_reset epoch|null>
  python3 - "$1/fc.json" "$2" "$3" "$4" <<'PY'
import datetime, json, sys
f, av, tot, r = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
iso = (datetime.datetime.fromtimestamp(int(r), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if r != "null" else None)
rows = [{"account": f"a{i}", "judge": "가용" if i < av else "소진(공통 창)", "free": None} for i in range(tot)]
json.dump([{"pool": "claude", "model": None, "available": av, "accounts": tot, "earliest": None, "pool_reset": iso,
            "pool_exhaust": "근거 없음", "rows": rows, "windows": []}], open(f, "w"))
PY
}
scn() {   # scn <이름> → 새 임시 루트(명부 = 루트 seats.json · _master 있음)
  local d="$T/$1"; rm -rf "$d"; mkdir -p "$d/root/.fable-team/state" "$d/root/.fable-team/comm"
  cat > "$d/root/.fable-team/seats.json" <<'EOF'
{"_master": "M#1",
 "M#1": {"role": "master", "agent": "claude", "model": "claude-fable-5-1[1m]", "tick": null},
 "N#1": {"role": "nano", "agent": "claude", "model": "claude-fable-5-1[1m]", "tick": null},
 "N#2": {"role": "nano", "agent": "claude", "model": "claude-fable-5-1[1m]", "tick": null}}
EOF
}
W() {   # W <이름> <가상 시각> [env…] → ft-acct-watch 1판 (bin = ${WB:-$B})
  local s="$1" now="$2" d; shift 2; d="$T/$s"
  env FAKE_DIR="$d" FAKE_BIN="${WB:-$B}" FT_TICK_ACCT_NOW="$now" FT_ACCT_NOW="$now" FT_ACCT_TMUX="$T/tmux" FT_ACCT_MBOX="$T/mbox.sh" \
    FT_TICK_MBOX="$T/mbox.sh" FT_TICK_STATE_DIR="$d/st" FT_TICK_API_OUTAGE_STATE="$d/apio.json" RACE_UNTIL="$(ISOZ $((now + 7200)))" "$@" \
    bash "${WB:-$B}/ft-acct-watch.sh" --root "$d/root" >> "$d/out.log" 2>&1
}
P() { local d="$T/$1" now="$2"; shift 2; env FT_ACCT_ROOT="$d/root" FT_ACCT_TMUX="$T/tmux" FT_ACCT_MBOX="$T/mbox.sh" FAKE_DIR="$d" FT_ACCT_NOW="$now" bash "${WB:-$B}/ft-acct-pause.sh" "$@" 2>&1; }
F() { python3 -c 'import json,sys
try: e=(json.load(open(sys.argv[1])) or {}).get("claude") or {}
except Exception: e={}
print(e.get(sys.argv[2]) or "")' "$T/$1/root/.fable-team/state/ACCT_PAUSE" "$2"; }   # F <이름> <칸> → ACCT_PAUSE claude 항목 칸(없으면 빈 줄)

# ── ⓪ dry-run: 루트 명부 기본값으로 두 단계가 다 보인다(명부 이름 조건 통째 skip 0) ──────────────
chk_dry() {
  scn dry; local out; out="$(env FT_TICK_STATE_DIR="$T/dry/st" FT_TICK_MBOX="$T/mbox.sh" bash "$B/ft-acct-watch.sh" --root "$T/dry/root" --dry-run 2>&1)"
  has "$out" "DRY kind=acct-pause" "⓪ dry-run 재개 단계"
  has "$out" "DRY kind=acct-notice" "⓪ dry-run 안내 단계(명부 이름 조건 통과)"
  has "$out" "notify=M#1" "⓪ 안내 대상 = 루트 seats.json _master"
  has "$out" "file=$T/dry/root/.fable-team/state/ACCT_PAUSE" "⓪ 정지 파일 = 그 루트"
}
# ── ①②③ 정지 → 같은 판 set 0 → 풀림 clear + [재개] · 만료 재개(acct_pause_watch) ──────────────
chk_cycle() {
  scn cy; local d="$T/cy"
  mk "$d" 0 2 $((BASE + 7200)); W cy "$BASE"
  [ -n "$(F cy round_id)" ] && ok "① 가용 0 → ACCT_PAUSE claude 항목 1개" || bad "① 정지 항목 없음 ← $(tail -3 "$d/out.log")"
  has "$(F cy set_by)" "acct-auto:root:" "① set_by = acct-auto:<루트 이름>:<시도 id>"
  eq "$(cnt "$d/mbox.log" '\[정지 예고\]')" 3 "① [정지 예고] 현역 좌석마다 1통(M#1·N#1·N#2)"
  has "$(cat "$d/st/acct-notice/pause-claude.json" 2>/dev/null)" "$(F cy round_id)" "① 소유 기록 = 그 round"
  [ ! -e "$d/root/.fable-team/state/acct-notice/cycle.lock" ] && ok "① 판 끝 잠금 닫힘" || bad "① 잠금이 남았다"
  local r1; r1="$(F cy round_id)"
  W cy $((BASE + 600)); eq "$(F cy round_id)" "$r1" "② 같은 판 다시 → set 0(같은 회차)"
  eq "$(ls "$d/root/.fable-team/state/acct-pause/" | grep -c '^claude-')" 1 "② 회차 기록 1개 그대로"
  mk "$d" 2 2 null; W cy $((BASE + 1200))
  eq "$(F cy round_id)" "" "③ 가용 복귀 → clear --round · 항목 삭제"
  eq "$(cnt "$d/mbox.log" $'\t\\[재개\\]')" 3 "③ [재개] 좌석마다 1통"
  eq "$(cnt "$d/mbox.log" '^ring')" 3 "③ 유휴 좌석 ring 1회씩"
  [ ! -f "$d/st/acct-notice/pause-claude.json" ] && ok "③ 소유 기록 삭제" || bad "③ 소유 기록 남음"
}
chk_expire() {   # ③b 만료 재개 = acct_pause_watch 몫(안내 주기 안 · 예측 0)
  scn ex; local d="$T/ex"
  mk "$d" 0 2 $((BASE + 30)); W ex "$BASE"
  [ -n "$(F ex round_id)" ] && ok "③b 정지(풀림 지금+30초)" || bad "③b 정지 없음 ← $(tail -3 "$d/out.log")"
  W ex $((BASE + 120))
  eq "$(cnt "$d/fc.runs" run)" 1 "③b 둘째 판 = 안내 주기 안(예측 0)"
  eq "$(F ex round_id)" "" "③b 유효 끝 지남 → 재개 단계가 항목 삭제"
  eq "$(cnt "$d/mbox.log" $'\t\\[재개\\]')" 3 "③b [재개] 좌석마다 1통"
}
# ── ④ 손 정지(다른 round)는 자동 clear 0 ─────────────────────────────────────────────
chk_hand() {
  scn hd; local d="$T/hd"
  P hd "$BASE" set --provider claude --until "$(ISOZ $((BASE + 7200)))" --reason "손 정지 — 사람이 직접 건 회차" --set-by manual-owner >/dev/null
  local r0; r0="$(F hd round_id)"
  mk "$d" 2 2 null; W hd "$BASE"
  eq "$(F hd round_id)" "$r0" "④ 가용 복귀여도 손 정지 그대로"
  has "$(cat "$d/out.log")" "정지 유지(손|다른 회차)" "④ 로그 «손|다른 회차»"
}
# ── ⑤ 예측 실패 → ERROR 1줄 · 정지 쓰기 0 · 다음 판 계속 ───────────────────────────────
chk_fcfail() {
  scn ff; local d="$T/ff"
  W ff "$BASE" FAKE_FC_MSG="판정 불가 조회 실패" FAKE_FC_RC=2
  eq "$(grep -c 'acct_notice: ERROR forecast' "$d/out.log")" 1 "⑤ ERROR forecast 1줄"
  [ ! -f "$d/root/.fable-team/state/ACCT_PAUSE" ] && ok "⑤ 정지 쓰기 0" || bad "⑤ 정지 파일 생김"
  mk "$d" 0 2 $((BASE + 7200)); W ff $((BASE + 600))
  [ -n "$(F ff round_id)" ] && ok "⑤ 다음 판 정상 → 정지" || bad "⑤ 다음 판 정지 없음"
}
# ── ⑥ 상한 넘는 판 → 끊고 1줄 · 잠금은 닫히거나 다음 판이 회수 ─────────────────────────
chk_wall() {
  scn wl; local d="$T/wl" s0
  echo '{}' > "$d/root/.fable-team/state/ACCT_PAUSE"
  s0="$(date +%s)"; W wl "$BASE" FT_ACCT_WATCH_SEC=2 FT_TICK_ACCT_PAUSE_BIN="$T/slowpause.sh"
  [ $(( $(date +%s) - s0 )) -le 6 ] && ok "⑥ 상한 2초 판이 6초 안에 끝남" || bad "⑥ 상한을 못 지킴"
  eq "$(grep -c '2초 넘음 — 판 끊음 · 남은 단계 다음 판' "$d/out.log")" 1 "⑥ 끊김 로그 1줄"
  rm -f "$d/root/.fable-team/state/ACCT_PAUSE"; mk "$d" 0 2 $((BASE + 7200)); W wl $((BASE + 600))
  [ -n "$(F wl round_id)" ] && ok "⑥ 다음 판 정상(잠금 안 막힘)" || bad "⑥ 다음 판 막힘 ← $(tail -2 "$d/out.log")"
}
# ── ⑦ 구조: ft-tick 은 lib 를 source 만 · 옮긴 함수 정의 0 · bin·kit 같음 ───────────────
chk_struct() {
  local f n=0
  for f in acct_notice acct_pause_watch acct_rows acct_run acct_pause_run acct_head_changed log now read_stamp write_stamp acct_cycle; do
    grep -q "^$f() *{" "$BIN/ft-tick.sh" && { bad "⑦ ft-tick.sh 에 $f 정의가 남음"; n=1; }
    grep -q "^$f() *{" "$BIN/ft-tick-acct-lib.sh" || { bad "⑦ lib 에 $f 없음"; n=1; }
  done
  [ "$n" = 0 ] && ok "⑦ 옮긴 함수 정의 = lib 에만"
  eq "$(grep -c '^\. "\$HERE/ft-tick-acct-lib.sh"' "$BIN/ft-tick.sh")" 1 "⑦ ft-tick 이 lib 를 1번 source"
  eq "$(grep -c 'acct_cycle "${ROOT:-$WT}"' "$BIN/ft-tick.sh")" 2 "⑦ ft-tick 은 acct_cycle 만 부름(재개·안내 2곳)"
  for f in ft-tick.sh ft-tick-acct-lib.sh ft-acct-watch.sh ft-acct-watch.plist; do cmp -s "$BIN/$f" "$KIT/$f" && ok "⑦ bin·kit 같음 $f" || bad "⑦ bin·kit 다름 $f"; done
  plutil -lint "$BIN/ft-acct-watch.plist" >/dev/null 2>&1 && ok "⑦ plist lint" || bad "⑦ plist lint"
  grep -q '<integer>300</integer>' "$BIN/ft-acct-watch.plist" && ok "⑦ StartInterval 300" || bad "⑦ StartInterval"
}
# ── ⑧ 같은 루트 두 주체: 잠금 1개만 씀 · ft-tick 경로도 같은 잠금 · 닫힘·재진입·죽은 주체 회수 ──────────
tick_once() {   # ft-tick --once 1바퀴(계정 단계만 켬) — 같은 루트·같은 STATE_DIR
  local s="$1" now="$2" d; d="$T/$1"; shift 2
  ( cd "$T" && env FAKE_DIR="$d" FT_TICK_ACCT_NOW="$now" FT_ACCT_NOW="$now" FT_ACCT_TMUX="$T/tmux" FT_ACCT_MBOX="$T/mbox.sh" FT_ACCT_ROOT="$d/root" \
    FT_TICK_API_OUTAGE_STATE="$d/apio.json" FT_TICK_SEATS="$d/root/.fable-team/seats.json" FT_TICK_MBOX="$T/mbox.sh" FT_TICK_PIDFILE="$d/tick.pid" \
    FT_TICK_STATE_DIR="$d/st" FT_TICK_STAMP_PREFIX="$d/p-" FT_TICK_SEAT_STATUS="$d/none" FT_ROOT="$d/root" FT_TICK_TRIGGERS=0 FT_TICK_TEAMMAIN_SEC=0 \
    FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 \
    FT_TICK_API_OUTAGE=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 \
    FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_WT_SWEEP=0 FT_TICK_UNPUSHED=0 FT_TICK_WATCH_SAMPLE=0 "$@" \
    bash "${WB:-$B}/ft-tick.sh" --once >> "$d/tick.log" 2>&1 )
}
chk_lock() {
  scn lk; local d="$T/lk" L st a b
  L="$d/root/.fable-team/state/acct-notice/cycle.lock"
  mk "$d" 0 2 $((BASE + 7200))
  # 실제 동시 2개: 예측 1초 지연 · 같은 루트 · 같은 시각 → 예측·set 은 한 주체만
  W lk "$BASE" FAKE_FC_SLEEP=1 & a=$!; W lk "$BASE" FAKE_FC_SLEEP=1 & b=$!; wait "$a" "$b"
  eq "$(cnt "$d/fc.runs" run)" 1 "⑧ 동시 2주체 → 예측 1번(한 주체만 씀)"
  eq "$(grep -cE 'acct_cycle: 잠금 (사용 중|owner 쓰는 중)' "$d/out.log")" 1 "⑧ 다른 주체 = «잠금 사용 중|owner 쓰는 중» 1줄 · 쓰기 0"
  eq "$(ls "$d/root/.fable-team/state/acct-pause/" 2>/dev/null | grep -c '^claude-')" 1 "⑧ 회차 1개"
  [ ! -e "$L" ] && ok "⑧ 두 판 뒤 잠금 닫힘" || bad "⑧ 잠금 남음"
  # 살아 있는 남의 잠금 → watch·ft-tick 둘 다 쓰기 0 (같은 잠금 연결)
  tail -f /dev/null & LIVEP=$!; st="$(ps -o lstart= -p "$LIVEP" | sed 's/^ *//')"
  mkdir -p "$L"; printf '%s\t%s\t%s\n' "$LIVEP" "$st" test-live > "$L/owner"
  : > "$d/out.log"; mk "$d" 2 2 null; W lk $((BASE + 600))
  eq "$(cnt "$d/fc.runs" run)" 1 "⑧ 산 잠금 → watch 예측 0"
  has "$(cat "$d/out.log")" "잠금 사용 중(pid=$LIVEP)" "⑧ watch «잠금 사용 중»"
  tick_once lk $((BASE + 600))
  eq "$(grep -c "acct_cycle: 잠금 사용 중(pid=$LIVEP)" "$d/tick.log")" 2 "⑧ ft-tick 재개·안내 단계도 같은 잠금에서 멈춤(2줄)"
  [ -n "$(F lk round_id)" ] && ok "⑧ 산 잠금 동안 clear 0(정지 그대로)" || bad "⑧ 정지가 풀림"
  [ -d "$L" ] && [ "$(cut -f1 "$L/owner")" = "$LIVEP" ] && ok "⑧ 살아 있는 남의 잠금 삭제 0" || bad "⑧ 산 잠금이 지워짐"
  kill "$LIVEP" 2>/dev/null; wait "$LIVEP" 2>/dev/null; LIVEP=""
  # 죽은 주체 잠금 → 회수 뒤 진행(ft-tick 경로) · 재진입
  tick_once lk $((BASE + 600))
  has "$(cat "$d/tick.log")" "끊긴 주체 잠금 회수" "⑧ 죽은 주체 잠금 회수"
  eq "$(F lk round_id)" "" "⑧ 회수 뒤 ft-tick 이 풀림(clear)"
  [ ! -e "$L" ] && ok "⑧ ft-tick 바퀴 뒤 잠금 닫힘" || bad "⑧ ft-tick 뒤 잠금 남음"
  # owner 없는 젊은 잠금 = 대기 · 오래되면 회수
  mkdir -p "$L"; : > "$d/out.log"; mk "$d" 0 2 $((BASE + 9000)); W lk $((BASE + 1800))
  has "$(cat "$d/out.log")" "잠금 owner 쓰는 중" "⑧ owner 없는 젊은 잠금 → 쓰기 0"
  W lk $((BASE + 1800)) FT_ACCT_LOCK_ORPHAN_SEC=0
  [ -n "$(F lk round_id)" ] && ok "⑧ 오래된 빈 잠금 회수 → 재진입 정지" || bad "⑧ 빈 잠금 회수 실패 ← $(tail -2 "$d/out.log")"
}
# ── ⑨⑩ set 결과 불명: 이번 시도 id 일 때만 소유 ─────────────────────────────────────
chk_unknown_hand() {   # ⑨ = DA 반례(set 끊김 사이 손 정지)
  scn uh; local d="$T/uh"
  mk "$d" 0 2 $((BASE + 7200)); W uh "$BASE" FT_TICK_ACCT_PAUSE_BIN="$T/race.sh" RACE_MODE=hand
  eq "$(F uh set_by)" "manual-owner" "⑨ 끊김 사이 손 정지가 걸림"
  [ ! -f "$d/st/acct-notice/pause-claude.json" ] && ok "⑨ 소유 기록 0" || bad "⑨ 손 정지 round 를 내 것으로 기록"
  has "$(cat "$d/out.log")" "이번 시도가 아님" "⑨ 로그 «이번 시도가 아님»"
  mk "$d" 2 2 null; W uh $((BASE + 600))
  eq "$(F uh set_by)" "manual-owner" "⑨ 복귀 표본에서도 손 정지 clear 0"
}
chk_unknown_mine() {   # ⑩ 같은 불명이어도 내 시도 id 면 정상 회복
  scn um; local d="$T/um"
  mk "$d" 0 2 $((BASE + 7200)); W um "$BASE" FT_TICK_ACCT_PAUSE_BIN="$T/race.sh" RACE_MODE=mine
  has "$(F um set_by)" "acct-auto:root:" "⑩ 끊김이지만 도구는 내 시도로 걸었다"
  has "$(cat "$d/st/acct-notice/pause-claude.json" 2>/dev/null)" "$(F um round_id)" "⑩ 소유 기록 1(그 round)"
  mk "$d" 2 2 null; W um $((BASE + 600))
  eq "$(F um round_id)" "" "⑩ 복귀 → 내 회차 clear"
}
# ── ⑪ clear 중 손 정지로 교체 → REJECT round 불일치 · 손 정지 그대로 · ⑪b 자동 아닌 항목 clear 0 ──────
chk_swap() {
  scn sw; local d="$T/sw"
  mk "$d" 0 2 $((BASE + 7200)); W sw "$BASE"
  mk "$d" 2 2 null; W sw $((BASE + 600)) FT_TICK_ACCT_PAUSE_BIN="$T/race.sh" RACE_MODE=swap
  eq "$(F sw set_by)" "manual-owner" "⑪ 교체된 손 정지 그대로"
  has "$(cat "$d/out.log")" "정지 유지(교체됨)" "⑪ 도구 round 검사 REJECT → «교체됨»"
  scn sb; d="$T/sb"
  P sb "$BASE" set --provider claude --until "$(ISOZ $((BASE + 7200)))" --reason "손 정지 — 옛 기록과 같은 round" --set-by manual-owner >/dev/null
  mkdir -p "$d/st/acct-notice"; printf '{"round_id": "%s", "cause": "a", "set_at": %s}\n' "$(F sb round_id)" "$BASE" > "$d/st/acct-notice/pause-claude.json"
  mk "$d" 2 2 null; W sb "$BASE"
  eq "$(F sb set_by)" "manual-owner" "⑪b 소유 기록 round 가 맞아도 set_by 자동 아님 → clear 0"
  has "$(cat "$d/out.log")" "자동 아님 — clear 0" "⑪b 로그"
}
all_checks() { chk_dry; chk_struct; PH "⓪⑦"; chk_cycle; chk_expire; PH "①②③"; chk_hand; chk_fcfail; PH "④⑤"; chk_wall; PH "⑥"; chk_lock; PH "⑧"; chk_unknown_hand; chk_unknown_mine; chk_swap; PH "⑨⑩⑪"; }

for f in ft-acct-watch.sh ft-tick-acct-lib.sh ft-tick.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
if [ "$MUT" = 0 ]; then
  all_checks
else
  mutant() {   # $1 번호 · $2 검사 함수 — 사본 bin 의 lib 한 줄을 어긋나게 → 그 칸이 FAIL 을 내야 잡힌 것
    local MB="$T/mut$1"; mkbin "$MB"
    python3 - "$MB/ft-tick-acct-lib.sh" "$1" <<'PY' || { bad "변이 $1 — 치환 자리를 못 찾음"; return; }
import sys
f, m = sys.argv[1:3]
pairs = {
  "1": ("    *) acct_pause_watch; acct_notice;;", "    *) acct_pause_watch;;"),
  "2": ("    *) acct_pause_watch; acct_notice;;", "    *) acct_notice;;"),
  "3": ('if [ "$(acct_entry_field "$P" set_by)" = "$tok" ]; then', 'if true; then'),
  "4": ('acct_lock_take "$root/.fable-team/state/acct-notice/cycle.lock" || return 0', ':'),
}
old, new = pairs[m]
s = open(f, encoding="utf-8").read()
if old not in s: sys.exit(1)
open(f, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    local out n; out="$(WB="$MB"; "$2" 2>&1)"; n="$(printf '%s\n' "$out" | grep -c '^FAIL')"
    [ "$n" -gt 0 ] && ok "변이 M$1 → FAIL ${n}건(변이가 잡힘)" || bad "변이 M$1 → 전부 PASS(변이가 안 잡힘)"
  }
  mutant 1 chk_cycle          # M1 acct_notice 호출 삭제 → ① FAIL
  mutant 2 chk_expire         # M2 acct_pause_watch 호출 삭제 → ③b FAIL
  mutant 3 chk_unknown_hand   # M3 set_by 확인 삭제 → ⑨ FAIL
  mutant 4 chk_lock           # M4 잠금 삭제 → ⑧ FAIL
fi
PH end
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL ${fail}건"; exit 1; }
