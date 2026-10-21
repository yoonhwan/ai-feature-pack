#!/usr/bin/env bash
# test_resource_watch.sh — R320 ft-resource-watch.sh: 동결 자동 해제 교정 · (R323) du 스캔 상한 · 원인 좌석 표시.
# 가짜 센서(PATH 앞)·임시 FT_RES_ROOT 만 쓴다 — 실 동결 파일·실 launchd·실 tmux 0. 값은 FAKE_* env 로 준다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_RECLAIM_PREVENT_SEC=0   # R332 3b: 기존 시험은 선제 회수 호출 0 (예방 시험만 아래 ptick 이 켠다 · 실 tmux 0)
unset FT_RES_SWAP_FREEZE   # r633 DA⑥ r1 ⑥: 전역 env 0 — swap 동결을 보는 단언만 호출마다 FT_RES_SWAP_FREEZE=1(env 모드) · 같은 입력의 기본 모드 단언은 아래 «r633 기본 모드» 블록
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
kids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kids "$c"; echo "$c"; done; }   # 자손 pid(깊은 쪽 먼저)
T="$(cd "$(mktemp -d)" && pwd -P)"
# 시험이 끝나거나 끊길 때(EXIT·INT·TERM) 이 시험이 띄운 자손(awk·tick 등)을 모두 정리한다 — 멈춘 자손이 2시간 남던 사고(DA⑥ H4)
trap 'kill $(kids $$) 2>/dev/null; rm -rf "$T"' EXIT; trap 'exit 143' INT TERM
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
seed() { # 표본줄 N개(이전 시각순) — 인자: swap memfree level 개수 · NOW 는 호출마다 갱신(R357: 동결 틱이 길어져도 표본이 낡지 않게)
  local i; NOW="$(date +%s)"; : > "$PTSV"; for i in $(seq "$4" -1 1); do printf '%s\t%s\t%s\t%s\t2303978\n' "$((NOW-60*i))" "$1" "$2" "$3" >> "$PTSV"; done; }
printf '#!/bin/bash\necho "$*" >> "%s/wrc.calls"\necho "후보 | 종류 | 승인 근거 | 결과"\necho "PREVENTIVE reclaimed=0 candidates=0 skipped=0 pressure=0 swap=0%%"\n' "$T" > "$T/wrc.sh"; chmod 755 "$T/wrc.sh"   # r633: 기본 모드 swap 경고 틱의 회수 도구(가짜 · 실 tmux 0)
printf '#!/bin/bash\n[ "$1" = send ] && printf "%%s\\n" "$*" >> "%s/wmbox.log"\nexit 0\n' "$T" > "$T/wmbox.sh"; chmod 755 "$T/wmbox.sh"   # r633: 가짜 mbox(실 쪽지 0)
tick() { # tick <env…> — 임시 루트에서 감시자 tick 1회 (r633: 회수 도구·mbox 는 가짜 기본값 · 인자로 덮어쓸 수 있음)
  env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FT_RECLAIM_SH="$T/wrc.sh" FT_MBOX_SH="$T/wmbox.sh" "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
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
# R357: 옛 단언 «swap>12288 단독 동결(level 1)» 은 플래핑의 원인이라 교체 — swap 트리거는 level≥2 와 결합(카드 r357 §시험 입력 ⓗ)
rm -f "$FREEZE"; seed 13000 40 2 2; tick FAKE_SWAP=13000 FAKE_LEVEL=2 FAKE_MEMFREE=40 FT_RES_SWAP_FREEZE=1
[ -f "$FREEZE" ] && ok "R357 동결 트리거 swap>12288 & level 2 → 동결" || bad "R357 swap 13000·level 2 동결 안 걸림"

# ── R357. swap 절대량 단독 동결·해제 플래핑 폐기 ──
cnt() { grep -c "$1" "$WLOG" 2>/dev/null || true; }
# ⓖ 플래핑 재현: 동결 없음 · swap 13500 memfree 55 level 1 ×3 틱 → 동결·해제 모두 0 (옛 코드 = FREEZE·THAW·FREEZE)
rm -f "$FREEZE" "$WLOG"; seed 13500 55 1 3
for _i in 1 2 3; do tick FAKE_SWAP=13500 FAKE_LEVEL=1 FAKE_MEMFREE=55; done
eq "$(cnt 'FREEZE created')" 0 "R357 ⓖ swap13500·level1 ×3틱 → FREEZE created 0"
eq "$(cnt 'THAW removed')" 0 "R357 ⓖ THAW 0"
[ ! -f "$FREEZE" ] && ok "R357 ⓖ 동결 파일 없음" || bad "R357 ⓖ 동결 파일이 생김"
# ⓗ swap 13500 level 2 → 동결 1(사유 줄에 swap·level) → level 1 로 내려가고 rate≤512 → 해제 1 → 이어 2틱 동결 0
rm -f "$FREEZE" "$WLOG"; seed 13500 55 2 2; tick FAKE_SWAP=13500 FAKE_LEVEL=2 FAKE_MEMFREE=55 FT_RES_SWAP_FREEZE=1
eq "$(cnt 'FREEZE created')" 1 "R357 ⓗ swap13500·level2 → FREEZE created 1"
has "$(cat "$FREEZE" 2>/dev/null)" "swap=13500M level=2" "R357 ⓗ 동결 사유 줄에 swap·level"
seed 13500 55 1 3; tick FAKE_SWAP=13500 FAKE_LEVEL=1 FAKE_MEMFREE=55
eq "$(cnt 'THAW removed')" 1 "R357 ⓗ level 1 · rate≤512 → THAW 1"
tick FAKE_SWAP=13500 FAKE_LEVEL=1 FAKE_MEMFREE=55; tick FAKE_SWAP=13500 FAKE_LEVEL=1 FAKE_MEMFREE=55
eq "$(cnt 'FREEZE created')" 1 "R357 ⓗ 해제 뒤 2틱 → 새 FREEZE 0(총 1 그대로)"
# ⓘ 불변식: 해제 직전 트리거 재평가 — 동결 있음 · memfree 22(해제 ≥20 참) · FT_RES_MEM_MIN=25(트리거 <25 참) → 해제하지 않고 THAW held trig=memfree
rm -f "$WLOG"; frz; seed 9000 22 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=22 FT_RES_MEM_MIN=25
[ -f "$FREEZE" ] && ok "R357 ⓘ 해제·트리거 동시 참 → 동결 유지" || bad "R357 ⓘ 트리거가 참인데 해제됨"
eq "$(cnt 'THAW removed')" 0 "R357 ⓘ THAW removed 0"
has "$(cat "$WLOG")" "THAW held trig=memfree" "R357 ⓘ 로그 THAW held trig=memfree"
# ⓙ 다른 트리거 불변: memfree<10 · disk<25 는 level 과 무관하게 동결
rm -f "$FREEZE"; seed 9000 40 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=9
[ -f "$FREEZE" ] && ok "R357 ⓙ memfree 9 → 동결(level 1)" || bad "R357 ⓙ memfree 9 동결 안 걸림"
rm -f "$FREEZE"; seed 9000 40 1 2; tick FAKE_SWAP=9000 FAKE_LEVEL=1 FAKE_MEMFREE=40 FAKE_DISK_KIB=$((24*1048576))
[ -f "$FREEZE" ] && ok "R357 ⓙ disk 24G → 동결(level 1)" || bad "R357 ⓙ disk 24G 동결 안 걸림"
# ⓚ 무효 FT_SWAP_LEVEL_MIN(abc·0·-1) → 로그 WARN 1줄(중복 0) + 기본 2 로 동작(swap13500·level2 동결) · 미설정 → WARN 0
for v in abc 0 -1; do
  rm -f "$FREEZE" "$WLOG"; seed 13500 55 2 2; tick FAKE_SWAP=13500 FAKE_LEVEL=2 FAKE_MEMFREE=55 FT_SWAP_LEVEL_MIN="$v" FT_RES_SWAP_FREEZE=1
  eq "$(cnt "WARN FT_SWAP_LEVEL_MIN=${v} ")" 1 "R357 ⓚ FT_SWAP_LEVEL_MIN=${v} → 로그 WARN 1줄(중복 0)"
  [ -f "$FREEZE" ] && ok "R357 ⓚ ${v} → 기본 2 적용(swap13500·level2 동결)" || bad "R357 ⓚ ${v} 인데 기본 2 로 동작 안 함"
done
rm -f "$FREEZE" "$WLOG"; seed 13500 55 2 2; tick FAKE_SWAP=13500 FAKE_LEVEL=2 FAKE_MEMFREE=55 FT_RES_SWAP_FREEZE=1
eq "$(cnt 'WARN')" 0 "R357 ⓚ 미설정 → WARN 0"
# ⓛ 10-14 03:31 원 사고 입력 보존 — disk 748MiB(=0GiB) · level 4 · swap 13500 · memfree 30 → 동결 trig=disk(swap 파일 23개는 센서 아님 — 환산 0)
rm -f "$FREEZE" "$WLOG"; seed 13500 30 4 2; tick FAKE_SWAP=13500 FAKE_LEVEL=4 FAKE_MEMFREE=30 FAKE_DISK_KIB=$((748*1024))
has "$(cat "$WLOG" 2>/dev/null)" "trig=disk" "R357 ⓛ4 원 사고 입력 → FREEZE created trig=disk"
rm -f "$FREEZE" "$WLOG"; seed 13500 30 4 2; tick FAKE_SWAP=13500 FAKE_LEVEL=4 FAKE_MEMFREE=30 FT_RES_SWAP_FREEZE=1
has "$(cat "$WLOG" 2>/dev/null)" "trig=swap" "R357 ⓛ5 (env 모드) disk 86G·level4·swap13500 → trig=swap(결합)"
# ── r633 기본 모드(env 없음) — 같은 입력에서 swap∧level2 는 동결 0 · level 4 는 단독 동결 ──
rm -f "$FREEZE" "$WLOG" "$T/wrc.calls"; seed 13500 55 2 3; for _i in 1 2; do tick FAKE_SWAP=13500 FAKE_LEVEL=2 FAKE_MEMFREE=55; done
for _i in $(seq 1 100); do [ -f "$T/wrc.calls" ] && [ ! -d "$ST/swap-warn-send.lock.d" ] && break; sleep 0.2; done   # r633 r3: 발신 쪽은 분리 실행 — 끝날 때까지 기다려 다음 시험 로그에 섞이지 않게
eq "$(cnt 'FREEZE created')" 0 "r633 기본 ⓗ swap13500·level2 ×2틱 → FREEZE created 0"
[ ! -f "$FREEZE" ] && ok "r633 기본 ⓗ 동결 파일 없음" || bad "r633 기본 ⓗ 동결 파일이 생김"
has "$(cat "$T/wrc.calls" 2>/dev/null)" "--dry-run --preventive" "r633 기본 ⓗ 닫기 목록 경로(가짜 회수 도구 --dry-run --preventive)"
rm -f "$FREEZE" "$WLOG"; seed 13500 30 4 2; tick FAKE_SWAP=13500 FAKE_LEVEL=4 FAKE_MEMFREE=30
has "$(cat "$WLOG" 2>/dev/null)" "trig=level" "r633 기본 ⓛ5 level4·swap13500 → trig=level(swap 결합 아님)"
rm -f "$FREEZE" "$WLOG"; seed 6000 30 4 2; tick FAKE_SWAP=6000 FAKE_LEVEL=4 FAKE_MEMFREE=30
[ -f "$FREEZE" ] && ok "r633 기본 level4·swap6000 → 동결(옛 판 구멍)" || bad "r633 기본 level4 동결 0"
rm -f "$FREEZE" "$WLOG"

# ── R320c. 해제의 swap 축 = 문지기(ft-resource-gate.sh)와 «같은 rate 정의» — 마지막 6표본 (s1−s0)×60/(t1−t0) ≤ 허용치(512) ──
seedseq() { # seedseq <swap…> — 인자 개수만큼 표본(1분 간격 · 마지막이 NOW-60) · memfree 40 · level 1
  local n=$# i=$#; NOW="$(date +%s)"; : > "$PTSV"; for s in "$@"; do printf '%s\t%s\t40\t1\t2303978\n' "$((NOW-60*i))" "$s" >> "$PTSV"; i=$((i-1)); done; }
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

# ── R323. 디스크 스냅샷의 du: 상한 7초(시험은 FT_RES_DU_CAP_SEC 로 단축) · nice 19 · 잠금 1개 · (r534) 워크트리 합계 = 폴더별 증분 캐시 합 ──
grep -q 'FT_RES_DU_CAP_SEC:-7' "$BIN/ft-resource-watch.sh" && ok "R323 du 상한 기본 7초" || bad "R323 du 상한 기본값이 7초가 아님"
D2="$T/du2"; mkdir -p "$D2" "$T/wt/a"; DULOG="$T/du.log"
cat > "$D2/du" <<EOF
#!/bin/bash
p="\${@: -1}"; echo "\$p nice=\$(ps -o nice= -p \$\$ | tr -d ' ')" >> "$DULOG"
if [ "\${p#$T/wt/}" != "\$p" ] && [ -n "\${FAKE_DU_SLEEP:-}" ]; then trap 'kill \$! 2>/dev/null; exit 143' TERM; sleep "\$FAKE_DU_SLEEP" & wait; fi
printf '12345\t%s\n' "\$p"
EOF
chmod +x "$D2/du"
snap() { # snap <env…> — 스냅샷을 강제(FT_RES_SNAP_SEC=0)해 tick 1회 · 걸린 초는 SECS
  local t0; t0="$(date +%s)"; env FT_RES_ROOT="$R" PATH="$D2:$S:$PATH" HOME="$T/home" TMPDIR="$T/home" FT_RES_SNAP_SEC=0 FT_WORKTREES="$T/wt" FAKE_SWAP=6000 FAKE_LEVEL=1 FAKE_MEMFREE=50 "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1
  SECS=$(( $(date +%s) - t0 )); }
wcalls() { grep -c "^$T/wt/" "$DULOG" 2>/dev/null || true; }
wtotal() { awk -F'\t' '$2=="worktrees.total"{v=$3} END{print v}' "$ST/disk-attrib.tsv"; }
reset_du() { rm -f "$DULOG" "$ST/disk-attrib.tsv" "$ST/du-cache.tsv" "$ST/.disk-attrib-last"; rm -rf "$ST/du-scan.lock.d"; : > "$DULOG"; }
reset_du; snap FAKE_DU_SLEEP=30 FT_RES_DU_CAP_SEC=1
[ "$SECS" -le 15 ] && ok "R323 du 가 멈춰도 tick 은 상한 안에 끝남(${SECS}s ≤ 15)" || bad "R323 tick 이 ${SECS}s 걸림"
eq "$(wtotal)" "PARTIAL 0" "R323 상한 초과 → worktrees.total 숫자 아님(r534: PARTIAL · 그 폴더만 TIMEOUT)"
[ ! -d "$ST/du-scan.lock.d" ] && ok "R323 끝난 뒤 잠금 해제" || bad "R323 잠금이 남음"
sleep 1; [ -z "$(pgrep -f "$D2/du" 2>/dev/null)" ] && ok "R323 상한 초과 du 프로세스 정리(잔존 0)" || bad "R323 du 프로세스 잔존"
reset_du; snap
eq "$(wtotal)" 12345 "R323 정상 du → worktrees.total 기록"
has "$(grep "^$T/wt/a " "$DULOG")" "nice=19" "R323 du 는 nice 19 로 돈다"
eq "$(wcalls)" 1 "R323 첫 스냅샷 = 워크트리 폴더 du 1회"
snap FT_RES_WT_PER_TICK=0; eq "$(wcalls)" 1 "r534 틱당 0개 → du 재호출 0"; eq "$(wtotal)" 12345 "r534 폴더별 캐시 합이 기록됨"
snap; eq "$(wcalls)" 2 "r534 다음 틱 = 다시 잼(돌아가며)"
reset_du; mkdir "$ST/du-scan.lock.d"; echo "$$ $(date +%s)" > "$ST/du-scan.lock.d/owner"; echo "$$" > "$ST/du-scan.lock.d/pid"
snap
eq "$(wcalls)" 0 "R323 다른 스캔이 잠금 중(살아 있는 pid) → 두 번째 스캔 시작 0"
[ -d "$ST/du-scan.lock.d" ] && ok "R323 남의 잠금은 건드리지 않음" || bad "R323 남의 잠금을 지움"
has "$(tail -3 "$WLOG")" "du 스캔 진행 중" "R323 건너뛴 사실을 로그 1줄"
reset_du; mkdir "$ST/du-scan.lock.d"; true & dp=$!; wait $dp; echo "$dp $(date +%s)" > "$ST/du-scan.lock.d/owner"; echo "$dp" > "$ST/du-scan.lock.d/pid"
snap; eq "$(wcalls)" 1 "R323 죽은 pid 잠금 = 회수 후 스캔"

# ── R332. 선제 회수 호출 — tick 진입 직후 «독립된» 보조 호출(ft-resource-preventive.sh) · 예방 stamp+실행권 한 직렬 · 실패·경합이 측정·동결을 안 바꿈 ──
# 회수 도구는 대역(FT_RECLAIM_SH)만 쓴다 — 실 tmux·실 kill 0. 위 기존 시험은 파일 맨 위 export 의 FT_RECLAIM_PREVENT_SEC=0 으로 예방 호출 0.
bash -n "$BIN/ft-resource-preventive.sh" && ok "bash -n preventive" || bad "bash -n preventive"
cmp -s "$BIN/ft-resource-preventive.sh" "$KIT/ft-resource-preventive.sh" && ok "키트 사본 cmp 0 preventive" || bad "키트 사본 어긋남 preventive"
grep -q 'ft-resource-preventive.sh' "$BIN/ft-resource-watch.sh" && ok "R332 감시자가 선제 호출을 부름" || bad "R332 감시자 연결 없음"
RC="$T/rc"; mkdir -p "$RC" "$T/badsys"; RCSH="$RC/reclaim.sh"
printf '#!/bin/sh\nexit 1\n' > "$T/badsys/sysctl"; chmod 755 "$T/badsys/sysctl"
cat > "$RCSH" <<EOF
#!/bin/bash
echo "\$*" >> "$RC/calls"
sleep "\$(cat "$RC/sleep" 2>/dev/null || echo 0)"
cat "$RC/out" 2>/dev/null
exit "\$(cat "$RC/rc" 2>/dev/null || echo 0)"
EOF
chmod +x "$RCSH"
rcalls() { [ -f "$RC/calls" ] && wc -l < "$RC/calls" | tr -d ' ' || echo 0; }
pstate() { rm -f "$RC/calls" "$ST/.preventive-last"; rm -rf "$ST/preventive.lock.d"; echo 0 > "$RC/sleep"; echo 0 > "$RC/rc"; echo "PREVENTIVE reclaimed=0 candidates=0 skipped=0" > "$RC/out"; rm -f "$FREEZE"; seed 6000 50 1 2; }
ptick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FT_RECLAIM_PREVENT_SEC=600 FT_RECLAIM_SH="$RCSH" FAKE_SWAP=6000 FAKE_LEVEL=1 FAKE_MEMFREE=50 "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
# ⓔ 정상 / gate 측정 오류 / 새 freeze 생성 — 세 경로 모두 due 면 예방 호출 1 (조기 종료와 독립)
pstate; ptick; eq "$(rcalls)" 1 "R332 ⓔ 정상 tick → 예방 호출 1"
[ -f "$ST/.preventive-last" ] && ok "R332 ⓔ 완료 stamp 기록" || bad "R332 ⓔ 완료 stamp 없음"
pstate; ptick PATH="$T/badsys:$S:$PATH"; prc=$?
{ [ "$prc" -ne 0 ] && [ "$(rcalls)" = 1 ]; } && ok "R332 ⓔ gate 측정 오류(tick rc=$prc)에서도 예방 호출 1" || bad "R332 ⓔ 측정 오류 경로 rc=$prc 호출=$(rcalls)"
pstate; ptick FAKE_SWAP=13000 FAKE_LEVEL=2 FT_RES_SWAP_FREEZE=1
{ [ -f "$FREEZE" ] && [ "$(rcalls)" = 1 ]; } && ok "R332 ⓔ 새 freeze 생성 tick 에서도 예방 호출 1 · 동결은 그대로 생성" || bad "R332 ⓔ freeze 경로 호출=$(rcalls) freeze=$([ -f "$FREEZE" ] && echo 있음 || echo 없음)"
# ⓑ stamp 오래됨 + 동시 두 tick → 호출 1 (실행권 mkdir 1회 · 경합이면 즉시 포기)
pstate; echo 2 > "$RC/sleep"; ( ptick & ptick & wait )
eq "$(rcalls)" 1 "R332 ⓑ 동시 두 tick → 예방 호출 1"
# ⓒ 후보 0 정상 완료도 완료 기록 → 다음 600초 안 tick 호출 0 · 기한이 지나면 다시 호출
echo 0 > "$RC/sleep"; ptick; ptick; eq "$(rcalls)" 1 "R332 ⓒ 후보 0 정상 완료 뒤 600초 안 tick 호출 0"
sleep 2; ptick FT_RECLAIM_PREVENT_SEC=1; eq "$(rcalls)" 2 "R332 ⓒ 기한(1초) 지나면 다시 호출"
# ⓓ 경합(skipped=lock)·실패(rc≠0)는 완료 기록 0 → 다음 tick 재시도 · 측정 tick 은 상한 안에 끝남
pstate; echo "PREVENTIVE skipped=lock" > "$RC/out"; t0=$(date +%s); ptick; ptick
{ [ "$(rcalls)" = 2 ] && [ ! -e "$ST/.preventive-last" ]; } && ok "R332 ⓓ 경합 skipped=lock = stamp 0 · 다음 tick 재시도(호출 2)" || bad "R332 ⓓ 경합 호출=$(rcalls) stamp=$([ -e "$ST/.preventive-last" ] && echo 있음 || echo 없음)"
[ $(( $(date +%s) - t0 )) -le 15 ] && ok "R332 ⓓ 경합 tick 두 번 15초 안 종료" || bad "R332 ⓓ 경합 tick 이 느림"
pstate; echo 1 > "$RC/rc"; echo "boom" > "$RC/out"; ptick FAKE_SWAP=13000 FAKE_LEVEL=2 FT_RES_SWAP_FREEZE=1; ptick FAKE_SWAP=13000 FAKE_LEVEL=2 FT_RES_SWAP_FREEZE=1
{ [ "$(rcalls)" = 2 ] && [ ! -e "$ST/.preventive-last" ] && [ -f "$FREEZE" ]; } && ok "R332 ⓓ 회수 실패(rc1) = stamp 0·재시도 · 측정·동결은 정상" || bad "R332 ⓓ 실패 경로 호출=$(rcalls)"
# 잠금 점유: 살아 있는 pid = 호출 0 · 남의 잠금 보존 / 죽은 pid = 회수 후 호출 1
pstate; mkdir "$ST/preventive.lock.d"; echo $$ > "$ST/preventive.lock.d/pid"; ptick
{ [ "$(rcalls)" = 0 ] && [ "$(cat "$ST/preventive.lock.d/pid")" = "$$" ]; } && ok "R332 살아 있는 실행권 = 호출 0 · 남의 잠금 보존" || bad "R332 살아 있는 잠금 처리 이상"
rm -rf "$ST/preventive.lock.d"; true & dpp=$!; wait $dpp; mkdir "$ST/preventive.lock.d"; echo "$dpp" > "$ST/preventive.lock.d/pid"; ptick
eq "$(rcalls)" 1 "R332 죽은 pid 실행권 = 회수 후 호출 1"
[ ! -d "$ST/preventive.lock.d" ] && ok "R332 끝난 뒤 실행권 해제" || bad "R332 실행권이 남음"
# ⓕ FT_RECLAIM_PREVENT_SEC=0 → 호출 0
pstate; ptick FT_RECLAIM_PREVENT_SEC=0; eq "$(rcalls)" 0 "R332 ⓕ FT_RECLAIM_PREVENT_SEC=0 → 호출 0"
# DA⑥ H2: 낡은 stamp + 죽은 pid 잠금 + 동시 두 호출 → 호출 1 (회수+획득 직렬화 · 남의 새 잠금을 지우지 않음) — 삭제 도구를 느리게 해 «둘 다 죽은 잠금을 본 뒤 지우는» 창을 연다(옛 코드는 호출 2)
SR="$T/slowrm"; mkdir -p "$SR"; printf '#!/bin/sh\nsleep 0.4\nexec /bin/rm "$@"\n' > "$SR/rm"; chmod 755 "$SR/rm"
pv() { env FT_RES_ROOT="$R" PATH="$SR:$PATH" FT_RECLAIM_PREVENT_SEC=600 FT_RECLAIM_SH="$RCSH" bash "$BIN/ft-resource-preventive.sh" >/dev/null 2>&1; }
h2bad=0
for _r in 1 2 3; do
  pstate; echo 1 > "$RC/sleep"; mkdir "$ST/preventive.lock.d"; true & dq=$!; wait $dq; echo "$dq" > "$ST/preventive.lock.d/pid"
  ( pv & sleep 0.2; pv & wait )   # 둘째가 0.2초 늦게 와 «첫째가 새 잠금을 만든 뒤» 낡은 삭제가 끝나는 순서를 만든다
  [ "$(rcalls)" = 1 ] || { h2bad=$((h2bad+1)); echo "  H2 회차 $_r 호출=$(rcalls)"; }
done
[ "$h2bad" = 0 ] && ok "R332 H2 죽은 잠금 + 동시 두 호출 ×3 → 호출 1" || bad "R332 H2 동시 회수 경쟁 ${h2bad}/3 회차에서 호출 2"
rm -rf "$ST/preventive.lock.d" "$ST/preventive.lock.d.rc"
# DA⑥ H4: stdin 을 열어 둔 채(tty 없는 배경 셸 꼴) freeze 생성 tick·scan 이 awk 에서 멈추면 안 된다 — 입력 파일 인자 명시
mkfifo "$T/hold"; exec 7<>"$T/hold"
held() { # held <상한초> <watch 인자…> — stdin=열린 fifo · 제한 안에 안 끝나면 정리하고 rc 1
  local lim="$1" i wp; shift
  ( env FT_RES_ROOT="$R" PATH="$D2:$S:$PATH" HOME="$T/home" TMPDIR="$T/home" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FAKE_SWAP=13000 FAKE_LEVEL=2 FAKE_MEMFREE=40 FT_RECLAIM_PREVENT_SEC=0 FT_RES_SWAP_FREEZE=1 bash "$BIN/ft-resource-watch.sh" "$@" <&7 >/dev/null 2>&1 ) & wp=$!
  for i in $(seq 1 $((lim*10))); do kill -0 "$wp" 2>/dev/null || { wait "$wp"; return 0; }; sleep 0.1; done
  kill $(pgrep -P "$wp") "$wp" 2>/dev/null; return 1
}
mkdir -p "$T/home"   # r534: 실 HOME(claude.projects·caches) 을 증분으로 훑지 않게 격리
rm -f "$FREEZE"; printf '%s\tdisk.free\t100000000\n%s\tworktrees.total\t100\n' "$((NOW-900))" "$((NOW-900))" > "$ST/disk-attrib.tsv"; seed 13000 40 2 2
held 8 tick && ok "R332 H4 stdin 을 열어 둔 freeze 생성 tick(top1_disk awk) → 8초 안 종료" || bad "R332 H4 top1_disk awk 가 stdin 에서 멈춤"
[ -f "$FREEZE" ] && ok "R332 H4 freeze 파일 생성" || bad "R332 H4 freeze 미생성"
held 8 scan && ok "R332 H4 stdin 을 열어 둔 scan(disk_top·floor_line awk) → 8초 안 종료" || bad "R332 H4 scan awk 가 stdin 에서 멈춤"
exec 7<&-

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
