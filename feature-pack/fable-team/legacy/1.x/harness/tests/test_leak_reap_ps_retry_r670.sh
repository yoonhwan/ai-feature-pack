#!/usr/bin/env bash
# test_leak_reap_ps_retry_r670.sh — r670: 부하 꼭대기(load 98~122)에서 유출 조사(ft-leak-reap)의 ps 1회가 7초를 넘겨 «조사 못 함»(rc 20)이 두 번 났다.
#   ⓐ 첫 출력 전 실패만 1회 재시도(첫 호출 8초 잠 · 둘째 즉시 → 조사 성공) ⓑ ps 경량 = 판정 필드 5(옛 필드 7 표도 읽는다 · 긴 명령 줄 자르기)
#   ⓒ 두 번 다 실패 = rc 20 그대로(0 으로 숨기지 않음 · 사유에 재시도 표시) · 출력이 나온 뒤 실패는 재시도 0 ⓓ ft-leak-watch 실패 경보 = «연속 N회 · 다음 재조사 60초 뒤»
#   ⓔ 총 마감 = 7 + 7 = 14초 이하(실제 경과 단언) ⓕ 스냅샷 경로는 재시도 0(ps 호출 0).
# 가짜 ps(FT_PS_CMD 대역) 만 쓴다 — 실 프로세스 종료 0 · 실 명부·실 우편함 0 · mktemp 만. 변이 대조는 R670_BIN=<옛 판 폴더>.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R670_BIN:-$REPO/harness/bin}"; KIT="$REPO/harness/kit/fable-team/bin"
T0="$(mktemp -d)"; T="$(cd "$T0" && pwd -P)"
trap 'rm -rf "$T0"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
rc_is(){ [ "$1" = "$2" ] && ok "$3 (rc=$1)" || bad "$3 — rc=$1 기대=$2"; }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }

REAP="$BIN/ft-leak-reap.sh"; WATCH="$BIN/ft-leak-watch.sh"
for f in ft-leak-reap.sh ft-leak-watch.sh; do
  [ -f "$BIN/$f" ] && bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f (없거나 문법 오류)"
done
if [ -z "${R670_BIN:-}" ]; then for f in ft-leak-reap.sh ft-leak-watch.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done; fi

# ── 표본: 필드 5(r670 생산) · 필드 7(R347 계약 · 옛 판·ft-agent-alive) · 유출 0 · 긴 명령 줄 ──
L="Sat Oct 18 00:12:34 2026"
row5() { printf '%6s %6s %s %10s %s\n' "$1" "$2" "$L" "$3" "$4"; }
row7() { printf '%6s %6s %6s %s %10s %-4s %s\n' "$1" "$2" "$1" "$L" "$3" "${4:-R}" "$5"; }
{ row5 5001 1 1:30.00 "bash -c (while :; do :; done)"; row5 5003 777 2:00.00 "bash -c (while :; do :; done)"
  row5 5004 1 5:00.00 '/opt/homebrew/bin/headroom proxy --note "while :; do :; done"'; } > "$T/ps5.txt"
{ row7 5001 1 1:30.00 R "bash -c (while :; do :; done)"; row7 5003 777 2:00.00 R "bash -c (while :; do :; done)"; } > "$T/ps7.txt"
{ row5 7001 1 9:00.00 "/usr/libexec/logd"; } > "$T/ps0.txt"
LONG="$(printf 'A%.0s' $(seq 1 3000))"
{ row5 8001 1 1:30.00 "bash -c (while :; do :; done) $LONG"; } > "$T/pslong.txt"
RUN()  { local rc o; o="$(FT_PS_SNAPSHOT="$1" bash "$REAP" "${@:2}" 2>&1)"; rc=$?; printf '%s\n' "$o" | grep -v 'setlocale'; return $rc; }
# 가짜 ps: 첫 호출만 $2 초 잠(그 뒤 즉시 $3 표) — 호출 횟수를 $1/calls 에 센다
mkps() { mkdir -p "$1"; printf '#!/bin/bash\nn=$(cat "%s/calls" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "%s/calls"\nif [ "$n" -eq 1 ]; then exec sleep %s; fi\ncat %s\n' "$1" "$1" "$2" "$3" > "$1/ps"; chmod +x "$1/ps"; }
mkhang() { mkdir -p "$1"; printf '#!/bin/bash\nn=$(cat "%s/calls" 2>/dev/null || echo 0); echo "$((n+1))" > "%s/calls"\nexec sleep %s\n' "$1" "$1" "$2" > "$1/ps"; chmod +x "$1/ps"; }   # 매 호출 잠(exec = 고아 sleep 안 남김)
calls() { cat "$1/calls" 2>/dev/null || echo 0; }

# ── ⓑ ps 경량: 판정 필드 5 · 옛 필드 7 호환 · 긴 명령 줄 자르기 ──
grep -q 'DEFAULT_PS = "ps -axo pid=,ppid=,lstart=,time=,command="' "$REAP" && ok "ⓑ DEFAULT_PS = 판정 필드 5(pid ppid lstart time command)" || bad "ⓑ DEFAULT_PS 가 경량 5필드가 아님"
hasnt "$(grep '^DEFAULT_PS' "$REAP")" "pgid=" "ⓑ ps 명령에서 pgid 제거(판정에 안 씀)"
hasnt "$(grep '^DEFAULT_PS' "$REAP")" "stat=" "ⓑ ps 명령에서 stat 제거(판정에 안 씀)"
o="$(RUN "$T/ps5.txt" --dry-run)"; rc=$?; rc_is "$rc" 10 "ⓑ 필드 5 표 → 발견"; has "$o" "pid=5001" "ⓑ 필드 5 검출"; hasnt "$o" "pid=5003" "ⓑ 필드 5 부모 생존 제외"
hasnt "$o" "pid=5004" "ⓑ 필드 5 보호 exe 제외"; has "$o" "유출 1건" "ⓑ 필드 5 검출 1건"
o="$(RUN "$T/ps7.txt" --dry-run)"; rc=$?; rc_is "$rc" 10 "ⓑ 옛 필드 7 표(설치 직후 옛 스냅샷·ft-agent-alive 계약)도 읽는다"; has "$o" "pid=5001" "ⓑ 필드 7 검출"
o="$(RUN "$T/pslong.txt" --json)"; rc=$?; rc_is "$rc" 10 "ⓑ 3000자 명령 줄도 파싱·검출"; n="$(printf '%s' "$o" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["rows"][0]["cmd"]))' 2>/dev/null || echo err)"
[ "$n" != err ] && [ "$n" -le 512 ] && ok "ⓑ 긴 명령 줄은 앞 512자만 판정(실제 ${n}자)" || bad "ⓑ 명령 줄 자르기 실패(길이=${n})"

# ── ⓐ 첫 출력 전 실패 1회 재시도 ──
mkps "$T/ps_a" 8 "$T/ps5.txt"
s0=$SECONDS; o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="$T/ps_a/ps" bash "$REAP" --dry-run 2>&1)"; rc=$?; el=$((SECONDS-s0))
hasnt "$o" "ps timeout" "ⓐ 첫 호출 시간 초과해도 조사 성공(stderr 에 timeout 없음)"
eq "$(calls "$T/ps_a")" 2 "ⓐ ps 2회(1회 재시도)"; [ "$rc" = 10 ] && ok "ⓐ 재시도 뒤 발견 rc=10" || bad "ⓐ 재시도 뒤 rc=$rc 기대=10"
[ "$el" -le 12 ] && ok "ⓐ 8초 잠 1회 + 즉시 1회 = ${el}s(12초 안)" || bad "ⓐ ${el}s — 재시도가 아니라 대기한 것"

# ── ⓒ 두 번 다 실패 = rc 20 그대로 · 출력 뒤 실패는 재시도 0 ──
mkhang "$T/ps_c" 30
s0=$SECONDS; o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="$T/ps_c/ps" bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?; el=$((SECONDS-s0))
rc_is "$rc" 20 "ⓒ 두 번 다 시간 초과 → rc 20(0 으로 숨기지 않음)"; eq "$(calls "$T/ps_c")" 2 "ⓒ ps 2회(재시도 1회)"
has "$o" "timeout" "ⓒ 사유 = ps timeout"; has "$o" "재시도 1회 포함 2회 실패" "ⓒ 사유에 재시도 사실 표시"; hasnt "$o" "Traceback" "ⓒ traceback 0"
[ "$el" -ge 13 ] && [ "$el" -le 16 ] && ok "ⓔ 총 마감 = 7+7 = ${el}s(14초 이하 · 실제 경과)" || bad "ⓔ 총 마감 ${el}s — 7+7=14초 안이어야 함"
printf '#!/bin/bash\nexit 1\n' > "$T/ps_false"; chmod +x "$T/ps_false"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="$T/ps_false" bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?
rc_is "$rc" 20 "ⓒ 출력 없는 rc≠0 → rc 20"; has "$o" "ps rc=1" "ⓒ 사유 = ps rc=1"
printf '#!/bin/bash\ncat %s\nn=$(cat "%s/calls2" 2>/dev/null || echo 0); echo $((n+1)) > "%s/calls2"\nexit 1\n' "$T/ps5.txt" "$T" "$T" > "$T/ps_outrc"; chmod +x "$T/ps_outrc"
o="$(env -u FT_PS_SNAPSHOT FT_PS_CMD="$T/ps_outrc" bash "$REAP" --dry-run --quiet 2>&1)"; rc=$?
rc_is "$rc" 20 "ⓒ 출력 뒤 rc≠0 → rc 20"; eq "$(cat "$T/calls2")" 1 "ⓒ 출력이 나온 뒤 실패는 재시도 0(ps 1회)"

# ── ⓕ 스냅샷 경로 = 파일 읽기 · 재시도 0 · ps 호출 0 ──
mkps "$T/ps_f" 30 "$T/ps5.txt"
s0=$SECONDS; o="$(FT_PS_SNAPSHOT="$T/ps5.txt" FT_PS_CMD="$T/ps_f/ps" bash "$REAP" --dry-run 2>&1)"; rc=$?; el=$((SECONDS-s0))
rc_is "$rc" 10 "ⓕ 스냅샷 소비는 재시도와 무관하게 발견"; eq "$(calls "$T/ps_f")" 0 "ⓕ 스냅샷 경로는 ps 호출 0"; [ "$el" -le 3 ] && ok "ⓕ 스냅샷 소비 ${el}s(ps 대기 0)" || bad "ⓕ 스냅샷 소비가 ${el}s"

# ── ⓓ ft-leak-watch: 실패 경보에 «연속 N회 · 다음 재조사 60초 뒤» · 억제 중에도 조사·연속 갱신 ──
TK="$T/tk"; mkdir -p "$TK"; printf '{"_master":"m#1","_hil_route":"p#1"}\n' > "$TK/seats.json"
printf '#!/bin/bash\necho "$*" >> "%s/mbox.log"\n' "$T" > "$T/fakembox.sh"
printf '#!/bin/bash\nexit 1\n' > "$T/failmbox.sh"; chmod +x "$T/fakembox.sh" "$T/failmbox.sh"
ST="$T/alert.state"; : > "$T/mbox.log"
W() { local mb="$1"; shift; env "$@" FT_TICK_SEATS="$TK/seats.json" FT_TICK_MBOX="$mb" FT_LEAK_ALERT_STATE="$ST" bash "$WATCH" 2>&1; }
sends() { local c; c="$(grep -c "$1" "$T/mbox.log" 2>/dev/null)"; echo "${c:-0}"; }
o="$(W "$T/fakembox.sh" FT_PS_CMD="$T/ps_false")"
eq "$(sends '\[부하 유출 조사 실패\]')" 1 "ⓓ 조사 실패 경보 1통"; has "$o" "leak-reap: ERROR" "ⓓ 틱 로그용 ERROR 줄"
has "$(cat "$T/mbox.log")" "연속 1회" "ⓓ 경보 본문에 연속 1회"; has "$(cat "$T/mbox.log")" "다음 재조사 60초 뒤" "ⓓ 경보 본문에 다음 재조사 60초 뒤"
[ -f "$ST.err" ] && ok "ⓓ 실패 상태 파일 저장" || bad "ⓓ 실패 상태 파일 없음"
read -r efp ets ecnt enext < "$ST.err"
eq "$ecnt" 1 "ⓓ 연속 횟수 1"; d=$(( enext - ets )); [ "$d" -ge 58 ] && [ "$d" -le 62 ] && ok "ⓓ 다음 재조사 시각 = 실패 +60초(${d}s)" || bad "ⓓ 다음 재조사 시각 간격 ${d}s"
sleep 1.1; W "$T/fakembox.sh" FT_PS_CMD="$T/ps_false" >/dev/null
eq "$(sends '\[부하 유출 조사 실패\]')" 1 "ⓓ 같은 오류 600초 억제 = 추가 통 0"
read -r efp ets2 ecnt2 enext2 < "$ST.err"
eq "$ecnt2" 2 "ⓓ 억제 중에도 연속 횟수는 오른다(2)"; [ "$enext2" -gt "$enext" ] && ok "ⓓ 억제 중에도 다음 재조사 시각 전진" || bad "ⓓ 다음 재조사 시각 그대로($enext2 ≤ $enext)"
printf '%s %s %s %s\n' "$efp" "$ets2" "$ecnt2" "$(( $(date +%s) - 5 ))" > "$ST.err"
o="$(W "$T/fakembox.sh" FT_PS_CMD="$T/ps_false")"; has "$o" "재조사 — 직전 실패의 예정 시각" "ⓓ 예정 시각을 넘긴 틱이 그 재조사를 한다(로그 1줄)"
o="$(W "$T/fakembox.sh" FT_PS_CMD="cat $T/ps0.txt")"; has "$o" "조사 오류 해소" "ⓓ 조사가 다시 되면 해소 줄"; has "$o" "연속" "ⓓ 해소 줄에 연속 횟수"
[ ! -e "$ST.err" ] && ok "ⓓ 해소 뒤 실패 상태 삭제" || bad "ⓓ 실패 상태 남음"; eq "$(sends '\[부하 유출 해소\]')" 0 "ⓓ 오류만 있던 경우 유출 해소 통 0"
o="$(W "$T/failmbox.sh" FT_PS_CMD="$T/ps_false")"; has "$o" "mbox failed" "ⓓ 송신 실패 stderr 1줄"
[ ! -e "$ST.err" ] && ok "ⓓ 송신 실패 = 상태 미저장(다음 틱 재시도)" || bad "ⓓ 송신 실패인데 상태 저장"
W "$T/fakembox.sh" FT_PS_CMD="$T/ps_false" >/dev/null; eq "$(sends '\[부하 유출 조사 실패\]')" 2 "ⓓ 다음 틱 재시도 1통"

echo "--- 증거: 시험 로케일 ${LC_ALL:-기본}"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
