#!/usr/bin/env bash
# test_resource_freeze_exempt.sh — 동결 표식·자원 넘김의 «멈추지 않는» 처리(r921).
#   ★r921(오빠 2026-10-25 «컴퓨터가 죽어버려도 개발은 해야지 멈춰 있으면 머할건데»)★
#   · 문지기 갈래 = OK / WARN(넘음·못 잼·동결 → exit 0 진행) / REJECT(디스크 하드 하한·디스크 측정 실패만 exit 3)
#   · 동결 파일(.fable-team/state/RESOURCE_FREEZE)은 «알림용» 표식으로 강등 — 승계·리서치·일반 모두 WARN 통과
#   · 리서치 나노 1석 상한 삭제 — 잠금만 남는다(동시 개설이 같은 자리를 두 번 쓰지 않는다)
#   · 감시자(ft-resource-watch.sh)의 동결 판정은 그대로 — 이 파일이 «문지기와 감시자가 같은 문턱» 을 계속 고정한다(ⓕ)
# 가짜 센서(PATH 앞)·임시 FT_RES_ROOT 만 쓴다 — 실 동결 파일·실 tmux·실 spawn 0. 값은 FAKE_* env 로 준다.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
export FT_RECLAIM_PREVENT_SEC=0   # 선제 회수 호출 0 — 이 시험은 문지기·감시자·spawn 문만 본다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/../.." && pwd)"; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 — 있음: «${2}» ← ${1:0:300}";; *) ok "$3";; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
S="$T/stub"; R="$T/R"; ST="$R/.fable-team/state"; mkdir -p "$S" "$ST" "$T/home" "$T/cwd" "$T/root/.fable-team/comm" "$T/root/.fable-team/state" "$T/root/design"
. "$HERE/lib/fake_resource_env.sh"; fake_comm_root "$T/root" || { echo "FAIL fake_comm_root"; exit 1; }
FREEZE="$ST/RESOURCE_FREEZE"; PTSV="$ST/pressure.tsv"; WLOG="$ST/resource-watch.log"
printf '#!/bin/sh\ncase "$2" in\n  vm.swapusage) echo "total = 14336.00M  used = ${FAKE_SWAP}.00M  free = 1000.00M  (encrypted)";;\n  kern.memorystatus_vm_pressure_level) echo "$FAKE_LEVEL";;\n  *) exit 1;;\nesac\n' > "$S/sysctl"
printf '#!/bin/sh\necho "System-wide memory free percentage: ${FAKE_MEMFREE}%%"\n' > "$S/memory_pressure"
printf '#!/bin/sh\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Swapouts:                          2303978."\n' > "$S/vm_stat"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted"\necho "/dev/x 999999999 1 ${FAKE_DISK_KIB:-104857600} 1%% /System/Volumes/Data"\n' > "$S/df"
printf '#!/bin/sh\ncase "$*" in\n  "-a -x claude") seq 101 135; exit 0;;\n  "-a -x codex") exit 1;;\nesac\nexec /usr/bin/pgrep "$@"\n' > "$S/pgrep"
printf '#!/bin/sh\nexit 0\n' > "$S/osascript"
# tmux 대역 — list-sessions 만 진짜로 흉내낸다(rc = TMUX_RC 기본 0 · 세션 이름 = TMUX_SESSIONS 공백 구분). 그 밖 명령은 rc 1.
cat > "$S/tmux" <<'TM'
#!/bin/sh
case "$1" in
  list-sessions) rc="${TMUX_RC:-0}"; if [ "$rc" != 0 ]; then [ -z "${TMUX_STDERR:-}" ] || echo "$TMUX_STDERR" >&2; exit "$rc"; fi; if [ -n "${TMUX_SESSIONS_FILE:-}" ]; then cat "$TMUX_SESSIONS_FILE"; else [ -z "${TMUX_SESSIONS:-}" ] || printf '%s\n' "${TMUX_SESSIONS}" | tr ' ' '\n'; fi; exit 0;;
  has-session) exit "${TMUX_HAS_RC:-1}";;
  *) exit 1;;
esac
TM
chmod 755 "$S"/*
# 표본 2줄(증가 0 · 180초 안) — 문지기 rate 축을 «na» 로 만들지 않는다
sens() { FAKE_SWAP="$1"; FAKE_MEMFREE="$2"; FAKE_LEVEL="$3"; export FAKE_SWAP FAKE_MEMFREE FAKE_LEVEL; }
seed() { local now; now="$(date +%s)"; printf '%s\t%s\t%s\t%s\t2303978\n%s\t%s\t%s\t%s\t2303978\n' "$((now-60))" "$1" "$2" "$3" "$now" "$1" "$2" "$3" > "$PTSV"; sens "$1" "$2" "$3"; }
frz() { echo "시험 동결" > "$FREEZE"; }
rmfrz() { rm -f "$FREEZE"; }
# g <check|check --succession|check --research|status> [env…] — OUT·RC
g() { local args="$1"; shift; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" "$@" bash "$BIN/ft-resource-gate.sh" $args 2>&1)"; RC=$?; }
# tick [env…] — 감시자 1회
tick() { env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" "$@" bash "$BIN/ft-resource-watch.sh" tick >/dev/null 2>&1; }
cnt() { grep -c "$1" "$WLOG" 2>/dev/null || true; }
hasline() { printf '%s\n' "$1" | grep -q -- "$2"; }
# spawn <도구> [env…] -- <인자…> — spawn 문(부작용 «전») 출력·rc
spawnrun() { local tool="$1"; shift; local envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
  OUT="$(cd "$T/root" && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY \
    HOME="$T/home" PATH="$S:$T/stub:$PATH" FT_ROOT="$T/root" FT_TEAMSET=0 FT_RES_ROOT="$R" FT_RECLAIM=0 \
    FT_DISK_MIN_GIB=0 FT_DISK_HARD_MIN_MIB=0 FT_SWAP_HARD_MIB=999999999 FT_PRESSURE_MAX=99 FT_SWAP_RATE_MAX=999999999 FT_MEM_FREE_MIN_PCT=0 FT_AGENT_MAX=999999 \
    ${envs[@]+"${envs[@]}"} bash "$BIN/$tool" "$@" 2>&1)"; RC=$?; }

[ -x "$BIN/ft-resource-gate.sh" ] && [ -x "$BIN/ft-resource-watch.sh" ] || { echo "FAIL 설치본 없음"; exit 1; }

# ── ⓐ swap 13000 · level 2 · memfree 66 → 문지기 통과 · 감시자 동결 0 (r672 판정식 유지) ──
rmfrz; rm -f "$WLOG"; seed 13000 66 2
g check
{ [ "$RC" = 0 ] && hasline "$OUT" '^OK '; } && ok "ⓐ 문지기 swap13000·level2·memfree66 → 통과(OK 줄 있음)" || bad "ⓐ 문지기 rc=$RC $OUT"
tick
eq "$(cnt 'FREEZE created')" 0 "ⓐ 감시자 FREEZE created 0"
[ ! -f "$FREEZE" ] && ok "ⓐ 동결 파일 없음" || bad "ⓐ 동결 파일이 생김"

# ── ⓑ swap 13000 · level 2 · memfree 20 → r921: 문지기 WARN + 진행(감시자는 동결 = 위험 축 유지) ──
rmfrz; rm -f "$WLOG"; seed 13000 20 2
g check
{ [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource swap=13000MiB level=2 memfree=20% limit=12288MiB@level>=2&memfree<30$'; } && ok "ⓑ 문지기 swap 넘김 = WARN 1줄 + 진행 — 사유 줄 전문 일치" || bad "ⓑ 문지기 rc=$RC $OUT"
tick
eq "$(cnt 'FREEZE created')" 1 "ⓑ 감시자 FREEZE created 1"
has "$(cat "$FREEZE" 2>/dev/null)" "swap=13000M level=2" "ⓑ 동결 사유에 swap·level"

# ── ⓒ 동결 파일 있음 → r921: 세 갈래 모두 WARN + 진행(동결은 «알림용» 으로 강등) ──
rm -f "$WLOG"; frz; seed 9000 66 1
g check
{ [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource freeze=시험 동결 limit=0$' && ! hasline "$OUT" '^REJECT'; } && ok "ⓒ 일반 check → WARN freeze + 진행(REJECT 아님)" || bad "ⓒ 일반 check rc=$RC $OUT"
g "check --succession"
{ [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource freeze=시험 동결 limit=0$'; } && ok "ⓒ --succession → WARN freeze + 진행" || bad "ⓒ --succession rc=$RC $OUT"
g "check --research"
{ [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource freeze=시험 동결 limit=0$'; } && ok "ⓒ --research → WARN freeze + 진행" || bad "ⓒ --research rc=$RC $OUT"
# spawn 도 같이 — 동결 중에도 문지기가 세우지 않는다(다음 검사까지 간다)
spawnrun ft-nano-spawn.sh -- "$T/card.md"
{ hasline "$OUT" 'WARN resource freeze=시험 동결 limit=0' && ! hasline "$OUT" 'REJECT resource'; } && ok "ⓒ 동결 중 일반 spawn → WARN 남기고 다음 검사로 진행" || bad "ⓒ 동결 spawn rc=$RC $OUT"
rmfrz

# ── ⓓ 리서치 = 일반 나노와 같은 규칙(r921 상한 삭제) · 잠금만 남는다 ──
spawnrun ft-nano-spawn.sh TMUX_SESSIONS="ft-v65-temp-old-research#0" -- "$T/card.md" --research
hasnt "$OUT" "REJECT 리서치" "ⓓ 리서치 1석 살아 있어도 상한 거절 없음(r921)"
has "$OUT" "REJECT 인덱스 없음" "ⓓ 리서치가 다음 검사(인덱스)까지 감 = 문지기·상한이 세우지 않음"
OUT="$( ( set -uo pipefail; TMUX_RC=2 PATH="$S:$PATH"; export TMUX_RC PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_cap_check "$T/lockcount.d" 2>&1; echo "rc=$?"; ft_research_unlock "$T/lockcount.d" ) 2>&1)"
hasnt "$OUT" "REJECT" "ⓓH1 tmux 조회 실패도 이제 REJECT 아님"
{ hasline "$OUT" 'WARN research 리서치 좌석 수 조회 실패' && hasline "$OUT" 'rc=0'; } && ok "ⓓH1 조회 실패 = WARN 1줄 + 진행(못 세면 멈출 근거도 없다)" || bad "ⓓH1 조회 실패 «${OUT}»"
spawnrun ft-nano-spawn.sh TMUX_SESSIONS="ft-v65-temp-old-research#0" FT_RESEARCH_SEAT_MAX=5 -- "$T/card.md" --research
hasnt "$OUT" "REJECT 리서치 나노 상한" "ⓓH1 FT_RESEARCH_SEAT_MAX 주입해도 상한 거절 없음"
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions.txt" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH; : > "$T/sessions.txt"
  . "$BIN/ft-research-seat-lib.sh"
  ft_research_cap_check "$T/lockenv.d" 2>&1; echo "rc=$?"; ft_research_unlock "$T/lockenv.d" ) 2>&1)"
{ hasline "$OUT" 'WARN research FT_RESEARCH_SEAT_MAX'; hasline "$OUT" 'rc=0'; } && ok "ⓓH2 상한 env 주입 = WARN(무시) + rc0 통과" || bad "ⓓH2 상한 env 처리 «${OUT}»"
# 동시 두 spawn — 잠금으로 직렬화되지만 상한이 없으니 «둘 다» 열린다(r921)
LIB="$BIN/ft-research-seat-lib.sh"
[ -f "$LIB" ] && ok "ⓓH1 ft-research-seat-lib.sh 있음(잠금·셈 한 곳)" || bad "ⓓH1 ft-research-seat-lib.sh 없음"
SESS="$T/sessions.txt"; : > "$SESS"; LK="$T/lock.d"
race_one() { # race_one <이름> — 잠그고(조회) «개설»(파일에 세션 추가) 뒤 해제
  ( set -uo pipefail; TMUX_SESSIONS_FILE="$SESS" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH
    . "$LIB"
    out="$(ft_research_cap_check "$LK" 2>&1)" || { echo "$out"; exit 0; }
    sleep 0.3; printf '%s\n' "ft-v65-temp-$1-research#0" >> "$SESS"; ft_research_unlock "$LK"; echo "OPENED $1" )
}
( race_one A > "$T/raceA" 2>&1 ) & sleep 0.1; race_one B > "$T/raceB" 2>&1; wait
{ grep -q 'OPENED A' "$T/raceA" && grep -q 'OPENED B' "$T/raceB"; } && ok "ⓓH1 동시 두 리서치 → 둘 다 개설(상한 없음 · 잠금은 순서만 정한다)" || bad "ⓓH1 동시 결과 A=«$(cat "$T/raceA")» B=«$(cat "$T/raceB")»"
[ -e "$LK" ] && bad "ⓓH1 잠금이 남음: $LK" || ok "ⓓH1 잠금 해제됨(자국 0)"
# 셈 갈래 — tmux rc1 의 «오류» 만 셈 실패(rc2) · «no server running» 은 0석
OUT="$( ( set -uo pipefail; TMUX_RC=1 TMUX_STDERR="error connecting to /x (Permission denied)" PATH="$S:$PATH"; export TMUX_RC TMUX_STDERR PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_live_count; echo " rc=$?" ) 2>&1)"
{ hasline "$OUT" 'rc=2'; } && ok "ⓓH1' tmux rc1 + «error connecting» → 셈 실패(rc2)" || bad "ⓓH1' rc1 오류 갈래가 0석으로 통과 «${OUT}»"
OUT="$( ( set -uo pipefail; TMUX_RC=1 TMUX_STDERR="no server running on /private/tmp/tmux-501/default" PATH="$S:$PATH"; export TMUX_RC TMUX_STDERR PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_live_count; echo " rc=$?" ) 2>&1)"
{ hasline "$OUT" '0 rc=0'; } && ok "ⓓH1' tmux rc1 + «no server running» → 0석(정상)" || bad "ⓓH1' 서버 없음이 0석이 아님 «${OUT}»"
# 잠금 — pid 가 «비어 있으면» 만드는 중이다 · 폴더가 10초 넘게 묵었을 때만 회수 · 죽은 pid 는 회수
LK3="$T/lock3.d"; rm -rf "$LK3"; mkdir -p "$LK3"; : > "$LK3/pid"
( sleep 0.6; rm -rf "$LK3" ) &
_t0=$SECONDS
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions2.txt" PATH="$S:$PATH"; export PATH TMUX_SESSIONS_FILE PATH; : > "$T/sessions2.txt"
  . "$BIN/ft-research-seat-lib.sh"; ft_research_cap_check "$LK3" 2>&1 && { echo OK; ft_research_unlock "$LK3"; } ) 2>&1)"
_dt=$((SECONDS - _t0)); wait
{ hasline "$OUT" 'OK' && [ "$_dt" -ge 0 ]; } && ok "ⓓH1'' 빈 pid = 만드는 중 → 지우지 않고 기다려 통과(경과 ${_dt}s)" || bad "ⓓH1'' 빈 pid 처리 «${OUT}»"
[ -e "$LK3" ] && bad "ⓓH1'' 잠금이 남음" || ok "ⓓH1'' 통과 뒤 잠금 해제"
LK3="$T/lock3.d"; rm -rf "$LK3"; mkdir -p "$LK3"; : > "$LK3/pid"; touch -t 202001010000 "$LK3"
OUT="$( ( set -uo pipefail; TMUX_SESSIONS_FILE="$T/sessions2.txt" PATH="$S:$PATH"; export PATH TMUX_SESSIONS_FILE PATH
  . "$BIN/ft-research-seat-lib.sh"; ft_research_cap_check "$LK3" 2>&1 && { echo OK; ft_research_unlock "$LK3"; } ) 2>&1)"
{ hasline "$OUT" 'OK'; } && ok "ⓓH1'' 묵은 빈 pid(10초 초과) → 회수하고 통과" || bad "ⓓH1'' 묵은 빈 pid «${OUT}»"
rm -rf "$LK3"
mkdir -p "$LK"; echo 999999 > "$LK/pid"
( . "$LIB"; TMUX_SESSIONS_FILE="$SESS" PATH="$S:$PATH"; export TMUX_SESSIONS_FILE PATH
  : > "$SESS"; out="$(ft_research_cap_check "$LK" 2>&1)" && { echo OK; ft_research_unlock "$LK"; } || echo "REJECT $out" ) > "$T/raceC" 2>&1
grep -q '^OK$' "$T/raceC" && ok "ⓓH1 죽은 pid 잠금 → 회수되고 통과" || bad "ⓓH1 굳은 잠금 회수 실패 «$(cat "$T/raceC")»"
rm -rf "$LK"

# ── ⓔ 진짜 못 쓰는 것 = 디스크 하드 하한만 (r921 · 동결 상태에서도) ──
frz; seed 9000 66 1
g "check --research" FAKE_DISK_KIB=$((500*1024))
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource disk=500MiB limit=1024MiB$'; } && ok "ⓔ 디스크 500MiB(<1024) → REJECT disk(유일한 거절)" || bad "ⓔ 디스크 하드 하한 rc=$RC $OUT"
g "check --succession" FAKE_DISK_KIB=$((500*1024))
{ [ "$RC" = 3 ] && hasline "$OUT" '^REJECT resource disk=500MiB limit=1024MiB$'; } && ok "ⓔ 승계도 디스크 하드 하한은 REJECT" || bad "ⓔ --succession disk rc=$RC $OUT"
# 디스크 «소프트» 문턱(기본 30GiB)은 이제 WARN — 24GiB 는 막지 않는다
g "check --research" FAKE_DISK_KIB=$((24*1048576))
{ [ "$RC" = 0 ] && hasline "$OUT" 'disk=24GiB limit=30GiB' && ! hasline "$OUT" '^REJECT'; } && ok "ⓔ 디스크 24GiB(소프트 문턱) → WARN + 진행" || bad "ⓔ 디스크 소프트 문턱 rc=$RC $OUT"
seed 9000 66 4; g "check --research"
{ [ "$RC" = 0 ] && hasline "$OUT" 'level=4 limit=2'; } && ok "ⓔ level 4 → WARN + 진행" || bad "ⓔ level rc=$RC $OUT"
seed 9000 9 1; g "check --research"
{ [ "$RC" = 0 ] && hasline "$OUT" 'memfree=9% limit=15%'; } && ok "ⓔ memfree 9%(<15) → WARN + 진행" || bad "ⓔ memfree rc=$RC $OUT"
g "check --succession"
{ [ "$RC" = 0 ] && hasline "$OUT" 'memfree=9% limit=10%'; } && ok "ⓔ 승계 memfree 9%(<10) → WARN + 진행" || bad "ⓔ --succession memfree rc=$RC $OUT"
rmfrz

# ── ⓕ 문지기·감시자가 «같은 변수 하나»(FT_SWAP_MEMFREE_MAX)로 움직인다 ──
rmfrz; rm -f "$WLOG"; seed 13000 66 2
g check FT_SWAP_MEMFREE_MAX=100
{ [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource swap=13000MiB level=2 memfree=66%'; } && ok "ⓕ FT_SWAP_MEMFREE_MAX=100 → 문지기 WARN(감시자와 같은 문턱)" || bad "ⓕ 문지기 rc=$RC $OUT"
tick FT_SWAP_MEMFREE_MAX=100
eq "$(cnt 'FREEZE created')" 1 "ⓕ FT_SWAP_MEMFREE_MAX=100 → 감시자 동결(문지기와 같은 문턱)"
rmfrz; rm -f "$WLOG"; seed 13000 66 2
tick FT_RES_SWAP_MEMFREE_MAX=100
eq "$(cnt 'FREEZE created')" 0 "ⓕH2 감시자 전용 변수 무시 — 공통 30 기준 동결 0(문지기와 일치)"
for v in 0 abc -1; do
  rmfrz; rm -f "$WLOG"; seed 13000 66 2
  g check FT_SWAP_MEMFREE_MAX="$v"
  { [ "$RC" = 0 ] && hasline "$OUT" '^WARN resource FT_SWAP_MEMFREE_MAX='; } && ok "ⓕ 문지기 무효값 «${v}» → 기본 30 + WARN" || bad "ⓕ 문지기 무효값 «${v}» rc=$RC $OUT"
  tick FT_SWAP_MEMFREE_MAX="$v"
  { has "$(cat "$WLOG" 2>/dev/null)" "WARN FT_SWAP_MEMFREE_MAX=${v}" "ⓕH2 감시자 무효값 «${v}» 로그 WARN"; [ ! -f "$FREEZE" ]; } && ok "ⓕH2 감시자 무효값 «${v}» 살아서 종료(기본 30 · 동결 0)" || bad "ⓕH2 감시자 무효값 «${v}» 죽었거나 동결됨"
done
rmfrz

# ── ⓗ 변이 대조 — 고침을 되돌리면 이 시험이 «실패»해야 한다 ──
mutant() { local name="$1" f="$2"; shift 2; M="$T/mut-$name"; mkdir -p "$M"; cp "$BIN"/ft-*.sh "$M"/ 2>/dev/null; cp "$BIN"/ft-resource-swap-lib.sh "$M"/ 2>/dev/null
  python3 - "$BIN/$f" "$M/$f" "$@" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
assert old in s, "MUT-OLD 없음"
open(dst, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
# 변이1: 동결 WARN 줄을 지운다 → ⓒ 가 실패해야(동결이 조용해지면 안 된다)
if mutant nofreeze ft-resource-gate.sh '[ "$FREEZE_FLAG" = 1 ] && warn_add "freeze=$(sed -n '"'"'1p'"'"' "$FREEZE" 2>/dev/null) limit=0"' ': freeze warn 삭제됨'; then
  frz; OUT="$(env FT_RES_ROOT="$R" PATH="$S:$PATH" bash "$M/ft-resource-gate.sh" check 2>&1)"; RC=$?; rmfrz
  { [ "$RC" = 0 ] && ! hasline "$OUT" 'WARN resource freeze='; } && ok "ⓗ 변이1(동결 WARN 삭제) 검출" || bad "ⓗ 변이1 검출 실패 rc=$RC $OUT"
else bad "ⓗ 변이1 준비 실패"; fi
# 변이2: 감시자가 전용 변수를 우선(문지기와 어긋남) → ⓕH2 가 실패해야
if mutant watchsplit ft-resource-watch.sh 'SWAP_MEMFREE_MAX="$FT_SWAP_MEMFREE_MAX_VAL"' 'SWAP_MEMFREE_MAX="${FT_RES_SWAP_MEMFREE_MAX:-$FT_SWAP_MEMFREE_MAX_VAL}"'; then
  rmfrz; : > "$WLOG"; seed 13000 66 2
  env FT_RES_ROOT="$R" PATH="$S:$PATH" FT_RES_SNAP_SEC=9999999999 FT_WORKTREES="$T/wt" FT_RES_SWAP_MEMFREE_MAX=100 bash "$M/ft-resource-watch.sh" tick >/dev/null 2>&1
  [ -f "$FREEZE" ] && ok "ⓗ 변이2(감시자 전용 변수 우선 = 문지기와 어긋남) 검출" || bad "ⓗ 변이2 검출 실패(전용 변수 우선인데 동결 0)"
else bad "ⓗ 변이2 준비 실패"; fi
rmfrz
# 변이3: 리서치 상한을 되살린다(1석) → «1석 살아 있어도 통과» 칸이 실패해야
if mutant recap ft-research-seat-lib.sh '  return 0
}' '  [ "${n:-0}" -lt 1 ] || { echo "REJECT 리서치 나노 상한 — 되살아남"; ft_research_unlock "$d"; return 3; }
  return 0
}'; then
  OUT="$( ( set -uo pipefail; TMUX_SESSIONS="ft-v65-temp-old-research#0" PATH="$S:$PATH"; export TMUX_SESSIONS PATH
    . "$M/ft-research-seat-lib.sh"; ft_research_cap_check "$T/lockmut.d" 2>&1; echo "rc=$?"; ft_research_unlock "$T/lockmut.d" ) 2>&1)"
  { hasline "$OUT" 'REJECT 리서치 나노 상한'; } && ok "ⓗ 변이3(리서치 상한 부활) 검출" || bad "ⓗ 변이3 검출 실패 «${OUT}»"
else bad "ⓗ 변이3 준비 실패"; fi

# ── ⓖ 키트 두 사본 일치 (harness/bin = kit) ──
for f in ft-resource-gate.sh ft-resource-watch.sh ft-nano-spawn.sh ft-resource-swap-lib.sh ft-research-seat-lib.sh; do
  cmp -s "$BIN/$f" "$KIT/$f" && ok "ⓖ cmp $f" || bad "ⓖ cmp $f"
done
for f in ft-resource-gate.sh ft-resource-watch.sh ft-nano-spawn.sh ft-resource-swap-lib.sh ft-research-seat-lib.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
[ "$(wc -l < "$BIN/ft-resource-watch.sh" | tr -d ' ')" -le 245 ] && ok "감시자 줄 수 ≤245" || bad "감시자 줄 수 >245"

echo "fail=$fail"; [ $fail -eq 0 ]
