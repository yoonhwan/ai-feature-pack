#!/usr/bin/env bash
# test_resource_cause_cpu_lifetime_r1340.sh — r1340 CPU 폭주 감지(ft-resource-cause.sh cpu)가 «순간 CPU ≥30%» 대신
#   «자신 ≥5분 ∧ 살아온 평균(누적 CPU 시간 ÷ 경과) ≥30%» 멤버만 센다 · 분 = 멤버 중 가장 짧은 나이 · time 칸 못 읽음 = 판정 불가 1줄.
#   + 보탬(arch#222): 감시자 disk 칸에 임시 사본($TMPDIR/ft-scratch/<주인 좌석>/) 증분 1칸 · 원인 줄 scratch:<좌석> 갈래.
# 가짜 ps(FT_RES_PS · 칸 = pid ppid tty etime time pcpu comm)·가짜 tmux·가짜 launchd 표·가짜 du·임시 루트/HOME/TMPDIR 만 쓴다 —
#   실 ps·실 du·실 launchctl·실 tmux·실 쪽지·kill 0 · 네트워크 0.
# 기준판: R1340_BIN=<옛 bin 폴더> R1340_BASE=1 → 견본을 옛 ps 칸(time 없음)으로 쓴다(P1·P4·D1 FAIL 이 기대값).
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(RSG_ACTIVE 재진입 표지)
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1 FT_RECLAIM_PREVENT_SEC=0
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; KIT="$REPO/harness/kit/fable-team/bin"; BIN="${R1340_BIN:-$REPO/harness/bin}"
BASE="${R1340_BASE:-0}"; fail=0; T0=$SECONDS
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
kids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kids "$c"; echo "$c"; done; }
T="$(cd "$(mktemp -d)" && pwd -P)"
trap 'kill $(kids $$) 2>/dev/null; rm -rf "$T"' EXIT; trap 'exit 143' INT TERM
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; WT="$T/wt"; HM="$T/home"; TD="$T/tmpd"
mkdir -p "$S" "$ST" "$WT" "$HM" "$TD"
[ "$BASE" = 1 ] || for f in ft-resource-cause.sh ft-resource-watch.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
for k in kill renice pkill killall; do printf '#!/bin/sh\necho "%s $*" >> "%s/killed.log"\n' "$k" "$T" > "$S/$k"; done
CALLS="$T/launchctl.calls"; : > "$CALLS"
printf '#!/bin/sh\necho "launchctl $*" >> "%s"\nexit 0\n' "$CALLS" > "$S/launchctl"
chmod 755 "$S"/*
printf 'byz-v65-master-claude#0 100 /dev/ttys003\n' > "$T/tmux.txt"; : > "$T/launchd-empty.txt"
PSF="$T/ps.txt"
psl() { # psl pid ppid tty etime time pcpu comm — 기준판(R1340_BASE=1)이면 옛 칸(time 없음)
  if [ "$BASE" = 1 ]; then printf '%s %s %s %s %s %s\n' "$1" "$2" "$3" "$4" "$6" "$7"; else printf '%s %s %s %s %s %s %s\n' "$@"; fi; }
base_ps() { psl 100 1 ttys003 1-00:00:00 0:01.00 0.0 -zsh; psl 150 100 ttys003 10:00 0:03.00 0.5 /bin/zsh; }
cl3() { local i; for i in 1 2 3; do psl $((700+i)) 1 '??' 30:00 25:00.00 40.0 /usr/local/bin/claude; done; }   # 진짜 폭주 3개(평균 83% · 30분)
c() { env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" FT_RES_LAUNCHD="$T/launchd-empty.txt" PATH="$S:$PATH" bash "${1:-$BIN}/ft-resource-cause.sh" cpu 2>/dev/null; }

# ── CPU 반례 P1~P6 (동결 집합 · 카드 §반례 집합) ──
p1() { { base_ps; psl 601 1 '??' 05:00:00 5:00.00 35.0 /usr/local/bin/claude; psl 602 1 '??' 01:00 0:20.00 35.0 claude; psl 603 1 '??' 01:00 0:20.00 35.0 claude; } > "$PSF"; }
p2() { { base_ps; cl3; } > "$PSF"; }
p3() { { base_ps; psl 801 1 '??' 04:00 3:36.00 90.0 /usr/bin/python3; psl 802 1 '??' 30:00 27:00.00 90.0 /usr/bin/python3; psl 803 1 '??' 30:00 27:00.00 90.0 /usr/bin/python3; } > "$PSF"; }
p4() { { base_ps; local i; for i in 1 2 3; do psl $((900+i)) 1 '??' 10:00 6:00.00 60.0 /usr/local/bin/claude; done; psl 904 1 '??' 05:00:00 9:00.00 35.0 /usr/local/bin/claude; } > "$PSF"; }
p5() { { base_ps; cl3; printf '%s\n' '710 1 ?? 30:00 - 50.0 /usr/local/bin/claude'; } > "$PSF"; }
E1=""; E2="cpu claude×3 CPU 120% 30분 · 주인 미상"; E3=""; E4="cpu claude×3 CPU 180% 10분 · 주인 미상"
E5="cpu claude×3 CPU 120% 30분 · 주인 미상; cpu? time 칸 판정 불가 1줄"
p1; out="$(c)"; rc=$?; eq "$rc|$out" "0|$E1" "P1 claude×3 순간 35% · 나이 300·1·1분 · 누적 5분·20초·20초 → 경보 0"
p2; eq "$(c)" "$E2" "P2 claude×3 평균 83% · 30분 → 경보 1줄 «30분»"
p3; eq "$(c)" "$E3" "P3 python 3 중 1개 4분 → 멤버 2 · 경보 0"
p4; eq "$(c)" "$E4" "P4 폭주 3(평균 60% · 10분) + 일상 1(평균 3% · 300분 · 순간 35%) → «claude×3 … 10분»"
if [ "$BASE" = 1 ]; then ok "P5 기준판 건너뜀(옛 칸에 time 없음)"; else p5; eq "$(c)" "$E5" "P5 time «-» 1줄 + 폭주 3 → 경보 + 판정 불가 1줄"; fi
{ base_ps; } > "$PSF"; : > "$CALLS"
out="$(env FT_RES_ROOT="$R" FT_RES_PS="$PSF" FT_RES_TMUX="$T/tmux.txt" PATH="$S:$PATH" bash "$BIN/ft-resource-cause.sh" cpu 2>&1)"; rc=$?
eq "$rc|$out" "0|" "P6 폭주 0 → 출력 0 rc0"
eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "P6 launchctl 호출 0"

# ── CPU 변이 3 (사본 cause.sh 를 고쳐 그 칸만 FAIL 인지) ──
mut() { # mut <이름> <파이썬 치환 old> <new> [old2 new2] — $T/<이름>/ft-resource-cause.sh 사본
  local d="$T/$1"; shift; mkdir -p "$d"; cp "$BIN/ft-resource-cause.sh" "$d/"
  python3 - "$d/ft-resource-cause.sh" "$@" <<'PY'
import sys
p=sys.argv[1]; a=sys.argv[2:]; s=open(p,encoding='utf-8').read()
for o,n in zip(a[0::2],a[1::2]):
    if s.count(o)!=1: sys.exit("MUT-MISS "+o)
    s=s.replace(o,n)
open(p,'w',encoding='utf-8').write(s)
PY
}
if [ "$BASE" = 1 ]; then ok "변이 기준판 건너뜀"; else
  mut m1 'if (e>=300 && t*100>=30*e)' 'if (u+0>=30)' && ok "변이 1 적용(멤버 = 순간 pcpu)" || bad "변이 1 적용 실패"
  p1; o="$(c "$T/m1")"; [ "$o" != "$E1" ] && ok "변이 1 → P1 FAIL «${o}»" || bad "변이 1 이 P1 을 못 가름"
  mut m2 'if (e>=300 && t*100>=30*e)' 'if (t*100>=30*e)' && ok "변이 2 적용(멤버마다 5분 제거)" || bad "변이 2 적용 실패"
  p3; o="$(c "$T/m2")"; [ "$o" != "$E3" ] && ok "변이 2 → P3 FAIL «${o}»" || bad "변이 2 가 P3 을 못 가름"
  mut m3 'if (e>=300 && t*100>=30*e)' 'if (u+0>=30 && e>old[c]) old[c]=e; if (e>=300 && t*100>=30*e)' 'young[c]/60, ow' 'old[c]/60, ow' \
    && ok "변이 3 적용(분 = 가장 오래된 나이)" || bad "변이 3 적용 실패"
  p4; o="$(c "$T/m3")"; [ "$o" != "$E4" ] && ok "변이 3 → P4 FAIL «${o}»" || bad "변이 3 이 P4 를 못 가름"
fi

# ── 보탬 D1~D4: disk 칸 임시 사본 ──
TSV="$ST/disk-attrib.tsv"; CACHE="$ST/du-cache.tsv"; DUCFG="$T/du.cfg"; DULOG="$T/du.log"; : > "$DUCFG"; : > "$DULOG"
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = 6000.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo 1;;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: 50%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 104857600 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\nexit 1\n' > "$S/pgrep"; printf '#!/bin/sh\nexit 0\n' > "$S/osascript"; printf '#!/bin/sh\nexit 0\n' > "$T/noop.sh"
cat > "$S/du" <<EOF
#!/bin/bash
p="\${@: -1}"; echo "\$p" >> "$DULOG"
kb="\$(awk -F'\t' -v p="\$p" '\$1==p{l=\$2} END{print l}' "$DUCFG")"; [ -n "\$kb" ] || kb=1
printf '%s\t%s\n' "\$kb" "\$p"
EOF
chmod 755 "$S"/* "$T/noop.sh"
p6ps="$T/ps-calm.txt"; base_ps > "$p6ps"; printf 'u 1 /sbin/launchd\n' > "$T/procps.txt"
snap() { # snap <bin 폴더> [env…] — 스냅샷 강제 tick 1회
  local b="$1"; shift
  env FT_RES_ROOT="$R" PATH="$S:$PATH" HOME="$HM" TMPDIR="$TD" USER=u FT_RES_SNAP_SEC=0 FT_WORKTREES="$WT" FT_RES_DU_CAP_SEC=2 \
    FT_RES_PS="$p6ps" FT_RES_LAUNCHD="$T/launchd-empty.txt" FT_RES_PROC_PS="$T/procps.txt" FT_RES_PROC_USER=u FT_RES_KILL_CMD="$T/noop.sh" \
    FT_RES_SELFLINK_PATH="$T/selflink" FT_PREVENTIVE_SH="$T/noop.sh" FT_MBOX_SH="$T/noop.sh" "$@" bash "$b/ft-resource-watch.sh" tick >/dev/null 2>&1; }
cfg() { printf '%s\t%s\n' "$1" "$2" >> "$DUCFG"; }
last() { awk -F'\t' -v k="$1" '$2==k{v=$3} END{print v}' "$TSV" 2>/dev/null; }
reset() { rm -rf "$TSV" "$CACHE" "$ST/.disk-attrib-last" "$TD/ft-scratch" "$ST/resource-watch.log"; : > "$DULOG"; : > "$DUCFG"; }
ago() { awk -F'\t' -v OFS='\t' '{ $1=$1-3700; print }' "$TSV" > "$TSV.x" && mv "$TSV.x" "$TSV"; }   # 앞 스냅샷을 1시간+ 전으로
cause_disk() { env FT_RES_ROOT="$R" FT_WORKTREES="$WT" TMPDIR="$TD" PATH="$S:$PATH" bash "${1:-$BIN}/ft-resource-cause.sh" disk 2>/dev/null; }
SEAT='byz-v65-nano-big#0'; D1E="scratch:$SEAT +14.0G ← $SEAT"
d1() { # d1 <bin> — 사본 폴더 없음 스냅 → 1시간 전으로 → 좌석 사본 14G 생김 → 스냅 → 원인 줄
  reset; snap "$1"; ago; mkdir -p "$TD/ft-scratch/$SEAT/repo-abc" "$TD/ft-scratch/byz-x-small#0"
  cfg "$TD/ft-scratch/$SEAT" 14680064; cfg "$TD/ft-scratch/byz-x-small#0" 2048; snap "$1"; cause_disk "$1"; }
out="$(d1 "$BIN")"
eq "${out%%;*}" "$D1E" "D1 사본 +14G(60분) → disk 줄 첫 칸 «scratch:<좌석> +14.0G ← <좌석>»"
[ "$BASE" = 1 ] || eq "$(last scratch.total)" "14682112" "D1 scratch.total = 사본 폴더 합(KB)"
# D2 ft-scratch 폴더 없음 → 값 0 행(다른 없는 칸 pytest 와 같은 꼴) · 오류 0 · 원인 줄에 scratch 0
reset; snap "$BIN"
if [ "$BASE" = 1 ]; then ok "D2 기준판 건너뜀"; else
  eq "$(last scratch.total)|$(last scratch.known)" "0|0/0" "D2 폴더 없음 → scratch.total 0 · scratch.known 0/0(pytest 칸과 같은 꼴)"
  eq "$(grep 'ERROR' "$ST/resource-watch.log" 2>/dev/null | grep -i 'scratch')" "" "D2 감시자 로그 scratch ERROR 0(ft-disk-alarm rc=3 = 임시 루트 탓 · 이 칸 무관)"
  eq "$(grep -c 'ft-scratch' "$DULOG")" 0 "D2 없는 폴더 du 0회"
fi
# D3 사본 폴더 30개 > 틱 예산 8 → scratch.known 8/30 · 합 PARTIAL
reset; for i in $(seq -w 1 30); do mkdir -p "$TD/ft-scratch/byz-t-nano-s$i#0"; done
snap "$BIN" FT_RES_WT_PER_TICK=8
if [ "$BASE" = 1 ]; then ok "D3 기준판 건너뜀"; else
  eq "$(last scratch.known)" "8/30" "D3 30개 · 틱 8 → scratch.known 8/30"
  case "$(last scratch.total)" in PARTIAL*) ok "D3 합 = PARTIAL";; *) bad "D3 합 PARTIAL 아님 «$(last scratch.total)»";; esac
fi
# D4 다른 칸 바이트 그대로 — scratch 칸을 뺀 사본(DM1)과 같은 입력 · 시각 칸 제외 대조
norm() { awk -F'\t' -v OFS='\t' '$2 !~ /^scratch/ { $1=""; print }' "$1"; }
dm1="$T/dm1"; dm2="$T/dm2"
if [ "$BASE" = 1 ]; then ok "D4·D 변이 기준판 건너뜀"; else
  cp -R "$BIN" "$dm1"; cp -R "$BIN" "$dm2"
  python3 - "$dm1/ft-resource-watch.sh" "$dm2/ft-resource-cause.sh" <<'PY' && ok "D 변이 2개 적용" || bad "D 변이 적용 실패"
import sys
w,c=sys.argv[1],sys.argv[2]
s=open(w,encoding='utf-8').read(); o='"scratch.total|scratch.known|scratch|${TMPDIR:-/tmp}/ft-scratch" '
assert s.count(o)==1; open(w,'w',encoding='utf-8').write(s.replace(o,''))
s=open(c,encoding='utf-8').read(); o='      scratch.total)   # r1340'
assert s.count(o)==1; open(c,'w',encoding='utf-8').write(s.replace(o,'      scratch.total.off)   # r1340'))
PY
  mk4() { reset; mkdir -p "$WT/w1" "$WT/w2" "$TD/ft-scratch/byz-a#0"; cfg "$WT/w1" 100; cfg "$WT/w2" 300; cfg "$TD/ft-scratch/byz-a#0" 500; }
  mk4; snap "$BIN"; norm "$TSV" > "$T/d4.new"; awk -F'\t' -v OFS='\t' '$2 !~ /^scratch/ { $1=""; print }' "$CACHE" > "$T/d4c.new"
  mk4; snap "$dm1"; norm "$TSV" > "$T/d4.old"; awk -F'\t' -v OFS='\t' '$2 !~ /^scratch/ { $1=""; print }' "$CACHE" > "$T/d4c.old"
  cmp -s "$T/d4.new" "$T/d4.old" && ok "D4 disk-attrib 다른 칸(/private/tmp·worktrees 등) 바이트 같음($(wc -l < "$T/d4.new" | tr -d ' ')줄)" || bad "D4 다른 칸 바뀜: $(diff "$T/d4.old" "$T/d4.new" | head -3)"
  cmp -s "$T/d4c.new" "$T/d4c.old" && ok "D4 du-cache 다른 칸 바이트 같음" || bad "D4 du-cache 다른 칸 바뀜"
  o="$(d1 "$dm1")"; [ "${o%%;*}" != "$D1E" ] && ok "D 변이 1(목록에서 scratch 뺌) → D1 FAIL «${o}»" || bad "D 변이 1 을 D1 이 못 가름"
  o="$(d1 "$dm2")"; [ "${o%%;*}" != "$D1E" ] && ok "D 변이 2(주인 갈래 끔) → D1 FAIL «${o}»" || bad "D 변이 2 를 D1 이 못 가름"
fi
[ ! -s "$T/killed.log" ] && ok "종료 계열 호출 0" || bad "종료 계열 호출됨: $(cat "$T/killed.log")"

echo "---- fail=$fail · $((SECONDS-T0))초"
[ "$fail" -eq 0 ]
