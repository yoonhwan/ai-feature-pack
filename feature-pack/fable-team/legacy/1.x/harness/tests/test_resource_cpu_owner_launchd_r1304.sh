#!/usr/bin/env bash
# test_resource_cpu_owner_launchd_r1304.sh — r1304 CPU 폭주 «주인» 칸이 launchd 잡 이름까지 싣는다(ft-resource-cause.sh cpu · launchctl list PID 일치만) + 감시자 서명(주인 제외).
# 가짜 ps(FT_RES_PS · r1340 칸 = pid ppid tty etime time pcpu comm · 폭주 견본 time=etime → 살아온 평균 100%)·가짜 tmux(FT_RES_TMUX)·가짜 launchd 표(FT_RES_LAUNCHD)·임시 루트·가짜 mbox 만 쓴다 — 실 launchctl·실 프로세스·실 tmux·실 쪽지·종료 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_RECLAIM_PREVENT_SEC=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_DIR
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
for f in ft-resource-cause.sh ft-resource-watch.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
CALLS="$T/launchctl.calls"; : > "$CALLS"
# 가짜 launchctl — 호출을 기록 · 기본 rc0(표는 stdout 없음) · RC 주입 · SLEEP 주입
printf '#!/bin/sh\necho "launchctl $*" >> "%s"\n[ -n "${LC_SLEEP:-}" ] && sleep "$LC_SLEEP"\nexit "${LC_RC:-0}"\n' "$CALLS" > "$S/launchctl"
chmod 755 "$S/launchctl"
printf 'byz-v65-master-claude#0 100 /dev/ttys003\nbyz-t-other-claude#1 400 /dev/ttys009\n' > "$T/tmux.txt"
PSF="$T/ps.txt"; LC="$T/launchd.txt"
base_ps() { printf '%s\n' '100 1 ttys003 1-00:00:00 0:00.00 0.0 -zsh' '150 100 ttys003 10:00 0:03.00 0.5 /bin/zsh' '300 1 ?? 02:00:00 114:00.00 95.0 /usr/sbin/mds'; }
py_ps() { # py_ps <개수> <ppid> <tty> <etime> <pcpu>
  local i; for i in $(seq 1 "$1"); do printf '%s %s %s %s %s %s /usr/bin/Python\n' "$((40+i))" "$2" "$3" "$4" "$4" "$5"; done; }
yes_ps() { local i; for i in $(seq 1 "$1"); do printf '%s %s %s %s %s %s /usr/bin/yes\n' "$((200+i))" "$2" "$3" "$4" "$4" "$5"; done; }
c() { env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$S:$PATH" \
  bash "$BIN/ft-resource-cause.sh" cpu 2>"$T/err.txt"; }
nerr() { wc -l < "$T/err.txt" | tr -d ' '; }

# R1 가짜 ps: Python×4(각 40% · 30분 · ppid 22042) · 22042 = bash(ppid 1 · tty ??) · 표 탭 구분 → launchd 잡
{ base_ps; py_ps 4 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
printf '22042\t0\tcom.byz.ft-secret-scan\n' > "$LC"; export FT_RES_LAUNCHD="$LC"
out="$(c)"; rc=$?
eq "$rc" 0 "R1 rc0"
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 launchd com.byz.ft-secret-scan" "R1 조상 PID 가 표에 있으면 «launchd <Label>»"
hasnt "$out" $'\n' "R1 개행 0"
# R1b 같은 표를 공백 구분으로
printf '22042 0 com.byz.ft-secret-scan\n' > "$LC"
eq "$(c)" "cpu Python×4 CPU 160% 30분 · 주인 launchd com.byz.ft-secret-scan" "R1b 공백 구분 표 → 같은 결과"
# R2 조상 사슬에 pane 도 있고 표의 PID 도 있음 → pane 우선(표 PID = 그 pane 의 pid)
printf 'byz-v65-master-claude#0 150 /dev/ttys003\n' > "$T/tmux-r2.txt"
{ base_ps; py_ps 4 150 ttys003 30:00 40.0; printf '%s\n' '150 100 ttys003 35:00 0:06.30 0.3 /bin/bash' '100 1 ttys003 1-00:00:00 0:00.00 0.0 -zsh'; } > "$PSF"
printf '150\t0\tcom.byz.ft-other\n' > "$LC"
out="$(env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux-r2.txt" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" cpu 2>/dev/null)"
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 byz-v65-master-claude#0" "R2 pane 우선(좌석 문구 그대로)"; hasnt "$out" "launchd" "R2 «launchd» 글자 0"
# R3 표에 없음 + tty 일치 → «<세션> (tty)» (기존 ⓑ 와 바이트 같음)
{ base_ps; yes_ps 4 1 ttys003 08:00 90.0; } > "$PSF"; : > "$LC"
eq "$(c)" "cpu yes×4 CPU 360% 8분 · 주인 byz-v65-master-claude#0 (tty)" "R3 표에 없음 → tty 대조"
# R4 표에 없음 · tty ?? → 미상 (기존 ⓒ 와 바이트 같음)
{ base_ps; yes_ps 4 1 '??' 08:00 90.0; } > "$PSF"; : > "$LC"
eq "$(c)" "cpu yes×4 CPU 360% 8분 · 주인 미상" "R4 표에 없음 · tty ?? → 미상"
# R5 launchctl rc1 → WARN 1줄(stderr + 감시자 로그) · stdout 미상 · rc0 · 경보는 나간다
{ base_ps; py_ps 4 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
unset FT_RES_LAUNCHD; : > "$CALLS"; rm -f "$ST/resource-watch.log"
out="$(LC_RC=1 c)"; rc=$?
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R5 실패 → stdout 은 지금 길(미상) · 경보는 나간다"
eq "$(nerr)" 1 "R5 stderr WARN 1줄"
has "$(cat "$T/err.txt")" "WARN launchd 잡 표 못 읽음(rc=1) — launchd 판정 없이 계속" "R5 WARN 문구"
has "$(cat "$ST/resource-watch.log" 2>/dev/null)" "WARN launchd 잡 표 못 읽음(rc=1) — launchd 판정 없이 계속" "R5 감시자 로그에도 같은 줄 1"
eq "$(wc -l < "$ST/resource-watch.log" | tr -d ' ')" 1 "R5 로그 1줄"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 1 "R5 launchctl 1회"
# R5b PATH 에 launchctl 없음 → 같은 WARN(rc=127)
MP="$T/minpath"; mkdir -p "$MP"; for t in awk cat sort cut date timeout sleep env bash; do ln -sf "$(command -v "$t")" "$MP/$t" 2>/dev/null; done
out="$(env -u FT_RES_LAUNCHD FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$MP" bash "$BIN/ft-resource-cause.sh" cpu 2>"$T/err.txt")"
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R5b launchctl 없음 → 미상"
has "$(cat "$T/err.txt")" "(rc=127)" "R5b WARN rc=127"
# R5c 빈 표 파일 = 잡 0행 → WARN 0 · 미상
: > "$T/launchd-empty.txt"; export FT_RES_LAUNCHD="$T/launchd-empty.txt"; : > "$CALLS"
eq "$(c)" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R5c 빈 표 → 미상"
eq "$(nerr)" 0 "R5c 빈 표 → WARN 0(잡 0 = 실패 아님)"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "R5c 표 주입 → launchctl 호출 0"
# R6 폭주 묶음 0 → launchctl 호출 기록 0줄 · 빈 출력
{ base_ps; yes_ps 2 150 ttys003 08:00 90.0; } > "$PSF"; unset FT_RES_LAUNCHD; : > "$CALLS"
out="$(c)"; rc=$?
eq "$rc|$out" "0|" "R6 묶음 0 → 빈 출력 rc0"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "R6 묶음 0 → launchctl 호출 0"
# R7 FT_RES_LAUNCHD_OWNER=0 → 미상 · 호출 0
{ base_ps; py_ps 4 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
out="$(FT_RES_LAUNCHD_OWNER=0 c)"
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R7 끄기 → 미상"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "R7 끄기 → launchctl 호출 0"
# R8 표에 PID «-»(주기 잡) + comm 이 라벨 꼬리와 같은 폭주(ppid 1) → 매칭 0 → 미상(라벨 글자 매칭 0)
{ base_ps; for i in 1 2 3; do printf '%s 1 ?? 30:00 30:00 40.0 /usr/local/bin/ft-magazine\n' "$((500+i))"; done; } > "$PSF"
printf -- '-\t0\tcom.byz.ft-magazine\n' > "$LC"; export FT_RES_LAUNCHD="$LC"
eq "$(c)" "cpu ft-magazine×3 CPU 120% 30분 · 주인 미상" "R8 PID «-» 줄 · 라벨 글자 매칭 0"
# R11 전체 예산 — 느린 launchctl(sleep 4) → cap 2 · 전체 < 7초 · WARN rc=124
{ base_ps; py_ps 4 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
unset FT_RES_LAUNCHD; : > "$CALLS"; t1=$SECONDS
out="$(LC_SLEEP=4 c)"; dt=$((SECONDS-t1))
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R11 느린 launchctl → 미상"
has "$(cat "$T/err.txt")" "(rc=124)" "R11 WARN rc=124(timeout)"
[ "$dt" -lt 7 ] && ok "R11 전체 ${dt}초 < 7초" || bad "R11 전체 ${dt}초 — 7초 넘음"
# R11b 남은 예산 — 느린 ps(2.5초) + 느린 launchctl → 표 읽기 호출 0 · WARN «예산 부족» · 전체 < 3.5초
printf '#!/bin/sh\nsleep 2.5\ncat "%s"\n' "$PSF" > "$S/ps"; chmod 755 "$S/ps"
: > "$CALLS"; t1=$SECONDS
out="$(env -u FT_RES_LAUNCHD -u FT_RES_PS FT_RES_ROOT="$R" FT_RES_TMUX="$T/tmux.txt" FT_RES_CPU_BUDGET_SEC=3 PATH="$S:$PATH" LC_SLEEP=4 LC_RC=0 bash "$BIN/ft-resource-cause.sh" cpu 2>"$T/err.txt")"; dt=$((SECONDS-t1))
eq "$out" "cpu Python×4 CPU 160% 30분 · 주인 미상" "R11b 예산 부족 → 미상 · 경보 줄은 나감"
has "$(cat "$T/err.txt")" "표 건너뜀(예산 부족" "R11b WARN «예산 부족»"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "R11b 표 읽기 호출 0"
[ "$dt" -lt 4 ] && ok "R11b 전체 ${dt}초 < 3.5초(여유 포함)" || bad "R11b 전체 ${dt}초 — 너무 김"
rm -f "$S/ps"

# ---- R9 감시자 tick(쪽지·로그·서명) · R9b 서명 = 명령·개수(주인 제외·다른 묶음 보존)
for t in vm_stat df osascript sysctl memory_pressure; do printf '#!/bin/sh\nexit 0\n' > "$S/$t"; done
printf '#!/bin/sh\necho "System-wide memory free percentage: 60%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "total = 14336.00M  used = 1000.00M  free = 1000.00M  (encrypted)"\n' > "$S/sysctl"
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$S"/* "$T/noop.sh"
MB="$T/mbox.sh"; printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$MB"; chmod 755 "$MB"
echo '{"_master": "byz-t-planner-claude#9"}' > "$T/seats-planner.json"; : > "$T/mbox.log"
CLOG="$ST/runaway-cpu.log"; notes() { grep -c '\[CPU 폭주\]' "$T/mbox.log" || true; }
tick() { env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" \
  FT_MBOX_SH="$MB" FT_SEATS_JSON="$T/seats-planner.json" FT_PREVENTIVE_SH="$T/noop.sh" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
{ base_ps; py_ps 4 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
printf '22042\t0\tcom.byz.ft-secret-scan\n' > "$LC"; export FT_RES_LAUNCHD="$LC"; : > "$CLOG"
tick
eq "$(wc -l < "$CLOG" 2>/dev/null | tr -d ' ')" 1 "R9 tick ① → runaway-cpu.log 1줄"
has "$(cat "$CLOG" 2>/dev/null)" "주인 launchd com.byz.ft-secret-scan" "R9 ① 로그 줄 = launchd 주인"
eq "$(notes)" 1 "R9 ① planner 쪽지 1통"
has "$(cat "$T/mbox.log")" "주인 launchd com.byz.ft-secret-scan" "R9 ① 쪽지 본문에 launchd 주인"
unset FT_RES_LAUNCHD; : > "$CALLS"
out="$(LC_RC=1 tick)"; true   # tick ② = launchctl 실패 → 주인 미상 · 서명 그대로 → 쪽지 0
has "$(cat "$CLOG")" "주인 미상" "R9 ② 실패 tick 로그 줄 = 미상"
has "$(cat "$ST/resource-watch.log" 2>/dev/null)" "WARN launchd 잡 표 못 읽음(rc=1)" "R9 ② 감시자 로그에 WARN"
eq "$(notes)" 1 "R9 ② 서명(명령·개수) 그대로 → 쪽지 0"
tick   # tick ③ 표 복구 → 쪽지 0
eq "$(notes)" 1 "R9 ③ 표 복구 → 쪽지 0"
{ base_ps; py_ps 5 22042 '??' 30:00 40.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; } > "$PSF"
tick
eq "$(notes)" 2 "R9 ④ 개수 4→5 → 쪽지 1통"
eq "$(awk -F'\t' '{print $2}' "$CLOG" | sed 's/.*주인 //')" "$(printf 'launchd com.byz.ft-secret-scan\n미상\n미상\n미상')" "R9 로그 줄마다 주인 값 그대로(launchd/미상/미상/미상)"
[ ! -s "$T/killed.log" ] && ok "R9 종료 계열 호출 0" || bad "R9 종료 계열 호출됨: $(cat "$T/killed.log")"
# R9b 서명: 묶음 2(«Python×4(360%) · 주인 launchd X; yes×3(120%) · 주인 S») · **둘째** 묶음 개수 3→5 → 쪽지 1통(서명에 둘째 묶음이 남아 있다)
{ base_ps; py_ps 4 22042 '??' 30:00 90.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; yes_ps 3 150 ttys003 08:00 40.0; } > "$PSF"
printf '22042\t0\tcom.byz.ft-secret-scan\n' > "$LC"; export FT_RES_LAUNCHD="$LC"; : > "$T/mbox.log"; : > "$CLOG"
tick
echLINE="$(cat "$CLOG")"; has "$echLINE" "cpu Python×4 CPU 360% 30분 · 주인 launchd com.byz.ft-secret-scan; cpu yes×3" "R9b 정렬 · 첫 묶음 Python"
eq "$(notes)" 1 "R9b 묶음 2 첫 tick → 쪽지 1통"
{ base_ps; py_ps 4 22042 '??' 30:00 90.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; yes_ps 5 150 ttys003 08:00 40.0; } > "$PSF"
tick
echLINE="$(cat "$CLOG")"; has "$echLINE" "cpu Python×4 CPU 360% 30분 · 주인 launchd com.byz.ft-secret-scan; cpu yes×5" "R9b 첫 묶음 보존(둘째만 바뀜)"
eq "$(notes)" 2 "R9b 둘째 묶음 개수 3→5 → 쪽지 1통 더(둘째 묶음이 서명에 남아 있다)"
{ base_ps; py_ps 4 22042 '??' 30:00 90.0; printf '%s\n' '22042 1 ?? 35:00 0:06.30 0.3 /bin/bash'; yes_ps 7 150 ttys003 08:00 40.0; } > "$PSF"
tick
eq "$(notes)" 3 "R9b 둘째 개수 5→7 → 다시 쪽지 1통(누적 3)"

# R10 기존 시험(test_resource_cpu_owner.sh) 그대로 PASS + 실 launchctl 호출 0
RC="$T/reclog"; mkdir -p "$RC"; printf '#!/bin/sh\necho "launchctl $*" >> "%s/real.log"\n' "$T" > "$RC/launchctl"; chmod 755 "$RC/launchctl"
unset FT_RES_LAUNCHD
PATH="$RC:$PATH" timeout 70 bash "$HERE/test_resource_cpu_owner.sh" > "$T/old.out" 2>&1; rc=$?
eq "$rc" 0 "R10 기존 시험 rc0"
grep -q '^FAIL' "$T/old.out" && bad "R10 기존 시험 FAIL 있음: $(grep -m2 '^FAIL' "$T/old.out")" || ok "R10 기존 시험 FAIL 0"
[ ! -s "$T/real.log" ] && ok "R10 기존 시험 실 launchctl 호출 0" || bad "R10 실 launchctl 호출됨: $(cat "$T/real.log")"

echo "---- fail=$fail · ${T0}~$SECONDS 초"
[ "$fail" -eq 0 ]
