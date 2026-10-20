#!/usr/bin/env bash
# test_resource_cpu_owner.sh — r522 CPU 폭주 «주인» 한 줄(ft-resource-cause.sh cpu) + 감시자 tick 기록·planner 쪽지 1통.
# 가짜 ps(FT_RES_PS)·가짜 tmux(FT_RES_TMUX)·가짜 센서·임시 루트·가짜 mbox 만 쓴다 — 실 프로세스·실 tmux·실 쪽지·kill 0.
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
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
for f in ft-resource-cause.sh ft-resource-watch.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done

# 가짜 kill·renice·pkill·killall — 불리면 기록(ⓕ)
for k in kill renice pkill killall; do printf '#!/bin/sh\necho "%s $*" >> "%s/killed.log"\n' "$k" "$T" > "$S/$k"; done
chmod 755 "$S"/*
printf 'byz-v65-master-claude#0 100 /dev/ttys003\nbyz-t-other-claude#1 400 /dev/ttys009\n' > "$T/tmux.txt"
PSF="$T/ps.txt"
base_ps() { # 셸 pane(100) · 중간 zsh(150) · 상관없는 폭주 1개(mds) · 공백 든 이름 3개(10% — 문턱 밑)
  printf '%s\n' '100 1 ttys003 1-00:00:00 0.0 -zsh' '150 100 ttys003 10:00 0.5 /bin/zsh' '300 1 ?? 02:00:00 95.0 /usr/sbin/mds' \
    '310 1 ?? 30:00 10.0 /Applications/Google Chrome.app/Contents/Google Chrome Helper' '311 1 ?? 30:00 10.0 /Applications/Google Chrome.app/Contents/Google Chrome Helper' \
    '312 1 ?? 30:00 10.0 /Applications/Google Chrome.app/Contents/Google Chrome Helper'; }
yes_ps() { # yes_ps <개수> <ppid> <tty> <etime> <pcpu>
  local i; for i in $(seq 1 "$1"); do printf '%s %s %s %s %s /usr/bin/yes\n' "$((200+i))" "$2" "$3" "$4" "$5"; done; }
c() { env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" cpu 2>&1; }

# ⓐ 조상 pane(중간 zsh 경유) → 세션
{ base_ps; yes_ps 4 150 ttys003 08:00 90.0; } > "$PSF"
out="$(c)"; rc=$?
eq "$rc" 0 "ⓐ cpu 모드 rc0"
eq "$out" "cpu yes×4 CPU 360% 8분 · 주인 byz-v65-master-claude#0" "ⓐ yes×4 각 90% 8분 → 조상 pane 의 세션 한 줄"
hasnt "$out" "mds" "ⓐ 같은 이름 3개 미만(mds 1개)은 제외"
hasnt "$out" "Chrome" "ⓐ 각 30% 미만(10%)은 제외"
# ⓑ 부모 잃음(ppid 1) · tty = 그 pane tty → 같은 세션 «(tty)»
{ base_ps; yes_ps 4 1 ttys003 08:00 90.0; } > "$PSF"
eq "$(c)" "cpu yes×4 CPU 360% 8분 · 주인 byz-v65-master-claude#0 (tty)" "ⓑ ppid 1 · tty 대조 → 같은 세션(tty)"
# ⓒ 부모 잃음 · tty 없음(??) → 주인 미상(추측 0)
{ base_ps; yes_ps 4 1 '??' 08:00 90.0; } > "$PSF"
eq "$(c)" "cpu yes×4 CPU 360% 8분 · 주인 미상" "ⓒ ppid 1 · tty ?? → 주인 미상"
# ⓔ 조건 미달 — 2개 / 4분 → 빈 출력 rc0
{ base_ps; yes_ps 2 150 ttys003 08:00 90.0; } > "$PSF"; out="$(c)"; rc=$?
eq "$rc|$out" "0|" "ⓔ 2개 → 빈 출력 rc0"
{ base_ps; yes_ps 4 150 ttys003 04:00 90.0; } > "$PSF"
eq "$(c)" "" "ⓔ 가장 오래된 것 4분 → 빈 출력"
# ps 읽기 실패 = 조용한 빈 출력 아님
: > "$PSF"; out="$(c)"; rc=$?
[ "$rc" != 0 ] && ok "ps 자료 0 → rc≠0 ($rc)" || bad "ps 자료 0 인데 rc0 «$out»"

# ⓓ 감시자 tick — 상태 파일 1줄 + planner 쪽지 1통 · 같은 서명 다음 tick 쪽지 0 · 서명 바뀌면 1통
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 1000.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo 1;;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 60%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"; printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"
MB="$T/mbox.sh"; printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$MB"
chmod 755 "$S"/* "$MB" "$T/noop.sh"
echo '{"_master": "byz-t-planner-claude#9"}' > "$T/seats-planner.json"; : > "$T/mbox.log"
tick() { env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" \
  FT_MBOX_SH="$MB" FT_SEATS_JSON="$T/seats-planner.json" FT_PREVENTIVE_SH="$T/noop.sh" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
CLOG="$ST/runaway-cpu.log"; notes() { grep -c '\[CPU 폭주\]' "$T/mbox.log" || true; }
{ base_ps; yes_ps 4 150 ttys003 08:00 90.0; } > "$PSF"
tick
eq "$(wc -l < "$CLOG" 2>/dev/null | tr -d ' ')" 1 "ⓓ tick 1 → runaway-cpu.log 1줄"
has "$(cat "$CLOG" 2>/dev/null)" "cpu yes×4 CPU 360% 8분 · 주인 byz-v65-master-claude#0" "ⓓ 로그 줄 = 주인 줄"
eq "$(notes)" 1 "ⓓ planner 쪽지 1통"
has "$(cat "$T/mbox.log")" "send byz-t-planner-claude#9 " "ⓓ 수신자 = planner 명부 _master"
has "$(cat "$T/mbox.log")" "끄기는 사람 판단 · kill 0" "ⓓ 쪽지 본문 «끄기는 사람 판단 · kill 0»"
{ base_ps; yes_ps 4 150 ttys003 09:00 95.0; } > "$PSF"; tick
eq "$(notes)" 1 "ⓓ 같은 서명(명령·주인·개수 · CPU·분만 바뀜) → 다음 tick 쪽지 0"
{ base_ps; yes_ps 5 150 ttys003 10:00 95.0; } > "$PSF"; tick
eq "$(notes)" 2 "ⓓ 개수가 바뀌면(4→5) 쪽지 1통 더"
# planner 명부 못 풀면 로그 ERROR(조용한 통과 0)
echo '{}' > "$T/seats-planner.json"; { base_ps; yes_ps 3 1 '??' 07:00 90.0; } > "$PSF"; tick
has "$(cat "$ST/resource-watch.log" 2>/dev/null)" "ERROR CPU 폭주 쪽지 수신자 없음" "ⓓ planner _master 없음 → 로그 ERROR"
eq "$(notes)" 2 "ⓓ 수신자 없음 → 쪽지 0"
# ⓔ 조건 미달 tick → 기록 0
echo '{"_master": "byz-t-planner-claude#9"}' > "$T/seats-planner.json"; n0="$(wc -l < "$CLOG" | tr -d ' ')"
{ base_ps; yes_ps 2 150 ttys003 08:00 90.0; } > "$PSF"; tick
eq "$(wc -l < "$CLOG" | tr -d ' ')" "$n0" "ⓔ 2개 tick → 로그 줄 증가 0"
{ base_ps; yes_ps 4 150 ttys003 04:00 90.0; } > "$PSF"; tick
eq "$(wc -l < "$CLOG" | tr -d ' ')" "$n0" "ⓔ 4분 tick → 로그 줄 증가 0"
eq "$(notes)" 2 "ⓔ 조건 미달 → 쪽지 0"
# 원인 도구 실패 → 로그 ERROR · 동결 판정 영향 0(tick 은 끝까지)
: > "$PSF"; tick
has "$(cat "$ST/resource-watch.log")" "ERROR cpu 원인" "원인 도구 rc≠0 → 로그 ERROR"
# ⓕ 어떤 경우도 kill·renice 0 — 가짜 kill 기록 0 + 코드에 호출 0
[ ! -s "$T/killed.log" ] && ok "ⓕ 가짜 kill·renice·pkill·killall 호출 0" || bad "ⓕ 호출됨: $(cat "$T/killed.log")"
code() { sed -e 's/"[^"]*"//g' -e "s/'[^']*'//g" -e 's/#.*//'; }   # 따옴표 안 글자(쪽지 본문 «kill 0»)·주석은 호출이 아니다
KRE='(^|[^a-z_-])(kill|renice|pkill|killall)([^a-z_-]|$)'
code < "$BIN/ft-resource-cause.sh" | grep -qE "$KRE" && bad "ⓕ ft-resource-cause.sh 에 kill 계열" || ok "ⓕ ft-resource-cause.sh 에 kill 계열 0"
body="$(sed -n '/^cpu_watch()/,/^}/p' "$BIN/ft-resource-watch.sh")"
[ -n "$body" ] && ok "ⓕ watch cpu_watch 본문 있음" || bad "ⓕ watch cpu_watch 없음"
printf '%s\n' "$body" | code | grep -qE "$KRE" && bad "ⓕ cpu_watch 에 kill 계열" || ok "ⓕ cpu_watch 에 kill 계열 0"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
