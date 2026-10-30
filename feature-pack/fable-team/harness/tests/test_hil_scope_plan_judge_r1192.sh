#!/usr/bin/env bash
# test_hil_scope_plan_judge_r1192.sh — r1192: 범위 승인(S) 중 h 계획의 approve-merge 줄 = ft-hil --add 등록 전 REJECT(scope-approve 로) · scope-status 끝 시각에 날짜
#   카드 반례 R1~R7 · 변이 1(ft-hil 판정 호출 삭제) · bin·kit 같은 내용 · 줄 상한
# 격리: 임시 HIL_DIR·임시 계획 · FT_SCOPE_STATUS_CMD 대역(출력·rc 고정 · 호출 기록 calls.log) · 임시 FT_ROOT 상태(autonomy.json·log) + FT_NOW 고정 시계
#   실 autonomy.log·실 /tmp/h*·실 gh 0 · 자기 재호출 0(변이는 bin 사본을 함수로 돌린다) · 고정 sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN0="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
sec() { echo "== $1 (누적 $((SECONDS - T0))s)"; }

mkdir -p "$T/home" "$T/comm" "$T/st"
st() {  # <이름> <rc> <출력> — scope-status 대역(부를 때마다 calls.log 1줄)
  printf '#!/bin/bash\necho x >> "%s/calls.log"\nprintf "%%s\\n" %q\nexit %s\n' "$T" "$3" "$2" > "$T/st/$1"; chmod +x "$T/st/$1"
}
st alive 0 '[범위 승인 S4 · A23 · ~10-31 22:38까지 · 0/100 · 오늘 0/50 · docs,ff,revert,code · code 0/33]'
st none 0 '[범위 승인 없음]'
st stop 0 '[범위 승인 S4 정지: 자율 모드 OFF]'
st fail 1 'boom'
st weird 0 '[자율 ON A23]'
SHA=6d5975bc0123456789abcdef0123456789abcdef
HD="$T/hil"; mkdir -p "$HD"
hil() { env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$T/comm" FT_SCOPE_STATUS_CMD="$T/st/$2" bash "$1/ft-hil.sh" --add "$T/$4.sh.hil" 2>&1; }   # <bin> <scope-status 대역> <빈 칸> <계획> — 한 줄(ft_secret_judge 가 env 뒤 명령을 글자로 확정)
nh() { find "$HD" -maxdepth 1 -name 'h[0-9]*' ! -name '*.*' | wc -l | tr -d ' '; }
nc() { wc -l < "$T/calls.log" 2>/dev/null | tr -d ' ' || echo 0; }
plan() { printf '#!/usr/bin/env bash\n# ft-hil-request seat=byz-planner-master-claude#1\n# 자율 A2 · 범위 S4(code)\nA=/x/ft-autonomy.sh\n%s\n' "$2" > "$T/$1.sh.hil"; }
plan merge "bash \"\$A\" approve-merge $SHA"
plan scope "bash \"\$A\" scope-approve $SHA --pr 5234 --card design/x.md"
plan quiet "# 옛 길: bash \"\$A\" approve-merge $SHA
echo \"승인은 approve-merge 말고 scope-approve\"; bash \"\$A\" scope-approve $SHA --pr 1 # approve-merge 아님
echo 'x \$(bash \"\$A\" approve-merge)'"
plan r1b "echo \"\$(bash \"\$A\" approve-merge \"$SHA\")\""
plan r1c "printf '%s\\\\n' '# approval'; bash \"\$A\" approve-merge \"$SHA\""
plan r1d "eval \"bash \$A approve-merge $SHA\""
plan r1e "bash -c \"bash \$A approve-merge $SHA\""
plan r1f "M=approve-merge; bash \"\$A\" \"\$M\" \"$SHA\""

check_r1() { local o rc n0; n0="$(nh)"; o="$(hil "$1" alive "" merge)"; rc=$?
  [ "$rc" = 1 ] && [ "$(nh)" = "$n0" ] && has "$o" "REJECT 범위 승인 S4 중 approve-merge — scope-approve <sha> --pr <N> [--card <카드>] [--repo byz|pack] 로 (판정 2904) — 줄 5" "R1 범위 S4 살아 있음 + approve-merge = REJECT · 등록 0" || bad "R1 rc=$rc h=$(nh) ← $o"; }
check_r1x() { local o rc n0; n0="$(nh)"; o="$(hil "$1" alive "" "$2")"; rc=$?   # R1b~R1e: 실행되는 $( )·따옴표 벗긴 '#' 인자·eval·bash -c
  [ "$rc" = 1 ] && [ "$(nh)" = "$n0" ] && has "$o" "REJECT 범위 승인 S4 중 approve-merge" "R1 $2 $(sed -n 5p "$T/$2.sh.hil") = REJECT · 등록 0" || bad "R1 $2 rc=$rc h=$(nh) ← $o"; }
sec "R1~R4 범위 상태별"
check_r1 "$BIN0"
for k in r1b r1c r1d r1e r1f; do check_r1x "$BIN0" "$k"; done
o="$(hil "$BIN0" alive "" scope)"; rc=$?; [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && ok "R2 scope-approve 계획 = 등록 rc0" || bad "R2 rc=$rc h=$(nh) ← $o"
o="$(hil "$BIN0" none "" merge)"; rc=$?; [ "$rc" = 0 ] && [ "$(nh)" = 2 ] && ok "R3 범위 승인 없음 + approve-merge = 등록 rc0" || bad "R3 rc=$rc h=$(nh) ← $o"
rm -rf "$HD"; mkdir -p "$HD"
o="$(hil "$BIN0" stop "" merge)"; rc=$?; [ "$rc" = 0 ] && [ "$(nh)" = 1 ] && ok "R4 범위 정지 + approve-merge = 등록 rc0" || bad "R4 rc=$rc h=$(nh) ← $o"
sec "R5 주석·echo 글자만 = 후보 0 · 범위 조회 0"
: > "$T/calls.log"; o="$(hil "$BIN0" alive "" quiet)"; rc=$?
[ "$rc" = 0 ] && [ "$(nc)" = 0 ] && ok "R5 주석 줄·echo 문자열·줄 끝 주석·작은따옴표 안 \$( ) = 등록 rc0 · scope-status 호출 0" || bad "R5 rc=$rc calls=$(nc) ← $o"
sec "R6 범위 조회 실패 = ERROR 등록 0"
for k in fail weird; do rm -rf "$HD"; mkdir -p "$HD"; o="$(hil "$BIN0" "$k" "" merge)"; rc=$?
  [ "$rc" != 0 ] && [ "$(nh)" = 0 ] && has "$o" "ERROR ft-hil 판정기 실행 실패" "R6 조회 $k = ERROR · rc=$rc · 등록 0" || bad "R6 $k rc=$rc h=$(nh) ← $o"
done

sec "R7 scope-status 끝 시각에 날짜 + 실 scope-status 길(대역 없이) R1"
U="$(date -j -f '%Y-%m-%d %H:%M:%S' '2026-10-31 22:38:00' +%s 2>/dev/null || date -d '2026-10-31 22:38:00' +%s)"; NOW=$((U - 3600))
R="$T/root"; S="$R/.fable-team/state"; mkdir -p "$S"
printf '{"mode": "on", "since": %s, "event": "A1", "until": null}\n' "$NOW" > "$S/autonomy.json"
printf '%s\ton\tA1\napprove-scope S1 A1 %s until=%s max=30 daily=10 classes=docs\n' "$NOW" "$NOW" "$U" > "$S/autonomy.log"
o="$(env -i HOME="$T/home" PATH="/usr/bin:/bin" FT_ROOT="$R" FT_NOW="$NOW" bash "$BIN0/ft-autonomy.sh" scope-status 2>&1)"
[ "$o" = "[범위 승인 S1 · A1 · ~10-31 22:38까지 · 0/30 · 오늘 0/10 · docs]" ] && ok "R7 «~10-31 22:38까지»" || bad "R7 ← $o"
rm -rf "$HD"; mkdir -p "$HD"
o="$(env -i HOME="$T/home" PATH="/usr/bin:/bin" HIL_DIR="$HD" HIL_CLIP=0 FT_SECRET_JUDGE="$T/none.py" FT_MBOX_DIR="$T/comm" FT_ROOT="$R" FT_NOW="$NOW" bash "$BIN0/ft-hil.sh" --add "$T/merge.sh.hil" 2>&1)"; rc=$?
[ "$rc" = 1 ] && [ "$(nh)" = 0 ] && has "$o" "REJECT 범위 승인 S1 중 approve-merge" "R1' 실 ft-autonomy.sh scope-status 길 = REJECT · 등록 0" || bad "R1' rc=$rc h=$(nh) ← $o"

sec "bin·kit 같은 내용 · 줄 상한"
for f in ft_scope_plan_judge.py ft-hil.sh ft-autonomy-scope.sh; do
  cmp -s "$BIN0/$f" "$KIT/$f" && ok "bin=kit $f" || bad "bin≠kit $f"
done
n="$(wc -l < "$BIN0/ft-hil.sh" | tr -d ' ')"; [ "$n" -le 200 ] && ok "ft-hil.sh ${n}줄 ≤200" || bad "ft-hil.sh ${n}줄 > 200"
n="$(wc -l < "$BIN0/ft_scope_plan_judge.py" | tr -d ' ')"; [ "$n" -le 130 ] && ok "판정기 ${n}줄 ≤130" || bad "판정기 ${n}줄 > 130"

sec "변이 2 — 판정 호출 삭제 → R1 FAIL · 재귀 삭제 → R1b FAIL 검출"
mutv() { local f0=$fail; "$@" > /dev/null 2>&1; local d=$((fail - f0)); fail=$f0; [ "$d" -gt 0 ]; }
m="$T/mut-judge"; cp -R "$BIN0" "$m" && sed 's/ && lint "\$f" "\${FT_SCOPE_JUDGE[^}]*}" "범위 승인 경로" ""//' "$BIN0/ft-hil.sh" > "$m/ft-hil.sh"
if cmp -s "$BIN0/ft-hil.sh" "$m/ft-hil.sh"; then bad "변이 사본 = 원본"; else rm -rf "$HD"; mkdir -p "$HD"; mutv check_r1 "$m" && ok "변이 1(판정 호출 삭제) → R1 FAIL 검출" || bad "변이 1 을 못 잡음"; fi
m="$T/mut-rec"; cp -R "$BIN0" "$m" && sed 's/if q or any(is_candidate(s) for s in subs):/if q:/' "$BIN0/ft_scope_plan_judge.py" > "$m/ft_scope_plan_judge.py"
if cmp -s "$BIN0/ft_scope_plan_judge.py" "$m/ft_scope_plan_judge.py"; then bad "변이 2 사본 = 원본"; else rm -rf "$HD"; mkdir -p "$HD"; mutv check_r1x "$m" r1b && ok "변이 2(\$( )·백틱 재귀 삭제) → R1b FAIL 검출" || bad "변이 2 를 못 잡음"; fi

sec "끝"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAIL $fail"; exit 1; }
