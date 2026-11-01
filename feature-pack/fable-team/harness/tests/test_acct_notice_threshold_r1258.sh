#!/usr/bin/env bash
# test_acct_notice_threshold_r1258.sh — r1258: ft-tick acct_notice() 의 (결함 1) 시각 문턱 · (결함 2) «옛 회차가 남아 있다» 거절 = 정상 대기 · (결함 3) 불명만으로 가용 0 ≠ 정지 원인.
#   반례 R1~R10(카드 동결 집합) + 변이 4(문턱 제거 · «이미 있다» 분기 제거 · 재시도 120초→600초 · 알려진 계정 조건 제거).
#   bash tests/test_acct_notice_threshold_r1258.sh            # 전 칸
#   bash tests/test_acct_notice_threshold_r1258.sh --mutate   # 변이 4종(사본에 한 줄 어긋나게 하고 «그 칸이 무너지는지» 를 같은 프로세스에서 본다)
# 실 계정·실 우편함·실 정지 파일·실 네트워크 0: 가짜 예측·정지·mbox 도구 · 명부·상태·표식 전부 mktemp 안 · 가상 시각(FT_TICK_ACCT_NOW) · 고정 sleep 0 · r1215 시험 틀 그대로.
[ "${FT_TEST_ACCT_R1258_RUNNING:-0}" = 1 ] && { echo "SKIP 재진입(이미 도는 시험)"; exit 0; }
export FT_TEST_ACCT_R1258_RUNNING=1
ulimit -u "$(( $(ps -u "$(id -u)" 2>/dev/null | wc -l | tr -d ' ') + 300 ))" 2>/dev/null || true   # r1041: 사용자 프로세스 상한 여유
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="${FT_TEST_ACCT_BIN:-$HERE/../bin}"; KIT="${FT_TEST_ACCT_KIT:-$HERE/../kit/fable-team/bin}"
TICK="${R1258_TICK:-$BIN/ft-tick.sh}"
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
BASE=1793400000   # 가상 «지금»(60 의 배수 · 실제 시각과 무관)
ISOZ() { python3 -c 'import sys,datetime;print(datetime.datetime.fromtimestamp(int(sys.argv[1]),datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
cnt() { [ -f "$1" ] || { echo 0; return; }; grep -c "$2" "$1" || true; }
E0=$(( BASE + 18000 )); R0=$(( BASE + 36000 ))   # 소진 예상 · 풀림 기준 시각(분 경계)

# ── 가짜 도구 — 실머신 호출 0 ─────────────────────────────────────────────────────
cat > "$T/fc.sh" <<'EOF'
#!/bin/bash
echo run >> "$FAKE_DIR/fc.runs"
cat "$FAKE_FC_JSON"; exit 0
EOF
cat > "$T/pause.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_DIR/pause.calls"
case "$1 $2" in
  "status --check") [ -f "$FAKE_DIR/cleared" ] && { echo "OK pause=none"; exit 0; }; [ -f "$FAKE_DIR/chk.out" ] && cat "$FAKE_DIR/chk.out"; exit "$(cat "$FAKE_DIR/chk.rc" 2>/dev/null || echo 0)";;
  "set --provider") [ -n "${FAKE_SET_OUT:-}" ] && { echo "$FAKE_SET_OUT"; exit "${FAKE_SET_RC:-1}"; }; echo "SET pause $3 until=x release=— round=${FAKE_ROUND:-R1} recipients=1 남은통지=0"; exit "${FAKE_SET_RC:-0}";;
  "clear --provider") touch "$FAKE_DIR/cleared"; echo "CLEARED pause"; exit 0;;
esac
exit 0
EOF
cat > "$T/mbox.sh" <<'EOF'
#!/bin/bash
[ "$1" = send ] || exit 0
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
    FT_TICK_ACCT_NOTIFY="plan desk" FAKE_FC_JSON="$d/fc.json" \
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
fresh() { local d; d="$(D "$1")"; mkdir -p "$d"; rm -rf "$d"/*; }

# 비교 함수 단위 시험 — ft-tick.sh 에서 함수 3개만 떼어 와 부른다(실 파일 그대로 · 외부 호출 0)
hcmp() {   # hcmp <지난 값> <이번 값> [env…] → CHANGED | SAME
  local o="$1" n="$2"; shift 2
  sed -n '/^acct_mins() {/,/^acct_held_note() {/p' "$TICK" | sed '$d' > "$T/fn.sh"
  ( [ "$#" -eq 0 ] || export "$@"; . "$T/fn.sh"; acct_head_changed "$o" "$n" && echo CHANGED || echo SAME )
}

# ── R1: 흔들림은 안내 0 · 문턱을 넘으면 1통 (변이 1 대상) ───────────────────────────
chk_shake() {
  fresh sk; local d; d="$(D sk)"
  mk "$d/fc.json" claude 3 4 "$(ISOZ $E0)" "$(ISOZ $R0)"; lap sk "$BASE"
  eq "$(cnt "$d/mbox.log" .)" 2 "R1 첫 바퀴 planner·desk 각 1통(2통)"
  local i=1 m r; for m in 14 22 8 27; do   # 지난 안내(E0) 기준 |차| < 30 · 풀림 ±1분 흔들림
    r=$(( R0 + (i % 2) * 60 )); mk "$d/fc.json" claude 3 4 "$(ISOZ $((E0 + m * 60)))" "$(ISOZ $r)"; lap sk "$((BASE + 600 * i))"; i=$((i+1))
  done
  eq "$(cnt "$d/mbox.log" .)" 2 "R1 소진 +14·+22·+8·+27분 · 풀림 ±1분 4바퀴 → 안내 0통(2통 그대로)"
  mk "$d/fc.json" claude 3 4 "$(ISOZ $((E0 + 37 * 60)))" "$(ISOZ $R0)"; lap sk "$((BASE + 600 * i))"
  eq "$(cnt "$d/mbox.log" .)" 4 "R1 여섯째 바퀴 소진 +37분(차 37 ≥ 30) → 1통 더(4통)"
}
# ── R2·R7·R8: 비교 함수 단위 (실 함수 · 외부 호출 0) ─────────────────────────────────
chk_unit() {
  local K0="claude|3/4|2026-10-31 22:00|2026-11-01 02:00|0"
  eq "$(hcmp "$K0" "claude|2/4|2026-10-31 22:00|2026-11-01 02:00|0")" CHANGED "R2 가용 3/4→2/4 → 바뀜"
  eq "$(hcmp "$K0" "claude|3/4|2026-10-31 22:00|2026-11-01 02:00|1")" CHANGED "R2 불명 0→1 → 바뀜"
  eq "$(hcmp "$K0" "claude|3/4|—|2026-11-01 02:00|0")" CHANGED "R2 소진 값→«—» → 바뀜(숨기지 않음)"
  eq "$(hcmp "claude|3/4|—|—|0" "claude|3/4|—|2026-11-01 02:00|0")" CHANGED "R2 풀림 «—»→값 → 바뀜"
  eq "$(hcmp "claude|3/4|—|2026-10-31 23:49|0" "claude|3/4|—|2026-10-31 23:55|0")" CHANGED "R2 풀림 23:49→23:55(차 6 ≥ 2) → 바뀜"
  eq "$(hcmp "claude|3/4|—|2026-10-31 23:49|0" "claude|3/4|—|2026-10-31 23:50|0")" SAME "R1 풀림 23:49→23:50(차 1 < 2) → 안 바뀜"
  eq "$(hcmp "claude|3/4|—|2026-10-31 23:49|0" "claude|3/4|—|2026-10-31 23:51|0")" CHANGED "R2 풀림 차 2(문턱 경계) → 바뀜"
  eq "$(hcmp "$K0" "claude|3/4|2026-10-31 22:29|2026-11-01 02:00|0")" SAME "R1 소진 차 29 → 안 바뀜"
  eq "$(hcmp "$K0" "claude|3/4|2026-10-31 22:30|2026-11-01 02:00|0")" CHANGED "R1 소진 차 30(문턱 경계) → 바뀜"
  eq "$(hcmp "claude|3/4|2026-10-31 23:50|x|0" "claude|3/4|2026-11-01 00:10|x|0")" SAME "R1 자정 넘어 차 20 → 안 바뀜(날짜 계산)"
  eq "$(hcmp "claude|3/4|2026-10-31 23:50|x|0" "claude|3/4|2026-11-01 00:50|x|0")" CHANGED "R1 자정 넘어 차 60 → 바뀜(날짜 계산)"
  eq "$(hcmp "claude|3/4|2026-02-28 23:50|x|0" "claude|3/4|2026-03-01 00:10|x|0")" SAME "R1 2월 말→3월 차 20 → 안 바뀜(월 경계)"
  eq "$(hcmp "$K0" "$K0")" SAME "R8 같은 값 문턱 30 → 안 바뀜"
  eq "$(hcmp "$K0" "$K0" FT_TICK_ACCT_EXHAUST_MIN=0 FT_TICK_ACCT_RELEASE_MIN=0)" SAME "R8 같은 값 문턱 0 → 안 바뀜(글자 같음)"
  eq "$(hcmp "$K0" "claude|3/4|2026-10-31 22:01|2026-11-01 02:00|0" FT_TICK_ACCT_EXHAUST_MIN=0 FT_TICK_ACCT_RELEASE_MIN=0)" CHANGED "R7 문턱 0 → 글자가 다르면 바뀜(옛 동작)"
  eq "$(hcmp "claude|3/4|—" "$K0")" CHANGED "R7 옛 last 꼴(칸 수 다름) → 바뀜"
  eq "$(hcmp "" "$K0")" CHANGED "R7 last 파일 없음(빈 값) → 바뀜"
}
# ── R3~R5: 옛 회차가 남아 거절 = 정상 대기 (변이 2·3 대상) ─────────────────────────────
HELD_OUT() { echo "REJECT acct-pause set — claude 항목이 이미 있다(round=$1) — clear 뒤 set"; }
chk_held() {
  fresh hd; local d lr; d="$(D hd)"
  mk "$d/fc.json" claude 0 4 null "$(ISOZ $((BASE + 14400)))"
  lap hd "$BASE" FAKE_SET_RC=1 FAKE_SET_OUT="$(HELD_OUT RA)"
  eq "$(cnt "$d/pause.calls" '^set ')" 1 "R3 가용 0 → set 1회(거절)"
  eq "$(cnt "$d/pause.calls" '^status --check')" 1 "R3 새 status 호출 0(status --check 는 처음 1회뿐)"
  not "$(cat "$d/err.log")" "ERROR" "R3 «이미 있다» 거절 → ERROR 0"
  not "$(cat "$d/out.log")" "보류" "R3 «이미 있다» 거절 → 보류 줄 0"
  eq "$(grep -c 'claude 옛 회차 RA 남음 — 재정지 대기' "$d/out.log")" 1 "R3 INFO 1줄"
  has "$(cat "$d/mbox.log" 2>/dev/null)" "claude 재정지 대기(RA)" "R3 안내 정지 칸 «claude 재정지 대기(RA)»"
  eq "$(cat "$d/state/acct-notice/last-run" 2>/dev/null)" "$(( BASE - 600 + 120 ))" "R3 주기 표식 = 지금 − 600 + 120"
  lap hd "$((BASE + 119))"; has "$(cat "$d/out.log")" "acct_notice: skip 599s" "R4 +119초 → skip"
  eq "$(cnt "$d/pause.calls" '^set ')" 1 "R4 +119초 → set 0(1 그대로)"
  lap hd "$((BASE + 120))" FAKE_SET_RC=1 FAKE_SET_OUT="$(HELD_OUT RA)"
  eq "$(cnt "$d/pause.calls" '^set ')" 2 "R4 +120초 → 실행 · set 재시도"
  eq "$(grep -c '옛 회차 RA 남음' "$d/out.log")" 0 "R4 같은 회차 RA → INFO 0줄(그 바퀴 로그에 없음)"
  lap hd "$((BASE + 240))" FAKE_SET_RC=1 FAKE_SET_OUT="$(HELD_OUT RB)"
  eq "$(grep -c 'claude 옛 회차 RB 남음 — 재정지 대기' "$d/out.log")" 1 "R4 회차가 RB 로 바뀜 → INFO 1줄"
  lap hd "$((BASE + 360))" FAKE_ROUND=RN
  eq "$(cnt "$d/pause.calls" '^set ')" 4 "R4 회차 지워진 뒤 +120초 → set 성공"
  has "$(cat "$d/state/acct-notice/pause-claude.json" 2>/dev/null)" '"round_id": "RN"' "R4 set 성공 → 소유 기록 RN"
  [ ! -f "$d/state/acct-notice/held-claude.txt" ] && ok "R4 set 성공 → held 표식 삭제" || bad "R4 held 표식 남음"
  has "$(cat "$d/out.log")" "정지 set" "R4 성공 바퀴 로그 «정지 set»"
  lr="$(cat "$d/state/acct-notice/last-run" 2>/dev/null)"; eq "$lr" "$((BASE + 360))" "R4 성공 바퀴 → 10분 주기 복귀(last-run = 지금)"
  # R5: cause 없어짐(가용 1/4) + held 표식 → set 0 · 표식 삭제
  fresh h5; d="$(D h5)"; mkdir -p "$d/state/acct-notice"; echo RA > "$d/state/acct-notice/held-claude.txt"
  mk "$d/fc.json" claude 1 4 null null; lap h5 "$BASE"
  eq "$(cnt "$d/pause.calls" '^set ')" 0 "R5 가용 복귀 → set 0"
  [ ! -f "$d/state/acct-notice/held-claude.txt" ] && ok "R5 held 표식 삭제" || bad "R5 held 표식 남음"
  eq "$(cat "$d/state/acct-notice/last-run")" "$BASE" "R5 10분 주기(당김 0)"
}
# ── R6: 그 밖 실패·손 정지는 지금 경로 ─────────────────────────────────────────────────
chk_other() {
  fresh ot; local d; d="$(D ot)"
  mk "$d/fc.json" claude 0 4 null null
  lap ot "$BASE" FAKE_SET_RC=1 FAKE_SET_OUT="REJECT acct-pause set — 다른 이유"
  has "$(cat "$d/err.log")" "acct_notice: ERROR claude set rc=1: REJECT acct-pause set — 다른 이유" "R6 다른 문구 rc1 → ERROR"
  has "$(cat "$d/out.log")" "보류(정지 도구를 못 마침)" "R6 다른 문구 rc1 → 보류"
  [ ! -f "$d/state/acct-notice/last-run" ] && ok "R6 보류 → 주기 표식 지움(r1215 그대로)" || bad "R6 표식이 남음"
  fresh ot; mk "$d/fc.json" claude 0 4 null null
  lap ot "$BASE" FAKE_SET_RC=124
  has "$(cat "$d/err.log")" "acct_notice: ERROR claude set rc=124" "R6 rc124 → ERROR"
  has "$(cat "$d/out.log")" "보류(정지 도구를 못 마침)" "R6 rc124 → 보류"
  fresh ot; mk "$d/fc.json" claude 0 4 null null
  echo 3 > "$d/chk.rc"; echo "PAUSED claude until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=HAND stage=set" > "$d/chk.out"
  lap ot "$BASE"; eq "$(cnt "$d/pause.calls" '^set ')" 0 "R6 손 정지(status --check rc3) → set 0"
  has "$(cat "$d/out.log")" "정지 유지(손|다른 회차)" "R6 손 정지 로그(r1215 case 3 그대로)"
}
# ── R7: 옛 last 꼴 · env 0 되돌림 (lap 수준) ───────────────────────────────────────────
chk_old_env() {
  fresh oe; local d; d="$(D oe)"; mkdir -p "$d/state/acct-notice"; echo "claude|3/4|old" > "$d/state/acct-notice/last-claude.txt"
  mk "$d/fc.json" claude 3 4 "$(ISOZ $E0)" "$(ISOZ $R0)"; lap oe "$BASE"
  eq "$(cnt "$d/mbox.log" .)" 2 "R7 옛 last 꼴 → 첫 안내 1통(2통)"
  mk "$d/fc.json" claude 3 4 "$(ISOZ $((E0 + 600)))" "$(ISOZ $((R0 + 60)))"; lap oe "$((BASE + 600))"
  eq "$(cnt "$d/mbox.log" .)" 2 "R7 그 뒤 흔들림(소진 +10분 · 풀림 +1분) → 0통"
  fresh oz; d="$(D oz)"; mk "$d/fc.json" claude 3 4 "$(ISOZ $E0)" "$(ISOZ $R0)"
  lap oz "$BASE" FT_TICK_ACCT_EXHAUST_MIN=0 FT_TICK_ACCT_RELEASE_MIN=0
  lap oz "$((BASE + 600))" FT_TICK_ACCT_EXHAUST_MIN=0 FT_TICK_ACCT_RELEASE_MIN=0
  eq "$(cnt "$d/mbox.log" .)" 2 "R8 문턱 0 · 같은 값 → 0통(2통 그대로)"
  mk "$d/fc.json" claude 3 4 "$(ISOZ $((E0 + 60)))" "$(ISOZ $R0)"
  lap oz "$((BASE + 1200))" FT_TICK_ACCT_EXHAUST_MIN=0 FT_TICK_ACCT_RELEASE_MIN=0
  eq "$(cnt "$d/mbox.log" .)" 4 "R7 문턱 0 · 소진 +1분(값 다름) → 1통 더(옛 동작)"
}
# ── R9·R10: 불명만으로 가용 0 ≠ 정지 원인 (변이 4 대상) ─────────────────────────────────
chk_unknown() {
  fresh uk; local d; d="$(D uk)"
  mk "$d/fc.json" antigravity 0 1 null null 1
  lap uk "$BASE"; lap uk "$((BASE + 3600))"; lap uk "$((BASE + 7200))"
  eq "$(cnt "$d/pause.calls" '^set ')" 0 "R9 가용 0/1 · 불명 1 → 3바퀴 동안 set 0"
  eq "$(cnt "$d/mbox.log" .)" 2 "R9 안내 첫 바퀴 1통(2통) 뒤 0통"
  has "$(cat "$d/mbox.log" 2>/dev/null | head -1)" "가용 0/1 · 가장 이른 소진 근거 없음 · 풀림 — · 불명 1" "R9 안내 머리 줄은 그대로(불명 1 이 보임)"
  fresh uc; d="$(D uc)"; mk "$d/fc.json" antigravity 0 1 null null 0; lap uc "$BASE"
  eq "$(cnt "$d/pause.calls" '^set ')" 1 "R9 대조: 가용 0/1 · 불명 0 → 지금처럼 set 1(자동 a)"
  fresh ur; d="$(D ur)"; mkdir -p "$d/state/acct-notice"
  printf '{"round_id": "R1", "cause": "a", "set_at": 1}\n' > "$d/state/acct-notice/pause-antigravity.json"
  echo 3 > "$d/chk.rc"; echo "PAUSED antigravity until_hhmm=12:00 until_epoch=1 release_hhmm=12:00 round=R1 stage=set" > "$d/chk.out"
  mk "$d/fc.json" antigravity 0 2 null null 2; lap ur "$BASE"
  has "$(cat "$d/pause.calls" 2>/dev/null)" "clear --provider antigravity --round R1" "R10 풀이 가용 0/2 · 불명 2 로 바뀜 → clear --round R1"
  eq "$(cnt "$d/pause.calls" '^clear ')" 1 "R10 clear 정확히 1회"
  [ ! -f "$d/state/acct-notice/pause-antigravity.json" ] && ok "R10 소유 기록 삭제" || bad "R10 소유 기록 남음"
  eq "$(cnt "$d/pause.calls" '^set ')" 0 "R10 새 set 0"
}
all_checks() { chk_shake; PH R1; chk_unit; PH unit; chk_held; PH R3R5; chk_other; PH R6; chk_old_env; PH R7R8; chk_unknown; PH R9R10; }

bash -n "$TICK" && ok "bash -n ft-tick.sh" || bad "bash -n ft-tick.sh"
if [ "$MUT" = 0 ]; then
  all_checks
  for f in ft-tick.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓗ $f bin·kit 같음" || bad "ⓗ $f bin·kit 다름"; done
else
  # 변이: 사본 한 줄을 어긋나게 → 대응 칸이 «FAIL 을 내야» 변이가 잡힌 것(잡히면 PASS)
  mkdir -p "$T/mutbin"; cp -R "$BIN"/. "$T/mutbin/"
  mutant() {   # $1 번호 · $@ 검사 함수들
    local m="$1"; shift
    python3 - "$BIN/ft-tick.sh" "$T/mutbin/ft-tick.sh" "$m" <<'PY' || { bad "변이 $m — 치환 자리를 못 찾음"; return; }
import sys
pairs = {
  "1": ('''[ "${3:-0}" -gt 0 ] 2>/dev/null || return 0''', "return 0"),
  "2": ("항목이 이미 있다(round=", "항목이 없다(round="),
  "3": ("FT_TICK_ACCT_HELD_RETRY_SEC:-120", "FT_TICK_ACCT_HELD_RETRY_SEC:-600"),
  "4": (''' && [ "$av" = 0 ] && [ $(( tot - K )) -ge 1 ]''', ''' && [ "$av" = 0 ]'''),
}
old, new = pairs[sys.argv[3]]
s = open(sys.argv[1], encoding="utf-8").read()
if old not in s: sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
    local out n f; out=""; for f in "$@"; do out="$out$(TICK="$T/mutbin/ft-tick.sh" R1258_TICK="$T/mutbin/ft-tick.sh" "$f" 2>&1)"$'\n'; done
    n="$(printf '%s\n' "$out" | grep -c '^FAIL')"
    [ "$n" -gt 0 ] && ok "변이 $m → FAIL ${n}건(변이가 잡힘)" || bad "변이 $m → 전부 PASS(변이가 안 잡힘)"
  }
  mutant 1 chk_shake     # ① 문턱 제거(글자 비교) → R1 흔들림이 안내
  mutant 2 chk_held      # ② «이미 있다» 분기 제거 → R3 ERROR·보류
  mutant 3 chk_held      # ③ 재시도 표식 600초 → R4 +120초에 실행 안 함
  mutant 4 chk_unknown   # ④ 알려진 계정 조건 제거 → R9 set 1
fi
PH end
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL ${fail}건"; exit 1; }
