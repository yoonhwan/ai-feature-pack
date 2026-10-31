#!/usr/bin/env bash
# test_tick_pass_steps_r1253.sh — r1253: ft-tick 바퀴(pass)의 «실행한 단계» 시각·소요 초 표식 + 완주 요약 줄 + 끊김 ERROR 보강(측정만).
#   R1 완주: «pass steps:» 줄 = 실행 항목만 · 코드 순서 · last.tsv 행 수 = 실행 항목 수 · cur 없음 (좌석 0 = 조기 반환 24항목 · 좌석 1 = 25항목)
#   R2 느린 단계 3초(wt-sweep 대역 sleep) → 완주 · steps 줄에 그 단계 3±1
#   R3 느린 단계 8초(뉴스 원장 대역 sleep) · PASS_MAX=6 → 끊김 · ERROR 줄에 끊긴 단계·이 바퀴 최대·직전 완주 최대 · last.tsv 바이트 불변 · done 임시 0 · 다음 바퀴가 cur 삭제
#   R4 첫 바퀴 끊김 = 직전 완주 «?(기록 없음)» · 낡은 cur(다른 바퀴 id) = «끊긴 단계 ?»
#   R5 FT_TICK_STEPS=0/1 대조: 끔 = 표식·요약·ERROR 보강 0 · 로그 사건 순서 같음 · rc 같음 · 실 단계(wt-sweep)가 느릴 때 켬 = «끊긴 단계 sweep_wt»
#   R6 --dry-run: «DRY kind=steps n=<실행 항목 수>» 1줄 · 표식 쓰기 0
#   변이 1(cur 표식 쓰기 제거) → R3 «끊긴 단계 ?» = FAIL · 변이 2(자식이 단계마다 last.tsv 직접 갱신) → R3 last.tsv 바뀜 = FAIL
# 시험 전용 env 0(STEP_FAKE 없음): 실 단계 함수 그대로 · 끄기 env + 외부 도구 대역(wt-sweep · 뉴스 원장 = sleep) · 가상 시각 FT_TICK_NOW_BASE(기준 + 실제 경과) · 실 좌석·실 네트워크 0.
#   인터프리터 = /bin/bash(ft-tick 셔뱅 · macOS 3.2). 허용 오차: 경과초 ±2(폴링 1초 + 부하). R1253_TICK=<사본> 으로 변이판을 돌린다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC_TICK="${R1253_TICK:-$HERE/../bin/ft-tick.sh}"
SRC_BIN="$(cd -- "$(dirname -- "$SRC_TICK")" && pwd)"
SHB=/bin/bash
TMP="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$TMP"' EXIT   # 병렬로 띄운 칸(r4·r5cut·변이)이 시험 끝에 남지 않게(r1234)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

EXP22="watch_sample_tick autonomy_expire leak_watch hil_watch live_snapshot dead_seat_watch idle_watch idle_long_watch outage_watch acct_pause_watch model_swap stall sweep_wt drift_watch raised_watch renamed_watch queue_full_watch queue_watch card_assign_watch launchd_watch unpushed_daily news_ledger"
EXP_EARLY="$EXP22 prep acct_notice"          # 좌석 0 = prep 뒤 조기 반환(fire 미실행)
EXP_FULL="$EXP22 prep fire acct_notice"      # 좌석 1

# 도구 사본 폴더: ft-tick(원본 또는 변이판) + 형제 도구 심링크 + 뉴스 원장 대역
mkbin() {   # $1 = ft-tick 소스 → $TMP/bin-<n> 경로를 stdout
  local d; d="$(mktemp -d "$TMP/bin.XXXXXX")"; local f
  for f in "$SRC_BIN"/*; do [ "$(basename "$f")" = ft-tick.sh ] || [ "$(basename "$f")" = ft-news-ledger.sh ] || ln -s "$f" "$d/$(basename "$f")"; done
  cp "$1" "$d/ft-tick.sh"
  cat > "$d/ft-news-ledger.sh" <<'EOF'
#!/bin/bash
# 뉴스 원장 대역: FAKE_CUR_INJECT 가 있으면 낡은 cur 표식(다른 바퀴 id)을 덮어쓴 뒤 FAKE_NEWS_SLEEP 초 쉰다.
[ -z "${FAKE_CUR_INJECT:-}" ] || printf 'old-round\tnews_ledger\t%s\t-\t0\n' "$(date +%s)" > "$FAKE_CUR_INJECT"
# FAKE_TORN=<cur.log 경로>: 현재 바퀴 id 의 완전한 줄 1개 + 개행 없는 꼬리 1개를 덧붙인다(끊김 도중 반쪽 쓰기 대역).
if [ -n "${FAKE_TORN:-}" ]; then
  e="$(date +%s)"; printf '%s\tfake_step\t%s\t-\t0\t%s\n' "$FT_TICK_PASS_ID" "$e" "$e" >> "$FAKE_TORN"
  printf '%s\tpartial_step\t17' "$FT_TICK_PASS_ID" >> "$FAKE_TORN"
fi
sleep "${FAKE_NEWS_SLEEP:-0}"
exit 0
EOF
  cat > "$d/sweep.sh" <<'EOF'
#!/bin/bash
sleep "${FAKE_SWEEP_SLEEP:-0}"
echo "sweep 계획 0"
EOF
  chmod +x "$d/ft-news-ledger.sh" "$d/sweep.sh"; echo "$d"
}
printf '#!/bin/bash\nexit 0\n' > "$TMP/mbox.sh"; chmod +x "$TMP/mbox.sh"
echo '{"_master": null}' > "$TMP/seats-0.json"
echo '{"_master": "m1", "m1": {"role": "master", "tick": "ft-master-tick"}}' > "$TMP/seats-1.json"
printf '{ broken json\n' > "$TMP/seats-bad.json"

# run_tick <상태폴더이름> <bin폴더> <seats> [env=값 …] -- [옵션…] → 로그 $TMP/<이름>.log · rc $TMP/<이름>.rc
run_tick() {
  local n="$1" bd="$2" seats="$3"; shift 3
  local envs=() opts=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "${1:-}" != -- ] || shift
  opts=("${@:-}")
  mkdir -p "$TMP/$n/root"
  ( cd "$TMP/$n" && exec env FT_TICK_SEATS="$seats" FT_TICK_MBOX="$TMP/mbox.sh" FT_TICK_PIDFILE="$TMP/$n/tick.pid" \
      FT_ROOT="$TMP/$n/root" FT_TICK_CARD_ASSIGN=0 \
      FT_TICK_STATE_DIR="$TMP/$n/state" FT_TICK_STAMP_PREFIX="$TMP/$n/p-" FT_TICK_LOOP_SEC=1 FT_TICK_SEAT_STATUS="$TMP/$n/none" \
      FT_TICK_NOW_BASE=1800000000 FT_TICK_WT_SWEEP=1 FT_TICK_WT_SWEEP_BIN="$bd/sweep.sh" \
      FT_TICK_AUTONOMY=0 FT_TICK_LEAK_REAP=0 FT_TICK_HIL=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_RESUME=0 \
      FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_TICK_API_OUTAGE=0 FT_MODEL_SWAP=0 FT_TICK_DRIFT=0 \
      FT_TICK_RAISED=0 FT_TICK_RENAMED=0 FT_TICK_QUEUE_FULL=0 FT_TICK_QUEUE=0 FT_TICK_LAUNCHD=0 \
      FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 \
      ${envs[@]+"${envs[@]}"} \
      timeout 45 "$SHB" "$bd/ft-tick.sh" ${opts[@]+"${opts[@]}"} > "$TMP/$n.log" 2>&1 ); echo $? > "$TMP/$n.rc"
}
SD() { echo "$TMP/$1/state/tick-steps"; }
steps_line() { grep -m1 'pass steps:' "$TMP/$1.log" || true; }
names_of() { local l="${1#*pass steps: }" it out=""; for it in $l; do case "$it" in total=*) ;; *) out="$out ${it%%=*}";; esac; done; echo "${out# }"; }
val_of() { local l="${1#*pass steps: }" it; for it in $l; do [ "${it%%=*}" = "$2" ] && { echo "${it#*=}"; return; }; done; echo ""; }
rows() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
mutate() {   # mutate <원본> <변이본> <awk 프로그램> — 바뀌지 않으면 실패
  awk "$3" "$1" > "$2" && ! cmp -s "$1" "$2"
}

/bin/bash -n "$SRC_TICK" && ok "bash -n (/bin/bash)" || bad "bash -n"
BD="$(mkbin "$SRC_TICK")"
# 느린 칸(끊김 3초·6초)은 병렬로 미리 돌려 한 회차 시간을 줄인다(시험 상한 70초) — 단언은 wait 뒤에.
( run_tick r4a "$BD" "$TMP/seats-0.json" FAKE_NEWS_SLEEP=8 FT_TICK_NEWS_LEDGER=1 FT_TICK_PASS_MAX_SEC=3 -- --once ) &
( run_tick r4b "$BD" "$TMP/seats-0.json" FAKE_NEWS_SLEEP=8 FT_TICK_NEWS_LEDGER=1 FT_TICK_PASS_MAX_SEC=3 FAKE_CUR_INJECT="$TMP/r4b/state/tick-steps/cur.log" -- --once ) &
( run_tick r4c "$BD" "$TMP/seats-0.json" FAKE_NEWS_SLEEP=8 FT_TICK_NEWS_LEDGER=1 FT_TICK_PASS_MAX_SEC=3 FAKE_TORN="$TMP/r4c/state/tick-steps/cur.log" -- --once ) &
( run_tick r5cut1 "$BD" "$TMP/seats-0.json" FT_TICK_STEPS=1 FAKE_SWEEP_SLEEP=30 FT_TICK_PASS_MAX_SEC=3 -- --once ) &
( run_tick r5cut0 "$BD" "$TMP/seats-0.json" FT_TICK_STEPS=0 FAKE_SWEEP_SLEEP=30 FT_TICK_PASS_MAX_SEC=3 -- --once ) &
# 변이판 R2/R3 도 병렬(단언 = FAIL 이어야 함 · 결과는 $TMP/<m>.res / .reason). cell_r2_r3 는 원본에서 이미 통과해야 의미가 있다(아래 R2/R3 칸이 그 기준판).
run_mut() { local m="$1" bd="$2"; ( cell_r2_r3 "$m" "$bd"; echo $? > "$TMP/$m.res"; echo "${REASON:-}" > "$TMP/$m.reason" ) & }

# ── R1 완주 ─────────────────────────────────────────────────────────────────────────────────────
cell_r1() {   # cell_r1 <이름> <bin> <seats> <기대 이름 목록> → 0 PASS (REASON)
  local n="$1" bd="$2" seats="$3" exp="$4" line got v it bigv=0
  REASON=""
  run_tick "$n" "$bd" "$seats" -- --once
  line="$(steps_line "$n")"
  [ -n "$line" ] || { REASON="pass steps 줄 0 (로그: $(tail -2 "$TMP/$n.log" | tr '\n' ' '))"; return 1; }
  got="$(names_of "$line")"
  [ "$got" = "$exp" ] || { REASON="단계 이름·순서 불일치: [$got]"; return 1; }
  for it in ${line#*pass steps: }; do
    case "$it" in total=*) continue;; esac
    v="${it#*=}"
    case "$v" in ''|*[!0-9]*) REASON="초 값 숫자 아님: $v"; return 1;; esac
    [ "$v" -le 2 ] || bigv=1
  done
  [ "$bigv" = 0 ] || { REASON="대역 단계가 2초 넘음: $line"; return 1; }
  [ "$(rows "$(SD "$n")/last.tsv")" = "$(echo $exp | wc -w | tr -d ' ')" ] || { REASON="last.tsv 행 수 $(rows "$(SD "$n")/last.tsv") ≠ $(echo $exp | wc -w | tr -d ' ')"; return 1; }
  [ ! -e "$(SD "$n")/cur.log" ] || { REASON="cur.log 남음"; return 1; }
  ls "$(SD "$n")"/done-* >/dev/null 2>&1 && { REASON="done 임시 남음"; return 1; }
  [ "$(cat "$TMP/$n.rc")" = 0 ] || { REASON="--once rc=$(cat "$TMP/$n.rc")"; return 1; }
  return 0
}
if cell_r1 r1a "$BD" "$TMP/seats-0.json" "$EXP_EARLY"; then ok "R1 좌석 0 = 조기 반환 24항목 · 코드 순서 · last.tsv 24행 · cur 0 · done 0"; else bad "R1 좌석 0: $REASON"; fi
if cell_r1 r1b "$BD" "$TMP/seats-1.json" "$EXP_FULL"; then ok "R1 좌석 1 = prep·fire 포함 25항목 · last.tsv 25행"; else bad "R1 좌석 1: $REASON"; fi
grep -q 'no active seat with tick' "$TMP/r1a.log" && ok "R1 좌석 0 조기 반환 로그(원래 줄 그대로)" || bad "R1 조기 반환 로그 없음"

# ── R2 느린 단계 3초 → 완주 → R3 끊김(같은 상태 폴더) ─────────────────────────────────────────────
cell_r2_r3() {   # cell_r2_r3 <이름> <bin> → R2 + R3 (REASON)
  local n="$1" bd="$2" line v E S cs p0 f lastcur
  REASON=""
  run_tick "$n" "$bd" "$TMP/seats-0.json" FAKE_SWEEP_SLEEP=3 FT_TICK_PASS_MAX_SEC=12 -- --once   # R2 상한은 부하 여유(병렬 칸 동시 실행) — R3 가 카드값 6
  line="$(steps_line "$n")"; v="$(val_of "$line" sweep_wt)"
  case "$v" in 2|3|4) ;; *) REASON="R2 sweep_wt=$v (기대 3±1) · $line"; return 1;; esac
  cp "$(SD "$n")/last.tsv" "$TMP/$n.last0"
  L0="$(date +%s)"
  run_tick "$n" "$bd" "$TMP/seats-0.json" FAKE_NEWS_SLEEP=8 FT_TICK_NEWS_LEDGER=1 FT_TICK_PASS_MAX_SEC=6 -- --once
  f="$(grep -m1 'ERROR pass over 6s' "$TMP/$n.log")"
  [ -n "$f" ] || { REASON="R3 ERROR 줄 0"; return 1; }
  case "$f" in *'끊긴 단계 news_ledger '*) ;; *) REASON="R3 끊긴 단계 이름 불일치: $f"; return 1;; esac
  E="$(echo "$f" | sed -n 's/.*끊긴 단계 news_ledger \([0-9]*\)s.*/\1/p')"
  lastcur="$(tail -1 "$(SD "$n")/cur.log" 2>/dev/null)"; cs="$(echo "$lastcur" | awk -F'\t' '{print $3}')"; p0="$(echo "$lastcur" | awk -F'\t' '{print $6}')"
  case "$cs$p0" in ''|*[!0-9]*) REASON="R3 cur 표식 시작·바퀴 시작 칸 없음: [$cs][$p0]"; return 1;; esac
  S=$(( cs - p0 )); [ "$S" -ge 0 ] || S=0   # 앞 단계 합 = 단계 시작 epoch − 바퀴 시작 epoch(같은 표식 두 칸의 차)
  [ -n "$E" ] && [ "$E" -ge $(( 6 - S - 2 )) ] || { REASON="R3 경과 ${E:-?}s < 6−앞단계합(${S})−2"; return 1; }
  case "$f" in *'이 바퀴 최대 '*) ;; *) REASON="R3 «이 바퀴 최대» 없음: $f"; return 1;; esac
  case "$f" in *'직전 완주 최대 sweep_wt '[234]s*) ;; *) REASON="R3 «직전 완주 최대 sweep_wt» 불일치: $f"; return 1;; esac
  cmp -s "$TMP/$n.last0" "$(SD "$n")/last.tsv" || { REASON="R3 끊긴 바퀴에 last.tsv 바뀜"; return 1; }
  ls "$(SD "$n")"/done-* >/dev/null 2>&1 && { REASON="R3 done 임시 남음"; return 1; }
  [ "$(echo "$lastcur" | cut -f2)" = news_ledger ] || { REASON="R3 cur 표식 이름 ≠ news_ledger"; return 1; }
  grep -q 'pass steps:' "$TMP/$n.log" && { REASON="R3 끊긴 바퀴에 steps 줄이 나옴"; return 1; }
  # 다음 바퀴(완주)가 cur 삭제 + last.tsv 갱신
  run_tick "$n" "$bd" "$TMP/seats-0.json" FT_TICK_PASS_MAX_SEC=6 -- --once
  [ ! -e "$(SD "$n")/cur.log" ] || { REASON="R3 다음 바퀴 뒤 cur 남음"; return 1; }
  [ -n "$(steps_line "$n")" ] || { REASON="R3 다음 바퀴 steps 줄 0"; return 1; }
  return 0
}
if mutate "$SRC_TICK" "$TMP/m1.sh" 'index($0,"printf '"'"'%s") && index($0,"cur.log") { next } { print }'; then run_mut m1 "$(mkbin "$TMP/m1.sh")"; fi
if mutate "$SRC_TICK" "$TMP/m2.sh" '{ print } index($0,"STEP_NAMES+=(\"$_st_name\")") { print "  printf \"%s\\t%s\\n\" \"$_st_name\" \"$_st_d\" >> \"$STEP_DIR/last.tsv\" 2>/dev/null" }'; then run_mut m2 "$(mkbin "$TMP/m2.sh")"; fi
if cell_r2_r3 r23 "$BD"; then ok "R2 sweep_wt 3±1 · R3 끊김(이름·경과≥6−앞합−2·최대 2종·last.tsv 불변·done 0·다음 바퀴 cur 삭제)"; else bad "R2/R3: $REASON"; fi

# ── R4 첫 바퀴 끊김 · 낡은 cur ───────────────────────────────────────────────────────────────────
wait   # 위에서 병렬로 시작한 r4a·r4b·r5cut·변이 칸
f="$(grep -m1 'ERROR pass over 3s' "$TMP/r4a.log")"
case "$f" in *'끊긴 단계 news_ledger '*'직전 완주 최대 ?(기록 없음)'*) ok "R4 첫 바퀴 끊김 = 직전 완주 ?(기록 없음)";; *) bad "R4 첫 바퀴: $f";; esac
f="$(grep -m1 'ERROR pass over 3s' "$TMP/r4b.log")"
case "$f" in *'끊긴 단계 ? '*'이 바퀴 최대 ? '*) ok "R4 낡은 cur(다른 바퀴 id) = 끊긴 단계 ? · 이 바퀴 최대 ?";; *) bad "R4 낡은 cur: $f";; esac

f="$(grep -m1 'ERROR pass over 3s' "$TMP/r4c.log")"
case "$f" in *'끊긴 단계 fake_step '*) case "$f" in *partial_step*) bad "R4 개행 없는 꼬리를 읽음: $f";; *) ok "R4 cur.log 꼬리(개행 없음) 버림 · 마지막 완전한 줄만";; esac;; *) bad "R4 꼬리 칸: $f";; esac

# ── R5 켬/끔 대조 ───────────────────────────────────────────────────────────────────────────────
norm() { sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ?//g; s/pid=[0-9]+/pid=N/g' "$1" | grep -v 'pass steps:' | sed "s#$TMP/[^ /]*#T#g"; }
run_tick r5on  "$BD" "$TMP/seats-1.json" FT_TICK_STEPS=1 -- --once
run_tick r5off "$BD" "$TMP/seats-1.json" FT_TICK_STEPS=0 -- --once
if [ "$(norm "$TMP/r5on.log")" = "$(norm "$TMP/r5off.log")" ] && [ "$(cat "$TMP/r5on.rc")" = "$(cat "$TMP/r5off.rc")" ]; then ok "R5 켬/끔 로그 사건 순서·--once rc 같음(rc=$(cat "$TMP/r5on.rc"))"; else bad "R5 켬/끔 로그 다름: $(diff <(norm "$TMP/r5on.log") <(norm "$TMP/r5off.log") | head -4 | tr '\n' ' ')"; fi
[ ! -e "$(SD r5off)" ] || [ -z "$(ls "$(SD r5off)" 2>/dev/null)" ] && ok "R5 끔: 표식 0" || bad "R5 끔인데 표식: $(ls "$(SD r5off)")"
[ -z "$(steps_line r5off)" ] && ok "R5 끔: steps 줄 0" || bad "R5 끔인데 steps 줄"
[ -n "$(steps_line r5on)" ] && ok "R5 켬: steps 줄 있음" || bad "R5 켬인데 steps 줄 0"
for s in 1 0; do run_tick "r5bad$s" "$BD" "$TMP/seats-bad.json" FT_TICK_STEPS=$s -- --once; done
c1="$(grep -c 'ERROR pass failed rc=1' "$TMP/r5bad1.log")"; c0="$(grep -c 'ERROR pass failed rc=1' "$TMP/r5bad0.log")"
[ "$c1" = 1 ] && [ "$c0" = 1 ] && [ "$(cat "$TMP/r5bad1.rc")" = 0 ] && [ "$(cat "$TMP/r5bad0.rc")" = 0 ] && ok "R5 pass rc=1(명부 읽기 실패)이 켬·끔 모두 같은 ERROR 1줄 · --once 종료 0" || bad "R5 rc 대조 켬=$c1 끔=$c0"
f1="$(grep -m1 'ERROR pass over 3s' "$TMP/r5cut1.log")"; f0="$(grep -m1 'ERROR pass over 3s' "$TMP/r5cut0.log")"
case "$f1" in *'끊긴 단계 sweep_wt '*) ok "R5 켬: 실 단계(wt-sweep) 지연 → 끊긴 단계 sweep_wt";; *) bad "R5 켬 끊긴 단계: $f1";; esac
case "$f0" in *'바퀴 끊음('*) case "$f0" in *'끊긴 단계'*) bad "R5 끔인데 ERROR 보강: $f0";; *) ok "R5 끔: 끊김 ERROR 줄 원래 그대로(보강 0)";; esac;; *) bad "R5 끔 ERROR 줄 없음";; esac

# ── R6 DRY ───────────────────────────────────────────────────────────────────────────────────────
run_tick r6 "$BD" "$TMP/seats-0.json" -- --dry-run
n="$(grep -c '^DRY kind=steps n=' "$TMP/r6.log")"; l="$(grep -m1 '^DRY kind=steps n=' "$TMP/r6.log")"
[ "$n" = 1 ] && [ "$l" = "DRY kind=steps n=24" ] && ok "R6 --dry-run: «${l}» 1줄" || bad "R6 DRY 줄 ${n}개: ${l}"
[ -z "$(ls "$(SD r6)" 2>/dev/null)" ] && ok "R6 DRY 표식 쓰기 0" || bad "R6 DRY 표식 있음: $(ls "$(SD r6)")"

# ── 변이 ─────────────────────────────────────────────────────────────────────────────────────────
for m in m1 m2; do
  if [ -f "$TMP/$m.res" ] && [ "$(cat "$TMP/$m.res")" != 0 ]; then
    case "$(cat "$TMP/$m.reason")" in R3*) ok "변이 $m → R3 FAIL ($(cat "$TMP/$m.reason" | cut -c1-120))";; *) bad "변이 $m 가 R3 가 아닌 곳에서 실패(원인이 다름): $(cat "$TMP/$m.reason" | cut -c1-120)";; esac
  elif [ -f "$TMP/$m.res" ]; then bad "변이 $m 가 R2/R3 를 통과함 — 시험이 약하다"
  else bad "변이 $m 만들기 실패(대상 줄 없음)"; fi
done

echo "RESULT fail=$fail"
[ "$fail" -eq 0 ]
