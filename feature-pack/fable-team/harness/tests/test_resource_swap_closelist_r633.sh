#!/usr/bin/env bash
# test_resource_swap_closelist_r633.sh — r633: swap>12288 ∧ level 2 는 동결·REJECT 하지 않는다. 막기(동결·REJECT)는 level 4 · disk · memfree 문턱만.
# 판정 2531(DA⑥ r3 HOLD → 안 1): 팀장 앞 목록 쪽지 발신은 뺐다 — 감시자는 «WARN … 막지 않음 · 선제 회수가 유휴 좌석 처리» 1줄만(사유가 바뀔 때만) · 쪽지·회수 호출 0.
# FT_RES_SWAP_FREEZE=1 = swap 축만 옛 동작(level 4 단독 동결은 env 무관).
# 가짜 센서(PATH 앞) · 임시 FT_RES_ROOT · 가짜 회수 도구·mbox(불리면 기록 — 불리면 안 됨) 만 쓴다 — 실 동결·실 tmux·실 kill·실 쪽지 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_RECLAIM_PREVENT_SEC=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_RES_SWAP_FREEZE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST" "$T/home"
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"; WLOG="$ST/resource-watch.log"
for f in ft-resource-watch.sh ft-resource-gate.sh; do
  bash -n "$BIN/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"
done
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245" || bad "감시자 줄 수 >245"
# 판정 2531: 발신 lib·잠금·pending·서명·수신자 코드 삭제
[ ! -e "$KIT/ft-resource-swapwarn-lib.sh" ] && [ ! -e "$BIN/ft-resource-swapwarn-lib.sh" ] && ok "발신 lib 파일 없음(키트·추적본)" || bad "발신 lib 파일이 남음"
eq "$(grep -c 'swapwarn\|swap-warn-pending\|swap-warn-send\|swap-warn.json' "$BIN/ft-resource-watch.sh")" 0 "감시자에 발신·pending·잠금·서명 상태 참조 0"

# 가짜 센서 — 값은 FAKE_* env
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 16384.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo "$FAKE_LEVEL";;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 ${FAKE_DISK_KIB:-438304768} 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 120; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' > "$S/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
chmod 755 "$S"/*
printf '#!/bin/bash\necho "$*" >> "%s/rc.calls"\n' "$T" > "$T/reclaim.sh"; chmod 755 "$T/reclaim.sh"   # 불리면 기록 — swap 경고 경로에서 불리면 안 됨
printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/mbox.log"\nexit 0\n' "$T" > "$T/mbox.sh"; chmod 755 "$T/mbox.sh"
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"
seed() { local i n; n="$(date +%s)"; : > "$PTSV"; for i in 2 1; do printf '%s\t%s\t%s\t%s\t2303978\n' "$((n-60*i))" "$1" "$2" "$3" >> "$PTSV"; done; }
fresh() { rm -f "$FREEZE" "$WLOG" "$T/mbox.log" "$T/rc.calls" "$ST/.swap-warn.sig"; : > "$T/mbox.log"; }
tick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" HOME="$T/home" \
  FT_MBOX_SH="$T/mbox.sh" FT_RECLAIM_SH="$T/reclaim.sh" FT_PREVENTIVE_SH="$T/noop.sh" FT_SEATS_JSON="$T/none.json" "$@" \
  bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
gate() { env FT_RES_ROOT="$R" PATH="$S:$PATH" "$@" bash "$BIN/ft-resource-gate.sh" check 2>&1; }
warns() { grep -c 'WARN swap=.* — 막지 않음 · 선제 회수가 유휴 좌석 처리' "$WLOG" 2>/dev/null || true; }
mails() { grep -c '\[자원 경고' "$T/mbox.log" 2>/dev/null || true; }   # 디스크 경보(ft-disk-alarm) 등 다른 쪽지는 세지 않는다
SW="FAKE_SWAP=14288 FAKE_LEVEL=2 FAKE_MEMFREE=31"

# ⓐ (실패 시험 먼저) swap 14288 · level 2 · memfree 31 · disk 418G → 동결 0 · check OK + WARN 1줄 · 감시 로그 WARN 1줄 · 쪽지·회수 호출 0
fresh; seed 14288 31 2; tick $SW
[ ! -f "$FREEZE" ] && ok "ⓐ swap14288·level2·memfree31 → 동결 0" || bad "ⓐ 동결이 생김: $(cat "$FREEZE" 2>/dev/null)"
G="$(gate $SW)"; grc=$?
eq "$grc" 0 "ⓐ check rc=0(REJECT 아님)"
has "$G" "OK disk=418GiB swap=14288MiB" "ⓐ check 첫 줄 OK"
has "$G" "WARN swap=14288MiB level=2 — 막지 않음(유휴 좌석은 선제 회수가 처리)" "ⓐ check 뒤 WARN 1줄(쪽지 주장 0)"
hasnt "$G" "REJECT" "ⓐ check REJECT 0"
has "$(cat "$WLOG" 2>/dev/null)" "WARN swap=14288MiB level=2 — 막지 않음 · 선제 회수가 유휴 좌석 처리" "ⓐ 감시 로그 WARN 1줄"
hasnt "$(cat "$WLOG" 2>/dev/null)" "FREEZE created" "ⓐ 감시 로그 FREEZE created 0"
[ ! -f "$T/rc.calls" ] && ok "ⓐ 회수 도구 호출 0(유휴 좌석은 선제 회수 몫)" || bad "ⓐ swap 경고 경로가 회수 도구를 부름"
eq "$(mails)" 0 "ⓐ 자원 경고 쪽지 0"
[ ! -e "$ST/swap-warn-pending.json" ] && [ ! -e "$ST/swap-warn.json" ] && [ ! -d "$ST/swap-warn-send.lock.d" ] && ok "ⓐ pending·서명 상태·잠금 파일 0" || bad "ⓐ 옛 발신 상태 파일이 생김"

# ⓑ WARN 은 사유(swap 4GiB 구간·level)가 바뀔 때만 1줄 · 경고가 풀렸다가 다시 오면 새 1줄
tick $SW; tick FAKE_SWAP=14500 FAKE_LEVEL=2 FAKE_MEMFREE=31
eq "$(warns)" 1 "ⓑ 같은 사유(같은 4GiB 구간·level 2) 다음 틱 2번 → 추가 0"
seed 16400 31 2; tick FAKE_SWAP=16400 FAKE_LEVEL=2 FAKE_MEMFREE=31
eq "$(warns)" 2 "ⓑ swap 구간이 바뀌면(3→4) 1줄 더"
seed 16400 31 3; tick FAKE_SWAP=16400 FAKE_LEVEL=3 FAKE_MEMFREE=31
eq "$(warns)" 3 "ⓑ level 이 바뀌면(2→3) 1줄 더"
seed 9000 31 2; tick FAKE_SWAP=9000 FAKE_LEVEL=2 FAKE_MEMFREE=31; seed 16400 31 3; tick FAKE_SWAP=16400 FAKE_LEVEL=3 FAKE_MEMFREE=31
eq "$(warns)" 4 "ⓑ 경고가 풀렸다가(swap 9000) 다시 오면 1줄 더"
[ ! -f "$T/rc.calls" ] && eq "$(mails)" 0 "ⓑ 틱 6번 내내 쪽지·회수 호출 0" || bad "ⓑ 회수 도구가 불림"

# ⓓ level 4 → 동결 생성 + check REJECT (swap 크기와 무관) · hard 틱은 WARN 0
fresh; seed 6000 31 4; tick FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=31
[ -f "$FREEZE" ] && ok "ⓓ level 4 → 동결 생성" || bad "ⓓ level 4 인데 동결 0"
has "$(cat "$WLOG" 2>/dev/null)" "trig=level" "ⓓ 로그 trig=level"
has "$(gate FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=31)" "REJECT resource" "ⓓ check REJECT"
fresh; seed 14288 31 4; tick FAKE_SWAP=14288 FAKE_LEVEL=4 FAKE_MEMFREE=31
[ -f "$FREEZE" ] && ok "ⓓ swap14288·level 4 → 동결 생성" || bad "ⓓ swap14288·level4 동결 0"
eq "$(warns)" 0 "ⓓ hard(level 4) 틱 → swap WARN 0"

# ⓔ disk<25 · memfree<10 → 동결 생성 + REJECT (그대로)
fresh; seed 9000 31 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=31 FAKE_DISK_KIB=$((24*1048576))
has "$(cat "$WLOG" 2>/dev/null)" "trig=disk" "ⓔ disk 24G → FREEZE trig=disk"
has "$(gate FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=31 FAKE_DISK_KIB=$((24*1048576)))" "REJECT resource" "ⓔ disk 24G → REJECT"
fresh; seed 9000 9 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=9
has "$(cat "$WLOG" 2>/dev/null)" "trig=memfree" "ⓔ memfree 9 → FREEZE trig=memfree"
has "$(gate FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=9)" "REJECT resource" "ⓔ memfree 9 → REJECT"

# ⓕ 해제 조건 그대로 — 동결 있음 · 3표본 calm → THAW · 트리거 아직 참 → THAW held
fresh; echo "FREEZE 시험" > "$FREEZE"; seed 9000 40 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "ⓕ 해제 조건 3표본 → THAW" || bad "ⓕ 해제 안 됨"
has "$(cat "$WLOG" 2>/dev/null)" "THAW removed" "ⓕ 로그 THAW removed"
fresh; echo "FREEZE 시험" > "$FREEZE"; seed 9000 22 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=22 FT_RES_MEM_MIN=25
[ -f "$FREEZE" ] && ok "ⓕ 트리거 아직 참 → 유지" || bad "ⓕ 트리거 참인데 해제"
has "$(cat "$WLOG" 2>/dev/null)" "THAW held trig=memfree" "ⓕ 로그 THAW held"

# ⓖ FT_RES_SWAP_FREEZE=1 → swap 축만 옛 동작(swap∧level2 동결 · check REJECT · WARN 0) — level 4 단독 동결은 ⓜ
fresh; seed 14288 31 2; tick $SW FT_RES_SWAP_FREEZE=1
[ -f "$FREEZE" ] && ok "ⓖ FT_RES_SWAP_FREEZE=1 → 동결" || bad "ⓖ 옛 동작 동결 0"
has "$(cat "$WLOG" 2>/dev/null)" "trig=swap" "ⓖ 로그 trig=swap"
eq "$(warns)" 0 "ⓖ 옛 동작 → 막지 않음 WARN 0"
rm -f "$FREEZE"; G="$(gate $SW FT_RES_SWAP_FREEZE=1)"
has "$G" "REJECT resource swap=14288MiB level=2 limit=12288MiB@level>=2" "ⓖ check 옛 REJECT 줄"

# ⓘ hard 조건(disk 24G) ∧ swap 경고 → 동결이 먼저 · swap WARN 0 · 쪽지·회수 0
fresh; seed 14288 31 2; tick $SW FAKE_DISK_KIB=$((24*1048576))
[ -f "$FREEZE" ] && ok "ⓘ hard(disk 24G)∧swap 경고 → 동결 생성" || bad "ⓘ hard 조건인데 동결 0"
eq "$(warns)" 0 "ⓘ hard 조건 틱 → swap WARN 0"
[ ! -f "$T/rc.calls" ] && eq "$(mails)" 0 "ⓘ hard 조건 틱 → 쪽지·회수 호출 0" || bad "ⓘ hard 조건인데 회수 도구 호출"

# ⓜ env(FT_RES_SWAP_FREEZE=1) 모드에서도 level 4 · swap 작음 → 동결(swap 축만 옛 동작 — level 4 단독은 env 무관)
fresh; seed 6000 31 4; tick FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=31 FT_RES_SWAP_FREEZE=1
[ -f "$FREEZE" ] && ok "ⓜ env 모드 level 4·swap 6000 → 동결" || bad "ⓜ env 모드 level 4 동결 0"
has "$(cat "$WLOG")" "trig=level" "ⓜ env 모드 trig=level"

# swap 경고 아님(swap 9000 · level 2 / swap 14288 · level 1) → WARN 0 · 동결 0
fresh; seed 9000 31 2; tick FAKE_SWAP=9000 FAKE_LEVEL=2 FAKE_MEMFREE=31; seed 14288 31 1; tick FAKE_SWAP=14288 FAKE_LEVEL=1 FAKE_MEMFREE=31
eq "$(warns)" 0 "swap 경고 아님 → WARN 0"
[ ! -f "$FREEZE" ] && ok "swap 경고 아님 → 동결 0" || bad "swap 경고 아닌데 동결"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
