#!/usr/bin/env bash
# test_hil_entry_run_lock_r2193.sh — r2193: 같은 h 를 겹쳐 돌리면 둘째는 «REJECT 실행 중» rc 1 · 쓰기 0 · 쪽지 0 · 실행마다 .out 사본
#   카드 반례 ②~⑫(① = 기존 hil 시험 재실행 · 이 파일 밖) · 변이 M1~M6(사본 · 변이마다 원본 같은 칸 대조) · bin·kit 같은 바이트 · ft-hil.sh 200줄
#   사용: bash <이 파일> [cases|mut|all(기본)] · 기준판 = R2193_BIN=<기준판 bin>(② ③ ④ ⑥ ⑦ ⑩ ⑪ FAIL = Red)
# 격리: 임시 HIL_DIR · 임시 HOME · 가짜 mbox.sh · 리포 밖 계획 · 멈춤 = fifo(시험이 풀어 줌) — 실 /tmp/h* · 실 쪽지함 0 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="${R2193_BIN:-$HERE/../bin}"; KIT="$HERE/../kit/fable-team/bin"; MODE="${1:-all}"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'kill $(cat "$T"/*.pid 2>/dev/null) 2>/dev/null; rm -rf "$T"' EXIT
fail=0; T0=$SECONDS; WHY=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }
chk() { local t="$1"; shift; WHY=""; if "$@"; then ok "$t"; else bad "$t — $WHY"; fi; }
C="$T/comm"; mkdir -p "$C" "$T/home"
printf '#!/bin/bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "$(dirname "$0")/sent.log"\n' > "$C/mbox.sh"
hil()  { local b="$1"; shift; env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/n" FT_TRAFFIC_JUDGE="$T/n" FT_SCOPE_JUDGE="$T/n" FT_MIX_JUDGE="$T/n" FT_PACK_PATH_JUDGE="$T/n" FT_MBOX_DIR="$C" bash "$b/ft-hil.sh" "$@" 2>/dev/null; }
TO="$(command -v timeout || command -v gtimeout || echo env)"; [ "$TO" = env ] && TO="env" || TO="$TO 30"
runh() { ( cd "$T" && exec env -i HOME="$T/home" PATH="/usr/bin:/bin" $TO bash "$H" ); }   # 사람이 치는 `bash /tmp/h<N>` · 30초 = 멈춘 변이의 상한
bgh()  { ( cd "$T" && exec env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$H" ) > "$T/$1.o" 2>&1 & echo $! > "$T/$1.pid"; }   # 뒤로 띄움 · pid = 진입 bash
fresh() { HD="$T/hd-$1"; rm -rf "$HD"; mkdir -p "$HD"; rm -f "$C/sent.log"; }   # 칸마다 새 폴더(h 번호가 h1 부터) · 쪽지 장부 비움
nsent() { cat "$C/sent.log" 2>/dev/null | grep -c "\[완료 ${H##*/}\]"; }
# 계획: RUNS 에 1줄 → 첫 실행만 UP 에 알리고 GO 를 기다린다 · 나머지 = 실행 번호 글 + rc $RC2(기본 2)
reg() {  # <bin> <칸> [첫 실행 멈춤 0|1] → HD · H · RUNS · UP · GO
  local s="${3:-1}"; fresh "$2"; RUNS="$T/runs-$2"; UP="$T/up-$2"; GO="$T/go-$2"; rm -f "$RUNS" "$UP" "$GO"; mkfifo "$UP" "$GO"
  printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-harness-desk-claude#1\necho r >> %q; n=$(wc -l < %q | tr -d " ")\nif [ "$n" = 1 ] && [ %s = 1 ]; then echo "첫째-글"; echo up > %q; read -r x < %q; echo "=== 결과 === 첫째"; exit 0; fi\necho "=== 결과 === 실행-$n"; exit %s\n' \
    "$RUNS" "$RUNS" "$s" "$UP" "$GO" "${RC2:-2}" > "$T/p$2.sh.hil"
  H="$(hil "$1" --add "$T/p$2.sh.hil")"; H="${H#! bash }"; [ -f "$H" ] || { WHY="등록 실패"; return 1; }; }
hold_up() { exec 7<>"$UP" 8<>"$GO"; read -r -t 20 _ <&7 || { WHY="첫 실행이 UP 에 안 옴"; return 1; }; }
release() { echo go >&8; echo go >&8; }
nruns() { [ -f "$RUNS" ] && wc -l < "$RUNS" | tr -d ' ' || echo 0; }
dead() { bash -c 'exit 0' & local p=$!; wait "$p"; echo "$p"; }
nolock() { [ ! -e "$H.lock" ] && [ ! -e "$H.lock.take" ] || { WHY="$WHY 잠금 남음"; return 1; }; }

c2() {  # 겹침: 첫째 멈춘 동안 둘째 → 둘째 rc 1 «REJECT 실행 중» · .ran 1줄 · .out 불변 · 쪽지 0 · 첫째 풀면 rc 0 · 쪽지 1 · 결과 = 첫째
  reg "$1" 2 || return 1; bgh a; hold_up || return 1
  local o0 o rc r1; o0="$(cat "$H.out")"; o="$(runh 2>&1)"; rc=$?
  WHY="둘째 rc=$rc .ran=$(wc -l < "$H.ran" | tr -d ' ') 쪽지=$(nsent) ← ${o:0:200}"
  [ "$rc" = 1 ] && grep -q "REJECT 실행 중 — ${H##*/} pid" <<< "$o" && [ "$(wc -l < "$H.ran" | tr -d ' ')" = 1 ] && [ "$o0" = "$(cat "$H.out")" ] && [ "$(nsent)" = 0 ] || { release; wait "$(cat "$T/a.pid")"; return 1; }
  release; wait "$(cat "$T/a.pid")"; r1=$?
  WHY="첫째 rc=$r1 쪽지=$(nsent) 실행=$(nruns) ← $(tail -2 "$C/sent.log" 2>/dev/null)"
  [ "$r1" = 0 ] && [ "$(nsent)" = 1 ] && [ "$(nruns)" = 1 ] && grep -q "\[완료 ${H##*/}\] rc=0 · === 결과 === 첫째" "$C/sent.log" && nolock; }
c3() {  # 차례 실행 2번 → .ran 4줄 · 쪽지 2 · 사본 2 각 제 글 · .out = 둘째 글
  local rc1 rc2 cs; RC2=0 reg "$1" 3 0 || return 1; runh >/dev/null 2>&1; rc1=$?; runh >/dev/null 2>&1; rc2=$?
  cs="$(cat "$H".out.*.* 2>/dev/null | grep -c '=== 결과 === 실행-')"
  WHY="rc=$rc1/$rc2 .ran=$(wc -l < "$H.ran" | tr -d ' ') 쪽지=$(nsent) 사본=$(ls "$H".out.*.* 2>/dev/null | wc -l | tr -d ' ')($cs)"
  [ "$rc1$rc2" = 00 ] && [ "$(wc -l < "$H.ran" | tr -d ' ')" = 4 ] && [ "$(nsent)" = 2 ] && grep -q '실행-1 ·' "$C/sent.log" && grep -q '실행-2 ·' "$C/sent.log" \
    && [ "$(ls "$H".out.*.* 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && [ "$cs" = 2 ] && [ "$(cat "$H".out.*.* | grep -c '실행-1')" = 1 ] && grep -q '실행-2' "$H.out" && ! grep -q '실행-1' "$H.out" && nolock; }
c4() {  # 죽은 잠금 → INFO · 실행 · 끝난 뒤 .lock 없음
  local o rc; reg "$1" 4 0 || return 1; echo "$(dead) 1700000000" > "$H.lock"; o="$(runh 2>&1)"; rc=$?
  WHY="rc=$rc 실행=$(nruns) ← ${o:0:200}"; [ "$rc" = 2 ] && [ "$(nruns)" = 1 ] && grep -q "INFO 죽은 잠금 넘겨받음" <<< "$o" && nolock; }
c5() {  # 깨진 잠금(abc · 빈 파일) → rc 3 판정 불가 · 실행 0 · .ran .out 0
  local o rc x; for x in abc ''; do reg "$1" "5$x" 0 || return 1; printf '%s' "$x" > "$H.lock"; o="$(runh 2>&1)"; rc=$?
    WHY="«${x}» rc=$rc 실행=$(nruns) ← ${o:0:200}"; [ "$rc" = 3 ] && grep -q "판정 불가 — ${H##*/}.lock" <<< "$o" && [ "$(nruns)" = 0 ] && [ ! -e "$H.ran" ] && [ ! -e "$H.out" ] || return 1; done; }
c6() {  # 신호: 계획+자식이 fifo 에서 멈춘 진입에 TERM → rc 143 · 계획·자식 0 · .lock 없음 · 풀린 뒤 .out 불변 · 다음 실행 됨
  local rc sz pp kp; fresh 6; rm -f "$T/six.done"; UP="$T/up-6"; GO="$T/go-6"; rm -f "$UP" "$GO"; mkfifo "$UP" "$GO"
  printf '#!/usr/bin/env bash\n[ -e %q ] && { echo 다음-실행; exit 0; }\necho $$ > %q; ( read -r y < %q; echo 자식-글 ) & echo $! > %q\necho up > %q; read -r x < %q; echo 계획-글\n' \
    "$T/six.done" "$T/six-plan.pid" "$GO" "$T/six-kid.pid" "$UP" "$GO" > "$T/p6.sh.hil"
  H="$(hil "$1" --add "$T/p6.sh.hil")"; H="${H#! bash }"; [ -f "$H" ] || { WHY="등록 실패"; return 1; }
  bgh six; hold_up || return 1; kill -TERM "$(cat "$T/six.pid")"; wait "$(cat "$T/six.pid")"; rc=$?
  pp="$(cat "$T/six-plan.pid")"; kp="$(cat "$T/six-kid.pid")"; sz="$(wc -c < "$H.out")"
  WHY="rc=$rc 계획 산=$(kill -0 "$pp" 2>/dev/null && echo 1 || echo 0) 자식 산=$(kill -0 "$kp" 2>/dev/null && echo 1 || echo 0)"   # 살아 있는지는 fifo 를 풀기 전에 본다
  { kill -0 "$pp" || kill -0 "$kp"; } 2>/dev/null && { kill -9 "$pp" "$kp" 2>/dev/null; release; return 1; }
  release; release; WHY="$WHY .out ${sz}→$(wc -c < "$H.out")"
  [ "$rc" = 143 ] && nolock && [ "$sz" = "$(wc -c < "$H.out")" ] && [ "$(nsent)" = 0 ] || return 1
  : > "$T/six.done"; runh > /dev/null 2>&1 || { WHY="다음 실행 rc=$?"; return 1; }; grep -q 다음-실행 "$H.out"; }
c7() {  # 계획 rc 7 → rc 7 · 쪽지 1 · .lock 없음 · 사본 1
  local rc; RC2=7 reg "$1" 7 0 || return 1; runh >/dev/null 2>&1; rc=$?
  WHY="rc=$rc 쪽지=$(nsent) 사본=$(ls "$H".out.*.* 2>/dev/null | wc -l | tr -d ' ')"; [ "$rc" = 7 ] && [ "$(nsent)" = 1 ] && [ "$(ls "$H".out.*.* 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && nolock; }
c8() {  # --pending: .lock · 사본 파일이 있어도 출력이 같다
  local a b c d; reg "$1" 8 0 || return 1; a="$(hil "$1" --pending)"; b="$(hil "$1" --pending --each)"
  echo "$$ 1700000000" > "$H.lock"; echo x > "$H.out.1700000000.123"; c="$(hil "$1" --pending)"; d="$(hil "$1" --pending --each)"
  WHY="«${a}»→«${c}» «${b}»→«${d}»"; [ -n "$a" ] && [ "$a" = "$c" ] && [ "$b" = "$d" ]; }
c9() {  # 대체됨 · 보류 → 기준판과 같은 REJECT · .lock 0 / 이상한 계획 경로 → 표식 0
  local o rc d="$T/d \`touch BT\` \$(touch DL)"; reg "$1" 9 0 || return 1; cp "$T/p9.sh.hil" "$T/p9x.sh.hil"
  hil "$1" --add "$T/p9x.sh.hil" --supersedes "${H##*/}" >/dev/null; o="$(runh 2>&1)"; rc=$?
  WHY="대체 rc=$rc 실행=$(nruns) ← ${o:0:120}"; [ "$rc" = 1 ] && grep -q 'REJECT 대체됨' <<< "$o" && nolock && [ "$(nruns)" = 0 ] || return 1
  reg "$1" 9c 0 || return 1; hil "$1" --hold "${H##*/}" --why 시험 >/dev/null; o="$(runh 2>&1)"; rc=$?
  WHY="보류 rc=$rc ← ${o:0:120}"; [ "$rc" = 1 ] && grep -q 'REJECT 보류 중' <<< "$o" && nolock && [ "$(nruns)" = 0 ] || return 1
  mkdir -p "$d"; printf '#!/usr/bin/env bash\necho 이상한-경로\n' > "$d/p.sh.hil"; fresh 9d; H="$(hil "$1" --add "$d/p.sh.hil")"; H="${H#! bash }"
  o="$(runh 2>&1)"; rc=$?; WHY="경로 rc=$rc BT=$([ -e "$T/BT" ] && echo 1) DL=$([ -e "$T/DL" ] && echo 1) ← ${o:0:120}"
  [ "$rc" = 0 ] && [ ! -e "$T/BT" ] && [ ! -e "$T/DL" ] && grep -q 이상한-경로 "$H.out" && nolock; }
c10() {  # 넘겨받기 경합: 죽은 .lock + 두 실행 함께 → 계획 1 · 쪽지 1 · 다른 하나 rc 1 · 잠금 0
  local f="$T/ten.done" r a b x; reg "$1" 10 || return 1; echo "$(dead) 1700000000" > "$H.lock"; rm -f "$f"; mkfifo "$f"; exec 9<>"$f"
  for x in a b; do ( ( cd "$T" && exec env -i HOME="$T/home" PATH="/usr/bin:/bin" bash "$H" ) > "$T/ten-$x.o" 2>&1; echo "$x $?" >&9 ) & echo $! > "$T/ten-$x.pid"; done
  hold_up || { release; return 1; }; read -r -t 20 a r <&9 || { WHY="겹친 하나가 안 끝남 · 실행=$(nruns)"; release; return 1; }
  WHY="먼저 끝난 $a rc=$r 실행=$(nruns) ← $(head -c 200 "$T/ten-$a.o")"; [ "$r" = 1 ] && grep -q 'REJECT 실행 중' "$T/ten-$a.o" || { release; return 1; }
  release; read -r -t 20 b r <&9; WHY="나중 $b rc=$r 실행=$(nruns) 쪽지=$(nsent)"; [ "$r" = 0 ] && [ "$(nruns)" = 1 ] && [ "$(nsent)" = 1 ] && nolock; }
c11() {  # 넘겨받기 잠금: 죽은 .lock + 산 .take → rc 1 · 불변 · 실행 0 / 죽은 .take → rc 3 · 두 파일 불변
  local o rc l t; reg "$1" 11 0 || return 1; l="$(dead) 1700000000"; echo "$l" > "$H.lock"; echo "$$" > "$H.lock.take"; o="$(runh 2>&1)"; rc=$?
  WHY="산 take rc=$rc 실행=$(nruns) ← ${o:0:150}"; [ "$rc" = 1 ] && grep -q 'REJECT 실행 중' <<< "$o" && [ "$(cat "$H.lock")" = "$l" ] && [ "$(nruns)" = 0 ] || return 1
  t="$(dead)"; echo "$t" > "$H.lock.take"; o="$(runh 2>&1)"; rc=$?
  WHY="죽은 take rc=$rc 실행=$(nruns) ← ${o:0:150}"; [ "$rc" = 3 ] && grep -q '판정 불가' <<< "$o" && [ "$(cat "$H.lock")" = "$l" ] && [ "$(cat "$H.lock.take")" = "$t" ] && [ "$(nruns)" = 0 ]; }
c12() {  # stdin: 한 줄을 파이프로 → 계획이 읽어 낸 글 = 넣은 글
  local o; fresh 12; printf '#!/usr/bin/env bash\nread -r l; echo "got=$l"\n' > "$T/p12.sh.hil"
  H="$(hil "$1" --add "$T/p12.sh.hil")"; H="${H#! bash }"; o="$(printf 'stdin-줄-12\n' | runh 2>/dev/null)"; WHY="← ${o:0:120}"; grep -q 'got=stdin-줄-12' <<< "$o" && grep -q 'got=stdin-줄-12' "$H.out"; }

if [ "$MODE" != mut ]; then
  for c in 2 3 4 5 6 7 8 9 10 11 12; do sec "반례 c$c"; chk "반례 ⑵~⑿ c$c" "c$c" "$BIN0"; done
  sec "bin·kit 같은 바이트 · 200줄"
  cmp -s "$BIN0/ft-hil.sh" "$KIT/ft-hil.sh" && ok "cmp bin·kit ft-hil.sh" || bad "bin·kit 다름"
  [ "$(wc -l < "$BIN0/ft-hil.sh")" -le 200 ] && ok "ft-hil.sh ≤200줄" || bad "ft-hil.sh 200줄 초과"
fi
mut() {  # <이름> <sed 식> <칸> → 변이 사본에서 그 칸 FAIL · 원본에서 같은 칸 PASS
  local m="$T/mut-$1" f0=$fail; cp -R "$BIN0" "$m"; sed "$2" "$BIN0/ft-hil.sh" > "$m/ft-hil.sh"
  cmp -s "$BIN0/ft-hil.sh" "$m/ft-hil.sh" && { bad "변이 $1 사본 = 원본(sed 안 맞음)"; return; }
  "$3" "$m" >/dev/null 2>&1 && bad "변이 $1 → $3 PASS(못 잡음)" || ok "변이 $1 → $3 FAIL(검출) — ${WHY:0:160}"
  WHY=""; "$3" "$BIN0" >/dev/null 2>&1 && ok "원본 대조 $1 → $3 PASS" || bad "원본 대조 $1 → $3 FAIL — $WHY"; }
if [ "$MODE" != cases ]; then
  sec "변이 M1~M6"
  mut M1-잠금잡기뺌 's/; tk   # r2193 B3/   # r2193 B3/' c2
  mut M2-신호풀기뺌 's/; fi; rd "\$K" \&\& \[ "\$p" = \$\$ \] \&\& unlink "\$K" 2>\/dev\/null;/; fi;/' c6
  mut M3-사본뺌 's/cp -p "\$M.out" "\$M.out.\$S0.\$\$"/true/' c3
  mut M4-넘겨받기뺌 's/! al "\$p" || bz; local d/bz; local d/' c4
  mut M5-take잡기뺌 's/if ! lk "\$K.take" "\$\$"; then/if false; then/' c11
  mut M6-신호끝내기뺌 's/if \[ -n "\$W" \]; then/if false; then/' c6
fi
echo "== 결과: FAIL $fail · 총 $((SECONDS - T0))s"
[ "$fail" -eq 0 ]
