#!/usr/bin/env bash
# test_resource_watch_proc_count.sh — r1041 ft-resource-watch.sh tick 의 proc_watch(ft-resource-proc-lib.sh):
#   ⓐ 사용자 프로세스 수 ≥ 임계(기본 4000) → planner _master 에 [프로세스 폭주] 쪽지 1통(같은 사건이면 다시 안 보냄)
#   ⓑ 같은 명령줄 ≥ 임계(기본 200) → 그 명령줄 프로세스만 SIGSTOP(다른 프로세스 0 · kill 0 · 정리 kill 은 HIL)
#   ⓒ ps 표본 실패 → «판정 불가» 로그 1줄 · 쪽지 0 · 정지 0
# 가짜 센서(PE PATH 앞)·가짜 ps 표본 파일(FT_RES_PROC_PS)·가짜 kill(FT_RES_KILL_CMD)·가짜 mbox·임시 루트만 쓴다 —
#   ★실제 프로세스를 늘리지 않고 실제 신호도 보내지 않는다★(이 카드의 사고를 시험으로 재현하지 않는다 · r1041).
# 상한: 이 시험은 70초 안에 끝나고 자기 자신을 다시 부르지 않는다(하드 룰 22).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_RECLAIM_PREVENT_SEC=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
for f in ft-resource-watch.sh ft-resource-proc-lib.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
bash -n "$BIN/ft-resource-proc-lib.sh" && ok "bash -n proc-lib" || bad "bash -n proc-lib"
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245(새 함수는 proc-lib)" || bad "감시자 줄 수 >245"
[ "$(grep -c 'proc_watch' "$BIN/ft-resource-watch.sh")" -ge 1 ] && ok "tick 이 proc_watch 를 부른다" || bad "tick 에 proc_watch 호출 없음"
awk '/proc_watch/{n=NR} /bash "\$GATE" status/{print (n && n<NR) ? "P" : "F"; exit}' "$BIN/ft-resource-watch.sh" | grep -q P \
  && ok "proc_watch 가 문지기·동결 분기보다 앞" || bad "proc_watch 가 문지기 뒤(이른 return 에 안 돈다)"

# 가짜 센서 · 가짜 도구
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 1000.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo 1;;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 60%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
chmod 755 "$S"/*
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"                  # 선제 회수 · cpu 원인(빈 출력 = 폭주 0)
printf '#!/bin/sh\nexit 0\n' > "$T/cause_noop.sh"
printf '#!/bin/sh\necho "$*" >> "%s/killed.log"\n' "$T" > "$T/kill_stub"; chmod 755 "$T/kill_stub"   # 실제 신호 0 · 호출만 기록
MB="$T/mbox.sh"; printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$MB"; chmod 755 "$MB"
echo '{"_master": "byz-harness-planner-claude#3"}' > "$T/seats-planner.json"
PSF="$T/ps.txt"; ME="$(id -un)"
tick() { env FT_RES_ROOT="$R" FT_RES_PROC_PS="$PSF" FT_RES_PROC_USER="$ME" FT_RES_KILL_CMD="$T/kill_stub" \
  PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FT_MBOX_SH="$MB" FT_SEATS_JSON="$T/seats-planner.json" \
  FT_PREVENTIVE_SH="$T/noop.sh" FT_RESOURCE_CAUSE_SH="$T/cause_noop.sh" "$@" \
  bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
notes() { grep -c '프로세스 폭주' "$T/mbox.log" 2>/dev/null | tr -d ' '; }
stops() { if [ -f "$T/killed.log" ]; then wc -l < "$T/killed.log" | tr -d ' '; else echo 0; fi; }
reset() { : > "$T/mbox.log"; rm -f "$T/killed.log" "$ST/.proc-flood.sig" "$ST/.proc-flood.last"; }
mkps() { printf '%s\n' "$@" > "$PSF"; }
plain() { local i; for i in $(seq 1 "$1"); do printf '%s %d /usr/bin/sleep %d\n' "$ME" "$((1000+i))" "$i"; done; }

# ── R5: 사용자 프로세스 수 < 4000 · 같은 명령줄 < 200 → 쪽지 0 · 정지 0 ──
reset; mkps $(plain 50) "${ME} 9 /usr/bin/yes"
tick
eq "$(notes)" 0 "R5 수 임계 미만 → 쪽지 0"
eq "$(stops)" 0 "R5 수 임계 미만 → 정지 0"
[ -s "$ST/proc-flood.log" ] && bad "R5 proc-flood.log 가 생겼다" || ok "R5 proc-flood.log 없음"

# ── R7: 같은 명령줄 210개 → 그 프로세스만 SIGSTOP · 다른 프로세스 0 · kill 0 ──
reset; { plain 3; for i in $(seq 1 210); do printf '%s %d bash /tmp/test_da_rounds_three_r1038.sh --mutate\n' "$ME" "$((5000+i))"; done; } > "$PSF"
tick
eq "$(stops)" 210 "R7 같은 명령줄 210개 → SIGSTOP 210회"
[ "$(awk '$1!="-STOP"{c++} END{print c+0}' "$T/killed.log")" = 0 ] && ok "R7 정지가 아닌 신호 0(kill 0)" || bad "R7 -STOP 아닌 호출 있음"
[ "$(awk '$2>=5001 && $2<=5210{n++} END{print n+0}' "$T/killed.log")" = 210 ] && ok "R7 정지 대상 = 그 명령줄 pid 만" || bad "R7 다른 pid 를 정지"
eq "$(notes)" 1 "R7 같은 명령줄 폭주 → 쪽지 1통"
has "$(cat "$T/mbox.log")" "byz-harness-planner-claude#3" "R7 수신자 = planner 명부 _master"
has "$(cat "$T/mbox.log")" "HIL" "R7 정리 kill 은 HIL 로 적는다"
eq "$(awk 'END{print NR}' "$ST/proc-flood.log")" 1 "R7 proc-flood.log 1줄"
# 같은 서명 다음 tick = 쪽지 0 · 정지 0(같은 사건)
: > "$T/killed.log"; tick
eq "$(notes)" 1 "R7 같은 서명 다음 tick → 쪽지 0"
eq "$(stops)" 0 "R7 같은 서명 다음 tick → 정지 0"
# 폭주가 끝나면 서명을 지운다 — 다시 생기면 새 사건(쪽지 1통 더)
reset; mkps $(plain 50); tick
{ plain 3; for i in $(seq 1 210); do printf '%s %d bash /tmp/test_da_rounds_three_r1038.sh --mutate\n' "$ME" "$((5000+i))"; done; } > "$PSF"; tick
eq "$(notes)" 1 "R7 폭주 종료 뒤 재발 → 새 사건 쪽지 1통"

# ── R6: 사용자 프로세스 수 ≥ 4000 → 쪽지 1통 · 같은 서명이면 다시 안 보냄 ──
reset; { plain 4005; } > "$PSF"; tick
eq "$(notes)" 1 "R6 4005개 → 쪽지 1통"
has "$(cat "$T/mbox.log")" "프로세스 4005" "R6 쪽지에 프로세스 수"
tick
eq "$(notes)" 1 "R6 같은 서명 다음 tick → 쪽지 0"
eq "$(stops)" 0 "R6 총량만 폭주면 정지 0(같은 명령줄 200 미만)"
# 임계를 env 로 바꾸면 판정도 바뀐다(값이 하드코딩 아님)
reset; mkps $(plain 50); tick FT_RES_PROC_MAX=40
eq "$(notes)" 1 "R6 FT_RES_PROC_MAX=40 이면 50개도 폭주(값이 하드코딩 아님)"
tick FT_RES_PROC_MAX=40
eq "$(notes)" 1 "R6 같은 서명 → 쪽지 0(같은 사건)"
reset; mkps $(plain 50); tick FT_RES_PROC_MAX=9999 FT_RES_PROC_DUP=9999
eq "$(notes)" 0 "R6 임계를 올리면 조용"

# ── 쪽지 억제 창(기본 600초) — 서명이 바뀌어도 최근 1통이면 안 보낸다(폭주 중 도배 방지) ──
reset; { plain 4005; } > "$PSF"; tick
eq "$(notes)" 1 "억제: 첫 쪽지 1통"
{ plain 4006; } > "$PSF"; tick            # 서명이 바뀜(total=4000 유지 → 서명 동일) → 쪽지 0
eq "$(notes)" 1 "억제: 서명 같으면 0"
reset      # 서명 초기화 뒤 다시
{ plain 4005; } > "$PSF"; tick FT_RES_PROC_QUIET_SEC=0
{ plain 4005; } > "$PSF"; rm -f "$ST/.proc-flood.sig"; tick FT_RES_PROC_QUIET_SEC=600
eq "$(notes)" 1 "억제: 같은 사건 재발신은 창 안에서 0"
has "$(cat "$ST/resource-watch.log")" "쪽지 억제" "억제: 로그에 억제 1줄"

# ── R8: ps 표본 실패 → «판정 불가» 1줄 · 쪽지 0 · 정지 0 ──
reset; PSF="$T/없는표본.txt"; tick
has "$(cat "$ST/resource-watch.log")" "판정 불가" "R8 표본 실패 → 판정 불가 1줄"
eq "$(notes)" 0 "R8 표본 실패 → 쪽지 0"
eq "$(stops)" 0 "R8 표본 실패 → 정지 0"
PSF="$T/ps.txt"

# ── 다른 사용자 프로세스는 세지 않는다 ──
reset; { plain 3; for i in $(seq 1 300); do printf 'otheruser %d bash /tmp/other.sh\n' "$((7000+i))"; done; } > "$PSF"; tick
eq "$(notes)" 0 "다른 사용자 행은 판정 밖"
eq "$(stops)" 0 "다른 사용자 행은 정지 0"

# ── 회귀: cpu_watch 경로가 그대로 돈다(빈 출력 = 폭주 0) ──
reset; : > "$ST/resource-watch.log"; mkps $(plain 5); tick   # 로그를 비우고 회귀 tick 만 본다(R8 의 판정 불가 줄이 남아 있으면 오판)
[ -s "$T/killed.log" ] && bad "회귀: cpu 경로에서 정지 발생" || ok "회귀: cpu 경로 정지 0"
if grep -q 'ERROR 프로세스 수' "$ST/resource-watch.log" 2>/dev/null; then bad "회귀: proc 축 ERROR — $(tail -2 "$ST/resource-watch.log")"; else ok "회귀: proc 축 ERROR 0(다른 축 로그는 이 시험 소관 아님)"; fi

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
