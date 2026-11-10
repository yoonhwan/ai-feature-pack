#!/usr/bin/env bash
# test_resource_watch_incremental_r534.sh — r534 감시자 디스크 기록표: 워크트리·큰 폴더(pytest·caches·claude.projects)를 1단계 폴더별 «증분» 측정.
#   (워크트리 443개 전체 du 1회가 7초 상한에 매번 걸려 worktrees.total=TIMEOUT 393회 · 10-17 21:22 뒤 숫자 0 — 오빠 «디스크 한 100G 줄었는데?»)
# 가짜 du(경로별 크기·걸리는 시간 = DUCFG 표)·가짜 센서·임시 FT_RES_ROOT·임시 HOME/TMPDIR 만 쓴다 — 실 du·실 동결·실 launchd·실 tmux 0 · 외부 호출 0 · GIT_* 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_RECLAIM_PREVENT_SEC=0
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
kids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kids "$c"; echo "$c"; done; }
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'kill $(kids $$) 2>/dev/null; rm -rf "$T"' EXIT; trap 'exit 143' INT TERM
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; WT="$T/wt"; HM="$T/home"; TD="$T/tmpd"
mkdir -p "$S" "$ST" "$WT" "$HM" "$TD"
TSV="$ST/disk-attrib.tsv"; CACHE="$ST/du-cache.tsv"; DUCFG="$T/du.cfg"; DULOG="$T/du.log"; : > "$DUCFG"
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 6000.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo 1;;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 50%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\nexit 1\n' > "$S/pgrep"; printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
# 가짜 du — 마지막 인자 경로를 DUCFG(경로<TAB>KB<TAB>초)에서 찾음 · 없으면 1KB·0초 · 부른 경로를 DULOG 에 1줄
cat > "$S/du" <<EOF
#!/bin/bash
p="\${@: -1}"; echo "\$p" >> "$DULOG"
line="\$(awk -F'\t' -v p="\$p" '\$1==p{l=\$2" "\$3} END{print l}' "$DUCFG")"; kb="\${line% *}"; sl="\${line#* }"
[ -n "\$line" ] || { kb=1; sl=0; }
[ "\${sl:-0}" = 0 ] || { trap 'kill \$! 2>/dev/null; exit 143' TERM; sleep "\$sl" & wait; }
printf '%s\t%s\n' "\$kb" "\$p"
EOF
chmod 755 "$S"/*
cfg() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-0}" >> "$DUCFG"; }   # cfg <경로> <KB> [초]
snap() { # 스냅샷 강제 tick 1회 · 걸린 초 = SECS
  local t0; t0="$(date +%s)"
  env FT_RES_ROOT="$R" PATH="$S:$PATH" HOME="$HM" TMPDIR="$TD" USER=u FT_RES_SNAP_SEC=0 FT_WORKTREES="$WT" FT_RES_DU_CAP_SEC=2 "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1
  SECS=$(( $(date +%s) - t0 )); }
last() { awk -F'\t' -v k="$1" '$2==k{v=$3} END{print v}' "$TSV" 2>/dev/null; }   # 칸 k 의 마지막 값
lastts() { awk -F'\t' 'END{print $1}' "$TSV"; }
tickrows() { awk -F'\t' -v t="$(lastts)" '$1==t' "$TSV"; }   # 마지막 스냅샷 줄 전부
reset() { rm -f "$TSV" "$CACHE" "$ST/.disk-attrib-last" "$DULOG"; : > "$DULOG"; : > "$DUCFG"; }
bash -n "$BIN/ft-resource-watch.sh" && ok "bash -n watch" || bad "bash -n watch"
bash -n "$BIN/ft-resource-du-lib.sh" && ok "bash -n du-lib" || bad "bash -n du-lib"
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245(증분 함수는 du-lib)" || bad "감시자 줄 수 >245"
for f in ft-resource-watch.sh ft-resource-du-lib.sh ft-resource-cause.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done

# ── ⓐ 폴더 20개 · 전체 du 는 상한(2초)을 넘김(3초) → 고치기 전 = worktrees.total TIMEOUT. 고친 뒤 = 한 틱 8개씩 · 3틱 뒤 20/20 · 합 = 캐시 합 숫자 ──
reset; cfg "$WT" 999999 3
for i in $(seq -w 1 20); do mkdir -p "$WT/w$i"; cfg "$WT/w$i" $((10#$i * 10)); done
snap FT_RES_WT_PER_TICK=8
eq "$(last worktrees.known)" "8/20" "ⓐ 1틱 = 8개만 잼 → worktrees.known 8/20"
case "$(last worktrees.total)" in PARTIAL*) ok "ⓐ 1틱 합 = PARTIAL(모르는 폴더 있음 — 부분 합을 숫자처럼 쓰지 않음)";; *) bad "ⓐ 1틱 합이 PARTIAL 아님 — «$(last worktrees.total)»";; esac
eq "$(grep -c "^$WT\$" "$DULOG")" 0 "ⓐ 워크트리 폴더 전체 du 0회"
eq "$(grep -c "^$WT/" "$DULOG")" 8 "ⓐ 폴더별 du = 틱당 8회"
snap FT_RES_WT_PER_TICK=8; eq "$(last worktrees.known)" "16/20" "ⓐ 2틱 → 16/20"
snap FT_RES_WT_PER_TICK=8; eq "$(last worktrees.known)" "20/20" "ⓐ 3틱 → 20/20"
eq "$(last worktrees.total)" 2100 "ⓐ 20/20 → worktrees.total = 캐시 합 숫자(10+…+200=2100)"
hasnt "$(cat "$TSV")" "TIMEOUT" "ⓐ TIMEOUT 줄 0"
has "$(tickrows)" "wt.top	w20 200" "ⓐ 한 바퀴 끝 → wt.top 1위 w20 200"
eq "$(tickrows | grep -c '	wt.top	')" 5 "ⓐ wt.top 상위 5줄"
has "$(grep '	wt:w20	' "$CACHE")" "	200" "ⓐ 캐시 du-cache.tsv 에 wt:<이름> 줄"

# ── ⓑ 새 폴더(캐시 없음) → 잰 뒤 바뀐 폴더(2시간 안 mtime) → 캐시 오래된 순 ──
mkdir -p "$WT/wnew"; cfg "$WT/wnew" 7; touch -t "$(date -v+2M +%Y%m%d%H%M)" "$WT/w03"
: > "$DULOG"; snap FT_RES_WT_PER_TICK=2
eq "$(sed -n '/\/wt\//p' "$DULOG" | tr '\n' ' ')" "$WT/wnew $WT/w03 " "ⓑ 순번 = 새 폴더(wnew) → 바뀐 폴더(w03)"
: > "$DULOG"; snap FT_RES_WT_PER_TICK=2
hasnt "$(cat "$DULOG")" "/wnew" "ⓑ 잰 뒤 안 바뀐 폴더는 다음 틱 맨 앞 아님"
eq "$(last worktrees.known)" "21/21" "ⓑ 새 폴더 포함 21/21"
eq "$(last worktrees.total)" 2107 "ⓑ 합 = 2100 + 새 폴더 7"

# ── ⓒ 사라진 폴더 → 캐시에서 빠지고 합에서도 빠짐 ──
rmdir "$WT/w05"; snap FT_RES_WT_PER_TICK=2
eq "$(grep -c '	wt:w05	' "$CACHE")" 0 "ⓒ 사라진 폴더 캐시 줄 제거"
eq "$(last worktrees.known)" "20/20" "ⓒ 전체 20"
eq "$(last worktrees.total)" 2057 "ⓒ 합에서 50 빠짐(2107−50)"

# ── ⓓ 한 폴더가 상한을 넘김 → 그 폴더만 TIMEOUT · known n/m · 옛 값을 새 값처럼 0 · 다음 틱부터 1단계 하위로 나눠 잰다 ──
mkdir -p "$WT/w07/a" "$WT/w07/b"; cfg "$WT/w07" 70 5; cfg "$WT/w07/a" 30; cfg "$WT/w07/b" 45
touch -t "$(date -v+3M +%Y%m%d%H%M)" "$WT/w07"
snap FT_RES_WT_PER_TICK=1
has "$(tickrows)" "wt:w07	TIMEOUT" "ⓓ 넘긴 폴더만 TIMEOUT 표기"
eq "$(tickrows | grep -c 'TIMEOUT')" 1 "ⓓ TIMEOUT 은 그 폴더 1줄"
eq "$(last worktrees.known)" "19/20" "ⓓ 합 줄 known 19/20"
eq "$(last worktrees.total)" "PARTIAL 1987" "ⓓ 옛 값(70)을 새 값처럼 안 씀 — PARTIAL 합 = 나머지 19개(2057−70)"
has "$(grep '	wt:w07	' "$CACHE")" "split" "ⓓ 넘긴 폴더 = 나눔 표식(split)"
snap FT_RES_WT_PER_TICK=2
eq "$(last worktrees.known)" "20/20" "ⓓ 다음 틱 하위 a·b 측정 → 20/20"
eq "$(last worktrees.total)" 2062 "ⓓ 합 = 1987 + 30 + 45"
eq "$(grep -c "^$WT/w07\$" "$DULOG")" 1 "ⓓ 나눈 폴더 통째 du 는 다시 안 함"
# 나눌 깊이 0 → 넘긴 폴더는 stale(옛 값 보존 · 합에서 제외)
reset; mkdir -p "$T/wt2/s1" "$T/wt2/s2"; cfg "$T/wt2/s1" 11 5; cfg "$T/wt2/s2" 22
snap FT_WORKTREES="$T/wt2" FT_RES_SPLIT_DEPTH=0
snap FT_WORKTREES="$T/wt2" FT_RES_SPLIT_DEPTH=0
has "$(grep '	wt:s1	' "$CACHE")" "stale" "ⓓ 나눌 수 없음 → 캐시 표기 stale"
eq "$(last worktrees.known)" "1/2" "ⓓ stale 은 known 에서 빠짐"
eq "$(last worktrees.total)" "PARTIAL 22" "ⓓ stale 값은 합에 0"

# ── ⓔ pytest·caches·claude.projects = 1단계 하위 증분 · 칸 이름 그대로 합 + <칸>.known ──
reset; mkdir -p "$HM/.claude/projects/p1" "$HM/.claude/projects/p2" "$HM/.claude/projects/p3" "$HM/Library/Caches/c1" "$HM/Library/Caches/c2" "$TD/pytest-of-u/t1" "$TD/pytest-of-u/t2"
cfg "$HM/.claude/projects" 999 3; cfg "$HM/Library/Caches" 999 3; cfg "$TD/pytest-of-u" 999 3
for x in p1:100 p2:200 p3:300; do cfg "$HM/.claude/projects/${x%:*}" "${x#*:}"; done
cfg "$HM/Library/Caches/c1" 40; cfg "$HM/Library/Caches/c2" 60; cfg "$TD/pytest-of-u/t1" 5; cfg "$TD/pytest-of-u/t2" 6
snap FT_RES_WT_PER_TICK=2; snap FT_RES_WT_PER_TICK=2
eq "$(last claude.projects)" 600 "ⓔ claude.projects = 하위 합 600"; eq "$(last claude.projects.known)" "3/3" "ⓔ claude.projects.known 3/3"
eq "$(last caches)" 100 "ⓔ caches = 100"; eq "$(last caches.known)" "2/2" "ⓔ caches.known 2/2"
eq "$(last pytest)" 11 "ⓔ pytest = 11"; eq "$(last pytest.known)" "2/2" "ⓔ pytest.known 2/2"
eq "$(grep -cE "^($HM/.claude/projects|$HM/Library/Caches|$TD/pytest-of-u)\$" "$DULOG")" 0 "ⓔ 큰 폴더 통째 du 0회"
hasnt "$(cat "$TSV")" "TIMEOUT" "ⓔ TIMEOUT 0"

# ── ⓖ 한 틱 전체 측정 시간 상한(FT_RES_SNAP_BUDGET_SEC) · 예산으로 끊은 du 는 TIMEOUT·나눔 표식 0 ──
grep -q 'FT_RES_SNAP_BUDGET_SEC:-55' "$BIN/ft-resource-watch.sh" && ok "ⓖ 기본 예산 55초(≤60)" || bad "ⓖ 기본 예산 55초 아님"
reset; for i in 1 2 3 4 5 6 7 8 9 10; do mkdir -p "$T/wt3/g$i"; cfg "$T/wt3/g$i" 1 1.5; done
snap FT_WORKTREES="$T/wt3" FT_RES_SNAP_BUDGET_SEC=5
[ "$SECS" -le 8 ] && ok "ⓖ 가짜 du 합 15초 · 예산 5초 → tick ${SECS}s ≤ 8" || bad "ⓖ tick 이 ${SECS}s 걸림"
hasnt "$(cat "$TSV")" "TIMEOUT" "ⓖ 예산으로 끊은 du 는 TIMEOUT 표기 0"
hasnt "$(cat "$CACHE" 2>/dev/null)" "split" "ⓖ 예산으로 끊은 du 는 나눔 표식 0"
sleep 1; [ -z "$(pgrep -f "$S/du" 2>/dev/null)" ] && ok "ⓖ du 잔존 0" || bad "ⓖ du 잔존"

# ── ⓕ ft-resource-cause.sh disk — worktrees.total 증가 → wt: 캐시의 1시간 증가 상위 3 + 주인 좌석 ──
reset; NOW="$(date +%s)"; mkdir -p "$WT/harness-grow" "$WT/newone" "$WT/oldsplit" "$WT/stalewt" "$WT/quiet"
touch -t 202001010000 "$WT/harness-grow" "$WT/oldsplit" "$WT/stalewt" "$WT/quiet"   # 생긴 시각을 옛날로(맥 birthtime 이 mtime 따라 내려감)
G=1048576
{ printf '%s\t%s\t%s\n' $((NOW-3700)) worktrees.total $((10*G)) "$NOW" worktrees.total $((14*G)) $((NOW-3700)) disk.free 1 "$NOW" disk.free 1; } > "$TSV"
{ printf '%s\twt:harness-grow\t%s\t%s\t%s\t\n' $((NOW-100)) $((3*G)) $((NOW-9000)) $((1*G))   # +2G
  printf '%s\twt:newone\t%s\t\t\t\n' $((NOW-50)) $((G))                                # 1시간 안 생긴 폴더 통째 +1G
  printf '%s\twt:oldsplit/x\t%s\t\t\t\n' $((NOW-50)) $((5*G))                          # 옛 폴더의 처음 잰 하위 = 증가 아님
  printf '%s\twt:oldsplit\t-\t\t\tsplit\n' $((NOW-60))
  printf '%s\twt:stalewt\t%s\t%s\t%s\tstale\n' $((NOW-10)) $((9*G)) $((NOW-9000)) 1     # stale = 증가 아님
  printf '%s\twt:quiet\t%s\t%s\t%s\t\n' $((NOW-7200)) $((8*G)) $((NOW-9000)) 1 ; } > "$CACHE"   # 1시간 밖 측정
printf '#!/bin/bash\ncase "$*" in *list-sessions*) echo "byz-harness-nano-grow#0";; esac\n' > "$S/tmux"; chmod 755 "$S/tmux"
out="$(env FT_RES_ROOT="$R" FT_WORKTREES="$WT" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" disk 2>&1)"; rc=$?
eq "$rc" 0 "ⓕ cause disk rc0"
has "$out" "worktrees.total +4.0G ← harness-grow +2.0G→byz-harness-nano-grow#0" "ⓕ 1위 harness-grow +2.0G → 나노 좌석"
has "$out" "newone +1.0G(주인 미상)" "ⓕ 1시간 안 생긴 폴더 통째 증가 · 주인 못 찾음 → «주인 미상»"
hasnt "$out" "oldsplit" "ⓕ 옛 폴더의 처음 잰 하위는 증가 아님"
hasnt "$out" "stalewt" "ⓕ stale 값은 증가 아님"
hasnt "$out" "quiet" "ⓕ 1시간 밖 측정은 제외"
: > "$CACHE"; out="$(env FT_RES_ROOT="$R" FT_WORKTREES="$WT" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" disk 2>&1)"
has "$out" "worktrees.total +4.0G ← 워크트리별 1시간 증가 없음" "ⓕ 캐시에 증가 없음 → 추측 0 한 줄"

echo "---- fail=$fail"; [ "$fail" -eq 0 ]
