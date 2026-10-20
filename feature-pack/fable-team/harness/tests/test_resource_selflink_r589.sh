#!/usr/bin/env bash
# test_resource_selflink_r589.sh — r589: 루트 clients/web/node_modules 안 «자기 자신을 가리키는 링크»(루트 FE 500 원인) 감시.
# 가짜 센서·임시 루트·가짜 mbox 만 쓴다 — 실 루트·실 launchd·실 쪽지·삭제 0.
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
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
bash -n "$BIN/ft-resource-watch.sh" && ok "bash -n watch" || bad "bash -n watch"
cmp -s "$BIN/ft-resource-watch.sh" "$KIT/ft-resource-watch.sh" && ok "키트 사본 cmp 0 watch" || bad "키트 사본 어긋남 watch"

# 가짜 센서(동결 판정이 안 걸리는 값) · 가짜 mbox · noop 선제회수
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 6000.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo 1;;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 60%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\nexit 0\n' > "$S/pgrep"; printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
chmod 755 "$S"/*
printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"; chmod 755 "$T/noop.sh"
MB="$T/mbox.sh"; printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/mbox.log"\necho QUEUED\n' "$T" > "$MB"; chmod 755 "$MB"
echo '{"_master": "byz-t-planner-claude#9"}' > "$T/seats-planner.json"; : > "$T/mbox.log"
WLOG="$ST/resource-watch.log"
notes() { grep -c '\[장비 정리\]' "$T/mbox.log" 2>/dev/null || true; }
warns() { grep -c 'WARN node_modules 자기 링크' "$WLOG" 2>/dev/null || true; }
tick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" \
  FT_MBOX_SH="$MB" FT_SEATS_JSON="$T/seats-planner.json" FT_PREVENTIVE_SH="$T/noop.sh" \
  bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
W="$R/clients/web/node_modules"; LN="$W/node_modules"; mkdir -p "$W"

# ⓐ (실패 시험) 안에 자기 자신을 가리키는 링크 → 로그 WARN 1줄 + planner _master 쪽지 1통(«지우기: unlink <경로>»)
ln -s "$W" "$LN"; tick
eq "$(warns)" 1 "ⓐ 자기 링크 → 로그 WARN 1줄"
has "$(cat "$WLOG" 2>/dev/null)" "WARN node_modules 자기 링크 $LN → $W" "ⓐ 로그 줄 = 경로 → 대상"
eq "$(notes)" 1 "ⓐ planner 쪽지 1통"
has "$(cat "$T/mbox.log")" "send byz-t-planner-claude#9 " "ⓐ 수신자 = planner 명부 _master"
has "$(cat "$T/mbox.log")" "[장비 정리]" "ⓐ 쪽지 제목 «[장비 정리]»"
has "$(cat "$T/mbox.log")" "루트 FE 500 원인" "ⓐ 쪽지에 원인 한 줄"
has "$(cat "$T/mbox.log")" "지우기: unlink $LN" "ⓐ 쪽지에 «지우기: unlink <경로>»"
[ -L "$LN" ] && ok "ⓐ 링크는 그대로(삭제 0)" || bad "ⓐ 감시자가 링크를 지움"

# ⓑ 같은 서명이 다음 틱에도 있으면 쪽지 0 · 로그 WARN 도 중복 0
tick; eq "$(notes)" 1 "ⓑ 같은 서명 다음 틱 → 쪽지 0(누적 1)"
eq "$(warns)" 1 "ⓑ 같은 서명 다음 틱 → 로그 WARN 중복 0"
rm -f "$LN"; ln -s "$R" "$LN"; tick
eq "$(notes)" 2 "ⓑ 대상이 바뀌면(서명 변경) 쪽지 1통 더"
eq "$(warns)" 2 "ⓑ 서명이 바뀌면 로그 WARN 1줄 더"

# ⓒ 링크가 아니라 «일반 폴더» → 로그·쪽지 0 (서명은 지워져 다음 발생은 새 사건)
rm -f "$LN"; mkdir "$LN"; tick
eq "$(notes)" 2 "ⓒ 일반 폴더 node_modules → 쪽지 0"
eq "$(warns)" 2 "ⓒ 일반 폴더 node_modules → 로그 WARN 0"

# ⓓ 폴더 없음 → 0
rm -rf "$LN"; tick; rm -rf "$R/clients"; tick
eq "$(notes)" 2 "ⓓ 폴더 없음 → 쪽지 0"
eq "$(warns)" 2 "ⓓ 폴더 없음 → 로그 WARN 0"

# ⓔ planner 명부를 못 풀면 조용한 통과 0 — 로그 ERROR
rm -rf "$R/clients"; mkdir -p "$W"; ln -s "$W" "$LN"; echo '{}' > "$T/seats-planner.json"; tick
has "$(cat "$WLOG" 2>/dev/null)" "ERROR 자기 링크 쪽지 수신자 없음" "ⓔ planner _master 없음 → 로그 ERROR"
eq "$(notes)" 2 "ⓔ 명부 없음 → 쪽지 0(발신 안 함)"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
