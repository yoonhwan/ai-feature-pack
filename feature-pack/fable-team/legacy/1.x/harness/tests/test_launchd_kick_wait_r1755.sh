#!/usr/bin/env bash
# test_launchd_kick_wait_r1755.sh — r1755: ft-launchd-kick-wait.sh 가 launchd 잡을 다시 돌린 뒤 «이번 실행이 쓴 결과 파일»(mtime ≥ T0)을 기다려 읽는다.
#   반례 ①~⑥(카드 «반례 집합» 그대로) · 기준 = 설치 h(h-r1744 :35~44) 루프를 함수로 옮긴 꼴에서 ① Red · 변이 M1~M3 = 사본에서 한 곳만 + 원본 대조(반대 결과)
#   PATH 스텁 launchctl·date·sleep(가짜 시계 · sleep 1 = 시계 +1 · 정해진 시각에 결과 파일 touch) — 실 launchd 0 · 실 sleep 0 · 70초 안
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export LC_ALL=C
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"; F=ft-launchd-kick-wait.sh
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$(/bin/date +%s); TL=$T0; STEPS=""
ok()  { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
lap() { local n; n=$(/bin/date +%s); STEPS="$STEPS $1=$((n-TL))s"; TL=$n; }
echo "== 짝 cmp · bash -n"; cmp -s "$BIN/$F" "$KIT/$F" && ok "cmp bin == kit $F" || bad "cmp 다름 $F" ; /bin/bash -n "$BIN/$F" && ok "/bin/bash 3.2 -n $F" || bad "bash -n $F"
S="$T/stub"; mkdir -p "$S"; export KW_STATE="$T/st" KW_RESULT="$T/scan-latest.txt"
cat > "$S/date" <<'SH'
#!/bin/bash
[ "${1:-}" = +%s ] && { echo $(( $(cat "$KW_STATE/base") + $(cat "$KW_STATE/clk") )); exit 0; }
exec /bin/date "$@"
SH
cat > "$S/sleep" <<'SH'
#!/bin/bash
c=$(( $(cat "$KW_STATE/clk") + 1 )); echo "$c" > "$KW_STATE/clk"
[ "$c" = "${KW_TOUCH_AT:-x}" ] && touch -t "$(/bin/date -r $(( $(cat "$KW_STATE/base") + c )) +%Y%m%d%H%M.%S)" "$KW_RESULT"
exit 0
SH
cat > "$S/launchctl" <<'SH'
#!/bin/bash
c=$(cat "$KW_STATE/clk")
case "${1:-}" in
  kickstart) echo "$*" >> "$KW_STATE/kicks"; exit "${KW_KICK_RC:-0}" ;;
  print) [ "${KW_PRINT_RC:-0}" = 0 ] || exit "$KW_PRINT_RC"
    if [ "$c" -lt "${KW_RUN_UNTIL:-0}" ]; then printf '\tstate = running\n\tlast exit code = %s\n' "${KW_EXIT_OLD:-0}"
    else printf '\tstate = not running\n\tlast exit code = %s\n' "${KW_EXIT:-0}"; fi ;;
  *) exit 64 ;;
esac
SH
chmod +x "$S/date" "$S/sleep" "$S/launchctl"
reset() {  # 시계 0 · 결과 파일 = 옛 판(T0 - 100초) · kickstart 횟수 0
  mkdir -p "$KW_STATE"; rm -f "$KW_STATE/kicks"; echo 0 > "$KW_STATE/clk"; /bin/date +%s > "$KW_STATE/base"; echo old > "$KW_RESULT"; touch -t "$(/bin/date -r $(( $(cat "$KW_STATE/base") - 100 )) +%Y%m%d%H%M.%S)" "$KW_RESULT"
}
# 사례 env(카드 반례 ①~⑥) — KW_TOUCH_AT(결과 파일 touch 시각) · KW_RUN_UNTIL(그 시각 전까지 running) · KW_EXIT_OLD(running 동안 last exit) · KW_EXIT · KW_PRINT_RC
case_env() { case "$1" in c1) echo "KW_TOUCH_AT=3 KW_RUN_UNTIL=0 KW_EXIT=0" ;; c2) echo "KW_TOUCH_AT=2 KW_RUN_UNTIL=3 KW_EXIT_OLD=5 KW_EXIT=0" ;;
  c3) echo "KW_TOUCH_AT=1 KW_RUN_UNTIL=0 KW_EXIT=78" ;; c4|c6) echo "KW_RUN_UNTIL=0 KW_EXIT=0" ;; c5) echo "KW_PRINT_RC=113" ;; esac; }
case_args() { case "$1" in c4) echo "--wait 3" ;; c6) echo "--wait 99" ;; esac; }
OUT=""; RC=0; run() {  # run <도구 경로> <사례>
  reset; OUT=$(env $(case_env "$2") PATH="$S:$PATH" /bin/bash "$1" com.test.scan "$KW_RESULT" $(case_args "$2") 2>&1); RC=$?
}
want() {  # want <이름> <도구> <사례> <rc> <글자(ERE)>
  run "$2" "$3"
  [ "$RC" = "$4" ] && printf '%s\n' "$OUT" | grep -Eq -- "$5" && ok "$1 rc=$RC" || bad "$1 (rc=$RC want=$4 out=[${OUT:0:300}] want=/$5/)"
}
# 기준 = 설치 h(h-r1744-scan-install-20261112.sh :35~44) 루프를 함수로 옮긴 꼴 — «running 일 때만 기다림»
h_loop() {
  local U="gui/$(id -u)/$1" SL="$2" t0 ec m i; t0=$(date +%s); launchctl kickstart -k "$U" || return 7
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do launchctl print "$U" 2>/dev/null | grep -q 'state = running' || break; sleep 1; done
  ec=$(launchctl print "$U" 2>/dev/null | awk -F'= ' '/last exit code/{print $2; exit}')
  m=$(stat -f %m "$SL" 2>/dev/null || echo 0)
  [ "$m" -ge "$t0" ] || { echo "STALE h-loop mtime $m < $t0 exit=$ec"; return 3; }
  echo "KICKED h-loop exit=$ec"
}
export -f h_loop; lap 준비
echo "== 반례 ①~⑥ (원본)"
want "① 빨리 끝남·3초 뒤 결과" "$BIN/$F" c1 0 '^KICKED com\.test\.scan fresh=[0-9]+ exit=0 waited=3$'
want "② 결과 뒤 1초 더 running · exit 은 끝난 뒤 값" "$BIN/$F" c2 0 '^KICKED com\.test\.scan fresh=[0-9]+ exit=0 waited=3$'
want "③ 이번 판 · exit 78" "$BIN/$F" c3 1 '^KICKED com\.test\.scan fresh=[0-9]+ exit=78 waited=1$'
want "④ 결과 안 바뀜 · --wait 3" "$BIN/$F" c4 3 '^STALE com\.test\.scan 결과 파일 mtime [0-9]+ < T0 [0-9]+ · waited=3$'
want "⑤ print rc113 = 잡 없음" "$BIN/$F" c5 2 '^판정 불가 잡 없음'
[ -e "$KW_STATE/kicks" ] && bad "⑤ kickstart $(wc -l < "$KW_STATE/kicks")회(want 0)" || ok "⑤ kickstart 0회"
want "⑥ --wait 99 → 25 로 잘림" "$BIN/$F" c6 3 'waited=25$'
want "A1 kickstart -k gui/<uid>/<라벨> 1회" "$BIN/$F" c1 0 '^KICKED'; [ "$(cat "$KW_STATE/kicks" 2>/dev/null)" = "kickstart -k gui/$(id -u)/com.test.scan" ] && ok "A1 kickstart 인자" || bad "A1 kickstart 인자 [$(cat "$KW_STATE/kicks" 2>/dev/null)]"
lap 반례
echo "== 기준(h 루프 꼴) ① Red"; reset; OUT=$(env $(case_env c1) PATH="$S:$PATH" /bin/bash -c 'h_loop com.test.scan "$KW_RESULT"' 2>&1); RC=$?
[ "$RC" = 3 ] && ok "기준 ① Red = STALE ($OUT)" || bad "기준 ① Red 아님 (rc=$RC out=[$OUT])"
lap 기준
echo "== 변이 — 사본에서 한 곳만 · 각 뒤 원본으로 같은 사례 1회(반대 결과)"
mutant() {  # mutant <이름> <옛 글자> <새 글자> → 사본 경로
  local d="$T/v-$1"; mkdir -p "$d"; cp "$BIN/$F" "$d/$F"
  python3 - "$d/$F" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:60]}"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
  echo "$d/$F"
}
flip() {  # flip <이름> <변이 경로> <사례> <원본 기대 rc> <원본 글자>
  run "$2" "$3"; local mrc=$RC mout=$OUT; run "$BIN/$F" "$3"
  if [ "$RC" = "$4" ] && printf '%s\n' "$OUT" | grep -Eq -- "$5" && ! { [ "$mrc" = "$4" ] && printf '%s\n' "$mout" | grep -Eq -- "$5"; }; then
    ok "$1 변이 FAIL(rc=$mrc ${mout:0:120}) · 원본 PASS"
  else bad "$1 (변이 rc=$mrc out=[${mout:0:200}] · 원본 rc=$RC out=[${OUT:0:200}])"; fi
}
M1=$(mutant M1 '[ "$m" -ge "$T0" ] && ! running && break   # r1755-mut:fresh' '! running && break   # r1755-mut:fresh') || bad "M1 변이 자리"
M2=$(mutant M2 '[ "$m" -ge "$T0" ] && ! running && break   # r1755-mut:fresh' '[ "$m" -ge "$T0" ] && break   # r1755-mut:fresh') || bad "M2 변이 자리"
M3=$(mutant M3 '[ "$W" -gt 25 ] && W=25   # r1755-mut:cap' 'true   # r1755-mut:cap') || bad "M3 변이 자리"
flip "M1(running 일 때만 기다림) ①" "$M1" c1 0 'exit=0 waited=3$'; flip "M2(exit 을 끝나기 전에 읽음) ②" "$M2" c2 0 'exit=0 waited=3$'
flip "M3(상한 자르기 지움) ⑥" "$M3" c6 3 'waited=25$'
cmp -s "$BIN/$F" "$KIT/$F" && ok "변이 뒤 bin·kit cmp0" || bad "변이 뒤 cmp 다름"; lap 변이
echo "단계별 초: 전체=$(( $(/bin/date +%s) - T0 ))s ·$STEPS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
