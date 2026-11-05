#!/usr/bin/env bash
# R1320 — ft-tick 이 600초마다 팀 메인 파일을 «팀마다» 다시 그린다 (지시 16 · 판정 3224 · REWORK r1).
#   계약 T1 · T2'(팀별 render <팀> timeout 7 · 실패 팀만 ERROR 1줄 · 목록 = ft_team_lib.team_names) · T3 · T4 / 반례 M1~M9.
#   실 launchd·실 STATE 렌더 0 — 가짜 ft-team-main.sh(render 만) + 임시 stamp 폴더 + --once 만 쓴다.
#   팀 목록은 «진짜» 경로를 태운다: 임시 루트 design/TEAMS.md → ft_team_lib.team_names(가짜 아님).
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
printf '{"_version":1}\n' > "$ROOT/.fable-team/seats.json"
printf '#!/bin/sh\nexit 0\n' > "$ROOT/.fable-team/comm/mbox.sh"
STAMP="$ROOT/.fable-team/state/teammain.last"   # r2: 표식은 데이터 루트 상태 폴더(STAMP_PREFIX 아님)
LOCK="$ROOT/.fable-team/state/teammain.lock"    # r2: 잠금 = mkdir 원자
CALLS="$TMP/calls"; MODEF="$TMP/mode"; SLOWF="$TMP/slow-team"
TOOL="$TMP/ft-team-main.sh"
: > "$CALLS"; printf 'ok\n' > "$MODEF"; printf 'beta\n' > "$SLOWF"
cat > "$TOOL" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "list" ]; then echo "이 시험은 목록을 가짜로 만들지 않는다" >&2; exit 9; fi
printf '%s\n' "$*" >> "$FAKE_TEAMMAIN_CALLS"        # render <팀> 만 기록한다
team="${2:-}"
case "$(cat "$FAKE_TEAMMAIN_MODE" 2>/dev/null)" in
  fail) echo "render failed $team" >&2; exit 1;;
  slow) exec sleep 8;;                              # timeout 7 이 끊는지(M4) — exec 라 TERM 이 sleep 에 바로 간다
  hold) exec sleep 1;;                              # M9b: 잠금을 잡은 채 잠시 버틴다(동시 데몬 경합)
  one-slow) [ "$team" = "$(cat "$FAKE_TEAMMAIN_SLOW_TEAM")" ] && exec sleep 8; echo "rendered $team"; exit 0;;
  *) echo "rendered $team"; exit 0;;
esac
SH
teams_md() {   # teams_md <팀…> — 현역 행만 있는 최소 TEAMS.md(진짜 ft_team_lib 파서가 읽는다)
  { printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n'
    local t; for t in "$@"; do printf '| %s | `design/teams/%s/` | byz-%s-master-claude | 현역 |\n' "$t" "$t" "$t"; done
  } > "$ROOT/design/TEAMS.md"; }
teams_md_broken() { printf '| 팀 | 폴더 | 오케 좌석 계열 | 상태 |\n|---|---|---|---|\n| alpha | `design/teams/alpha/` | x | 이상함 |\n' > "$ROOT/design/TEAMS.md"; }
teams_md alpha
export FAKE_TEAMMAIN_CALLS="$CALLS" FAKE_TEAMMAIN_MODE="$MODEF" FAKE_TEAMMAIN_SLOW_TEAM="$SLOWF"
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
now_at() { stamp_at "$(( $(date +%s) - $1 ))"; }

# ── T1/M1 — 600초 안 두 번째 바퀴 = 호출 0 ──
: > "$CALLS"; now_at 0; printf 'ok\n' > "$MODEF"
rc="$(run)"
[ "$rc" = 0 ] || bad "M1 tick rc=$rc (기대 0)"
[ "$(calls)" = 0 ] && ok "M1 600초 안 = 호출 0" || bad "M1 호출 $(calls)회 (기대 0)"

# ── T1/M2 — 600초 지나면 1회 · «render <팀>» 로 부른다 ──
: > "$CALLS"; now_at 700
rc="$(run)"
[ "$(calls)" = 1 ] && ok "M2 600초 경과 = 호출 1회" || bad "M2 호출 $(calls)회 (기대 1)"
grep -q '^render alpha$' "$CALLS" && ok "M2 인자 = render <팀>" || bad "M2 인자 어긋남: $(cat "$CALLS")"
grep -q 'TEAMMAIN render ok=1 fail=0' "$TMP/out" && ok "M2 요약 로그 1줄(ok=1 fail=0)" || bad "M2 요약 로그 없음"

# ── T4 — --dry-run = 실행 0 · DRY 1줄 ──
: > "$CALLS"; now_at 0
bash "$TICK" --once --dry-run > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "T4 dry-run 실행 0" || bad "T4 dry-run 인데 $(calls)회 실행"
[ "$(grep -c 'DRY kind=teammain' "$TMP/out")" = 1 ] && ok "T4 DRY teammain 1줄" || bad "T4 DRY 줄 $(grep -c 'DRY kind=teammain' "$TMP/out")개"

# ── T2'/M3 — render 실패 → 그 팀만 ERROR 1줄 · 바퀴 계속 · stamp 씀(다음 간격 뒤 재시도) ──
: > "$CALLS"; now_at 700; printf 'fail\n' > "$MODEF"
rc="$(run)"
[ "$rc" = 0 ] && ok "M3 바퀴 계속 rc=0" || bad "M3 tick rc=$rc (기대 0 — 실패해도 바퀴는 계속)"
[ "$(grep -c 'ERROR teammain: alpha rc=1' "$TMP/out")" = 1 ] && ok "M3 ERROR 1줄(그 팀)" || bad "M3 ERROR 줄 $(grep -c 'ERROR teammain: alpha rc=1' "$TMP/out")개"
grep -q 'TEAMMAIN render ok=0 fail=1' "$TMP/out" && ok "M3 요약 로그(ok=0 fail=1)" || bad "M3 요약 로그 없음"
[ "$(calls)" = 1 ] && ok "M3 호출 1회" || bad "M3 호출 $(calls)회 (기대 1)"
: > "$CALLS"; rc="$(run)"      # stamp 를 썼으므로 바로 다음 바퀴는 재시도 0
[ "$(calls)" = 0 ] && ok "M3 stamp 씀 = 다음 간격까지 재시도 0" || bad "M3 같은 600초 안 재시도 $(calls)회"

# ── T2'/M4 — 한 팀이 8초 → timeout rc124 ERROR · 바퀴 계속 ──
: > "$CALLS"; now_at 700; printf 'slow\n' > "$MODEF"
rc="$(run)"
[ "$(grep -c 'ERROR teammain: alpha rc=124' "$TMP/out")" = 1 ] && ok "M4 timeout rc124 ERROR 1줄" || bad "M4 rc124 ERROR $(grep -c 'ERROR teammain: alpha rc=124' "$TMP/out")개"
[ "$rc" = 0 ] && ok "M4 바퀴 계속 rc=0" || bad "M4 tick rc=$rc (기대 0)"

# ── T2'/M7 — 팀 3개 중 1개(beta)만 8초 → 나머지 2팀 갱신 · ERROR 1줄 · 바퀴 계속 ──
: > "$CALLS"; now_at 700; printf 'one-slow\n' > "$MODEF"; teams_md alpha beta gamma
rc="$(run)"
[ "$rc" = 0 ] && ok "M7 바퀴 계속 rc=0" || bad "M7 tick rc=$rc (기대 0)"
[ "$(calls)" = 3 ] && ok "M7 3팀 모두 시도(끊긴 팀이 나머지를 막지 않음)" || bad "M7 시도 $(calls)회 (기대 3): $(tr '\n' ' ' < "$CALLS")"
grep -q '^render alpha$' "$CALLS" && grep -q '^render gamma$' "$CALLS" && ok "M7 나머지 2팀 갱신 호출" || bad "M7 나머지 팀 호출 빠짐: $(tr '\n' ' ' < "$CALLS")"
[ "$(grep -c 'ERROR teammain: beta rc=124' "$TMP/out")" = 1 ] && ok "M7 ERROR = 끊긴 그 팀 1줄" || bad "M7 ERROR 줄 $(grep -c 'ERROR teammain: beta rc=124' "$TMP/out")개"
[ "$(grep -c 'ERROR teammain:' "$TMP/out")" = 1 ] && ok "M7 ERROR 총 1줄" || bad "M7 ERROR 총 $(grep -c 'ERROR teammain:' "$TMP/out")줄"
grep -q 'TEAMMAIN render ok=2 fail=1' "$TMP/out" && ok "M7 요약 ok=2 fail=1" || bad "M7 요약 어긋남"
teams_md alpha

# ── T2'/M8 — 목록 판정 불가(팀 명단 깨짐) → ERROR 1줄 · 렌더 0 ──
: > "$CALLS"; now_at 700; printf 'ok\n' > "$MODEF"; teams_md_broken
rc="$(run)"
[ "$(calls)" = 0 ] && ok "M8 목록 실패 = 렌더 0" || bad "M8 목록 실패인데 $(calls)회 렌더"
[ "$(grep -c 'ERROR teammain: 목록 판정 불가' "$TMP/out")" = 1 ] && ok "M8 목록 ERROR 1줄" || bad "M8 목록 ERROR $(grep -c 'ERROR teammain: 목록 판정 불가' "$TMP/out")개"
[ "$rc" = 0 ] && ok "M8 바퀴 계속 rc=0" || bad "M8 tick rc=$rc (기대 0)"
teams_md alpha

# ── T3/M5 — 도구 없음 = WARN 1줄 · 간격 안 반복 0 ──
: > "$CALLS"; now_at 700
FT_TICK_TEAMMAIN_BIN="$TMP/없는도구.sh" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(grep -c 'WARN teammain: 도구 없음' "$TMP/out")" = 1 ] && ok "M5 도구 없음 WARN 1줄" || bad "M5 WARN $(grep -c 'WARN teammain: 도구 없음' "$TMP/out")개"
FT_TICK_TEAMMAIN_BIN="$TMP/없는도구.sh" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(grep -c 'WARN teammain: 도구 없음' "$TMP/out")" = 0 ] && ok "M5 두 번째 바퀴 WARN 0(반복 안 함)" || bad "M5 WARN 반복됨"

# ── T1/M6 — FT_TICK_TEAMMAIN_SEC=0 → 호출 0 ──
: > "$CALLS"; now_at 700
FT_TICK_TEAMMAIN_SEC=0 bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "M6 0 = 끔(호출 0)" || bad "M6 끔인데 $(calls)회 호출"

# ── T2' 바퀴 시간 — 마감 3초 안이면 남은 팀은 다음 간격(ERROR 0 · 로그 1줄) ──
: > "$CALLS"; now_at 700; teams_md alpha beta gamma
FT_TICK_DEADLINE="$(( $(date +%s) + 2 ))" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "바퀴 마감 2초 = 남은 팀 다음 간격(호출 0)" || bad "바퀴 마감인데 $(calls)회 호출"
[ "$(grep -c '남은팀 다음 간격' "$TMP/out")" = 1 ] && ok "바퀴 마감 로그 1줄" || bad "바퀴 마감 로그 $(grep -c '남은팀 다음 간격' "$TMP/out")개"
[ "$(grep -c 'ERROR teammain:' "$TMP/out")" = 0 ] && ok "바퀴 마감 = ERROR 0" || bad "바퀴 마감인데 ERROR 발생"
teams_md alpha

# ── T1/M9 — 같은 루트 데몬 2개(STAMP_PREFIX 다름) 같은 바퀴 → render 합 1 ──
: > "$CALLS"; rm -f "$STAMP"; printf 'ok\n' > "$MODEF"; teams_md alpha
FT_TICK_STAMP_PREFIX="$ROOT/pa-" bash "$TICK" --once > "$TMP/a.out" 2>&1
FT_TICK_STAMP_PREFIX="$ROOT/pb-" bash "$TICK" --once > "$TMP/b.out" 2>&1
[ "$(calls)" = 1 ] && ok "M9 접두 다른 데몬 2개 = render 합 1" || bad "M9 합 $(calls)회 (기대 1 — 표식은 데이터 루트)"

# ── T1/M9b — 동시에 도는 2데몬: 잠금(mkdir)이 겹저리를 막는다 ──
: > "$CALLS"; rm -f "$STAMP"; rm -rf -- "$LOCK"; printf 'hold\n' > "$MODEF"
FT_TICK_STAMP_PREFIX="$ROOT/pc-" bash "$TICK" --once > "$TMP/a.out" 2>&1 & apid=$!
i=0; while [ "$i" -lt 300 ] && [ ! -s "$CALLS" ]; do sleep 0.05; i=$(( i + 1 )); done   # 첫 렌더가 시작(잠금 잡힘)했을 때
FT_TICK_STAMP_PREFIX="$ROOT/pd-" FT_TICK_PIDFILE="$ROOT/tickB.pid" bash "$TICK" --once > "$TMP/b.out" 2>&1
wait "$apid"
[ "$(calls)" = 1 ] && ok "M9b 동시 2데몬 = 잠금으로 합 1" || bad "M9b 합 $(calls)회 (기대 1 — 잠금)"
grep -q '잠금 보유 중' "$TMP/b.out" && ok "M9b 진 쪽 log 1줄" || bad "M9b 진 쪽 log 없음"
[ ! -d "$LOCK" ] && ok "M9b 끝나면 잠금 지움" || bad "M9b 잠금이 남았다 $LOCK"
printf 'ok\n' > "$MODEF"

# ── T1/M10 (r1391) — «at» 없는 잠금 폴더(도중에 죽은 틱이 남긴 것)도 낡음으로 깨고 렌더한다 · 새 폴더는 안 깬다 ──
: > "$CALLS"; now_at 700; printf 'ok\n' > "$MODEF"; rm -rf -- "$LOCK"; mkdir -p "$LOCK"; touch -t "$(date -v-60M '+%Y%m%d%H%M')" "$LOCK"
bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 1 ] && ok "M10 at 없는 낡은 잠금 → 깨고 렌더 1" || bad "M10 호출 $(calls)회 (기대 1 — 빈 잠금)"
grep -q '낡은 잠금' "$TMP/out" && ok "M10 깼다는 log 1줄" || bad "M10 log 없음: $(cat "$TMP/out")"
: > "$CALLS"; now_at 700; rm -rf -- "$LOCK"; mkdir -p "$LOCK"
bash "$TICK" --once > "$TMP/out" 2>&1
{ [ "$(calls)" = 0 ] && grep -q '잠금 보유 중' "$TMP/out"; } && ok "M10b 방금 만든 빈 잠금 = 안 깨고 skip" || bad "M10b 호출 $(calls)회 · $(tail -1 "$TMP/out")"
rm -rf -- "$LOCK"

# ── 가드 — 팀 명단 파일 자체가 없는 루트 = 렌더 대상 0 · 조용히 skip(남의 루트를 렌더하지 않는다) ──
: > "$CALLS"; now_at 700
FT_TEAMS_MD="$TMP/없는명단.md" bash "$TICK" --once > "$TMP/out" 2>&1
[ "$(calls)" = 0 ] && ok "가드 명단 없음 = 호출 0" || bad "가드 명단 없는데 $(calls)회 호출"

if [ "$FAIL" = 0 ]; then echo "PASS R1320 ft-tick 팀 메인 render 팀별 주기 호출"; exit 0; fi
echo "FAIL R1320 — $FAIL 건"; exit 1
