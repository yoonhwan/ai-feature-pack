#!/usr/bin/env bash
# test_autonomy_preflight.sh — 자율 «켜기·시작»(r-autonomy-night-preflight · #1406 · 판정 1355·1359) 시험.
#   ①켜기 직전 인증 사전 점검(gcloud 2종 · 7초+재시도 1) ②끝 시각 인자(--until/--for) ③시작 장부.
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + PATH 앞 가짜 gcloud·gh 스텁 + 고정 시계(FT_NOW) — 실 gcloud·gh·상태 파일 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/scripts/fable-team-bin"; MIR="$ROOT/scripts/harness-install/fable-team/bin"
fail=0; n=0
ck() { n=$((n+1)); if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$2" <<<"$1"; }   # has "<출력>" "<정규식>"

suite() {  # <셸 경로>
  local SH="$1" T; T="$(mktemp -d)"; echo "== suite $SH"
  export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" HIL_DIR="$T"
  mkdir -p "$T/state" "$T/planner" "$T/stubs" "$T/nogc"
  # 가짜 gcloud — GC_USER·GC_ADC = ok|fail|slow · 호출 기록 $T/gcloud.calls · 성공 시 «토큰»을 찍는다(출력에 새면 안 됨)
  cat > "$T/stubs/gcloud" <<'STUB'
#!/bin/bash
case "$*" in
  *application-default*) item=adc; mode="${GC_ADC:-ok}" ;;
  *) item=user; mode="${GC_USER:-ok}" ;;
esac
echo "$item" >> "$GC_CALLS"
case "$mode" in
  ok) echo "ya29.SECRET-TOKEN-VALUE" ;;
  slow) sleep 20 ;;
  *) echo "ERROR: reauth required" >&2; exit 1 ;;
esac
STUB
  chmod +x "$T/stubs/gcloud"; export GC_CALLS="$T/gcloud.calls"; : > "$GC_CALLS"
  # 가짜 gh — GH_FAIL=1 실패 · GH_SLOW=1 20초 지연 · 그 외 GH_JSON 을 그대로 찍는다 · 호출 기록 $GH_CALLS (실 gh 0)
  cat > "$T/stubs/gh" <<'STUB'
#!/bin/bash
echo gh >> "$GH_CALLS"
[ "${GH_FAIL:-0}" = 1 ] && { echo "gh: authentication required" >&2; exit 1; }
[ "${GH_SLOW:-0}" = 1 ] && sleep 20
printf '%s\n' "${GH_JSON:-[]}"
STUB
  chmod +x "$T/stubs/gh"; export GH_CALLS="$T/gh.calls"; : > "$GH_CALLS"
  export PATH="$T/stubs:$PATH"
  local A="$SH $BIN/ft-autonomy.sh" out rc

  # --- ① 사전 점검 ---
  out="$(GC_USER=ok GC_ADC=ok $A on 2>&1)"; rc=$?
  [ $rc = 0 ] && has "$out" 'PASS gcloud 사용자 계정' && has "$out" 'PASS gcloud ADC' && has "$out" '사람 손 필요 0건'; ck "① 둘 다 성공 → PASS 2 · 0건 · rc 0 ($rc)" $?
  tail -n 1 <<<"$out" | grep -q '^\[자율 ON A1' && [ "$($A mode)" = on ]; ck "① status 1줄이 마지막 · 상태 ON" $?
  ! grep -q 'ya29' <<<"$out"; ck "① 출력에 토큰 글자 0" $?
  [ "$(sed -n '/PASS gcloud 사용자/=' <<<"$out")" -lt "$(sed -n '/^\[자율 ON/=' <<<"$out")" ]; ck "① 점검 블록이 status 줄 위" $?
  $A off >/dev/null 2>&1; : > "$GC_CALLS"
  out="$(GC_USER=fail GC_ADC=ok $A on 2>&1)"; rc=$?
  has "$out" 'FAIL gcloud 사용자 계정 — 지금 사람 손: gcloud auth login' && has "$out" 'PASS gcloud ADC' && has "$out" '사람 손 필요 1건'; ck "① 사용자 실패 → FAIL + auth login + 1건" $?
  [ $rc = 0 ] && [ "$($A mode)" = on ]; ck "① 점검 실패가 켜기를 막지 않음 (상태 ON · rc $rc)" $?
  ! grep -q 'ya29' <<<"$out"; ck "① 실패 때도 토큰 글자 0" $?
  $A off >/dev/null 2>&1
  out="$(GC_USER=ok GC_ADC=fail $A on 2>&1)"
  has "$out" 'FAIL gcloud ADC — 지금 사람 손: gcloud auth application-default login' && has "$out" '사람 손 필요 1건'; ck "① ADC 실패 → application-default login" $?
  $A off >/dev/null 2>&1
  out="$(GC_USER=fail GC_ADC=fail $A on 2>&1)"; has "$out" '사람 손 필요 2건'; ck "① 둘 다 실패 → 2건" $?
  $A off >/dev/null 2>&1; : > "$GC_CALLS"
  s=$(date +%s); out="$(GC_USER=slow GC_ADC=ok $A on 2>&1)"; rc=$?; e=$(( $(date +%s) - s ))
  has "$out" 'FAIL gcloud 사용자 계정' && has "$out" '사람 손 필요 1건' && [ "$(grep -c '^user$' "$GC_CALLS")" = 2 ] && [ $e -lt 30 ]; ck "① 7초 초과 → 재시도 1회(호출 기록 2) 뒤 FAIL (${e}s)" $?
  [ "$($A mode)" = on ]; ck "① 초과 FAIL 도 켜기는 진행" $?
  $A off >/dev/null 2>&1; : > "$GC_CALLS"
  out="$(PATH="$T/nogc:/usr/bin:/bin" $SH "$BIN/ft-autonomy.sh" on 2>&1)"
  has "$out" 'FAIL gcloud 없음' && has "$out" '사람 손 필요 [0-9]+건' && [ "$($A mode)" = on ]; ck "① gcloud 없음 → FAIL gcloud 없음 (조용한 생략 0) · 켜기는 진행" $?
  # 이미 ON 이면 점검 0 · status 만 (지금 동작)
  : > "$GC_CALLS"; out="$($A on 2>/dev/null)"   # 줄 수는 stdout 만 — C.UTF-8 의 setlocale 경고(stderr)를 세지 않는다
  [ ! -s "$GC_CALLS" ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && has "$out" '^\[자율 ON A[0-9]+'; ck "① 이미 ON → 점검 0 · status 1줄만" $?
  # off·status 회귀
  out="$($A off)"; has "$out" '^\[자율 OFF\]'; ck "① off 회귀" $?
  out="$($A status)"; has "$out" '^\[자율 OFF\]$'; ck "① status 회귀" $?

  # --- ② 끝 시각 인자 (--until HH:MM · --for <N>h|<N>m) — 고정 시계 FT_NOW(epoch) ---
  local mid; mid=$(( $(date +%s) - 10#$(date +%H)*3600 - 10#$(date +%M)*60 - 10#$(date +%S) ))
  local H=3600 DAY=86400 cnt0 bad r
  until_of() { sed -n 's/.*"until":\([0-9a-z]*\).*/\1/p' "$T/state/autonomy.json"; }
  logn() { wc -l < "$T/state/autonomy.log" | tr -d ' '; }
  : > "$GC_CALLS"
  out="$(FT_NOW=$((mid + 7*H)) $A on --until 08:00 2>&1)"; rc=$?
  [ $rc = 0 ] && [ "$(until_of)" = "$((mid + 8*H))" ] && has "$out" '~08:00까지'; r=$?; ck "② --until 08:00 (07:00 에 켬) → 오늘 08:00 · status ~08:00까지 (until=$(until_of))" $r
  [ "$($A mode)" = on ]; ck "② until 칸 있는 json 이 위변조로 안 읽힘" $?
  tail -n 1 <<<"$out" | grep -q '^\[자율 ON A[0-9]* · .*~08:00까지'; ck "② status 마지막 줄에 끝 시각" $?
  out="$(FT_NOW=$((mid + 8*H)) $A on --until 09:00 2>/dev/null)"
  [ "$(until_of)" = "$((mid + 8*H))" ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && has "$out" '~08:00까지'; ck "② 이미 ON + 인자 → 무시 · status 만 (연장·단축 0)" $?
  $A off >/dev/null 2>&1
  FT_NOW=$((mid + 9*H)) $A on --until 08:00 >/dev/null 2>&1
  [ "$(until_of)" = "$((mid + DAY + 8*H))" ]; r=$?; ck "② --until 08:00 (09:00 에 켬 · 이미 지남) → 다음 날 08:00 (until=$(until_of))" $r
  $A off >/dev/null 2>&1
  FT_NOW=$((mid + 7*H)) $A on --for 3h >/dev/null 2>&1; [ "$(until_of)" = "$((mid + 10*H))" ]; ck "② --for 3h → +3시간" $?
  $A off >/dev/null 2>&1
  FT_NOW=$((mid + 7*H)) $A on --for 90m >/dev/null 2>&1; [ "$(until_of)" = "$((mid + 7*H + 5400))" ]; ck "② --for 90m → +90분" $?
  $A off >/dev/null 2>&1
  out="$($A on 2>&1)"; [ "$(until_of)" = null ] && has "$out" '끝 없음'; ck "② 인자 없음 → until null · 끝 없음 표시" $?
  $A off >/dev/null 2>&1; : > "$GC_CALLS"; cnt0=$(logn)
  for bad in "--until 08:00 --for 3h" "--for 3h --until 08:00" "--until 25:00" "--until 8" "--until 08:60" "--until" "--for 3d" "--for 0h" "--for h" "--for" "--bogus 1"; do
    out="$($A on $bad 2>&1)"; rc=$?
    [ $rc = 2 ] && has "$out" '^REJECT' && [ "$($A mode)" = off ] && [ "$(logn)" = "$cnt0" ] && [ ! -s "$GC_CALLS" ]; ck "② REJECT [$bad] → rc 2 · 상태 쓰기 0 · 점검 0 (rc $rc)" $?
  done

  # --- ③ 시작 장부 (design/planner/AUTONOMY-START-A<N>.md) ---
  local d ev ledger
  for d in alpha/indices/진행/a1 beta/indices/진행/b1 alpha/indices/대기/a2 gamma/indices/대기/g1; do
    mkdir -p "$T/design/$(dirname "$d")"; printf '# 인덱스: %s — 카드 머리 한 줄\n본문은 장부에 안 나온다\n' "$(basename "$d")" > "$T/design/$d.md"
  done
  export GH_JSON='[{"number":11,"title":"P1 이슈","labels":[{"name":"priority:p1"},{"name":"team:beta"}]},{"number":10,"title":"P0 이슈","labels":[{"name":"priority:p0"}]},{"number":12,"title":"P2 이슈","labels":[{"name":"priority:p2"}]},{"number":13,"title":"라벨 없는 이슈","labels":[]}]'
  $A off >/dev/null 2>&1; : > "$GH_CALLS"
  out="$($A on 2>&1)"; rc=$?; ev="$($A event)"; ledger="$T/planner/AUTONOMY-START-$ev.md"
  [ $rc = 0 ] && [ -f "$ledger" ]; ck "③ 켜기 → AUTONOMY-START-$ev.md 생성 (rc $rc)" $?
  ln() { grep -n -- "$1" "$ledger" | head -1 | cut -d: -f1; }   # 장부에서 낱말의 첫 줄 번호
  [ -n "$(ln 'a1 —')" ] && [ -n "$(ln '#12')" ] && [ -n "$(ln 'g1 —')" ] \
    && [ "$(ln 'a1 —')" -lt "$(ln 'b1 —')" ] && [ "$(ln 'b1 —')" -lt "$(ln '#10')" ] && [ "$(ln '#10')" -lt "$(ln '#11')" ] \
    && [ "$(ln '#11')" -lt "$(ln '#12')" ] && [ "$(ln '#12')" -lt "$(ln 'a2 —')" ] && [ "$(ln '#12')" -lt "$(ln 'g1 —')" ]; ck "③ 순서 진행 → p0 → p1 → p2 → 대기 카드" $?
  grep -q '\[beta\].*#11\|#11.*\[beta\]' "$ledger"; ck "③ 팀 열 = team:* 라벨" $?
  grep -qE '\[alpha\].*a1 —|a1 —.*\[alpha\]' "$ledger"; ck "③ 팀 열 = 폴더 이름" $?
  ! grep -q '#13' "$ledger"; ck "③ 우선순위 라벨 없는 Issue 는 장부에 없음" $?
  ! grep -q '본문은 장부에 안 나온다' "$ledger"; ck "③ 카드는 머리 1줄만" $?
  [ "$(grep -c '^gh$' "$GH_CALLS")" = 1 ]; ck "③ gh 호출 1회" $?
  tail -n 1 <<<"$out" | grep -q '^\[자율 ON'; ck "③ status 줄이 여전히 마지막" $?
  $A off >/dev/null 2>&1; : > "$GH_CALLS"
  out="$(GH_FAIL=1 $A on 2>&1)"; rc=$?; ev="$($A event)"; ledger="$T/planner/AUTONOMY-START-$ev.md"
  [ $rc = 0 ] && grep -q 'Issue 목록 못 읽음' "$ledger" && grep -q 'a1 —' "$ledger" && ! grep -q '#10' "$ledger"; ck "③ gh 실패 → «Issue 목록 못 읽음» 줄 + 카드 절은 유지 + rc 0 (rc $rc)" $?
  [ "$($A mode)" = on ]; ck "③ gh 실패도 켜기는 진행" $?
  $A off >/dev/null 2>&1; : > "$GH_CALLS"
  s=$(date +%s); out="$(GH_SLOW=1 $A on 2>&1)"; rc=$?; e=$(( $(date +%s) - s )); ev="$($A event)"
  grep -q 'Issue 목록 못 읽음' "$T/planner/AUTONOMY-START-$ev.md" && [ "$(grep -c '^gh$' "$GH_CALLS")" = 2 ] && [ $rc = 0 ] && [ $e -lt 40 ]; ck "③ gh 7초 초과 → 재시도 1회(기록 2) 뒤 못 읽음 (${e}s)" $?
  $A off >/dev/null 2>&1
  out="$(PATH="$T/nogc:/usr/bin:/bin" $SH "$BIN/ft-autonomy.sh" on 2>&1)"; rc=$?; ev="$($A event)"
  [ $rc = 0 ] && grep -q 'Issue 목록 못 읽음: gh 없음' "$T/planner/AUTONOMY-START-$ev.md"; ck "③ gh 없음 → 못 읽음: gh 없음 (조용한 생략 0)" $?
  $A off >/dev/null 2>&1
  chmod 555 "$T/planner"; out="$($A on 2>"$T/err"; echo "rc=$?")"; chmod 755 "$T/planner"
  has "$out" 'rc=1' && grep -q 'ERROR' "$T/err" && grep -q '이미 ON' "$T/err" && [ "$($A mode)" = on ]; ck "③ 장부 쓰기 실패 → ERROR rc 1 + «상태는 이미 ON» (상태 ON 유지)" $?
  has "$out" '^\[자율 ON'; ck "③ 장부 실패여도 status 줄은 찍힘" $?
  rm -rf "$T"
}
bounded_suite() {  # <셸> — bounded() 마감·계보 정리 (DA⑥ HOLD C1·C2) — 가짜 도구만 · 한도 2초(CALL_TIMEOUT_S=2)
  local SH="$1" T s e out r; T="$(mktemp -d)"; echo "== bounded $SH"
  sed -n '/^_bd_tree() {/,/^}/p;/^_bd_stop() {/,/^}/p;/^bounded() {/,/^}/p' "$BIN/ft-autonomy-start.sh" > "$T/lib.sh"
  grep -q '^bounded() {' "$T/lib.sh"; ck "bounded: 함수 추출" $?
  mkdir -p "$T/fake"
  # ⓐ 부하 모사: sleep 0.1 이 0.2 로 늘어진다(틱 세기 마감이면 한도가 2배로 늘어남)
  printf '%s\n' '#!/bin/bash' 'if [ "${1:-}" = 0.1 ]; then exec /bin/sleep 0.2; fi' 'exec /bin/sleep "$@"' > "$T/fake/sleep"; chmod +x "$T/fake/sleep"
  printf '%s\n' '#!/bin/bash' '/bin/sleep 3' 'echo LATE_OK' > "$T/slow.sh"
  printf '%s\n' '#!/bin/bash' "bash \"$T/late-child.sh\" &" '/bin/sleep 30' > "$T/late-parent.sh"
  printf '%s\n' '#!/bin/bash' '/bin/sleep 6' 'echo LATE_ONLY' > "$T/late-child.sh"
  printf '%s\n' '#!/bin/bash' "trap '' TERM" 'while :; do /bin/sleep 0.1; done' > "$T/term-ignore.sh"
  printf '%s\n' 'set -uo pipefail' ". \"$T/lib.sh\"" 'CALL_TIMEOUT_S=2; CALL_RETRIES=1' 'export BOUND_OUT="$1"; shift' 'bounded "$@"; echo "rc=$?"' > "$T/run.sh"
  s=$(date +%s); out="$(PATH="$T/fake:$PATH" $SH "$T/run.sh" "$T/o1" bash "$T/slow.sh" 2>&1)"; e=$(( $(date +%s) - s ))
  ! grep -q '^rc=0$' <<<"$out" && [ $e -le 8 ]; r=$?; ck "C1 ⓐ 느린 sleep + 한도 뒤 rc0 도구 → 채택 0 · 총 ≤ 2×(한도+1.5) (${e}s: $(tail -n 1 <<<"$out"))" $r
  # ⓑ 부모가 자식을 띄우고 자식이 한도 뒤 BOUND_OUT 에 쓴다 → 반환 뒤 자식 0 · 늦은 글자 0
  out="$($SH "$T/run.sh" "$T/o2" bash "$T/late-parent.sh" 2>&1)"
  [ -z "$(pgrep -f "$T/late-parent.sh")" ] && [ -z "$(pgrep -f "$T/late-child.sh")" ]; ck "C2 ⓑ 반환 뒤 부모·자식 프로세스 0 (${out##*$'\n'})" $?
  /bin/sleep 8
  ! grep -q LATE_ONLY "$T/o2"; ck "C2 ⓑ 반환 +8초 뒤 BOUND_OUT 에 늦은 글자 0" $?
  # ⓒ TERM 무시 → KILL 로 마감 안에 반환
  s=$(date +%s); out="$($SH "$T/run.sh" "$T/o3" bash "$T/term-ignore.sh" 2>&1)"; e=$(( $(date +%s) - s ))
  ! grep -q '^rc=0$' <<<"$out" && [ $e -le 8 ] && [ -z "$(pgrep -f "$T/term-ignore.sh")" ]; ck "C2 ⓒ TERM 무시 → 총 ≤ 2×(한도+1.5) · 반환 뒤 프로세스 0 (${e}s)" $?
  rm -rf "$T"
}
suite /bin/bash
B5="$(command -v bash)"; [ "$("$B5" -c 'echo ${BASH_VERSINFO[0]}')" -ge 5 ] 2>/dev/null && suite "$B5" || echo "SKIP bash5 없음"
bounded_suite /bin/bash
[ -n "${B5:-}" ] && [ "$("$B5" -c 'echo ${BASH_VERSINFO[0]}')" -ge 5 ] 2>/dev/null && bounded_suite "$B5"
# --- 정적 점검: 키트 미러 cmp · 200줄 이하 · bash -n ---
for f in ft-autonomy.sh ft-autonomy-start.sh; do
  cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp $f" $?
  [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?
  bash -n "$BIN/$f"; ck "bash -n $f" $?
done
grep -qE '^CALL_TIMEOUT_S=7;? CALL_RETRIES=1$' "$BIN/ft-autonomy-start.sh"; ck "7초+재시도 1회 상수 (판정 666)" $?
echo "== $n checks, fail=$fail"; [ "$fail" = 0 ]
