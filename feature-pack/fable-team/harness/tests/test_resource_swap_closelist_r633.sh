#!/usr/bin/env bash
# test_resource_swap_closelist_r633.sh — r633: swap>12288 ∧ level 2 는 동결·REJECT 하지 않고 «유휴 좌석 닫기 목록» 을 팀장에게 쪽지로.
# 막기(동결·REJECT)는 level 4 · disk · memfree 문턱만. FT_RES_SWAP_FREEZE=1 = 옛 동작.
# 가짜 센서(PATH 앞) · 임시 FT_RES_ROOT · 가짜 회수 도구(FT_RECLAIM_SH) · 가짜 mbox 만 쓴다 — 실 동결·실 tmux·실 kill·실 쪽지 0.
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
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"; WLOG="$ST/resource-watch.log"; WSTATE="$ST/swap-warn.json"
for f in ft-resource-watch.sh ft-resource-gate.sh ft-resource-swapwarn-lib.sh; do
  bash -n "$BIN/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"
  cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"
done
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245" || bad "감시자 줄 수 >245"

# 가짜 센서 — 값은 FAKE_* env
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 16384.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo "$FAKE_LEVEL";;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 ${FAKE_DISK_KIB:-438304768} 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 120; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' > "$S/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
chmod 755 "$S"/*
# 가짜 회수 도구 — 받은 인자 기록 · 출력 = $T/rc.out · rc = $T/rc.rc
RC="$T/reclaim.sh"
cat > "$RC" <<EOF
#!/bin/bash
echo "\$*" >> "$T/rc.calls"
cat "$T/rc.out" 2>/dev/null
exit "\$(cat "$T/rc.rc" 2>/dev/null || echo 0)"
EOF
chmod 755 "$RC"
MB="$T/mbox.sh"
printf '#!/bin/bash\n[ "$1" = send ] || exit 0\nprintf "%%s\\n" "$*" >> "%s/mbox.log"\nexit "$(cat "%s/mb.rc" 2>/dev/null || echo 0)"\n' "$T" "$T" > "$MB"; chmod 755 "$MB"
# 명부 2팀 — v65(seats.json) · harness(seats-harness.json) · 교대된 옛 세대는 사슬 끝 명부의 _master 로
cat > "$R/.fable-team/seats.json" <<'EOF'
{"_master": "byz-v65-master-claude#9", "byz-v65-master-claude#9": {"role": "master"},
 "byz-v65-nano-a#0": {"role": "nano"}, "byz-v65-arch-claude#3": {"role": "arch", "_replaced_by": "byz-v65-arch-claude#4"},
 "byz-v65-arch-claude#4": {"role": "arch"}}
EOF
cat > "$R/.fable-team/seats-harness.json" <<'EOF'
{"_master": "byz-harness-master-claude#90", "byz-harness-master-claude#90": {"role": "master"},
 "byz-harness-nano-b#0": {"role": "nano"}, "byz-harness-nano-d#0": {"role": "nano"}}
EOF
cands() { # cands <이름:종류…> → 회수 도구 dry-run 출력(WOULD-CLOSE 행) + 승인 범위 밖·SKIP 행 1개씩(목록에 들어가면 안 됨)
  { echo "후보 | 종류 | 승인 근거 | 결과"
    for c in "$@"; do echo "${c%%:*} | ${c#*:} | 나노 세션 정리 2026-10-02 | WOULD-CLOSE(nano-close)"; done
    echo "byz-v65-master-claude#8 | 현역 역할/기타 | - | HIL(승인 범위 밖: 현역 역할 좌석)"
    echo "byz-harness-nano-c#0 | 병합 끝 나노 | - | SKIP idle 3분 < 30분"
    echo "RECLAIMED $# pressure=2 swap=88%"
    echo "PREVENTIVE reclaimed=$# candidates=$(( $# + 2 )) skipped=1 pressure=2 swap=88%"; } > "$T/rc.out"; }
seed() { local i n; n="$(date +%s)"; : > "$PTSV"; for i in 2 1; do printf '%s\t%s\t%s\t%s\t2303978\n' "$((n-60*i))" "$1" "$2" "$3" >> "$PTSV"; done; }
fresh() { rm -f "$FREEZE" "$WLOG" "$WSTATE" "$T/mbox.log" "$T/rc.calls" "$T/rc.rc" "$T/mb.rc"; : > "$T/mbox.log"; }
tick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" HOME="$T/home" \
  FT_MBOX_SH="$MB" FT_RECLAIM_SH="$RC" FT_PREVENTIVE_SH="$T/noop.sh" FT_SEATS_JSON="$T/none.json" "$@" \
  bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
gate() { env FT_RES_ROOT="$R" PATH="$S:$PATH" "$@" bash "$BIN/ft-resource-gate.sh" check 2>&1; }
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"; mkdir -p "$T/home"
notes() { grep -c '\[자원 경고\]' "$T/mbox.log" 2>/dev/null || true; }
warnmail() { grep '\[자원 경고\]' "$T/mbox.log" 2>/dev/null; }   # 디스크 경보(ft-disk-alarm) 등 다른 쪽지는 세지 않는다
SW="FAKE_SWAP=14288 FAKE_LEVEL=2 FAKE_MEMFREE=31"

# ⓐ (실패 시험 먼저) swap 14288 · level 2 · memfree 31 · disk 418G → 동결 0 · check OK + WARN 1줄 · 감시 로그 WARN … close-list sent n=<후보 수>
fresh; seed 14288 31 2; cands "byz-v65-nano-a#0:병합 끝 나노" "byz-harness-nano-b#0:병합 끝 나노" "byz-v65-arch-claude#3:직전 세대 좌석"
tick $SW
[ ! -f "$FREEZE" ] && ok "ⓐ swap14288·level2·memfree31 → 동결 0" || bad "ⓐ 동결이 생김: $(cat "$FREEZE" 2>/dev/null)"
G="$(gate $SW)"; grc=$?
eq "$grc" 0 "ⓐ check rc=0(REJECT 아님)"
has "$G" "OK disk=418GiB swap=14288MiB" "ⓐ check 첫 줄 OK"
has "$G" "WARN swap=14288MiB level=2 — 닫기 목록 보냄" "ⓐ check 뒤 WARN 1줄"
hasnt "$G" "REJECT" "ⓐ check REJECT 0"
has "$(cat "$WLOG" 2>/dev/null)" "WARN swap=14288M level=2 close-list sent n=3" "ⓐ 감시 로그 WARN … close-list sent n=3"
hasnt "$(cat "$WLOG" 2>/dev/null)" "FREEZE created" "ⓐ 감시 로그 FREEZE created 0"
has "$(cat "$T/rc.calls" 2>/dev/null)" "--dry-run --preventive" "ⓐ 회수 도구는 --dry-run --preventive 로만(닫기 0)"

# ⓑ 팀별 묶어 각 팀 명부 _master 에 1통 · 승인 범위 밖·SKIP 행은 목록 0 · 교대된 옛 세대는 사슬 끝 팀 master 로
eq "$(notes)" 2 "ⓑ 후보 있는 팀 2개 → 쪽지 2통"
V="$(warnmail | grep 'send byz-v65-master-claude#9 ')"; H="$(warnmail | grep 'send byz-harness-master-claude#90 ')"
has "$V" "[자원 경고] swap 14288MiB level 2 — 닫아도 되는 유휴 좌석: byz-v65-arch-claude#3 byz-v65-nano-a#0 · 팀장이 닫기(nano-close 경로) · 새 spawn 은 막지 않음" "ⓑ v65 팀장 쪽지 원문(옛 세대 포함)"
has "$H" "닫아도 되는 유휴 좌석: byz-harness-nano-b#0 ·" "ⓑ harness 팀장 쪽지 = 자기 팀 좌석만"
hasnt "$(cat "$T/mbox.log")" "byz-v65-master-claude#8" "ⓑ 승인 범위 밖(HIL) 행은 목록 0"
hasnt "$(cat "$T/mbox.log")" "byz-harness-nano-c#0" "ⓑ SKIP 행은 목록 0"
fresh; seed 14288 31 2; cands "byz-harness-nano-b#0:병합 끝 나노"; tick $SW
eq "$(notes)" 1 "ⓑ 후보 0 팀(v65)엔 안 보냄 — 1통"
eq "$(warnmail | grep -c 'send byz-v65-master')" 0 "ⓑ v65 팀장 쪽지 0"

# ⓒ 같은 서명(swap 구간·후보 목록)이면 30분 안에 다시 안 보냄 · 후보가 바뀌면 보냄 · 30분 지나면 다시
tick $SW; tick FAKE_SWAP=14500 FAKE_LEVEL=2 FAKE_MEMFREE=31
eq "$(notes)" 1 "ⓒ 같은 서명(같은 4 GiB 구간·같은 목록) 다음 틱 2번 → 추가 0"
cands "byz-harness-nano-b#0:병합 끝 나노" "byz-harness-nano-d#0:병합 끝 나노"; tick $SW
eq "$(notes)" 2 "ⓒ 후보 목록이 바뀌면 1통 더"
tick $SW FT_RES_SWAPWARN_REPEAT_SEC=0
eq "$(notes)" 3 "ⓒ 같은 서명도 반복 간격(시험 0초)이 지나면 다시"
fresh; seed 14288 31 2; cands "byz-harness-nano-b#0:병합 끝 나노"; tick $SW
seed 16400 31 2; tick FAKE_SWAP=16400 FAKE_LEVEL=2 FAKE_MEMFREE=31
eq "$(notes)" 2 "ⓒ swap 구간이 바뀌면(4 GiB 구간 3→4) 1통 더"

# ⓓ level 4 → 동결 생성 + check REJECT (swap 크기와 무관)
fresh; seed 6000 31 4; cands; tick FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=31
[ -f "$FREEZE" ] && ok "ⓓ level 4 → 동결 생성" || bad "ⓓ level 4 인데 동결 0"
has "$(cat "$WLOG" 2>/dev/null)" "trig=level" "ⓓ 로그 trig=level"
has "$(gate FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=31)" "REJECT resource" "ⓓ check REJECT"
fresh; seed 14288 31 4; cands; tick FAKE_SWAP=14288 FAKE_LEVEL=4 FAKE_MEMFREE=31
[ -f "$FREEZE" ] && ok "ⓓ swap14288·level 4 → 동결 생성" || bad "ⓓ swap14288·level4 동결 0"

# ⓔ disk<25 · memfree<10 → 동결 생성 + REJECT (그대로)
fresh; seed 9000 31 1; cands; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=31 FAKE_DISK_KIB=$((24*1048576))
has "$(cat "$WLOG" 2>/dev/null)" "trig=disk" "ⓔ disk 24G → FREEZE trig=disk"
has "$(gate FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=31 FAKE_DISK_KIB=$((24*1048576)))" "REJECT resource" "ⓔ disk 24G → REJECT"
fresh; seed 9000 9 1; cands; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=9
has "$(cat "$WLOG" 2>/dev/null)" "trig=memfree" "ⓔ memfree 9 → FREEZE trig=memfree"
has "$(gate FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=9)" "REJECT resource" "ⓔ memfree 9 → REJECT"

# ⓕ 해제 조건 그대로 — 동결 있음 · 3표본 calm → THAW · 트리거 아직 참 → THAW held
fresh; echo "FREEZE 시험" > "$FREEZE"; seed 9000 40 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "ⓕ 해제 조건 3표본 → THAW" || bad "ⓕ 해제 안 됨"
has "$(cat "$WLOG" 2>/dev/null)" "THAW removed" "ⓕ 로그 THAW removed"
fresh; echo "FREEZE 시험" > "$FREEZE"; seed 9000 22 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=22 FT_RES_MEM_MIN=25
[ -f "$FREEZE" ] && ok "ⓕ 트리거 아직 참 → 유지" || bad "ⓕ 트리거 참인데 해제"
has "$(cat "$WLOG" 2>/dev/null)" "THAW held trig=memfree" "ⓕ 로그 THAW held"

# ⓖ FT_RES_SWAP_FREEZE=1 → 옛 동작(swap∧level2 동결 · check REJECT · 목록 쪽지 0)
fresh; seed 14288 31 2; cands "byz-harness-nano-b#0:병합 끝 나노"; tick $SW FT_RES_SWAP_FREEZE=1
[ -f "$FREEZE" ] && ok "ⓖ FT_RES_SWAP_FREEZE=1 → 동결" || bad "ⓖ 옛 동작 동결 0"
has "$(cat "$WLOG" 2>/dev/null)" "trig=swap" "ⓖ 로그 trig=swap"
eq "$(notes)" 0 "ⓖ 옛 동작 → 목록 쪽지 0"
rm -f "$FREEZE"; G="$(gate $SW FT_RES_SWAP_FREEZE=1)"
has "$G" "REJECT resource swap=14288MiB level=2 limit=12288MiB@level>=2" "ⓖ check 옛 REJECT 줄"

# ⓗ 회수 도구 실패·쪽지 실패 = 감시 로그 ERROR 1줄 · 동결 0(막기로 폴백 0)
fresh; seed 14288 31 2; cands "byz-harness-nano-b#0:병합 끝 나노"; echo 4 > "$T/rc.rc"; tick $SW
[ ! -f "$FREEZE" ] && ok "ⓗ 회수 도구 rc4 → 동결 0" || bad "ⓗ 회수 실패가 동결로 폴백"
eq "$(grep -c 'ERROR swap 닫기 목록 회수 도구 rc=4' "$WLOG" 2>/dev/null || true)" 1 "ⓗ 회수 도구 실패 → 로그 ERROR 1줄"
eq "$(notes)" 0 "ⓗ 회수 도구 실패 → 쪽지 0"
fresh; seed 14288 31 2; cands "byz-harness-nano-b#0:병합 끝 나노"; echo 3 > "$T/mb.rc"; tick $SW
[ ! -f "$FREEZE" ] && ok "ⓗ 쪽지 실패 → 동결 0" || bad "ⓗ 쪽지 실패가 동결로 폴백"
eq "$(grep -c 'ERROR swap 닫기 목록 쪽지 발신 실패 to=byz-harness-master-claude#90' "$WLOG" 2>/dev/null || true)" 1 "ⓗ 쪽지 실패 → 로그 ERROR 1줄"
rm -f "$T/mb.rc"; tick $SW
eq "$(warnmail | grep -c 'send byz-harness-master-claude#90 ')" 2 "ⓗ 쪽지 실패는 서명 기록 0 → 다음 틱 재시도"
fresh; seed 14288 31 2; cands "byz-zz-orphan#0:직전 세대 좌석"; tick $SW
has "$(cat "$WLOG" 2>/dev/null)" "ERROR swap 닫기 목록 수신자 없음 byz-zz-orphan#0" "ⓗ 명부에 없는 좌석 → 로그 ERROR(조용한 통과 0)"
# swap 경고 아님(swap 9000 · level 2 / swap 14288 · level 1) → 회수 도구 호출 0 · 쪽지 0
fresh; seed 9000 31 2; tick FAKE_SWAP=9000 FAKE_LEVEL=2 FAKE_MEMFREE=31; seed 14288 31 1; tick FAKE_SWAP=14288 FAKE_LEVEL=1 FAKE_MEMFREE=31
[ ! -f "$T/rc.calls" ] && ok "swap 경고 아님 → 회수 도구 호출 0" || bad "swap 경고 아닌데 회수 도구 호출"
eq "$(notes)" 0 "swap 경고 아님 → 쪽지 0"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
