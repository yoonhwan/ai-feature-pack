#!/usr/bin/env bash
# test_heavy_slot_lib_r1286.sh — r1286 무거운 git 전역 자리(ft-heavy-slot-lib.sh) 단위 반례
#   R1 빈 자리 → 즉시 · owner 1줄 · release 뒤 밖에서 잡힘 / R2 셋째 «순번 대기 1(앞: …)» 1줄 · 앞이 놓으면 그 자리
#   R3 상한 2초 → «판정 불가 — … 대기 N초 초과» rc3 · 12초 안 / R4 쥔 셸 SIGKILL → 회수 줄 없이 즉시 잡힘
#   R5 셸만 SIGKILL · 자식 살아 있음 → 계속 쥠 · 자식 끝나면 풀림 / R6 20개 동시 → 최대 2 · 전부 rc0
#   R7 셸 TERM → 풀림 / R8 안 쥔 셸 release → 남의 자리 그대로 / R10 FT_HEAVY_SLOTS=0 → rc0 · 자리 파일 0
#   R11 같은 셸 재획득 rc3 · release 뒤 재획득 성공 · 그 자식 셸 잠금은 밖에서 거절
#   변이 1(잠금 → 있나 보고 만들기) → R6 FAIL · 변이 2(대기 상한 제거) → R3 FAIL(timeout) · 변이 3(상한 넘김 rc0) → R3 FAIL · 변이 10(재획득 허용) → R11 FAIL
#   실 tmux·네트워크·Redis 0 · 자기 재호출 0 · 고정 sleep 0(표식 폴링) · 시험 1개 상한 70초
set -uo pipefail
[ -z "${FT_R1286_REENTRY:-}" ] || { echo "FAIL 재진입"; exit 1; }
export FT_R1286_REENTRY=1
D="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
LIB="${LIB:-$D/../bin/ft-heavy-slot-lib.sh}"
T="$(mktemp -d "${TMPDIR:-/tmp}/r1286lib.XXXXXX")"; fail=0; BAD=""; BG=()
clean(){ local p; for p in ${BG[@]+"${BG[@]}"}; do kill -9 "$p" 2>/dev/null || true; done; rm -rf "$T"; }
trap clean EXIT
bad(){ echo "FAIL $1" >&2; fail=$((fail+1)); BAD="$BAD $1"; }
waitfor(){ local i; for i in $(seq 1 200); do [ -e "$1" ] && return 0; command sleep 0.05; done; return 1; }
run(){ # <이름> <함수> — 케이스마다 자기 자리 폴더를 쓰고, 안쪽 명령은 각자 timeout 으로 끊는다
  local n="$1" f="$2"; if "$f"; then return 0; fi; bad "$n"; return 1; }
lib(){ local d="$1"; shift; FT_HEAVY_DIR="$d" FT_HEAVY_POLL_SEC=0.2 bash -c '. "$0"; '"$*" "$LIB"; }
probe(){ # 밖에서 LOCK_NB → 0 잡힘(빈 자리) · 1 거절(쥠)
  local f="$1" fd; { exec {fd}>>"$f"; } 2>/dev/null || return 2
  perl -MFcntl=:flock -e 'open(my $h, ">&=", $ARGV[0]) or exit 3; flock($h, LOCK_EX|LOCK_NB) or exit 1;' "$fd" 2>/dev/null
  local rc=$?; eval "exec ${fd}>&-" 2>/dev/null; return $rc
}
mkh(){ # <이름> [자리폴더] → 자리를 쥐고 stop.<이름> 표식을 기다리는 holder
  cat > "$T/h-$1.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
export FT_HEAVY_DIR="${2:-$T/slots}"
. "$LIB"
hs_acquire "$1" 0 >/dev/null || exit 1
trap 'hs_release' EXIT
touch "$T/held.$1"
while [ ! -f "$T/stop.$1" ]; do command sleep 0.05; done
EOF
  rm -f "$T/held.$1" "$T/stop.$1"; }
up(){ local n="$1" d="${2:-$T/slots}"; mkh "$n" "$d"; bash "$T/h-$n.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.$n"; }
R1(){ lib "$T/s1" 'hs_acquire a 0 >/dev/null && [ -n "$HS_FD" ] && [ -s "$FT_HEAVY_DIR/slot-1.owner" ] && grep -q "^a " "$FT_HEAVY_DIR/slot-1.owner"' || return 1
  lib "$T/s1" 'hs_acquire a 0 >/dev/null; hs_release; [ -z "${HS_FD:-}" ]' || return 1; probe "$T/s1/slot-1.lock"; }
R2(){ mkh r2 "$T/s2"; bash "$T/h-r2.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.r2" || return 1
  mkh r2b "$T/s2"; bash "$T/h-r2b.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.r2b" || return 1
  local out="" i; ( FT_HEAVY_DIR="$T/s2" FT_HEAVY_POLL_SEC=0.15 timeout 10 bash -c '. "$0"; hs_acquire c 10; echo "rc=$?"' "$LIB" > "$T/r2.out" 2>&1 ) & BG+=($!)
  for i in $(seq 1 100); do grep -q '순번 대기 1(앞: ' "$T/r2.out" 2>/dev/null && break; command sleep 0.05; done
  touch "$T/stop.r2"
  for i in $(seq 1 200); do grep -q '^rc=0$' "$T/r2.out" 2>/dev/null && break; command sleep 0.05; done
  touch "$T/stop.r2b"
  grep -q '순번 대기 1(앞: ' "$T/r2.out" && grep -q '^rc=0$' "$T/r2.out"; }
R3(){ mkh r3 "$T/s3"; bash "$T/h-r3.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.r3" || return 1
  mkh r3b "$T/s3"; bash "$T/h-r3b.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.r3b" || return 1
  local t0 t1 out rc; t0="$SECONDS"
  out="$(FT_HEAVY_DIR="$T/s3" FT_HEAVY_POLL_SEC=0.15 timeout 10 bash -c '. "$0"; hs_acquire c 2' "$LIB" 2>&1)"; rc=$?
  t1="$SECONDS"; touch "$T/stop.r3" "$T/stop.r3b"
  [ "$rc" = 3 ] || { echo "  R3 rc=$rc" >&2; return 1; }
  printf '%s' "$out" | grep -q '판정 불가 — 무거운 git 자리 대기 [0-9]*초 초과' || return 1
  [ $((t1-t0)) -le 12 ]; }
R4(){ mkh r4 "$T/s4"; bash "$T/h-r4.sh" 2>/dev/null & local p=$! i out=""; BG+=($p); waitfor "$T/held.r4" || return 1
  kill -9 "$p" 2>/dev/null
  for i in $(seq 1 100); do out="$(FT_HEAVY_DIR="$T/s4" bash -c '. "$0"; hs_acquire z 0' "$LIB" 2>&1)" && break; command sleep 0.05; done
  case "$out" in *회수*) return 1;; esac
  printf '%s' "$out" | grep -q '판정 불가' && return 1; rm -f "$T/stop.r4"; return 0; }
R5(){ cat > "$T/h-r5.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
export FT_HEAVY_DIR="$T/s5"
. "$LIB"
hs_acquire r5 0 >/dev/null || exit 1
trap 'hs_release' EXIT
command sleep 30 & echo \$! > "$T/r5.child"
touch "$T/held.r5"
wait \$!
EOF
  bash "$T/h-r5.sh" 2>/dev/null & local p=$! i; BG+=($p); waitfor "$T/held.r5" || return 1
  kill -9 "$p" 2>/dev/null
  for i in $(seq 1 60); do probe "$T/s5/slot-1.lock" && return 1; command sleep 0.03; done   # 셸만 죽음 → 자식이 쥠
  kill -9 "$(cat "$T/r5.child" 2>/dev/null)" 2>/dev/null
  for i in $(seq 1 200); do probe "$T/s5/slot-1.lock" && return 0; command sleep 0.03; done; return 1; }
R6(){ cat > "$T/w.sh" <<EOF
#!/usr/bin/env bash
. "$LIB"
hs_acquire w 30 >/dev/null || { : > "$T/w.fail"; exit 1; }
printf 'E\n' >> "$T/conc.log"
command sleep 0.1
printf 'X\n' >> "$T/conc.log"
hs_release
EOF
  rm -f "$T/conc.log" "$T/w.fail"; local i pids=()
  for i in $(seq 1 20); do FT_HEAVY_DIR="$T/s6" FT_HEAVY_POLL_SEC=0.15 bash "$T/w.sh" 2>/dev/null & pids+=($!); done
  for i in "${pids[@]}"; do wait "$i" || true; done
  [ ! -s "$T/w.fail" ] || return 1; [ -f "$T/conc.log" ] || return 1
  [ "$(awk '$1=="E"{c++; if(c>m)m=c} $1=="X"{c--} END{print m+0}' "$T/conc.log")" = 2 ]; }
R7(){ mkh r7 "$T/s7"; bash "$T/h-r7.sh" 2>/dev/null & local p=$! i; BG+=($p); waitfor "$T/held.r7" || return 1
  kill -TERM "$p" 2>/dev/null
  for i in $(seq 1 200); do probe "$T/s7/slot-1.lock" && return 0; command sleep 0.05; done; return 1; }
R8(){ mkh r8 "$T/s8"; bash "$T/h-r8.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.r8" || return 1
  lib "$T/s8" 'hs_release; echo "relrc=$?"' | grep -q 'relrc=0' || return 1
  local rc; probe "$T/s8/slot-1.lock"; rc=$?; touch "$T/stop.r8"; [ "$rc" = 1 ]; }
R10(){ local out; out="$(FT_HEAVY_SLOTS=0 FT_HEAVY_DIR="$T/s10" bash -c '. "$0"; hs_acquire a 5; echo "acq=$?"; hs_release; echo "rel=$?"' "$LIB" 2>&1)"
  printf '%s' "$out" | grep -q 'acq=0' && printf '%s' "$out" | grep -q 'rel=0' || return 1
  [ -z "$(ls "$T/s10"/slot-*.lock 2>/dev/null)" ]; }
R11(){ local out; out="$(FT_HEAVY_DIR="$T/s11" bash -c '. "$0"; hs_acquire a 0 >/dev/null; hs_acquire b 0; echo "dup=$?"; hs_release; hs_acquire c 0 >/dev/null; echo "again=$?"' "$LIB" 2>&1)"
  printf '%s' "$out" | grep -q '이미 자리를 쥠' || return 1
  printf '%s' "$out" | grep -q 'dup=3' && printf '%s' "$out" | grep -q 'again=0' || return 1
  cat > "$T/h-11.sh" <<EOF
#!/usr/bin/env bash
export FT_HEAVY_DIR="$T/s11"
. "$LIB"
hs_acquire d 0 >/dev/null || exit 1
touch "$T/held.11"
while [ ! -f "$T/stop.11" ]; do command sleep 0.05; done
EOF
  rm -f "$T/held.11" "$T/stop.11"; bash "$T/h-11.sh" 2>/dev/null & BG+=($!); waitfor "$T/held.11" || return 1
  local rc; probe "$T/s11/slot-1.lock"; rc=$?; touch "$T/stop.11"; [ "$rc" = 1 ]; }
mkvar(){ local out="$T/lib-$1.sh"; python3 -I - "$LIB" "$out" "$2" <<'PY' || return 1
import sys
s = open(sys.argv[1], encoding="utf-8").read()
ns = {"s": s}
exec(sys.argv[3], ns)
open(sys.argv[2], "w", encoding="utf-8").write(ns["s"])
PY
}
for c in R1 R2 R3 R4 R5 R6 R7 R8 R10 R11; do run "$c" "$c"; done
runv(){ local n="$1" f="$2"; if "$f"; then bad "변이 $n — $f 통과"; else echo "변이 $n → $f FAIL(정상)"; fi; }
BASE="$D/../bin/ft-heavy-slot-lib.sh"
LIB="$BASE"; mkvar v1 's = s.replace("""  { exec {HS_FD}>>"$f"; } 2>/dev/null || { unset HS_FD; return 3; }""", """  [ -e "$f" ] && return 1
  : > "$f"; HS_FD=99; return 0""")' && { LIB="$T/lib-v1.sh"; runv "1(있나 보고 만들기)" R6; }
LIB="$BASE"; mkvar v2 's = s.replace("""if [ "$lim" -le 0 ] || [ "$waited" -ge "$lim" ]; then""", """if false; then""")' \
  && { LIB="$T/lib-v2.sh"; runv "2(대기 상한 제거)" R3; }
LIB="$BASE"; mkvar v3 's = s.replace("""      HS_MSG="판정 불가 — 무거운 git 자리 대기 ${waited}초 초과(앞: $(hs_ahead))"; echo "$HS_MSG" >&2
      return 3""", """      HS_MSG="판정 불가 — 무거운 git 자리 대기 ${waited}초 초과(앞: $(hs_ahead))"; echo "$HS_MSG" >&2
      return 0""")' \
  && { LIB="$T/lib-v3.sh"; runv "3(상한 넘김 rc0)" R3; }
LIB="$BASE"; mkvar v10 's = s.replace("""  [ -z "${HS_FD:-}" ] || { HS_MSG="판정 불가 — 이미 자리를 쥠(release 누락)"; echo "$HS_MSG" >&2; return 3; }""", """  :""")' \
  && { LIB="$T/lib-v10.sh"; runv "10(재획득 허용)" R11; }
LIB="$BASE"
[ -z "$BAD" ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail$BAD"; exit 1
