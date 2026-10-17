#!/usr/bin/env bash
# test_resource_watch.sh — R320 ft-resource-watch.sh: 동결 자동 해제 교정 · (R323) du 스캔 상한 · 원인 좌석 표시.
# 가짜 센서(PATH 앞)·임시 FT_RES_ROOT 만 쓴다 — 실 동결 파일·실 launchd·실 tmux 0. 값은 FAKE_* env 로 준다.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/scripts/fable-team-bin"; KIT="$REPO/scripts/harness-install/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST"
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"; WLOG="$ST/resource-watch.log"
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo "$FAKE_LEVEL";;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 ${FAKE_DISK_KIB:-104857600} 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 135; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' > "$S/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
chmod 755 "$S"/*
NOW="$(date +%s)"
seed() { # 표본줄 N개(이전 시각순) — 인자: swap memfree level 개수
  local i; : > "$PTSV"; for i in $(seq "$4" -1 1); do printf '%s\t%s\t%s\t%s\t2303978\n' "$((NOW-60*i))" "$1" "$2" "$3" >> "$PTSV"; done; }
tick() { # tick <env…> — 임시 루트에서 감시자 tick 1회
  env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
bash -n "$BIN/ft-resource-watch.sh" && ok "bash -n watch" || bad "bash -n watch"
cmp -s "$BIN/ft-resource-watch.sh" "$KIT/ft-resource-watch.sh" && ok "키트 사본 cmp 0 watch" || bad "키트 사본 어긋남 watch"

# ── 2. 동결 자동 해제: disk≥35 · memfree≥20 · level=1 · swap 비증가 가 «최근 3표본 연속» (swap 절대량은 해제 조건 아님) ──
frz() { echo "FREEZE 시험" > "$FREEZE"; }
frz; seed 9000 40 1 2   # 2줄 + tick 이 1줄 추가 = 3표본
tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "R320 level1·memfree40·swap 9000(비증가) 3표본 → 해제" || bad "R320 3표본 해제 안 됨"
has "$(cat "$WLOG")" "THAW removed" "R320 해제 로그 1줄"
frz; seed 11500 40 1 2; tick FAKE_SWAP=11500 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "R320 swap 11500(옛 조건 <4096 밖)도 해제 — 절대량은 조건 아님" || bad "R320 swap 절대량이 해제를 막음"
frz; seed 9000 40 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=2 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320 level=2 → 유지" || bad "R320 level=2 인데 해제됨"
frz; seed 9000 40 1 1; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320 표본 2개뿐 → 유지" || bad "R320 표본 2개뿐인데 해제됨"
frz; seed 9000 19 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320 과거 표본 memfree 19 → 유지" || bad "R320 과거 표본 memfree 19 인데 해제됨"
frz; seed 8000 40 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320 swap 증가(8000→9000) → 유지" || bad "R320 swap 증가인데 해제됨"
frz; seed 9000 40 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40 FAKE_DISK_KIB=$((34*1048576))
[ -f "$FREEZE" ] && ok "R320 disk 34G(<35) → 유지" || bad "R320 disk 34G 인데 해제됨"
rm -f "$FREEZE"; seed 13000 40 1 2; tick FAKE_SWAP=13000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320 동결 트리거 swap>12288 그대로" || bad "R320 swap 13000 동결 안 걸림"

# ── R320c. 해제의 swap 축 = 문지기(ft-resource-gate.sh)와 «같은 rate 정의» — 마지막 6표본 (s1−s0)×60/(t1−t0) ≤ 허용치(512) ──
seedseq() { # seedseq <swap…> — 인자 개수만큼 표본(1분 간격 · 마지막이 NOW-60) · memfree 40 · level 1
  local n=$# i=$#; : > "$PTSV"; for s in "$@"; do printf '%s\t%s\t40\t1\t2303978\n' "$((NOW-60*i))" "$s" >> "$PTSV"; i=$((i-1)); done; }
gate_rate() { env FT_RES_ROOT="$R" PATH="$S:$PATH" "$@" bash "$BIN/ft-resource-gate.sh" status 2>&1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^rate=/){sub(/^rate=/,"",$i); print $i}}'; }
# ⓐ 마지막 3표본은 평평(11000)인데 6표본 rate ≈600 > 512 → 문지기는 막는다 → 감시는 풀면 안 된다(옛 calm3 은 풀었다)
frz; seedseq 8000 9000 10000 11000 11000; tick FAKE_SWAP=11000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ -f "$FREEZE" ] && ok "R320c ⓐ swap 8000→11000 뒤 평평 3표본(rate≈600>512) → 유지" || bad "R320c ⓐ rate>512 인데 해제됨"
has "$(tail -1 "$WLOG" 2>/dev/null)" "THAW held rate=" "R320c ⓐ 막은 이유를 로그 1줄(THAW held rate=…)"
# ⓑ 평평 6표본(rate 0) · memfree≥20 · level 1 → 해제
frz; seedseq 9000 9000 9000 9000 9000; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "R320c ⓑ 평평 6표본(rate 0) → 해제" || bad "R320c ⓑ rate 0 인데 유지됨"
has "$(tail -1 "$WLOG")" "rate=0" "R320c ⓑ 해제 로그에 rate=0"
# ⓒ 감시와 문지기가 «같은 표본»에서 같은 rate 를 낸다 — 해제 로그의 rate 값 == 같은 표본에 대한 gate status 의 rate
frz; seedseq 8000 8500 9000 9000 9000; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40
[ ! -f "$FREEZE" ] && ok "R320c ⓒ rate≈200(≤512) 완만한 상승 뒤 평평 → 해제(문지기도 통과시키는 표본)" || bad "R320c ⓒ rate≈200 인데 유지됨"
GR="$(gate_rate FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40)"; WR="$(tail -1 "$WLOG" | sed -n 's/.*rate=\(-\{0,1\}[0-9][0-9]*\).*/\1/p')"
[ -n "$GR" ] && [ "$GR" = "$WR" ] && ok "R320c ⓒ 감시 해제 로그 rate=$WR == 문지기 status rate=$GR" || bad "R320c ⓒ rate 불일치 감시=«${WR}» 문지기=«${GR}»"
# 다른 조건(disk)이 안 맞으면 rate 가 좋아도 유지
frz; seedseq 9000 9000 9000 9000 9000; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40 FAKE_DISK_KIB=$((34*1048576))
[ -f "$FREEZE" ] && ok "R320c 기존 조건(disk 34G<35)은 그대로 유지" || bad "R320c disk 조건 회귀"

# ── R323. 디스크 스냅샷의 du: 상한 7초(시험은 FT_RES_DU_CAP_SEC 로 단축) · nice 19 · 잠금 1개 · 워크트리 합계는 결과 캐시 ──
grep -q 'FT_RES_DU_CAP_SEC:-7' "$BIN/ft-resource-watch.sh" && ok "R323 du 상한 기본 7초" || bad "R323 du 상한 기본값이 7초가 아님"
D2="$T/du2"; mkdir -p "$D2" "$T/wt"; DULOG="$T/du.log"
cat > "$D2/du" <<EOF
#!/bin/bash
p="\${@: -1}"; echo "\$p nice=\$(ps -o nice= -p \$\$ | tr -d ' ')" >> "$DULOG"
if [ "\$p" = "$T/wt" ] && [ -n "\${FAKE_DU_SLEEP:-}" ]; then trap 'kill \$! 2>/dev/null; exit 143' TERM; sleep "\$FAKE_DU_SLEEP" & wait; fi
printf '12345\t%s\n' "\$p"
EOF
chmod +x "$D2/du"
snap() { # snap <env…> — 스냅샷을 강제(FT_RES_SNAP_SEC=0)해 tick 1회 · 걸린 초는 SECS
  local t0; t0="$(date +%s)"; env FT_RES_ROOT="$R" PATH="$D2:$S:$PATH" FT_RES_SNAP_SEC=0 FT_WORKTREES="$T/wt" FAKE_SWAP=6000 FAKE_LEVEL=1 FAKE_MEMFREE=50 "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1
  SECS=$(( $(date +%s) - t0 )); }
wcalls() { grep -c "^$T/wt " "$DULOG" 2>/dev/null || true; }
wtotal() { awk -F'\t' '$2=="worktrees.total"{v=$3} END{print v}' "$ST/disk-attrib.tsv"; }
reset_du() { rm -f "$DULOG" "$ST/disk-attrib.tsv" "$ST/du-cache.tsv" "$ST/.disk-attrib-last"; rm -rf "$ST/du-scan.lock.d"; : > "$DULOG"; }
reset_du; snap FAKE_DU_SLEEP=30 FT_RES_DU_CAP_SEC=1
[ "$SECS" -le 15 ] && ok "R323 du 가 멈춰도 tick 은 상한 안에 끝남(${SECS}s ≤ 15)" || bad "R323 tick 이 ${SECS}s 걸림"
eq "$(wtotal)" TIMEOUT "R323 상한 초과 → worktrees.total=TIMEOUT(캐시 없음)"
[ ! -d "$ST/du-scan.lock.d" ] && ok "R323 끝난 뒤 잠금 해제" || bad "R323 잠금이 남음"
sleep 1; [ -z "$(pgrep -f "$D2/du" 2>/dev/null)" ] && ok "R323 상한 초과 du 프로세스 정리(잔존 0)" || bad "R323 du 프로세스 잔존"
reset_du; snap
eq "$(wtotal)" 12345 "R323 정상 du → worktrees.total 기록"
has "$(grep "^$T/wt " "$DULOG")" "nice=19" "R323 du 는 nice 19 로 돈다"
eq "$(wcalls)" 1 "R323 첫 스냅샷 = 워크트리 du 1회"
snap; eq "$(wcalls)" 1 "R323 TTL 안 두 번째 스냅샷 = 캐시 사용(du 재호출 0)"; eq "$(wtotal)" 12345 "R323 캐시 값이 기록됨"
snap FT_RES_DU_TTL_SEC=0; eq "$(wcalls)" 2 "R323 TTL 0 → 다시 스캔"
reset_du; mkdir "$ST/du-scan.lock.d"; echo "$$ $(date +%s)" > "$ST/du-scan.lock.d/owner"; echo "$$" > "$ST/du-scan.lock.d/pid"
snap
eq "$(wcalls)" 0 "R323 다른 스캔이 잠금 중(살아 있는 pid) → 두 번째 스캔 시작 0"
[ -d "$ST/du-scan.lock.d" ] && ok "R323 남의 잠금은 건드리지 않음" || bad "R323 남의 잠금을 지움"
has "$(tail -3 "$WLOG")" "du 스캔 진행 중" "R323 건너뛴 사실을 로그 1줄"
reset_du; mkdir "$ST/du-scan.lock.d"; true & dp=$!; wait $dp; echo "$dp $(date +%s)" > "$ST/du-scan.lock.d/owner"; echo "$dp" > "$ST/du-scan.lock.d/pid"
snap; eq "$(wcalls)" 1 "R323 죽은 pid 잠금 = 회수 후 스캔"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
