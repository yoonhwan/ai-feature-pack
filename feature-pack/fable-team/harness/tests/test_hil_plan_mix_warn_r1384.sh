#!/usr/bin/env bash
# test_hil_plan_mix_warn_r1384.sh — r1384: 자율 ON 중 h 계획에 desk 줄(scope-stop·approve-merge·좌석 닫기)과 오빠 줄(on/off·approve-scope·forget-kind…)이 섞이면 ft-hil --add 가 WARN 1줄(등록 그대로)
#   카드 반례 X1~X7 · 변이 5(모드 검사 끔 · desk 셈 끔 · warn 내보내기 삭제 · echo 인자 거름 끔 · 주석 거름 끔) · bin·kit 같은 내용 · ft-hil.sh 200줄
# 격리: 임시 HIL_DIR·임시 계획 · FT_AUTONOMY_MODE_CMD 대역(on|off|실패 · 호출 기록 calls.log) · FT_SCOPE_STATUS_CMD 대역 · 실 자율 상태·실 /tmp/h*·실 우편함 0
#   자기 재호출 0(변이는 bin 사본) · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:400}";; *) ok "$3";; esac; }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

mkdir -p "$T/home" "$T/comm" "$T/st"
stub() {  # <이름> <rc> <출력> — 자율 모드·범위 대역(부를 때마다 calls.log 1줄)
  printf '#!/bin/bash\necho x >> "%s/calls.log"\nprintf "%%s\\n" %q\nexit %s\n' "$T" "$3" "$2" > "$T/st/$1"
}
stub on 0 on; stub off 0 off; stub fail 1 boom
stub scope-alive 0 '[범위 승인 S4 · A23 · ~10-31 22:38까지 · 0/100 · 오늘 0/50 · docs,ff,revert,code · code 0/33]'
SHA=6d5975bc0123456789abcdef0123456789abcdef
HD="$T/hil"; mkdir -p "$HD"
fresh() { rm -rf "$HD"; mkdir -p "$HD"; : > "$T/calls.log"; }
hil() {  # <bin> <모드 대역> <범위 대역> <계획> — 한 줄(ft_secret_judge 가 env 뒤 명령을 글자로 확정)
  env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$T/comm" FT_AUTONOMY_MODE_CMD="bash $T/st/$2" FT_SCOPE_STATUS_CMD="bash $T/st/$3" bash "$1/ft-hil.sh" --add "$T/$4.sh.hil" 2>&1
}
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
nc() { wc -l < "$T/calls.log" 2>/dev/null | tr -d ' ' || echo 0; }
plan() { printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-planner-master-claude#1\n# 자율 A2\nA=/x/ft-autonomy.sh\n%s\n' "$2" > "$T/$1.sh.hil"; }
plan x1 "bash \"\$A\" approve-merge $SHA
bash \"\$A\" approve-scope --for 9h --max 500"
plan x3 "bash \"\$A\" approve-scope --for 9h --max 500
bash \"\$A\" on"
plan x4 "bash \"\$A\" scope-stop S4 \"되돌림\"
bash /x/ft-seat-close.sh byz-x-nano#0"
plan x5 "# bash \"\$A\" approve-merge $SHA
echo \"승인은 approve-merge · scope-stop · ft-seat-close.sh 로\"
bash \"\$A\" approve-scope --for 9h # scope-stop 아님
printf '%s\\n' 'ft-nano-close.sh'"
plan x6 "bash \"\$A\" approve-merge $SHA
bash \"\$A\" approve-scope --for 9h"

x1() { local o rc; fresh; o="$(hil "$1" on scope-none x1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && has "$o" "WARN h 계획 섞임 — desk 줄 1(5) · 오빠 줄 1 — desk 줄은 desk 가 직접(자율 ON) · h 는 오빠 손 줄만" "X1 자율 ON 섞인 계획 = WARN 1줄 · 등록 rc0·h 1" || bad "X1 rc=$rc h=$(nh) ← $o"; }
x2() { local o rc; fresh; o="$(hil "$1" off scope-none x1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && hasnt "$o" "h 계획 섞임" "X2 자율 OFF 같은 계획 = WARN 0 · 등록 rc0" || bad "X2 rc=$rc h=$(nh) ← $o"; }
x3() { local o rc; fresh; o="$(hil "$1" on scope-none x3)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && [ "$(nc)" = 0 ] && hasnt "$o" "h 계획 섞임" "X3 자율 ON 오빠 줄만 = WARN 0 · 모드 조회 0" || bad "X3 rc=$rc h=$(nh) calls=$(nc) ← $o"; }
x4() { local o rc; fresh; o="$(hil "$1" on scope-none x4)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && has "$o" "WARN h 계획 섞임 — desk 줄 2(5) · 오빠 줄 0 — h 불필요 — desk 가 직접(자율 ON)" "X4 자율 ON desk 줄만 = «h 불필요» WARN · 등록 rc0" || bad "X4 rc=$rc h=$(nh) ← $o"; }
x5() { local o rc; fresh; o="$(hil "$1" on scope-none x5)"; rc=$?
  [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && [ "$(nc)" = 0 ] && hasnt "$o" "h 계획 섞임" "X5 주석·echo·printf 안 desk 낱말 = WARN 0 · 모드 조회 0" || bad "X5 rc=$rc h=$(nh) calls=$(nc) ← $o"; }
x6() { local o rc; fresh; o="$(hil "$1" on scope-alive x6)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$o" "REJECT 범위 승인 S4 중 approve-merge" "X6 범위 중 approve-merge = 범위 판정기 REJECT rc1 그대로 · 등록 0" && hasnt "$o" "h 계획 섞임" "X6 REJECT 뒤 섞임 WARN 0" || bad "X6 rc=$rc h=$(nh) ← $o"; }
x7() { local o rc; fresh; o="$(hil "$1" fail scope-none x1)"; rc=$?
  [ "$rc" != 0 ] && [ "$(nh)" = 0 ] && has "$o" "ERROR ft-hil 판정기 실행 실패" "X7 모드 조회 실패 = ERROR · 등록 0 · rc=$rc" || bad "X7 rc=$rc h=$(nh) ← $o"; }
stub scope-none 0 '[범위 승인 없음]'

sec "X1~X7"
for k in x1 x2 x3 x4 x5 x6 x7; do "$k" "$BIN0"; done
sec "X1 kit 쪽도 같다"
x1 "$KIT"; x4 "$KIT"

sec "bin·kit 같은 내용 · 줄 상한"
for f in ft_hil_mix_judge.py ft-hil.sh ft_scope_plan_judge.py ft_traffic_plan_judge.py; do
  cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"
done
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-hil.sh ${n}줄 ≤200" || bad "ft-hil.sh ${n}줄 > 200"

sec "변이 5 — 각각 해당 반례 FAIL 검출"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }
mut() {  # <이름> <바꿀 파일> <sed 식> <검출 반례...> — 사본을 만들어 고치고 · 사본 ≠ 원본 · 반례가 FAIL 하면 검출
  local name="$1" f="$2" ex="$3" m="$T/mut-$1" k; shift 3
  cp -R "$BIN0" "$m" && sed "$ex" "$BIN0/$f" > "$m/$f"
  if cmp -s "$BIN0/$f" "$m/$f"; then bad "변이 $name 사본 = 원본"; return; fi
  for k in "$@"; do mutv "$k" "$m" && ok "변이 $name → $k FAIL 검출" || bad "변이 $name 을 $k 로 못 잡음"; done
}
mut mode-off ft_hil_mix_judge.py 's/\[-1\] == "on"/[-1] != "zzz"/' x2
mut desk-off ft_hil_mix_judge.py 's/\[n for n, d, _ in ks if d\]/[]/' x1 x4
mut warn-emit ft-hil.sh 's/case "\$out" in warn\*) echo "WARN \${out#warn }" >&2;; esac; //' x1 x4
mut text-off ft_hil_mix_judge.py 's/if cmd not in TEXT:/if True:/' x5
mut comment-off ft_hil_mix_judge.py 's/cut, subs, q = scan(line)/cut, subs, q = line, [], ""/' x5

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
