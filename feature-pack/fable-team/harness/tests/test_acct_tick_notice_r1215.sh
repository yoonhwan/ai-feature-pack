#!/usr/bin/env bash
# test_acct_tick_notice_r1215.sh — r1215: ft-tick 의 acct_notice() = 10분 주기 예측 + 바뀔 때만 «[계정 안내]» + 자동 정지·재개(내 회차만).
#   반례 R1~R9(카드 동결 집합) + 변이 3(비교 제거 · --round 제거 · 주기 표식 검사 제거).
#   bash tests/test_acct_tick_notice_r1215.sh            # 전 칸
#   bash tests/test_acct_tick_notice_r1215.sh --mutate   # 변이 3종(사본에 한 줄 어긋나게 하고 «그 칸이 무너지는지» 를 같은 프로세스에서 본다)
# 실 좌석·실 우편함·실 정지 파일·실 네트워크 0: 가짜 예측·정지·mbox 도구 · 명부·상태·표식 전부 mktemp 안 · 가상 시각(FT_TICK_ACCT_NOW) · 고정 sleep 0.
[ "${FT_TEST_ACCT_NOTICE_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_ACCT_NOTICE_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041: 사용자 프로세스 상한 여유
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_ACCT_BIN:-$HERE/../bin}"; KIT="${FT_TEST_ACCT_KIT:-$HERE/../kit/fable-team/bin}"
TICK="${R1215_TICK:-$BIN/ft-tick.sh}"
fail=0; MUT=0; case "${1:-}" in --mutate) MUT=1;; esac
T0="$(date +%s)"
PH() { echo "PHASE ${1} +$(( $(date +%s) - T0 ))s"; }   # 단계별 초 — 회차 요약 첫 줄에 쓴다
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "${3:-판정}" || bad "${3:-판정} — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "${3:-판정}";; *) bad "${3:-판정} — 없음: «${2}» ← ${1:0:300}";; esac; }
not() { case "$1" in *"$2"*) bad "${3:-판정} — 있으면 안 됨: «${2}» ← ${1:0:300}";; *) ok "${3:-판정}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 2
export GIT_CEILING_DIRECTORIES="$(dirname -- "$T")"
BASE=1793400000   # 가상 «지금»(실제 시각과 무관)
ISOZ() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
cnt() { [ -f "$1" ] || { echo 0; return; }; grep -c "$2" "$1" || true; }

# ── 가짜 도구 — 실머신 호출 0 ─────────────────────────────────────────────────────
cat > "$T/fc.sh" <<'EOF'
#!/bin/bash
echo run >> "$FAKE_DIR/fc.runs"
[ -n "${FAKE_FC_SLEEP:-}" ] && sleep "$FAKE_FC_SLEEP"
[ -n "${FAKE_FC_MSG:-}" ] && { echo "$FAKE_FC_MSG"; exit "${FAKE_FC_RC:-2}"; }
cat "$FAKE_FC_JSON"; exit "${FAKE_FC_RC:-0}"
EOF
cat > "$T/pause.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_DIR/pause.calls"; echo "${FT_ACCT_BATCH_SEC:-}" >> "$FAKE_DIR/batch.log"
case "$1 $2" in
  "status --check") [ -f "$FAKE_DIR/cleared" ] && { echo "OK pause=none"; exit 0; }; [ -f "$FAKE_DIR/chk.out" ] && cat "$FAKE_DIR/chk.out"; exit "$(cat "$FAKE_DIR/chk.rc" 2>/dev/null || echo 0)";;
  "set --provider") echo "SET pause $3 until=x release=— round=${FAKE_ROUND:-R1} recipients=1 남은통지=0"; exit "${FAKE_SET_RC:-0}";;
  "clear --provider") case " $* " in *" --round "*) [ "${FAKE_CLEAR_RC:-0}" = 0 ] && [ -z "${FAKE_RELEASING:-}" ] && touch "$FAKE_DIR/cleared"; echo "${FAKE_CLEAR_OUT:-CLEARED pause}"; exit "${FAKE_CLEAR_RC:-0}";; *) echo "CLEARED pause (round 없이 — 교체 정지도 풀림)"; exit 0;; esac;;
esac
exit 0
EOF
cat > "$T/mbox.sh" <<'EOF'
#!/bin/bash
[ "$1" = send ] || exit 0
[ "$2" = "${FAKE_MBOX_FAIL_TO:-}" ] && exit 1
printf '%s\t%s\n' "$2" "$4" >> "$FAKE_DIR/mbox.log"; echo "QUEUED seq=1"
EOF
chmod +x "$T/fc.sh" "$T/pause.sh" "$T/mbox.sh"
echo '{"_master": null}' > "$T/seats.json"

# JSON 만들기: mk <파일> <풀> <가용> <계정수> <earliest ISO|null> <pool_reset ISO|null> [불명 K]
mk() {
  python3 - "$@" <<'PY'
import json, sys
f, pool, av, tot, e, r = sys.argv[1:7]; k = int(sys.argv[7]) if len(sys.argv) > 7 else 0
rows = [{"account": f"a{i}", "judge": "판정 불가" if i < k else ("가용" if i < int(av) + k else "소진(공통 창)"), "free": None} for i in range(int(tot))]
json.dump([{"pool": pool, "model": None, "available": int(av), "accounts": int(tot),
            "earliest": ({"account": "a0", "at": e, "kind": "5h"} if e != "null" else None),
            "pool_reset": (r if r != "null" else None), "pool_exhaust": "근거 없음(배정 순서)", "rows": rows, "windows": []}], open(f, "w"))
PY
}
# lap <시나리오> <가상 시각> [env…] → ft-tick --once 1바퀴(다른 감시 전부 끔 · 알림 대상 = plan·desk)
lap() {
  local s="$1" now="$2"; shift 2; local d="$T/$s"; mkdir -p "$d"; rm -f "$d/cleared"
  env FAKE_DIR="$d" FT_TICK_ACCT_NOW="$now" FT_TICK_ACCT_BIN="$T/fc.sh" FT_TICK_ACCT_PAUSE_BIN="$T/pause.sh" \
    FT_TICK_ACCT_NOTIFY="${NOTIFY:-plan desk}" FAKE_FC_JSON="${FAKE_FC_JSON:-$d/fc.json}" \
    FT_TICK_API_OUTAGE_STATE="$d/apio.json" FT_TICK_SEATS="$T/seats.json" FT_TICK_MBOX="$T/mbox.sh" FT_TICK_PIDFILE="$d/tick.pid" \
    FT_TICK_STATE_DIR="$d/state" FT_TICK_STAMP_PREFIX="$d/p-" FT_TICK_SEAT_STATUS="$d/none" FT_ROOT="$T/root" \
    FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 \
    FT_TICK_API_OUTAGE=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 \
    FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_WT_SWEEP=0 FT_TICK_UNPUSHED=0 \
    FT_TICK_WATCH_SAMPLE=0 FT_TICK_ACCT_PAUSE=0 "$@" \
    bash "$TICK" --once > "$d/out.log" 2> "$d/err.log"
  echo $? > "$d/rc"
}
D() { echo "$T/$1"; }

# ── R1·R2: 바뀔 때만 안내 · 분 단위 비교 (변이 1 대상) ─────────────────────────────
chk_notice() {
  local s="n${1:-a}" d; d="$(D "$s")"; mkdir -p "$d"; rm -rf "$d"/*
  mk "$d/fc.json" claude 3 4 null null
  lap "$s" "$BASE"; eq "$(cnt "$d/mbox.log" .)" 2 "R1 첫 바퀴 planner·desk 각 1통(2통)"
  has "$(cat "$d/mbox.log" 2>/dev/null)" "가용 3/4 · 가장 이른 소진 근거 없음 · 풀림 — · 불명 0" "R1 본문 머리 줄"
  [ -f "$d/state/acct-notice/last-claude.txt" ] && ok "R1 last 파일 생김" || bad "R1 last 파일 없음"
  lap "$s" "$((BASE + 600))"; eq "$(cnt "$d/mbox.log" .)" 2 "R1 둘째 바퀴 같은 JSON → 0통(2통 그대로)"
  mk "$d/fc.json" claude 3 4 "2026-10-31T14:30:10+00:00" "2026-11-02T02:59:10+00:00"
  lap "$s" "$((BASE + 1200))"; eq "$(cnt "$d/mbox.log" .)" 4 "R2 셋째 바퀴 earliest·pool_reset 생김 → 1통 더(4통)"
  mk "$d/fc.json" claude 3 4 "2026-10-31T14:30:50+00:00" "2026-11-02T02:59:50+00:00"
  lap "$s" "$((BASE + 1800))"; eq "$(cnt "$d/mbox.log" .)" 4 "R2 넷째 바퀴 초만 다름 → 0통"
  mk "$d/fc.json" claude 3 4 null "2026-11-02T02:59:50+00:00"
  lap "$s" "$((BASE + 2400))"; eq "$(cnt "$d/mbox.log" .)" 6 "R2 다섯째 earliest null 전환 → 1통 더(숨기지 않음)"
}
# ── R3~R5: 자동 정지·재개 (변이 2 대상 = chk_round) ────────────────────────────────
chk_pause_set() {
  local d="$(D ps)"; mkdir -p "$d"; rm -rf "$d"/*
  mk "$d/fc.json" claude 0 4 null "$(ISOZ $((BASE + 14400)))"; echo 0 > "$d/chk.rc"
  lap ps "$BASE"; local calls; calls="$(cat "$d/pause.calls" 2>/dev/null)"
  eq "$(cnt "$d/pause.calls" '^set ')" 1 "R3 가용 0 → set 1회"
  has "$calls" "set --provider claude --until $(ISOZ $((BASE + 14400))) --release-at $(ISOZ $((BASE + 14400))) --reason acct_notice 자동(a):" "R3 set 인자(until=release=풀림)"
  has "$(cat "$d/state/acct-notice/pause-claude.json" 2>/dev/null)" '"round_id": "R1"' "R3 pause-claude.json round 기록"
  echo 3 > "$d/chk.rc"; echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=R1 stage=set" > "$d/chk.out"
  lap ps "$((BASE + 600))"; eq "$(cnt "$d/pause.calls" '^set ')" 1 "R3 다음 바퀴 가용 0 + 정지 있음 → set 0(중복 없음)"
  # 풀림이 지금+9h → until = 지금+8h · 풀림 null → 지금+1h · release-at 없음
  rm -rf "$d"/state "$d"/pause.calls; echo 0 > "$d/chk.rc"; rm -f "$d/chk.out"
  mk "$d/fc.json" claude 0 4 null "$(ISOZ $((BASE + 32400)))"; lap ps "$BASE"
  has "$(cat "$d/pause.calls")" "--until $(ISOZ $((BASE + 28800))) --release-at $(ISOZ $((BASE + 32400)))" "R3 풀림 지금+9h → until 지금+8h"
  rm -rf "$d"/state "$d"/pause.calls; mk "$d/fc.json" claude 0 4 null null; lap ps "$BASE"
  has "$(cat "$d/pause.calls")" "--until $(ISOZ $((BASE + 3600))) --reason" "R3 풀림 null → until 지금+1h"
  not "$(cat "$d/pause.calls")" "--release-at" "R3 풀림 null → release-at 없음"
  # 반송 1-④: 풀림이 지금+30초(가까운 미래) → release-at 보존 · until 은 도구가 받는 최소(지금+60초)
  rm -rf "$d"/state "$d"/pause.calls; mk "$d/fc.json" claude 0 4 null "$(ISOZ $((BASE + 30)))"; lap ps "$BASE"
  has "$(cat "$d/pause.calls")" "--until $(ISOZ $((BASE + 60))) --release-at $(ISOZ $((BASE + 30)))" "R3 풀림 지금+30초 → release-at 보존 · until 지금+60초"
  # 반송 1-①: 정지 도구 배치를 남은 처리 예산보다 짧게(예산 5s → 배치 ≤3)
  local mx; mx="$(sort -n "$d/batch.log" | tail -1)"; [ -n "$mx" ] && [ "$mx" -ge 1 ] && [ "$mx" -le 3 ] && ok "R3 정지 도구 배치 ${mx}s < 처리 예산 5s" || bad "R3 배치 값 «$mx»"
  # 처리 예산이 3초 미만 → set 호출 0(끊긴 set 으로 정지만 남는 일 0) · 다음 바퀴 재시도
  rm -rf "$d"/state "$d"/pause.calls; rm -f "$d/mbox.log"; lap ps "$BASE" FT_TICK_ACCT_POST=2
  eq "$(cnt "$d/pause.calls" '^set ')" 0 "R3 처리 예산 2s → set 호출 0"
  [ ! -f "$d/state/acct-notice/pause-claude.json" ] && ok "R3 예산 부족 → 소유 기록 0(정지도 0)" || bad "R3 소유 기록이 생김"
  # 반송 2 덧붙임: 호출 0 바퀴는 안내 상태를 바꾸지 않는다(안내 0 · 표식 지움) → 뒤 바퀴 set 성공 때 안내 1통
  eq "$(cnt "$d/mbox.log" .)" 0 "R3 호출 0 바퀴 → 안내 0(옛 «판정 불가» 안내를 만들지 않음)"
  [ ! -f "$d/state/acct-notice/last-run" ] && ok "R3 호출 0 바퀴 → 주기 표식 지움(다음 바퀴 재시도)" || bad "R3 표식이 남음"
  [ ! -f "$d/state/acct-notice/last-claude.txt" ] && ok "R3 호출 0 바퀴 → last 갱신 0" || bad "R3 last 갱신됨"
  lap ps "$((BASE + 60))"; eq "$(cnt "$d/pause.calls" '^set ')" 1 "R3 뒤 바퀴 set 성공"
  eq "$(grep -c '정지: claude 있음' "$d/mbox.log")" 2 "R3 뒤 바퀴 set 성공 때 안내 1통씩(planner·desk · 정지 있음)"
}
chk_pause_b() {
  local d="$(D pb)"; mkdir -p "$d"; rm -rf "$d"/*
  mk "$d/fc.json" claude 3 4 null "$(ISOZ $((BASE + 150000)))"; echo 0 > "$d/chk.rc"; echo '{"status": "OUTAGE"}' > "$d/apio.json"
  lap pb "$BASE"
  has "$(cat "$d/pause.calls" 2>/dev/null)" "set --provider claude --until $(ISOZ $((BASE + 3600))) --reason acct_notice 자동(b):" "R4 OUTAGE → set(until 지금+1h · 원인 b)"
  not "$(cat "$d/pause.calls" 2>/dev/null)" "--release-at" "R4 원인 b = release-at 없음(다른 계정 풀림 무시)"
  rm -rf "$d"/state "$d"/pause.calls; mk "$d/fc.json" codex 0 2 null null
  lap pb "$BASE"; has "$(cat "$d/pause.calls" 2>/dev/null)" "acct_notice 자동(a):" "R4 codex 가용 0 + OUTAGE → 원인 a 로만"
  rm -rf "$d"/state "$d"/pause.calls; mk "$d/fc.json" codex 2 2 null null
  lap pb "$BASE"; eq "$(cnt "$d/pause.calls" '^set ')" 0 "R4 codex 가용 있음 + OUTAGE → 장애는 claude 고정(set 0)"
}
chk_round() {
  local d="$(D rd)"; mkdir -p "$d/state/acct-notice"; rm -rf "$d"/pause.calls
  printf '{"round_id": "R1", "cause": "a", "set_at": 1}\n' > "$d/state/acct-notice/pause-claude.json"
  mk "$d/fc.json" claude 1 4 null null; echo 3 > "$d/chk.rc"; echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=R1 stage=set" > "$d/chk.out"
  lap rd "$BASE"; has "$(cat "$d/pause.calls" 2>/dev/null)" "clear --provider claude --round R1" "R5 복귀 → clear --round R1 1회"
  eq "$(cnt "$d/pause.calls" '^clear ')" 1 "R5 clear 정확히 1회"
  [ ! -f "$d/state/acct-notice/pause-claude.json" ] && ok "R5 clear 뒤 기록 삭제" || bad "R5 기록 남음"
  # 확인 직후 손 정지로 교체 — 가짜 clear 가 round 불일치 REJECT rc3
  rm -rf "$d"/pause.calls "$d"/state/acct-notice/last-run; printf '{"round_id": "R1", "cause": "a", "set_at": 1}\n' > "$d/state/acct-notice/pause-claude.json"
  lap rd "$((BASE + 5000))" FAKE_CLEAR_RC=3 FAKE_CLEAR_OUT="REJECT acct-pause clear — round 불일치"
  [ -f "$d/state/acct-notice/pause-claude.json" ] && ok "R5 REJECT → 기록 유지" || bad "R5 REJECT 인데 기록 삭제됨"
  has "$(cat "$d/out.log")" "정지 유지(교체됨)" "R5 로그 «정지 유지(교체됨)»"
  # 손 정지(기록 없음) → clear 0
  rm -rf "$d"/pause.calls "$d"/state; echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=HAND stage=set" > "$d/chk.out"
  lap rd "$BASE"; eq "$(cnt "$d/pause.calls" '^clear ')" 0 "R5 손 정지 → clear 0"
  has "$(cat "$d/out.log")" "정지 유지(손|다른 회차)" "R5 로그 «정지 유지(손|다른 회차)»"
  # 원인 b 정지 + OUTAGE 유지 + 가용 4/4 → clear 0 · OUTAGE→OK → clear 1
  rm -rf "$d"/pause.calls "$d"/state; mkdir -p "$d/state/acct-notice"; mk "$d/fc.json" claude 4 4 null null
  printf '{"round_id": "R1", "cause": "b", "set_at": 1}\n' > "$d/state/acct-notice/pause-claude.json"
  echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=— round=R1 stage=set" > "$d/chk.out"; echo '{"status": "OUTAGE"}' > "$d/apio.json"
  lap rd "$BASE"; eq "$(cnt "$d/pause.calls" '^clear ')" 0 "R5 원인 b + OUTAGE 유지 → clear 0(가용 수 무관)"
  echo '{"status": "RECOVERED"}' > "$d/apio.json"; rm -f "$d/state/acct-notice/last-run" "$d/pause.calls"
  lap rd "$((BASE + 650))"; eq "$(cnt "$d/pause.calls" '^clear ')" 0 "R5 원인 b + RECOVERED(복구 절차 중) → clear 0"
  rm -f "$d/apio.json" "$d/state/acct-notice/last-run" "$d/pause.calls"
  lap rd "$((BASE + 680))"; eq "$(cnt "$d/pause.calls" '^clear ')" 0 "R5 원인 b + 장애 상태 읽기 불가(빈 값) → clear 0"
  echo '{"status": "OK"}' > "$d/apio.json"; rm -f "$d/state/acct-notice/last-run"
  lap rd "$((BASE + 700))"; eq "$(cnt "$d/pause.calls" '^clear ')" 1 "R5 OUTAGE→OK → clear 1"
  # 반송 1-②: clear 가 RELEASING(rc0)이면 status --check 로 확정 — rc3 이면 소유 기록·정지 표시 유지
  rm -rf "$d"/pause.calls "$d"/state; rm -f "$d/mbox.log"; mkdir -p "$d/state/acct-notice"; mk "$d/fc.json" claude 1 4 null null; rm -f "$d/apio.json"
  printf '{"round_id": "R1", "cause": "a", "set_at": 1}\n' > "$d/state/acct-notice/pause-claude.json"
  echo 3 > "$d/chk.rc"; echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=R1 stage=releasing" > "$d/chk.out"
  lap rd "$BASE" FAKE_RELEASING=1 FAKE_CLEAR_OUT="RELEASING claude/* round=R1 남은=2"
  [ -f "$d/state/acct-notice/pause-claude.json" ] && ok "R5 RELEASING → 소유 기록 유지" || bad "R5 RELEASING 인데 기록 삭제됨"
  has "$(cat "$d/mbox.log" 2>/dev/null)" "정지: claude 있음" "R5 RELEASING → 안내에 «정지: claude 있음»"
  not "$(cat "$d/mbox.log" 2>/dev/null)" "claude 없음" "R5 RELEASING → «claude 없음» 안내 0"
}
# ── R6: 실패 가시 · 불명 K · 예산 ──────────────────────────────────────────────────
chk_fail() {
  local d="$(D fl)"; mkdir -p "$d"; rm -rf "$d"/*
  lap fl "$BASE" FAKE_FC_RC=2 FAKE_FC_MSG="판정 불가 전 계정 429"
  has "$(cat "$d/err.log")" "acct_notice: ERROR forecast rc=2: 판정 불가 전 계정 429" "R6 예측 rc2 → ERROR 1줄"
  eq "$(cnt "$d/mbox.log" .)" 0 "R6 쪽지 0"; eq "$(cnt "$d/pause.calls" .)" 0 "R6 set/clear 0"; eq "$(cat "$d/rc")" 0 "R6 바퀴 rc0"
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null 1
  lap fl "$BASE" FAKE_FC_RC=3; has "$(cat "$d/mbox.log" 2>/dev/null)" "불명 1" "R6 rc3 + 유효 JSON → 처리 · 머리 줄 «불명 1»"
  # 예산(축소판: 마감 = 지금+6s · 최소 예산 3s · 여유 1s · 예측 10초 지연 → 5초에 끊김) + 예산 부족 건너뜀
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null; local t0 r; t0="$(date +%s)"
  lap fl "$BASE" FT_TICK_DEADLINE="$((t0 + 6))" FT_TICK_ACCT_MIN_BUDGET=3 FT_TICK_ACCT_MARGIN=1 FAKE_FC_SLEEP=10
  r="$(( $(date +%s) - t0 ))"; [ "$r" -le 8 ] && ok "R6 지연 예측이 남은 예산(5s)에서 끊김(${r}s)" || bad "R6 안 끊김 ${r}s"
  has "$(cat "$d/err.log")" "ERROR forecast rc=124" "R6 끊김 = ERROR rc=124"; eq "$(cat "$d/rc")" 0 "R6 끊겨도 바퀴 rc0"
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null
  lap fl "$BASE" FT_TICK_DEADLINE="$(( $(date +%s) + 2 ))" FT_TICK_ACCT_MIN_BUDGET=3
  has "$(cat "$d/out.log")" "acct_notice: skip 예산" "R6 예산 부족 → «skip 예산»"; eq "$(cnt "$d/fc.runs" .)" 0 "R6 예산 부족 → 예측 0회"
  [ ! -f "$d/state/acct-notice/last-run" ] && ok "R6 예산 부족 → 표식 갱신 0" || bad "R6 표식 갱신됨"
}
# ── R7: 부분 전달 재송 · 지정 대상 ─────────────────────────────────────────────────
chk_deliver() {
  local d="$(D dl)"; mkdir -p "$d"; rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null
  lap dl "$BASE" FAKE_MBOX_FAIL_TO=desk
  eq "$(cnt "$d/mbox.log" '^plan')" 1 "R7 planner 1통 QUEUED"; [ ! -f "$d/state/acct-notice/last-claude.txt" ] && ok "R7 desk 실패 → last 갱신 0" || bad "R7 last 갱신됨"
  has "$(cat "$d/err.log")" "mbox failed to=desk" "R7 실패 ERROR 1줄"
  lap dl "$((BASE + 600))"; eq "$(cnt "$d/mbox.log" '^plan')" 2 "R7 다음 바퀴 둘 다 재송(planner 중복 1통 허용)"; eq "$(cnt "$d/mbox.log" '^desk')" 1 "R7 desk 재송 성공"
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null; NOTIFY="only" lap dl "$BASE"
  eq "$(cut -f1 "$d/mbox.log" | sort -u | tr '\n' ,)" "only," "R7 FT_TICK_ACCT_NOTIFY 지정 시 그 좌석만"
}
# ── R8: DRY · 끄기 + 마지막 함수 ───────────────────────────────────────────────────
chk_dry() {
  local d="$(D dr)"; mkdir -p "$d"; rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null
  env FAKE_DIR="$d" FAKE_FC_JSON="$d/fc.json" FT_TICK_ACCT_NOW="$BASE" FT_TICK_ACCT_BIN="$T/fc.sh" FT_TICK_ACCT_PAUSE_BIN="$T/pause.sh" FT_TICK_ACCT_NOTIFY="plan desk" \
    FT_TICK_SEATS="$T/seats.json" FT_TICK_MBOX="$T/mbox.sh" FT_TICK_STATE_DIR="$d/state" FT_TICK_STAMP_PREFIX="$d/p-" FT_TICK_SEAT_STATUS="$d/none" FT_ROOT="$T/root" \
    FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 \
    FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_WT_SWEEP=0 \
    FT_TICK_UNPUSHED=0 FT_TICK_WATCH_SAMPLE=0 FT_TICK_API_OUTAGE_STATE="$d/apio.json" bash "$TICK" --dry-run > "$d/out.log" 2> "$d/err.log"
  eq "$(grep -c 'DRY kind=acct-notice' "$d/out.log")" 1 "R8 --dry-run → DRY 1줄"
  has "$(grep 'DRY kind=acct-notice' "$d/out.log")" "bin=$T/fc.sh pause=$T/pause.sh notify=plan desk" "R8 DRY 줄에 bin·pause·notify"
  eq "$(grep 'DRY kind=' "$d/out.log" | tail -1 | sed 's/DRY kind=\([a-z-]*\).*/\1/')" "acct-notice" "R8 acct_notice 가 바퀴의 «마지막» DRY 줄(앞 함수가 다 먼저)"
  eq "$(cnt "$d/fc.runs" .)$(cnt "$d/mbox.log" .)" 00 "R8 DRY → 도구·쪽지 0"; [ ! -e "$d/state/acct-notice" ] && ok "R8 DRY → 표식·파일 0" || bad "R8 DRY 가 파일 만듦"
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null; lap dr "$BASE" FT_TICK_ACCT=0
  eq "$(cnt "$d/fc.runs" .)" 0 "R8 FT_TICK_ACCT=0 → 실행 0"; not "$(cat "$d/out.log" "$d/err.log")" "acct_notice" "R8 FT_TICK_ACCT=0 → 로그 0"
  rm -rf "$d"/*; lap dr "$BASE" FT_TICK_ACCT_BIN=; eq "$(cat "$d/rc")" 0 "R8 임시 명부 + 도구 미지정 → 실 조회 0(다른 시험이 실 계정을 안 부른다)"
  not "$(cat "$d/out.log" "$d/err.log")" "acct_notice" "R8 임시 명부 + 도구 미지정 → 로그 0"
  rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null; lap dr "$BASE" FT_TICK_TEAM=harness; eq "$(cnt "$d/fc.runs" .)" 0 "R8 팀 틱(FT_TICK_TEAM) → 실행 0"
}
# ── R9: 10분 주기 (변이 3 대상) ────────────────────────────────────────────────────
chk_period() {
  local d="$(D pr)"; mkdir -p "$d"; rm -rf "$d"/*; mk "$d/fc.json" claude 3 4 null null
  lap pr 0; eq "$(cnt "$d/fc.runs" .)" 1 "R9 가상 0초 첫 실행 → 호출 1"
  lap pr 599; eq "$(cnt "$d/fc.runs" .)" 1 "R9 599초 → skip(호출 1 그대로)"; has "$(cat "$d/out.log")" "acct_notice: skip 599s" "R9 skip 로그"
  lap pr 600; eq "$(cnt "$d/fc.runs" .)" 2 "R9 600초 → 실행(호출 2)"
  lap pr 1200 FAKE_FC_RC=2 FAKE_FC_MSG="판정 불가 x"; eq "$(cnt "$d/fc.runs" .)" 3 "R9 1200초 실행(ERROR 바퀴)"
  lap pr 1500; eq "$(cnt "$d/fc.runs" .)" 3 "R9 ERROR 바퀴도 표식 갱신 → 1500초 skip"
}
# ── 실 도구: ft-acct-pause.sh clear --round (카드 «r1214 clear 에 round 일치 조건 1개») ──────────────
chk_real_clear() {
  local R="$T/real"; mkdir -p "$R/.fable-team/state"; echo '{}' > "$R/.fable-team/seats.json"
  printf '#!/bin/bash\nexit 0\n' > "$T/ftmux"; chmod +x "$T/ftmux"
  P() { env FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$T/ftmux" FT_ACCT_MBOX="$T/mbox.sh" FAKE_DIR="$T" FT_ACCT_NOW="$BASE" bash "$BIN/ft-acct-pause.sh" "$@" 2>&1; }
  local out rid before
  out="$(P set --provider claude --until "$(ISOZ $((BASE + 3600)))" --reason "acct_notice 자동(a): 시험 회차")"; rid="$(printf '%s\n' "$out" | sed -n 's/.*round=\([^ ]*\).*/\1/p' | head -1)"
  [ -n "$rid" ] && ok "실도구 set → round=$rid" || bad "실도구 set 실패: $out"
  before="$(cat "$R/.fable-team/state/ACCT_PAUSE")"
  out="$(P clear --provider claude --round WRONG-ROUND)"; rc=$?
  has "$out" "REJECT acct-pause clear" "실도구 다른 round → REJECT"; eq "$(P clear --provider claude --round WRONG-ROUND >/dev/null; echo $?)" 3 "실도구 다른 round → rc3"
  eq "$(cat "$R/.fable-team/state/ACCT_PAUSE")" "$before" "실도구 다른 round → 상태 파일 불변(부작용 0)"
  eq "$(P clear --round "$rid" >/dev/null; echo $?)" 2 "실도구 --round 만(provider 없음) → 사용법 rc2"
  out="$(P clear --provider claude --round "$rid")"; has "$out" "CLEARED pause claude/* round=$rid" "실도구 맞는 round → CLEARED"
  [ ! -s "$R/.fable-team/state/ACCT_PAUSE" ] || [ "$(cat "$R/.fable-team/state/ACCT_PAUSE" 2>/dev/null)" = "{}" ] && ok "실도구 clear 뒤 항목 없음" || bad "실도구 항목 남음"
  has "$(P clear --provider claude --round "$rid")" "pause=none" "실도구 이미 없는 provider + round → pause=none rc0"
}
# ── 반송 2: 실 도구 set — 모델명 빈 좌석 6 + 조회 지연 0.8초가 배치 예산을 넘겨도 끊기지 않고 «기록 + 정지» 가 같이 있다 ──
chk_real_set_budget() {
  local R="$T/real2" i s0 e rc rcc; mkdir -p "$R/.fable-team/state"
  { echo '{'; for i in 1 2 3 4 5 6; do echo "\"s$i#1\":{\"role\":\"nano\",\"agent\":\"claude\",\"model\":\"\",\"tick\":null}$([ $i = 6 ] || echo ,)"; done; echo '}'; } > "$R/.fable-team/seats.json"
  cat > "$T/slowtmux" <<'EOF'
#!/bin/bash
case "$1" in
  list-panes) for i in 1 2 3 4 5 6; do echo "s$i#1 %$i"; done;;
  display-message) sleep 0.8; echo $PPID;;
esac
exit 0
EOF
  chmod +x "$T/slowtmux"
  s0="$(date +%s)"
  env FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$T/slowtmux" FT_ACCT_MBOX="$T/mbox.sh" FAKE_DIR="$T" FT_ACCT_NOW="$BASE" FT_ACCT_BATCH_SEC=3 \
    timeout 5 bash "$BIN/ft-acct-pause.sh" set --provider claude --until "$(ISOZ $((BASE + 3600)))" --reason "acct_notice 자동(a): 배치 시험" > "$T/real2.out" 2>&1; rc=$?
  e=$(( $(date +%s) - s0 ))
  eq "$rc" 0 "실도구 set 모델 조회 6좌석×0.8s · 배치 3s → 끊기지 않고 rc0(${e}s)"
  [ "$e" -le 4 ] && ok "실도구 set 이 배치 예산(3s)+여유 안에 끝남(${e}s)" || bad "실도구 set 이 ${e}s 걸림"
  env FT_ACCT_ROOT="$R" FT_ACCT_TMUX="$T/slowtmux" FT_ACCT_MBOX="$T/mbox.sh" FAKE_DIR="$T" FT_ACCT_NOW="$BASE" bash "$BIN/ft-acct-pause.sh" status --check claude > "$T/real2.chk" 2>&1; rcc=$?
  eq "$rcc" 3 "실도구 set 뒤 status --check = 유효한 정지(rc3 · 회차 기록 있음 · rc4 아님)"
  has "$(cat "$T/real2.chk")" "round=" "실도구 정지에 회차 기록"
}
all_checks() { chk_notice a; PH R1R2; chk_pause_set; chk_pause_b; chk_round; PH R3R5; chk_fail; PH R6; chk_deliver; chk_dry; PH R7R8; chk_period; PH R9; chk_real_clear; chk_real_set_budget; PH real; }

bash -n "$TICK" && ok "bash -n ft-tick.sh" || bad "bash -n ft-tick.sh"
bash -n "$BIN/ft-acct-pause.sh" && ok "bash -n ft-acct-pause.sh" || bad "bash -n ft-acct-pause.sh"
if [ "$MUT" = 0 ]; then
  all_checks
  # ⓗ bin·kit cmp0
  for f in ft-tick.sh ft-acct-pause.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓗ $f bin·kit 같음" || bad "ⓗ $f bin·kit 다름"; done
else
  # 변이: 사본 한 줄을 어긋나게 → 대응 칸이 «FAIL 을 내야» 변이가 잡힌 것(잡히면 PASS)
  mkdir -p "$T/mutbin"; cp -R "$BIN"/. "$T/mutbin/"
  mutant() {   # $1 번호 · $2 검사 함수 — 치환쌍은 mkmut 안
    python3 - "$BIN/ft-tick.sh" "$T/mutbin/ft-tick.sh" "$1" <<'PY' || { bad "변이 $1 — 치환 자리를 못 찾음"; return; }
import sys
pairs = {
  "1": (r'''[ "$(cat "$sd/last-${t%%$'\t'*}.txt" 2>/dev/null)" = "${t#*$'\t'}" ] || changed=1''', "changed=1"),
  "2": (r'''--provider "$P" --round "$rid"''', '--provider "$P"'),
  "3": (r'''if [ -f "$sd/last-run" ] && [ "$left" -lt "${FT_TICK_ACCT_INTERVAL:-600}" ]; then''', "if false; then"),
}
old, new = pairs[sys.argv[3]]
s = open(sys.argv[1], encoding="utf-8").read()
if old not in s: sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    local out n; out="$(TICK="$T/mutbin/ft-tick.sh" "$2" 2>&1)"; n="$(printf '%s\n' "$out" | grep -c '^FAIL')"
    [ "$n" -gt 0 ] && ok "변이 $1 → FAIL ${n}건(변이가 잡힘)" || bad "변이 $1 → 전부 PASS(변이가 안 잡힘)"
  }
  mutant 1 chk_notice   # ① 비교 제거 → 매 바퀴 1통
  mutant 2 chk_round    # ③ --round 제거 → 교체 정지도 clear
  mutant 3 chk_period   # ⑦ 주기 표식 검사 제거 → 599초에 호출 2
fi
PH end
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL ${fail}건"; exit 1; }
