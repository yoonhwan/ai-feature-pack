#!/usr/bin/env bash
# R1320 — ft-tick 이 600초마다 ft-team-main.sh render --all 을 1회 부른다 (지시 16 · 판정 3224).
#   계약 T1~T4 · 반례 M1~M6. 실 launchd·실 STATE 렌더 0 — 가짜 ft-team-main.sh + 임시 stamp 폴더 + --once 만 쓴다.
#   FT_TICK_UNDER_TEST=<경로> 로 변이 사본을 같은 시험에 걸 수 있다(기본 = 실제 ft-tick.sh).
set -uo pipefail
export LC_ALL=C
ulimit -u 2000 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"
TICK="${FT_TICK_UNDER_TEST:-$BIN/ft-tick.sh}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/root"; mkdir -p "$ROOT/.fable-team/comm" "$ROOT/.fable-team/state" "$ROOT/design"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n' > "$ROOT/design/TEAMS.md"   # 렌더 가드(팀 명단 있음) 통과용
printf '{"_version":1}\n' > "$ROOT/.fable-team/seats.json"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/.fable-team/comm/mbox.sh"
STAMP="$ROOT/stamp-_all.teammain.last"          # stamp_of _all teammain 과 같은 꼴(<prefix><이름>.<칸>.last)
CALLS="$TMP/calls"; MODEF="$TMP/mode"; TOOL="$TMP/ft-team-main.sh"
: > "$CALLS"; printf 'ok\n' > "$MODEF"
cat > "$TOOL" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TEAMMAIN_CALLS"
case "$(cat "$FAKE_TEAMMAIN_MODE" 2>/dev/null)" in
  fail) echo "render failed" >&2; exit 1;;
  slow) exec sleep 8;;          # timeout 7 이 끊는지(M4) — exec 라 TERM 이 sleep 에 바로 간다
  *) echo "rendered"; exit 0;;
esac
SH
export FAKE_TEAMMAIN_CALLS="$CALLS" FAKE_TEAMMAIN_MODE="$MODEF"
export FT_ROOT="$ROOT" FT_TICK_SEATS="$ROOT/.fable-team/seats.json"
export FT_TICK_PIDFILE="$ROOT/tick.pid" FT_TICK_STAMP_PREFIX="$ROOT/stamp-"
export FT_TICK_STATE_DIR="$ROOT/.fable-team/state/tick"
export FT_TICK_MBOX="$ROOT/.fable-team/comm/mbox.sh"
export FT_TICK_TEAMMAIN_BIN="$TOOL"
# 이 시험은 teammain 한 칸만 본다 — 다른 바퀴 단계는 전부 끈다(로그 줄 수를 정확히 세기 위해)
export FT_TICK_WATCH_SAMPLE=0 FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 \
  FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 \
  FT_TICK_API_OUTAGE=0 FT_TICK_ACCT_PAUSE=0 FT_MODEL_SWAP=0 FT_TICK_WT_SWEEP=0 \
  FT_TICK_DRIFT=0 FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 \
  FT_TICK_CARD_ASSIGN=0 FT_TICK_LAUNCHD=0 FT_TICK_UNPUSHED=0 FT_TICK_NEWS_LEDGER=0 \
  FT_TICK_NEWS_WATCH=0 FT_TICK_ACCT=0 FT_TICK_ACCT_POST=0 FT_TICK_ACCT_NOTIFY=0
FAIL=0
ok()   { echo "  ok $1"; }
bad()  { echo "  FAIL $1"; FAIL=$(( FAIL + 1 )); }
calls() { cat "$CALLS" 2>/dev/null | grep -c . ; }
run() { bash "$TICK" --once > "$TMP/out" 2>&1; echo $?; }          # run → rc · 출력은 $TMP/out
stamp_at() { printf '%s\n' "$1" > "$STAMP"; }                       # stamp 를 «$1 초 전» 으로

# ── T1/M1 — 600초 안 두 번째 바퀴 = 호출 0 ──
: > "$CALLS"; stamp_at "$(date +%s)"; printf 'ok\n' > "$MODEF"
rc="$(run)"
[ "$rc" = 0 ] || bad "M1 tick rc=$rc (기대 0)"
[ "$(calls)" = 0 ] && ok "M1 600초 안 = 호출 0" || bad "M1 호출 $(calls)회 (기대 0)"

# ── T1/M2 — 600초 지나면 1회 + rc0 로그 1줄 ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"
rc="$(run)"
[ "$(calls)" = 1 ] && ok "M2 600초 경과 = 호출 1회" || bad "M2 호출 $(calls)회 (기대 1)"
grep -q 'render --all' "$CALLS" && ok "M2 인자 = render --all" || bad "M2 인자 어긋남: $(cat "$CALLS")"
grep -q 'TEAMMAIN render rc=0' "$TMP/out" && ok "M2 rc0 로그 1줄" || bad "M2 rc0 로그 없음"

# ── T4 — --dry-run = 실행 0 · DRY 1줄 ──
: > "$CALLS"; stamp_at "$(date +%s)"
bash "$TICK" --once --dry-run > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "T4 dry-run 실행 0" || bad "T4 dry-run 인데 $(calls)회 실행"
[ "$(grep -c 'DRY kind=teammain' "$TMP/out")" = 1 ] && ok "T4 DRY teammain 1줄" || bad "T4 DRY 줄 $(grep -c 'DRY kind=teammain' "$TMP/out")개"

# ── T2/M3 — render rc1 → ERROR 1줄 · 바퀴 계속 · stamp 씀(다음 간격 뒤 재시도) ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"; printf 'fail\n' > "$MODEF"
rc="$(run)"
[ "$rc" = 0 ] && ok "M3 바퀴 계속 rc=0" || bad "M3 tick rc=$rc (기대 0 — 실패해도 바퀴는 계속)"
[ "$(grep -c 'ERROR teammain: render rc=1' "$TMP/out")" = 1 ] && ok "M3 ERROR 1줄" || bad "M3 ERROR 줄 $(grep -c 'ERROR teammain: render rc=1' "$TMP/out")개"
[ "$(calls)" = 1 ] && ok "M3 호출 1회" || bad "M3 호출 $(calls)회 (기대 1)"
: > "$CALLS"; rc="$(run)"      # stamp 를 썼으므로 바로 다음 바퀴는 재시도 0
[ "$(calls)" = 0 ] && ok "M3 stamp 씀 = 다음 간격까지 재시도 0" || bad "M3 같은 600초 안 재시도 $(calls)회"

# ── T2/M4 — render 8초 → timeout rc124 ERROR ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"; printf 'slow\n' > "$MODEF"
rc="$(run)"
[ "$(grep -c 'ERROR teammain: render rc=124' "$TMP/out")" = 1 ] && ok "M4 timeout rc124 ERROR 1줄" || bad "M4 rc124 ERROR $(grep -c 'ERROR teammain: render rc=124' "$TMP/out")개"
[ "$rc" = 0 ] && ok "M4 바퀴 계속 rc=0" || bad "M4 tick rc=$rc (기대 0)"

# ── T3/M5 — 도구 없음 = WARN 1줄 · 간격 안 반복 0 ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"; printf 'ok\n' > "$MODEF"
FT_TICK_TEAMMAIN_BIN="$TMP/없는도구.sh" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(grep -c 'WARN teammain: 도구 없음' "$TMP/out")" = 1 ] && ok "M5 도구 없음 WARN 1줄" || bad "M5 WARN $(grep -c 'WARN teammain: 도구 없음' "$TMP/out")개"
FT_TICK_TEAMMAIN_BIN="$TMP/없는도구.sh" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(grep -c 'WARN teammain: 도구 없음' "$TMP/out")" = 0 ] && ok "M5 두 번째 바퀴 WARN 0(반복 안 함)" || bad "M5 WARN 반복됨"

# ── T1/M6 — FT_TICK_TEAMMAIN_SEC=0 → 호출 0 ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"
FT_TICK_TEAMMAIN_SEC=0 bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "M6 0 = 끔(호출 0)" || bad "M6 끔인데 $(calls)회 호출"

# ── 가드 — 팀 명단(design/TEAMS.md) 없는 루트 = 렌더 대상 0 · 조용히 skip(실 프로젝트 오염 방지) ──
: > "$CALLS"; stamp_at "$(( $(date +%s) - 700 ))"
FT_TEAMS_MD="$TMP/없는명단.md" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "가드 명단 없음 = 호출 0" || bad "가드 명단 없는데 $(calls)회 호출"

if [ "$FAIL" = 0 ]; then echo "PASS R1320 ft-tick 팀 메인 render 주기 호출"; exit 0; fi
echo "FAIL R1320 — $FAIL 건"; exit 1
